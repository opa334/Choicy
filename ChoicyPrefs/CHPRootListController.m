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

#import "CHPRootListController.h"
#import "../Shared.h"
#import "CHPDaemonList.h"
#import "CHPTweakList.h"
#import <mach-o/dyld.h>
#import "CHPPreferences.h"
#import "CHPProcessConfigurationListController.h"
#import "CoreServices.h"
#import "../ChoicyPrefsMigrator.h"
#import "../ChoicyRoot.h"

NSArray *dylibsBeforeChoicy;

#import <dirent.h>

NSDictionary *preferences;

void choicy_reloadPreferences()
{
	if (![NSThread isMainThread]) {
		dispatch_async(dispatch_get_main_queue(), ^{ choicy_reloadPreferences(); });
		return;
	}
	NSDictionary *updated = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath] ?: @{};
	BOOL changed = ![preferences isEqualToDictionary:updated];
	preferences = updated;
	if (changed) {
		[[NSNotificationCenter defaultCenter] postNotificationName:kChoicyPreferencesDidReloadNotification object:nil];
	}
}

static void choicyPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	choicy_reloadPreferences();
}

NSMutableDictionary *preferencesForWriting()
{
	if (preferences.count) {
		return preferences.mutableCopy;
	}
	else {
		NSMutableDictionary *mutablePrefs = [NSMutableDictionary new];
		[ChoicyPrefsMigrator updatePreferenceVersion:mutablePrefs];
		return mutablePrefs;
	}
}

void writePreferences(NSMutableDictionary *mutablePrefs)
{
	[mutablePrefs writeToFile:kChoicyPrefsPlistPath atomically:YES];
	choicy_reloadPreferences();
	[CHPListController sendChoicyPrefsPostNotification];
}

NSArray *getInjectionLibraries()
{
	static NSArray *injectionLibraries = nil;

	if (!injectionLibraries) {
		NSMutableArray *injectionLibrariesM = [NSMutableArray new];

		for (uint32_t i = 0; i < _dyld_image_count(); i++) {
			const char *pathC = _dyld_get_image_name(i);
			NSString *path = [NSString stringWithUTF8String:pathC];

			if ([path hasSuffix:@"/usr/lib/substitute-inserter.dylib"]) {
				[injectionLibrariesM addObject:path];
			}
			else if ([path hasSuffix:@"/usr/lib/substitute-loader.dylib"]) {
				[injectionLibrariesM addObject:path];
			}
			else if ([path hasSuffix:@"/usr/lib/TweakInject.dylib"]) {
				[injectionLibrariesM addObject:path];
			}
			else if ([path hasSuffix:@"/usr/lib/substrate/SubstrateInserter.dylib"]) {
				[injectionLibrariesM addObject:path];
			} else if ([path hasSuffix:@"/usr/lib/substrate/SubstrateLoader.dylib"]) {
				[injectionLibrariesM addObject:path];
			}
		}

		injectionLibraries = injectionLibrariesM.copy;
	}

	return injectionLibraries;
}

NSString *getInjectionPlatform()
{
	static NSString *injectionPlatform = nil;

	if (!injectionPlatform) {
		for (uint32_t i = 0; i < _dyld_image_count(); i++) {
			const char *pathC = _dyld_get_image_name(i);
			NSString *path = [NSString stringWithUTF8String:pathC];

			if ([path hasSuffix:@"/usr/lib/substitute-inserter.dylib"]) {
				injectionPlatform = @"Substitute";
			}
			else if ([path hasSuffix:@"/usr/lib/TweakInject.dylib"]) {
				injectionPlatform = @"libhooker";
			}
			else if ([path hasSuffix:@"/usr/lib/substrate/SubstrateInserter.dylib"]) {
				injectionPlatform = @"Substrate";
			}
		}

		if (!injectionPlatform) {
			injectionPlatform = localize(@"THE_INJECTION_PLATFORM");
		}
	}

	return injectionPlatform;
}

