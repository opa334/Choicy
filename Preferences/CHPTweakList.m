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

#import "CHPTweakList.h"

#import "CHPTweakInfo.h"

@implementation CHPTweakList

+ (instancetype)sharedInstance
{
	static CHPTweakList* sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^
	{
		//Initialise instance
		sharedInstance = [[CHPTweakList alloc] init];
	});
	return sharedInstance;
}

- (void)updateTweakList
{
    NSMutableArray* tweakListM = [NSMutableArray new];
    NSArray* dynamicLibraries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/Library/MobileSubstrate/DynamicLibraries"].URLByResolvingSymlinksInPath includingPropertiesForKeys:nil options:0 error:nil];

    for(NSURL* URL in dynamicLibraries)
    {
        if([[URL pathExtension] isEqualToString:@"plist"])
        {
            NSURL* dylibURL = [[URL URLByDeletingPathExtension] URLByAppendingPathExtension:@"dylib"];
            if([dylibURL checkResourceIsReachableAndReturnError:nil])
            {
                CHPTweakInfo* tweakInfo = [[CHPTweakInfo alloc] initWithDylibPath:dylibURL.path plistPath:URL.path];
                [tweakListM addObject:tweakInfo];
            }
        }
    }

    self.tweakList = [tweakListM copy];
}

- (NSArray*)tweakListForKey:(NSString*)key
{
    NSMutableArray* tweakListForKey = [NSMutableArray new];

    for(CHPTweakInfo* info in self.tweakList)
    {
        if([info.filterBundles containsObject:@"com.apple.UIKit"] || [info.filterBundles containsObject:key] || [info.filterExecutables containsObject:key])
        {
            [tweakListForKey addObject:info];
        }
    }

    return [tweakListForKey copy];
}

@end