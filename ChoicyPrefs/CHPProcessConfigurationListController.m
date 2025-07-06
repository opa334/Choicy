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

#import "CHPProcessConfigurationListController.h"

#import <Preferences/PSSpecifier.h>
#import "../Shared.h"
#import "CHPTweakList.h"
#import "CHPTweakInfo.h"
#import "CHPMachoParser.h"
#import "CHPRootListController.h"
#import "CHPPackageInfo.h"
#import "CoreServices.h"
#import "CHPPreferences.h"
#import "CHPPackageInfo.h"
#import "CHPApplicationPlugInsListController.h"
#import <MobileCoreServices/LSBundleProxy.h>
#import <MobileCoreServices/LSPlugInKitProxy.h>
#import "../ChoicyPrefsMigrator.h"

@interface PSSpecifier ()
@property (nonatomic,retain) NSArray *values;
@end

@implementation CHPProcessConfigurationListController

+ (NSString *)executablePathForBundleProxy:(LSBundleProxy *)bundleProxy
{
	NSString *bundleExecutablePath = nil;
	if ([bundleProxy respondsToSelector:@selector(canonicalExecutablePath)]) {
		bundleExecutablePath = bundleProxy.canonicalExecutablePath;
	}

	if (!bundleExecutablePath) {
		NSString *bundleExecutable = bundleProxy.bundleExecutable;
		if (bundleExecutable) {
			bundleExecutablePath = [bundleProxy.bundleURL URLByAppendingPathComponent:bundleExecutable].path;
		}
	}

	if (!bundleExecutablePath && [bundleProxy isKindOfClass:[LSPlugInKitProxy class]]) {
		if (NSClassFromString(@"LSApplicationExtensionRecord")) {
			LSApplicationExtensionRecord *appexRecord = [bundleProxy valueForKey:@"_appexRecord"];
			bundleExecutablePath = appexRecord.executableURL.path;
		}
		else {
			NSString *bundleExecutable = ((LSPlugInKitProxy *)bundleProxy).infoPlist[@"CFBundleExecutable"];
			if (bundleExecutable) {
				bundleExecutablePath = [bundleProxy.bundleURL URLByAppendingPathComponent:bundleExecutable].path;
			}
		}
	}

	return bundleExecutablePath;
}

- (NSString *)executableName
{
	return [self executablePath].lastPathComponent;
}

- (NSString *)executablePath
{
	NSString *executablePath = [[self specifier] propertyForKey:@"executablePath"];
	if (executablePath) return executablePath;

	if (_bundleProxy) {
		return [[self class] executablePathForBundleProxy:_bundleProxy];
	}

	return nil;
}

- (BOOL)shouldShowAppPlugIns
{
	return YES;
}

- (NSString *)applicationIdentifier
{
	return _appIdentifier;
}

- (NSString *)keyForPreferences
{
	if (_appIdentifier) return _appIdentifier;
	if (_pluginIdentifier) return _pluginIdentifier;
	return [self executableName];
}

- (void)respring
{
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicy/respring"), NULL, NULL, YES);
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	if ([_appIdentifier isEqualToString:kSpringboardBundleID]) {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:localize(@"RESPRING") style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
	}

	[self updateSwitchesAvailability];
}

- (void)viewWillDisappear:(BOOL)animated
{
	// reload preview string in previous page
	PSListController *topVC = (PSListController *)self.navigationController.topViewController;
	if ([topVC respondsToSelector:@selector(reloadSpecifier:)]) {
		[topVC reloadSpecifier:[self specifier]];
	}
}

- (NSString *)topTitle
{
	return [self specifier].name;
}

- (NSString *)dictionaryName
{
	if (_appIdentifier || _pluginIdentifier) {
		return kChoicyPrefsKeyAppSettings;
	}
	else {
		return kChoicyPrefsKeyDaemonSettings;
	}
}

- (NSString *)plistName
{
	return @"ApplicationDaemon";
}

- (BOOL)shouldShowTweak:(CHPTweakInfo *)tweakInfo
{
	CHPTweakList *sharedTweakList = [CHPTweakList sharedInstance];

	if ([kAlwaysInjectGlobal containsObject:tweakInfo.dylibName]) {
		return NO;
	}

	if (_appIdentifier) {
		if ([sharedTweakList isTweak:tweakInfo hiddenForApplicationWithIdentifier:_appIdentifier]) {
			return NO;
		}
	}

	return YES;
}

