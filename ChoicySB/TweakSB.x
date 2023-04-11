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

#import "SpringBoard.h"
#import "../Shared.h"
#import "ChoicyOverrideManager.h"
#import "../ChoicyPrefsMigrator.h"
#import <rootless.h>

NSBundle* CHBundle;
NSDictionary* preferences;

void reloadPreferences()
{
	if(preferences)
	{
		NSDictionary* oldPreferences = [preferences copy];
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];

		NSDictionary* appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
		NSDictionary* oldAppSettings = [oldPreferences objectForKey:kChoicyPrefsKeyAppSettings];

		NSMutableSet* allApps = [NSMutableSet setWithArray:[appSettings allKeys]];
		[allApps unionSet:[NSMutableSet setWithArray:[oldAppSettings allKeys]]];

		NSMutableSet* changedApps = [NSMutableSet new];

		for(NSString* appKey in allApps)
		{
			if(![((NSDictionary*)[appSettings objectForKey:appKey]) isEqualToDictionary:((NSDictionary*)[oldAppSettings objectForKey:appKey])])
			{
				[changedApps addObject:appKey];
			}
		}

		for(NSString* applicationID in changedApps)
		{
			if(![applicationID isEqualToString:kSpringboardBundleID] && ![applicationID isEqualToString:kPreferencesBundleID])
			{
				BKSTerminateApplicationForReasonAndReportWithDescription(applicationID, 5, false, @"Choicy - prefs changed, killed");
			}
		}
	}
	else
	{
		NSString *parentDir = [kChoicyPrefsPlistPath stringByDeletingLastPathComponent];
		if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir]) {
			[[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
		}
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];
	}
}

NSString* toggleOneTimeApplicationID;

BOOL shouldDisableTweakInjectionForApplication(NSString* applicationID)
{
	BOOL safeMode = NO;

	BOOL overrideExists;
	BOOL disableTweakInjectionOverrideValue = [[ChoicyOverrideManager sharedManager] disableTweakInjectionOverrideForApplication:applicationID overrideExists:&overrideExists];
	if(overrideExists)
	{
		return disableTweakInjectionOverrideValue;
	}

	NSDictionary* settingsForApp = processPreferencesForApplication(preferences, applicationID);

	if(settingsForApp && [settingsForApp isKindOfClass:[NSDictionary class]])
	{
		if(![applicationID isEqualToString:kPreferencesBundleID])
		{
			safeMode = ((NSNumber*)[settingsForApp objectForKey:kChoicyProcessPrefsKeyTweakInjectionDisabled]).boolValue;
		}
	}

	if([toggleOneTimeApplicationID isEqualToString:applicationID])
	{
		safeMode = !safeMode;
	}

	toggleOneTimeApplicationID = nil;

	return safeMode;
}

BOOL shouldShow3DTouchOptionForDisableTweakInjectionState(BOOL disableTweakInjectionState)
{
	BOOL shouldShow = NO;

	if(disableTweakInjectionState)
	{
		shouldShow = ((NSNumber*)[preferences objectForKey:@"launchWithTweaksOptionEnabled"]).boolValue;
	}
	else
	{
		NSNumber* shouldShowNumber = [preferences objectForKey:@"launchWithoutTweaksOptionEnabled"];
		if(shouldShowNumber)
		{
			shouldShow = shouldShowNumber.boolValue; 
		}
		else
		{
			shouldShow = YES;
		}
	}

	return shouldShow;
}

%hook FBProcessManager

