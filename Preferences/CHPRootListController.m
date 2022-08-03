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
#import <AppList/AppList.h>
#import <mach-o/dyld.h>
#import "CHPPreferences.h"
#import "../ChoicyPrefsMigrator.h"

NSArray* dylibsBeforeChoicy;

#import <dirent.h>

NSDictionary* preferences;

void reloadPreferences()
{
	preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];
}

NSMutableDictionary* preferencesForWriting()
{
	if(preferences)
	{
		return preferences.mutableCopy;
	}
	else
	{
		NSMutableDictionary* mutablePrefs = [NSMutableDictionary new];
		[ChoicyPrefsMigrator updatePreferenceVersion:mutablePrefs];
		return mutablePrefs;
	}
}

void writePreferences(NSMutableDictionary* mutablePrefs)
{
	[mutablePrefs writeToFile:kChoicyPrefsPlistPath atomically:YES];
	[CHPListController sendChoicyPrefsPostNotification];
}

NSArray* getInjectionLibraries()
{
	static NSArray* injectionLibraries = nil;

	if(!injectionLibraries)
	{
		NSMutableArray* injectionLibrariesM = [NSMutableArray new];

		for (uint32_t i = 0; i < _dyld_image_count(); i++)
		{
			const char *pathC = _dyld_get_image_name(i);
			NSString* path = [NSString stringWithUTF8String:pathC];

			if([path isEqualToString:@"/usr/lib/substitute-inserter.dylib"])
			{
				[injectionLibrariesM addObject:path];
			}
			else if([path isEqualToString:@"/usr/lib/substitute-loader.dylib"])
			{
				[injectionLibrariesM addObject:path];
			}
			else if([path isEqualToString:@"/usr/lib/TweakInject.dylib"])
			{
				[injectionLibrariesM addObject:path];
			}
			else if([path isEqualToString:@"/usr/lib/substrate/SubstrateInserter.dylib"])
			{
				[injectionLibrariesM addObject:path];
			} else if([path isEqualToString:@"/usr/lib/substrate/SubstrateLoader.dylib"])
			{
				[injectionLibrariesM addObject:path];
			}
		}

		injectionLibraries = injectionLibrariesM.copy;
	}

	return injectionLibraries;
}

