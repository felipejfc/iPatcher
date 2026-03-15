# iPatcher — Xcode-toolchain-only build (no Theos)
# Requirements: Xcode (xcrun, clang, swiftc, codesign)

SDK       := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC        := $(shell xcrun --sdk iphoneos -f clang)
SWIFTC    := $(shell xcrun --sdk iphoneos -f swiftc)
CODESIGN  := codesign
MIN_IOS   := 15.0

BUILD_DIR := build
TWEAK_OUT := $(BUILD_DIR)/iPatcher.dylib
LOADER_OUT:= $(BUILD_DIR)/TweakLoader.dylib
HELPER_OUT:= $(BUILD_DIR)/ipatcher-helper
CLI_OUT   := $(BUILD_DIR)/ipatcher-cli
APP_DIR   := $(BUILD_DIR)/iPatcher.app
APP_BIN   := $(APP_DIR)/iPatcher

# --- Sources ---------------------------------------------------------------
TWEAK_SRC := iPatcherTweak/Tweak.m \
             iPatcherTweak/DebugLog.m \
             iPatcherTweak/PatternScanner.c \
             iPatcherTweak/PatchEngine.m \
             iPatcherTweak/ConfigReader.m \
             iPatcherTweak/MemoryUtils.m

LOADER_SRC := LeanTweakLoader/TweakLoader.m

APP_SRC   := $(wildcard iPatcherApp/Sources/*.swift)

# --- Flags ------------------------------------------------------------------
TWEAK_CFLAGS := -isysroot $(SDK) \
                -arch arm64 -arch arm64e \
                -miphoneos-version-min=$(MIN_IOS) \
                -dynamiclib \
                -fobjc-arc -O3 \
                -framework Foundation \
                -I Shared

HELPER_CFLAGS := -isysroot $(SDK) \
                 -arch arm64 -arch arm64e \
                 -miphoneos-version-min=$(MIN_IOS) \
                 -O2

APP_SWIFTFLAGS := -sdk $(SDK) \
                  -target arm64-apple-ios$(MIN_IOS) \
                  -framework UIKit \
                  -framework SwiftUI \
                  -framework Foundation \
                  -framework UniformTypeIdentifiers \
                  -O

# --- Targets ----------------------------------------------------------------
.PHONY: all tweak loader helper cli app ipa deb clean

all: tweak loader helper cli app

tweak: $(TWEAK_OUT)
loader: $(LOADER_OUT)
helper: $(HELPER_OUT)
cli: $(CLI_OUT)
app: $(APP_BIN)

$(TWEAK_OUT): $(TWEAK_SRC)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(TWEAK_CFLAGS) -o $@ $^
	@echo "==> Built tweak:  $@"

$(LOADER_OUT): $(LOADER_SRC)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(TWEAK_CFLAGS) -o $@ $^
	@echo "==> Built loader: $@"

$(HELPER_OUT): iPatcherHelper/helper.c
	@mkdir -p $(BUILD_DIR)
	$(CC) $(HELPER_CFLAGS) -o $@ $^
	@$(CODESIGN) --force --sign - \
		--entitlements iPatcherApp/entitlements.plist \
		$@
	@echo "==> Built helper: $@"

$(CLI_OUT): iPatcherCLI/cli.m
	@mkdir -p $(BUILD_DIR)
	$(CC) -isysroot $(SDK) \
		-arch arm64 -arch arm64e \
		-miphoneos-version-min=$(MIN_IOS) \
		-fobjc-arc -O2 \
		-framework Foundation \
		-o $@ $^
	@$(CODESIGN) --force --sign - \
		--entitlements iPatcherApp/entitlements.plist \
		$@
	@echo "==> Built CLI:    $@"

$(APP_BIN): $(APP_SRC)
	@mkdir -p $(APP_DIR)
	$(SWIFTC) $(APP_SWIFTFLAGS) -o $@ $^
	@cp iPatcherApp/Info.plist $(APP_DIR)/
	@cp iPatcherApp/entitlements.plist $(APP_DIR)/
	@cp iPatcherApp/Icons/*.png $(APP_DIR)/
	@$(CODESIGN) --force --sign - \
		--entitlements iPatcherApp/entitlements.plist \
		$(APP_DIR)
	@echo "==> Built app:    $(APP_DIR)"

ipa: tweak loader helper app
	@./scripts/build_ipa.sh

deb: tweak loader helper cli app
	@./scripts/build_deb.sh

clean:
	rm -rf $(BUILD_DIR)
