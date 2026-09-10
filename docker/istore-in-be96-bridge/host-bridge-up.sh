#!/usr/bin/env sh
set -eu

bridge=br-istoreos
parent=
test_only=0
migrate_parent=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		--bridge)
			bridge="$2"; shift 2 ;;
		--parent)
			parent="$2"; shift 2 ;;
		--test-only)
			test_only=1; shift ;;
		--migrate-parent)
			migrate_parent=1; shift ;;
		*)
			echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

need_root() {
	[ "$(id -u)" = 0 ] || {
		echo "run as root" >&2
		exit 1
	}
}

check_ifname() {
	[ "${#1}" -le 15 ] || {
		echo "interface name is too long: $1" >&2
		echo "Linux interface names must be 15 characters or fewer" >&2
		exit 2
	}
}

ensure_bridge() {
	ip link show "$bridge" >/dev/null 2>&1 || ip link add "$bridge" type bridge
	ip link set "$bridge" up
}

ensure_bridge_forwarding() {
	local iptables_bin=

	for candidate in /usr/sbin/iptables /sbin/iptables; do
		if [ -x "$candidate" ]; then
			iptables_bin="$candidate"
			break
		fi
	done

	if [ -n "$iptables_bin" ]; then
		"$iptables_bin" -C FORWARD -i "$bridge" -o "$bridge" -j ACCEPT >/dev/null 2>&1 ||
			"$iptables_bin" -I FORWARD 1 -i "$bridge" -o "$bridge" -j ACCEPT || true
	fi
}

write_rollback() {
	local path="/tmp/istoreos-bridge-rollback-${bridge}.sh"
	{
		echo "#!/usr/bin/env sh"
		echo "set -eu"
		echo "ip link set '$parent' nomaster 2>/dev/null || true"
		echo "ip link set '$parent' up 2>/dev/null || true"
		echo "ip addr flush dev '$bridge' 2>/dev/null || true"
		echo "ip link del '$bridge' 2>/dev/null || true"
	} > "$path"
	chmod +x "$path"
	echo "rollback=$path"
}

need_root
check_ifname "$bridge"

if [ "$test_only" = 1 ]; then
	ensure_bridge
	ensure_bridge_forwarding
	ip addr show dev "$bridge" | grep -q 'inet ' || ip addr add 10.90.0.1/24 dev "$bridge"
	echo "bridge=$bridge"
	exit 0
fi

[ -n "$parent" ] || {
	echo "--parent is required unless --test-only is used" >&2
	exit 2
}

if [ "$migrate_parent" != 1 ]; then
	echo "refusing to migrate $parent without --migrate-parent" >&2
	exit 2
fi

write_rollback
ensure_bridge

ip addr show dev "$bridge" | grep -q 'inet ' || {
	ip -4 addr show dev "$parent" | awk '/ inet / {print $2}' | while read cidr; do
		ip addr add "$cidr" dev "$bridge"
	done
}

ip route show default dev "$parent" | while read route; do
	gateway="$(printf '%s\n' "$route" | awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}')"
	metric="$(printf '%s\n' "$route" | awk '{for (i = 1; i <= NF; i++) if ($i == "metric") print $(i + 1)}')"
	[ -n "$gateway" ] || continue
	if [ -n "$metric" ]; then
		ip route replace default via "$gateway" dev "$bridge" metric "$metric"
	else
		ip route replace default via "$gateway" dev "$bridge"
	fi
done

ip addr flush dev "$parent"
ip link set "$parent" master "$bridge"
ip link set "$parent" up
ip link set "$bridge" up
ensure_bridge_forwarding

echo "bridge=$bridge"
echo "parent=$parent"