NSString* getInjectionPlatform()
{
	static NSString* injectionPlatform = nil;

	if(!injectionPlatform)
	{
		for (uint32_t i = 0; i < _dyld_image_count(); i++)
		{
			const char *pathC = _dyld_get_image_name(i);
			NSString* path = [NSString stringWithUTF8String:pathC];

			if([path isEqualToString:@"/usr/lib/substitute-inserter.dylib"])
			{
				injectionPlatform = @"Substitute";
			}
			else if([path isEqualToString:@"/usr/lib/TweakInject.dylib"])
			{
				injectionPlatform = @"libhooker";
			}
			else if([path isEqualToString:@"/usr/lib/substrate/SubstrateInserter.dylib"])
			{
				injectionPlatform = @"Substrate";
			}
		}

		if(!injectionPlatform)
		{
			injectionPlatform = localize(@"THE_INJECTION_PLATFORM");
		}
	}

	return injectionPlatform;
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

- (void)resetPreferences
{
	UIAlertController* resetPreferencesAlert = [UIAlertController alertControllerWithTitle:localize(@"RESET_PREFERENCES") message:localize(@"RESET_PREFERENCES_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* continueAction = [UIAlertAction actionWithTitle:localize(@"CONTINUE") style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action)
	{
		[[NSFileManager defaultManager] removeItemAtPath:kChoicyPrefsPlistPath error:nil];
		[[self class] sendChoicyPrefsPostNotification];
	}];

	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:localize(@"CANCEL") style:UIAlertActionStyleDefault handler:nil];
	
	[resetPreferencesAlert addAction:continueAction];
	[resetPreferencesAlert addAction:cancelAction];

	[self presentViewController:resetPreferencesAlert animated:YES completion:nil];
}

void presentNotLoadingFirstWarning(PSListController* plc, BOOL showDontShowAgainOption)
{
	PSSpecifier* dontShowAgainSpecifier = [PSSpecifier preferenceSpecifierNamed:@"dontShowWarningAgain"
					target:plc
					set:nil
					get:nil
					detail:nil
					cell:0
					edit:nil];

	[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs" forKey:@"defaults"];
	[dontShowAgainSpecifier setProperty:@"dontShowWarningAgain" forKey:@"key"];
	[dontShowAgainSpecifier setProperty:@"com.opa334.choicyprefs/ReloadPrefs" forKey:@"PostNotification"];

	NSNumber* dontShowAgainNum = nil;
	if(showDontShowAgainOption)
	{
		dontShowAgainNum = [plc readPreferenceValue:dontShowAgainSpecifier];
	}

	if(![dontShowAgainNum boolValue])
	{
		NSString* injectionPlatform = getInjectionPlatform();

		NSString* message = [NSString stringWithFormat:localize(@"TWEAKS_LOADING_BEFORE_CHOICY_ALERT_MESSAGE"), injectionPlatform];

		if([injectionPlatform isEqualToString:@"Substrate"])
		{
			message = [message stringByAppendingString:[@" " stringByAppendingString:localize(@"CHOICYLOADER_ADVICE")]];
		}

		UIAlertController* warningAlert = [UIAlertController alertControllerWithTitle:localize(@"WARNING_ALERT_TITLE") message:message preferredStyle:UIAlertControllerStyleAlert];
	
		if([injectionPlatform isEqualToString:@"Substrate"])
		{
			UIAlertAction* openRepoAction = [UIAlertAction actionWithTitle:localize(@"OPEN_REPO") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
			{
				[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://opa334.github.io"]];
			}];

			[warningAlert addAction:openRepoAction];
		}

		if(showDontShowAgainOption)
		{
			UIAlertAction* dontShowAgainAction = [UIAlertAction actionWithTitle:localize(@"DONT_SHOW_AGAIN") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action)
			{
				[plc setPreferenceValue:@1 specifier:dontShowAgainSpecifier];
			}];

			[warningAlert addAction:dontShowAgainAction];
		}

		UIAlertAction* closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];

		[warningAlert addAction:closeAction];

		if([warningAlert respondsToSelector:@selector(setPreferredAction:)])
		{
			warningAlert.preferredAction = closeAction;
		}

		[plc presentViewController:warningAlert animated:YES completion:nil];
	}
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	if(dylibsBeforeChoicy)
	{
		presentNotLoadingFirstWarning(self, YES);
	}
}

@end

void determineLoadingOrder()
{
	NSMutableArray* dylibsInOrder = [NSMutableArray new];

	BOOL isSubstrate = [getInjectionPlatform() isEqualToString:@"Substrate"];
	if(isSubstrate)
	{
		//SubstrateLoader doesn't sort anything and instead process the raw output of readdir
		DIR *dir;
		struct dirent* dp;
		dir = opendir("/Library/MobileSubstrate/DynamicLibraries");
		dp=readdir(dir); //.
		dp=readdir(dir); //..
		while((dp = readdir(dir)) != NULL)
		{
			NSString* filename = [NSString stringWithCString:dp->d_name encoding:NSUTF8StringEncoding];

			if([filename.pathExtension isEqualToString:@"dylib"])
			{
				[dylibsInOrder addObject:[filename stringByDeletingPathExtension]];
			}
		}
	}
	else
	{
		//Anything but substrate sorts the dylibs alphabetically
		NSMutableArray* contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Library/MobileSubstrate/DynamicLibraries" error:nil] mutableCopy];
		NSArray* plists = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@", @"plist"]];
		for(NSString* plist in plists)
		{
			NSString* dylibName = [plist stringByDeletingPathExtension];
			[dylibsInOrder addObject:dylibName];
		}
		[dylibsInOrder sortUsingSelector:@selector(caseInsensitiveCompare:)];
	}

	NSUInteger choicyIndex = [dylibsInOrder indexOfObject:kChoicyDylibName];

	if(choicyIndex == NSNotFound) return;

	if(choicyIndex != 0)
	{
		dylibsBeforeChoicy = [dylibsInOrder subarrayWithRange:NSMakeRange(0,choicyIndex)];
	}

	if(dylibsBeforeChoicy && isSubstrate)
	{
		NSDictionary* targetLoaderAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:@"/usr/lib/substrate/SubstrateLoader.dylib" error:nil];

		if([[targetLoaderAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink])
		{
			NSString* destination = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:@"/usr/lib/substrate/SubstrateLoader.dylib" error:nil];
			if([destination isEqualToString:@"/usr/lib/ChoicyLoader.dylib"])
			{
				// If ChoicyLoader is installed on Substrate, Choicy always loads first
				dylibsBeforeChoicy = nil;
			}
		}
	}
}

__attribute__((constructor))
static void init(void)
{
	reloadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
	determineLoadingOrder();
}