#!/usr/bin/env sh
set -eu

container=istoreos
image=linkease/istore24.10-in-be96:latest
bridge=br-istoreos
static=
gateway=
dns=

while [ "$#" -gt 0 ]; do
	case "$1" in
		--container)
			container="$2"; shift 2 ;;
		--image)
			image="$2"; shift 2 ;;
		--bridge)
			bridge="$2"; shift 2 ;;
		--static)
			static="$2"; shift 2 ;;
		--gateway)
			gateway="$2"; shift 2 ;;
		--dns)
			dns="$2"; shift 2 ;;
		*)
			echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

[ "$(id -u)" = 0 ] || {
	echo "run as root" >&2
	exit 1
}

command -v docker >/dev/null
command -v nsenter >/dev/null
command -v ip >/dev/null
ip link show "$bridge" >/dev/null

[ "${#bridge}" -le 15 ] || {
	echo "interface name is too long: $bridge" >&2
	exit 2
}

docker rm -f "$container" >/dev/null 2>&1 || true

docker run -d \
	--name "$container" \
	--privileged \
	--restart unless-stopped \
	--network none \
	"$image" \
	/bin/sh -lc 'while [ ! -e /tmp/istoreos-start-init ]; do sleep 1; done; exec /sbin/init' >/dev/null

pid="$(docker inspect -f '{{.State.Pid}}' "$container")"
suffix="$(printf '%s' "$container" | cksum | awk '{print substr($1,1,6)}')"
host_if="ve${suffix}h"
cont_if="ve${suffix}c"

ip link del "$host_if" >/dev/null 2>&1 || true
ip link add "$host_if" type veth peer name "$cont_if"
ip link set "$cont_if" netns "$pid"
nsenter -t "$pid" -n ip link set "$cont_if" name eth0
nsenter -t "$pid" -n ip link set eth0 up
ip link set "$host_if" master "$bridge"
ip link set "$host_if" up

tmp_network="$(mktemp)"
tmp_uci_default="$(mktemp)"
tmp_init="$(mktemp)"
tmp_sbin="$(mktemp)"
tmp_bridge_conf="$(mktemp)"
trap 'rm -f "$tmp_network" "$tmp_uci_default" "$tmp_init" "$tmp_sbin" "$tmp_bridge_conf"' EXIT

if [ -n "$static" ]; then
	ipaddr="${static%/*}"
	prefix="${static#*/}"
	[ "$ipaddr" != "$prefix" ] || prefix=24
	netmask=255.255.255.0
	[ "$prefix" = 24 ] || {
		echo "only /24 static smoke-test addresses are supported by this launcher" >&2
		exit 2
	}
fi

{
	cat <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'auto'

config device
	option name 'br-lan'
	option type 'bridge'
	option bridge_empty '1'
	list ports 'eth0'

config interface 'lan'
	option device 'br-lan'
EOF
	if [ -n "$static" ]; then
		echo "	option proto 'static'"
		echo "	option ipaddr '$ipaddr'"
		echo "	option netmask '$netmask'"
		[ -z "$gateway" ] || echo "	option gateway '$gateway'"
		[ -z "$dns" ] || echo "	list dns '$dns'"
	else
		echo "	option proto 'dhcp'"
	fi
	cat <<'EOF'

config interface 'lan6'
	option device 'br-lan'
	option proto 'dhcpv6'
EOF
} > "$tmp_network"

cat > "$tmp_uci_default" <<'EOF'
#!/bin/sh
uci -q set dhcp.lan.ignore='1'
uci -q commit dhcp
exit 0
EOF

{
	echo "STATIC='$static'"
	echo "GATEWAY='$gateway'"
	echo "DNS='$dns'"
} > "$tmp_bridge_conf"

cat > "$tmp_sbin" <<'EOF'
#!/bin/sh
set -eu
	. /etc/bridge-mode.conf
	logger -t bridge-mode-net "configuring br-lan bridge mode"

	/etc/init.d/network stop >/dev/null 2>&1 || true
	ip netns del dhns >/dev/null 2>&1 || true
	ip link del br-lan >/dev/null 2>&1 || true
	ip link set eth0 nomaster >/dev/null 2>&1 || true
	ip link set eth0 up
	ip link add br-lan type bridge
	ip link set eth0 master br-lan
	ip link set br-lan up

	if [ -n "$STATIC" ]; then
		ip addr flush dev br-lan
		ip addr add "$STATIC" dev br-lan
		[ -z "$GATEWAY" ] || ip route replace default via "$GATEWAY" dev br-lan
		if [ -n "$DNS" ]; then
			echo "nameserver $DNS" > /tmp/resolv.conf.d/resolv.conf.auto
		fi
	else
		udhcpc -i br-lan -p /var/run/udhcpc-br-lan.pid -b >/dev/null 2>&1 || true
	fi

	logger -t bridge-mode-net "br-lan bridge mode configured"
EOF

cat > "$tmp_init" <<'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=0

boot() {
	start
}

start() {
	/usr/sbin/bridge-mode-net
}
EOF

docker exec "$container" rm -f /etc/uci-defaults/40_docker_macvlan_network
docker exec "$container" mkdir -p /etc/config /etc/uci-defaults
docker exec -i "$container" /bin/sh -c 'cat > /etc/config/network' < "$tmp_network"
docker exec -i "$container" /bin/sh -c 'cat > /etc/uci-defaults/41_bridge_mode_dhcp_ignore' < "$tmp_uci_default"
docker exec "$container" chmod +x /etc/uci-defaults/41_bridge_mode_dhcp_ignore
docker exec "$container" /bin/sh -c 'rm -f /etc/rc.d/S94dockermanager /etc/rc.d/S99dockerd'
docker exec -i "$container" /bin/sh -c 'cat > /etc/bridge-mode.conf' < "$tmp_bridge_conf"
docker exec -i "$container" /bin/sh -c 'cat > /usr/sbin/bridge-mode-net' < "$tmp_sbin"
docker exec -i "$container" /bin/sh -c 'cat > /etc/init.d/bridge-mode-net' < "$tmp_init"
docker exec "$container" /bin/sh -c 'chmod +x /usr/sbin/bridge-mode-net /etc/init.d/bridge-mode-net && ln -s ../init.d/bridge-mode-net /etc/rc.d/S99zbridge-mode-net'
docker exec "$container" grep -q "br-lan" /etc/config/network

docker exec "$container" touch /tmp/istoreos-start-init
sleep 35
docker exec "$container" /usr/sbin/bridge-mode-net
echo "container=$container"
echo "bridge=$bridge"
echo "host_if=$host_if"
