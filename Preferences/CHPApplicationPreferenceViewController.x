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

#import "CHPApplicationPreferenceViewController.h"
#import "../Shared.h"

extern NSDictionary* preferences;

NSString* previewStringForSettings(NSDictionary* settings)
{
	NSNumber* tweakInjectionDisabled = [settings objectForKey:@"tweakInjectionDisabled"];
	NSNumber* customTweakConfigurationEnabled = [settings objectForKey:@"customTweakConfigurationEnabled"];

	if(tweakInjectionDisabled.boolValue)
	{
		return localize(@"TWEAKS_DISABLED");
	}
	else if(customTweakConfigurationEnabled.boolValue)
	{
		return localize(@"CUSTOM");
	}
	else
	{
		return @"";
	}
}

@interface CHPApplicationPreferenceViewController()
@property (strong) UISearchController*searchController;
@end

%subclass CHPApplicationPreferenceViewController : ALApplicationPreferenceViewController

%property (strong) UISearchController*searchController;

- (id)initForContentSize:(CGSize)size
{
	CHPApplicationPreferenceViewController* orig = %orig;

	UISearchController *searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController = searchController;
	searchController.searchResultsUpdater = (id<UISearchResultsUpdating>) self;
	if (@available(iOS 9.1, *)) searchController.obscuresBackgroundDuringPresentation = NO;

	if (@available(iOS 11.0, *))
	{
		self.navigationItem.searchController = searchController;
		self.navigationItem.hidesSearchBarWhenScrolling=NO;
	}
	else
	{
		UITableView* tableView = [orig valueForKey:@"_tableView"];
		tableView.tableHeaderView = searchController.searchBar;
	}

	ALPreferencesTableDataSource* dataSource = [self valueForKey:@"_dataSource"];
	object_setClass(dataSource, NSClassFromString(@"CHPPreferencesTableDataSource"));

	[[NSNotificationCenter defaultCenter] addObserver:orig selector:@selector(reloadValueOfVisibleCells) name:@"preferencesDidReload" object:nil];

	return orig;
}

- (void)pushController:(id)arg
{
	if(kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_11_0)
	{
		[UIView performWithoutAnimation:^
		{
			self.searchController.active=NO;
		}];
	}
    %orig;
}

%new
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
	NSString *searchKey = searchController.searchBar.text;

	NSMutableArray* descriptorsM = [self.specifier.properties[@"ALSectionDescriptors"] mutableCopy];

	for(NSDictionary* desc in [descriptorsM reverseObjectEnumerator])
	{
		NSMutableDictionary* newDesc = [desc mutableCopy];

		if(!newDesc[@"orig_predicate"]) newDesc[@"orig_predicate"] = newDesc[@"predicate"];

		if([searchKey isEqualToString:@""])
		{
			newDesc[@"predicate"] = newDesc[@"orig_predicate"];
		}
		else
		{
			newDesc[@"predicate"] = [NSString stringWithFormat:@"%@ AND displayName CONTAINS[cd] '%@'", newDesc[@"orig_predicate"], searchKey];
		}

		[descriptorsM replaceObjectAtIndex:[descriptorsM indexOfObject:desc] withObject:[newDesc copy]];
	}

	[self.specifier setProperty:[descriptorsM copy] forKey:@"ALSectionDescriptors"];

	[self loadFromSpecifier:self.specifier];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	%orig;
}

%new
- (void)reloadValueOfVisibleCells
{
	UITableView* tableView = [self valueForKey:@"_tableView"];

	for(id cell in tableView.visibleCells)
	{
		if([cell isKindOfClass:NSClassFromString(@"ALValueCell")])
		{
			NSIndexPath* indexPath = [tableView indexPathForCell:cell];
			[(ALValueCell *)cell loadValue:[self valueForCellAtIndexPath:indexPath] withTitle:[self valueTitleForCellAtIndexPath:indexPath]];
		}
	}
}

- (id)valueForCellAtIndexPath:(NSIndexPath *)indexPath
{
	ALApplicationTableDataSource* dataSource = [self valueForKey:@"_dataSource"];
	ALApplicationTableDataSourceSection* section = [[dataSource valueForKey:@"_sectionDescriptors"] objectAtIndex:indexPath.section];
	NSString* displayIdentifier = [section displayIdentifierForRow:indexPath.row];

	NSDictionary* appSettings = [preferences objectForKey:@"appSettings"];

	NSDictionary* settingsForApp = [appSettings objectForKey:displayIdentifier];

	return previewStringForSettings(settingsForApp);
}

%end

void initCHPApplicationPreferenceViewController()
{
	%config(generator=internal)
	%init;
}