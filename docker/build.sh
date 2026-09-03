#!/bin/bash

case ${WORK_TARGET} in
  x86_64)
    ;;
  rk35xx)
    ;;
  rk33xx)
    ;;
  *)
    echo "not supported"
    exit 1
    ;;
esac

source env/${WORK_TARGET}.env

set -e

prepare_ib=0
if [ -n "${IB_TARBALL:-}" ]; then
    [ -f "${IB_TARBALL}" ] || { echo "missing local ImageBuilder tarball: ${IB_TARBALL}" >&2; exit 1; }
    actual_sha="$(sha256sum "${IB_TARBALL}" | cut -d " " -f 1)"
    if [ -n "${IB_TARBALL_SHA256:-}" ] && [ "${actual_sha}" != "${IB_TARBALL_SHA256}" ]; then
        echo "ImageBuilder sha256 mismatch: ${actual_sha} != ${IB_TARBALL_SHA256}" >&2
        exit 1
    fi
    if [ ! -f ib/.source_tarball_sha256 ] || [ "$(cat ib/.source_tarball_sha256 2>/dev/null)" != "${actual_sha}" ]; then
        prepare_ib=1
        if [ -d "${WORK_SOURCE}/ib_${WORK_TARGET}" ] && [ -n "$(ls -A "${WORK_SOURCE}/ib_${WORK_TARGET}" 2>/dev/null)" ]; then
            mv "${WORK_SOURCE}/ib_${WORK_TARGET}" "${WORK_SOURCE}/ib_${WORK_TARGET}.bak-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "${WORK_SOURCE}/ib_${WORK_TARGET}"
            ln -sfn "ib_${WORK_TARGET}" "${WORK_SOURCE}/ib"
        fi
    fi
elif grep -q istore_nas ib/repositories.conf 2>/dev/null; then
    prepare_ib=0
else
    prepare_ib=1
fi

if [ "${prepare_ib}" = "1" ]; then
    if [ -n "${IB_TARBALL:-}" ]; then
        tar -C ib --strip-components=1 -xf "${IB_TARBALL}"
        echo "${actual_sha}" > ib/.source_tarball_sha256
        if [ -n "${IB_MANIFEST:-}" ]; then
            [ -f "${IB_MANIFEST}" ] || { echo "missing local ImageBuilder manifest: ${IB_MANIFEST}" >&2; exit 1; }
            cp "${IB_MANIFEST}" ib/target.manifest
        fi
    else
        if [ ! -f dl/${IB_NAME}.tar.xz ]; then
            wget -O dl/${MF_NAME} ${IB_URL}${MF_NAME}
            wget -O dl/${IB_NAME}.tar.xz ${IB_URL}${IB_NAME}.tar.xz
            wget -O dl/sha256sums ${IB_URL}sha256sums
            [ -s dl/sha256sums ]
            [ -s dl/${MF_NAME} ]
            [ -s dl/${IB_NAME}.tar.xz ]
            grep -Fq ${IB_NAME}.tar.xz dl/sha256sums
            cd dl && sha256sum -c --ignore-missing --status sha256sums
            cd ${WORK_SOURCE}
        fi
        tar -C ib --strip-components=1 -xJf dl/${IB_NAME}.tar.xz
    fi

    cd ${WORK_SOURCE}
    cp -a src/* ib/
    printf '%s\n' 001-all-profiles.patch | xargs -n1 sh -c 'patch -N --batch -p1 -d ib -i ../patches/$0'
    sed -i 's/ unofficial/ oversea/' ib/Makefile
fi
set +e

# Always refresh source-controlled overlay, selected local IPKs, and package manifest.
is_excluded_ipk() {
    local pkg="$1"
    local exclude

    for exclude in ${LOCAL_IPK_EXCLUDE:-}; do
        [ "${pkg}" = "${exclude}" ] && return 0
    done

    return 1
}

refresh_ipks() {
    local ipk_dir ipk pkg

    for ipk_dir in ${WORK_SOURCE}/packages/all ${EXTRA_IPK_DIRS:-}; do
        [ -d "${ipk_dir}" ] || { echo "missing IPK directory: ${ipk_dir}" >&2; exit 1; }
        for ipk in "${ipk_dir}"/*.ipk; do
            [ -e "${ipk}" ] || continue
            pkg="$(basename "${ipk}" | cut -d "_" -f 1)"
            is_excluded_ipk "${pkg}" && continue
            rm -f "${WORK_SOURCE}"/ib/packages/"${pkg}"_*.ipk
            cp "${ipk}" "${WORK_SOURCE}"/ib/packages/
        done
    done
}

refresh_ipks

rm -rf ${WORK_SOURCE}/ib/files
mkdir -p ${WORK_SOURCE}/ib/files
if [ -n "${IB_MANIFEST:-}" ]; then
    [ -f "${IB_MANIFEST}" ] || { echo "missing local ImageBuilder manifest: ${IB_MANIFEST}" >&2; exit 1; }
    cp "${IB_MANIFEST}" ${WORK_SOURCE}/ib/target.manifest
fi
cp -a ${WORK_SOURCE}/files/all/* ${WORK_SOURCE}/ib/files/ 2>/dev/null || true
case ${WORK_TARGET} in
  *x86*)
      cp ${WORK_SOURCE}/src/target_x86_64.manifest ${WORK_SOURCE}/ib/custom.manifest
      cp -a ${WORK_SOURCE}/files/x86_64/* ${WORK_SOURCE}/ib/files/ 2>/dev/null || true
    ;;
  *rk35xx*)
      cp ${WORK_SOURCE}/src/target_rk35xx.manifest ${WORK_SOURCE}/ib/custom.manifest
      cp -a ${WORK_SOURCE}/files/rk35xx/* ${WORK_SOURCE}/ib/files/ 2>/dev/null || true
    ;;
  *rk33xx*)
      cp ${WORK_SOURCE}/src/target_rk33xx.manifest ${WORK_SOURCE}/ib/custom.manifest
      cp -a ${WORK_SOURCE}/files/rk33xx/* ${WORK_SOURCE}/ib/files/ 2>/dev/null || true
    ;;
  *bcm2711*)
      cp ${WORK_SOURCE}/src/target_bcm2711.manifest ${WORK_SOURCE}/ib/custom.manifest
      cp -a ${WORK_SOURCE}/files/bcm2711/* ${WORK_SOURCE}/ib/files/ 2>/dev/null || true
    ;;
esac

if [ "${WORK_TARGET}" = "rk35xx" ]; then
    rm -f "${WORK_SOURCE}"/ib/build_dir/target-*/root-*/etc/uci-defaults/41_uhttpd_proxy_linkease
    rm -f "${WORK_SOURCE}"/ib/build_dir/target-*/root.orig-*/etc/uci-defaults/41_uhttpd_proxy_linkease
fi

cd ${WORK_SOURCE}/ib

case $1 in
  Pack)
    make -f release.mk IB=1
    make -f multi.mk release_env
    ;;
  *)
    make -f multi.mk image_multi FILES="files"
    ;;
esac
