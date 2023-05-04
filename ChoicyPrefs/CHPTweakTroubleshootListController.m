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

#import "CHPTweakTroubleshootListController.h"
#import "CHPPackageInfo.h"
#import "../Shared.h"
#import <Preferences/PSSpecifier.h>
#import "CHPBlackTextTableCell.h"
#import "CHPPreferences.h"
#import "CHPDaemonList.h"
#import "CHPProcessConfigurationListController.h"
#import <MobileCoreServices/LSApplicationProxy.h>
#import "CHPTweakInfo.h"
#import "CHPTweakList.h"

@implementation CHPTweakTroubleshootListController

- (void)viewDidLoad
{
	[[CHPDaemonList sharedInstance] addObserver:self];
	if (![CHPDaemonList sharedInstance].loaded) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
			[[CHPDaemonList sharedInstance] updateDaemonListIfNeeded];
		});
	}

	[super viewDidLoad];
}

- (PSSpecifier *)newSpecifierForPackage:(CHPPackageInfo *)packageInfo
{
	PSSpecifier *packageSpecifier = [PSSpecifier preferenceSpecifierNamed:packageInfo.name
		target:self
		set:nil
		get:nil
		detail:nil
		cell:PSButtonCell
		edit:nil];

	[packageSpecifier setProperty:@1 forKey:@"enabled"];
	[packageSpecifier setProperty:packageInfo forKey:@"packageInfo"];
	[packageSpecifier setProperty:[CHPBlackTextTableCell class] forKey:@"cellClass"];
	packageSpecifier.buttonAction = @selector(packageSpecifierPressed:);
	
	return packageSpecifier;
}

- (void)daemonListDidUpdate:(CHPDaemonList *)list
{
	if (_selectedPackageWhileWaitingOnLoad) {
		[self handleTroubleshootingForPackage:_selectedPackageWhileWaitingOnLoad];
		_selectedPackageWhileWaitingOnLoad = nil;
	}
}

- (BOOL)isTweakDylib:(NSString *)tweakDylib deniedFromInjectingIntoExecutable:(NSString *)executablePath withProcessPreferences:(NSDictionary *)processPrefs
{
	BOOL tweakInjectionDisabled = parseNumberBool(processPrefs[kChoicyProcessPrefsKeyTweakInjectionDisabled], NO);
	BOOL customTweakConfigurationEnabled = parseNumberBool(processPrefs[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled], NO);
	NSInteger allowDenyMode = parseNumberInteger(processPrefs[kChoicyProcessPrefsKeyAllowDenyMode], 1);

	if (!tweakInjectionDisabled && !customTweakConfigurationEnabled) return NO;

	if (customTweakConfigurationEnabled) {
		if (allowDenyMode == 2) { // DENY
			NSArray *deniedDylibs = processPrefs[kChoicyProcessPrefsKeyDeniedTweaks];
			if ([deniedDylibs containsObject:tweakDylib]) {
				return YES;
			}
		}
	}

	NSArray *executableTweaks = [[CHPTweakList sharedInstance] tweakListForExecutableAtPath:executablePath];
	
	__block BOOL tweakInjectsIntoExecutable = NO;
	[executableTweaks enumerateObjectsUsingBlock:^(CHPTweakInfo *tweakInfo, NSUInteger idx, BOOL *stop) {
		if ([tweakInfo.dylibName isEqualToString:tweakDylib]) {
			tweakInjectsIntoExecutable = YES;
			*stop = YES;
		}
	}];

	if (tweakInjectsIntoExecutable) {
		if (tweakInjectionDisabled) {
			return YES;
		}
		else if (customTweakConfigurationEnabled == YES && allowDenyMode == 1) {
			NSArray *allowedTweaks = processPrefs[kChoicyProcessPrefsKeyAllowedTweaks];
			return ![allowedTweaks containsObject:tweakDylib];
		}
	}

	return NO;
}

- (void)showLoadingAlertController
{
	_loadingAlertController = [UIAlertController alertControllerWithTitle:@"" message:@"" preferredStyle:UIAlertControllerStyleAlert];
	UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(110,0,45,45)];
	activityIndicator.hidesWhenStopped = YES;

	if (@available(iOS 13, *)) {
		activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleMedium;
	}
	else {
		activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
	}
	
	[activityIndicator startAnimating];
	[_loadingAlertController.view addSubview:activityIndicator];

	[self.navigationController presentViewController:_loadingAlertController animated:YES completion:nil];
}

- (void)hideLoadingAlertControllerWithCompletion:(void (^)(void))completion
{
	[_loadingAlertController dismissViewControllerAnimated:YES completion:completion];
	_loadingAlertController = nil;
}

