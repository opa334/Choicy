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
#import "../ChoicyRoot.h"
#import "ChoicySB.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

NSBundle *CHBundle;
NSString *toggleOneTimeApplicationID;
static NSString *const kChoicyLaunchShortcutType = @"com.opa334.choicy.toggleSafeModeOnce";
static NSString *const kChoicyOpenShortcutType = @"com.opa334.choicy.openInChoicy";
static NSHashTable<SBIconView *> *choicyVisibleIconViews;
static char choicyIconTagKey;

static NSString *choicyApplicationIDForIconView(SBIconView *view)
{
	SBIcon *icon = [view respondsToSelector:@selector(icon)] ? [view icon] : nil;
	BOOL isApplication = [icon respondsToSelector:@selector(isApplicationIcon)]
		? [icon isApplicationIcon] : [icon isKindOfClass:NSClassFromString(@"SBApplicationIcon")];
	if (!isApplication) return nil;
	NSString *applicationID = nil;
	// The icon model supplies the bundle ID on iOS 10-12, where the newer
	// shortcut-specific SBIconView selectors may not exist.
	if ([icon respondsToSelector:@selector(applicationBundleID)]) applicationID = [icon applicationBundleID];
	if (!applicationID.length && [icon respondsToSelector:@selector(applicationBundleIdentifier)]) applicationID = [icon applicationBundleIdentifier];
	if (!applicationID.length && [icon respondsToSelector:@selector(application)]) {
		SBApplication *application = [icon application];
		if ([application respondsToSelector:@selector(bundleIdentifier)]) applicationID = [application bundleIdentifier];
	}
	if (!applicationID.length && [view respondsToSelector:@selector(applicationBundleIdentifier)]) applicationID = [view applicationBundleIdentifier];
	if (!applicationID.length && [view respondsToSelector:@selector(applicationBundleIdentifierForShortcuts)]) applicationID = [view applicationBundleIdentifierForShortcuts];
	return applicationID.length ? applicationID : nil;
}

static void choicyUpdateIconTag(SBIconView *view)
{
	UIView *tag = objc_getAssociatedObject(view, &choicyIconTagKey);
	NSString *applicationID = choicyApplicationIDForIconView(view);
	BOOL show = view.window && applicationID.length
		&& parseNumberBool(preferences[kChoicyPrefsKeyTagCustomAppsEnabled], NO)
		&& processPreferencesAreConfigured(processPreferencesForApplication(preferences, applicationID));
	UIView *imageView = nil;
	if (show && [view respondsToSelector:@selector(iconImageView)]) imageView = [view iconImageView];
	if (show && !imageView && [view respondsToSelector:@selector(_iconImageView)]) imageView = [view _iconImageView];
	if (!show || ![imageView isKindOfClass:[UIView class]] || ![imageView isDescendantOfView:view]) {
		[tag removeFromSuperview];
		return;
	}
	CGRect imageBounds = [view convertRect:imageView.bounds fromView:imageView];
	if (CGRectIsEmpty(imageBounds) || !isfinite(CGRectGetMaxX(imageBounds)) || !isfinite(CGRectGetMaxY(imageBounds))) {
		[tag removeFromSuperview];
		return;
	}
	CGFloat diameter = MIN(6.0, MIN(imageBounds.size.width, imageBounds.size.height) * 0.1);
	CGFloat inset = diameter / 3.0;
	if (!tag) {
		tag = [[UIView alloc] initWithFrame:CGRectZero];
		tag.backgroundColor = [UIColor colorWithWhite:0.55 alpha:1.0];
		tag.userInteractionEnabled = NO;
		tag.isAccessibilityElement = NO;
		tag.accessibilityElementsHidden = YES;
		objc_setAssociatedObject(view, &choicyIconTagKey, tag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	tag.frame = CGRectMake(CGRectGetMaxX(imageBounds) - diameter - inset, CGRectGetMaxY(imageBounds) - diameter - inset, diameter, diameter);
	tag.layer.cornerRadius = diameter / 2.0;
	if (tag.superview != view) [view addSubview:tag];
}

void choicy_refreshIconTags(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		for (SBIconView *view in choicyVisibleIconViews) {
			choicyUpdateIconTag(view);
			[view setNeedsLayout];
		}
	});
}

