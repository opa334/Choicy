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

#include <mach/mach.h>
#include <stdlib.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <xpc/xpc.h>
#include <libgen.h>
#include <os/log.h>
#include <dlfcn.h>
#include <libroot.h>
#include <mach-o/dyld.h>
#include "dyld_interpose.h"

bool gShouldLog = true;
#define os_log_dbg(args ...) if (gShouldLog) os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG, args)

extern xpc_object_t xpc_create_from_plist(const void *buf, size_t len);
#define kEnvDeniedTweaksOverride "CHOICY_DENIED_TWEAKS_OVERRIDE"
#define kEnvAllowedTweaksOverride "CHOICY_ALLOWED_TWEAKS_OVERRIDE"
#define kEnvOverwriteGlobalConfigurationOverride "CHOICY_OVERWRITE_GLOBAL_TWEAK_CONFIGURATION_OVERRIDE"
#define kChoicyPrefsPlistPath JBROOT_PATH("/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist")
#define kChoicyPrefsKeyGlobalDeniedTweaks "globalDeniedTweaks"
#define kChoicyPrefsKeyAppSettings "appSettings"
#define kChoicyPrefsKeyDaemonSettings "daemonSettings"
#define kChoicyProcessPrefsKeyTweakInjectionDisabled "tweakInjectionDisabled"
#define kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled "customTweakConfigurationEnabled"
#define kChoicyProcessPrefsKeyAllowDenyMode "allowDenyMode"
#define kChoicyProcessPrefsKeyDeniedTweaks "deniedTweaks"
#define kChoicyProcessPrefsKeyAllowedTweaks "allowedTweaks"
#define kChoicyProcessPrefsKeyOverwriteGlobalTweakConfiguration "overwriteGlobalTweakConfiguration"
#define kPreferencesBundleID "com.apple.Preferences"
#define kSpringboardBundleID "com.apple.springboard"

enum {
	PROCESS_TYPE_BINARY,
	PROCESS_TYPE_APP,
	PROCESS_TYPE_PLUGIN,
};

char *gExecutablePath = NULL;
char *gBundleIdentifier = NULL;
int gProcessType = 0;

bool gTweakInjectionDisabled = false;
xpc_object_t gAllowedTweaks = NULL;
xpc_object_t gDeniedTweaks = NULL;
xpc_object_t gGlobalDeniedTweaks = NULL;

