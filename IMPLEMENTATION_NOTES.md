# Local implementation handoff

The local implementation sets the Debian version to exactly `1.5.5~b1` and implements configured-first lists, the two opt-in App Options, icon tags, both Open in Choicy shortcut paths and their Settings receiver, and the three-package workflow.

No commits, tags, pushes, workflow dispatches, package builds, installs, or device tests were performed. The local snapshot has no `.git` metadata and its two submodule directories are empty.

## Files changed

| Area | Files |
| --- | --- |
| Shared saved-rule predicate, one-shot route request, and path compatibility | `Shared.h`, `Shared.m`, `ChoicyRoot.h` (new), `Tweak.c` |
| Application ordering and refresh | `ChoicyPrefs/CHPApplicationListSubcontrollerController.m`, `ChoicyPrefs/CHPPreferences.h` |
| Daemon ordering and discovery completion | `ChoicyPrefs/CHPDaemonListController.m`, `ChoicyPrefs/CHPDaemonList.m` |
| Settings route and detail return | `ChoicyPrefs/CHPRootListController.m`, `ChoicyPrefs/CHPProcessConfigurationListController.m`, `ChoicyPrefs/entry.plist` |
| Options and English fallback strings | `ChoicyPrefs/Resources/Root.plist`, `layout/Library/Application Support/Choicy.bundle/en.lproj/Localizable.strings` |
| Native RootHide path access | `ChoicyPrefs/CHPPackageInfo.m`, `ChoicyPrefs/CHPTweakList.m` |
| SpringBoard tags, shortcuts, and reload | `ChoicySB/SpringBoard.h`, `ChoicySB/SpringBoard.x`, `ChoicySB/Tweak.x`, `ChoicySB/ChoicySB.h` |
| Build settings and package version | `Makefile`, `ChoicyPrefs/Makefile`, `ChoicySB/Makefile`, `control` |
| CI | `.github/workflows/build.yml` (new), `.github/scripts/verify-package.py` (new) |
| Handoff | `IMPLEMENTATION_NOTES.md` (new) |

## Source and API review

