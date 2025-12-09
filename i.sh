#!/bin/bash

# XMR Miner Setup Script for Debian 12 - Simplified Version
# Save as: setup-xmr-miner-simple.sh
# chmod +x setup-xmr-miner-simple.sh
# ./setup-xmr-miner-simple.sh

# Configuration
MINER_DIR="$HOME/xmr-miner"
POOL="pool.supportxmr.com:443"

echo "========================================"
echo "XMR Miner Setup for Debian 12"
echo "========================================"

# Update and install dependencies
echo "[*] Installing dependencies..."
apt-get update
apt-get install -y wget curl git build-essential cmake libuv1-dev libssl-dev libhwloc-dev

# Get XMR address
echo ""
echo "Enter your Monero (XMR) wallet address:"
echo "Note: This can be a standard address (starts with 4)"
echo "      or a subaddress (starts with 8)"
read -p "XMR Address: " XMR_ADDRESS

# Get number of threads
CPU_THREADS=$(nproc)
echo ""
echo "Your system has $CPU_THREADS CPU threads."
read -p "How many threads to use for mining? (1-$CPU_THREADS): " THREADS
if [ -z "$THREADS" ] || [ "$THREADS" -lt 1 ] || [ "$THREADS" -gt "$CPU_THREADS" ]; then
    THREADS=$((CPU_THREADS - 1))
    if [ $THREADS -lt 1 ]; then
        THREADS=1
    fi
    echo "[*] Using $THREADS threads"
fi

# Create directory
echo "[*] Setting up miner in $MINER_DIR"
mkdir -p "$MINER_DIR"
cd "$MINER_DIR"

# Download XMRig
echo "[*] Downloading XMRig..."
wget -q https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-x64.tar.gz
tar -xzf xmrig-6.21.0-linux-x64.tar.gz
mv xmrig-6.21.0/* .
rm -rf xmrig-6.21.0 xmrig-6.21.0-linux-x64.tar.gz
chmod +x xmrig

# Create start script
echo "[*] Creating start script..."
cat > start-mining.sh << EOF
#!/bin/bash
cd "$MINER_DIR"
echo "Starting XMRig miner..."
echo "Pool: $POOL"
echo "Address: $XMR_ADDRESS"
echo "Threads: $THREADS"
echo ""
echo "Press Ctrl+C to stop mining"
echo ""
./xmrig -o $POOL -u $XMR_ADDRESS -p x --threads=$THREADS --tls
EOF

chmod +x start-mining.sh

# Create systemd service
echo "[*] Creating systemd service..."
cat > /etc/systemd/system/xmr-miner.service << EOF
[Unit]
Description=XMRig Monero Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$MINER_DIR
ExecStart=$MINER_DIR/xmrig -o $POOL -u $XMR_ADDRESS -p x --threads=$THREADS --tls
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable xmr-miner.service
systemctl start xmr-miner.service

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Miner is now running!"
echo ""
echo "To check status:"
echo "  systemctl status xmr-miner"
echo ""
echo "To view logs:"
echo "  journalctl -u xmr-miner -f"
echo ""
echo "To stop mining:"
echo "  systemctl stop xmr-miner"
echo ""
echo "To start mining again:"
echo "  systemctl start xmr-miner"
echo ""
echo "You can also run manually:"
echo "  cd $MINER_DIR"
echo "  ./start-mining.sh"
echo ""
echo "Your mining info:"
echo "  Address: $XMR_ADDRESS"
echo "  Pool: $POOL"
echo "  Threads: $THREADS"
echo ""
echo "Check your stats on: https://supportxmr.com/#/dashboard/$XMR_ADDRESS"