- (void)loadCustomConfigurationSpecifiersIfNeeded
{
	if (!_customConfigurationSpecifiers) {
		CHPTweakList *sharedTweakList = [CHPTweakList sharedInstance];
		NSArray *tweakList;

		// Load tweak list
		NSString *executablePath = [self executablePath];
		tweakList = [sharedTweakList tweakListForExecutableAtPath:executablePath];

		_customConfigurationSpecifiers = [NSMutableArray new];

		_segmentSpecifier = [PSSpecifier preferenceSpecifierNamed:nil
						  target:self
						  set:@selector(setPreferenceValue:specifier:)
						  get:@selector(readPreferenceValue:)
						  detail:nil
						  cell:PSSegmentCell
						  edit:nil];

		[_segmentSpecifier setProperty:@YES forKey:@"enabled"];
		_segmentSpecifier.values = @[@1,@2];
		_segmentSpecifier.titleDictionary = @{@1 : localize(@"ALLOW"), @2 : localize(@"DENY")};
		[_segmentSpecifier setProperty:@1 forKey:@"default"];
		[_segmentSpecifier setProperty:kChoicyProcessPrefsKeyAllowDenyMode forKey:@"key"];

		[_customConfigurationSpecifiers addObject:_segmentSpecifier];

		PSSpecifier *groupSpecifier = [PSSpecifier preferenceSpecifierNamed:nil
						  target:self
						  set:nil
						  get:nil
						  detail:nil
						  cell:PSGroupCell
						  edit:nil];

		[groupSpecifier setProperty:@YES forKey:@"enabled"];

		[_customConfigurationSpecifiers addObject:groupSpecifier];

		__block BOOL atLeastOneTweakDisabled = NO;

		[tweakList enumerateObjectsUsingBlock:^(CHPTweakInfo *tweakInfo, NSUInteger idx, BOOL *stop) {
			BOOL show = [self shouldShowTweak:tweakInfo];
			if (!show) return;

			BOOL enabled = ![dylibsBeforeChoicy containsObject:tweakInfo.dylibName];
			if (!enabled) {
				atLeastOneTweakDisabled = YES;
			}

			PSSpecifier *tweakSpecifier = [PSSpecifier preferenceSpecifierNamed:tweakInfo.dylibName
						  target:self
						  set:@selector(setPreferenceValue:forTweakWithSpecifier:)
						  get:@selector(readValueForTweakWithSpecifier:)
						  detail:nil
						  cell:PSSwitchCell
						  edit:nil];
			
			[tweakSpecifier setProperty:NSClassFromString(@"CHPSubtitleSwitch") forKey:@"cellClass"];
			[tweakSpecifier setProperty:@(enabled) forKey:@"enabled"];
			[tweakSpecifier setProperty:tweakInfo.dylibName forKey:@"key"];
			[tweakSpecifier setProperty:@NO forKey:@"default"];

			CHPPackageInfo *packageInfo = [CHPPackageInfo fetchPackageInfoForDylibName:tweakInfo.dylibName];
			if (packageInfo) {
				[tweakSpecifier setProperty:[NSString stringWithFormat:@"%@: %@", localize(@"PACKAGE"), packageInfo.name] forKey:@"subtitle"];
			}

			[_customConfigurationSpecifiers addObject:tweakSpecifier];
		}];

		if (atLeastOneTweakDisabled) {
			PSSpecifier *greyedOutInfoSpecifier = [PSSpecifier preferenceSpecifierNamed:localize(@"GREYED_OUT_ENTRIES")
						  target:self
						  set:nil
						  get:nil
						  detail:nil
						  cell:PSButtonCell
						  edit:nil];
			
			[greyedOutInfoSpecifier setProperty:@YES forKey:@"enabled"];
			greyedOutInfoSpecifier.buttonAction = @selector(presentNotLoadingFirstWarning);
			[_customConfigurationSpecifiers addObject:greyedOutInfoSpecifier];
		}
	}
}

- (void)presentNotLoadingFirstWarning
{
	presentNotLoadingFirstWarning(self, NO);
}

