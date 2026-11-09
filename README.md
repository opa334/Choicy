# ChoySee

A forked (enhanced) version of Choicy, an advanced tweak configurator!

## Features

- Disable tweak injection individually for every process
- Configure each tweak dylib individually for every process
- Disable tweaks globally (with the ability to set exceptions for individual processes)
- Option for an application shortcut to launch the application with or without tweaks once
- **NEW** Option for an application shortcut to launch injection settings for that app.
- **NEW** Option to add grey dot to app icons that have custom / blocked injection. 

## Building Choicy 1.5.5~b3

The default Theos target uses SDK 16.5 and iOS 15.0 with `arm64` and `arm64e`. An empty package scheme selects modern Rootful. The **Build Choicy packages** GitHub workflow uses Xcode 16.4 to build and verify all three modern schemes. On a prepared modern build host, `sh ./release_build.sh` builds the same schemes using RootHide Theos and matching AltList development frameworks.

### Legacy Rootful on a prepared macOS host

Select this profile explicitly when targeting older Rootful jailbreaks. The shared sources target iOS 10.0 on `armv7` and `arm64`, and iOS 12.0 on old-ABI `arm64e`.

From the project root, with `THEOS_PACKAGE_SCHEME` unset or empty, run the following with local paths to the prepared tools.

```sh
THEOS=/absolute/path/to/prepared/theos \
LEGACY_PREFIX=/absolute/path/to/Xcode11.7.xctoolchain/usr/bin/ \
LEGACY_SDKROOT=/absolute/path/to/prepared/theos/sdks/iPhoneOS13.7.sdk \
GEN_CLANG=/absolute/path/to/musttail-capable/clang \
sh ./legacy_build.sh
```

Prepare GNU Make, Python 3.9+, `dpkg-deb` with `--root-owner-group` and `--uniform-compression`, `ldid`, `lipo`, `otool`, `codesign`, and `ar`. Use the patched SDK 13.7, the LiteHook and ChOma sources, compatible Theos/SDK headers and stubs, and Rootful development files for AltList, Substrate, and libroot. AltList and libroot must cover the legacy slices and deployment versions. The modern CI AltList framework targets iOS 15 and has only modern 64-bit slices. The separate generator must accept `musttail` for all three slices and `-fno-ptrauth-abi-version` for arm64e. Record the generator version that successfully assembles and links with the prepared Xcode 11.7 tools.

The helper cleans, regenerates the hooks, and stages and verifies the legacy package locally. Build the profiles sequentially in the same checkout and clean each time you switch. A successful run publishes under `artifacts/legacy/` and atomically replaces an earlier legacy archive of the same version after verification. Both Rootful variants use the Choicy package ID and are alternative installs with the same preferences.

| Verified output | Firmware dependency | Filename |
| --- | --- | --- |
| GitHub Rootless | `>= 15.0` | `Choicy_1.5.5~b3_Rootless.deb` |
| GitHub native Roothide | `>= 15.0` | `Choicy_1.5.5~b3_Roothide.deb` |
| GitHub Rootful | `>= 15.0` | `Choicy_1.5.5~b3_Rootful.deb` |
| Local Legacy Rootful | `>= 10.0` | `Choicy_1.5.5~b3_Rootful_Legacy_iOS10.deb` |