- Checked the plan's file references against the local source. Preserved the existing Disabled, Custom, and Global Overwrite preview implementation and the older Crane class method. The bundle version and preferences migration version remain unchanged.
- Reviewed AltList's inherited specifiers and routing IDs at [1.0.4](https://github.com/opa334/AltList/blob/19ec927b61bfa723a41ec38d6722d0ac69d35223/ATLApplicationListControllerBase.m) and the [1.0.11 CI pin](https://github.com/opa334/AltList/blob/9db09f92eff0404ae7fa9c2fe6c25ba13d5e02d7/ATLApplicationListControllerBase.m). Ordering replaces the displayed `_specifiers` after AltList applies its current query, leaving its unfiltered cache intact. The configured Visible/Hidden arrangement does not enable alphabetic indexing.
- Reviewed [PreferenceLoader's controller construction](https://github.com/rpetrich/PreferenceLoader/blob/master/prefs.xm). The installed entry ID is `ChoicyPrefs`; the Applications ID is `Applications`; app rows use their bundle IDs. The encoded URL requests `Applications/<bundle-id>`. A separate, locked, 60-second one-shot request lets the root controller open the detail controller independently of dynamic app rows and active search. Warm activation and repeated selections are handled by that receiver.
- Reviewed the [native RootHide API guidance](https://github.com/roothide/Developer), [package architecture rule](https://github.com/roothide/theos/blob/958fea4f779943505b15b93c88bb4db8d97b346d/vendor/mod/roothide/package/deb.mk), and [framework install-name rule](https://github.com/roothide/theos/blob/958fea4f779943505b15b93c88bb4db8d97b346d/vendor/mod/roothide/instance/framework.mk). Native Roothide stages under `/Library`, uses `iphoneos-arm64e`, and links through `.jbroot`. Its headers reject the old top-level libroot include, so `ChoicyRoot.h` selects its native `jbroot` API. Other schemes retain libroot.
- The workflow pins Theos and its recursive submodules, AltList, checkout/upload actions, and SDK/ldid downloads. The SDK and ldid SHA-256 values were calculated from the versioned official release downloads. The Rootful compiler archive is pinned by the owner's dispatch SHA-256.

## Local checks completed

- Parsed both changed XML plists with Python `plistlib`.
- Parsed the English strings entries, checked duplicate keys and escapes, and asserted the exact requested labels and two-paragraph footer.
- Parsed the workflow YAML with project-local PyYAML 6.0.3; checked dispatch-only triggering, required compiler inputs, read-only repository permissions, immutable action/toolchain references, and all three matrix rows.
- Ran actionlint 1.7.12 successfully with ShellCheck and Pyflakes integration disabled. Bash commands were reviewed statically; no shell execution of build steps occurred.
- Parsed `.github/scripts/verify-package.py` with Python's AST parser.
- Cross-checked the shared predicate's two flags, false defaults, both shortcut builders and consumed activation branches, detail receiver, snapshot-only icon layout, exported targets, and the three literal leading spaces in the installed Choicy filenames.
- Compared the changed files with a local original snapshot and ran `git diff --no-index --check` without persistent Git configuration changes; no whitespace errors were found.

Objective-C/Logos compilation and package verification were not run locally. Those require the CI toolchains and the real recursive source checkout. Temporary downloaded references and check tools are removed after review.

## Manual CI checks

Dispatch `Build Choicy packages` with:

- `xcode11_archive_url`: an HTTPS URL accessible to the runner without interactive authentication. Supply a tar archive, optionally gzip/xz compressed, containing exactly one complete `.xctoolchain` directory extracted from Xcode 11.7. Include its `usr/bin`, compiler libraries, and `usr/lib/arc/libarclite_iphoneos.a`.
- `xcode11_archive_sha256`: the archive's 64-character SHA-256. The job verifies it before extracting and renames the toolchain directory to `$THEOS/toolchain/Xcode11.xctoolchain`.

Confirm the current `macos-15-intel` image still supplies Xcode 16.4, the recursive source checkout resolves both submodules, and all three jobs finish. Each job builds a matching AltList development framework and calls `make package FINALPACKAGE=1` once for Choicy. The package verifier checks metadata and payload before copying and uploading one file.

| Label | Expected architecture | Downloadable file |
| --- | --- | --- |
| Rootless | `iphoneos-arm64` | `Choicy_1.5.5~b1_Rootless.deb` |
| Roothide | `iphoneos-arm64e` | `Choicy_1.5.5~b1_Roothide.deb` |
| Rootful | `iphoneos-arm` | `Choicy_1.5.5~b1_Rootful.deb` |

Inspect and install each package in its matching environment. CI verifies `/var/jb/Library/...` for Rootless and `/Library/...` for native Roothide and Rootful; Roothide also requires native `.jbroot`/libroothide linkage in the packaged images. The verifier has not yet been exercised against real build output.

## Manual device checks and compatibility assumptions

- Test fresh installation, upgrade, first preference write, and reset. Both new switches default off. Configure, disable, and clear apps and daemons; verify ordering after returning from details and after reload. Check name/ID search, Visible/Hidden apps, both daemon modes, duplicate prevention, and row identity. Global Overwrite alone, stale allow/deny lists, detail visits, and one-time launches must not promote an entry.
- Enable tags and change rules; test Home Screen pages, folders, Dock, icon reassignment/reuse, icon scaling, and switch-off/reset without respring. Confirm one grey dot stays inside the icon's bottom-right, preserves system indicators, and never appears on folders, widgets, or web clips. The guarded private icon-model/image-view selectors and their geometry require confirmation on each supported iOS generation and with icon customization tweaks.
- On iOS 10-12 and iOS 13+, test stock and third-party apps, including apps with no original shortcuts and with both launch options disabled. Open cold Settings, warm Settings showing a different app, and an active app search. Open two apps rapidly and the same app repeatedly. Confirm the exact app detail appears, the source app is not terminated by Open in Choicy, menu dismissal completes, and existing launch/system actions still work. Root-only navigation for an installed app fails acceptance.
- Verify removed-app and expired-request behavior. Confirm Settings can read/consume SpringBoard's separate pending request and that each supported PreferenceLoader/Settings version accepts the registered root URL. Private URL traversal, legacy force-touch dismissal, and split-view Settings navigation remain device assumptions.
- Confirm native RootHide file access, tweak discovery, and runtime dependency resolution on a device. CI layout/linkage checks do not establish runtime compatibility.
- Rootful deliberately retains Xcode 11's legacy arm64e ABI for iOS 12-13 and the armv7/arm64 slices for older supported devices, including iOS 10. Confirm this matches the intended Rootful device matrix; that arm64e slice does not provide the newer iOS 14+ arm64e ABI. See [Theos arm64e deployment guidance](https://theos.dev/docs/arm64e-deployment). The supplied Xcode 11 compiler also needs its first real execution on the selected CI runner.