- (NSMutableArray *)specifiers
{
	if (!_specifiers) {
		_appIdentifier = [[self specifier] propertyForKey:@"applicationIdentifier"];
		_pluginIdentifier = [[self specifier] propertyForKey:@"pluginIdentifier"];
		if (_appIdentifier) {
			_bundleProxy = (LSBundleProxy *)[LSApplicationProxy applicationProxyForIdentifier:_appIdentifier]; 
		}
		else if (_pluginIdentifier) {
			_bundleProxy = (LSBundleProxy *)[LSPlugInKitProxy pluginKitProxyForIdentifier:_pluginIdentifier];
		}

		[self readPreferences];

		_allowedTweaks = [[_processPreferences objectForKey:kChoicyProcessPrefsKeyAllowedTweaks] mutableCopy] ?: [NSMutableArray new];
		_deniedTweaks = [[_processPreferences objectForKey:kChoicyProcessPrefsKeyDeniedTweaks] mutableCopy] ?: [NSMutableArray new];

		_specifiers = [super specifiers];

		NSArray *globalDeniedTweaks = preferences[kChoicyPrefsKeyGlobalDeniedTweaks];
		if (!globalDeniedTweaks.count) {
			[_specifiers removeObjectAtIndex:0];
			[_specifiers removeObjectAtIndex:0];
		}

		PSSpecifier *customTweakConfigurationSpecifier = [self specifierForID:@"CUSTOM_TWEAK_CONFIGURATION"];
		[self getGroup:&_customTweakConfigurationSection row:nil ofSpecifier:customTweakConfigurationSpecifier];

		if (((NSNumber *)[self readPreferenceValue:customTweakConfigurationSpecifier]).boolValue) {
			[self loadCustomConfigurationSpecifiersIfNeeded];
			[_specifiers addObjectsFromArray:_customConfigurationSpecifiers];
		}

		if (_appIdentifier && [self shouldShowAppPlugIns]) {
			LSApplicationProxy *appProxy = (LSApplicationProxy *)_bundleProxy;

			if (appProxy.VPNPlugins.count > 0 || appProxy.plugInKitPlugins.count > 0) {
				PSSpecifier *plugInsGroupSpecifier = [PSSpecifier emptyGroupSpecifier];
				[_specifiers addObject:plugInsGroupSpecifier];

				PSSpecifier *plugInsSpecifier = [PSSpecifier preferenceSpecifierNamed:localize(@"APP_PLUGINS")
								target:self
								set:nil
								get:@selector(previewStringForSpecifier:)
								detail:[CHPApplicationPlugInsListController class]
								cell:PSLinkListCell
								edit:nil];

				[plugInsSpecifier setProperty:@YES forKey:@"enabled"];
				[plugInsSpecifier setProperty:_appIdentifier forKey:@"applicationIdentifier"];
				[_specifiers addObject:plugInsSpecifier];
			}
		}
	}

	return _specifiers;
}

- (void)reloadSpecifiers
{
	[super reloadSpecifiers];
	[self updateSwitchesAvailability];
}

- (void)updateSwitchesAvailability
{
	PSSpecifier *disableTweakInjectionSpecifier = [self specifierForID:@"DISABLE_TWEAK_INJECTION"];
	PSSpecifier *customTweakConfigurationSpecifier = [self specifierForID:@"CUSTOM_TWEAK_CONFIGURATION"];

	NSNumber *disableTweakInjectionNum = [self readPreferenceValue:disableTweakInjectionSpecifier];
	NSNumber *customTweakConfigurationNum = [self readPreferenceValue:customTweakConfigurationSpecifier];

	//handle the edge case where a user managed to enable both at the same time
	if ([disableTweakInjectionNum boolValue] && [customTweakConfigurationNum boolValue]) {
		[disableTweakInjectionSpecifier setProperty:@(YES) forKey:@"enabled"];
		[customTweakConfigurationSpecifier setProperty:@(YES) forKey:@"enabled"];
	}
	else {
		[disableTweakInjectionSpecifier setProperty:@(!customTweakConfigurationNum.boolValue) forKey:@"enabled"];
		[customTweakConfigurationSpecifier setProperty:@(!disableTweakInjectionNum.boolValue) forKey:@"enabled"];
	}

	if ([_appIdentifier isEqualToString:kPreferencesBundleID]) {
		if (![disableTweakInjectionNum boolValue]) {
			[disableTweakInjectionSpecifier setProperty:@(NO) forKey:@"enabled"];
		}
	}

	[self reloadSpecifier:disableTweakInjectionSpecifier];
	[self reloadSpecifier:customTweakConfigurationSpecifier];
}

