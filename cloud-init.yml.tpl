#cloud-config

repo_upgrade: security

manage_etc_hosts: localhost

users:
  - name: guillaume
    gecos: Guillaume
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPNqav8C5nINxC5BISInbpQFEZstHyfV3vrbPCXr+7DO guillaume.kh.alt@gmail.com

disable_root: true

packages:
  - wireguard

write_files:
    - content: |
        [Interface]
        PrivateKey = server_private_key
        Address = 10.0.0.1/24
        ListenPort = 52820
        PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
        PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

        [Peer]
        PublicKey = client_public_key
        AllowedIPs = 10.0.0.2/32
      path: /etc/wireguard/wg0.conf
      owner: root:root
      permissions: '666'

runcmd:
    # Generate server keypair
    - [ sh, -c, 'umask 033; wg genkey | tee /etc/wireguard/server_private_key | wg pubkey > /etc/wireguard/server_public_key' ]
    # Wait for client public key
    - [ sh, -c, 'while [ ! -f /tmp/client_public_key ] ; do echo "Awaiting client public key..."; sleep 5; done' ]
    # Insert keys inside wireguard's conf file
    - [ sh, -c, 'SERVERPRIVATEKEY=$(cat /etc/wireguard/server_private_key); sed -i "s|server_private_key|$SERVERPRIVATEKEY|" /etc/wireguard/wg0.conf']
    - [ sh, -c, 'CLIENTPUBLICKEY=$(cat /tmp/client_public_key); sed -i "s|client_public_key|$CLIENTPUBLICKEY|" /etc/wireguard/wg0.conf']
    # Set permissions on Wireguard files
    - [ sh, -c, 'chmod 600 /etc/wireguard/server_private_key /etc/wireguard/server_public_key' ]
    # Enable IPv4 routing
    - [ sh, -c, 'sysctl -w net.ipv4.ip_forward=1' ]
    # Start Wireguard
    - [ sh, -c, 'sudo systemctl enable --now wg-quick@wg0' ]

final_message: "System provisioning is complete and took $UPTIME seconds"
