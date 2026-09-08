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

password_auth=no
if [ -n "${DEBUG_PASSWORD:-}" ]; then
  printf 'debug:%s\n' "${DEBUG_PASSWORD}" | chpasswd
  password_auth=yes
fi

if [ -n "${DEBUG_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "${DEBUG_AUTHORIZED_KEYS}" > /home/debug/.ssh/authorized_keys
elif [ -s /authorized_keys ]; then
  cp /authorized_keys /home/debug/.ssh/authorized_keys
elif [ "${password_auth}" != yes ] && [ ! -s /home/debug/.ssh/authorized_keys ]; then
  echo "missing SSH credential: set DEBUG_AUTHORIZED_KEYS, mount /authorized_keys, or set DEBUG_PASSWORD" >&2
  exit 2
fi

if [ -s /home/debug/.ssh/authorized_keys ]; then
  chown debug:debug /home/debug/.ssh/authorized_keys
  chmod 0600 /home/debug/.ssh/authorized_keys
fi

sed -i "s/^#\\?PasswordAuthentication .*/PasswordAuthentication ${password_auth}/" /etc/ssh/sshd_config

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

if [ "${ISTOREOS_AUTO_START:-0}" = "1" ]; then
  /usr/local/bin/istoreos-manager >>/var/log/istoreos-manager.log 2>&1 &
fi

exec /usr/sbin/sshd -D -e -p "${debug_ssh_port}"
