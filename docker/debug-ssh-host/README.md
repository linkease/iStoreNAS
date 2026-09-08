# be96-debug

SSH debug toolbox and optional iStoreOS launcher for Docker-only BE96/iStoreOS
hosts.

## Start

```sh
export DEBUG_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"
docker compose up -d
ssh -p 2223 debug@<host-ip>
```

Password login is also supported:

```sh
export DEBUG_PASSWORD='change-this-password'
docker compose up -d
ssh -p 2223 debug@<host-ip>
```

The container uses host network, host pid/ipc/uts namespaces, privileged mode,
mounts the host root at `/host`, and mounts `/var/run/docker.sock`.

Useful checks after login:

```sh
sudo nsenter --target 1 --mount --uts --ipc --net --pid /bin/sh
ls /host
zcat /proc/config.gz
cat /host/boot/config-$(uname -r)
```

## Start iStoreOS too

The same debug container can also act as the iStoreOS manager. It prepares the
host bridge, creates the iStoreOS container, injects a veth pair, and makes
iStoreOS use `br-lan` internally.

```sh
export DEBUG_PASSWORD='change-this-password'
export ISTOREOS_AUTO_START=1
export ISTOREOS_PARENT=eth0
export ISTOREOS_BRIDGE=br-istoreos
export ISTOREOS_IMAGE=linkease/istore-in-be96:24.10
docker compose up -d
```

Do not set `ISTOREOS_STATIC` when `br-lan` should get its LAN address by DHCP.

Verify:

```sh
docker exec istoreos ip -4 addr show br-lan
docker exec istoreos ip route
```

The first bridge migration writes a rollback helper under `/host/tmp/`.
