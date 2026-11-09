# Choicy 1.5.5~b1 implementation plan

Work from `C:\Choicy`. This plan covers the Settings lists, two App Options, a three-package GitHub Actions workflow, and the Debian package version. The implementing session edits local files and performs focused static checks. The owner handles remote operations, package builds, and device testing.

## 1. Use the same rule for list order and icon tags

Add a small predicate to `Shared.h` and `Shared.m`, which both ChoicyPrefs and ChoicySB already compile. Given a saved process dictionary, return true when either `tweakInjectionDisabled` or `customTweakConfigurationEnabled` is true. Use the existing key constants and `parseNumberBool` with a false default. A missing or malformed dictionary yields false. A record with both flags set qualifies once.

Use `processPreferencesForApplication` with the bundle identifier and `processPreferencesForDaemon` with the executable basename. Only the two active flags qualify. Visiting a detail page, retaining an old allow/deny list, setting Global Overwrite alone, or using a one-time launch shortcut should leave the process in the ordinary group. Keep the existing Disabled, Custom, and Global Overwrite preview behavior in `CHPListController`.

## 2. Put configured processes first

- **Applications.** `ChoicyPrefs/Resources/Root.plist` requests AltList's Visible and Hidden sections, display-name and identifier search, and identifier subtitles. `CHPApplicationListSubcontrollerController` currently supplies just the previews. At the point where AltList supplies the rows for the current query, collect configured apps from both sections into one leading, localized `Configured` section. Order them by localized display name, using bundle ID to break ties. Keep ordinary rows in their existing sections and omit empty groups. Each bundle ID appears exactly once. With no configured apps, use the original list.
- **AltList integration.** Reuse its app specifiers, icons, search filtering, and detail targets. Keep any section/index data used for row selection in sync with the displayed order. The AltList headers and implementation are absent from this snapshot. Start from the subclass's inherited Preferences specifiers and their `applicationIdentifier` properties. Verify any AltList-specific extension point before depending on it. Preserve `+previewStringForProcessPreferences:`, which older Crane versions call.
- **Daemons.** `CHPDaemonList` already discovers and alphabetizes eligible executables. In `CHPDaemonListController -specifiers`, apply the current Recommended/All and search filters, then split the matching rows into configured and ordinary arrays. Append them in that order, preserving the alphabetical order of each. Keep the loading row, mode button, and footer in their existing roles. Use the identity emitted by `createSpecifierForExecutable:named:`. Ordinary daemons use `daemonSettings[executableName]`, while a row resolved as an app or plug-in uses its identifier in `appSettings`.
- **Refresh.** Returning from `CHPProcessConfigurationListController` currently refreshes a preview. Both lists also need to rebuild their ordering from fresh preferences when they reappear or receive a relevant preferences reload. Preserve the active query and daemon mode. Reuse the daemon discovery result and handle its asynchronous completion on the main thread.

## 3. Add the two App Options

In `ChoicyPrefs/Resources/Root.plist`, insert these global `PSSwitchCell` rows immediately below the existing `"Launch With Tweaks" Option`, in this order. This cell type supplies the right-hand switch. Use the existing `com.opa334.choicyprefs/ReloadPrefs` notification. Apply the same false defaults when SpringBoard reads absent keys, making both features opt-in on installation, upgrade, and reset.

| Settings label | Preference key | Default |
| --- | --- | --- |
| `Tag Custom Apps` | `tagCustomAppsEnabled` | Off |
| `"Open in Choicy" Option` | `openInChoicyOptionEnabled` | Off |

Set the App Options group footer to the following two paragraphs. The first is the requested wording verbatim.

> Adds an option to 3D touch / haptic touch menu on apps to launch with or without tweak injection.
>
> Tag Custom Apps places a small grey dot at the bottom-right of an app's icon when tweak injection is disabled or custom rules are enabled.

