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
#include <mach-o/getsect.h>
#include <ptrauth.h>
#include <litehook.h>
#include "dyld_interpose.h"
#include "nextstep_plist.h"

void *(*dlopen_orig)(const char*, int);
void *dlopen_hook(const char *path, int mode);

void *(*dyld_dlopen_orig)(const void *, const char*, int);
void *dyld_dlopen_hook(const void *dyld, const char *path, int mode);

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

char *path_copy_basename(const char *path)
{
	char pathdup[strlen(path) + 1];
	strcpy(pathdup, path);
	return strdup(basename(pathdup));
}

char *path_copy_dirname(const char *path)
{
	char pathdup[strlen(path) + 1];
	strcpy(pathdup, path);
	return strdup(dirname(pathdup));
}

xpc_object_t xpc_object_from_plist(const char *path)
{
	int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;

    struct stat st = {0};
    if (fstat(fd, &st) != 0 || st.st_size == 0) {
        close(fd);
        return NULL;
    }

    void *data = mmap(NULL, st.st_size, PROT_READ, MAP_FILE | MAP_PRIVATE, fd, 0);
    close(fd);
    if (data == MAP_FAILED) return NULL;

    xpc_object_t plist = xpc_create_from_plist(data, st.st_size);
    if (plist == NULL) {
        char *plist_str = (char *)data;
        if (strnstr(plist_str, "bplist", st.st_size) ||
            strnstr(plist_str, "?xml", st.st_size) ||
            strnstr(plist_str, "!DOCTYPE plist", st.st_size)) {
            munmap(data, st.st_size);
            return NULL;
        }

        for (int i = 0; i < st.st_size; i++) {
            if (plist_str[i] < 0 || plist_str[i] > 127) {
                munmap(data, st.st_size);
                return NULL;
            }
        }

        nextstep_plist_t nextstep_plist = {0};
        nextstep_plist.index = 0;
        nextstep_plist.size = st.st_size;
        nextstep_plist.data = plist_str;
        plist = nxp_parse_object(&nextstep_plist);
    }

    munmap(data, st.st_size);
    return plist;
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
		gTweakInjectionDisabled = xpc_dictionary_get_bool(processPreferencesXdict, kChoicyProcessPrefsKeyTweakInjectionDisabled);
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

	// Calling os_log from inside logd or notifyd deadlocks the system, prevent that...
	if (!strcmp(gExecutablePath, "/usr/libexec/logd") || !strcmp(gExecutablePath, "/usr/sbin/notifyd")) gShouldLog = false;

	// Load process type
	char *executableDir = path_copy_dirname(gExecutablePath);
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
					const char *executableName = strrchr(gExecutablePath, '/');
					if (executableName) {
						xpc_object_t thisDaemonXdict = xpc_dictionary_get_value(daemonPreferencesXdict, &executableName[1]);
						if (thisDaemonXdict && xpc_get_type(thisDaemonXdict) == XPC_TYPE_DICTIONARY) {
							processPreferencesXdict = thisDaemonXdict;
						}
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
		char dylibPathLength = strlen(dylibPath)+1;
		char plistPath[dylibPathLength];
		strcpy(plistPath, dylibPath);
		strlcpy(&plistPath[dylibPathLength - 6], "plist", 6);

		if (access(plistPath, R_OK) == 0) {
			xpc_object_t tweakPlist = xpc_object_from_plist(plistPath);
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

	char *dylibNameHeap = path_copy_basename(dylibPath);
	char dylibName[strlen(dylibNameHeap)+1];
	strcpy(dylibName, dylibNameHeap);
	free(dylibNameHeap);

	dylibName[strlen(dylibName)-6] = '\0';

	if (!strcmp(dylibName, "   Choicy")) return true;

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

void *(*dlopen_from_orig)(const char*, int, void *) = NULL;
void *dlopen_from_hook(const char *path, int mode, void *lr)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	return dlopen_from_orig(path, mode, lr);
}

void *(*dyld_dlopen_from_orig)(const void *, const char*, int, void *) = NULL;
void *dyld_dlopen_from_hook(const void *dyld, const char *path, int mode, void *lr)
{
	if (path) {
		if (!should_load_dylib(path)) {
			return NULL;
		}
	}
	return dyld_dlopen_from_orig(dyld, path, mode, lr);
}

const struct mach_header *find_tweak_loader_mach_header(const char **pathOut)
{
	const char *tweakLoaderPaths[] = {
		JBROOT_PATH("/usr/lib/TweakLoader.dylib"),													 // Ellekit (Rootless Standard)
		JBROOT_PATH("/usr/lib/substitute-loader.dylib"),											 // Substitute
		JBROOT_PATH("/usr/lib/TweakInject.dylib"),													 // libhooker
		JBROOT_PATH("/usr/lib/substrate/SubstrateLoader.dylib"),									 // Substrate
		JBROOT_PATH("/Library/Frameworks/CydiaSubstrate.framework/Libraries/SubstrateLoader.dylib"), // Substrate (Older versions)
		JBROOT_PATH("/usr/lib/Sonar/libsonar.dylib"),												 // Sonar
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
				if (pathOut) *pathOut = path;
				return _dyld_get_image_header(i);
			}
		}
	}

	return NULL;
}