@interface PSListController (ChoicyNavigation)
- (id)controllerForSpecifier:(PSSpecifier *)specifier;
@end

@interface CHPRootListController ()
@property (nonatomic) BOOL choicyOpenScheduled;
- (void)choicy_schedulePendingApplicationSettings;
- (void)choicy_openPendingApplicationSettings;
@end

static void choicyOpenRequestReceived(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	CHPRootListController *controller = (__bridge CHPRootListController *)observer;
	dispatch_async(dispatch_get_main_queue(), ^{ [controller choicy_schedulePendingApplicationSettings]; });
}

@implementation CHPRootListController

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, kChoicyOpenRequestNotification, NULL);
}

- (void)choicy_applicationDidBecomeActive:(NSNotification *)notification
{
	[self choicy_schedulePendingApplicationSettings];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self choicy_schedulePendingApplicationSettings];
}

- (void)choicy_schedulePendingApplicationSettings
{
	if (self.choicyOpenScheduled) return;
	self.choicyOpenScheduled = YES;
	// Allow Settings' own URL traversal and any navigation transition to finish.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self.choicyOpenScheduled = NO;
		[self choicy_openPendingApplicationSettings];
	});
}

- (void)choicy_openPendingApplicationSettings
{
	UINavigationController *navigation = self.navigationController;
	if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive
		|| ![navigation.viewControllers containsObject:self] || !navigation.view.window) return;
	NSDictionary *request = choicyPendingApplicationSettingsRequest();
	if (!request) return;
	if (navigation.transitionCoordinator) {
		__weak typeof(self) weakSelf = self;
		[navigation.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
			[weakSelf choicy_schedulePendingApplicationSettings];
		}];
		return;
	}
	for (UIViewController *controller in navigation.viewControllers) {
		if (@available(iOS 11.0, *)) controller.navigationItem.searchController.active = NO;
		if ([controller.presentedViewController isKindOfClass:[UISearchController class]]) {
			((UISearchController *)controller.presentedViewController).active = NO;
		}
	}
	if (navigation.presentedViewController) {
		[navigation dismissViewControllerAnimated:NO completion:^{ [self choicy_schedulePendingApplicationSettings]; }];
		return;
	}
	NSString *applicationID = request[@"applicationIdentifier"];
	LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:applicationID];
	BOOL installed = proxy.bundleURL.isFileURL && [[NSFileManager defaultManager] fileExistsAtPath:proxy.bundleURL.path];
	if (!installed) {
		choicyConsumeApplicationSettingsRequest(request[@"requestID"]);
		return;
	}
	UIViewController *top = navigation.topViewController;
	PSListController *detail = nil;
	if ([top isKindOfClass:[CHPProcessConfigurationListController class]]
		&& [applicationID isEqualToString:[[(PSListController *)top specifier] propertyForKey:@"applicationIdentifier"]]) {
		detail = (PSListController *)top;
	}
	else {
		PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:(proxy.localizedName ?: applicationID)
			target:self set:nil get:@selector(previewStringForSpecifier:)
			detail:[CHPProcessConfigurationListController class] cell:PSLinkListCell edit:nil];
		specifier.identifier = applicationID;
		[specifier setProperty:applicationID forKey:@"applicationIdentifier"];
		[specifier setProperty:@YES forKey:@"enabled"];
		detail = [self controllerForSpecifier:specifier];
	}
	if (!detail) return;
	if (!choicyConsumeApplicationSettingsRequest(request[@"requestID"])) {
		[self choicy_schedulePendingApplicationSettings];
		return;
	}
	// Normalize the stack even for an already-open app, so URL traversal and
	// repeated shortcuts cannot leave duplicate app controllers behind.
	NSUInteger rootIndex = [navigation.viewControllers indexOfObject:self];
	NSMutableArray *controllers = [[navigation.viewControllers subarrayWithRange:NSMakeRange(0, rootIndex + 1)] mutableCopy];
	[controllers addObject:detail];
	[navigation setViewControllers:controllers animated:NO];
}

