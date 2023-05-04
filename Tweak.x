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

#import "HBLogWeak.h"

#import "Shared.h"
#import <substrate.h>
#import <dlfcn.h>

BOOL g_tweakInjectionDisabled = NO;
BOOL g_customTweakConfigurationEnabled = NO;

NSArray *g_allowedTweaks = nil;
NSArray *g_deniedTweaks = nil;
NSArray *g_globalDeniedTweaks = nil;
BOOL g_isApplication = NO;

NSString *g_bundleIdentifier = nil;

//methods of getting executablePath and bundleIdentifier with the least side effects possible
//for more information, check out https://github.com/checkra1n/BugTracker/issues/343
extern char** *_NSGetArgv();
NSString *safe_getExecutablePath() {
	char *executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

NSString *safe_getBundleIdentifier() {
	CFBundleRef mainBundle = CFBundleGetMainBundle();

	if (mainBundle != NULL) {
		CFStringRef bundleIdentifierCF = CFBundleGetIdentifier(mainBundle);

		return (__bridge NSString *)bundleIdentifierCF;
	}

	return nil;
}

NSArray *env_getDeniedTweaksOverwrite() {
	char *deniedTweaksC = getenv(kEnvDeniedTweaksOverride);
	if (deniedTweaksC == NULL) return nil;
	unsetenv(kEnvDeniedTweaksOverride);

	NSString *deniedTweaksString = [NSString stringWithCString:deniedTweaksC encoding:NSUTF8StringEncoding];
	return [deniedTweaksString componentsSeparatedByString:@"/"];
}

NSArray *env_getAllowedTweaksOverwrite() {
	char *allowedTweaksC = getenv(kEnvAllowedTweaksOverride);
	if (allowedTweaksC == NULL) return nil;
	unsetenv(kEnvAllowedTweaksOverride);

	NSString *allowedTweaksString = [NSString stringWithCString:allowedTweaksC encoding:NSUTF8StringEncoding];
	return [allowedTweaksString componentsSeparatedByString:@"/"];
}

BOOL env_getOverwriteGlobalTweakConfigurationOverwrite(BOOL *envOverwriteExists) {
	char *overwriteGlobalTweakConfigurationStr = getenv(kEnvOverwriteGlobalConfigurationOverride);
	if (overwriteGlobalTweakConfigurationStr == NULL) {
		if (envOverwriteExists) *envOverwriteExists = NO;
		return NO;
	}
	unsetenv(kEnvOverwriteGlobalConfigurationOverride);
	if (envOverwriteExists) *envOverwriteExists = YES;
	return !strcmp(overwriteGlobalTweakConfigurationStr, "1");
}

BOOL isTweakDylib(NSString *dylibPath) {
	if ([dylibPath containsString:@"TweakInject"] || [dylibPath containsString:@"MobileSubstrate/DynamicLibraries"]) {
		NSString *plistPath = [[dylibPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];

		HBLogDebugWeak(@"plistPath = %@", plistPath);

		if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
			//Shoutouts to libFLEX for having a plist with an empty bundles entry
			NSDictionary *bundlePlistDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];

			HBLogDebugWeak(@"bundlePlistDict = %@", bundlePlistDict);

			NSDictionary *filter = [bundlePlistDict objectForKey:@"Filter"];

			for (NSString *key in [filter allKeys]) {
				NSObject *obj = [filter objectForKey:key];

				if ([obj respondsToSelector:@selector(count)]) {
					NSArray *arrObj = (NSArray *)obj;

					if (arrObj.count > 0) {
						return YES;
					}
				}
			}
		}
	}

	return NO;
}

