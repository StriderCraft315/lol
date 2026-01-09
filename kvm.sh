cat /sys/module/kvm_amd/parameters/nested
echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf
modprobe -r kvm_amd && modprobe kvm_amd
