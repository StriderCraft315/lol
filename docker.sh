    clear
    cat << "EOF"
                           
                           
 _____ _     _           _ 
|     |_|___| |_ ___ ___| |
| | | | |  _|   | .'| -_| |
|_|_|_|_|___|_|_|__,|___|_|
                           
                                                      
                                                                   
EOF

    clear
    cat << "EOF"
 
                                                           
 ____          _              _____         _   _         
|    \ ___ ___| |_ ___ ___   |   __|___ ___| |_| |___ ___ 
|  |  | . |  _| '_| -_|  _|  |   __|   | .'| . | | -_|  _|
|____/|___|___|_,_|___|_|    |_____|_|_|__,|___|_|___|_|  
                                                          
                                                                                                                   
                                                                                                                                            
                                                                   
EOF


echo " Applying Docke Permissions to NoverixCloud-Michael "

lxc config set NoverixCloud-Michael security.nesting true
lxc config device add NoverixCloud-Michael kvm unix-char path=/dev/kvm
lxc config set NoverixCloud-Michael security.nesting true
lxc config set NoverixCloud-Michael security.privileged true
lxc config set NoverixCloud-Michael security.syscalls.intercept.mknod true
lxc config set NoverixCloud-Michael security.syscalls.intercept.setxattr true
lxc config device add NoverixCloud-Michael fuse unix-char path=/dev/fuse
lxc config set NoverixCloud-Michael linux.kernel_modules overlay,loop,nf_nat,ip_tables,ip6_tables,netlink_diag,br_netfilter
lxc restart NoverixCloud-Michael


echo "All Done!! "
echo "Enjoy The Power Of Docker "
