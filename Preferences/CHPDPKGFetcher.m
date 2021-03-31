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

#import "CHPDPKGFetcher.h"

@implementation CHPDPKGFetcher

+ (instancetype)sharedInstance
{
	static CHPDPKGFetcher *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^
	{
		sharedInstance = [[CHPDPKGFetcher alloc] init];
	});
	return sharedInstance;
}

- (void)_parseStatusForInfos
{
	NSString* status = [NSString stringWithContentsOfFile:@"/var/lib/dpkg/status" encoding:NSUTF8StringEncoding error:nil];
	_infos = [status componentsSeparatedByString:@"\n\n"];
}

- (void)_deleteInfos
{
	_infos = nil;
}

- (NSString*)_getPackageNameForPackageIdentifier:(NSString*)packageIdentifier
{
	NSString* prefix = [NSString stringWithFormat:@"Package: %@", packageIdentifier];
	for(NSString* info in _infos)
	{
		if([info hasPrefix:prefix])
		{
			NSArray* lines = [info componentsSeparatedByString:@"\n"];
			for(NSString* line in lines)
			{
				if([line hasPrefix:@"Name: "])
				{
					return [line stringByReplacingOccurrencesOfString:@"Name: " withString:@""];
				}
			}
		}
	}

	return nil;
}

- (void)_populatePackageNames
{
	// /Library/dpkg/info *.list

	HBLogDebug(@"_populatePackageNames start");

	[self _parseStatusForInfos];

	NSString* dirPath = @"/var/lib/dpkg/info";
	NSDirectoryEnumerator* dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];
	NSMutableDictionary* packageNamesForDylibPathsM = [NSMutableDictionary new];
	NSString* filename;

	while(filename = [dirEnum nextObject])
	{
		if([filename hasSuffix:@".list"])
		{
			NSString* content = [NSString stringWithContentsOfFile:[dirPath stringByAppendingPathComponent:filename]
                encoding:NSUTF8StringEncoding error:nil];

			if(content)
			{
				NSArray* lines = [content componentsSeparatedByString:@"\n"];
				for(NSString* line in lines)
				{
					if([line hasPrefix:@"/Library/MobileSubstrate/DynamicLibraries"] && [line.pathExtension isEqualToString:@"dylib"])
					{
						NSString* packageID = [filename stringByDeletingPathExtension];
						NSString* packageName = [self _getPackageNameForPackageIdentifier:packageID];

						if(!packageName)
						{
							break;
						}

						[packageNamesForDylibPathsM setObject:packageName forKey:[[line lastPathComponent] stringByDeletingPathExtension]];
					}
				}
			}
		}
	}

	_packageNamesForDylibNames = [packageNamesForDylibPathsM copy];

	[self _deleteInfos];

	HBLogDebug(@"_populatePackageNames end");
}

- (NSString*)getPackageNameForDylibWithName:(NSString*)dylibName
{
	if(!_packageNamesForDylibNames)
	{
		[self _populatePackageNames];
	}

	return [_packageNamesForDylibNames objectForKey:dylibName];
}

@end