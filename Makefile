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
SRCS := src/main.m src/KobaApp.m src/KobaClipboard.m src/KobaColors.m \
	src/KobaCommandPalette.m src/KobaConfig.m src/KobaSplitView.m \
	src/KobaSurfaceView.m src/KobaWorkspace.m src/KobaWorkspaceStrip.m
HDRS := src/KobaApp.h src/KobaClipboard.h src/KobaColors.h \
	src/KobaCommandPalette.h src/KobaConfig.h src/KobaSplitView.h \
	src/KobaSurfaceView.h src/KobaWorkspace.h src/KobaWorkspaceStrip.h

# Herdr.app: a dedicated window running a herdr client, sharing Koba's
# ghostty surface.
HERDR_APP := build/Herdr.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
HERDR_BIN := $(HERDR_APP)/Contents/MacOS/herdr-app
HERDR_SRCS := src/herdr_main.m src/HerdrApp.m src/KobaClipboard.m \
	src/KobaColors.m src/KobaConfig.m src/KobaSurfaceView.m
HERDR_HDRS := src/HerdrApp.h src/KobaClipboard.h src/KobaColors.h \
	src/KobaConfig.h src/KobaSurfaceView.h
# Run by the app itself; the rest of scripts/ is run by herdr's config.
HERDR_SCRIPTS := scripts/herdr-pr-status scripts/herdr-lib.sh

CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -g -I$(GHOSTTY_OUT)/include
FRAMEWORKS := -framework Cocoa -framework CoreText -framework Metal \
	-framework MetalKit -framework QuartzCore -framework IOSurface \
	-framework CoreVideo -framework Carbon -framework UniformTypeIdentifiers \
	-framework UserNotifications
LDFLAGS := $(LIBGHOSTTY) $(FRAMEWORKS) -lc++ -lz

export ZIG_GLOBAL_CACHE_DIR := $(CURDIR)/vendor/zig-cache/global
export ZIG_LOCAL_CACHE_DIR := $(CURDIR)/vendor/zig-cache/local

.PHONY: app run install herdr run-herdr install-herdr reload-herdr clean clean-all libghostty

app: $(BIN)

run: $(BIN)
	$(BIN)

install: $(BIN)
	mkdir -p ~/Applications
	rsync -a --delete $(APP)/ ~/Applications/Koba.app/
	/usr/libexec/PlistBuddy \
		-c 'Set :CFBundleName Koba' \
		-c 'Set :CFBundleDisplayName Koba' \
		~/Applications/Koba.app/Contents/Info.plist
	codesign --force --sign - ~/Applications/Koba.app

herdr: $(HERDR_BIN)

run-herdr: $(HERDR_BIN)
	$(HERDR_BIN)

# rsync keeps the old bundle mtime, so LaunchServices would keep serving a
# cached icon; touch and re-register to pick up changes.
install-herdr: $(HERDR_BIN)
	mkdir -p ~/Applications
	rsync -a --delete $(HERDR_APP)/ ~/Applications/Herdr.app/
	codesign --force --sign - ~/Applications/Herdr.app
	touch ~/Applications/Herdr.app
	$(LSREGISTER) -f ~/Applications/Herdr.app

# Applies config/herdr.toml and relaunches the app with the latest build.
# Quitting only detaches; spaces and agents keep running in the server.
reload-herdr: install-herdr
	herdr server reload-config
	pkill -x herdr-app || true
	while pgrep -x herdr-app > /dev/null; do sleep 0.1; done
	open ~/Applications/Herdr.app

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

$(BIN): $(SRCS) $(HDRS) resources/Info.plist resources/icon.png $(LIBGHOSTTY)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp resources/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c 'Set :CFBundleName "Koba (Dev)"' \
		-c 'Set :CFBundleDisplayName "Koba (Dev)"' \
		$(APP)/Contents/Info.plist
	mkdir -p build/koba.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s resources/icon.png \
			--out build/koba.iconset/icon_$${s}x$${s}.png > /dev/null; \
		sips -z $$((s * 2)) $$((s * 2)) resources/icon.png \
			--out build/koba.iconset/icon_$${s}x$${s}@2x.png > /dev/null; \
	done
	iconutil -c icns build/koba.iconset -o $(APP)/Contents/Resources/koba.icns
	rsync -a --delete $(GHOSTTY_OUT)/share/ghostty/ $(APP)/Contents/Resources/ghostty/
	rsync -a --delete $(GHOSTTY_OUT)/share/terminfo/ $(APP)/Contents/Resources/terminfo/
	clang $(CFLAGS) $(SRCS) $(LDFLAGS) -o $(BIN)
	codesign --force --sign - $(APP)

$(HERDR_BIN): $(HERDR_SRCS) $(HERDR_HDRS) resources/Herdr-Info.plist resources/herdr-icon.png \
		resources/herdr.ghostty $(HERDR_SCRIPTS) $(LIBGHOSTTY)
	mkdir -p $(HERDR_APP)/Contents/MacOS $(HERDR_APP)/Contents/Resources/scripts
	cp resources/Herdr-Info.plist $(HERDR_APP)/Contents/Info.plist
	cp resources/herdr.ghostty $(HERDR_APP)/Contents/Resources/herdr.ghostty
	cp $(HERDR_SCRIPTS) $(HERDR_APP)/Contents/Resources/scripts/
	mkdir -p build/herdr.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s resources/herdr-icon.png \
			--out build/herdr.iconset/icon_$${s}x$${s}.png > /dev/null; \
		sips -z $$((s * 2)) $$((s * 2)) resources/herdr-icon.png \
			--out build/herdr.iconset/icon_$${s}x$${s}@2x.png > /dev/null; \
	done
	iconutil -c icns build/herdr.iconset -o $(HERDR_APP)/Contents/Resources/herdr.icns
	rsync -a --delete $(GHOSTTY_OUT)/share/ghostty/ $(HERDR_APP)/Contents/Resources/ghostty/
	rsync -a --delete $(GHOSTTY_OUT)/share/terminfo/ $(HERDR_APP)/Contents/Resources/terminfo/
	clang $(CFLAGS) $(HERDR_SRCS) $(LDFLAGS) -framework WebKit -o $(HERDR_BIN)
	codesign --force --sign - $(HERDR_APP)

clean:
	rm -rf build

clean-all: clean
	rm -rf vendor