bool string_has_prefix(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

bool string_has_suffix(const char* str, const char* suffix)
{
	if (!str || !suffix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t suffix_len = strlen(suffix);

	if (str_len < suffix_len) {
		return false;
	}

	return !strcmp(str + str_len - suffix_len, suffix);
}

xpc_object_t xpc_object_from_plist(const char *path)
{
	xpc_object_t xObj = NULL;
	int ldFd = open(path, O_RDONLY);
	if (ldFd >= 0) {
		struct stat s = {};
		if(fstat(ldFd, &s) != 0) {
			close(ldFd);
			return NULL;
		}
		size_t len = s.st_size;
		void *addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, ldFd, 0);
		if (addr != MAP_FAILED) {
			close(ldFd);

			xObj = xpc_create_from_plist(addr, len);
			munmap(addr, len);
		}
	}
	return xObj;
}

bool xpc_array_contains_string(xpc_object_t xArr, const char *string)
{
	if (!xArr) return false;

	__block bool found = false;
	xpc_array_apply(xArr, ^bool(size_t index, xpc_object_t value){
		if (xpc_get_type(value) == XPC_TYPE_STRING) {
			const char *thisString = xpc_string_get_string_ptr(value);
			if (!strcmp(thisString, string)) {
				found = true;
				return false;
			}
		}
		return true;
	});
	return found;
}

void parse_allow_deny_list(const char *listStr, xpc_object_t *arrOut)
{
	if (!listStr || !arrOut) return;

	xpc_object_t xArr = xpc_array_create(NULL, 0);
	char *listStrCopy = strdup(listStr);
	char *curString = strtok(listStrCopy, ":");
	while (curString != NULL) {
		xpc_array_set_string(xArr, XPC_ARRAY_APPEND, curString);
		curString = strtok(NULL, ":");
	}
	free(listStrCopy);

	*arrOut = xArr;
}

void load_global_preferences(xpc_object_t preferencesXdict, xpc_object_t processPreferencesXdict)
{
	bool overwriteGlobalConfig = false;
	char *overwriteEnvConfigStr = getenv(kEnvOverwriteGlobalConfigurationOverride);
	if (overwriteEnvConfigStr) {
		overwriteGlobalConfig = !strcmp(overwriteEnvConfigStr, "1");
	}
	else if (processPreferencesXdict && xpc_get_type(processPreferencesXdict) == XPC_TYPE_DICTIONARY) {
		overwriteGlobalConfig = xpc_dictionary_get_bool(processPreferencesXdict, kChoicyProcessPrefsKeyOverwriteGlobalTweakConfiguration);
	}

	if (!overwriteGlobalConfig) {
		xpc_object_t globalDeniedTweaks = xpc_dictionary_get_value(preferencesXdict, kChoicyPrefsKeyGlobalDeniedTweaks);
		if (globalDeniedTweaks && xpc_get_type(globalDeniedTweaks) == XPC_TYPE_ARRAY) {
			gGlobalDeniedTweaks = xpc_retain(globalDeniedTweaks);
		}
	}
}

void load_process_preferences(xpc_object_t preferencesXdict, xpc_object_t processPreferencesXdict)
{
	if (gProcessType != PROCESS_TYPE_APP || !strcmp(gBundleIdentifier, kSpringboardBundleID)) {
		gTweakInjectionDisabled = xpc_dictionary_get_bool(processPreferencesXdict, kChoicyProcessPrefsKeyTweakInjectionDisabled);;
	}

	bool customTweakConfigurationEnabled = xpc_dictionary_get_bool(processPreferencesXdict, kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled);
	if (customTweakConfigurationEnabled) {
		int allowDenyMode = 1;
		xpc_object_t allowDenyModeVal = xpc_dictionary_get_value(processPreferencesXdict, kChoicyProcessPrefsKeyAllowDenyMode);
		if (allowDenyModeVal && xpc_get_type(allowDenyModeVal) == XPC_TYPE_INT64) {
			allowDenyMode = xpc_int64_get_value(allowDenyModeVal);
		}

		if (allowDenyMode == 2) { // DENY
			xpc_object_t deniedTweaks = xpc_dictionary_get_value(processPreferencesXdict, kChoicyProcessPrefsKeyDeniedTweaks);
			if (deniedTweaks && xpc_get_type(deniedTweaks) == XPC_TYPE_ARRAY) {
				gDeniedTweaks = xpc_retain(deniedTweaks);
			}
		}
		else if (allowDenyMode == 1) { // ALLOW
			xpc_object_t allowedTweaks = xpc_dictionary_get_value(processPreferencesXdict, kChoicyProcessPrefsKeyAllowedTweaks);
			if (allowedTweaks && xpc_get_type(allowedTweaks) == XPC_TYPE_ARRAY) {
				gAllowedTweaks = xpc_retain(allowedTweaks);
			}
		}
	}
}

void load_process_info(void)
{
	// Load executable path
	uint32_t executablePathSize = 0;
	_NSGetExecutablePath(NULL, &executablePathSize);
	gExecutablePath = malloc(executablePathSize);
	_NSGetExecutablePath(gExecutablePath, &executablePathSize);

	// Calling os_log from inside logd deadlocks the system, prevent that...
	if (!strcmp(gExecutablePath, "/usr/libexec/logd")) gShouldLog = false;

	// Load process type
	char *executableDir = dirname(strdup(gExecutablePath));
	if (string_has_suffix(executableDir, ".app"))		 gProcessType = PROCESS_TYPE_APP;
	else if (string_has_suffix(executableDir, ".appex")) gProcessType = PROCESS_TYPE_PLUGIN;
	else												 gProcessType = PROCESS_TYPE_BINARY;

	// Load application identifier
	size_t infoPlistPathSize = strlen(executableDir) + strlen("/Info.plist") + 1;
	char infoPlistPath[infoPlistPathSize];
	strlcpy(infoPlistPath, executableDir, infoPlistPathSize);
	strlcat(infoPlistPath, "/Info.plist", infoPlistPathSize);
	free(executableDir);
	if ((gProcessType == PROCESS_TYPE_APP || gProcessType == PROCESS_TYPE_PLUGIN) && access(infoPlistPath, R_OK) == 0) {
		xpc_object_t infoXdict = xpc_object_from_plist(infoPlistPath);
		if (infoXdict && xpc_get_type(infoXdict) == XPC_TYPE_DICTIONARY) {
			const char *bundleIdentifier = xpc_dictionary_get_string(infoXdict, "CFBundleIdentifier");
			if (bundleIdentifier) {
				gBundleIdentifier = strdup(bundleIdentifier);
			}
			xpc_release(infoXdict);
		}
	}

	// Load overwrites from environment
	parse_allow_deny_list(getenv(kEnvDeniedTweaksOverride), &gDeniedTweaks);
	parse_allow_deny_list(getenv(kEnvAllowedTweaksOverride), &gAllowedTweaks);

	// Load preferences
	xpc_object_t preferencesXdict = xpc_object_from_plist(kChoicyPrefsPlistPath);
	if (preferencesXdict) {
		if (xpc_get_type(preferencesXdict) == XPC_TYPE_DICTIONARY) {
			xpc_object_t processPreferencesXdict = NULL;

			if (gBundleIdentifier) {
				xpc_object_t appPreferencesXdict = xpc_dictionary_get_value(preferencesXdict, kChoicyPrefsKeyAppSettings);
				if (appPreferencesXdict && xpc_get_type(appPreferencesXdict) == XPC_TYPE_DICTIONARY) {
					xpc_object_t thisAppXdict = xpc_dictionary_get_value(appPreferencesXdict, gBundleIdentifier);
					if (thisAppXdict && xpc_get_type(thisAppXdict) == XPC_TYPE_DICTIONARY) {
						processPreferencesXdict = thisAppXdict;
					}
				}
			}
			else {
				xpc_object_t daemonPreferencesXdict = xpc_dictionary_get_value(preferencesXdict, kChoicyPrefsKeyDaemonSettings);
				if (daemonPreferencesXdict && xpc_get_type(daemonPreferencesXdict) == XPC_TYPE_DICTIONARY) {
					xpc_object_t thisDaemonXdict = xpc_dictionary_get_value(daemonPreferencesXdict, gExecutablePath);
					if (thisDaemonXdict && xpc_get_type(thisDaemonXdict) == XPC_TYPE_DICTIONARY) {
						processPreferencesXdict = thisDaemonXdict;
					}
				}
			}

			// Load global preferences
			load_global_preferences(preferencesXdict, processPreferencesXdict);

			// If neither the allow nor the deny list has been overwritten from the environment, load them from preferences
			if (!gDeniedTweaks && !gAllowedTweaks && processPreferencesXdict) {
				load_process_preferences(preferencesXdict, processPreferencesXdict);
			}
		}
		xpc_release(preferencesXdict);
	}
}

bool dylib_is_tweak(const char *dylibPath)
{
	if (!dylibPath) return false;

	__block bool isTweak = false;
	if (strstr(dylibPath, "/TweakInject/") || strstr(dylibPath, "/MobileSubstrate/DynamicLibraries/")) {
		char dylibPathDup1[strlen(dylibPath + 1)];
		strcpy(dylibPathDup1, dylibPath);
		char dylibPathDup2[strlen(dylibPath + 1)];
		strcpy(dylibPathDup2, dylibPath);

		char *dylibDir = dirname(dylibPathDup1);
		char *dylibName = basename(dylibPathDup2);

		size_t tweakPlistPathLength = strlen(dylibDir) + strlen(dylibName) + 2;
		char tweakPlistPath[tweakPlistPathLength];
		strlcpy(tweakPlistPath, dylibDir, tweakPlistPathLength);
		strlcat(tweakPlistPath, "/", tweakPlistPathLength);
		strlcat(tweakPlistPath, dylibName, tweakPlistPathLength);
		strlcpy(&tweakPlistPath[tweakPlistPathLength - 6], "plist", 6);

		os_log_dbg("tweakPlistPath = %{public}s", tweakPlistPath);

		if (access(tweakPlistPath, R_OK) == 0) {
			xpc_object_t tweakPlist = xpc_object_from_plist(tweakPlistPath);
			if (tweakPlist) {
				xpc_object_t filterXdict = xpc_dictionary_get_value(tweakPlist, "Filter");
				if (filterXdict && xpc_get_type(filterXdict) == XPC_TYPE_DICTIONARY) {
					xpc_dictionary_apply(filterXdict, ^bool(const char *key, xpc_object_t value) {
						if (value && xpc_get_type(value) == XPC_TYPE_ARRAY) {
							if (xpc_array_get_count(value) > 0) {
								isTweak = true;
								return false;
							}
						}
						return true;
					});
				}
				xpc_release(tweakPlist);
			}
		}
	}
	return isTweak;
}

bool should_load_dylib(const char *dylibPath)
{
	if (!string_has_suffix(dylibPath, ".dylib")) return true;

	char dylibPathDup[strlen(dylibPath + 1)];
	strcpy(dylibPathDup, dylibPath);
	char *dylibName = basename(dylibPathDup);
	dylibName[strlen(dylibName)-6] = '\0';

	os_log_dbg("Checking whether %{public}s.dylib should be loaded...", dylibName);

	if (dylib_is_tweak(dylibPath)) {
		// dylibs crucial for Choicy itself to work
		if (gProcessType == PROCESS_TYPE_APP) {
			if (!strcmp(gBundleIdentifier, kPreferencesBundleID)) {
				if (!strcmp(dylibName, "PreferenceLoader") || !strcmp(dylibName, "preferred")) {
					os_log_dbg("%{public}s.dylib ✅ (crucial)", dylibName);
					return true;
				}
			}
			else if (!strcmp(gBundleIdentifier, kSpringboardBundleID)) {
				if (!strcmp(dylibName, "ChoicySB")) {
					os_log_dbg("%{public}s.dylib ✅ (crucial)", dylibName);
					return true;
				}
			}
		}

		if (gTweakInjectionDisabled) {
			os_log_dbg("%{public}s.dylib ❌ (tweak injection disabled)", dylibName);
			return false;
		}

		bool tweakIsAllowed = xpc_array_contains_string(gAllowedTweaks, dylibName);
		bool tweakIsDenied = xpc_array_contains_string(gDeniedTweaks, dylibName);
		bool tweakIsGloballyDenied = xpc_array_contains_string(gGlobalDeniedTweaks, dylibName);

		if (tweakIsGloballyDenied) {
			os_log_dbg("%{public}s.dylib ❌ (disabled in global tweak configuration)", dylibName);
			return false;
		}

		if (gAllowedTweaks && !tweakIsAllowed) {
			os_log_dbg("%{public}s.dylib ❌ (custom tweak configuration on allow and tweak not allowed)", dylibName);
			return false;
		}

		if (gDeniedTweaks && tweakIsDenied) {
			os_log_dbg("%{public}s.dylib ❌ (custom tweak configuration on deny and tweak denied)", dylibName);
			return false;
		}
	}
	else {
		os_log_dbg("%{public}s.dylib ✅ (not a tweak)", dylibName);
		return true;
	}

	os_log_dbg("%{public}s.dylib ✅ (allowed)", dylibName);
	return true;
}

void *(*dlopen_from_orig)(const char*, int, void *);
void *dlopen_from_hook(const char *path, int mode, void *lr)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	return dlopen_from_orig(path, mode, lr);
}

