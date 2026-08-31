
BUILDROOT_DIR=/home/rodney/buildroot
BR2_EXTERNAL := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CARD       ?= /dev/sdg
# Cap the user-data partition to this many GiB (0 = use rest of the card).
MAX_USERDATA_G ?= 0

# Config selection: either override DEFCONFIG, or set both MODEL and PROFILE.
MODEL   ?=
PROFILE ?=
ifeq ($(and $(MODEL),$(PROFILE)),)
  DEFCONFIG ?= pidap_defconfig
else
  DEFCONFIG ?= pidap_$(MODEL)_$(PROFILE)_defconfig
endif

# release profiles are SD-card-only and should not touch the host NFS server.
DEPLOY_NFS ?= $(if $(filter release,$(PROFILE)),0,1)

list-configs:
	@ls $(BR2_EXTERNAL)/configs/*_defconfig 2>/dev/null | xargs -n1 basename

defconfig:
	@test -f $(BR2_EXTERNAL)/configs/$(DEFCONFIG) || { echo "No such defconfig: configs/$(DEFCONFIG)"; exit 1; }
	make -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) $(DEFCONFIG)

nfs:
	make -C $(BUILDROOT_DIR)
	sudo ./deploy-nfs.sh


check:
	@sh -c ' \
		set -e; \
		card="$(CARD)"; \
		if [ ! -b "$$card" ]; then echo "ERROR: $$card is not a block device"; exit 1; fi; \
		echo "Checking $$card..."; \
		if [ -b "$${card}1" ]; then \
			mp=$$(findmnt -n -o TARGET "$${card}1" 2>/dev/null || true); \
			if [ -n "$$mp" ]; then \
				if [ ! -f "$$mp/config.txt" ]; then echo "Warning: $${card}1 has no config.txt at $$mp"; \
				elif ! grep -q "kernel=zImage" "$$mp/config.txt" 2>/dev/null; then echo "Warning: $${card}1 does not look like a PIDAP card"; fi; \
			fi; \
		else \
			echo "Warning: $${card}1 does not exist yet"; \
		fi; \
		if [ -b "$${card}3" ]; then \
			label=$$(sudo blkid -s LABEL -o value "$${card}3" 2>/dev/null || true); \
			if [ -n "$$label" ] && [ "$$label" != "user-data" ]; then echo "Warning: $${card}3 label is \"$$label\""; fi; \
		fi; \
		echo "$$card is a block device -- continue with care" \
	'

check-data:
	@sh -c ' \
		set -e; \
		card="$(CARD)"; \
		if [ ! -b "$$card" ]; then echo "ERROR: $$card is not a block device"; exit 1; fi; \
		echo "Checking $$card data partition..."; \
		if [ ! -b "$${card}3" ]; then echo "ERROR: $${card}3 does not exist"; exit 1; fi; \
		label=$$(sudo blkid -s LABEL -o value "$${card}3" 2>/dev/null || true); \
		if [ "$$label" != "user-data" ]; then echo "ERROR: $${card}3 label is \"$$label\", expected \"user-data\""; exit 1; fi; \
		echo "$$card data partition looks correct -- safe to flash data" \
	'


sdcard: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo CARD=$(CARD) MAX_USERDATA_G=$(MAX_USERDATA_G) ./flash-sdcard.sh all
	@if [ "$(DEPLOY_NFS)" = "1" ]; then \
		sudo ./deploy-nfs.sh; \
		ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true; \
	fi

sdcard-boot: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo dd if=$(BUILDROOT_DIR)/output/images/boot.vfat of=$(CARD)1 bs=4M status=progress conv=fsync
	@if [ "$(DEPLOY_NFS)" = "1" ]; then \
		sudo ./deploy-nfs.sh; \
		ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true; \
	fi

sdcard-system: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	cp $(BUILDROOT_DIR)/output/images/boot.vfat $(BUILDROOT_DIR)/output/images/boot-sd.vfat
	MTOOLS_SKIP_CHECK=1 mcopy -o -i $(BUILDROOT_DIR)/output/images/boot-sd.vfat $(BR2_EXTERNAL)/board/PIDAP/cmdline-sd.txt ::cmdline.txt
	sudo dd if=$(BUILDROOT_DIR)/output/images/boot-sd.vfat of=$(CARD)1 bs=4M status=progress conv=fsync
	rm -f $(BUILDROOT_DIR)/output/images/boot-sd.vfat
	sudo dd if=$(BUILDROOT_DIR)/output/images/rootfs.ext2 of=$(CARD)2 bs=4M status=progress conv=fsync

sdcard-data: check-data
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo CARD=$(CARD) ./flash-sdcard.sh data
