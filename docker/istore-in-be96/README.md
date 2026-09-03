# istore-in-be96

iStoreOS Docker rootfs image for BE96-style Docker-only hosts.

## Start

```sh
export ISTOREOS_IMAGE_TAG=22.03
docker compose up -d
```

Use `ISTOREOS_IMAGE_TAG=24.10` to run the 24.10 image.

The compose file creates a macvlan network so iStoreOS can obtain an
independent LAN address by DHCP. Adjust these variables when the LAN differs:

```sh
export ISTOREOS_LAN_PARENT=eth0
export ISTOREOS_LAN_SUBNET=192.168.50.0/24
export ISTOREOS_LAN_GATEWAY=192.168.50.1
```

The 22.03 image keeps OpenWrt/iStoreOS legacy iptables packages and includes
`quickstart`, `luci-app-quickstart`, `luci-i18n-quickstart-zh-cn`, and
`luci-theme-istorenas`. The 24.10 image is built from the 24.10 rk3xxx
ImageBuilder flow.
