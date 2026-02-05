    clear
    cat << "EOF"
                           
                           
 _____ _     _           _ 
|     |_|___| |_ ___ ___| |
| | | | |  _|   | .'| -_| |
|_|_|_|_|___|_|_|__,|___|_|
                           
                                                      
                                                                   
EOF

echo "Starting System......."
sleep 2
echo "Checking For Potential Errors"
sleep 2
echo "Starting Docker Enabler......"

sleep 1
echo "System Initializing"

sleep 2

echo "System Initialized !"
sleep 1

echo "System Ready To Configue Docker For Container 'vps-1421860082894766183-1' "

sleep 3

    clear

    cat << "EOF"
 
                                                           
 ____          _              _____         _   _         
|    \ ___ ___| |_ ___ ___   |   __|___ ___| |_| |___ ___ 
|  |  | . |  _| '_| -_|  _|  |   __|   | .'| . | | -_|  _|
|____/|___|___|_,_|___|_|    |_____|_|_|__,|___|_|___|_|  
                                                          
                                                                                                                   
                                                                                                                                            
                                                                   
EOF


echo "Applying Docker Permissions to NoverixCloud-Michael "

sleep 5

lxc config set vps-1421860082894766183-1 security.nesting true
lxc config device add vps-1421860082894766183-1 kvm unix-char path=/dev/kvm
lxc config set vps-1421860082894766183-1 security.nesting true
lxc config set vps-1421860082894766183-1 security.privileged true
lxc config set vps-1421860082894766183-1 security.syscalls.intercept.mknod true
lxc config set vps-1421860082894766183-1 security.syscalls.intercept.setxattr true
lxc config device add vps-1421860082894766183-1 fuse unix-char path=/dev/fuse
lxc config set vps-1421860082894766183-1 linux.kernel_modules overlay,loop,nf_nat,ip_tables,ip6_tables,netlink_diag,br_netfilter
lxc restart vps-1421860082894766183-1


echo "All Done!! "
echo "Enjoy The Power Of Docker "
echo "Made By Michael!!"
