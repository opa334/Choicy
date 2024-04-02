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

#import "CHPPackageInfo.h"
#import "CHPTweakList.h"
#import <libroot.h>

NSDictionary *g_packageNamesByIdentifier;
NSArray *g_packageInfos;

@implementation CHPPackageInfo

+ (void)load
{
	[self loadPackageNames];
	[self loadAvailablePackages];
}

+ (void)loadPackageNames
{
	NSMutableDictionary *packageNamesByIdentifierM = [NSMutableDictionary new];

	NSString *status = [NSString stringWithContentsOfFile:JBROOT_PATH_NSSTRING(@"/var/lib/dpkg/status") encoding:NSUTF8StringEncoding error:nil];
	NSArray *statusSections = [status componentsSeparatedByString:@"\n\n"];
	[statusSections enumerateObjectsUsingBlock:^(NSString *packageInfoStr, NSUInteger idx, BOOL *stop) {
		if ([packageInfoStr hasPrefix:@"Package: "]) {
			NSArray *packageLines = [packageInfoStr componentsSeparatedByString:@"\n"];

			NSString *packageIDLine = packageLines.firstObject;
			NSString *packageID = [packageIDLine substringWithRange:NSMakeRange(9, packageIDLine.length-9)];
			__block NSString *packageName;

			[packageLines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL *stop) {
				if ([line hasPrefix:@"Name: "]) {
					packageName = [line substringWithRange:NSMakeRange(6, line.length-6)];
					*stop = YES;
				}
			}];

			packageNamesByIdentifierM[packageID] = packageName;
		}
	}];

	g_packageNamesByIdentifier = packageNamesByIdentifierM.copy;
}

+ (void)loadAvailablePackages
{
	//Load all packages that have a dylib into g_packageInfos
	NSMutableArray *packageInfos = [NSMutableArray new];

	NSString *dirPath = JBROOT_PATH_NSSTRING(@"/var/lib/dpkg/info");
	NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];

	NSString *filename;
	while (filename = [dirEnum nextObject]) {
		if ([filename hasSuffix:@".list"]) {
			NSString *packageID = [filename stringByDeletingPathExtension];
			CHPPackageInfo *packageInfo = [[CHPPackageInfo alloc] initWithPackageIdentifier:packageID];
			// Filter out packages that do not have tweaks associated
			if (packageInfo.tweakDylibs.count) {
				[packageInfos addObject:packageInfo];
			}
		}
	}

	g_packageInfos = packageInfos.copy;
}

+ (instancetype)fetchPackageInfoForDylibName:(NSString *)dylibName
{
	__block CHPPackageInfo *result = nil;
	[g_packageInfos enumerateObjectsUsingBlock:^(CHPPackageInfo *info, NSUInteger idx, BOOL *stop) {
		if ([info.tweakDylibs containsObject:dylibName]) {
			result = info;
			*stop = YES;
		}
	}];
	return result;
}

+ (NSArray *)allInstalledPackages
{
	NSSortDescriptor *nameSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
	return [g_packageInfos sortedArrayUsingDescriptors:@[nameSortDescriptor]];
}

- (instancetype)initWithPackageIdentifier:(NSString *)packageID
{
	self = [super init];
	if (self) {
		_identifier = packageID;
		_name = g_packageNamesByIdentifier[packageID];
		[self loadTweakDylibs];
	}
	return self;
}

- (void)loadTweakDylibs
{
	NSString *dpkgInfoPath = [NSString stringWithFormat:JBROOT_PATH_NSSTRING(@"/var/lib/dpkg/info/%@.list"), _identifier];
	NSString *dpkgInfo = [NSString stringWithContentsOfFile:dpkgInfoPath encoding:NSUTF8StringEncoding error:nil];

	NSMutableArray *tweakDylibsM = [NSMutableArray new];

	if (dpkgInfo) {
		NSArray *infoLines = [dpkgInfo componentsSeparatedByString:@"\n"];
		[infoLines enumerateObjectsUsingBlock:^(NSString *infoLine, NSUInteger idx, BOOL *stop) {
			if ([CHPTweakList isTweakLibraryPath:infoLine]) {
				NSString *dylibName = infoLine.lastPathComponent.stringByDeletingPathExtension;
				[tweakDylibsM addObject:dylibName];
			}
		}];
	}

	_tweakDylibs = tweakDylibsM.copy;
}

@end