BOOL shouldLoadDylib(NSString *dylibPath) {
	NSString *dylibName = [dylibPath.lastPathComponent stringByDeletingPathExtension];
	HBLogDebugWeak(@"Checking whether %@.dylib should be loaded...", dylibName);

	if (isTweakDylib(dylibPath)) {
		// dylibs crucial for Choicy itself to work
		if (g_isApplication) {
			NSArray *forceInjectedTweaks;
			if ([g_bundleIdentifier isEqualToString:kPreferencesBundleID]) {
				forceInjectedTweaks = kAlwaysInjectPreferences;
			}
			else if ([g_bundleIdentifier isEqualToString:kSpringboardBundleID]) {
				forceInjectedTweaks = kAlwaysInjectSpringboard;
			}

			if ([forceInjectedTweaks containsObject:dylibName]) {
				HBLogDebugWeak(@"%@.dylib ✅ (crucial)", dylibName);
				return YES;
			}
		}

		if (g_tweakInjectionDisabled) {
			HBLogDebugWeak(@"%@.dylib ❌ (tweak injection disabled)", dylibName);
			return NO;
		}

		BOOL tweakIsInWhitelist = [g_allowedTweaks containsObject:dylibName];
		BOOL tweakIsInBlacklist = [g_deniedTweaks containsObject:dylibName];
		BOOL tweakIsInGlobalBlacklist = [g_globalDeniedTweaks containsObject:dylibName];

		if (tweakIsInGlobalBlacklist) {
			HBLogDebugWeak(@"%@.dylib ❌ (disabled in global tweak configuration)", dylibName);
			return NO;
		}

		if (g_allowedTweaks && !tweakIsInWhitelist) {
			HBLogDebugWeak(@"%@.dylib ❌ (custom tweak configuration on allow and tweak not allowed)", dylibName);
			return NO;
		}

		if (g_deniedTweaks && tweakIsInBlacklist) {
			HBLogDebugWeak(@"%@.dylib ❌ (custom tweak configuration on deny and tweak denied)", dylibName);
			return NO;
		}
	}
	else {
		HBLogDebugWeak(@"%@.dylib ✅ (not a tweak)", dylibName);
		return YES;
	}

	HBLogDebugWeak(@"%@.dylib ✅ (allowed)", dylibName);
	return YES;
}

void *(*dlopen_internal_orig)(const char*, int, void *);
void *$dlopen_internal(const char *path, int mode, void *lr) {
	@autoreleasepool {
		if (path != NULL) {
			NSString *dylibPath = @(path);
			if (!shouldLoadDylib(dylibPath)) {
				return NULL;
			}
		}
	}
	return dlopen_internal_orig(path, mode, lr);
}

void *(*dlopen_orig)(const char*, int);
void *$dlopen(const char *path, int mode) {
	@autoreleasepool {
		if (path != NULL) {
			NSString *dylibPath = @(path);
			if (!shouldLoadDylib(dylibPath)) {
				return NULL;
			}
		}
	}
	return dlopen_orig(path, mode);
}

