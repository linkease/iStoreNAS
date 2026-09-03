#!/usr/bin/env bash
set -euo pipefail

target="${1:-rk35xx}"
mode="${2:-${PACK:-}}"

case "${target}" in
  x86_64|rk35xx|rk33xx)
    ;;
  *)
    echo "usage: $0 [x86_64|rk35xx|rk33xx] [Pack]" >&2
    exit 2
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64)
    ;;
  *)
    echo "this ImageBuilder flow requires an x86_64 build host" >&2
    exit 2
    ;;
esac

required_commands="bash make tar xz patch wget sha256sum sed grep cut sort xargs flock"
missing=0
for cmd in ${required_commands}; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "missing command: ${cmd}" >&2
    missing=1
  fi
done
if [ "${missing}" != "0" ]; then
  exit 127
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

mkdir -p dl "ib_${target}" build-logs

if [ -e ib ] && [ ! -L ib ]; then
  echo "refusing to replace existing non-symlink ./ib" >&2
  exit 1
fi
ln -sfn "ib_${target}" ib

export WORK_SOURCE="${script_dir}"
export WORK_TARGET="${target}"

ts="$(date +%Y%m%d-%H%M%S)"
log="${script_dir}/build-logs/runmynas-local-${target}-${mode:-image}-${ts}.log"
status="${script_dir}/build-logs/runmynas-local-${target}-${mode:-image}-${ts}.status"

echo "log=${log}"
echo "status=${status}"

set +e
if [ "${mode}" = "Pack" ] || [ "${mode}" = "1" ]; then
  bash docker/build.sh Pack 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
else
  bash docker/build.sh 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
fi
set -e

echo "${rc}" > "${status}"
echo "exit_code=${rc}"
exit "${rc}"
