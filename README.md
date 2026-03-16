<p align="center">
  <img src="icon.png" width="128" height="128" alt="iPatcher icon">
</p>

# iPatcher

iPatcher is a rootless iOS runtime patcher for `/var/jb`-style environments. It provides a SwiftUI app for defining per-app byte patches, a tweak that applies those patches at process startup, a minimal runtime loader, a privileged helper for install operations, and a CLI for debugging the same workflow over SSH.

The project is aimed at environments where tweak-style dynamic libraries are loaded from a rootless filesystem layout rather than a traditional full jailbreak setup.

## Overview

iPatcher is split into a few small components:

- `iPatcherApp`
  The user-facing SwiftUI app. It discovers installed apps, lets you create patch profiles, toggles profiles on and off, and shows logs.
- `iPatcherTweak`
  The runtime patch engine. It loads the patch profile for the current bundle ID, scans the main executable for each pattern, and writes replacement bytes into memory.
- `LeanTweakLoader`
  A minimal loader that satisfies environments expecting `/var/jb/usr/lib/TweakLoader.dylib` and loads tweak dylibs based on simple substrate-style filters.
- `iPatcherHelper`
  A setuid root helper used by the app and CLI for tweak install, uninstall, and respring actions.
- `iPatcherCLI`
  A small on-device command-line tool that mirrors the major app operations and is useful for debugging.
- `FixtureApp`
  A small test target used to validate the patch pipeline end to end.

## Features

- Per-app patch profiles stored as JSON
- Hex pattern matching with `??` wildcard support
- Runtime patching of the target app’s main executable
- Rootless `/var/jb` package layout
- In-app tweak install and uninstall flow
- Respring support after install changes
- Aggregated logs for the app, tweak, and loader
- Fixture app for repeatable validation

## Compatibility

### Device/runtime

- iOS 15.0 or later
- `arm64`
- `arm64e`
- Rootless environment with writable `/var/jb`
- Runtime capable of loading tweak dylibs from `/var/jb/Library/MobileSubstrate/DynamicLibraries`

The package metadata currently declares `firmware (>= 15.0)`.

### Build host

- macOS
- Xcode command line tools or full Xcode
- iPhoneOS SDK available through `xcrun`

This repository does not use Theos. It builds directly with `clang`, `swiftc`, `codesign`, and shell packaging scripts.

## Dependencies

### Required on the build machine

- `xcrun`
- `clang`
- `swiftc`
- `codesign`
- `zip`
- `tar`
- `ar`

### Optional on the build machine

- `dpkg-deb`

If `dpkg-deb` is not available, the DEB packaging script falls back to manual archive assembly.

### Expected on the device

- `ldid` at `/var/jb/usr/bin/ldid` to re-sign the installed tweak dylib
- Root access once to install the helper with `root:wheel` ownership and mode `4755`

## How It Works

Patch profiles are stored under:

```text
/var/jb/var/mobile/Library/iPatcher/patches
```

Each profile is keyed by bundle ID and contains one or more patch entries. At app launch:

1. The tweak determines the current bundle ID.
2. It loads the JSON profile for that bundle ID.
3. Disabled profiles or entries are skipped.
4. Each enabled pattern is scanned in the main executable image.
5. Matching locations are patched in memory using the replacement bytes and configured offset.

The tweak intentionally skips patching `com.ipatcher.app` itself.

## Patch Format

The app stores additional metadata, but the runtime-relevant payload looks like this:

```json
{
  "bundleID": "com.example.target",
  "enabled": true,
  "patches": [
    {
      "name": "Example patch",
      "enabled": true,
      "pattern": "f4 4f ?? a9",
      "replacement": "00 00 80 d2",
      "offset": 0
    }
  ]
}
```

Rules:

- `pattern` is a space-separated list of hex bytes
- `??` matches any byte
- `replacement` is written verbatim
- `offset` is applied relative to the match start

## Building

Build everything:

```sh
make
```

Build individual targets:

```sh
make tweak
make loader
make helper
make cli
make app
```

Build deliverables:

```sh
make ipa
make deb
```

Clean generated outputs:

```sh
make clean
```

All artifacts are written to `build/`.

## Build Outputs

- `build/iPatcher.dylib`
- `build/TweakLoader.dylib`
- `build/ipatcher-helper`
- `build/ipatcher-cli`
- `build/iPatcher.app`
- `build/iPatcher.ipa`
- `build/com.ipatcher.app.deb`

