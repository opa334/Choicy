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

#import "ChoicyPrefsMigrator.h"
#import "Shared.h"

void renameKey(NSMutableDictionary* dict, NSString* key, NSString* newKey)
{
	if(!dict || !key || !newKey) return;
	NSObject* value = dict[key];
	if(!value) return;
	[dict removeObjectForKey:key];
	dict[newKey] = value;
}

void renameKeys(NSMutableDictionary* dict, NSDictionary* keyChanges)
{
	if(!dict || !keyChanges) return;

	[keyChanges enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* newKey, BOOL *stop)
	{
		renameKey(dict, key, newKey);
	}];
}

void removeKeys(NSMutableDictionary* dict, NSArray* keys)
{
	if(!dict || !keys) return;

	[keys enumerateObjectsUsingBlock:^(NSString* key, NSUInteger idx, BOOL* stop)
	{
		[dict removeObjectForKey:key];
	}];
}

@implementation ChoicyPrefsMigrator

+ (BOOL)preferencesNeedMigration:(NSDictionary*)prefs
{
	NSInteger preferenceVersion = parseNumberInteger(prefs[kChoicyPrefsVersionKey], 0);
	return preferenceVersion < kChoicyPrefsCurrentVersion;
}

+ (void)migratePreferences:(NSMutableDictionary*)prefs
{
	NSInteger preferenceVersion = parseNumberInteger(prefs[kChoicyPrefsVersionKey], 0);

	// pre 1.4 -> 1.4
	if(preferenceVersion == 0)
	{
		BOOL prev_allowBlacklistOverwrites = parseNumberBool(prefs[@"allowBlacklistOverwrites"], NO);
		BOOL prev_allowWhitelistOverwrites = parseNumberBool(prefs[@"allowWhitelistOverwrites"], NO);

		renameKeys(prefs, kChoicyPrefMigration1_4_ChangedKeys);
		removeKeys(prefs, kChoicyPrefMigration1_4_RemovedKeys);

		void (^processPrefsHandler)(NSMutableDictionary*, NSString*, NSDictionary*, BOOL*) = ^(NSMutableDictionary* sourceDict, NSString* key, NSDictionary* processPrefs, BOOL* stop)
		{
			NSMutableDictionary* processPrefsM = processPrefs.mutableCopy;
			renameKeys(processPrefsM, kChoicyProcessPrefMigration1_4_ChangedKeys);

			BOOL customTweakConfigurationEnabled = parseNumberBool(processPrefsM[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled], NO);
			if(customTweakConfigurationEnabled)
			{
				NSInteger allowDenyMode = parseNumberInteger(processPrefsM[kChoicyProcessPrefsKeyAllowDenyMode], 1);
				if((allowDenyMode == 1 && prev_allowWhitelistOverwrites) || (allowDenyMode == 2 && prev_allowBlacklistOverwrites)) // ALLOW
				{
					processPrefsM[kChoicyProcessPrefsKeyOverwriteGlobalTweakConfiguration] = @YES;
				}
			}

			sourceDict[key] = processPrefsM.copy;
		};

		NSMutableDictionary* appSettings = [prefs[kChoicyPrefsKeyAppSettings] mutableCopy];
		NSMutableDictionary* daemonSettings = [prefs[kChoicyPrefsKeyDaemonSettings] mutableCopy];

		if(appSettings)
		{
			[appSettings enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary* processPrefs, BOOL* stop)
			{
				processPrefsHandler(appSettings, key, processPrefs, stop);
			}];
			prefs[kChoicyPrefsKeyAppSettings] = appSettings.copy;
		}

		if(daemonSettings)
		{
			[daemonSettings enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary* processPrefs, BOOL* stop)
			{
				processPrefsHandler(daemonSettings, key, processPrefs, stop);
			}];
			prefs[kChoicyPrefsKeyDaemonSettings] = daemonSettings.copy;
		}
	}
}

+ (void)updatePreferenceVersion:(NSMutableDictionary*)prefs
{
	prefs[kChoicyPrefsVersionKey] = @kChoicyPrefsCurrentVersion;
}

@end