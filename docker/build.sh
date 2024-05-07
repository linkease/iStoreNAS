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

IB_FOUND=0
if grep -q istore_nas ib/repositories.conf; then
    IB_FOUND=1
else
    IB_FOUND=0
fi

set -e
if [ "$IB_FOUND" = "0" ]; then
    if [ ! -f dl/${IB_NAME}.tar.xz ]; then
        wget -O dl/${MF_NAME} ${IB_URL}${MF_NAME}
        wget -O dl/${IB_NAME}.tar.xz ${IB_URL}${IB_NAME}.tar.xz
        wget -O dl/sha256sums ${IB_URL}sha256sums
        [ -s dl/sha256sums ]
        [ -s dl/${MF_NAME} ]
        [ -s dl/${IB_NAME}.tar.xz ]
        grep -Fq ${IB_NAME}.tar.xz dl/sha256sums
        cd dl && sha256sum -c --ignore-missing --status sha256sums
    fi

    cd ${WORK_SOURCE}
    tar -C ib --strip-components=1 -xJf dl/${IB_NAME}.tar.xz
    cp -a src/* ib/
    ls patches/ | sort | xargs -n1 sh -c 'patch -p1 -d ib -i ../patches/$0'
    sed -i 's/ unofficial/ oversea/' ib/Makefile
    ls packages/all | cut -d "_" -f 1 | xargs -n1 sh -c 'rm ib/packages/$0*.ipk'
    cp packages/all/*.ipk ib/packages/
    mkdir -p ib/files
    cp -a files/all/* ib/files
    cp dl/${MF_NAME} ib/target.manifest
    case ${WORK_TARGET} in
      *x86*)
          cp src/repositories_x86_64.conf ib/repositories.conf
          cp src/target_x86_64.manifest ib/custom.manifest
        ;;
      *rk35xx*)
          cp src/repositories_rk35xx.conf ib/repositories.conf
          cp src/target_rk35xx.manifest ib/custom.manifest
        ;;
      *rk33xx*)
          cp src/repositories_rk33xx.conf ib/repositories.conf
          cp src/target_rk33xx.manifest ib/custom.manifest
        ;;
      *bcm2711*)
          cp src/repositories_aarch64.conf ib/repositories.conf
          cp src/target_bcm2711.manifest ib/custom.manifest
        ;;
    esac
fi
set +e

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