%new
- (void)choicy_handleEnvironmentChangesForExecutionContext:(FBProcessExecutionContext*)executionContext withApplicationID:(NSString*)applicationID
{
	NSMutableDictionary* environmentM = [executionContext.environment mutableCopy];

	if(shouldDisableTweakInjectionForApplication(applicationID))
	{
		[environmentM setObject:@(1) forKey:@"_MSSafeMode"];
		[environmentM setObject:@(1) forKey:@"_SafeMode"];
	}
	else
	{
		ChoicyOverrideManager* overrideManager = [ChoicyOverrideManager sharedManager];
		BOOL overrideExists = NO;

		BOOL customTweakConfigurationEnabledOverride = [overrideManager customTweakConfigurationEnabledOverwriteForApplication:applicationID overrideExists:&overrideExists];
		if(overrideExists)
		{
			if(!customTweakConfigurationEnabledOverride)
			{
				// if custom tweak configuration has been overwritten with NO
				// set up an empty deny list
				[environmentM setObject:@"" forKey:@kEnvDeniedTweaksOverride];
			}
			else
			{
				BOOL customTweakAllowDenyOverride = [overrideManager customTweakConfigurationAllowDenyModeOverrideForApplication:applicationID overrideExists:&overrideExists];
				NSArray* allowDenyList = [overrideManager customTweakConfigurationAllowOrDenyListOverrideForApplication:applicationID overrideExists:&overrideExists];

				if(overrideManager && allowDenyList)
				{
					NSString* allowDenyString = [allowDenyList componentsJoinedByString:@"/"];

					NSString* envName;
					if(customTweakAllowDenyOverride) // DENY
					{
						envName = @kEnvDeniedTweaksOverride;
					}
					else //ALLOW
					{
						envName = @kEnvAllowedTweaksOverride;
					}

					//NSLog(@"set %@ to %@", envName, allowDenyString);

					[environmentM setObject:allowDenyString forKey:envName];
				}
			}
		}

		BOOL overwriteGlobalConfigurationOverride = [overrideManager overwriteGlobalConfigurationOverrideForApplication:applicationID overrideExists:&overrideExists];
		//NSLog(@"overwriteGlobalConfigurationOverride=%i overrideExists=%i", overwriteGlobalConfigurationOverride, overrideExists);
		if(overrideExists)
		{
			NSString* envToSet;
			if(overwriteGlobalConfigurationOverride)
			{
				envToSet = @"1";
			}
			else
			{
				envToSet = @"0";
			}

			[environmentM setObject:envToSet forKey:@kEnvOverwriteGlobalConfigurationOverride];
		}
	}

	executionContext.environment = [environmentM copy];
}

// iOS >= 15
- (id)_createProcessWithExecutionContext:(FBProcessExecutionContext*)executionContext error:(id*)arg2
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext withApplicationID:executionContext.identity.embeddedApplicationIdentifier];

	return %orig;
}

// iOS 13 - 14
- (id)_createProcessWithExecutionContext:(FBProcessExecutionContext*)executionContext
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext withApplicationID:executionContext.identity.embeddedApplicationIdentifier];

	return %orig;
}

// iOS <= 12
- (id)createApplicationProcessForBundleID:(NSString*)bundleID withExecutionContext:(FBProcessExecutionContext*)executionContext
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext withApplicationID:bundleID];

	return %orig;
}

%end

%group Shortcut_iOS13Up

%hook SBIconView

- (NSArray *)applicationShortcutItems
{
	NSArray* orig = %orig;

	NSString* applicationID;
	if([self respondsToSelector:@selector(applicationBundleIdentifier)])
	{
		applicationID = [self applicationBundleIdentifier];
	}
	else if([self respondsToSelector:@selector(applicationBundleIdentifierForShortcuts)])
	{
		applicationID = [self applicationBundleIdentifierForShortcuts];
	}

	if(!applicationID)
	{
		return orig;
	}

	BOOL tweakInjectionDisabled = shouldDisableTweakInjectionForApplication(applicationID);

	if(shouldShow3DTouchOptionForDisableTweakInjectionState(tweakInjectionDisabled))
	{
		SBSApplicationShortcutItem* toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];
		NSString *imageName;

		if(tweakInjectionDisabled)
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
			imageName = @"AppLaunchIcon";
		}
		else
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
			imageName = @"AppLaunchIcon_Crossed";
		}

		UIImage* imageToSet = [[UIImage imageNamed:imageName inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		toggleSafeModeOnceItem.icon = [[%c(SBSApplicationShortcutCustomImageIcon) alloc] initWithImageData:UIImagePNGRepresentation(imageToSet) dataType:0 isTemplate:1];

		toggleSafeModeOnceItem.bundleIdentifierToLaunch = applicationID;
		toggleSafeModeOnceItem.type = @"com.opa334.choicy.toggleSafeModeOnce";

		return [orig arrayByAddingObject:toggleSafeModeOnceItem];
	}

	return orig;
}

