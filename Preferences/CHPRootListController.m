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

#import "CHPRootListController.h"
#import "../Shared.h"
#import "CHPDaemonList.h"
#import "CHPTweakList.h"

int hookingPlatform = 0;

BOOL customTweakConfigurationWorks;

#import <dirent.h>

NSDictionary* preferences;

void reloadPreferences()
{
	preferences = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:@"preferencesDidReload" object:nil]];
}

@implementation CHPRootListController

- (NSString*)title
{
	return @"Choicy";
}

- (NSString*)plistName
{
	return @"Root";
}

- (void)openTwitterWithUsername:(NSString*)username
{
	if([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]])
	{
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"twitter://user?screen_name=%@", username]]];
	}
	else
	{
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://twitter.com/%@", username]]];
	}
}

- (void)sourceLink
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/opa334/Choicy"]];
}

- (void)openTwitter
{
	[self openTwitterWithUsername:@"opa334dev"];
}

- (void)donationLink
{
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=opa334@protonmail.com&item_name=iOS%20Tweak%20Development"]];
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	[self updateGlobalConfigurationAvailability];

	if(!customTweakConfigurationWorks)
	{
		PSSpecifier* dontShowAgainSpecifier = [PSSpecifier preferenceSpecifierNamed:@"dontShowWarningAgain"
						target:self
						set:nil
						get:nil
						detail:nil
						cell:0
						edit:nil];

		[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs" forKey:@"defaults"];
		[dontShowAgainSpecifier setProperty:@"dontShowWarningAgain" forKey:@"key"];
		[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs/ReloadPrefs" forKey:@"PostNotification"];

		NSNumber* dontShowAgainNum = [self readPreferenceValue:dontShowAgainSpecifier];

		if(![dontShowAgainNum boolValue])
		{
			NSString* hookingPlatformName;

			if(hookingPlatform == 1)
			{
				hookingPlatformName = @"Substrate";
			}
			else if(hookingPlatform == 2)
			{
				hookingPlatformName = @"Substitute";
			}

			UIAlertController* warningAlert = [UIAlertController alertControllerWithTitle:localize(@"WARNING_ALERT_TITLE") message:[NSString stringWithFormat:localize(@"WARNING_ALERT_MESSAGE"), hookingPlatformName] preferredStyle:UIAlertControllerStyleAlert];
		
			UIAlertAction* openRepoAction = [UIAlertAction actionWithTitle:localize(@"OPEN_REPO") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
			{
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://opa334.github.io"]];
			}];

			[warningAlert addAction:openRepoAction];

			UIAlertAction* dontShowAgainAction = [UIAlertAction actionWithTitle:localize(@"DONT_SHOW_AGAIN") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
			{
				[self setPreferenceValue:@1 specifier:dontShowAgainSpecifier];
			}];

			[warningAlert addAction:dontShowAgainAction];

			UIAlertAction* closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];

			[warningAlert addAction:closeAction];

			if([warningAlert respondsToSelector:@selector(setPreferredAction:)])
			{
				warningAlert.preferredAction = closeAction;
			}

			[self presentViewController:warningAlert animated:YES completion:nil];
		}
	}
}

- (void)updateGlobalConfigurationAvailability
{
	if(!customTweakConfigurationWorks)
	{
		PSSpecifier* globalTweakConfiguration = [self specifierForID:@"GLOBAL_TWEAK_CONFIGURATION"];
		[globalTweakConfiguration setProperty:@NO forKey:@"enabled"];
		[self reloadSpecifier:globalTweakConfiguration];
	}
}

- (void)reloadSpecifiers
{
	[super reloadSpecifiers];
	[self updateGlobalConfigurationAvailability];
}

@end

extern void initCHPApplicationPreferenceViewController();
extern void initCHPPreferencesTableDataSource();

void checkIfCustomTweakConfigurationWorks()
{
	NSString* targetLoaderPath;

	if([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/substrate/SubstrateInserter.dylib"])
	{
		targetLoaderPath = @"/usr/lib/substrate/SubstrateLoader.dylib";
		hookingPlatform = 1;
	}
	else if([[NSFileManager defaultManager] fileExistsAtPath:@"/usr/lib/substitute-inserter.dylib"])
	{
		targetLoaderPath = @"/usr/lib/substitute-loader.dylib";
		hookingPlatform = 2;
	}
	
	DIR *dir;
    struct dirent* dp;
    dir = opendir("/Library/MobileSubstrate/DynamicLibraries");
	dp=readdir(dir); //.
	dp=readdir(dir); //..

	while((dp = readdir(dir)) != NULL)
	{
		NSString* filename = [NSString stringWithCString:dp->d_name encoding:NSUTF8StringEncoding];

		if([filename isEqualToString:@"000_Choicy.dylib"])
		{
			customTweakConfigurationWorks = YES;
			break;
		}

		if([filename.pathExtension isEqualToString:@"dylib"])
		{
			customTweakConfigurationWorks = NO;
			break;
		}
	}

	if(!customTweakConfigurationWorks)
	{
		NSDictionary* targetLoaderAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:targetLoaderPath error:nil];

		if([[targetLoaderAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		{
			NSString* destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:targetLoaderPath error:nil];
			if([destination isEqualToString:@"/usr/lib/ChoicyLoader.dylib"])
			{
				customTweakConfigurationWorks = YES;
			}
		}
	}
}

__attribute__((constructor))
static void init(void)
{
	[[CHPTweakList sharedInstance] updateTweakList];

	reloadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	NSBundle* applistBundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/AppList.bundle"];
	if(applistBundle)
	{
		[applistBundle load];
		initCHPApplicationPreferenceViewController();
		initCHPPreferencesTableDataSource();
	}

	checkIfCustomTweakConfigurationWorks();
}