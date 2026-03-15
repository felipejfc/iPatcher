#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/iPatcher.app"
TWEAK_DYLIB="$BUILD_DIR/iPatcher.dylib"
HELPER_BIN="$BUILD_DIR/ipatcher-helper"
FILTER_PLIST="$ROOT_DIR/iPatcherTweak/iPatcher.plist"
IPA_OUT="$BUILD_DIR/iPatcher.ipa"

# ---------------------------------------------------------------------------
# Verify build artifacts exist
# ---------------------------------------------------------------------------
for f in "$TWEAK_DYLIB" "$HELPER_BIN"; do
    [ -f "$f" ] || { echo "ERROR: $(basename "$f") not found. Run 'make' first."; exit 1; }
done
[ -d "$APP_DIR" ] || { echo "ERROR: iPatcher.app not found. Run 'make app' first."; exit 1; }

# ---------------------------------------------------------------------------
# Embed tweak payload inside the .app bundle
# ---------------------------------------------------------------------------
echo "==> Embedding tweak in app bundle..."
PAYLOAD_DIR="$APP_DIR/TweakPayload"
mkdir -p "$PAYLOAD_DIR"

cp "$TWEAK_DYLIB"  "$PAYLOAD_DIR/iPatcher.dylib"
cp "$FILTER_PLIST" "$PAYLOAD_DIR/iPatcher.plist"
cp "$HELPER_BIN"   "$PAYLOAD_DIR/ipatcher-helper"

echo "    iPatcher.dylib + iPatcher.plist + ipatcher-helper"

# ---------------------------------------------------------------------------
# Package as IPA
# ---------------------------------------------------------------------------
echo "==> Creating IPA..."
STAGE_DIR="$BUILD_DIR/_ipa_stage"
rm -rf "$STAGE_DIR" "$IPA_OUT"
mkdir -p "$STAGE_DIR/Payload"

cp -a "$APP_DIR" "$STAGE_DIR/Payload/"

cd "$STAGE_DIR"
zip -qr "$IPA_OUT" Payload/

rm -rf "$STAGE_DIR"

IPA_SIZE=$(du -h "$IPA_OUT" | cut -f1)
echo ""
echo "==> Done! $IPA_OUT ($IPA_SIZE)"
echo ""
echo "    Install via TrollStore, Filza, or sideload."
echo "    Then open iPatcher → Settings → Install Tweak → Respring."
echo ""
echo "    First-run setup (SSH as root):"
echo "      ssh root@<device> 'bash -s' < scripts/setup_helper.sh"