static void choicyOpenSettingsURL(NSURL *url, void (^completion)(BOOL))
{
	SpringBoard *application = (SpringBoard *)[UIApplication sharedApplication];
	SBUserAgent *userAgent = [application respondsToSelector:@selector(pluginUserAgent)] ? [application pluginUserAgent] : nil;
	if ([userAgent respondsToSelector:@selector(openURL:allowUnlock:animated:)]) {
		completion([userAgent openURL:url allowUnlock:NO animated:NO]);
		return;
	}
	if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
		[application openURL:url options:@{} completionHandler:completion];
		return;
	}
	NSLog(@"Choicy could not find a Settings URL opener");
	completion(NO);
}

static dispatch_block_t choicyPrepareApplicationSettingsActivation(SBSApplicationShortcutItem *item)
{
	NSString *applicationID = [item.userInfo isKindOfClass:[NSDictionary class]] ? item.userInfo[@"applicationIdentifier"] : nil;
	if (![applicationID isKindOfClass:[NSString class]] || !applicationID.length) return nil;

	NSString *route = [@"prefs:root=" stringByAppendingString:kChoicyPreferencesRootID];
	NSURL *url = [NSURL URLWithString:route];
	if (![route isEqualToString:url.absoluteString]) {
		NSLog(@"Choicy could not construct its Settings URL");
		return nil;
	}

	// Stage during the tap so a new selection supersedes any pending dismissal or launch.
	NSString *requestID = choicyStageApplicationSettingsRequest(applicationID);
	if (!requestID) {
		NSLog(@"Choicy could not stage its Settings request");
		return nil;
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kChoicyOpenRequestLifetime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (choicyCancelApplicationSettingsRequest(requestID)) {
			NSLog(@"Choicy Settings request expired before navigation");
		}
	});

	return ^{
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *currentRequestID = choicyPendingApplicationSettingsRequest(NO)[@"requestID"];
			if (![requestID isEqualToString:currentRequestID]) return;
			choicyOpenSettingsURL(url, ^(BOOL accepted) {
				if (!accepted) {
					choicyCancelApplicationSettingsRequest(requestID);
					NSLog(@"Choicy could not open %@", url);
					return;
				}
				if (!choicyMarkApplicationSettingsRequestReady(requestID)) {
					if (choicyCancelApplicationSettingsRequest(requestID)) {
						NSLog(@"Choicy could not mark its Settings request ready");
					}
					return;
				}
				CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kChoicyOpenRequestNotification, NULL, NULL, YES);
			});
		});
	};
}

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

