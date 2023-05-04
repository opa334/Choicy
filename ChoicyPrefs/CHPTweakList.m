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

#import "CHPTweakList.h"
#import "CHPTweakInfo.h"
#import "CHPDaemonInfo.h"
#import "CHPMachoParser.h"
#import "../Shared.h"
#import "../HBLogWeak.h"
#import <rootless.h>

@implementation CHPTweakList

+ (instancetype)sharedInstance
{
	static CHPTweakList *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^ {
		//Initialise instance
		sharedInstance = [[CHPTweakList alloc] init];
	});
	return sharedInstance;
}

+ (NSArray *)possibleInjectionLibrariesPaths
{
	// /Library and /usr always gets converted to rootless paths on xina, so this workaround is neccessary
	return @[[@"/" stringByAppendingString:@"Library/MobileSubstrate/DynamicLibraries"], [@"/" stringByAppendingString:@"usr/lib/TweakInject"], @"/var/jb/Library/MobileSubstrate/DynamicLibraries", @"/var/jb/usr/lib/TweakInject"];
}

+ (NSString *)injectionLibrariesPath
{
	for (NSString *possibleInjectionLibrariesPath in [self possibleInjectionLibrariesPaths]) {
		if ([[NSFileManager defaultManager] fileExistsAtPath:possibleInjectionLibrariesPath]) {
			return possibleInjectionLibrariesPath;
		}
	}

	@throw [[NSException alloc] initWithName:@"TweakDirectoryException" reason:[NSString stringWithFormat:@"Unable to locate tweak installation directory"] userInfo:nil];
}

+ (BOOL)isTweakLibraryPath:(NSString *)path
{
	if (![path.pathExtension isEqualToString:@"dylib"]) return NO;

	for (NSString *possibleInjectionLibrariesPath in [self possibleInjectionLibrariesPaths]) {
		if ([path hasPrefix:possibleInjectionLibrariesPath]) return YES;
	}

	return NO;
}

+ (NSURL *)injectionLibrariesURL
{
	return [NSURL fileURLWithPath:[self injectionLibrariesPath]].URLByResolvingSymlinksInPath;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		[self updateTweakList];
	}
	return self;
}

- (void)updateTweakList
{
	NSMutableArray *tweakListM = [NSMutableArray new];
	NSArray *dynamicLibraries = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[CHPTweakList injectionLibrariesURL] includingPropertiesForKeys:nil options:0 error:nil];

	for (NSURL *URL in dynamicLibraries) {
		if ([[URL pathExtension] isEqualToString:@"plist"]) {
			NSURL *dylibURL = [[URL URLByDeletingPathExtension] URLByAppendingPathExtension:@"dylib"];
			if ([dylibURL checkResourceIsReachableAndReturnError:nil]) {
				CHPTweakInfo *tweakInfo = [[CHPTweakInfo alloc] initWithDylibPath:dylibURL.path plistPath:URL.path];
				[tweakListM addObject:tweakInfo];
			}
		}
	}

	[tweakListM sortUsingSelector:@selector(caseInsensitiveCompare:)];

	self.tweakList = [tweakListM copy];
}

- (NSArray *)tweakListForExecutableAtPath:(NSString *)executablePath
{
	HBLogDebugWeak(@"tweakListForExecutableAtPath:%@", executablePath);
	if (!executablePath) return nil;

	NSString *bundleID = [NSBundle bundleWithPath:executablePath.stringByDeletingLastPathComponent].bundleIdentifier;
	NSString *executableName = executablePath.lastPathComponent;
	NSSet *linkedFrameworks = frameworkBundleIDsForMachoAtPath(executablePath);

	NSMutableArray *tweakListForExecutable = [NSMutableArray new];
	[self.tweakList enumerateObjectsUsingBlock:^(CHPTweakInfo *tweakInfo, NSUInteger idx, BOOL *stop) {
		if (bundleID) {
			if ([tweakInfo.filterBundles containsObject:bundleID]) {
				[tweakListForExecutable addObject:tweakInfo];
				return;
			}
		}

		if (executableName) {
			if ([tweakInfo.filterExecutables containsObject:executableName]) {
				[tweakListForExecutable addObject:tweakInfo];
				return;
			}
		}
		
		if (linkedFrameworks) {
			[linkedFrameworks enumerateObjectsUsingBlock:^(NSString *frameworkID, BOOL *stop) {
				if ([tweakInfo.filterBundles containsObject:frameworkID]) {
					[tweakListForExecutable addObject:tweakInfo];
					*stop = YES;
				}
			}];
		}
	}];

	return tweakListForExecutable;
}

- (BOOL)oneOrMoreTweaksInjectIntoExecutableAtPath:(NSString *)executablePath
{
	for (CHPTweakInfo *tweakInfo in [self tweakListForExecutableAtPath:executablePath]) {
		if ([tweakInfo.dylibName containsString:@"Choicy"]) {
			continue;
		}
		
		return YES;
	}

	return NO;
}

- (BOOL)isTweak:(CHPTweakInfo *)tweak hiddenForApplicationWithIdentifier:(NSString *)applicationID
{
	if ([applicationID isEqualToString:kSpringboardBundleID]) {
		if ([kAlwaysInjectSpringboard containsObject:tweak.dylibName]) {
			return YES;
		}
	}

	if ([applicationID isEqualToString:kPreferencesBundleID]) {
		if ([kAlwaysInjectPreferences containsObject:tweak.dylibName]) {
			return YES;
		}
	}

	return [kAlwaysInjectGlobal containsObject:tweak.dylibName];
}

- (BOOL)isTweakHiddenForAnyProcess:(CHPTweakInfo *)tweak
{
	if ([self isTweak:tweak hiddenForApplicationWithIdentifier:kSpringboardBundleID]) {
		return YES;
	}

	if ([self isTweak:tweak hiddenForApplicationWithIdentifier:kPreferencesBundleID]) {
		return YES;
	}

	return NO;
}

@end