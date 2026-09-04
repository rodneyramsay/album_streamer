
BUILDROOT_DIR=/home/rodney/buildroot
BR2_EXTERNAL := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CARD       ?= /dev/sdg
# Cap the user-data partition to this many GiB (0 = use rest of the card).
MAX_USERDATA_G ?= 0
# Size of the small pidap metadata partition in MiB (default 1; 512K is too small for ext4).
PIDAP_DATA_SIZE_M ?= 1

export PIDAP_DATA_SIZE_M

# Music to bundle into the user-data partition image during build.
# The default source is the NAS library; override if your music lives elsewhere.
MUSIC_SOURCE  ?= /mnt/wd_my_cloud/Music
MUSIC_INCLUDE ?=
# File with one relative path per line; overrides MUSIC_INCLUDE if it exists.
MUSIC_INCLUDE_FILE ?= $(BR2_EXTERNAL)music-include.txt

export MUSIC_INCLUDE_FILE MUSIC_INCLUDE MUSIC_SOURCE

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
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" BR2_EXTERNAL=$(BR2_EXTERNAL) $(DEFCONFIG)

nfs:
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)"
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
		if [ -b "$${card}4" ]; then \
			label=$$(sudo blkid -s LABEL -o value "$${card}4" 2>/dev/null || true); \
			if [ -n "$$label" ] && [ "$$label" != "user-data" ]; then echo "Warning: $${card}4 label is \"$$label\""; fi; \
		fi; \
		echo "$$card is a block device -- continue with care" \
	'

check-data:
	@sh -c ' \
		set -e; \
		card="$(CARD)"; \
		if [ ! -b "$$card" ]; then echo "ERROR: $$card is not a block device"; exit 1; fi; \
		echo "Checking $$card data partition..."; \
		if [ ! -b "$${card}4" ]; then echo "ERROR: $${card}4 does not exist"; exit 1; fi; \
		label=$$(sudo blkid -s LABEL -o value "$${card}4" 2>/dev/null || true); \
		if [ "$$label" != "user-data" ]; then echo "ERROR: $${card}4 label is \"$$label\", expected \"user-data\""; exit 1; fi; \
		echo "$$card data partition looks correct -- safe to flash data" \
	'


check-card:
	@for p in 1 2 3 4; do \
		dev="$(CARD)$$p"; \
		if [ ! -b "$$dev" ]; then \
			echo "Error: $$dev is not a block device (card missing or stale file)"; \
			exit 1; \
		fi; \
		size=$$(sudo blockdev --getsize64 "$$dev" 2>/dev/null) || true; \
		if [ -z "$$size" ] || [ "$$size" -eq 0 ] 2>/dev/null; then \
			echo "Error: $$dev has no size (card not inserted or wrong partition)"; \
			exit 1; \
		fi; \
	done

sdcard: defconfig check check-card
	-for p in 1 2 3 4; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" BR2_EXTERNAL=$(BR2_EXTERNAL)
	sudo CARD=$(CARD) MAX_USERDATA_G=$(MAX_USERDATA_G) PIDAP_DATA_SIZE_M=$(PIDAP_DATA_SIZE_M) ./flash-sdcard.sh all
	@if [ "$(DEPLOY_NFS)" = "1" ]; then \
		sudo ./deploy-nfs.sh; \
		ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true; \
	fi

sdcard-boot: defconfig check check-card
	-for p in 1 2 3 4; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" BR2_EXTERNAL=$(BR2_EXTERNAL)
	sudo dd if=$(BUILDROOT_DIR)/output/images/boot.vfat of=$(CARD)1 bs=4M status=progress conv=fsync
	@if [ "$(DEPLOY_NFS)" = "1" ]; then \
		sudo ./deploy-nfs.sh; \
		ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true; \
	fi

sdcard-system: defconfig check check-card
	-for p in 1 2 3 4; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" BR2_EXTERNAL=$(BR2_EXTERNAL)
	# Clean the existing user-data partition if it is dirty; we don't fsck on the Pi.
	-sudo fsck.vfat -a $(CARD)4 2>/dev/null || sudo fsck.fat -a $(CARD)4 2>/dev/null || true
	cp $(BUILDROOT_DIR)/output/images/boot.vfat $(BUILDROOT_DIR)/output/images/boot-sd.vfat
	MTOOLS_SKIP_CHECK=1 mcopy -o -i $(BUILDROOT_DIR)/output/images/boot-sd.vfat $(BR2_EXTERNAL)/board/PIDAP/cmdline-sd.txt ::cmdline.txt
	sudo dd if=$(BUILDROOT_DIR)/output/images/boot-sd.vfat of=$(CARD)1 bs=4M status=progress conv=fsync
	rm -f $(BUILDROOT_DIR)/output/images/boot-sd.vfat
	sudo dd if=$(BUILDROOT_DIR)/output/images/rootfs.ext2 of=$(CARD)2 bs=4M status=progress conv=fsync

sdcard-data: defconfig check-data check-card
	-for p in 1 2 3 4; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR) MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" BR2_EXTERNAL=$(BR2_EXTERNAL)
	# Clean the user-data partition before writing data.
	-sudo fsck.vfat -a $(CARD)4 2>/dev/null || sudo fsck.fat -a $(CARD)4 2>/dev/null || true
	sudo CARD=$(CARD) ./flash-sdcard.sh data

# Prepare a card with a sensibly small user-data partition.  If
# MAX_USERDATA_G is 0 (the default) the cap is computed from the card size.
sdcard-prep: check
	@cap=$(MAX_USERDATA_G); \
	if [ "$$cap" = "0" ]; then \
		size=$$(sudo blockdev --getsize64 $(CARD)); \
		gb=$$(( size / 1024 / 1024 / 1024 )); \
		cap=$$(( gb / 4 )); \
		[ $$cap -lt 1 ] && cap=1; \
		[ $$cap -gt 4 ] && cap=4; \
		echo "Detected $${gb} GiB card; capping user-data at $${cap} GiB"; \
	else \
		echo "Using requested user-data cap: $${cap} GiB"; \
	fi; \
	$(MAKE) CARD=$(CARD) MAX_USERDATA_G=$$cap MUSIC_SOURCE="$(MUSIC_SOURCE)" MUSIC_INCLUDE="$(MUSIC_INCLUDE)" sdcard
