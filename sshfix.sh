sudo bash -c 'cat <<EOF > /etc/ssh/sshd_config

# SSH LOGIN SETTINGS
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# SFTP SETTINGS

Subsystem sftp /usr/lib/openssh/sftp-server

EOF

systemctl restart ssh 2>/dev/null || service ssh restart

passwd root

'
