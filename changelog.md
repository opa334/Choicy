# v1.5.5~b3

## Release notes

- Configured apps and daemons appear first and the lists refresh when settings change. An entry qualifies when tweak injection is disabled or custom tweak rules are enabled. Saving an inactive rule list leaves the entry in its regular section.
- **Tag Custom Apps** puts a small grey dot at the bottom-right of configured app icons. The dot updates as settings and icon views change. **Open in Choicy** opens that app's Choicy settings from the Home Screen without changing injection preferences or terminating the app.
- **Choicy > App Options** now shows **Tag Custom Apps**, **"Open in Choicy" Option**, **"Launch Without Tweaks" Option**, and **"Launch With Tweaks" Option**, in that order. On a fresh install and after **Reset Preferences**, the first two are enabled and both launch options are disabled. Explicitly saved choices survive upgrades and reloads. Missing keys use the new defaults. Reset clears saved rules and immediately refreshes the visible switches.
- The Home Screen menu preserves the order of existing app and system shortcuts and adds one copy of each applicable Choicy entry. Open in Choicy precedes the applicable one-time launch shortcut when enabled. Its navigation waits for menu dismissal, handles cold and warm Settings, and builds the Back path through Applications and Choicy. A newer tap supersedes earlier requests, and one-use requests expire.
- Preference and list updates use the main thread where needed, with safer observer cleanup and handling of missing app or daemon dictionaries. The new labels and footer text are in English and use the existing localization fallback.
- The modern workflow builds and labels Rootless, native Roothide, and Rootful packages for iOS 15+. Native Roothide uses its own path and linkage support. Compared with the v1.5.4 build target, modern Rootful starts at iOS 15.0 and ships 64-bit slices.
- The separate opt-in Legacy Rootful command targets iOS 10.0 with `armv7` and `arm64`, plus old-ABI `arm64e` from iOS 12.0. Its package has its own filename and firmware dependency. The 32-bit pointer scan now visits every slot in the table. Use the modern packages for iOS 15+.

## Expected b3 packages

The modern workflow uses SDK 16.5 and Xcode 16.4. The Legacy Rootful profile uses a prepared Xcode 11.7 toolchain, patched SDK 13.7, and a separate Clang to generate tail-call assembly.

| Profile | Firmware dependency | Mach-O slices | Debian architecture | Filename |
| --- | --- | --- | --- | --- |
| Rootless | `>= 15.0` | `arm64 arm64e` | `iphoneos-arm64` | `Choicy_1.5.5~b3_Rootless.deb` |
| Native Roothide | `>= 15.0` | `arm64 arm64e` | `iphoneos-arm64e` | `Choicy_1.5.5~b3_Roothide.deb` |
| Rootful | `>= 15.0` | `arm64 arm64e` | `iphoneos-arm` | `Choicy_1.5.5~b3_Rootful.deb` |
| Legacy Rootful | `>= 10.0` | `armv7 arm64 arm64e` with old arm64e ABI and iOS 12.0 floor on that slice | `iphoneos-arm` | `Choicy_1.5.5~b3_Rootful_Legacy_iOS10.deb` |

## File inventory

### Added

| File | Reason |
| --- | --- |
| `.github/scripts/verify-package.py` | Check modern metadata, firmware, payload paths, Mach-O slices, and native Roothide linkage before labeling artifacts. Expect b3. |
| `.github/workflows/build.yml` | Build, verify, and upload the three modern schemes with pinned toolchain and development inputs. |
| `ChoicyRoot.h` | Share the native Roothide and libroot path interfaces across targets. |
| `changelog.md` | Summarize the b3 release and inventory the net changes from v1.5.4. |
| `control.legacy` | Give Legacy Rootful a separate b3 control file with the iOS 10.0 firmware minimum and the same Choicy identity and runtime dependencies. |
| `legacy_build.sh` | Validate prepared inputs and explicitly select, clean, generate, build, and verify the local Legacy Rootful profile. |
| `scripts/legacy-clang.sh` | Check the SDK Theos resolved and apply the iOS 12.0 arm64e floor to legacy compiler and link calls. |
| `scripts/package-legacy.py` | Check development inputs, package the Theos stage with legacy metadata and gzip, and publish only after payload, Mach-O, and signature verification. |

