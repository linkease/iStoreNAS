
CUR_MAKEFILE:=$(filter-out Makefile,$(firstword $(MAKEFILE_LIST)))
SUBMAKE:=make $(if $(CUR_MAKEFILE),-f $(CUR_MAKEFILE))

ifneq ($(BUILD),)

include $(TOPDIR)/rules.mk
REVISION:=$(shell $(TOPDIR)/scripts/getver.sh)
SOURCE_DATE_EPOCH:=$(shell $(TOPDIR)/scripts/get_source_date_epoch.sh)
include $(INCLUDE_DIR)/image.mk

all: $(BOARD)$(if $(SUBTARGET),-$(SUBTARGET))$(if $(PROFILE_SANITIZED),-$(PROFILE_SANITIZED))

define IMAGE/TARGET

FIRMWARE_BASE_NAME:=$(patsubst %.img,%,$(patsubst %.gz,%,$(3)))

$(1)/$(2)/version.index: $(1)/$(2)/$$(FIRMWARE_BASE_NAME).yaml
	echo "$(VERSION_NUMBER)-$(VERSION_CODE)" > $$@

$(1)/$(2)/$$(FIRMWARE_BASE_NAME).yaml: $(1)/$(2)/version.latest
	echo "filename: $(3)" > $$@
	echo "path: /iStoreOS/$(2)/" >> $$@
	head -3 $(1)/$(2)/version.latest | tail -2 | tr 'A-Z' 'a-z' >> $$@
	echo "device: $(2)" >> $$@
	echo "version: $(VERSION_NUMBER)" >> $$@
	echo "release: $(VERSION_CODE)" >> $$@
	TZ='CST-8' date +'date: %F %T' -r '$(1)/$(2)/$(3)' >> $$@
	echo "type: istoreos" >> $$@

$(1)/$(2)/version.latest: $(1)/$(2)/$(3)
	echo "[$(3)]($(3))" > $$@; \
	FIRMWARE_SHA256=`sha256sum $(1)/$(2)/$(3) | cut -d' ' -f1`; \
	echo "SHA256: $$$${FIRMWARE_SHA256}" >> $$@ ; \
	FIRMWARE_MD5=`md5sum $(1)/$(2)/$(3)| cut -d' ' -f1`; \
	echo "MD5: $$$${FIRMWARE_MD5}" >> $$@

$(1)/$(2)/$(3): $(BIN_DIR)/$(if $(4),$(4),$(3))
	mkdir -p $(1)/$(2)
ifeq ($(IB),)
	$(CP) $(BIN_DIR)/feeds.buildinfo $(1)/$(2)/
	$(CP) $(BIN_DIR)/config.buildinfo $(1)/$(2)/
	git log -n 1 --format="%h" > $(1)/$(2)/commit.buildinfo
	$(CP) ./feeds.conf $(1)/$(2)/
	./scripts/diffconfig.sh > $(1)/$(2)/config.seed
endif # !IB
	$(CP) $$< $$@

endef

define IMAGE/BUILDER

$(1)/$(2)/$(3).tar.xz: $(BIN_DIR)/$(3).tar.xz
	mkdir -p $(1)/$(2)
	$(CP) $$< $$@

$(1)/$(2)/$(4): $(BIN_DIR)/$(4)
	mkdir -p $(1)/$(2)
	$(CP) $$< $$@

$(1)/$(2)/sha256sums: $(1)/$(2)/$(3).tar.xz $(1)/$(2)/$(4)
	@$$(call sha256sums,$(1)/$(2))

endef

DIST_DIR:=../build

COMMON/IMAGE=$(call IMAGE/TARGET,$(DIST_DIR),$(2),$(VERSION_DIST_SANITIZED)-$(VERSION_NUMBER)-$(VERSION_CODE)-$(1)-$(2)-squashfs.img.gz,$(IMG_PREFIX)$(if $(PROFILE_SANITIZED),-$(PROFILE_SANITIZED))-squashfs-sysupgrade.img.gz)

COMMON/MULTI_DEVICES=$(call IMAGE/TARGET,$(DIST_DIR),$(if $(3),$(3),$(2)),$(VERSION_DIST_SANITIZED)-$(VERSION_NUMBER)-$(VERSION_CODE)-$(if $(3),$(3),$(2))-squashfs.img.gz,$(IMG_PREFIX)-$(1)_$(2)-squashfs-sysupgrade.img.gz)

COMMON/COMBINED_DEVICE=$(call IMAGE/TARGET,$(DIST_DIR),$(if $(3),$(3),$(2)),$(VERSION_DIST_SANITIZED)-$(VERSION_NUMBER)-$(VERSION_CODE)-$(if $(3),$(3),$(2))-squashfs-combined.img.gz,$(IMG_PREFIX)-$(1)_$(2)-squashfs-combined.img.gz)

HOST_OS:=$(shell uname)
HOST_ARCH:=$(shell uname -m)
IB_DIR:=$(DIST_DIR)/ib
IB_NAME:=$(VERSION_DIST_SANITIZED)-imagebuilder-$(if $(CONFIG_VERSION_FILENAMES),$(VERSION_NUMBER)-)$(BOARD)$(if $(SUBTARGET),-$(SUBTARGET)).$(HOST_OS)-$(HOST_ARCH)
MF_NAME:=$(IMG_PREFIX)$(if $(PROFILE_SANITIZED),-$(PROFILE_SANITIZED)).manifest

