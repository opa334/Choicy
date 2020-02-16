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

#import "CHPDaemonListController.h"

#import <AppList/AppList.h>
#import "../Shared.h"

#import "CHPDaemonInfo.h"
#import "CHPDaemonList.h"
#import "CHPApplicationDaemonConfigurationListController.h"

@implementation CHPDaemonListController

- (void)viewDidLoad
{
	[[CHPDaemonList sharedInstance] addObserver:self];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadValueOfSelectedSpecifier) name:@"preferencesDidReload" object:nil];

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

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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
	NSMutableArray* specifiers = [self valueForKey:@"_specifiers"];

	if(!specifiers)
	{
		specifiers = [NSMutableArray new];

		if(![CHPDaemonList sharedInstance].loaded)
		{
			PSSpecifier* loadingIndicator = [PSSpecifier preferenceSpecifierNamed:@""
							target:self
							set:nil
							get:nil
							detail:nil
							cell:[PSTableCell cellTypeFromString:@"PSSpinnerCell"]
							edit:nil];

			[specifiers addObject:loadingIndicator];
		}
		else
		{
			NSArray<CHPDaemonInfo*>* daemonList = [CHPDaemonList sharedInstance].daemonList;

			for(CHPDaemonInfo* info in daemonList)
			{
				if(_showsAllDaemons || [_suggestedDaemons containsObject:[info displayName]])
				{
					PSSpecifier* specifier = [PSSpecifier preferenceSpecifierNamed:[info displayName]
								target:self
								set:nil
								get:@selector(previewStringForSpecifier:)
								detail:[CHPApplicationDaemonConfigurationListController class]
								cell:PSLinkListCell
								edit:nil];
					
					[specifier setProperty:@YES forKey:@"enabled"];
					[specifier setProperty:[info displayName] forKey:@"key"];
					[specifier setProperty:info forKey:@"daemonInfo"];
					[specifier setProperty:@NO forKey:@"isApplication"];

					[specifiers addObject:specifier];
				}
			}

			PSSpecifier* buttonGroup = [PSSpecifier preferenceSpecifierNamed:@""
							target:self
							set:nil
							get:nil
							detail:nil
							cell:PSGroupCell
							edit:nil];

			[buttonGroup setProperty:localize(@"DAEMON_LIST_BOTTOM_NOTICE") forKey:@"footerText"];

			[specifiers addObject:buttonGroup];

			NSString* toggleName;

			if(_showsAllDaemons)
			{
				toggleName = localize(@"SHOW_RECOMMENDED_DAEMONS");
			}
			else
			{
				toggleName = localize(@"SHOW_ALL_DAEMONS");
			}

			PSSpecifier* specifier = [PSSpecifier preferenceSpecifierNamed:toggleName
							target:self
							set:nil
							get:nil
							detail:nil
							cell:PSButtonCell
							edit:nil];

			[specifier setProperty:@YES forKey:@"enabled"];
			specifier.buttonAction = @selector(daemonTogglePressed:);
			[specifiers addObject:specifier];
		}

		[self setValue:specifiers forKey:@"_specifiers"];
	}

	return specifiers;
}

extern NSString* previewStringForSettings(NSDictionary* settings);

- (id)previewStringForSpecifier:(PSSpecifier*)specifier
{
	NSString* identifier = [specifier propertyForKey:@"key"];

	NSDictionary* daemonSettings = [preferences objectForKey:@"daemonSettings"];

	NSDictionary* settingsForDaemon = [daemonSettings objectForKey:identifier];

	return previewStringForSettings(settingsForDaemon);
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
			[suggestedDaemons addObject:[info displayName]];
		}
	}

	_suggestedDaemons = [suggestedDaemons copy];
}

- (void)daemonListDidUpdate:(CHPDaemonList*)list
{
	[self updateSuggestedDaemons];
	[self reloadSpecifiers];
}

@end