%ctor {
	@autoreleasepool {
		HBLogDebugWeak(@"Choicy loaded");

		// Determine information about this process
		g_bundleIdentifier = safe_getBundleIdentifier();
		NSString *executablePath = safe_getExecutablePath();
		g_isApplication = [executablePath.stringByDeletingLastPathComponent.pathExtension isEqualToString:@"app"];
		BOOL isAppPlugIn = [executablePath.stringByDeletingLastPathComponent.pathExtension isEqualToString:@"appex"];

		// Load global preferences
		NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];

		// Load preferences specific to this process
		NSDictionary *processPreferences;
		if (g_isApplication) {
			processPreferences = processPreferencesForApplication(preferences, g_bundleIdentifier);
		}
		else {
			processPreferences = processPreferencesForDaemon(preferences, executablePath.lastPathComponent);
		}

		HBLogDebugWeak(@"Loaded Choicy process preferences: %@", processPreferences);

		// Check if the "Overwrite Global Tweak Configuration" toggle is enabled for this process or enabled via environment variable
		BOOL overwriteGlobalTweakConfiguration = parseNumberBool(processPreferences[kChoicyProcessPrefsKeyOverwriteGlobalTweakConfiguration], NO);
		BOOL overwriteGlobalTweakConfiguration_envOverwriteExists;
		BOOL overwriteGlobalTweakConfiguration_envOverwrite = env_getOverwriteGlobalTweakConfigurationOverwrite(&overwriteGlobalTweakConfiguration_envOverwriteExists);
		if (overwriteGlobalTweakConfiguration_envOverwriteExists) {
			overwriteGlobalTweakConfiguration = overwriteGlobalTweakConfiguration_envOverwrite;
		}

		if (!overwriteGlobalTweakConfiguration) {
			// If not, load tweaks disabled via global tweak configuration
			g_globalDeniedTweaks = preferences[kChoicyPrefsKeyGlobalDeniedTweaks];
		}

		HBLogDebugWeak(@"g_globalDeniedTweaks = %@", g_globalDeniedTweaks);

		NSInteger allowDenyMode = 0;
		if (processPreferences) {
			// If this process has non default preferences, load them into variables
			g_tweakInjectionDisabled = parseNumberBool(processPreferences[kChoicyProcessPrefsKeyTweakInjectionDisabled], NO);
			g_customTweakConfigurationEnabled = parseNumberBool(processPreferences[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled], NO);
			allowDenyMode = parseNumberInteger(processPreferences[kChoicyProcessPrefsKeyAllowDenyMode], 1);
		}

		// Load list overwrites from environment
		NSArray *env_deniedTweaks = env_getDeniedTweaksOverwrite();
		NSArray *env_allowedTweaks = env_getAllowedTweaksOverwrite();

		BOOL performedOverwrite = NO;

		// Perform overwrites if neccessary
		if (env_deniedTweaks) {
			g_customTweakConfigurationEnabled = YES;
			allowDenyMode = 2; // DENY
			g_deniedTweaks = env_deniedTweaks;
			performedOverwrite = YES;
		}
		else if (env_allowedTweaks) {
			g_customTweakConfigurationEnabled = YES;
			allowDenyMode = 1; // ALLOW
			g_allowedTweaks = env_allowedTweaks;
			performedOverwrite = YES;
		}

		if (g_tweakInjectionDisabled || g_customTweakConfigurationEnabled || g_globalDeniedTweaks.count > 0) {
			// If g_tweakInjectionDisabled is true for an application other than SpringBoard,
			// it means that tweak injection was enabled for one launch via 3D touch and we should not do anything
			if (g_isApplication && !isAppPlugIn && g_tweakInjectionDisabled) {
				if (![g_bundleIdentifier isEqualToString:kSpringboardBundleID]) {
					HBLogDebugWeak(@"Tweak injection has been enabled via 3D touch, Choicy will do nothing!");
					return;
				}
			}

			// If custom tweak configuration is enabled for this process, load the allow / deny list based on what mode is selected
			if (g_customTweakConfigurationEnabled && !performedOverwrite) {
				if (allowDenyMode == 2) { // DENY
					g_deniedTweaks = processPreferences[kChoicyProcessPrefsKeyDeniedTweaks];
				}
				else if (allowDenyMode == 1) { // ALLOW
					g_allowedTweaks = processPreferences[kChoicyProcessPrefsKeyAllowedTweaks];
				}
			}

			// Apply Choicy dlopen hooks
			MSImageRef libdyldImage = MSGetImageByName("/usr/lib/system/libdyld.dylib");
			void *libdyldHandle = dlopen("/usr/lib/system/libdyld.dylib", RTLD_NOW);

			void *dlopen_global_var_ptr = MSFindSymbol(libdyldImage, "__ZN5dyld45gDyldE"); // if this var exists, it means we're on a version new enough to hook dlopen directly again
			if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_14_1 && !dlopen_global_var_ptr) {
				void *dlopen_internal_ptr = MSFindSymbol(libdyldImage, "__ZL15dlopen_internalPKciPv");
				MSHookFunction(dlopen_internal_ptr, (void *)$dlopen_internal, (void* *)&dlopen_internal_orig);
			}
			else {
				MSHookFunction(&dlopen, (void *)$dlopen, (void* *)&dlopen_orig);
				void *dlopen_from_ptr = dlsym(libdyldHandle, "dlopen_from");
				if (dlopen_from_ptr) {
					MSHookFunction(dlopen_from_ptr, (void *)$dlopen_internal, (void* *)&dlopen_internal_orig);
				}
			}
		}
	}
}