### Modified

| File | Reason |
| --- | --- |
| `.gitignore` | Ignore the legacy artifact and scratch directory. |
| `ChoicyPrefs/CHPApplicationListSubcontrollerController.m` | List configured apps first and refresh after preference changes while preserving AltList search and sections. |
| `ChoicyPrefs/CHPDaemonList.m` | Resolve Rootful and jailbreak paths through the shared wrapper and deliver observer updates on the main thread. |
| `ChoicyPrefs/CHPDaemonListController.m` | List configured daemons first and manage refresh and observer cleanup. |
| `ChoicyPrefs/CHPPackageInfo.m` | Use the shared path wrapper for package lookup. |
| `ChoicyPrefs/CHPPreferences.h` | Expose the Settings preference reload function to controllers. |
| `ChoicyPrefs/CHPProcessConfigurationListController.m` | Call the parent disappearance method and check a previously displayed row before reloading it. |
| `ChoicyPrefs/CHPRootListController.m` | Deliver main-thread preference updates, route one-use requests with a Back stack, use jailbreak paths, and refresh switches immediately after reset. |
| `ChoicyPrefs/CHPTweakList.m` | Search translated jailbreak tweak paths and retain existing fallbacks. |
| `ChoicyPrefs/Makefile` | Link native Roothide, adjust one LiteHook warning, and quote staging paths. |
| `ChoicyPrefs/Resources/Root.plist` | Identify the Applications route, add the two optional features and footer, and set the App Options order and defaults. |
| `ChoicyPrefs/entry.plist` | Give PreferenceLoader a stable `ChoicyPrefs` routing ID. |
| `ChoicySB/ChoicySB.h` | Expose the icon tag refresh function. |
| `ChoicySB/Makefile` | Link UIKit and QuartzCore for icon tags and use native Roothide libraries for that scheme. |
| `ChoicySB/SpringBoard.h` | Declare the icon, shortcut dismissal, and Settings opening interfaces. |
| `ChoicySB/SpringBoard.x` | Add icon dots and the Open in Choicy shortcut for both menu paths, translate resource paths, and honor the App Options fallbacks and saved choices. |
| `ChoicySB/Tweak.x` | Reload on the main thread in SpringBoard, validate app dictionaries, type the notification callback, and refresh icon tags. |
| `Makefile` | Export modern SDK, deployment and slices, select direct hook compilation or legacy assembly, and route legacy stage output to its isolated packager. Keep native Roothide linkage and the focused LiteHook warning adjustment. |
| `README.md` | Describe modern and legacy builds, prepared inputs, scope, and expected artifacts. |
| `Shared.h` | Declare configured-state and request interfaces, keys and routing constants, and shared jailbreak paths. |
| `Shared.m` | Check process preference dictionaries, detect configured state, and manage locked, expiring one-use requests. |
| `Tweak.c` | Use the shared jailbreak path interface and make pointer conversions and section iteration work at either pointer width. |
| `Tweak.s` | Select and check only the matching generated hook assembly, with an error for unsupported architectures. |
| `control` | Set release b3 and require iOS 15.0 for the modern packages. |
| `gen.c` | Document direct compilation and legacy assembly generation from the same hook bodies. |
| `gen_asm.sh` | Generate the legacy slices using explicit compiler, SDK, deployment, and ABI settings with fail-fast publication. |
| `layout/Library/Application Support/Choicy.bundle/en.lproj/Localizable.strings` | Supply English labels for the new options, Configured section, and App Options footer. |
| `release_build.sh` | Use a valid shell header and explicitly build all three modern schemes, including native Roothide. |
