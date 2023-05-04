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

#import "CHPApplicationPlugInsListController.h"
#import "CoreServices.h"
#import <MobileCoreServices/LSApplicationProxy.h>
#import <MobileCoreServices/LSPlugInKitProxy.h>
#import "CHPProcessConfigurationListController.h"
#import "../Shared.h"
#import "CHPPreferences.h"
#import "CHPApplicationListSubcontrollerController.h"

@implementation CHPApplicationPlugInsListController

- (void)loadPlugIns
{
	NSString *applicationID = [self applicationIdentifier];
	LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:applicationID];
	
	NSMutableArray *appPlugIns = [NSMutableArray new];
	[appPlugIns addObjectsFromArray:[appProxy plugInKitPlugins]];
	[appPlugIns addObjectsFromArray:[appProxy VPNPlugins]];

	_appPlugIns = [appPlugIns sortedArrayUsingComparator:^NSComparisonResult(LSPlugInKitProxy *p1, LSPlugInKitProxy *p2) {
		NSString *p1Name = p1.infoPlist[@"CFBundleExecutable"];
		NSString *p2Name = p2.infoPlist[@"CFBundleExecutable"];
		return [p1Name caseInsensitiveCompare:p2Name];
	}];
}

- (PSSpecifier *)newSpecifierForPlugIn:(LSPlugInKitProxy *)plugInProxy
{
	NSString *plugInName = plugInProxy.infoPlist[@"CFBundleExecutable"];
	// alternative on iOS 14+
	/*else if (NSClassFromString(@"LSApplicationExtensionRecord")) {
		LSApplicationExtensionRecord *appexRecord = [plugInProxy valueForKey:@"_appexRecord"];
		plugInName = appexRecord.executableURL.lastPathComponent;
	}*/

	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:plugInName
						  target:self
						  set:nil
						  get:@selector(previewStringForSpecifier:)
						  detail:[CHPProcessConfigurationListController class]
						  cell:PSLinkListCell
						  edit:nil];

	[specifier setProperty:@YES forKey:@"enabled"];
	[specifier setProperty:plugInProxy.bundleIdentifier forKey:@"plugInIdentifier"];

	return specifier;
}

- (NSString *)applicationIdentifier
{
	return [[self specifier] propertyForKey:@"applicationIdentifier"];
}

- (NSMutableArray *)specifiers
{
	if (!_specifiers) {
		_specifiers = [NSMutableArray new];

		[self loadPlugIns];

		[_appPlugIns enumerateObjectsUsingBlock:^(LSPlugInKitProxy *plugInProxy, NSUInteger idx, BOOL *stop) {
			PSSpecifier *plugInSpecifier = [self newSpecifierForPlugIn:plugInProxy];
			[_specifiers addObject:plugInSpecifier];
		}];
	}

	return _specifiers;
}

- (NSString *)previewStringForSpecifier:(PSSpecifier *)specifier
{
	NSString *plugInID = [specifier propertyForKey:@"plugInIdentifier"];
	NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
	NSDictionary *settingsForApplication = [appSettings objectForKey:plugInID];
	return [CHPApplicationListSubcontrollerController previewStringForProcessPreferences:settingsForApplication];
}

@end