Add localized labels, the `Configured` heading, the footer, and the unquoted shortcut title `Open in Choicy` to `layout/Library/Application Support/Choicy.bundle/en.lproj/Localizable.strings`. Give the revised footer a new descriptive key in the plist and strings table. Other shipped locales already define the old footer key. A new key lets `Shared.m` use its English fallback wherever an updated translation is unavailable.

## 4. Draw the grey dot in SpringBoard

1. Add the icon-view behavior in `ChoicySB/SpringBoard.x` and the minimum declarations in `ChoicySB/SpringBoard.h`. Initialize it in `choicy_initSpringBoard` for both supported shortcut generations. The local `SBIconView` stub declares `NSObject` and two shortcut identifier selectors. Align the declaration with UIKit before using view methods and guard private image-view and icon-model accessors by availability. Resolve the actual application bundle ID on iOS 10–12 as well as 13+. Folder, widget, web clip, and other non-app icons should clear any previous tag on that view.
2. After icon assignment or layout, use the global switch and the shared saved-rule predicate. Keep one small circular grey `UIView` per qualifying icon view, associated with that view. Anchor it just inside the physical bottom-right of the icon image bounds so label size and icon scaling do not move it onto the caption. Make it noninteractive and decorative for accessibility. Reposition on layout and clear it immediately on reuse, reassignment, rule removal, or switch-off. Preserve system badges and indicators.
3. Use the preferences snapshot that `ChoicySB/Tweak.x` already loads. In `choicy_reloadPreferences`, treat absent old or new `appSettings` as empty when comparing keys. On `ReloadPrefs`, refresh visible icon views on the main thread, including first write and preference reset. A weak collection of visible views can request layout without retaining old icons. Keep file reads out of layout and UI work inside SpringBoard. The visual toggle itself should take effect without a respring or app termination.

## 5. Open the selected app's Choicy settings

1. Extend both existing menu paths in `ChoicySB/SpringBoard.x`. iOS 13+ uses `SBIconView` for construction and activation. iOS 10–12 uses `SBUIAppIconForceTouchControllerDataProvider` and `SBUIAppIconForceTouchController`. Add a distinct item type, such as `com.opa334.choicy.openInChoicy`, and carry the source bundle ID in its `userInfo`. Offer it for every real app when its switch is on, independently of the two launch switches and any saved rule. Start with the system items, handle a `nil` or empty original array, and add each Choicy type at most once.
2. Handle the new type in `+activateShortcut:withBundleIdentifier:forIconView:` and `-appIconForceTouchShortcutViewController:activateApplicationShortcutItem:`. Open Settings for the captured bundle ID, finish menu dismissal as needed, and consume the action. The source app keeps its current running state. Only the existing one-time launch item terminates its target and sets `toggleOneTimeApplicationID`. Other menu items continue through their original handlers.
3. Connect both ends of the route. `ChoicyPrefs/entry.plist` registers `CHPRootListController` through the installed PreferenceLoader entry `ChoicyPrefs.plist`. Give the entry and the Applications link stable specifier IDs where needed, and give each application row its bundle ID as its routing ID. Build the Preferences URL from the registered root and path components using `NSURLComponents`. A path of the form `Applications/<bundle-id>` is the proposed contract. This tree has no existing per-app URL handler. Verify that the receiver resolves the path to a detail controller even when the app list is still loading or a search was active.
4. Where a supported Settings version cannot traverse dynamic rows, deliver the bundle ID as a one-shot request when opening the Choicy pane. Have the root controller consume it when ready and on warm activation. If a cross-process pending request is needed, store it separately from injection preferences, expire it, and consume it once. Resolve an installed `LSApplicationProxy`, create the same `PSSpecifier` with `applicationIdentifier` and display name that normal navigation uses, and open `CHPProcessConfigurationListController`. It reads that property in `-specifiers`. Deduplicate repeated opens, respect the latest selection, and leave the Choicy pane usable if the app was removed. Landing on the root alone for an installed app is a failed check.

## 6. Set the version and build three distinct packages in CI

Change the `Version` field in `control` from `1.5.4` to exactly `1.5.5~b1`. Debian orders this beta after `1.5.4` and before the final `1.5.5` release. The bundle's `CFBundleVersion` and the preferences migration version have separate purposes.