- (void)packageSpecifierPressed:(PSSpecifier *)packageSpecifier
{
	[self showLoadingAlertController];

	CHPPackageInfo *packageInfo = [packageSpecifier propertyForKey:@"packageInfo"];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^ {
		[self handleTroubleshootingForPackage:packageInfo];
	});
}

- (void)handleTroubleshootingForPackage:(CHPPackageInfo *)packageInfo
{
	if (![CHPDaemonList sharedInstance].loaded) {
		_selectedPackageWhileWaitingOnLoad = packageInfo;
		return;
	}

	NSArray *globalDeniedTweaks = preferences[kChoicyPrefsKeyGlobalDeniedTweaks];
	NSDictionary *appSettings = preferences[kChoicyPrefsKeyAppSettings];
	NSDictionary *daemonSettings = preferences[kChoicyPrefsKeyDaemonSettings];

	NSMutableArray *globallyDeniedDylibs = [NSMutableArray new];
	NSMutableDictionary *deniedAppsByTweakDylib = [NSMutableDictionary new];
	NSMutableDictionary *deniedDaemonsByTweakDylib = [NSMutableDictionary new];
	
	[packageInfo.tweakDylibs enumerateObjectsUsingBlock:^(NSString *tweakDylib, NSUInteger idx, BOOL *stop) {
		if ([globalDeniedTweaks containsObject:tweakDylib]) {
			[globallyDeniedDylibs addObject:tweakDylib];
		}

		NSMutableArray *deniedAppsList = [NSMutableArray new];
		NSMutableArray *deniedDaemonsList = [NSMutableArray new];

		[appSettings enumerateKeysAndObjectsUsingBlock:^(NSString *applicationID, NSDictionary *processPrefs, BOOL *stop) {
			LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:applicationID];
			if (appProxy.isInstalled) {
				NSString *executablePath = [CHPProcessConfigurationListController executablePathForBundleProxy:appProxy];
				if ([self isTweakDylib:tweakDylib deniedFromInjectingIntoExecutable:executablePath withProcessPreferences:processPrefs]) {
					[deniedAppsList addObject:appProxy];
				}
			}
		}];

		[daemonSettings enumerateKeysAndObjectsUsingBlock:^(NSString *daemonName, NSDictionary *processPrefs, BOOL *stop) {
			NSString *executablePath = [[CHPDaemonList sharedInstance] executablePathForDaemonName:daemonName];
			if ([self isTweakDylib:tweakDylib deniedFromInjectingIntoExecutable:executablePath withProcessPreferences:processPrefs]) {
				[deniedDaemonsList addObject:daemonName];
			}
		}];

		if (deniedAppsList.count) {
			deniedAppsByTweakDylib[tweakDylib] = deniedAppsList;
		}
		if (deniedDaemonsList.count) {
			deniedDaemonsByTweakDylib[tweakDylib] = deniedDaemonsList;
		}
	}];

	dispatch_async(dispatch_get_main_queue(), ^ {
		[self hideLoadingAlertControllerWithCompletion:^ {
			dispatch_async(dispatch_get_main_queue(), ^ {
				NSString *title = [NSString stringWithFormat:@"%@ (%@)", localize(@"RESULTS"), packageInfo.name];
				if (globallyDeniedDylibs.count || deniedAppsByTweakDylib.count || deniedDaemonsByTweakDylib.count) {
					NSMutableString *messageM = [NSMutableString new];
					__block BOOL firstLinePrinted = NO;

					if (globallyDeniedDylibs.count) {
						NSString *globallyDeniedDylibsString = [globallyDeniedDylibs componentsJoinedByString:@"\n"];
						[messageM appendFormat:@"%@\n%@", localize(@"RESULTS_GLOBAL_DENIED"), globallyDeniedDylibsString];
						firstLinePrinted = YES;
					}

					if (deniedAppsByTweakDylib.count) {
						[deniedAppsByTweakDylib enumerateKeysAndObjectsUsingBlock:^(NSString *tweakDylib, NSArray *applicationProxies, BOOL *stop) {
							NSMutableString *applicationNamesString = [NSMutableString new];

							[applicationProxies enumerateObjectsUsingBlock:^(LSApplicationProxy *appProxy, NSUInteger idx, BOOL *stop) {
								[applicationNamesString appendString:appProxy.localizedName];
								if (idx < applicationProxies.count-1) {
									[applicationNamesString appendString:@"\n"];
								}
							}];

							if (firstLinePrinted) {
								[messageM appendString:@"\n\n"];
							}
							[messageM appendFormat:localize(@"RESULTS_APPLICATION"), tweakDylib, applicationNamesString.copy];
							firstLinePrinted = YES;
						}];
					}

					if (deniedDaemonsByTweakDylib.count) {
						[deniedDaemonsByTweakDylib enumerateKeysAndObjectsUsingBlock:^(NSString *tweakDylib, NSArray *daemonNames, BOOL *stop) {
							NSString *daemonNamesString = [daemonNames componentsJoinedByString:@"\n"];
							if (firstLinePrinted) {
								[messageM appendString:@"\n\n"];
							}
							[messageM appendFormat:localize(@"RESULTS_PROCESS"), tweakDylib, daemonNamesString];
							firstLinePrinted = YES;
						}];
					}

					UIAlertController *troubleshootController = [UIAlertController alertControllerWithTitle:title message:messageM.copy preferredStyle:UIAlertControllerStyleAlert];

					UIAlertAction *fixAction = [UIAlertAction actionWithTitle:localize(@"FIX") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
						// globally disabled -> remove tweak from global deny list
						// tweak injection disabled -> disable disable toggle, turn on custom config, set to allow, put tweak dylib on allow list
						// custom configuration enabled on allow -> add tweak to allow list
						// custom configuration enabled on deny -> remove tweak from deny list

						NSMutableString *changelogString = [NSMutableString new];
						__block BOOL changelogFirstLinePrinted = NO;

						NSMutableDictionary *mutablePrefs = preferences.mutableCopy;

						if (globallyDeniedDylibs.count) {
							// globally disabled -> remove tweak from global deny list
							NSArray *prefs_globalDeniedTweaks = mutablePrefs[kChoicyPrefsKeyGlobalDeniedTweaks];
							NSMutableArray *prefs_globalDeniedTweaks_m = prefs_globalDeniedTweaks.mutableCopy;
							[globallyDeniedDylibs enumerateObjectsUsingBlock:^(NSString *globalDeniedDylib, NSUInteger idx, BOOL *stop) {
								[prefs_globalDeniedTweaks_m removeObject:globalDeniedDylib];

								if (changelogFirstLinePrinted) [changelogString appendString:@"\n\n"];
								[changelogString appendFormat:localize(@"TROUBLESHOOT_LOG_ENABLED_IN_GLOBAL"), globalDeniedDylib];
								changelogFirstLinePrinted = YES;
							}];
							
							mutablePrefs[kChoicyPrefsKeyGlobalDeniedTweaks] = prefs_globalDeniedTweaks_m.copy;	
						}

						void (^handleProcessPrefs)(NSString*, NSMutableDictionary*, NSString *) = ^(NSString *displayName, NSMutableDictionary *processPrefs, NSString *dylibName) {
							if (parseNumberBool(processPrefs[kChoicyProcessPrefsKeyTweakInjectionDisabled], NO)) {
								// tweak injection disabled -> disable disable toggle, turn on custom config, set to allow, put tweak dylib on allow list
								processPrefs[kChoicyProcessPrefsKeyTweakInjectionDisabled] = @NO;
								processPrefs[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled] = @YES;
								processPrefs[kChoicyProcessPrefsKeyAllowDenyMode] = @1; //ALLOW
								processPrefs[kChoicyProcessPrefsKeyAllowedTweaks] = @[dylibName];

								if (changelogFirstLinePrinted) [changelogString appendString:@"\n\n"];
								[changelogString appendFormat:localize(@"TROUBLESHOOT_LOG_DISABLED_TO_ALLOW"), displayName, dylibName];
								changelogFirstLinePrinted = YES;
							}
							else {
								if (parseNumberBool(processPrefs[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled], NO)) {
									if (parseNumberInteger(processPrefs[kChoicyProcessPrefsKeyAllowDenyMode], 1) == 1) //ALLOW
									{
										// custom configuration enabled on allow -> add tweak to allow list
										NSArray *procPrefs_allowedTweaks = processPrefs[kChoicyProcessPrefsKeyAllowedTweaks];
										NSMutableArray *procPrefs_allowedTweaks_m = procPrefs_allowedTweaks ? procPrefs_allowedTweaks.mutableCopy : [NSMutableArray new];
										if (![procPrefs_allowedTweaks_m containsObject:dylibName])
										{
											[procPrefs_allowedTweaks_m addObject:dylibName];
											processPrefs[kChoicyProcessPrefsKeyAllowedTweaks] = procPrefs_allowedTweaks_m.copy;

											if (changelogFirstLinePrinted) [changelogString appendString:@"\n\n"];
											[changelogString appendFormat:localize(@"TROUBLESHOOT_LOG_ADDED_TO_ALLOW"), dylibName, displayName];
											changelogFirstLinePrinted = YES;
										}
									}
									else //DENY
									{
										// custom configuration enabled on deny -> remove tweak from deny list
										NSArray *procPrefs_deniedTweaks = processPrefs[kChoicyProcessPrefsKeyDeniedTweaks];
										NSMutableArray *procPrefs_deniedTweaks_m = procPrefs_deniedTweaks.mutableCopy;
										if ([procPrefs_deniedTweaks_m containsObject:dylibName])
										{
											[procPrefs_deniedTweaks_m removeObject:dylibName];
											processPrefs[kChoicyProcessPrefsKeyDeniedTweaks] = procPrefs_deniedTweaks_m.copy;

											if (changelogFirstLinePrinted) [changelogString appendString:@"\n\n"];
											[changelogString appendFormat:localize(@"TROUBLESHOOT_LOG_REMOVED_FROM_DENY"), dylibName, displayName];
											changelogFirstLinePrinted = YES;
										}
									}
								}
							}
						}; 

						// Call handleProcessPrefs on all denied dylibs for all apps
						if (deniedAppsByTweakDylib.count) {
							NSMutableDictionary *appSettings_m = appSettings.mutableCopy;
							[deniedAppsByTweakDylib enumerateKeysAndObjectsUsingBlock:^(NSString *dylibName, NSArray *applicationProxies, BOOL *stop) {
								[applicationProxies enumerateObjectsUsingBlock:^(LSApplicationProxy *appProxy, NSUInteger idx, BOOL *stop) {
									NSString *applicationID = appProxy.bundleIdentifier;
									NSDictionary *appProcessPrefs = appSettings_m[applicationID];
									NSMutableDictionary *appProcessPrefs_m = appProcessPrefs.mutableCopy;
									handleProcessPrefs(appProxy.localizedName, appProcessPrefs_m, dylibName);
									appSettings_m[applicationID] = appProcessPrefs_m.copy;
								}];
							}];
							mutablePrefs[kChoicyPrefsKeyAppSettings] = appSettings_m.copy;
						}

						// Call handleProcessPrefs on all denied dylibs for all daemons
						if (deniedDaemonsByTweakDylib.count) {
							NSMutableDictionary *daemonSettings_m = daemonSettings.mutableCopy;
							[deniedDaemonsByTweakDylib enumerateKeysAndObjectsUsingBlock:^(NSString *dylibName, NSArray *daemonNames, BOOL *stop) {
								[daemonNames enumerateObjectsUsingBlock:^(NSString *daemonName, NSUInteger idx, BOOL *stop) {
									NSDictionary *daemonProcessPrefs = daemonSettings_m[daemonName];
									NSMutableDictionary *daemonProcessPrefs_m = daemonProcessPrefs.mutableCopy;
									handleProcessPrefs(daemonName, daemonProcessPrefs_m, dylibName);
									daemonSettings_m[daemonName] = daemonProcessPrefs_m.copy;
								}];
							}];
							mutablePrefs[kChoicyPrefsKeyDaemonSettings] = daemonSettings_m.copy;
						}

						writePreferences(mutablePrefs);

						UIAlertController *changelogAlert = [UIAlertController alertControllerWithTitle:localize(@"APPLIED_CHANGES") message:changelogString.copy preferredStyle:UIAlertControllerStyleAlert];
						UIAlertAction *closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];
						[changelogAlert addAction:closeAction];

						[self presentViewController:changelogAlert animated:YES completion:nil];
					}];

					UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:localize(@"CANCEL") style:UIAlertActionStyleCancel handler:nil];

					[troubleshootController addAction:fixAction];
					[troubleshootController addAction:cancelAction];

					[self presentViewController:troubleshootController animated:YES completion:nil];
				}
				else {
					UIAlertController *nothingFoundController = [UIAlertController alertControllerWithTitle:title message:localize(@"NOTHING_FOUND_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
					UIAlertAction *closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];
					[nothingFoundController addAction:closeAction];

					[self presentViewController:nothingFoundController animated:YES completion:nil];
				}
			});
		}];
	});
}

- (NSMutableArray *)specifiers
{
	if (!_specifiers) {
		_packageList = [CHPPackageInfo allInstalledPackages];

		_specifiers = [NSMutableArray new];

		PSSpecifier *groupSpecifier = [PSSpecifier emptyGroupSpecifier];
		groupSpecifier.name = localize(@"PACKAGES");
		[_specifiers addObject:groupSpecifier];

		[_packageList enumerateObjectsUsingBlock:^(CHPPackageInfo *packageInfo, NSUInteger idx, BOOL *stop) {
			if ([packageInfo.name isEqualToString:@"Choicy"]) return;
			PSSpecifier *packageSpecifier = [self newSpecifierForPackage:packageInfo];
			[_specifiers addObject:packageSpecifier];
		}];
	}

	return _specifiers;
}



@end