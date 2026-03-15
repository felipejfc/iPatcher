LeanTweakLoader
================

Small runtime tweak loader for the vphone guest.

Purpose
- Satisfy the `/var/jb/usr/lib/TweakLoader.dylib` path expected by the vphone
  basebin runtime (`systemhook.dylib`).
- Enumerate standard rootless tweak files from
  `/var/jb/Library/MobileSubstrate/DynamicLibraries`.
- Apply basic substrate-style bundle / executable filters and `dlopen` the
  matching tweak dylibs into the current process.

Scope
- This is intentionally minimal. It is not a full jailbreak runtime and does
  not implement hook APIs.
- It only loads already-built tweak dylibs that rely on their own constructors.
- Current filter support is limited to:
  - `Filter.Bundles`
  - `Filter.Executables`

Logging
- Appends loader events to:
  `/var/jb/var/mobile/Library/iPatcher/tweakloader.log`
