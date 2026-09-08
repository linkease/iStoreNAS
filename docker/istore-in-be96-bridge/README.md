# iStoreOS bridge mode

This mode is for running iStoreOS with the normal OpenWrt LAN shape:

```text
container br-lan <- container eth0 <- veth <- host LAN bridge
```

It is different from the macvlan compose mode. The macvlan mode gives a simple
independent LAN IP, but the container interface is a macvlan endpoint and does
not behave well as an OpenWrt bridge port.

## 1. Prepare a host bridge

For a non-invasive smoke test:

```sh
sudo ./host-bridge-up.sh --bridge br-istest --test-only
```

For a real LAN bridge, prefer an existing host bridge. If the host does not
already have one, migration of the physical parent interface is required and can
disconnect remote management:

```sh
sudo ./host-bridge-up.sh --bridge br-istoreos --parent eth0 --migrate-parent
```

The migration command writes a rollback script before changing links.

## 2. Launch iStoreOS

```sh
sudo ./launch-istoreos-bridge.sh \
  --container istoreos \
  --image linkease/istore-in-be96:24.10 \
  --bridge br-istoreos
```

For the smoke-test bridge:

```sh
sudo ./launch-istoreos-bridge.sh \
  --container istoreos-bridge-test \
  --image linkease/istore-in-be96:24.10 \
  --bridge br-istest \
  --static 10.90.0.2/24 \
  --gateway 10.90.0.1
```

## 3. Verify

```sh
sudo docker exec istoreos ip -4 addr show br-lan
sudo docker exec istoreos ip route
sudo docker exec istoreos ifstatus lan
```

`br-lan` should be the LAN L3 device. `eth0` should be a bridge port.
