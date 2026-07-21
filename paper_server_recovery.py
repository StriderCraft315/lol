#!/usr/bin/env python3
"""
paper_server_recovery.py
=========================

Forensic reconstruction of deleted Pterodactyl / Paper Minecraft server
instances from a raw PhotoRec carve directory. PhotoRec destroys original
filenames/paths/timestamps, so every decision here is made from file
*content*, not from the recovered filename.

Pipeline
--------
Phase 1 (discovery):
    Walk the source tree. For every small text/extensionless candidate,
    sniff for "server-port=" to discover distinct server instances and
    record which PhotoRec "bucket" (top-level recup_dir.N folder, or
    whatever the first path component is) each port was found in.

Phase 2 (classification + placement):
    Walk every recovered file exactly once, multi-threaded, and route it:
      - server.properties            -> server_<port>/server.properties
      - paper-world-defaults.yml     -> server_<port>/
      - paper-world-configuration.yml-> server_<port>/
      - spigot.yml / bukkit.yml      -> server_<port>/
      - plugin configs (luckperms..) -> server_<port>/plugins/
      - gzip playerdata (.dat.gz)    -> server_<port>/world/playerdata/<uuid>.dat
      - Anvil region fragments       -> server_<port>/world/region/chunk_NNNNN.mca

    Files that cannot be tied to a specific port (because the bucket they
    were carved from contained no server.properties, and no nearby bucket
    did either) are placed under server_UNKNOWN/ rather than being dropped,
    so nothing is silently lost -- you can triage those manually.

Usage
-----
    python3 paper_server_recovery.py \
        --source /root/tmp/recovered_data \
        --dest   /root/rebuilt_servers \
        --workers 32

Everything is copy-only (shutil.copy2). Nothing is deleted or moved from
the PhotoRec dump.
"""

import argparse
import gzip
import os
import re
import shutil
import struct
import sys
import threading
import time
import traceback
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# --------------------------------------------------------------------------
# Constants / tunables
# --------------------------------------------------------------------------

