PREFIX     ?= /usr/local
BIN        ?= $(PREFIX)/bin
SWIFTC     ?= swiftc
SWIFTFLAGS ?= -O -whole-module-optimization

# Minimum macOS for the released universal binary. macOS 11 (Big Sur) is the
# first version that runs on Apple Silicon, so it's the natural floor.
MACOS_MIN  ?= 11
VERSION    ?= 0.1.0
BUILD_DIR  := build
RELEASE    := findmouse-$(VERSION)-macos-universal
RELEASE_DIR := $(BUILD_DIR)/$(RELEASE)
TARBALL    := $(BUILD_DIR)/$(RELEASE).tar.gz

.PHONY: all clean install uninstall release

all: findmouse

findmouse: findmouse.swift
	$(SWIFTC) $(SWIFTFLAGS) findmouse.swift -o findmouse
	strip -x findmouse

clean:
	rm -rf $(BUILD_DIR)
	rm -f findmouse

install: findmouse
	install -d "$(BIN)"
	install -m 755 findmouse "$(BIN)/findmouse"

uninstall:
	rm -f "$(BIN)/findmouse"

# Build a universal (arm64 + x86_64) binary and package it as a tarball ready
# to upload to a GitHub Release. Run `make release VERSION=x.y.z` to override.
release: findmouse.swift README.md LICENSE
	@rm -rf $(RELEASE_DIR)
	@mkdir -p $(RELEASE_DIR)
	$(SWIFTC) $(SWIFTFLAGS) -target arm64-apple-macos$(MACOS_MIN)  findmouse.swift -o $(BUILD_DIR)/findmouse.arm64
	$(SWIFTC) $(SWIFTFLAGS) -target x86_64-apple-macos$(MACOS_MIN) findmouse.swift -o $(BUILD_DIR)/findmouse.x86_64
	lipo -create $(BUILD_DIR)/findmouse.arm64 $(BUILD_DIR)/findmouse.x86_64 \
	     -output $(RELEASE_DIR)/findmouse
	strip -x $(RELEASE_DIR)/findmouse
	cp README.md LICENSE $(RELEASE_DIR)/
	tar -C $(BUILD_DIR) -czf $(TARBALL) $(RELEASE)
	cd $(BUILD_DIR) && shasum -a 256 $(RELEASE).tar.gz > $(RELEASE).tar.gz.sha256
	@echo
	@echo "=== release artifacts ==="
	@ls -la $(TARBALL) $(TARBALL).sha256
	@lipo -info $(RELEASE_DIR)/findmouse
