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

#import "CHPDaemonListController.h"
#import "CHPPreferences.h"

#import <AppList/AppList.h>
#import "../Shared.h"

#import "CHPDaemonInfo.h"
#import "CHPDaemonList.h"
#import "CHPProcessConfigurationListController.h"
#import "CHPApplicationListSubcontrollerController.h"

@interface PSListController()
- (id)controllerForSpecifier:(PSSpecifier*)specifier;
@end

@implementation CHPDaemonListController

- (void)viewDidLoad
{
	[self applySearchControllerHideWhileScrolling:NO];
	[[CHPDaemonList sharedInstance] addObserver:self];

	if(![CHPDaemonList sharedInstance].loaded)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
		{
			[[CHPDaemonList sharedInstance] updateDaemonListIfNeeded];
		});
	}
	else
	{
		[self updateSuggestedDaemons];
	}

	[super viewDidLoad];
}

- (NSString*)topTitle
{
	return localize(@"DAEMONS");
}

- (NSString*)plistName
{
	return nil;
}

- (NSMutableArray*)specifiers
{
	if(!_specifiers)
	{
		_specifiers = [NSMutableArray new];

		if(kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_11_0)
		{
			[_specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
			[_specifiers addObject:[PSSpecifier emptyGroupSpecifier]];
		}

		if(![CHPDaemonList sharedInstance].loaded)
		{
			PSSpecifier* loadingIndicator = [PSSpecifier preferenceSpecifierNamed:@""
							target:self
							set:nil
							get:nil
							detail:nil
							cell:[PSTableCell cellTypeFromString:@"PSSpinnerCell"]
							edit:nil];

			[_specifiers addObject:loadingIndicator];
		}
		else
		{
			NSString* toggleName;

			if(_showsAllDaemons)
			{
				toggleName = localize(@"SHOW_RECOMMENDED_DAEMONS");
			}
			else
			{
				toggleName = localize(@"SHOW_ALL_DAEMONS");
			}

			PSSpecifier* daemonToggleSpecifier = [PSSpecifier preferenceSpecifierNamed:toggleName
							target:self
							set:nil
							get:nil
							detail:nil
							cell:PSButtonCell
							edit:nil];

			[daemonToggleSpecifier setProperty:@YES forKey:@"enabled"];
			daemonToggleSpecifier.buttonAction = @selector(daemonTogglePressed:);
			[_specifiers addObject:daemonToggleSpecifier];

			PSSpecifier* daemonsGroup = [PSSpecifier emptyGroupSpecifier];
			[daemonsGroup setProperty:localize(@"DAEMON_LIST_BOTTOM_NOTICE") forKey:@"footerText"];
			[_specifiers addObject:daemonsGroup];

			NSArray<CHPDaemonInfo*>* daemonList = [CHPDaemonList sharedInstance].daemonList;

			for(CHPDaemonInfo* info in daemonList)
			{
				if(_showsAllDaemons || [_suggestedDaemons containsObject:[info executableName]])
				{
					if(_searchKey && ![_searchKey isEqualToString:@""])
					{
						if(![[info executableName] localizedStandardContainsString:_searchKey])
						{
							continue;
						}
					}
					
					PSSpecifier* specifier = [PSSpecifier preferenceSpecifierNamed:[info executableName]
								target:self
								set:nil
								get:@selector(previewStringForSpecifier:)
								detail:[CHPProcessConfigurationListController class]
								cell:PSLinkListCell
								edit:nil];
					
					[specifier setProperty:@YES forKey:@"enabled"];
					[specifier setProperty:info.executablePath forKey:@"executablePath"];

					[_specifiers addObject:specifier];
				}
			}
		}
	}

	return _specifiers;
}

- (id)previewStringForSpecifier:(PSSpecifier*)specifier
{
	NSString* executablePath = [specifier propertyForKey:@"executablePath"];

	NSDictionary* daemonSettings = [preferences objectForKey:kChoicyPrefsKeyDaemonSettings];
	NSDictionary* settingsForDaemon = [daemonSettings objectForKey:executablePath.lastPathComponent];
	return [CHPApplicationListSubcontrollerController previewStringForProcessPreferences:settingsForDaemon];
}

- (void)daemonTogglePressed:(PSSpecifier*)specifier
{
	_showsAllDaemons = !_showsAllDaemons;

	[self reloadSpecifiers];
}

- (void)reloadValueOfSelectedSpecifier
{
	UITableView* tableView = [self valueForKey:@"_table"];
	for(NSIndexPath* selectedIndexPath in tableView.indexPathsForSelectedRows)
	{
		PSSpecifier* specifier = [self specifierAtIndex:[self indexForIndexPath:selectedIndexPath]];
		[self reloadSpecifier:specifier];
	}
}

- (void)updateSuggestedDaemons
{
	NSMutableSet* suggestedDaemons = [NSMutableSet new];

	for(CHPDaemonInfo* info in [CHPDaemonList sharedInstance].daemonList)
	{
		if([info.linkedFrameworkIdentifiers containsObject:@"com.apple.UIKit"])
		{
			[suggestedDaemons addObject:[info executableName]];
		}
	}

	_suggestedDaemons = [suggestedDaemons copy];
}

- (void)daemonListDidUpdate:(CHPDaemonList*)list
{
	[self updateSuggestedDaemons];
	[self reloadSpecifiers];
}

- (id)controllerForSpecifier:(PSSpecifier*)specifier
{
	if(kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_11_0)
	{
		[UIView performWithoutAnimation:^
		{
			_searchController.active = NO;
		}];
	}

	return [super controllerForSpecifier:specifier];
}

@end