int dyld_hook_routine(void **dyld, int idx, void *hook, void **orig, uint16_t pacSalt)
{
	if (!dyld) return -1;

	__unused uint64_t dyldPacDiversifier = ((uint64_t)dyld & ~(0xFFFFull << 48)) | (0x63FAull << 48);
	void **dyldFuncPtrs = ptrauth_auth_data(*dyld, ptrauth_key_process_independent_data, dyldPacDiversifier);
	if (!dyldFuncPtrs) return -1;

	if (vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ | VM_PROT_WRITE) == 0) {
		uint64_t location = (uint64_t)&dyldFuncPtrs[idx];
		__unused uint64_t pacDiversifier = (location & ~(0xFFFFull << 48)) | ((uint64_t)pacSalt << 48);

		*orig = ptrauth_auth_and_resign(dyldFuncPtrs[idx], ptrauth_key_process_independent_code, pacDiversifier, ptrauth_key_function_pointer, 0);
		dyldFuncPtrs[idx] = ptrauth_auth_and_resign(hook, ptrauth_key_function_pointer, 0, ptrauth_key_process_independent_code, pacDiversifier);
		vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ);
		return 0;
	}

	return -1;
}

int replace_bss_pointer(const struct mach_header *mh, void *pointerToReplace, void *replacementPointer)
{
	unsigned long bssSectionSize = 0;
	uint8_t *bssSection = getsectiondata((void *)mh, "__DATA", "__bss", &bssSectionSize);
	if (!bssSection) return 0;

	int c = 0;
	uint8_t *curPtr = bssSection;
	while (true) {
		void **found = memmem(curPtr, bssSectionSize - (curPtr - bssSection), &pointerToReplace, sizeof(pointerToReplace));
		if (!found) break;
		*found = replacementPointer;
		c++;
		curPtr = (uint8_t *)found + sizeof(pointerToReplace);
	}

	return c;
}

__attribute__((constructor)) static void initializer(void)
{
	load_process_info();
	os_log_dbg("Choicy works");

	if (gTweakInjectionDisabled || gAllowedTweaks || gDeniedTweaks || gGlobalDeniedTweaks) {
		os_log_dbg("Initializing Choicy...");

		void **dyld4Struct = litehook_find_dsc_symbol("/usr/lib/system/libdyld.dylib", "__ZN5dyld45gDyldE");
		if (dyld4Struct) {
			// iOS 15+
			// dyld_dynamic_interpose is a stub, so apply the hooks by overwriting function pointers in gDyld
			// This will catch *all* dlopen calls

			dyld_hook_routine(*dyld4Struct, 14, (void *)&dyld_dlopen_hook, (void **)&dyld_dlopen_orig, 0xBF31);
			dyld_hook_routine(*dyld4Struct, 97, (void *)&dyld_dlopen_from_hook, (void **)&dyld_dlopen_from_orig, 0xD48C);
		}
		else {
			// iOS <=14
			// gDyld does not exist yet, but dyld_dynamic_interpose still works, so use that
			// This will only catch dlopen calls originating from the tweak loader

			void *libdyldHandle = dlopen("/usr/lib/system/libdyld.dylib", RTLD_NOW);
			void *dlopen_from = dlsym(libdyldHandle, "dlopen_from");

			dlopen_orig = dlopen;
			if (dlopen_from) dlopen_from_orig = dlopen_from;

			const char *tweakLoaderPath = NULL;
			const struct mach_header *tweakLoaderHeader = find_tweak_loader_mach_header(&tweakLoaderPath);
			if (tweakLoaderHeader) {
				// On rootful / iOS <=14, there are multiple different special cases we need to take care of
				// First: substitute-loader.dylib is heavily obfuscated and gets the dlopen pointer via dlsym before Choicy runs
				// So in order to support substitute, we have to find the dlopen pointer in it's BSS section and replace it
				if (!strcmp(tweakLoaderPath, "/usr/lib/substitute-loader.dylib")) {
					__unused int c = replace_bss_pointer(tweakLoaderHeader, dlopen, dlopen_hook);
					os_log_dbg("Replaced %u dlopen pointer(s) in bss section", c);
					if (dlopen_from) {
						c = replace_bss_pointer(tweakLoaderHeader, dlopen_from, dlopen_from_hook);
						os_log_dbg("Replaced %u dlopen_from pointer(s) in bss section", c);
					}

					// Fall through, since older versions of substitute-loader still called dlopen normally and we don't know what we're dealing with
				}
#ifdef __arm64e__
				// Second: dyld_dynamic_interpose seems to cause a nullptr deref in arm64e processes
				// So, we have to use a litehook rebind instead
				litehook_rebind_symbol((const mach_header *)tweakLoaderHeader, dlopen, dlopen_hook);
				if (dlopen_from) {
					litehook_rebind_symbol((const mach_header *)tweakLoaderHeader, dlopen_from, dlopen_from_hook);
				}
				return;
#endif
				// If not arm64e, we can just use dyld_dynamic_interpose, which (unlike litehook) supports armv7 aswell
				static struct dyld_interpose_tuple interposes[2];
				interposes[0] = (struct dyld_interpose_tuple){ .replacement = dlopen_hook, .replacee = dlopen };
				if (dlopen_from) {
					interposes[1] = (struct dyld_interpose_tuple){ .replacement = dlopen_from_hook, .replacee = dlopen_from };
				}
				dyld_dynamic_interpose(tweakLoaderHeader, interposes, dlopen_from ? 2 : 1);
				os_log_dbg("Initialized %u interpose(s) in tweak loader", dlopen_from ? 2 : 1);
			}
			else {
				os_log_dbg("Unable to find tweak loader");
			}
		}
	}
}