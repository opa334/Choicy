// Copyright (c) 2017-2019 Lars Fröder

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

@end

extern void initCHPApplicationPreferenceViewController();
extern void initCHPPreferencesTableDataSource();

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
}