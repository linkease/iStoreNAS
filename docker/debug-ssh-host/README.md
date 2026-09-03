# be96-debug

SSH debug toolbox for Docker-only BE96/iStoreNAS hosts.

## Start

```sh
export DEBUG_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"
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
