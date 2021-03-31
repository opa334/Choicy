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

#import "Shared.h"
#import <substrate.h>
#import <dlfcn.h>

BOOL tweakInjectionDisabled = NO;
BOOL customTweakConfigurationEnabled = NO;

NSArray* tweakWhitelist;
NSArray* tweakBlacklist;

NSArray* globalTweakBlacklist;
BOOL allowBlacklistOverwrites;
BOOL allowWhitelistOverwrites;
BOOL isApplication;

NSString* bundleIdentifier;

//methods of getting executablePath and bundleIdentifier with the least side effects possible
//for more information, check out https://github.com/checkra1n/BugTracker/issues/343
extern char*** _NSGetArgv();
NSString* safe_getExecutablePath()
{
	char* executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

NSString* safe_getBundleIdentifier()
{
	CFBundleRef mainBundle = CFBundleGetMainBundle();

	if(mainBundle != NULL)
	{
		CFStringRef bundleIdentifierCF = CFBundleGetIdentifier(mainBundle);

		return (__bridge NSString*)bundleIdentifierCF;
	}

	return nil;
}

BOOL isTweakDylib(NSString* dylibPath)
{
	if([dylibPath containsString:@"TweakInject"] || [dylibPath containsString:@"MobileSubstrate/DynamicLibraries"])
	{
		NSString* plistPath = [[dylibPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"plist"];

		HBLogDebug(@"plistPath = %@", plistPath);

		if([[NSFileManager defaultManager] fileExistsAtPath:plistPath])
		{
			//Shoutouts to libFLEX for having a plist with an empty bundles entry
			NSDictionary* bundlePlistDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];

			HBLogDebug(@"bundlePlistDict = %@", bundlePlistDict);

			NSDictionary* filter = [bundlePlistDict objectForKey:@"Filter"];

			for(NSString* key in [filter allKeys])
			{
				NSObject* obj = [filter objectForKey:key];

				if([obj respondsToSelector:@selector(count)])
				{
					NSArray* arrObj = (NSArray*)obj;

					if(arrObj.count > 0)
					{
						HBLogDebug(@"%@ was determined to be a tweak", dylibPath.lastPathComponent);
						return YES;
					}
				}
			}
		}
	}

	HBLogDebug(@"%@ was determined NOT to be a tweak", dylibPath.lastPathComponent);
	return NO;
}

BOOL shouldLoadDylib(NSString* dylibPath)
{
	if(isTweakDylib(dylibPath))
	{
		NSString* dylibName = [dylibPath.lastPathComponent stringByDeletingPathExtension];

		HBLogDebug(@"Checking whether %@ should be loaded", dylibName);

		//Don't prevent ChoicySB from loading into SpringBoard cause otherwise the 3d shortcuts and disabling tweaks inside applications doesn't work
		if([dylibName isEqualToString:@"ChoicySB"])
		{
			HBLogDebug(@"Loaded because ChoicySB");
			return YES;
		}

		if([dylibName isEqualToString:@"   Choicy"])
		{
			HBLogDebug(@"Loaded because Choicy main dylib");
			return YES;
		}

		//Don't prevent AppList from loading into SpringBoard cause otherwise the Choicy application settings break
		if([bundleIdentifier isEqualToString:@"com.apple.springboard"] && [dylibName isEqualToString:@"AppList"])
		{
			HBLogDebug(@"Loaded because AppList");
			return YES;
		}

		if(isApplication)
		{
			//Don't prevent PreferenceLoader from loading into Preferences.app cause otherwise once disabled it could never be reenabled
			if([bundleIdentifier isEqualToString:@"com.apple.Preferences"] && [dylibName isEqualToString:@"PreferenceLoader"])
			{
				HBLogDebug(@"Loaded because PreferenceLoader");
				return YES;
			}
		}

		if(tweakInjectionDisabled)
		{
			HBLogDebug(@"Not loading because tweakInjectionDisabled is enabled");
			return NO;
		}

		HBLogDebug(@"tweakWhitelist = %@", tweakWhitelist);
		HBLogDebug(@"tweakBlacklist = %@", tweakBlacklist);
		HBLogDebug(@"globalTweakBlacklist = %@", globalTweakBlacklist);

		BOOL tweakIsInWhitelist = [tweakWhitelist containsObject:dylibName];
		BOOL tweakIsInBlacklist = [tweakBlacklist containsObject:dylibName];
		BOOL tweakIsInGlobalBlacklist = [globalTweakBlacklist containsObject:dylibName];

		HBLogDebug(@"tweakIsInWhitelist = %d", tweakIsInWhitelist);
		HBLogDebug(@"tweakIsInBlacklist = %d", tweakIsInBlacklist);
		HBLogDebug(@"tweakIsInGlobalBlacklist = %d", tweakIsInGlobalBlacklist);

		if(tweakIsInGlobalBlacklist)
		{
			if(tweakWhitelist && tweakIsInWhitelist && allowWhitelistOverwrites)
			{
				HBLogDebug(@"Loaded because tweakWhitelist && tweakIsInWhitelist && allowWhitelistOverwrites");
				return YES;
			}

			if(tweakBlacklist && !tweakIsInBlacklist && allowBlacklistOverwrites)
			{
				HBLogDebug(@"Loaded because tweakBlacklist && !tweakIsInBlacklist && allowBlacklistOverwrites");
				return YES;
			}

			HBLogDebug(@"Not loaded because in global blacklist");
			return NO;
		}

		if(tweakWhitelist && !tweakIsInWhitelist)
		{
			HBLogDebug(@"Not loaded because not in whitelist");
			return NO;
		}

		if(tweakBlacklist && tweakIsInBlacklist)
		{
			HBLogDebug(@"Not loaded because in blacklist");
			return NO;
		}
	}

	HBLogDebug(@"Loaded");
	return YES;
}

void* (*dlopen_internal)(const char*, int, void*);
void* $dlopen_internal(const char *path, int mode, void* lr)
{
	@autoreleasepool
	{
		if(path != NULL)
		{
			NSString* dylibPath = @(path);

			if(!shouldLoadDylib(dylibPath))
			{
				HBLogDebug(@"%@ not loaded", dylibPath.lastPathComponent);
				return NULL;
			}

			HBLogDebug(@"%@ loaded", dylibPath.lastPathComponent);
		}
	}
	return dlopen_internal(path, mode, lr);
}

void* (*dlopen_regular)(const char*, int);
void* $dlopen_regular(const char *path, int mode)
{
	@autoreleasepool
	{
		if(path != NULL)
		{
			NSString* dylibPath = @(path);

			if(!shouldLoadDylib(dylibPath))
			{
				HBLogDebug(@"%@ not loaded", dylibPath.lastPathComponent);
				return NULL;
			}

			HBLogDebug(@"%@ loaded", dylibPath.lastPathComponent);
		}
	}
	return dlopen_regular(path, mode);
}

%ctor
{
	@autoreleasepool
	{
		HBLogDebug(@"CHOICY INIT");

		preferences = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];

		NSString* executablePath = safe_getExecutablePath();
		bundleIdentifier = safe_getBundleIdentifier();

		isApplication = [executablePath containsString:@"/Application"] || [executablePath containsString:@"/CoreServices"];
		NSDictionary* settings;

		if(isApplication)
		{
			settings = preferencesForApplicationWithID(bundleIdentifier);
		}
		else
		{
			settings = preferencesForDaemonWithDisplayName(executablePath.lastPathComponent);
		}

		HBLogDebug(@"settings = %@", settings);

		globalTweakBlacklist = [preferences objectForKey:@"globalTweakBlacklist"] ?: [NSArray new];
		allowBlacklistOverwrites = ((NSNumber*)[preferences objectForKey:@"allowBlacklistOverwrites"]).boolValue;
		allowWhitelistOverwrites = ((NSNumber*)[preferences objectForKey:@"allowWhitelistOverwrites"]).boolValue;

		NSInteger whitelistBlacklistSegment = 0;

		if(settings)
		{
			tweakInjectionDisabled = ((NSNumber*)[settings objectForKey:@"tweakInjectionDisabled"]).boolValue;
			customTweakConfigurationEnabled = ((NSNumber*)[settings objectForKey:@"customTweakConfigurationEnabled"]).boolValue;
			whitelistBlacklistSegment = ((NSNumber*)[settings objectForKey:@"whitelistBlacklistSegment"]).intValue;
		}

		if(tweakInjectionDisabled || customTweakConfigurationEnabled || globalTweakBlacklist.count > 0)
		{
			//If tweakInjectionDisabled is true for an application other than SpringBoard,
			//it means that tweak injection was enabled for one launch via 3D touch and we should not do anything
			if(isApplication && tweakInjectionDisabled)
			{
				if(![bundleIdentifier isEqualToString:@"com.apple.springboard"])
				{
					HBLogDebug(@"tweak injection has been enabled via 3D touch, bye!");
					return;
				}
			}

			if(customTweakConfigurationEnabled)
			{
				if(whitelistBlacklistSegment == 2) //blacklist
				{
					tweakBlacklist = [settings objectForKey:@"tweakBlacklist"] ?: [NSArray new];
				}
				else //whitelist
				{
					tweakWhitelist = [settings objectForKey:@"tweakWhitelist"] ?: [NSArray new];
				}
			}

			MSImageRef libdyldImage = MSGetImageByName("/usr/lib/system/libdyld.dylib");

			if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_14_1)
			{
				MSHookFunction(MSFindSymbol(libdyldImage, "__ZL15dlopen_internalPKciPv"), (void*)$dlopen_internal, (void**)&dlopen_internal);
			}
			else
			{
				MSHookFunction(MSFindSymbol(libdyldImage, "_dlopen"), (void*)$dlopen_regular, (void**)&dlopen_regular);
			}
		}
	}
}