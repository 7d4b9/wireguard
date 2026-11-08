WG_SYNOLOGY_PLATFORM ?= linux/arm/v7
WG_SYNOLOGY_DIR ?= $(CURDIR)
WG_SYNOLOGY_DIST ?= $(WG_SYNOLOGY_DIR)/dist/linux-armv7

.PHONY: build-synology build-wg-synology build-wireguard-go-synology clean-synologyy

build-synology: build-wg-synology build-wireguard-go-synology

build-wg-synology:
	mkdir -p $(WG_SYNOLOGY_DIST)
	docker run --rm \
		--platform $(WG_SYNOLOGY_PLATFORM) \
		-v "$(CURDIR)/wireguard-tools/src:/build" \
		-v "$(WG_SYNOLOGY_DIST):/dist" \
		-w /build \
		alpine:3.22 \
		sh -ec '\
			apk add --no-cache build-base linux-headers pkgconf; \
			make clean; \
			make CC=gcc LDFLAGS=-static \
				WITH_WGQUICK=no \
				WITH_SYSTEMDUNITS=no; \
			cp wg /dist/wg; \
		'

build-wireguard-go-synology:
	mkdir -p $(WG_SYNOLOGY_DIST)
	docker run --rm \
		--platform linux/amd64 \
		-v "$(CURDIR)/wireguard-go:/build" \
		-v "$(WG_SYNOLOGY_DIST):/dist" \
		-w /build \
		golang:1.27 \
		sh -ec '\
			CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
				go build -trimpath -o /dist/wireguard-go .; \
		'

clean-synology:
	rm -rf $(WG_SYNOLOGY_DIST)