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

#import "SpringBoard.h"
#import "../Shared.h"

void reloadPreferences()
{
	if(preferences)
	{
		NSDictionary* oldPreferences = [preferences copy];
		preferences = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];

		NSDictionary* appSettings = [preferences objectForKey:@"appSettings"];
		NSDictionary* oldAppSettings = [oldPreferences objectForKey:@"appSettings"];

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
			if(![applicationID isEqualToString:@"com.apple.springboard"] && ![applicationID isEqualToString:@"com.apple.Preferences"])
			{
				BKSTerminateApplicationForReasonAndReportWithDescription(applicationID, 5, false, @"Choicy - prefs changed, killed");
			}
		}
	}
	else
	{
		preferences = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	}
}

NSString* toggleOneTimeApplicationID;

BOOL shouldEnableSafeModeForApplicationWithID(NSString* applicationID)
{
	BOOL safeMode = NO;

	NSDictionary* settingsForApp = preferencesForApplicationWithID(applicationID);

	if(settingsForApp && [settingsForApp isKindOfClass:[NSDictionary class]])
	{
		safeMode = ((NSNumber*)[settingsForApp objectForKey:@"tweakInjectionDisabled"]).boolValue;
	}

	if([toggleOneTimeApplicationID isEqualToString:applicationID])
	{
		safeMode = !safeMode;
	}

	toggleOneTimeApplicationID = nil;

	return safeMode;
}

BOOL shouldShow3DTouchOptionForSafeModeState(BOOL safeModeState)
{
	BOOL shouldShow = NO;

	if(safeModeState)
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

%group iOS10Down
%hook SBApplication

- (id)valueForKeyPath:(NSString*)keyPath
{
	if([keyPath isEqualToString:@"info.choicy_hasHiddenTag"])
	{
		return [[self _appInfo] valueForKey:@"choicy_hasHiddenTag"];
	}

	return %orig;
}

%end
%end

%hook SBApplicationInfo

- (id)valueForKey:(NSString*)key
{
	if([key isEqualToString:@"choicy_executablePath"])
	{
		return self.executableURL.path;
	}

	if([key isEqualToString:@"choicy_hasHiddenTag"])
	{
		if([self respondsToSelector:@selector(hasHiddenTag)])
		{
			return @(self.hasHiddenTag);
		}
		else if([self respondsToSelector:@selector(tags)])
		{
			return @([self.tags containsObject:@"hidden"]);
		}
	}

	return %orig;
}

%end

%hook FBProcessManager

%new
- (void)handleSafeModeForExecutionContext:(FBProcessExecutionContext*)executionContext withApplicationID:(NSString*)applicationID
{
	if(shouldEnableSafeModeForApplicationWithID(applicationID))
	{
		NSMutableDictionary* environmentM = [executionContext.environment mutableCopy];
		[environmentM setObject:@(1) forKey:@"_MSSafeMode"];
		[environmentM setObject:@(1) forKey:@"_SafeMode"];
		executionContext.environment = [environmentM copy];
	}
}

%group SafeMode_iOS13Up

- (id)_createProcessWithExecutionContext:(FBProcessExecutionContext*)executionContext
{
	[self handleSafeModeForExecutionContext:executionContext withApplicationID:executionContext.identity.embeddedApplicationIdentifier];

	return %orig;
}

%end

%group SafeMode_iOS12Down

- (id)createApplicationProcessForBundleID:(NSString*)bundleID withExecutionContext:(FBProcessExecutionContext*)executionContext
{
	[self handleSafeModeForExecutionContext:executionContext withApplicationID:bundleID];

	return %orig;
}

%end

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

	BOOL isSafeMode = shouldEnableSafeModeForApplicationWithID(applicationID);

	if(shouldShow3DTouchOptionForSafeModeState(isSafeMode))
	{
		SBSApplicationShortcutItem* toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];

		if(isSafeMode)
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
		}
		else
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
		}
		
		//toggleSafeModeOnceItem.icon = [[%c(SBSApplicationShortcutSystemItem) alloc] initWithSystemImageName:@"fx"];
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

	BOOL isSafeMode = shouldEnableSafeModeForApplicationWithID(applicationID);

	if(shouldShow3DTouchOptionForSafeModeState(isSafeMode))
	{
		SBSApplicationShortcutItem* toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];

		if(isSafeMode)
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
		}
		else
		{
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
		}
		
		//toggleSafeModeOnceItem.icon = [[%c(SBSApplicationShortcutSystemItem) alloc] init];
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
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, respring, CFSTR("com.opa334.choicy/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0)
	{
		%init(SafeMode_iOS13Up);
		%init(Shortcut_iOS13Up);
	}
	else
	{
		%init(SafeMode_iOS12Down);
		%init(Shortcut_iOS12Down);
	}

	if(kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_11_0)
	{
		%init(iOS10Down);
	}
}