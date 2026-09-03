#!/usr/bin/env bash
set -euo pipefail

target="${1:-rk3xxx}"
mode="${2:-${PACK:-}}"

case "${target}" in
  rk3xxx)
    ;;
  *)
    echo "usage: $0 [rk3xxx] [Pack]" >&2
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

required_commands="bash make tar patch wget sha256sum sed grep cut sort xargs"
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

source "env/${target}.env"

archive="${IB_NAME}.${IB_ARCHIVE_EXT:-tar.xz}"
ib_dir="ib_${target}_2410"
mkdir -p dl "${ib_dir}" build-logs

if [ -e ib ] && [ ! -L ib ]; then
  echo "refusing to replace existing non-symlink ./ib" >&2
  exit 1
fi
ln -sfn "${ib_dir}" ib

export WORK_SOURCE="${script_dir}"
export WORK_TARGET="${target}"

ts="$(date +%Y%m%d-%H%M%S)"
log="${script_dir}/build-logs/runmynas-local-2410-${target}-${mode:-image}-${ts}.log"
status="${script_dir}/build-logs/runmynas-local-2410-${target}-${mode:-image}-${ts}.status"

echo "log=${log}"
echo "status=${status}"

set +e
if [ "${mode}" = "Pack" ] || [ "${mode}" = "1" ]; then
  bash docker/build-2410.sh Pack 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
else
  bash docker/build-2410.sh 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
fi
set -e

echo "${rc}" > "${status}"
echo "exit_code=${rc}"
exit "${rc}"
