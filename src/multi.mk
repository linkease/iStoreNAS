# build image as .config
# make -f multi.mk image_multi
# by jjm2473@gmail.com

include Makefile

package_install_multi: FORCE
	@echo
	@echo Installing manifest packages...
	$(OPKG) install $(firstword $(wildcard $(LINUX_DIR)/libc_*.ipk $(PACKAGE_DIR)/libc_*.ipk))
	$(OPKG) install $(firstword $(wildcard $(LINUX_DIR)/kernel_*.ipk $(PACKAGE_DIR)/kernel_*.ipk))
	cut -d' ' -f1 target.manifest >$(TMP_DIR)/opkg_install_list
	rm -f $(TMP_DIR)/opkg_add_list $(TMP_DIR)/opkg_remove_list
	if [ -s custom.manifest ]; then \
		grep '^-' custom.manifest | sed 's/^- *//g' >$(TMP_DIR)/opkg_remove_list; \
		grep -v '^-' custom.manifest >$(TMP_DIR)/opkg_add_list; \
	fi
	@echo Installing base packages...
	if grep -Eq '^src +imagebuilder +file:packages$$' repositories.conf; then \
		echo 'src imagebuilder file:packages' >$(TMP_DIR)/base_repositories.conf; \
		grep '^option ' repositories.conf >>$(TMP_DIR)/base_repositories.conf; \
		$(OPKG) -f $(TMP_DIR)/base_repositories.conf install --nodeps $$(cat $(TMP_DIR)/opkg_install_list); \
	else \
		$(OPKG) install --nodeps $$(cat $(TMP_DIR)/opkg_install_list); \
	fi
	if [ -s $(TMP_DIR)/opkg_remove_list ]; then \
		echo "Removing custom packages..."; \
		$(OPKG) remove --force-removal-of-dependent-packages $$(cat $(TMP_DIR)/opkg_remove_list); \
	fi
	if [ -s $(TMP_DIR)/opkg_add_list ]; then \
		echo "Installing custom packages..."; \
		$(OPKG) install $$(cat $(TMP_DIR)/opkg_add_list); \
	fi

build_image_multi: FORCE
	@echo
	@echo Building multi images...
	$(NO_TRACE_MAKE) -C target/linux/$(BOARD)/image install TARGET_BUILD=1 IB=1 EXTRA_IMAGE_NAME="$(EXTRA_IMAGE_NAME)"

_call_image_multi: staging_dir/host/.prereq-build
	echo 'Building images for $(BOARD)'
	echo
	rm -rf $(TARGET_DIR) $(TARGET_DIR_ORIG)
	mkdir -p $(TARGET_DIR) $(BIN_DIR) $(TMP_DIR) $(DL_DIR)
	$(MAKE) package_reload
	$(MAKE) -f multi.mk package_install_multi
	$(MAKE) -s prepare_rootfs
	$(MAKE) -f multi.mk build_image_multi
	$(MAKE) -s checksum

image_multi:
	$(MAKE) -s _check_profile
	$(MAKE) -s _check_keys
	(unset PROFILE FILES PACKAGES MAKEFLAGS; \
	$(MAKE) -f multi.mk -s _call_image_multi \
		$(if $(FILES),USER_FILES="$(FILES)") )

profiles_multi:
	@$(STAGING_DIR_HOST)/bin/sed -n 's/^CONFIG_TARGET_$(if $(CONFIG_TARGET_MULTI_PROFILE),DEVICE_)$(call target_conf,$(BOARD)$(if $(SUBTARGET),_$(SUBTARGET)))_\(.*\)=y/\1/p' .config

release_env:
	@echo "IB_BIN_DIR=$(BIN_DIR)"
	@echo "IB_OS_RELEASE=$(VERSION_DIST_SANITIZED)-$(VERSION_NUMBER)-$(VERSION_CODE)"
