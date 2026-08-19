# Koba: a Ghostty based terminal.
#
# Builds with Xcode Command Line Tools only (no Xcode required). libghostty
# is built from source with a pinned zig; see patches/ghostty-clt-build.patch
# for the small changes that make that possible.

GHOSTTY_VERSION := v1.3.1
ZIG_VERSION := 0.15.2
ZIG_DIST := zig-aarch64-macos-$(ZIG_VERSION)

ZIG := vendor/zig/$(ZIG_DIST)/zig
GHOSTTY_OUT := vendor/ghostty/zig-out
LIBGHOSTTY := $(GHOSTTY_OUT)/lib/libghostty.a

APP := build/Koba.app
BIN := $(APP)/Contents/MacOS/koba
SRCS := src/main.m src/KobaApp.m src/KobaColors.m src/KobaCommandPalette.m \
	src/KobaConfig.m src/KobaSplitView.m src/KobaSurfaceView.m \
	src/KobaWorkspace.m src/KobaWorkspaceStrip.m
HDRS := src/KobaApp.h src/KobaColors.h src/KobaCommandPalette.h \
	src/KobaConfig.h src/KobaSplitView.h src/KobaSurfaceView.h \
	src/KobaWorkspace.h src/KobaWorkspaceStrip.h

CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -g -I$(GHOSTTY_OUT)/include
FRAMEWORKS := -framework Cocoa -framework CoreText -framework Metal \
	-framework MetalKit -framework QuartzCore -framework IOSurface \
	-framework CoreVideo -framework Carbon -framework UniformTypeIdentifiers \
	-framework UserNotifications
LDFLAGS := $(LIBGHOSTTY) $(FRAMEWORKS) -lc++ -lz

export ZIG_GLOBAL_CACHE_DIR := $(CURDIR)/vendor/zig-cache/global
export ZIG_LOCAL_CACHE_DIR := $(CURDIR)/vendor/zig-cache/local

.PHONY: app run clean clean-all libghostty

app: $(BIN)

run: $(BIN)
	$(BIN)

# --- Toolchain + vendored ghostty ------------------------------------------

$(ZIG):
	mkdir -p vendor/zig
	curl -fsSL https://ziglang.org/download/$(ZIG_VERSION)/$(ZIG_DIST).tar.xz \
		| tar -xJ -C vendor/zig

vendor/ghostty/.patched:
	@if [ ! -d vendor/ghostty/.git ]; then \
		GIT_CONFIG_GLOBAL=/dev/null git clone --depth 1 --branch $(GHOSTTY_VERSION) \
			https://github.com/ghostty-org/ghostty vendor/ghostty; \
	fi
	git -C vendor/ghostty apply ../../patches/ghostty-clt-build.patch
	touch vendor/ghostty/.patched

$(LIBGHOSTTY): $(ZIG) vendor/ghostty/.patched
	./scripts/fetch-zig-deps.sh

libghostty: $(LIBGHOSTTY)

# --- App bundle -------------------------------------------------------------

$(BIN): $(SRCS) $(HDRS) resources/Info.plist $(LIBGHOSTTY)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp resources/Info.plist $(APP)/Contents/Info.plist
	rsync -a --delete $(GHOSTTY_OUT)/share/ghostty/ $(APP)/Contents/Resources/ghostty/
	rsync -a --delete $(GHOSTTY_OUT)/share/terminfo/ $(APP)/Contents/Resources/terminfo/
	clang $(CFLAGS) $(SRCS) $(LDFLAGS) -o $(BIN)
	codesign --force --sign - $(APP)

clean:
	rm -rf build

clean-all: clean
	rm -rf vendor
