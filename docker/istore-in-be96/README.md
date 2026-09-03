# istore-in-be96

iStoreNAS/iStoreOS 22.03 Docker rootfs image for BE96-style Docker-only hosts.

## Start

```sh
docker compose up -d
```

The compose file creates a macvlan network so iStoreNAS can obtain an
independent LAN address by DHCP. Adjust these variables when the LAN differs:

```sh
export ISTOREOS_LAN_PARENT=eth0
export ISTOREOS_LAN_SUBNET=192.168.60.0/24
export ISTOREOS_LAN_GATEWAY=192.168.60.1
```

The image keeps OpenWrt/iStoreOS 22.03 legacy iptables packages and includes
`quickstart`, `luci-app-quickstart`, `luci-i18n-quickstart-zh-cn`, and
`luci-theme-istorenas`.
