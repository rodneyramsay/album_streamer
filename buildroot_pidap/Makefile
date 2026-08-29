
BUILDROOT_DIR=/home/rodney/buildroot
CARD       ?= /dev/sdc

nfs:
	make -C $(BUILDROOT_DIR)
	sudo ./deploy-nfs.sh


check:
	@sh -c ' \
		set -e; \
		card="$(CARD)"; \
		if [ ! -b "$$card" ]; then echo "ERROR: $$card is not a block device"; exit 1; fi; \
		echo "Checking $$card..."; \
		if [ ! -b "$${card}1" ]; then echo "ERROR: $${card}1 does not exist"; exit 1; fi; \
		mp=$$(findmnt -n -o TARGET "$${card}1" 2>/dev/null || true); \
		if [ -z "$$mp" ]; then echo "ERROR: $${card}1 is not mounted -- cannot verify it is the PIDAP card"; exit 1; fi; \
		if [ ! -f "$$mp/config.txt" ]; then echo "ERROR: $${card}1 has no config.txt at $$mp"; exit 1; fi; \
		if ! grep -q "kernel=zImage" "$$mp/config.txt"; then echo "ERROR: $${card}1 does not look like a PIDAP card"; exit 1; fi; \
		if [ -b "$${card}3" ]; then \
			label=$$(sudo blkid -s LABEL -o value "$${card}3" 2>/dev/null || true); \
			if [ "$$label" != "user-data" ]; then echo "ERROR: $${card}3 label is \"$$label\", expected \"user-data\""; exit 1; fi; \
		fi; \
		echo "$$card is mounted and looks like the PIDAP card -- safe to unmount and flash" \
	'


sdcard: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo dd if=$(BUILDROOT_DIR)/output/images/sdcard.img of=$(CARD) bs=4M status=progress conv=fsync
	sudo ./deploy-nfs.sh
	ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true

sdcard-boot: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo dd if=$(BUILDROOT_DIR)/output/images/boot.vfat of=$(CARD)1 bs=4M status=progress conv=fsync
	sudo ./deploy-nfs.sh
	ssh-keygen -f /home/rodney/.ssh/known_hosts -R 192.168.0.31 2>/dev/null || true

sdcard-data: check
	-for p in 1 2 3; do sudo umount $(CARD)$$p 2>/dev/null || true; done
	make -C $(BUILDROOT_DIR)
	sudo dd if=$(BUILDROOT_DIR)/output/images/user-data.ext4 of=$(CARD)3 bs=4M status=progress conv=fsync