Create `C:\Choicy\.github\workflows\build.yml` with `workflow_dispatch` for an owner-initiated build, read-only repository permissions, and an isolated matrix job per row. Use these exact labels in both the artifact names and the downloadable filenames.

| Label | Toolchain and package scheme | SDK / deployment target | Debian architecture | Uploaded file |
| --- | --- | --- | --- | --- |
| Rootless | Theos, `THEOS_PACKAGE_SCHEME=rootless` | 16.5 / 15.0 | `iphoneos-arm64` | `Choicy_1.5.5~b1_Rootless.deb` |
| Roothide | Native RootHide Theos and `THEOS_PACKAGE_SCHEME=roothide` | 16.5 / 15.0 | `iphoneos-arm64e` | `Choicy_1.5.5~b1_Roothide.deb` |
| Rootful | Theos default scheme, legacy Xcode 11 compiler prefix | 13.7 / 8.0 | `iphoneos-arm` | `Choicy_1.5.5~b1_Rootful.deb` |

1. Use `actions/checkout` with recursive submodules. `.gitmodules` declares `external/litehook` and `external/ChOma`. Both directories are empty in this local snapshot, which also lacks `.git` metadata. Verify their source files after CI checkout. Provision compatible macOS runners, the per-row Theos/SDK/compiler and libroot development files, `ldid`, Debian packaging tools, and AltList development headers and a linkable framework for the target. `control` declares `com.opa334.altlist (>=1.0.4)` as a runtime dependency. Use reproducible toolchain references and check the required files before compilation, including the Rootful compiler under `$THEOS/toolchain/Xcode11.xctoolchain/usr/bin/`.
2. The top `Makefile` currently selects the modern target only for `rootless`. Extend that condition to include `roothide` and ensure the chosen target reaches both subprojects. Preserve Rootful's legacy architectures and compiler support for iOS 10. `release_build.sh` documents the Rootful `PREFIX` and builds only two schemes. In CI run `make package FINALPACKAGE=1` once in each clean job with that row's settings. Use the native Roothide package scheme for its relocation and metadata.
3. Check the top-level and `ChoicyPrefs/Makefile` staging rules against each scheme. Preserve the three literal leading spaces in the installed `   Choicy.dylib` and `   Choicy.plist` names. From that job's fresh output require exactly one `.deb`. Before labeling or uploading, use `dpkg-deb -f` to check the package ID `com.opa334.choicy`, exact `Version`, and the architecture above. Inspect the payload with `dpkg-deb -c` for both tweaks, the preference bundle, PreferenceLoader entry, and localization resources at the scheme's expected paths. Verify the native Roothide layout with its toolchain. Copy the verified file under its labeled name and upload that single path with `actions/upload-artifact`. Derive the filename's version from package metadata.

## Acceptance and handoff

The implementing session can inspect the final diff, parse changed XML plists and workflow YAML with locally available tools, and cross-check preference keys, localized strings, both menu handlers, and the three matrix rows. Keep checks proportional to the edits.

| Owner check | Expected result |
| --- | --- |
| Configure one app and one daemon, disable injection on another, then clear their rules. Try app name/ID search and both daemon modes. | Matching configured entries move to the top once. Clearing a rule restores ordinary ordering on return. The same row opens the same process before and after it moves. |
| Enable tags, change a rule, move between Home Screen pages, a folder, and the Dock, then disable tags or reset preferences. | Only qualifying app icons carry one grey dot. Existing and reused views update without a respring. |
| On the older and newer shortcut paths, use a stock and a third-party app, including one with no other shortcuts. Try cold Settings, warm Settings on a different app, and two different app shortcuts in succession. | With the switch on, each shortcut opens that exact app's Choicy detail. With it off, the item disappears. Existing Launch With/Without Tweaks and system actions still work. |
| Manually run the workflow and inspect its three downloads. | Each label yields one installable package with the requested ID, beta version, matching architecture, and scheme-specific layout. |
