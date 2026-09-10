#!/usr/bin/env bash
set -euo pipefail

container="${ISTOREOS_CONTAINER:-istoreos}"
image="${ISTOREOS_IMAGE:-linkease/istore-in-be96:24.10}"
bridge="${ISTOREOS_BRIDGE:-br-istoreos}"
parent="${ISTOREOS_PARENT-eth0}"
static="${ISTOREOS_STATIC:-}"
gateway="${ISTOREOS_GATEWAY:-}"
dns="${ISTOREOS_DNS:-}"

log() {
  printf '[istoreos-manager] %s\n' "$*"
}

check_ifname() {
  if [ "${#1}" -gt 15 ]; then
    echo "interface name is too long: $1" >&2
    exit 2
  fi
}

ensure_bridge_forwarding() {
  local iptables_bin=""

  for candidate in /host/usr/sbin/iptables /host/sbin/iptables /usr/sbin/iptables /sbin/iptables; do
    if [ -x "${candidate}" ]; then
      iptables_bin="${candidate}"
      break
    fi
  done

  if [ -n "${iptables_bin}" ]; then
    "${iptables_bin}" -C FORWARD -i "${bridge}" -o "${bridge}" -j ACCEPT >/dev/null 2>&1 ||
      "${iptables_bin}" -I FORWARD 1 -i "${bridge}" -o "${bridge}" -j ACCEPT || true
  fi
}

ensure_host_bridge() {
  check_ifname "${bridge}"

  if ! ip link show "${bridge}" >/dev/null 2>&1; then
    ip link add "${bridge}" type bridge
  fi

  ip link set "${bridge}" up

  if [ -n "${parent}" ]; then
    if ! ip link show "${parent}" >/dev/null 2>&1; then
      echo "parent interface not found: ${parent}" >&2
      exit 2
    fi

    current_master=""
    if [ -e "/sys/class/net/${parent}/master" ]; then
      current_master="$(basename "$(readlink "/sys/class/net/${parent}/master")")"
    fi

    if [ -n "${current_master}" ] && [ "${current_master}" != "${bridge}" ]; then
      echo "${parent} is already enslaved to ${current_master}, not ${bridge}" >&2
      exit 2
    fi

    if [ "${current_master}" != "${bridge}" ]; then
      rollback="/host/tmp/istoreos-bridge-rollback-${bridge}.sh"
      mkdir -p /host/tmp
      cat > "${rollback}" <<EOF
#!/usr/bin/env sh
set -eu
ip link set '${parent}' nomaster 2>/dev/null || true
ip link set '${parent}' up 2>/dev/null || true
ip addr flush dev '${bridge}' 2>/dev/null || true
ip link del '${bridge}' 2>/dev/null || true
EOF
      chmod +x "${rollback}"
      log "rollback=${rollback}"

      if ! ip -4 addr show dev "${bridge}" | grep -q ' inet '; then
        while read -r cidr; do
          [ -n "${cidr}" ] && ip addr add "${cidr}" dev "${bridge}" || true
        done < <(ip -4 addr show dev "${parent}" | awk '/ inet / {print $2}')
      fi

      while read -r route; do
        [ -n "${route}" ] || continue
        gateway="$(printf '%s\n' "${route}" | awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}')"
        metric="$(printf '%s\n' "${route}" | awk '{for (i = 1; i <= NF; i++) if ($i == "metric") print $(i + 1)}')"
        if [ -n "${gateway}" ]; then
          if [ -n "${metric}" ]; then
            ip route replace default via "${gateway}" dev "${bridge}" metric "${metric}" || true
          else
            ip route replace default via "${gateway}" dev "${bridge}" || true
          fi
        fi
      done < <(ip route show default dev "${parent}")

      ip addr flush dev "${parent}"
      ip link set "${parent}" master "${bridge}"
      ip link set "${parent}" up
      ip link set "${bridge}" up
    fi
  fi

  ensure_bridge_forwarding
}

write_container_file() {
  local target="$1"
  docker exec -i "${container}" /bin/sh -c "cat > '${target}'"
}

launch_istoreos() {
  docker rm -f "${container}" >/dev/null 2>&1 || true

  docker run -d \
    --name "${container}" \
    --privileged \
    --restart unless-stopped \
    --network none \
    "${image}" \
    /bin/sh -lc 'while [ ! -e /tmp/istoreos-start-init ]; do sleep 1; done; exec /sbin/init' >/dev/null

  pid="$(docker inspect -f '{{.State.Pid}}' "${container}")"
  suffix="$(printf '%s' "${container}" | cksum | awk '{print substr($1,1,6)}')"
  host_if="ve${suffix}h"
  cont_if="ve${suffix}c"

  ip link del "${host_if}" >/dev/null 2>&1 || true
  ip link add "${host_if}" type veth peer name "${cont_if}"
  ip link set "${cont_if}" netns "${pid}"
  nsenter -t "${pid}" -n ip link set "${cont_if}" name eth0
  nsenter -t "${pid}" -n ip link set eth0 up
  ip link set "${host_if}" master "${bridge}"
  ip link set "${host_if}" up

  docker exec "${container}" rm -f /etc/uci-defaults/40_docker_macvlan_network
  docker exec "${container}" mkdir -p /etc/config /etc/uci-defaults

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
    if [ -n "${static}" ]; then
      ipaddr="${static%/*}"
      prefix="${static#*/}"
      [ "${ipaddr}" != "${prefix}" ] || prefix=24
      if [ "${prefix}" != 24 ]; then
        echo "only /24 static addresses are supported" >&2
        exit 2
      fi
      echo "	option proto 'static'"
      echo "	option ipaddr '${ipaddr}'"
      echo "	option netmask '255.255.255.0'"
      [ -z "${gateway}" ] || echo "	option gateway '${gateway}'"
      [ -z "${dns}" ] || echo "	list dns '${dns}'"
    else
      echo "	option proto 'dhcp'"
    fi
    cat <<'EOF'

config interface 'lan6'
	option device 'br-lan'
	option proto 'dhcpv6'
EOF
  } | write_container_file /etc/config/network

  cat <<'EOF' | write_container_file /etc/uci-defaults/41_bridge_mode_dhcp_ignore
#!/bin/sh
uci -q set dhcp.lan.ignore='1'
uci -q commit dhcp
exit 0
EOF

  {
    echo "STATIC='${static}'"
    echo "GATEWAY='${gateway}'"
    echo "DNS='${dns}'"
  } | write_container_file /etc/bridge-mode.conf

  cat <<'EOF' | write_container_file /usr/sbin/bridge-mode-net
#!/bin/sh
set -eu
. /etc/bridge-mode.conf
logger -t bridge-mode-net "configuring br-lan bridge mode"

/etc/init.d/network stop >/dev/null 2>&1 || true
ip link set lo up
ip addr add 127.0.0.1/8 dev lo >/dev/null 2>&1 || true
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

  docker exec "${container}" /bin/sh -c 'chmod +x /etc/uci-defaults/41_bridge_mode_dhcp_ignore /usr/sbin/bridge-mode-net && rm -f /etc/rc.d/S94dockermanager /etc/rc.d/S99dockerd'
  docker exec "${container}" grep -q br-lan /etc/config/network
  docker exec "${container}" touch /tmp/istoreos-start-init

  sleep "${ISTOREOS_POST_START_DELAY:-35}"
  docker exec "${container}" /usr/sbin/bridge-mode-net

  log "container=${container}"
  log "image=${image}"
  log "bridge=${bridge}"
  log "host_if=${host_if}"
}

ensure_host_bridge
launch_istoreos