- (NSString *)title
{
	return @"Choicy";
}

- (NSString *)plistName
{
	return @"Root";
}

- (void)openTwitterWithUsername:(NSString *)username
{
	UIApplication *app = [UIApplication sharedApplication];

	if ([app canOpenURL:[NSURL URLWithString:@"twitter://"]]) {
		[app openURL:[NSURL URLWithString:[NSString stringWithFormat:@"twitter://user?screen_name=%@", username]]];
	}
	else {
		[app openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://twitter.com/%@", username]]];
	}
}

- (void)openMastodonWithUsername:(NSString *)username instance:(NSString *)instance
{
	UIApplication *app = [UIApplication sharedApplication];

	NSArray *candidateURLs = @[
		[NSURL URLWithString:[NSString stringWithFormat:@"opener://x-callback-url/show-options?url=https%%3A%%2F%%2F%@%%2F%@", instance, username]],
		[NSURL URLWithString:[NSString stringWithFormat:@"ivory://%@/@%@", instance, username]],
		[NSURL URLWithString:[NSString stringWithFormat:@"icecubesapp://%@/@%@", instance, username]],
		[NSURL URLWithString:[NSString stringWithFormat:@"mastodon://profile/%@@%@", username, instance]],
		[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/@%@", instance, username]],
	];

	for (NSURL *candidateURL in candidateURLs) {
		if ([app canOpenURL:candidateURL]) {
			[app openURL:candidateURL];
			break;
		}
	}
}

- (void)sourceLink
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/opa334/Choicy"]];
}

- (void)openMastodon
{
	[self openMastodonWithUsername:@"opa334" instance:@"infosec.exchange"];
}

- (void)donationLink
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=opa334@protonmail.com&item_name=iOS%20Tweak%20Development"]];
}

- (void)resetPreferences
{
	UIAlertController *resetPreferencesAlert = [UIAlertController alertControllerWithTitle:localize(@"RESET_PREFERENCES") message:localize(@"RESET_PREFERENCES_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction *continueAction = [UIAlertAction actionWithTitle:localize(@"CONTINUE") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
		[[NSFileManager defaultManager] removeItemAtPath:kChoicyPrefsPlistPath error:nil];
		[[self class] sendChoicyPrefsPostNotification];
	}];

	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:localize(@"CANCEL") style:UIAlertActionStyleDefault handler:nil];
	
	[resetPreferencesAlert addAction:continueAction];
	[resetPreferencesAlert addAction:cancelAction];

	[self presentViewController:resetPreferencesAlert animated:YES completion:nil];
}

