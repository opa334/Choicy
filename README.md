# ChoySee

A forked (enhanced) version of Choicy, an advanced tweak configurator!

## Features

- Disable tweak injection individually for every process
- Configure each tweak dylib individually for every process
- Disable tweaks globally (with the ability to set exceptions for individual processes)
- Option for an application shortcut to launch the application with or without tweaks once
- **NEW** - Option for an application shortcut to launch injection settings for that app.
- **NEW** - Option to add grey dot to app icons that have custom / blocked injection. 

## Install Choicy on iOS 15+

1. Download the deb file matching your jailbreak environment from the [latest release](https://github.com/EolnMsuk/ChoySee/releases).
2. Open it with Sileo or Zebra and install.

| Verified output | Firmware dependency | Filename |
| --- | --- | --- |
| GitHub Rootless | `>= 15.0` | `Choicy_1.5.5~b3_Rootless.deb` |
| GitHub native Roothide | `>= 15.0` | `Choicy_1.5.5~b3_Roothide.deb` |
| GitHub Rootful | `>= 15.0` | `Choicy_1.5.5~b3_Rootful.deb` |
| Local Legacy Rootful | `>= 10.0` | `Choicy_1.5.5~b3_Rootful_Legacy_iOS10.deb` |

---

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

## Credit
- [oppa334 - Choicy](https://github.com/opa334/Choicy) - [Support oppa334](opa334.github.io/donate.html)
- [EolnMsuk - ChoySee](https://github.com/EolnMsuk/ChoySee) - [Support EolnMsuk](https://venmo.com/u/RustOnRails/)