UUID_RE = re.compile(
    rb"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
PORT_RE = re.compile(r"server-port\s*=\s*(\d+)")

MAX_TEXT_SNIFF_SIZE = 2 * 1024 * 1024      # don't try to text-decode huge files
MAX_GZ_READ = 20 * 1024 * 1024             # cap decompressed read (zip-bomb guard)
MAX_NBT_LIST_LEN = 2_000_000               # sanity cap inside the NBT parser
MIN_REGION_FILE_SIZE = 8192                # smallest plausible .mca fragment


# ==========================================================================
# Progress / stats
# ==========================================================================

class Stats:
    def __init__(self):
        self.lock = threading.Lock()
        self.scanned = 0
        self.total = 0
        self.categorized = defaultdict(int)
        self.servers = set()
        self.errors = 0
        self.start = time.time()

    def bump(self, category=None, port=None):
        with self.lock:
            self.scanned += 1
            if category:
                self.categorized[category] += 1
            if port:
                self.servers.add(port)

    def error(self):
        with self.lock:
            self.errors += 1

    def render(self):
        with self.lock:
            elapsed = max(time.time() - self.start, 1e-6)
            rate = self.scanned / elapsed
            pct = (self.scanned / self.total * 100) if self.total else 0.0
            cats = " | ".join(f"{k}:{v}" for k, v in sorted(self.categorized.items()))
            line = (
                f"\r[{self.scanned:>7}/{self.total:<7}] {pct:5.1f}% "
                f"({rate:6.1f} f/s) servers={len(self.servers):<3} "
                f"errors={self.errors:<5} :: {cats}"
            )
            sys.stdout.write(line[:230].ljust(230))
            sys.stdout.flush()

    def final_report(self):
        with self.lock:
            elapsed = time.time() - self.start
            print("\n\n" + "=" * 70)
            print("RECOVERY COMPLETE")
            print("=" * 70)
            print(f"Files scanned : {self.scanned}")
            print(f"Elapsed       : {elapsed:.1f}s")
            print(f"Errors        : {self.errors}")
            print(f"Servers found : {sorted(self.servers)}")
            print("Category breakdown:")
            for k, v in sorted(self.categorized.items(), key=lambda kv: -kv[1]):
                print(f"    {k:<24} {v}")
            print("=" * 70)


stats = Stats()


class CounterBank:
    """Thread-safe monotonically increasing counters, keyed by name."""

    def __init__(self):
        self._lock = threading.Lock()
        self._counts = defaultdict(int)

    def next(self, key):
        with self._lock:
            self._counts[key] += 1
            return self._counts[key]


class ErrorLog:
    def __init__(self, path: Path):
        self.path = path
        self.lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("w") as f:
            f.write(f"Recovery run started {time.ctime()}\n")

    def log(self, file_path, exc):
        with self.lock:
            with self.path.open("a") as f:
                f.write(f"\n--- {file_path} ---\n")
                f.write("".join(traceback.format_exception(type(exc), exc, exc.__traceback__)))


# ==========================================================================
# Minimal, real, big-endian NBT parser (Java Edition)
# Enough to walk TAG_Compound / TAG_List and recover a player UUID.
# ==========================================================================

class NBTParseError(Exception):
    pass


def _read_named_tag_header(buf, offset):
    if offset >= len(buf):
        raise NBTParseError("eof (tag header)")
    tag_type = buf[offset]
    offset += 1
    if tag_type == 0:
        return tag_type, "", offset
    if offset + 2 > len(buf):
        raise NBTParseError("eof (name length)")
    (name_len,) = struct.unpack_from(">H", buf, offset)
    offset += 2
    if offset + name_len > len(buf):
        raise NBTParseError("eof (name)")
    name = buf[offset:offset + name_len].decode("utf-8", errors="replace")
    offset += name_len
    return tag_type, name, offset


def _read_payload(buf, offset, tag_type):
    if tag_type == 1:  # TAG_Byte
        v = struct.unpack_from(">b", buf, offset)[0]
        return v, offset + 1
    if tag_type == 2:  # TAG_Short
        v = struct.unpack_from(">h", buf, offset)[0]
        return v, offset + 2
    if tag_type == 3:  # TAG_Int
        v = struct.unpack_from(">i", buf, offset)[0]
        return v, offset + 4
    if tag_type == 4:  # TAG_Long
        v = struct.unpack_from(">q", buf, offset)[0]
        return v, offset + 8
    if tag_type == 5:  # TAG_Float
        v = struct.unpack_from(">f", buf, offset)[0]
        return v, offset + 4
    if tag_type == 6:  # TAG_Double
        v = struct.unpack_from(">d", buf, offset)[0]
        return v, offset + 8
    if tag_type == 7:  # TAG_Byte_Array
        (length,) = struct.unpack_from(">i", buf, offset)
        offset += 4
        if length < 0 or offset + length > len(buf):
            raise NBTParseError("bad byte array length")
        v = buf[offset:offset + length]
        return v, offset + length
    if tag_type == 8:  # TAG_String
        (length,) = struct.unpack_from(">H", buf, offset)
        offset += 2
        if offset + length > len(buf):
            raise NBTParseError("bad string length")
        v = buf[offset:offset + length].decode("utf-8", errors="replace")
        return v, offset + length
    if tag_type == 9:  # TAG_List
        item_type = buf[offset]
        offset += 1
        (length,) = struct.unpack_from(">i", buf, offset)
        offset += 4
        if length < 0:
            length = 0
        if length > MAX_NBT_LIST_LEN:
            raise NBTParseError("list too long, likely corrupt fragment")
        items = []
        for _ in range(length):
            if item_type == 0:
                break
            val, offset = _read_payload(buf, offset, item_type)
            items.append(val)
        return items, offset
    if tag_type == 10:  # TAG_Compound
        d = {}
        while True:
            t, name, offset = _read_named_tag_header(buf, offset)
            if t == 0:
                break
            val, offset = _read_payload(buf, offset, t)
            d[name] = val
        return d, offset
    if tag_type == 11:  # TAG_Int_Array
        (length,) = struct.unpack_from(">i", buf, offset)
        offset += 4
        if length < 0 or length > MAX_NBT_LIST_LEN or offset + 4 * length > len(buf):
            raise NBTParseError("bad int array")
        v = list(struct.unpack_from(f">{length}i", buf, offset))
        return v, offset + 4 * length
    if tag_type == 12:  # TAG_Long_Array
        (length,) = struct.unpack_from(">i", buf, offset)
        offset += 4
        if length < 0 or length > MAX_NBT_LIST_LEN or offset + 8 * length > len(buf):
            raise NBTParseError("bad long array")
        v = list(struct.unpack_from(f">{length}q", buf, offset))
        return v, offset + 8 * length
    raise NBTParseError(f"unknown tag type {tag_type}")


def parse_nbt(buf: bytes):
    """Parse a full NBT blob (already gzip-decompressed) into a nested
    Python dict/list structure. Raises NBTParseError / struct.error on
    malformed / truncated PhotoRec fragments -- callers must catch."""
    offset = 0
    tag_type, _name, offset = _read_named_tag_header(buf, offset)
    if tag_type == 0:
        return {}
    if tag_type != 10:
        # Not a compound root -- still parse whatever it is, just in case.
        value, _ = _read_payload(buf, offset, tag_type)
        return value
    value, _ = _read_payload(buf, offset, tag_type)
    return value


def _format_uuid_from_int(u: int) -> str:
    h = format(u & ((1 << 128) - 1), "032x")
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def _find_uuid_in_tree(node, depth=0):
    """Recursively search a parsed NBT tree for a UUID, modern or legacy."""
    if depth > 12 or not isinstance(node, (dict, list)):
        return None
    if isinstance(node, dict):
        ints = node.get("UUID")
        if isinstance(ints, list) and len(ints) == 4 and all(isinstance(i, int) for i in ints):
            u = 0
            for i in ints:
                u = (u << 32) | (i & 0xFFFFFFFF)
            return _format_uuid_from_int(u)
        if "UUIDMost" in node and "UUIDLeast" in node:
            most, least = node["UUIDMost"], node["UUIDLeast"]
            if isinstance(most, int) and isinstance(least, int):
                u = ((most & 0xFFFFFFFFFFFFFFFF) << 64) | (least & 0xFFFFFFFFFFFFFFFF)
                return _format_uuid_from_int(u)
        for v in node.values():
            found = _find_uuid_in_tree(v, depth + 1)
            if found:
                return found
    elif isinstance(node, list):
        for v in node:
            found = _find_uuid_in_tree(v, depth + 1)
            if found:
                return found
    return None


def extract_uuid(decompressed: bytes):
    """Try structured NBT extraction first, then fall back to a raw regex
    scan for a literal dashed UUID string (present in some older/plugin
    NBT/YAML-adjacent blobs)."""
    try:
        tree = parse_nbt(decompressed)
        uuid = _find_uuid_in_tree(tree)
        if uuid:
            return uuid
    except Exception:
        pass
    m = UUID_RE.search(decompressed)
    if m:
        return m.group().decode("ascii").lower()
    return None


# ==========================================================================
# Content sniffing helpers
# ==========================================================================

def read_head(path: Path, n: int) -> bytes:
    try:
        with path.open("rb") as f:
            return f.read(n)
    except Exception:
        return b""


def sniff_text(path: Path):
    """Return decoded text if this file plausibly looks like a small text
    config, else None. Deliberately conservative to avoid decoding huge
    binary world files."""
    try:
        size = path.stat().st_size
        if size == 0 or size > MAX_TEXT_SNIFF_SIZE:
            return None
        raw = path.read_bytes()
    except Exception:
        return None

    if b"\x00" in raw[:512]:
        return None  # NUL bytes early on strongly suggest binary data

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        try:
            text = raw.decode("latin-1")
        except Exception:
            return None

    sample = text[:2000]
    if not sample:
        return None
    printable = sum(1 for c in sample if c.isprintable() or c in "\n\r\t")
    if printable / len(sample) < 0.85:
        return None
    return text


def classify_config_text(text: str):
    """Return (kind, port_or_none) based on internal keys, per the spec."""
    if "server-port=" in text:
        m = PORT_RE.search(text)
        port = int(m.group(1)) if m else None
        return "server.properties", port

    if "sub-world-settings:" in text:
        return "paper-world-configuration.yml", None
    if "world-settings:" in text:
        return "paper-world-defaults.yml", None

    if "settings.bungeecord" in text or "settings.restart-on-crash" in text:
        return "spigot.yml", None

    if "allow-end:" in text or "settings.plugin-profiling" in text:
        return "bukkit.yml", None

    lower = text.lower()
    if "luckperms" in lower:
        return "plugins/luckperms_config.yml", None
    if "essentials" in lower and "kits:" in lower:
        return "plugins/essentials_config.yml", None
    if "worldguard" in lower:
        return "plugins/worldguard_config.yml", None
    if "vault" in lower and "economy" in lower:
        return "plugins/vault_config.yml", None

    return None, None


def is_anvil_region(path: Path) -> bool:
    """Heuristic Anvil (.mca) detector: the literal 'Anvil' marker string
    the user specified, OR a structural check (4096-byte sector alignment
    plus a populated chunk location table), since raw Anvil chunk payloads
    do not reliably contain that literal string."""
    try:
        size = path.stat().st_size
        if size < MIN_REGION_FILE_SIZE:
            return False

        with path.open("rb") as f:
            head = f.read(1_048_576)
            if b"Anvil" in head:
                return True
            if size > 1_048_576:
                f.seek(max(0, size - 1_048_576))
                tail = f.read(1_048_576)
                if b"Anvil" in tail:
                    return True

        if size % 4096 == 0:
            loc_table = head[:4096] if len(head) >= 4096 else read_head(path, 4096)
            if len(loc_table) == 4096:
                nonzero_entries = sum(
                    1 for i in range(0, 4096, 4) if loc_table[i:i + 4] != b"\x00\x00\x00\x00"
                )
                if nonzero_entries > 8:
                    return True
        return False
    except Exception:
        return False


# ==========================================================================
# Bucketing: map PhotoRec's recup_dir.N clustering to discovered ports
# ==========================================================================

def get_bucket(path: Path, source_root: Path) -> str:
    try:
        rel = path.relative_to(source_root)
        return rel.parts[0] if len(rel.parts) > 1 else "__root__"
    except ValueError:
        return "__root__"


def bucket_sort_key(bucket: str):
    m = re.search(r"(\d+)", bucket)
    return int(m.group(1)) if m else -1


def build_bucket_port_map(direct_map, window=3):
    """direct_map: bucket -> set(ports). Reduce to bucket -> port (or None
    if ambiguous), then fill gaps from the nearest bucket (by recup_dir
    index) that has an unambiguous port, within `window` buckets."""
    resolved = {}
    for bucket, ports in direct_map.items():
        resolved[bucket] = next(iter(ports)) if len(ports) == 1 else None

    ordered = sorted(resolved.keys(), key=bucket_sort_key)
    filled = dict(resolved)
    for i, bucket in enumerate(ordered):
        if filled[bucket] is not None:
            continue
        for dist in range(1, window + 1):
            for j in (i - dist, i + dist):
                if 0 <= j < len(ordered):
                    candidate = ordered[j]
                    if resolved.get(candidate) is not None:
                        filled[bucket] = resolved[candidate]
                        break
            if filled[bucket] is not None:
                break
    return filled


# ==========================================================================
# Output directory management
# ==========================================================================

_dir_lock = threading.Lock()
_dirs_created = set()


def ensure_server_dirs(dest_root: Path, port_key):
    key = str(port_key)
    if key in _dirs_created:
        return
    with _dir_lock:
        if key in _dirs_created:
            return
        base = dest_root / f"server_{key}"
        (base / "world" / "playerdata").mkdir(parents=True, exist_ok=True)
        (base / "world" / "region").mkdir(parents=True, exist_ok=True)
        (base / "plugins").mkdir(parents=True, exist_ok=True)
        _dirs_created.add(key)


def safe_copy(src: Path, dest: Path, counters: CounterBank):
    dest.parent.mkdir(parents=True, exist_ok=True)
    final = dest
    if final.exists():
        n = counters.next(f"collision::{dest}")
        final = dest.with_name(f"{dest.stem}_{n}{dest.suffix}")
    shutil.copy2(src, final)
    return final


# ==========================================================================
# Phase 1: discover ports
# ==========================================================================

def discover_port_in_file(path: Path):
    text = sniff_text(path)
    if text is None or "server-port=" not in text:
        return None
    m = PORT_RE.search(text)
    return int(m.group(1)) if m else None


def phase1_discover_ports(all_files, source_root: Path, workers: int, window: int):
    print("Phase 1: scanning for server.properties / discovering server instances ...")
    candidates = [
        p for p in all_files
        if p.suffix.lower() in ("", ".txt") and p.stat().st_size <= MAX_TEXT_SNIFF_SIZE
    ]
    direct_map = defaultdict(set)
    scanned = 0
    lock = threading.Lock()

    def worker(path):
        nonlocal scanned
        port = None
        try:
            port = discover_port_in_file(path)
        except Exception:
            port = None
        with lock:
            scanned_local = scanned + 1
            return port, scanned_local

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futures = {ex.submit(discover_port_in_file, p): p for p in candidates}
        done = 0
        for fut in as_completed(futures):
            path = futures[fut]
            done += 1
            if done % 500 == 0 or done == len(futures):
                sys.stdout.write(f"\r  scanned {done}/{len(candidates)} candidates for server-port=")
                sys.stdout.flush()
            try:
                port = fut.result()
            except Exception:
                continue
            if port is not None:
                bucket = get_bucket(path, source_root)
                direct_map[bucket].add(port)

    print()
    all_ports = sorted({p for ports in direct_map.values() for p in ports})
    print(f"Phase 1 complete. Discovered {len(all_ports)} server instance(s): {all_ports}")

    bucket_port_map = build_bucket_port_map(direct_map, window=window)
    return all_ports, bucket_port_map


# ==========================================================================
# Phase 2: classify + place every file
# ==========================================================================

def handle_gz(path: Path, mapped_port, counters: CounterBank, dest_root: Path):
    try:
        with gzip.open(path, "rb") as f:
            data = f.read(MAX_GZ_READ + 1)
    except Exception:
        stats.bump("non_gzip_or_corrupt")
        return
    if not data:
        stats.bump("empty_gzip")
        return

    markers = (b"Inventory", b"UUID", b"Bukkit.player.lastKnownName")
    if not any(m in data for m in markers):
        stats.bump("other_gzip")
        return

    uuid = extract_uuid(data)
    port_key = mapped_port if mapped_port is not None else "UNKNOWN"
    ensure_server_dirs(dest_root, port_key)

    if uuid:
        fname = f"{uuid}.dat"
    else:
        n = counters.next(f"{port_key}:playerdata_fallback")
        fname = f"unknown_player_{n:06d}.dat"

    dest = dest_root / f"server_{port_key}" / "world" / "playerdata" / fname
    safe_copy(path, dest, counters)
    stats.bump("playerdata", port_key)


def handle_config(path: Path, text: str, mapped_port, counters: CounterBank, dest_root: Path):
    kind, found_port = classify_config_text(text)
    if kind is None:
        return False

    if kind == "server.properties":
        if found_port is None:
            stats.bump("server.properties_no_port")
            return True
        ensure_server_dirs(dest_root, found_port)
        dest = dest_root / f"server_{found_port}" / "server.properties"
        safe_copy(path, dest, counters)
        stats.bump("server.properties", found_port)
        return True

    port_key = mapped_port if mapped_port is not None else "UNKNOWN"
    ensure_server_dirs(dest_root, port_key)

    if kind.startswith("plugins/"):
        fname = kind.split("/", 1)[1]
        n = counters.next(f"{port_key}:plugin:{fname}")
        out_name = fname if n == 1 else f"{Path(fname).stem}_{n}{Path(fname).suffix}"
        dest = dest_root / f"server_{port_key}" / "plugins" / out_name
    else:
        n = counters.next(f"{port_key}:{kind}")
        stem, suffix = Path(kind).stem, Path(kind).suffix
        out_name = kind if n == 1 else f"{stem}_{n}{suffix}"
        dest = dest_root / f"server_{port_key}" / out_name

    safe_copy(path, dest, counters)
    stats.bump(kind, port_key)
    return True


def handle_region(path: Path, mapped_port, counters: CounterBank, dest_root: Path):
    port_key = mapped_port if mapped_port is not None else "UNKNOWN"
    ensure_server_dirs(dest_root, port_key)
    n = counters.next(f"{port_key}:region")
    dest = dest_root / f"server_{port_key}" / "world" / "region" / f"chunk_{n:05d}.mca"
    safe_copy(path, dest, counters)
    stats.bump("region.mca", port_key)


def process_file(path: Path, source_root: Path, bucket_port_map, counters: CounterBank,
                  dest_root: Path, error_log: ErrorLog):
    try:
        bucket = get_bucket(path, source_root)
        mapped_port = bucket_port_map.get(bucket)

        ext = path.suffix.lower()
        head2 = read_head(path, 2)

        if ext == ".gz" or head2 == b"\x1f\x8b":
            handle_gz(path, mapped_port, counters, dest_root)
            stats.bump()
            return

        text = sniff_text(path)
        if text is not None:
            if handle_config(path, text, mapped_port, counters, dest_root):
                stats.bump()
                return

        if is_anvil_region(path):
            handle_region(path, mapped_port, counters, dest_root)
            stats.bump()
            return

        stats.bump("unclassified")
    except Exception as e:
        stats.error()
        error_log.log(path, e)
        stats.bump()


def progress_ticker(stop_event):
    while not stop_event.is_set():
        stats.render()
        time.sleep(0.3)
    stats.render()


# ==========================================================================
# main
# ==========================================================================

def main():
    ap = argparse.ArgumentParser(description="Recover Paper/Pterodactyl servers from a PhotoRec dump.")
    ap.add_argument("--source", default="/root/tmp/recovered_data", help="PhotoRec output directory")
    ap.add_argument("--dest", default="/root/rebuilt_servers", help="Where to reconstruct servers")
    ap.add_argument("--workers", type=int, default=min(64, (os.cpu_count() or 4) * 8),
                     help="Thread pool size (I/O bound, safe to over-subscribe)")
    ap.add_argument("--bucket-window", type=int, default=3,
                     help="How many neighboring recup_dir buckets to search for a port when a "
                          "bucket has no server.properties of its own")
    args = ap.parse_args()

    source_root = Path(args.source).resolve()
    dest_root = Path(args.dest).resolve()

    if not source_root.is_dir():
        print(f"ERROR: source directory {source_root} does not exist.", file=sys.stderr)
        sys.exit(1)

    dest_root.mkdir(parents=True, exist_ok=True)
    error_log = ErrorLog(dest_root / "recovery_errors.log")

    print(f"Source : {source_root}")
    print(f"Dest   : {dest_root}")
    print(f"Workers: {args.workers}")
    print("Enumerating recovered files (this can take a while for huge dumps) ...")

    all_files = []
    for root, _dirs, files in os.walk(source_root):
        root_path = Path(root)
        for name in files:
            all_files.append(root_path / name)

    stats.total = len(all_files)
    print(f"Found {stats.total} recovered files on disk.\n")

    if stats.total == 0:
        print("Nothing to do.")
        return

    # ---- Phase 1 ----
    all_ports, bucket_port_map = phase1_discover_ports(
        all_files, source_root, args.workers, args.bucket_window
    )
    for port in all_ports:
        ensure_server_dirs(dest_root, port)
    ensure_server_dirs(dest_root, "UNKNOWN")

    # ---- Phase 2 ----
    print("\nPhase 2: classifying and placing all recovered files ...\n")
    counters = CounterBank()
    stop_event = threading.Event()
    ticker = threading.Thread(target=progress_ticker, args=(stop_event,), daemon=True)
    ticker.start()

    try:
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            futures = [
                ex.submit(process_file, p, source_root, bucket_port_map, counters, dest_root, error_log)
                for p in all_files
            ]
            for fut in as_completed(futures):
                # exceptions are already caught/logged inside process_file;
                # this just surfaces anything truly unexpected.
                exc = fut.exception()
                if exc is not None:
                    stats.error()
    except KeyboardInterrupt:
        print("\nInterrupted by user -- shutting down thread pool, partial results are kept.")
    finally:
        stop_event.set()
        ticker.join(timeout=2)

    stats.final_report()

    manifest_path = dest_root / "recovery_manifest.txt"
    with manifest_path.open("w") as f:
        f.write(f"Recovery run completed {time.ctime()}\n")
        f.write(f"Source: {source_root}\nDest: {dest_root}\n\n")
        f.write(f"Servers discovered: {sorted(stats.servers)}\n\n")
        for k, v in sorted(stats.categorized.items(), key=lambda kv: -kv[1]):
            f.write(f"{k:<28} {v}\n")
    print(f"\nManifest written to {manifest_path}")
    print(f"Error log (if any)  at {error_log.path}")
    print(f"\nReconstructed servers live under: {dest_root}")


if __name__ == "__main__":
    main()