void presentNotLoadingFirstWarning(PSListController *plc, BOOL showDontShowAgainOption)
{
	PSSpecifier *dontShowAgainSpecifier = [PSSpecifier preferenceSpecifierNamed:@"dontShowWarningAgain"
					target:plc
					set:nil
					get:nil
					detail:nil
					cell:0
					edit:nil];

	[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs" forKey:@"defaults"];
	[dontShowAgainSpecifier setProperty:@"dontShowWarningAgain" forKey:@"key"];
	[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs/ReloadPrefs" forKey:@"PostNotification"];

	NSNumber *dontShowAgainNum = nil;
	if (showDontShowAgainOption) {
		dontShowAgainNum = [plc readPreferenceValue:dontShowAgainSpecifier];
	}

	if (![dontShowAgainNum boolValue]) {
		NSString *injectionPlatform = getInjectionPlatform();

		NSString *message = [NSString stringWithFormat:localize(@"TWEAKS_LOADING_BEFORE_CHOICY_ALERT_MESSAGE"), injectionPlatform];

		if ([injectionPlatform isEqualToString:@"Substrate"]) {
			message = [message stringByAppendingString:[@" " stringByAppendingString:localize(@"CHOICYLOADER_ADVICE")]];
		}

		UIAlertController *warningAlert = [UIAlertController alertControllerWithTitle:localize(@"WARNING_ALERT_TITLE") message:message preferredStyle:UIAlertControllerStyleAlert];
	
		if ([injectionPlatform isEqualToString:@"Substrate"]) {
			UIAlertAction *openRepoAction = [UIAlertAction actionWithTitle:localize(@"OPEN_REPO") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://opa334.github.io"]];
			}];

			[warningAlert addAction:openRepoAction];
		}

		if (showDontShowAgainOption) {
			UIAlertAction *dontShowAgainAction = [UIAlertAction actionWithTitle:localize(@"DONT_SHOW_AGAIN") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
				[plc setPreferenceValue:@1 specifier:dontShowAgainSpecifier];
			}];

			[warningAlert addAction:dontShowAgainAction];
		}

		UIAlertAction *closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];

		[warningAlert addAction:closeAction];

		if ([warningAlert respondsToSelector:@selector(setPreferredAction:)]) {
			warningAlert.preferredAction = closeAction;
		}

		[plc presentViewController:warningAlert animated:YES completion:nil];
	}
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(choicy_applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, choicyOpenRequestReceived, kChoicyOpenRequestNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (dylibsBeforeChoicy && !choicyPendingApplicationSettingsRequest()) {
		presentNotLoadingFirstWarning(self, YES);
	}
}

@end

void determineLoadingOrder()
{
	NSMutableArray *dylibsInOrder = [NSMutableArray new];
	NSString *injectionLibrariesPath = [CHPTweakList injectionLibrariesPath];

	BOOL isSubstrate = [getInjectionPlatform() isEqualToString:@"Substrate"];
	if (isSubstrate) {
		//SubstrateLoader doesn't sort anything and instead process the raw output of readdir
		DIR *dir;
		struct dirent *dp;
		dir = opendir(injectionLibrariesPath.UTF8String);
		dp=readdir(dir); //.
		dp=readdir(dir); //..
		while ((dp = readdir(dir)) != NULL) {
			NSString *filename = [NSString stringWithCString:dp->d_name encoding:NSUTF8StringEncoding];

			if ([filename.pathExtension isEqualToString:@"dylib"]) {
				[dylibsInOrder addObject:[filename stringByDeletingPathExtension]];
			}
		}
	}
	else {
		//Anything but substrate sorts the dylibs alphabetically
		NSMutableArray *contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:injectionLibrariesPath error:nil] mutableCopy];
		NSArray *plists = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", @"plist"]];
		for (NSString *plist in plists) {
			NSString *dylibName = [plist stringByDeletingPathExtension];
			[dylibsInOrder addObject:dylibName];
		}
		[dylibsInOrder sortUsingSelector:@selector(caseInsensitiveCompare:)];
	}

	NSUInteger choicyIndex = [dylibsInOrder indexOfObject:kChoicyDylibName];

	if (choicyIndex == NSNotFound) return;

	if (choicyIndex != 0) {
		dylibsBeforeChoicy = [dylibsInOrder subarrayWithRange:NSMakeRange(0,choicyIndex)];
	}

	if (dylibsBeforeChoicy && isSubstrate) {
		NSDictionary *targetLoaderAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:JBROOT_PATH_NSSTRING(@"/usr/lib/substrate/SubstrateLoader.dylib") error:nil];

		if ([[targetLoaderAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			NSString *destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:JBROOT_PATH_NSSTRING(@"/usr/lib/substrate/SubstrateLoader.dylib") error:nil];
			if ([destination hasPrefix:@"/usr/lib/ChoicyLoader.dylib"]) {
				// If ChoicyLoader is installed on Substrate, Choicy always loads first
				dylibsBeforeChoicy = nil;
			}
		}
	}
}

__attribute__((constructor))
static void init(void)
{
	choicy_reloadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, choicyPreferencesChanged, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	determineLoadingOrder();
}
