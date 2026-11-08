WG_SYNOLOGY_DIR ?= $(CURDIR)/synology

include $(WG_SYNOLOGY_DIR)/synology.mk

build: build-synology

clean: clean-synology