## How to Use

### IPA workflow

Build the IPA:

```sh
make ipa
```

Install:

- Install `build/iPatcher.ipa` with TrollStore, Filza, or your preferred sideload path

One-time helper setup:

```sh
ssh root@<device> 'bash -s' < scripts/setup_helper.sh
```

Then on the device:

1. Open `iPatcher`
2. Go to `Settings`
3. Verify helper status
4. Install the tweak
5. Respring when prompted
6. Open `Apps`
7. Pick a target app
8. Create or import a patch profile
9. Launch the target app

### DEB workflow

Build the package:

```sh
make deb
```

Install:

```sh
dpkg -i com.ipatcher.app.deb && uicache -a
```

The DEB installs:

- The app bundle at `/var/jb/Applications/iPatcher.app`
- The tweak at `/var/jb/Library/MobileSubstrate/DynamicLibraries/iPatcher.dylib`
- The filter plist at `/var/jb/Library/MobileSubstrate/DynamicLibraries/iPatcher.plist`
- The helper at `/var/jb/usr/local/libexec/ipatcher-helper`
- The loader at `/var/jb/usr/lib/TweakLoader.dylib`
- The CLI at `/var/jb/usr/local/bin/ipatcher-cli`
- The patch storage directory at `/var/jb/var/mobile/Library/iPatcher/patches`

## CLI Usage

The CLI mirrors the same install and diagnostic flows used by the app.

Examples:

```sh
ipatcher-cli status
ipatcher-cli install
ipatcher-cli uninstall
ipatcher-cli respring
ipatcher-cli apps
ipatcher-cli apps --all
ipatcher-cli patches
ipatcher-cli patches com.example.target
ipatcher-cli helper-test
```

To run it as the mobile user:

```sh
su mobile -c '/var/jb/usr/local/bin/ipatcher-cli status'
```

## Logs

Runtime logs are written to:

- `/var/jb/var/mobile/Library/iPatcher/app.log`
- `/var/jb/var/mobile/Library/iPatcher/tweak.log`
- `/var/jb/var/mobile/Library/iPatcher/tweakloader.log`

The app log viewer aggregates those sources into one screen.

## Repository Layout

- [iPatcherApp](/Users/felipejfc/dev/RE/iPatcher/iPatcherApp)
- [iPatcherTweak](/Users/felipejfc/dev/RE/iPatcher/iPatcherTweak)
- [LeanTweakLoader](/Users/felipejfc/dev/RE/iPatcher/LeanTweakLoader)
- [iPatcherHelper](/Users/felipejfc/dev/RE/iPatcher/iPatcherHelper)
- [iPatcherCLI](/Users/felipejfc/dev/RE/iPatcher/iPatcherCLI)
- [FixtureApp](/Users/felipejfc/dev/RE/iPatcher/FixtureApp)
- [scripts](/Users/felipejfc/dev/RE/iPatcher/scripts)
- [Makefile](/Users/felipejfc/dev/RE/iPatcher/Makefile)

## Troubleshooting

If installation succeeds but patching does not work, check:

- `/var/jb/usr/local/libexec/ipatcher-helper` exists
- The helper is executable
- The helper is owned by `root:wheel`
- The helper has mode `4755`
- `/var/jb/Library/MobileSubstrate/DynamicLibraries/iPatcher.dylib` exists
- `/var/jb/Library/MobileSubstrate/DynamicLibraries/iPatcher.plist` exists
- `ldid` is available on the device
- The patch JSON filename matches the target bundle ID
- The profile is enabled
- The individual patch entries are enabled
- The target pattern actually exists in the app’s main executable

If the loader is present but the tweak is not applied, inspect:

- `/var/jb/var/mobile/Library/iPatcher/tweakloader.log`
- `/var/jb/var/mobile/Library/iPatcher/tweak.log`

## Fixture App

The fixture app is included to validate the patch flow against a controlled target.

Build it with:

```sh
bash FixtureApp/scripts/build_fixture_ipa.sh
```

This produces:

```text
build/iPatcherFixture.ipa
```

## Notes

- `LeanTweakLoader` is intentionally minimal. It is a loader, not a full substrate-compatible runtime.
- Current loader filter support is limited to basic bundle and executable filters.
- The whole project is designed around a rootless `/var/jb` layout.
