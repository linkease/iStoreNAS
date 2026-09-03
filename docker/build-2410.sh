#!/bin/bash
set -e

case ${WORK_TARGET} in
  rk3xxx)
    ;;
  *)
    echo "not supported"
    exit 1
    ;;
esac

source env/${WORK_TARGET}.env

ARCHIVE="${IB_NAME}.${IB_ARCHIVE_EXT:-tar.xz}"
TAR_FLAGS="${IB_TAR_FLAGS:--J}"

IB_FOUND=0
if [ -f ib/.istorenas-2410-prepared ]; then
    IB_FOUND=1
fi

if [ "$IB_FOUND" = "0" ]; then
    if [ ! -f dl/${ARCHIVE} ]; then
        wget -O dl/${MF_NAME} ${IB_URL}${MF_NAME}
        wget -O dl/${ARCHIVE} ${IB_URL}${ARCHIVE}
        wget -O dl/sha256sums ${IB_URL}sha256sums
        [ -s dl/sha256sums ]
        [ -s dl/${MF_NAME} ]
        [ -s dl/${ARCHIVE} ]
        grep -Fq ${ARCHIVE} dl/sha256sums
        cd dl && sha256sum -c --ignore-missing --status sha256sums
    fi

    cd ${WORK_SOURCE}
    find ib -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    tar -C ib --strip-components=1 ${TAR_FLAGS} -xf dl/${ARCHIVE}

    cp -a src/multi.mk src/release.mk ib/
    patch --batch -p0 -d ib -i ../patches/001-all-profiles-2410.patch
    sed -i 's/ unofficial/ oversea/' ib/Makefile

    if ls packages/all/*.ipk >/dev/null 2>&1; then
        ls packages/all | cut -d "_" -f 1 | xargs -r -n1 sh -c 'rm -f ib/packages/$0*.ipk'
        cp packages/all/*.ipk ib/packages/
    fi

    mkdir -p ib/files
    cp -a files/all/* ib/files/ 2>/dev/null || true
    cp -a files/${WORK_TARGET}/* ib/files/ 2>/dev/null || true
    rm -f ib/files/etc/config/nginx
    rm -f ib/files/etc/nginx/uci.conf.template

    cp dl/${MF_NAME} ib/target.manifest
    cp src/target_${WORK_TARGET}.manifest ib/custom.manifest

    cp ib/repositories.conf ib/repositories.conf.orig
    grep -v '^option check_signature' ib/repositories.conf.orig > ib/repositories.conf
    cat >> ib/repositories.conf <<'REPOS'

src/gz istore_all_compat https://istore.linkease.com/repo/all/compat
src/gz istore_all https://istore.linkease.com/repo/all/store
src/gz istore_all_meta https://istore.linkease.com/repo/all/meta
src/gz istore_all_nas_luci https://istore.linkease.com/repo/all/nas_luci
src/gz istore_nas https://istore.linkease.com/repo/aarch64_cortex-a53/nas
REPOS
    grep -Eq '^src +imagebuilder +file:packages$' ib/repositories.conf || \
        echo 'src imagebuilder file:packages' >> ib/repositories.conf

    touch ib/.istorenas-2410-prepared
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