static NSArray *choicyShortcutItems(NSArray *original, NSString *applicationID, BOOL modern)
{
	NSMutableArray *items = [NSMutableArray new];
	for (SBSApplicationShortcutItem *item in original) {
		if (![item.type isEqualToString:kChoicyLaunchShortcutType] && ![item.type isEqualToString:kChoicyOpenShortcutType]) [items addObject:item];
	}
	if (!applicationID.length) return items;
	if (parseNumberBool(preferences[kChoicyPrefsKeyOpenInChoicyOptionEnabled], NO)) {
		SBSApplicationShortcutItem *open = [[NSClassFromString(@"SBSApplicationShortcutItem") alloc] init];
		open.type = kChoicyOpenShortcutType;
		open.localizedTitle = localize(@"OPEN_IN_CHOICY");
		open.userInfo = @{@"applicationIdentifier": applicationID};
		open.bundleIdentifierToLaunch = kPreferencesBundleID;
		[items addObject:open];
	}
	BOOL disabled = choicy_shouldDisableTweakInjectionForApplication(applicationID);
	if (choicy_shouldShow3DTouchOptionForDisableTweakInjectionState(disabled)) {
		SBSApplicationShortcutItem *launch = [[NSClassFromString(@"SBSApplicationShortcutItem") alloc] init];
		launch.type = kChoicyLaunchShortcutType;
		launch.localizedTitle = localize(disabled ? @"LAUNCH_WITH_TWEAKS" : @"LAUNCH_WITHOUT_TWEAKS");
		launch.bundleIdentifierToLaunch = applicationID;
		if (modern) {
			UIImage *image = [[UIImage imageNamed:(disabled ? @"AppLaunchIcon" : @"AppLaunchIcon_Crossed") inBundle:CHBundle compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
			launch.icon = [[NSClassFromString(@"SBSApplicationShortcutCustomImageIcon") alloc] initWithImageData:UIImagePNGRepresentation(image) dataType:0 isTemplate:YES];
		}
		[items addObject:launch];
	}
	return items;
}

%group IconTags

%hook SBIconView

- (void)setIcon:(SBIcon *)icon
{
	[objc_getAssociatedObject(self, &choicyIconTagKey) removeFromSuperview];
	%orig;
	choicyUpdateIconTag(self);
}

- (void)layoutSubviews
{
	%orig;
	choicyUpdateIconTag(self);
}

- (void)didMoveToWindow
{
	%orig;
	if (self.window) [choicyVisibleIconViews addObject:self];
	else [choicyVisibleIconViews removeObject:self];
	choicyUpdateIconTag(self);
}

%end

%end

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
	NSArray *original = %orig;
	return choicyShortcutItems(original, choicyApplicationIDForIconView(self), YES);
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(SBIconView *)iconView
{
	if ([item.type isEqualToString:kChoicyOpenShortcutType]) {
		dispatch_block_t activate = choicyPrepareApplicationSettingsActivation(item);
		if (!activate) return;
		// Leave the action callback before checking the system's dismissal state.
		dispatch_async(dispatch_get_main_queue(), ^{
			if ([iconView respondsToSelector:@selector(performAfterContextMenusDismissUsingBlock:)]
				&& [iconView respondsToSelector:@selector(isContextMenuInteractionActive)] && [iconView isContextMenuInteractionActive]) {
				[iconView performAfterContextMenusDismissUsingBlock:activate];
			}
			else {
				activate();
			}
		});
		return;
	}
	if ([item.type isEqualToString:kChoicyLaunchShortcutType]) {
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
	NSArray *original = %orig;
	NSString *applicationID = [self respondsToSelector:@selector(applicationBundleIdentifier)] ? [self applicationBundleIdentifier] : nil;
	return choicyShortcutItems(original, applicationID, NO);
}

%end

%hook SBUIAppIconForceTouchController

- (void)appIconForceTouchShortcutViewController:(id)arg1 activateApplicationShortcutItem:(SBSApplicationShortcutItem *)item
{
	if ([item.type isEqualToString:kChoicyOpenShortcutType]) {
		dispatch_block_t activate = choicyPrepareApplicationSettingsActivation(item);
		if ([self respondsToSelector:@selector(dismissAnimated:withCompletionHandler:)]) {
			[self dismissAnimated:NO withCompletionHandler:activate];
		}
		else if ([arg1 isKindOfClass:[UIViewController class]]) {
			[(UIViewController *)arg1 dismissViewControllerAnimated:NO completion:activate];
		}
		else if (activate) {
			activate();
		}
		return;
	}
	if ([item.type isEqualToString:kChoicyLaunchShortcutType]) {
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
	choicyVisibleIconViews = [NSHashTable weakObjectsHashTable];
	%init(IconTags);

	CHBundle = [NSBundle bundleWithPath:JBROOT_PATH_NSSTRING(@"/Library/Application Support/Choicy.bundle")];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, respring, CFSTR("com.opa334.choicy/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_13_0) {
		%init(Shortcut_iOS13Up);
	}
	else {
		%init(Shortcut_iOS12Down);
	}
}
