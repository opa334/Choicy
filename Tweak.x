// Copyright (c) 2019-2020 Lars Fröder

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

#import <dlfcn.h>
//#import <mach-o/dyld.h>

NSArray* tweakWhitelist;
NSArray* tweakBlacklist;

NSArray* globalTweakBlacklist;
BOOL allowBlacklistOverwrites;
BOOL allowWhitelistOverwrites;
BOOL isApplication;

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
		HBLogDebug(@"tweakWhitelist = %@", tweakWhitelist);
		HBLogDebug(@"tweakBlacklist = %@", tweakBlacklist);
		HBLogDebug(@"globalTweakBlacklist = %@", globalTweakBlacklist);

		if([dylibName isEqualToString:@"ChoicySB"])
		{
			HBLogDebug(@"Loaded because ChoicySB");
			return YES;
		}

		if(isApplication)
		{
			if([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Preferences"] && [dylibName isEqualToString:@"PreferenceLoader"])
			{
				HBLogDebug(@"Loaded because PreferenceLoader");
				return YES;
			}
		}

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

%group BlockAllTweaks

%hookf(void *, dlopen, const char *path, int mode)
{
	@autoreleasepool
	{
		if(path != NULL)
		{
			NSString* dylibPath = @(path);

			if(isTweakDylib(dylibPath))
			{
				if(![dylibPath.lastPathComponent isEqualToString:@"ChoicySB.dylib"])
				{
					HBLogDebug(@"%@ not loaded because all tweaks blocked", dylibPath.lastPathComponent);
					return NULL;
				}
			}

			HBLogDebug(@"%@ loaded because not a tweak", dylibPath.lastPathComponent);
		}
	}
	
	return %orig;
}

%end

%group CustomConfiguration

%hookf(void *, dlopen, const char *path, int mode)
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

	return %orig;
}

%end

%ctor
{
	@autoreleasepool
	{
		HBLogDebug(@"CHOICY INIT");

		preferences = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];

		NSString* executablePath = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments].firstObject;

		isApplication = [executablePath containsString:@"/Application"] || [executablePath containsString:@"/CoreServices"];
		NSDictionary* settings;

		if(isApplication)
		{
			settings = preferencesForApplicationWithID([NSBundle mainBundle].bundleIdentifier);
		}
		else
		{
			settings = preferencesForDaemonWithDisplayName(executablePath.lastPathComponent);
		}

		HBLogDebug(@"settings = %@", settings);

		globalTweakBlacklist = [preferences objectForKey:@"globalTweakBlacklist"] ?: [NSArray new];
		allowBlacklistOverwrites = ((NSNumber*)[preferences objectForKey:@"allowBlacklistOverwrites"]).boolValue;
		allowWhitelistOverwrites = ((NSNumber*)[preferences objectForKey:@"allowWhitelistOverwrites"]).boolValue;

		BOOL tweakInjectionDisabled = NO;
		BOOL customTweakConfigurationEnabled = NO;
		NSInteger whitelistBlacklistSegment = 0;

		if(settings)
		{
			tweakInjectionDisabled = ((NSNumber*)[settings objectForKey:@"tweakInjectionDisabled"]).boolValue;
			customTweakConfigurationEnabled = ((NSNumber*)[settings objectForKey:@"customTweakConfigurationEnabled"]).boolValue;
			whitelistBlacklistSegment = ((NSNumber*)[settings objectForKey:@"whitelistBlacklistSegment"]).intValue;
		}

		if(tweakInjectionDisabled)
		{
			if(isApplication)
			{
				if(![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"])
				{
					HBLogDebug(@"exiting cause application and tweakInjectionDisabled");
					return;
				}
			}

			HBLogDebug(@"blocking all tweaks");
			%init(BlockAllTweaks);
		}
		else if(customTweakConfigurationEnabled || globalTweakBlacklist.count > 0)
		{
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

			HBLogDebug(@"initialising custom configuration");
			%init(CustomConfiguration);
		}
	}
}