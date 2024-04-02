// Copyright (c) 2019-2021 Lars Fröder

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <HBLog.h>
#import <libroot.h>

extern NSBundle *CHBundle;
extern NSString *localize(NSString *key);
extern NSDictionary *processPreferencesForApplication(NSDictionary *preferences, NSString *applicationID);
extern NSDictionary *processPreferencesForDaemon(NSDictionary *preferences, NSString *daemonDisplayName);

extern BOOL parseNumberBool(id number, BOOL default_);
extern NSInteger parseNumberInteger(id number, NSInteger default_);

#define kChoicyPrefsPlistPath JBROOT_PATH_NSSTRING(@"/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist")
#define kChoicyDylibName @"   Choicy"

#define kChoicyPrefsKeyGlobalDeniedTweaks @"globalDeniedTweaks"
#define kChoicyPrefsKeyAppSettings @"appSettings"
#define kChoicyPrefsKeyDaemonSettings @"daemonSettings"
#define kChoicyPrefsKeyAdditionalExecutables @"additionalExecutables"
#define kChoicyProcessPrefsKeyTweakInjectionDisabled @"tweakInjectionDisabled"
#define kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled @"customTweakConfigurationEnabled"
#define kChoicyProcessPrefsKeyAllowDenyMode @"allowDenyMode"
#define kChoicyProcessPrefsKeyDeniedTweaks @"deniedTweaks"
#define kChoicyProcessPrefsKeyAllowedTweaks @"allowedTweaks"
#define kChoicyProcessPrefsKeyOverwriteGlobalTweakConfiguration @"overwriteGlobalTweakConfiguration"

// pre 1.4 keys
#define kChoicyPrefsKeyGlobalDeniedTweaks_LEGACY @"globalTweakBlacklist"
#define kChoicyProcessPrefsKeyAllowDenyMode_LEGACY @"whitelistBlacklistSegment"
#define kChoicyProcessPrefsKeyDeniedTweaks_LEGACY @"tweakBlacklist"
#define kChoicyProcessPrefsKeyAllowedTweaks_LEGACY @"tweakWhitelist"

// pref migration
#define kChoicyPrefMigration1_4_ChangedKeys @{kChoicyPrefsKeyGlobalDeniedTweaks_LEGACY : kChoicyPrefsKeyGlobalDeniedTweaks}
#define kChoicyPrefMigration1_4_RemovedKeys @[@"allowBlacklistOverwrites", @"allowWhitelistOverwrites"]
#define kChoicyProcessPrefMigration1_4_ChangedKeys @{kChoicyProcessPrefsKeyAllowDenyMode_LEGACY : kChoicyProcessPrefsKeyAllowDenyMode, kChoicyProcessPrefsKeyDeniedTweaks_LEGACY : kChoicyProcessPrefsKeyDeniedTweaks, kChoicyProcessPrefsKeyAllowedTweaks_LEGACY : kChoicyProcessPrefsKeyAllowedTweaks}

#define kPreferencesBundleID @"com.apple.Preferences"
#define kSpringboardBundleID @"com.apple.springboard"

#define kEnvDeniedTweaksOverride "CHOICY_DENIED_TWEAKS_OVERRIDE"
#define kEnvAllowedTweaksOverride "CHOICY_ALLOWED_TWEAKS_OVERRIDE"
#define kEnvOverwriteGlobalConfigurationOverride "CHOICY_OVERWRITE_GLOBAL_TWEAK_CONFIGURATION_OVERRIDE"

#define kNoDisableTweakInjectionToggle @[kPreferencesBundleID]
#define kAlwaysInjectGlobal @[kChoicyDylibName, @"MobileSafety"]
#define kAlwaysInjectSpringboard @[@"ChoicySB"]
#define kAlwaysInjectPreferences @[@"PreferenceLoader", @"preferred"]

#define kChoicyPrefsCurrentVersion 1
#define kChoicyPrefsVersionKey @"preferenceVersion"

extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description);

#ifndef kCFCoreFoundationVersionNumber_iOS_11_0
#define kCFCoreFoundationVersionNumber_iOS_11_0 1443.00
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_13_0
#define kCFCoreFoundationVersionNumber_iOS_13_0 1665.15
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_14_0
#define kCFCoreFoundationVersionNumber_iOS_14_0 1740.00
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_14_1
#define kCFCoreFoundationVersionNumber_iOS_14_1 1751.108
#endif