+ (void)activateShortcut:(SBSApplicationShortcutItem*)item withBundleIdentifier:(NSString*)bundleID forIconView:(id)iconView
{
	if([[item type] isEqualToString:@"com.opa334.choicy.toggleSafeModeOnce"])
	{
		BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, @"Choicy - force touch, killed");
		toggleOneTimeApplicationID = bundleID;
	}

	%orig;
}

%end

%end

%group Shortcut_iOS12Down

%hook SBUIAppIconForceTouchControllerDataProvider

- (NSArray *)applicationShortcutItems
{
	NSArray* orig = %orig;

	NSString* applicationID = [self applicationBundleIdentifier];

	if(!applicationID)
	{
		return orig;
	}

	BOOL disableTweakInjection = shouldDisableTweakInjectionForApplication(applicationID);

	if(shouldShow3DTouchOptionForDisableTweakInjectionState(disableTweakInjection))
	{
		SBSApplicationShortcutItem* toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];

		if(disableTweakInjection)
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
		}
		else
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
		}
		
		toggleSafeModeOnceItem.bundleIdentifierToLaunch = applicationID;
		toggleSafeModeOnceItem.type = @"com.opa334.choicy.toggleSafeModeOnce";

		if(!orig)
		{
			return @[toggleSafeModeOnceItem];
		}
		else
		{
			return [orig arrayByAddingObject:toggleSafeModeOnceItem];
		}
	}

	return orig;
}

%end

%hook SBUIAppIconForceTouchController

- (void)appIconForceTouchShortcutViewController:(id)arg1 activateApplicationShortcutItem:(SBSApplicationShortcutItem*)item
{
	if([item.type isEqualToString:@"com.opa334.choicy.toggleSafeModeOnce"])
	{
		NSString* bundleID = item.bundleIdentifierToLaunch;

		BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, @"Choicy - force touch, killed");
		toggleOneTimeApplicationID = bundleID;
	}

	%orig;
}

%end

%hook SBUIAction

- (id)initWithTitle:(id)title subtitle:(id)arg2 image:(id)image badgeView:(id)arg4 handler:(id)arg5
{
    if([title isEqualToString:localize(@"LAUNCH_WITHOUT_TWEAKS")])
	{
        image = [[UIImage imageNamed:@"AppLaunchIcon_Crossed_Big" inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
	else if([title isEqualToString:localize(@"LAUNCH_WITH_TWEAKS")])
	{
		image = [[UIImage imageNamed:@"AppLaunchIcon_Big" inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	}

    return %orig;
}

%end

%end

@interface FBSystemService
+ (id)sharedInstance;
- (void)exitAndRelaunch:(BOOL)arg1;
@end

void respring(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
  [[%c(FBSystemService) sharedInstance] exitAndRelaunch:YES];
}

%ctor
{
	%init();

	reloadPreferences();
	if(preferences && [ChoicyPrefsMigrator preferencesNeedMigration:preferences])
	{
		NSMutableDictionary* preferencesM = preferences.mutableCopy;
		[ChoicyPrefsMigrator migratePreferences:preferencesM];
		[ChoicyPrefsMigrator updatePreferenceVersion:preferencesM];
		[preferencesM writeToFile:kChoicyPrefsPlistPath atomically:NO];
		reloadPreferences();
	}

	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, respring, CFSTR("com.opa334.choicy/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	CHBundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/Choicy.bundle")];

	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0)
	{
		%init(Shortcut_iOS13Up);
	}
	else
	{
		%init(Shortcut_iOS12Down);
	}
}