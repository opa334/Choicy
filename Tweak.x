// Copyright (c) 2017-2019 Lars Fröder

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

		if([[NSFileManager defaultManager] fileExistsAtPath:plistPath])
		{
			//Shoutouts to libFLEX for having a plist with an empty bundles entry
			NSDictionary* bundlePlistDict = [NSDictionary dictionaryWithContentsOfFile:plistPath];

			NSDictionary* filter = [bundlePlistDict objectForKey:@"Filter"];
			NSDictionary* bundles = [filter objectForKey:@"Bundles"];
			NSDictionary* executables = [filter objectForKey:@"Executables"];

			if(bundles.count > 0 || executables.count > 0)
			{
				return YES;
			}
		}
	}

	return NO;
}

BOOL shouldLoadDylib(NSString* dylibPath)
{
	if(isTweakDylib(dylibPath))
	{
		NSString* dylibName = [dylibPath.lastPathComponent stringByDeletingPathExtension];

		if([dylibName isEqualToString:@"ChoicySB"])
		{
			return YES;
		}

		if(isApplication)
		{
			if([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Preferences"] && [dylibName isEqualToString:@"PreferenceLoader"])
			{
				return YES;
			}
		}

		BOOL tweakIsInWhitelist = [tweakWhitelist containsObject:dylibName];
		BOOL tweakIsInBlacklist = [tweakBlacklist containsObject:dylibName];
		BOOL tweakIsInGlobalBlacklist = [globalTweakBlacklist containsObject:dylibName];

		if(tweakIsInGlobalBlacklist)
		{
			if(tweakWhitelist && tweakIsInWhitelist && allowWhitelistOverwrites)
			{
				return YES;
			}

			if(tweakBlacklist && !tweakIsInBlacklist && allowBlacklistOverwrites)
			{
				return YES;
			}

			return NO;
		}

		if(tweakWhitelist && !tweakIsInWhitelist)
		{
			return NO;
		}

		if(tweakBlacklist && tweakIsInBlacklist)
		{
			return NO;
		}
	}

	return YES;
}

%group BlockAllTweaks

%hookf(void *, dlopen, const char *path, int mode)
{
	if(path != NULL)
	{
		NSString* dylibPath = @(path);

		if(isTweakDylib(dylibPath))
		{
			if(![dylibPath.lastPathComponent isEqualToString:@"ChoicySB.dylib"])
			{
				return NULL;
			}
		}
	}

	return %orig;
}

%end

%group CustomConfiguration

%hookf(void *, dlopen, const char *path, int mode)
{
	if(path != NULL)
	{
		NSString* dylibPath = @(path);

		if(!shouldLoadDylib(dylibPath))
		{
			return NULL;
		}
	}

	return %orig;
}

%end

%ctor
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
				return;
			}
		}
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

		%init(CustomConfiguration);
	}
}