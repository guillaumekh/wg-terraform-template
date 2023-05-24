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

# IPv6 is broken. There might be some good hints there:
# https://im.salty.fish/index.php/archives/linux-networking-shallow-dive.html
write_files:
    - content: |
        [Interface]
        PrivateKey = server_private_key
        Address = 10.0.0.1/24, fe80::f71d:19da:c23a:b56d/64
        ListenPort = 52820
        PostUp = iptables -A FORWARD -i %i -o ens5 -j ACCEPT
        PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o ens5 -j MASQUERADE
        PostUp = ip6tables -A INPUT -i %i -j ACCEPT
        PostUp = ip6tables -A FORWARD -i ens5 -o %i -j ACCEPT
        PostUp = ip6tables -A FORWARD -i %i -o ens5 -j ACCEPT
        PostDown = iptables -D FORWARD -i %i -o ens5 -j ACCEPT
        PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o ens5 -j MASQUERADE
        PostDown = ip6tables -D INPUT -i %i -j ACCEPT
        PostDown = ip6tables -D FORWARD -i ens5 -o %i -j ACCEPT
        PostDown = ip6tables -D FORWARD -i %i -o ens5 -j ACCEPT

        [Peer]
        PublicKey = client_public_key
        AllowedIPs = 10.0.0.2/32, fe80::/64
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
    # Enable IPv6 routing
    - [ sh, -c, 'sysctl -w net.ipv6.conf.all.forwarding=1' ]
    # Start Wireguard
    - [ sh, -c, 'sudo systemctl enable --now wg-quick@wg0' ]
    # Enable Wireguard logs
    - [ sh, -c, 'echo module wireguard +p | tee /sys/kernel/debug/dynamic_debug/control']

final_message: "System provisioning is complete and took $UPTIME seconds"
