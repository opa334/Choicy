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

#import "Shared.h"

NSBundle* CHBundle;
NSDictionary* englishLocalizations;
NSDictionary* preferences;

NSString* localize(NSString* key)
{	
	if(key == nil)
	{
		return nil;
	}

	if(!CHBundle)
	{
		CHBundle = [NSBundle bundleWithPath:@"/Library/Application Support/Choicy.bundle"];
	}

	NSString* localizedString = [CHBundle localizedStringForKey:key value:key table:nil];

	if([localizedString isEqualToString:key])
	{
		if(!englishLocalizations)
		{
			englishLocalizations = [NSDictionary dictionaryWithContentsOfFile:[CHBundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:@"en.lproj"]];
		}

		//If no localization was found, fallback to english
		NSString* engString = [englishLocalizations objectForKey:key];

		if(engString)
		{
			return engString;
		}
		else
		{
			//If an english localization was not found, just return the key itself
			return key;
		}
	}

	return localizedString;
}

NSDictionary* preferencesForApplicationWithID(NSString* applicationID)
{
	NSDictionary* appSettings = [preferences objectForKey:@"appSettings"];
	return [appSettings objectForKey:applicationID];
}

NSDictionary* preferencesForDaemonWithDisplayName(NSString* daemonDisplayName)
{
	NSDictionary* daemonSettings = [preferences objectForKey:@"daemonSettings"];
	return [daemonSettings objectForKey:daemonDisplayName];
}