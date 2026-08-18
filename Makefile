# Run the end-to-end tests one at a time.
# Tests drive real GPIO, so they must be run as root.
# Use: sudo make test

SUDO     ?= sudo
PERL     ?= /usr/bin/perl

TEST_DIR ?= test

TESTS    = $(TEST_DIR)/test_volume.pl \
           $(TEST_DIR)/test_pause.pl \
           $(TEST_DIR)/test_skip.pl \
           $(TEST_DIR)/test_albums.pl

.PHONY: all test

all: test

test:
	@for t in $(TESTS); do \
	    echo "==> $$t"; \
	    $(SUDO) $(PERL) $$t || exit 1; \
	done
