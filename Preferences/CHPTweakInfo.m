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

#import "CHPTweakInfo.h"

@implementation CHPTweakInfo

- (instancetype)initWithDylibPath:(NSString*)dylibPath plistPath:(NSString*)plistPath
{
	self = [super init];

	self.dylibName = [[dylibPath lastPathComponent] stringByDeletingPathExtension];

	NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];

	NSDictionary* filter = [plist objectForKey:@"Filter"];

	if(filter)
	{
		self.filterBundles = [filter objectForKey:@"Bundles"];
		self.filterExecutables = [filter objectForKey:@"Executables"];

		//If a plist filters classes, treat it as UIKit (maybe inaccurate, maybe not)
		NSArray* classes = [filter objectForKey:@"Classes"];
		if(classes && classes.count > 0 && ![self.filterBundles containsObject:@"com.apple.Security"])
		{
			if(!self.filterBundles)
			{
				self.filterBundles = @[@"com.apple.Security"];
			}
			else
			{
				self.filterBundles = [self.filterBundles arrayByAddingObject:@"com.apple.Security"];
			}
		}
	}

	return self;
}

- (NSString*)description
{
	return [NSString stringWithFormat:@"<CHPTweakInfo: dylibName = %@, filterBundles = %@, filterExecutables = %@>", self.dylibName, self.filterBundles, self.filterExecutables];
}

@end