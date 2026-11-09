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

#import "CHPApplicationListSubcontrollerController.h"
#import "../Shared.h"
#import "CHPPreferences.h"
#import "CHPListController.h"

@implementation CHPApplicationListSubcontrollerController

- (void)viewDidLoad
{
	[super viewDidLoad];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(choicy_preferencesDidReload:) name:kChoicyPreferencesDidReloadNotification object:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	choicy_reloadPreferences();
	[self reloadSpecifiers];
}

- (void)choicy_preferencesDidReload:(NSNotification *)notification
{
	[self reloadSpecifiers];
}

- (NSMutableArray *)specifiers
{
	BOOL needsOrdering = !_specifiers;
	NSMutableArray *inherited = [super specifiers];
	if (!needsOrdering) return inherited;

	// AltList 1.0.4+ filters _allSpecifiers into _specifiers for the current
	// query. Preferences and AltList both resolve row selection from _specifiers.
	// Copy that array; never rearrange AltList's unfiltered cache or its sections.
	NSMutableArray *configured = [NSMutableArray new];
	NSMutableArray *ordinary = [NSMutableArray new];
	NSMutableSet *seen = [NSMutableSet new];
	PSSpecifier *pendingGroup = nil;
	for (PSSpecifier *specifier in [inherited copy]) {
		if (specifier.cellType == PSGroupCell) {
			pendingGroup = specifier;
			continue;
		}
		NSString *applicationID = [specifier propertyForKey:@"applicationIdentifier"];
		if (applicationID.length) {
			specifier.identifier = applicationID;
			if ([seen containsObject:applicationID]) continue;
			[seen addObject:applicationID];
		}
		if (processPreferencesAreConfigured(processPreferencesForApplication(preferences, applicationID))) {
			[configured addObject:specifier];
		}
		else {
			if (pendingGroup) {
				[ordinary addObject:pendingGroup];
				pendingGroup = nil;
			}
			[ordinary addObject:specifier];
		}
	}
	if (!configured.count) return inherited;
	[configured sortUsingComparator:^NSComparisonResult(PSSpecifier *a, PSSpecifier *b) {
		NSComparisonResult result = [(a.name ?: @"") localizedCaseInsensitiveCompare:(b.name ?: @"")];
		return result == NSOrderedSame ? [a.identifier compare:b.identifier] : result;
	}];
	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	group.name = localize(@"CONFIGURED");
	_specifiers = [NSMutableArray arrayWithObject:group];
	[_specifiers addObjectsFromArray:configured];
	[_specifiers addObjectsFromArray:ordinary];
	return _specifiers;
}

- (NSString *)previewStringForApplicationWithIdentifier:(NSString *)applicationID
{
	NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
	NSDictionary *settingsForApplication = [appSettings objectForKey:applicationID];
	return [CHPListController previewStringForProcessPreferences:settingsForApplication];
}

// Older Crane versions depend on this
+ (NSString *)previewStringForProcessPreferences:(NSDictionary *)processPreferences
{
	return [CHPListController previewStringForProcessPreferences:processPreferences];
}

@end
