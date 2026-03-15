#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/FixtureApp"
BUILD_DIR="$ROOT_DIR/build/fixture"
APP_DIR="$BUILD_DIR/iPatcherFixture.app"
APP_BIN="$APP_DIR/iPatcherFixture"
OBJ_OUT="$BUILD_DIR/FixturePatchTarget.o"
IPA_OUT="$ROOT_DIR/build/iPatcherFixture.ipa"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
SWIFTC="$(xcrun --sdk iphoneos -f swiftc)"

mkdir -p "$BUILD_DIR" "$APP_DIR"

"$CC" -isysroot "$SDK" \
    -arch arm64 \
    -miphoneos-version-min=15.0 \
    -c "$FIXTURE_DIR/Sources/FixturePatchTarget.S" \
    -o "$OBJ_OUT"

"$SWIFTC" -sdk "$SDK" \
    -target arm64-apple-ios15.0 \
    -parse-as-library \
    -framework UIKit \
    -framework SwiftUI \
    -framework Foundation \
    -O \
    -o "$APP_BIN" \
    "$FIXTURE_DIR/Sources/FixtureApp.swift" \
    "$OBJ_OUT"

cp "$FIXTURE_DIR/Info.plist" "$APP_DIR/Info.plist"
cp "$ROOT_DIR"/iPatcherApp/Icons/*.png "$APP_DIR"/

codesign --force --sign - \
    --entitlements "$FIXTURE_DIR/entitlements.plist" \
    "$APP_DIR"

STAGE_DIR="$BUILD_DIR/_ipa_stage"
rm -rf "$STAGE_DIR" "$IPA_OUT"
mkdir -p "$STAGE_DIR/Payload"
cp -a "$APP_DIR" "$STAGE_DIR/Payload/"

cd "$STAGE_DIR"
zip -qr "$IPA_OUT" Payload/

rm -rf "$STAGE_DIR"

echo "Built fixture IPA: $IPA_OUT"
