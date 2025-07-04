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

#import "../Shared.h"
#import "../ChoicyPrefsMigrator.h"
#import "SpringBoard.h"
#import "ChoicyOverrideManager.h"
#import <UIKit/UIKit.h>
#import <libroot.h>
#import "ChoicySB.h"

NSBundle *CHBundle;
NSString *toggleOneTimeApplicationID;

BOOL choicy_shouldShow3DTouchOptionForDisableTweakInjectionState(BOOL disableTweakInjectionState)
{
	BOOL shouldShow = NO;

	if (disableTweakInjectionState) {
		shouldShow = ((NSNumber *)[preferences objectForKey:@"launchWithTweaksOptionEnabled"]).boolValue;
	}
	else {
		NSNumber *shouldShowNumber = [preferences objectForKey:@"launchWithoutTweaksOptionEnabled"];
		if (shouldShowNumber) {
			shouldShow = shouldShowNumber.boolValue; 
		}
		else {
			shouldShow = YES;
		}
	}

	return shouldShow;
}

%hook FBProcessManager

%new
- (void)choicy_handleEnvironmentChangesForExecutionContext:(FBProcessExecutionContext *)executionContext forAppWithBundleIdentifier:(NSString *)bundleIdentifier
{
	BOOL toggleOnce = [toggleOneTimeApplicationID isEqualToString:bundleIdentifier];
	toggleOneTimeApplicationID = nil;
	if (toggleOnce) {
		NSMutableDictionary *environmentM = [executionContext.environment mutableCopy];
		BOOL shouldDisableTweaks = !choicy_shouldDisableTweakInjectionForApplication(bundleIdentifier);
		if (shouldDisableTweaks) {
			[environmentM setObject:@(shouldDisableTweaks) forKey:@"_MSSafeMode"];
			[environmentM setObject:@(shouldDisableTweaks) forKey:@"_SafeMode"];
		}
		else {
			// If the the "Launch with Tweaks" option was pressed, we need to let the Choicy dylib know
			[environmentM setObject:@YES forKey:@"_ChoicyInjectionEnabledFromSpringBoard"];
		}

		executionContext.environment = [environmentM copy];
	}
	
	// runningboardd only exists on iOS 13 and up, so on lower versions we need to handle the logic in SpringBoard
	if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_13_0) {
		choicy_applyEnvironmentChangesToExecutionContext(executionContext, bundleIdentifier);
	}	
}

// iOS >= 15
- (id)_bootstrapProcessWithExecutionContext:(FBProcessExecutionContext *)executionContext synchronously:(BOOL)synchronously error:(id *)error
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext forAppWithBundleIdentifier:executionContext.identity.embeddedApplicationIdentifier];

	return %orig;
}

// iOS 13 - 14
- (id)_createProcessWithExecutionContext:(FBProcessExecutionContext *)executionContext
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext forAppWithBundleIdentifier:executionContext.identity.embeddedApplicationIdentifier];

	return %orig;
}

// iOS <= 12
- (id)createApplicationProcessForBundleID:(NSString *)bundleIdentifier withExecutionContext:(FBProcessExecutionContext *)executionContext
{
	[self choicy_handleEnvironmentChangesForExecutionContext:executionContext forAppWithBundleIdentifier:bundleIdentifier];

	return %orig;
}

%end

%group Shortcut_iOS13Up

%hook SBIconView

- (NSArray *)applicationShortcutItems
{
	NSArray *orig = %orig;

	NSString *applicationID;
	if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
		applicationID = [self applicationBundleIdentifier];
	}
	else if ([self respondsToSelector:@selector(applicationBundleIdentifierForShortcuts)]) {
		applicationID = [self applicationBundleIdentifierForShortcuts];
	}

	if (!applicationID) {
		return orig;
	}

	BOOL tweakInjectionDisabled = choicy_shouldDisableTweakInjectionForApplication(applicationID);

	if (choicy_shouldShow3DTouchOptionForDisableTweakInjectionState(tweakInjectionDisabled)) {
		SBSApplicationShortcutItem *toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];
		NSString *imageName;

		if (tweakInjectionDisabled) {
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
			imageName = @"AppLaunchIcon";
		}
		else {
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
			imageName = @"AppLaunchIcon_Crossed";
		}

		UIImage *imageToSet = [[UIImage imageNamed:imageName inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		toggleSafeModeOnceItem.icon = [[%c(SBSApplicationShortcutCustomImageIcon) alloc] initWithImageData:UIImagePNGRepresentation(imageToSet) dataType:0 isTemplate:1];

		toggleSafeModeOnceItem.bundleIdentifierToLaunch = applicationID;
		toggleSafeModeOnceItem.type = @"com.opa334.choicy.toggleSafeModeOnce";

		return [orig arrayByAddingObject:toggleSafeModeOnceItem];
	}

	return orig;
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView
{
	if ([[item type] isEqualToString:@"com.opa334.choicy.toggleSafeModeOnce"]) {
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
	NSArray *orig = %orig;

	NSString *applicationID = [self applicationBundleIdentifier];

	if (!applicationID) {
		return orig;
	}

	BOOL disableTweakInjection = choicy_shouldDisableTweakInjectionForApplication(applicationID);

	if (choicy_shouldShow3DTouchOptionForDisableTweakInjectionState(disableTweakInjection)) {
		SBSApplicationShortcutItem *toggleSafeModeOnceItem = [[%c(SBSApplicationShortcutItem) alloc] init];

		if (disableTweakInjection) {
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITH_TWEAKS");
		}
		else {
			toggleSafeModeOnceItem.localizedTitle = localize(@"LAUNCH_WITHOUT_TWEAKS");
		}
		
		toggleSafeModeOnceItem.bundleIdentifierToLaunch = applicationID;
		toggleSafeModeOnceItem.type = @"com.opa334.choicy.toggleSafeModeOnce";

		if (!orig) {
			return @[toggleSafeModeOnceItem];
		}
		else {
			return [orig arrayByAddingObject:toggleSafeModeOnceItem];
		}
	}

	return orig;
}

%end

%hook SBUIAppIconForceTouchController

- (void)appIconForceTouchShortcutViewController:(id)arg1 activateApplicationShortcutItem:(SBSApplicationShortcutItem *)item
{
	if ([item.type isEqualToString:@"com.opa334.choicy.toggleSafeModeOnce"]) {
		NSString *bundleID = item.bundleIdentifierToLaunch;

		BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, @"Choicy - force touch, killed");
		toggleOneTimeApplicationID = bundleID;
	}

	%orig;
}

%end

%hook SBUIAction

- (id)initWithTitle:(id)title subtitle:(id)arg2 image:(id)image badgeView:(id)arg4 handler:(id)arg5
{
    if ([title isEqualToString:localize(@"LAUNCH_WITHOUT_TWEAKS")]) {
        image = [[UIImage imageNamed:@"AppLaunchIcon_Crossed_Big" inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
	else if ([title isEqualToString:localize(@"LAUNCH_WITH_TWEAKS")]) {
		image = [[UIImage imageNamed:@"AppLaunchIcon_Big" inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	}

    return %orig;
}

%end

%end

void respring(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	[[%c(FBSystemService) sharedInstance] exitAndRelaunch:YES];
}

void choicy_initSpringBoard(void)
{
	%init();

	CHBundle = [NSBundle bundleWithPath:JBROOT_PATH_NSSTRING(@"/Library/Application Support/Choicy.bundle")];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, respring, CFSTR("com.opa334.choicy/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0) {
		%init(Shortcut_iOS13Up);
	}
	else {
		%init(Shortcut_iOS12Down);
	}
}