COMMON/BUILDER=$(call IMAGE/BUILDER,$(IB_DIR),$(1),$(IB_NAME),$(MF_NAME))

ifeq ($(BOARD), x86)
X86_64_DIR:=$(DIST_DIR)/x86_64
X86_64_IMG_PREFIX:=$(VERSION_DIST_SANITIZED)-$(VERSION_NUMBER)-$(VERSION_CODE)-x86-64-squashfs-combined
X86_64_SRC_PREFIX:=$(IMG_PREFIX)$(if $(PROFILE_SANITIZED),-$(PROFILE_SANITIZED))-squashfs-combined

X86_64/IMAGE=$(call IMAGE/TARGET,$(DIST_DIR),x86_64$(if $(1),_$(1)),$(X86_64_IMG_PREFIX)$(if $(1),-$(1)).img.gz,$(X86_64_SRC_PREFIX)$(if $(1),-$(1)).img.gz)

$(eval $(call X86_64/IMAGE,))
$(eval $(call X86_64/IMAGE,efi))
$(eval $(call COMMON/BUILDER,x86_64))

x86-64-generic: $(X86_64_DIR)/version.index $(X86_64_DIR)_efi/version.index \
 $(if $(IB),,$(IB_DIR)/x86_64/sha256sums)
endif

ifeq ($(BOARD), rockchip)
ifeq ($(SUBTARGET), armv8)
ifneq ($(PROFILE_SANITIZED),)
$(eval $(call COMMON/IMAGE,nanopi,r2s))

rockchip-armv8-friendlyarm_nanopi-r2s: $(DIST_DIR)/r2s/version.index

$(eval $(call COMMON/IMAGE,nanopi,r4s))

rockchip-armv8-friendlyarm_nanopi-r4s: $(DIST_DIR)/r4s/version.index
else # !PROFILE_SANITIZED

$(eval $(call COMMON/MULTI_DEVICES,friendlyarm,nanopi-r2s,r2s))
$(eval $(call COMMON/MULTI_DEVICES,friendlyarm,nanopi-r4s,r4s))
$(eval $(call COMMON/MULTI_DEVICES,friendlyarm,nanopi-r4se,r4se))

$(eval $(call COMMON/BUILDER,rk33xx))

rockchip-armv8: $(DIST_DIR)/r2s/version.index $(DIST_DIR)/r4s/version.index $(DIST_DIR)/r4se/version.index \
 $(if $(IB),,$(IB_DIR)/rk33xx/sha256sums)

endif # PROFILE_SANITIZED
endif # armv8

ifeq ($(SUBTARGET), rk35xx)
$(eval $(call COMMON/COMBINED_DEVICE,fastrhino,r6xs))
$(eval $(call COMMON/COMBINED_DEVICE,friendlyarm,nanopi-r5s,r5s))
$(eval $(call COMMON/COMBINED_DEVICE,friendlyarm,nanopi-r6s,r6s))
$(eval $(call COMMON/MULTI_DEVICES,firefly,station-p2))
$(eval $(call COMMON/MULTI_DEVICES,lyt,t68m))
$(eval $(call COMMON/COMBINED_DEVICE,hinlink,opc-h6xk,h6xk))
$(eval $(call COMMON/COMBINED_DEVICE,hinlink,h88k))
$(eval $(call COMMON/MULTI_DEVICES,hlink,h28k))
$(eval $(call COMMON/BUILDER,rk35xx))
rockchip-rk35xx: $(DIST_DIR)/r6xs/version.index \
 $(DIST_DIR)/r5s/version.index $(DIST_DIR)/r6s/version.index \
 $(DIST_DIR)/station-p2/version.index \
 $(DIST_DIR)/h6xk/version.index \
 $(DIST_DIR)/h88k/version.index \
 $(DIST_DIR)/h28k/version.index \
 $(DIST_DIR)/t68m/version.index \
 $(if $(IB),,$(IB_DIR)/rk35xx/sha256sums)
endif # rk35xx

endif # rockchip

ifeq ($(BOARD)-$(SUBTARGET), bcm27xx-bcm2711)
$(eval $(call COMMON/IMAGE,raspberrypi,rpi4))
$(eval $(call COMMON/BUILDER,bcm2711))
bcm27xx-bcm2711-rpi-4: $(DIST_DIR)/rpi4/version.index \
 $(if $(IB),,$(IB_DIR)/bcm2711/sha256sums)
endif # bcm27xx-bcm2711

else

TOPDIR:=${CURDIR}

LC_ALL:=C
LANG:=C
TZ:=UTC
export TOPDIR LC_ALL LANG TZ

export PATH:=$(TOPDIR)/staging_dir/host/bin:$(PATH)

all: FORCE
	$(SUBMAKE) BUILD=1 $(if $(IB),IB="$(IB)")
%: FORCE
	$(SUBMAKE) BUILD=1 $@ $(if $(IB),IB="$(IB)")

FORCE: ;
.PHONY: FORCE
endif
