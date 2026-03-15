#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/iPatcher.app"
TWEAK_DYLIB="$BUILD_DIR/iPatcher.dylib"
LOADER_DYLIB="$BUILD_DIR/TweakLoader.dylib"
HELPER_BIN="$BUILD_DIR/ipatcher-helper"
CLI_BIN="$BUILD_DIR/ipatcher-cli"
FILTER_PLIST="$ROOT_DIR/iPatcherTweak/iPatcher.plist"

# Verify artifacts
for f in "$TWEAK_DYLIB" "$LOADER_DYLIB" "$HELPER_BIN" "$CLI_BIN"; do
    [ -f "$f" ] || { echo "ERROR: $(basename "$f") not found. Run 'make' first."; exit 1; }
done
[ -d "$APP_DIR" ] || { echo "ERROR: iPatcher.app not found. Run 'make app' first."; exit 1; }

# ---------------------------------------------------------------------------
# Stage the .deb filesystem layout (rootless: everything under /var/jb)
# ---------------------------------------------------------------------------
STAGE="$BUILD_DIR/_deb_stage"
rm -rf "$STAGE"

# DEBIAN metadata
mkdir -p "$STAGE/DEBIAN"
cp "$ROOT_DIR/control" "$STAGE/DEBIAN/control"
cp "$ROOT_DIR/scripts/postinst" "$STAGE/DEBIAN/postinst"
chmod 755 "$STAGE/DEBIAN/postinst"

# App bundle → /var/jb/Applications/iPatcher.app/
APP_DEST="$STAGE/var/jb/Applications/iPatcher.app"
mkdir -p "$APP_DEST"
cp -a "$APP_DIR"/* "$APP_DEST/"

# Embed tweak payload in the app bundle
PAYLOAD="$APP_DEST/TweakPayload"
mkdir -p "$PAYLOAD"
cp "$TWEAK_DYLIB"  "$PAYLOAD/iPatcher.dylib"
cp "$FILTER_PLIST" "$PAYLOAD/iPatcher.plist"

# Tweak → /var/jb/Library/MobileSubstrate/DynamicLibraries/
SUBSTRATE="$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$SUBSTRATE"
cp "$TWEAK_DYLIB"  "$SUBSTRATE/iPatcher.dylib"
cp "$FILTER_PLIST" "$SUBSTRATE/iPatcher.plist"

# Root helper → /var/jb/usr/local/libexec/ (postinst sets setuid)
LIBEXEC="$STAGE/var/jb/usr/local/libexec"
mkdir -p "$LIBEXEC"
cp "$HELPER_BIN" "$LIBEXEC/ipatcher-helper"

# Runtime tweak loader expected by the vphone basebin hooks
USR_LIB="$STAGE/var/jb/usr/lib"
mkdir -p "$USR_LIB"
cp "$LOADER_DYLIB" "$USR_LIB/TweakLoader.dylib"

# CLI tool → /var/jb/usr/local/bin/
BINDIR="$STAGE/var/jb/usr/local/bin"
mkdir -p "$BINDIR"
cp "$CLI_BIN" "$BINDIR/ipatcher-cli"

# Patch storage directory
mkdir -p "$STAGE/var/jb/var/mobile/Library/iPatcher/patches"

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------
DEB_OUT="$BUILD_DIR/com.ipatcher.app.deb"
rm -f "$DEB_OUT"

# Use dpkg-deb if available, otherwise fall back to ar+tar
if command -v dpkg-deb &>/dev/null; then
    dpkg-deb -Zxz --root-owner-group -b "$STAGE" "$DEB_OUT"
else
    echo "==> dpkg-deb not found, building manually..."
    TMPWORK="$BUILD_DIR/_deb_work"
    rm -rf "$TMPWORK"
    mkdir -p "$TMPWORK"

    # data.tar.xz — everything except DEBIAN/
    cd "$STAGE"
    tar -cJf "$TMPWORK/data.tar.xz" --exclude='DEBIAN' .

    # control.tar.xz
    cd "$STAGE/DEBIAN"
    tar -cJf "$TMPWORK/control.tar.xz" .

    # debian-binary
    echo "2.0" > "$TMPWORK/debian-binary"

    # Assemble .deb (ar archive, no symdef)
    cd "$TMPWORK"
    ar rc "$DEB_OUT" debian-binary control.tar.xz data.tar.xz

    rm -rf "$TMPWORK"
fi

rm -rf "$STAGE"

DEB_SIZE=$(du -h "$DEB_OUT" | cut -f1)
echo ""
echo "==> Done! $DEB_OUT ($DEB_SIZE)"
echo ""
echo "    Install via Sileo, Filza, or SSH:"
echo "      dpkg -i com.ipatcher.app.deb && uicache -a"