void *(*dlopen_orig)(const char*, int);
void *dlopen_hook(const char *path, int mode);
/*void *dlopen_hook(const char *path, int mode)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	__attribute__((musttail)) return dlopen_orig(path, mode);
}*/

const struct mach_header *find_tweak_loader_mach_header(void)
{
	const char *tweakLoaderPaths[] = {
		JBROOT_PATH("/usr/lib/TweakLoader.dylib"),				   // Ellekit, rootless standard
		JBROOT_PATH("/usr/lib/substitute-loader.dylib"),		   // Substitute
		JBROOT_PATH("/usr/lib/TweakInject.dylib"),				   // libhooker
		JBROOT_PATH("/usr/lib/substrate/SubstrateInserter.dylib"), // Substrate 
	};

	bool foundTweakLoader = false;
	struct stat tweakLoaderStat;
	for (int k = 0; k < sizeof(tweakLoaderPaths) / sizeof(*tweakLoaderPaths); k++) {
		if (access(tweakLoaderPaths[k], F_OK) == 0) {
			stat(tweakLoaderPaths[k], &tweakLoaderStat);
			foundTweakLoader = true;
			break;
		}
	}

	if (!foundTweakLoader) return NULL;

	for (int i = 0; i < _dyld_image_count(); i++) {
		const char *path = _dyld_get_image_name(i);
		struct stat pathStat;
		if (stat(path, &pathStat) == 0) {
			if (pathStat.st_dev == tweakLoaderStat.st_dev && pathStat.st_ino == tweakLoaderStat.st_ino) {
				os_log_dbg("Found tweak loader: %{public}s\n", path);
				return _dyld_get_image_header(i);
			}
		}
	}

	return NULL;
}

__attribute__((constructor)) static void initializer(void)
{
	load_process_info();
	os_log_dbg("Choicy works");

	if (gTweakInjectionDisabled || gAllowedTweaks || gDeniedTweaks || gGlobalDeniedTweaks) {
		os_log_dbg("Initializing Choicy...");
		void *libdyldHandle = dlopen("/usr/lib/system/libdyld.dylib", RTLD_NOW);
		void *dlopen_from = dlsym(libdyldHandle, "dlopen_from");

		const struct mach_header *tweakLoaderHeader = find_tweak_loader_mach_header();
		os_log_dbg("tweakLoaderHeader: %p", tweakLoaderHeader);
		if (tweakLoaderHeader) {
			static struct dyld_interpose_tuple interposes[2];
			interposes[0] = (struct dyld_interpose_tuple){ .replacement = dlopen_hook, .replacee = dlopen };
			if (dlopen_from) {
				interposes[1] = (struct dyld_interpose_tuple){ .replacement = dlopen_from_hook, .replacee = dlopen_from };
			}
			dyld_dynamic_interpose(tweakLoaderHeader, interposes, dlopen_from ? 2 : 1);
		}
	}
}