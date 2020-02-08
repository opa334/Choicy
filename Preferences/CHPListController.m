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

#import "CHPListController.h"
#import "../Shared.h"

@implementation CHPListController

//Must be overwritten by subclass
- (NSString*)topTitle
{
	return nil;
}

//Must be overwritten by subclass
- (NSString*)plistName
{
	return nil;
}

- (NSMutableArray*)specifiers
{
	if(!_specifiers)
	{
		NSString* plistName = [self plistName];

		if(plistName)
		{
			_specifiers = [self loadSpecifiersFromPlistName:plistName target:self];
			[self parseLocalizationsForSpecifiers:_specifiers];
		}
	}

	NSString* title = [self topTitle];
	if(title)
	{
		[(UINavigationItem *)self.navigationItem setTitle:title];
	}

	return _specifiers;
}

- (void)parseLocalizationsForSpecifiers:(NSArray*)specifiers
{
	//Localize specifiers
	NSMutableArray* mutableSpecifiers = (NSMutableArray*)specifiers;
	for(PSSpecifier* specifier in mutableSpecifiers)
	{
		HBLogDebug(@"title:%@",specifier.properties[@"label"]);
		NSString* localizedTitle = localize(specifier.properties[@"label"]);
		NSString* localizedFooter = localize(specifier.properties[@"footerText"]);
		specifier.name = localizedTitle;
		[specifier setProperty:localizedFooter forKey:@"footerText"];
	}
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier
{
	NSMutableDictionary* mutableDict = [NSMutableDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	if(!mutableDict)
	{
		mutableDict = [NSMutableDictionary new];
	}
	[mutableDict setObject:value forKey:[[specifier properties] objectForKey:@"key"]];
	[mutableDict writeToFile:CHPPlistPath atomically:YES];

	[self sendPostNotificationForSpecifier:specifier];
}

- (id)readPreferenceValue:(PSSpecifier*)specifier
{
	NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];

	id obj = [dict objectForKey:[[specifier properties] objectForKey:@"key"]];

	if(!obj)
	{
		obj = [[specifier properties] objectForKey:@"default"];
	}

	return obj;
}

- (void)sendPostNotificationForSpecifier:(PSSpecifier*)specifier
{
	NSString* postNotification = [specifier propertyForKey:@"PostNotification"];
	if(postNotification)
	{
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)postNotification, NULL, NULL, YES);
	}
}

@end