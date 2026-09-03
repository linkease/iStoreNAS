#!/usr/bin/env bash
set -euo pipefail

ssh-keygen -A

debug_ssh_port="${DEBUG_SSH_PORT:-2223}"
case "${debug_ssh_port}" in
  ''|*[!0-9]*)
    echo "invalid DEBUG_SSH_PORT=${debug_ssh_port}" >&2
    exit 2
    ;;
esac

if [ -n "${DEBUG_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "${DEBUG_AUTHORIZED_KEYS}" > /home/debug/.ssh/authorized_keys
elif [ -s /authorized_keys ]; then
  cp /authorized_keys /home/debug/.ssh/authorized_keys
elif [ ! -s /home/debug/.ssh/authorized_keys ]; then
  echo "missing SSH public key: set DEBUG_AUTHORIZED_KEYS or mount /authorized_keys" >&2
  exit 2
fi

chown debug:debug /home/debug/.ssh/authorized_keys
chmod 0600 /home/debug/.ssh/authorized_keys

cat >/etc/motd <<'MOTD'
be96-debug

Useful commands:
  sudo nsenter --target 1 --mount --uts --ipc --net --pid /bin/sh
  ls /host
  zcat /proc/config.gz
  cat /host/boot/config-$(uname -r)

This container is intended to run with:
  --privileged --pid=host --ipc=host --uts=host -v /:/host:rw,rslave
MOTD

exec /usr/sbin/sshd -D -e -p "${debug_ssh_port}"