- (void)setPreferenceValue:(id)value forTweakWithSpecifier:(PSSpecifier *)specifier
{
	BOOL bValue = ((NSNumber *)value).boolValue;
	NSString *key = [specifier propertyForKey:@"key"];

	if (((NSNumber *)[self readPreferenceValue:_segmentSpecifier]).intValue == 1) {
		if (bValue) {
			[_allowedTweaks addObject:key];
		}
		else {
			[_allowedTweaks removeObject:key];
		}

		[self writePreferenceValue:[_allowedTweaks copy] key:kChoicyProcessPrefsKeyAllowedTweaks];
	}
	else {
		if (bValue) {
			[_deniedTweaks addObject:key];
		}
		else {
			[_deniedTweaks removeObject:key];
		}

		[self writePreferenceValue:[_deniedTweaks copy] key:kChoicyProcessPrefsKeyDeniedTweaks];
	}
}

- (id)readValueForTweakWithSpecifier:(PSSpecifier *)specifier
{
	BOOL tweakEnabled;
	NSString *key = [specifier propertyForKey:@"key"];
	NSInteger segmentValue = ((NSNumber *)[self readPreferenceValue:_segmentSpecifier]).intValue;

	if ([dylibsBeforeChoicy containsObject:key]) {
		if (segmentValue == 1) {
			return @1;
		}
		else {
			return @0;
		}
	}

	if (segmentValue == 1) {
		tweakEnabled = [_allowedTweaks containsObject:key];
	}
	else {
		tweakEnabled = [_deniedTweaks containsObject:key];
	}

	return [NSNumber numberWithBool:tweakEnabled];
}

- (void)performUpdatesIfNeccessaryForChangedValue:(id)value key:(NSString *)key
{
	if ([key isEqualToString:kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled]) {
		NSNumber *num = value;

		if (num.boolValue) {
			[self loadCustomConfigurationSpecifiersIfNeeded];
			[self insertContiguousSpecifiers:_customConfigurationSpecifiers atEndOfGroup:_customTweakConfigurationSection animated:YES];
		}
		else {
			[self removeContiguousSpecifiers:_customConfigurationSpecifiers animated:YES];
		}
	}

	if ([key isEqualToString:kChoicyProcessPrefsKeyTweakInjectionDisabled] || [key isEqualToString:kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled]) {
		[self updateSwitchesAvailability];
	}

	if ([key isEqualToString:kChoicyProcessPrefsKeyAllowDenyMode]) {
		for (PSSpecifier *specifier in _customConfigurationSpecifiers) {
			[self reloadSpecifier:specifier];
		}
	}
}

- (void)readPreferences
{
	[self readAppDaemonSettingsFromMainPropertyList];
}

- (void)writePreferences
{
	[self writeAppDaemonSettingsToMainPropertyList];
}

- (void)writePreferenceValue:(id)value key:(NSString *)key
{
	_processPreferences[key] = value;
	[self writePreferences];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
	NSString *key = [specifier propertyForKey:@"key"];
	[self writePreferenceValue:value key:key];
	[self performUpdatesIfNeccessaryForChangedValue:value key:key];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier
{
	id obj = [_processPreferences objectForKey:[[specifier properties] objectForKey:@"key"]];
	if (!obj) {
		obj = [specifier propertyForKey:@"default"];
	}
	return obj;
}

- (void)readAppDaemonSettingsFromMainPropertyList
{
	NSDictionary *appDaemonSettingsDict = [preferences objectForKey:[self dictionaryName]];

	_processPreferences = [[appDaemonSettingsDict objectForKey:[self keyForPreferences]] mutableCopy];
	if (!_processPreferences) {
		_processPreferences = [NSMutableDictionary new];
	}
}

- (void)writeAppDaemonSettingsToMainPropertyList
{
	NSMutableDictionary *mutablePrefs = preferencesForWriting();
	NSMutableDictionary *appDaemonSettingsDict = [[mutablePrefs objectForKey:[self dictionaryName]] mutableCopy] ?: [NSMutableDictionary new];
	appDaemonSettingsDict[[self keyForPreferences]] = [_processPreferences copy];
	mutablePrefs[[self dictionaryName]] = [appDaemonSettingsDict copy];
	writePreferences(mutablePrefs);
}

@end
