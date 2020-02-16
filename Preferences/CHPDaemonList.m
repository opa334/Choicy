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

#import "CHPDaemonList.h"
#import "CHPDaemonInfo.h"
#import "CHPMachoParser.h"
#import "CHPTweakList.h"

#import <dirent.h>

@implementation CHPDaemonList

+ (instancetype)sharedInstance
{
	static CHPDaemonList* sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^
	{
		//Initialise instance
		sharedInstance = [[CHPDaemonList alloc] init];
	});
	return sharedInstance;
}

- (instancetype)init
{
	self = [super init];

	_observers = [NSHashTable weakObjectsHashTable];

	return self;
}

- (BOOL)daemonList:(NSArray*)daemonList containsDisplayName:(NSString*)displayName
{
	for(CHPDaemonInfo* info in daemonList)
	{
		if([info.displayName isEqualToString:displayName])
		{
			return YES;
		}
	}

	return NO;
}

- (void)updateDaemonListIfNeeded
{
	if(_loaded || _loading)
	{
		return;
	}

	_loading = YES;

	NSMutableArray<NSURL*>* daemonPlists = [[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/System/Library/LaunchDaemons"] includingPropertiesForKeys:nil options:0 error:nil] mutableCopy];

	[daemonPlists addObjectsFromArray:[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/System/Library/NanoLaunchDaemons"] includingPropertiesForKeys:nil options:0 error:nil]];

	[daemonPlists addObjectsFromArray:[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/Library/LaunchDaemons"] includingPropertiesForKeys:nil options:0 error:nil]];

	for(NSURL* daemonPlistURL in [daemonPlists reverseObjectEnumerator])
	{
		if(![daemonPlistURL.pathExtension isEqualToString:@"plist"])
		{
			[daemonPlists removeObject:daemonPlistURL];
		}
	}

	NSMutableArray* daemonListM = [NSMutableArray new];

	for(NSURL* daemonPlistURL in daemonPlists)
	{
		NSDictionary* daemonDictionary = [NSDictionary dictionaryWithContentsOfURL:daemonPlistURL];
		
		CHPDaemonInfo* info = [[CHPDaemonInfo alloc] init];

		info.executablePath = [daemonDictionary objectForKey:@"Program"];

		if(!info.executablePath)
		{
			NSArray* programArguments = [daemonDictionary objectForKey:@"ProgramArguments"];
			if(programArguments.count > 0)
			{
				info.executablePath = programArguments.firstObject;
			}
		}

		info.plistIdentifier = [daemonPlistURL lastPathComponent].stringByDeletingPathExtension;

		if(info.executablePath && [[NSFileManager defaultManager] fileExistsAtPath:info.executablePath] && ![info.plistIdentifier hasSuffix:@"Jetsam"] && ![info.plistIdentifier hasSuffix:@"SimulateCrash"] && ![info.plistIdentifier hasSuffix:@"_v2"] && ![info.plistIdentifier isEqualToString:@"com.apple.SpringBoard"]) //Filter out some useless entries
		{
			if(![self daemonList:daemonListM containsDisplayName:info.displayName])
			{
				[daemonListM addObject:info];
			}
		}
	}

	NSDirectoryEnumerator* systemLibraryFrameworksEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"/System/Library/Frameworks" isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^(NSURL *url, NSError *error)
	{
		return YES;
	}];

	NSDirectoryEnumerator* systemLibraryPrivateFrameworksEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks" isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^(NSURL *url, NSError *error)
	{
		return YES;
	}];

	NSMutableArray* XPCUrls = [NSMutableArray new];

	for(NSURL* fileURL in systemLibraryFrameworksEnumerator)
	{
		if([fileURL.path hasSuffix:@".xpc"])
		{
			[XPCUrls addObject:fileURL];
		}
	}

	for(NSURL* fileURL in systemLibraryPrivateFrameworksEnumerator)
	{
		if([fileURL.path hasSuffix:@".xpc"])
		{
			[XPCUrls addObject:fileURL];
		}
	}

	for(NSURL* XPCUrl in XPCUrls)
	{
		NSString* XPCPath = XPCUrl.path;

		NSString* XPCName = [XPCUrl.lastPathComponent stringByReplacingOccurrencesOfString:@".xpc" withString:@""];

		NSString* XPCExecutablePath = [XPCPath stringByAppendingPathComponent:XPCName];

		if([[NSFileManager defaultManager] fileExistsAtPath:XPCExecutablePath])
		{
			CHPDaemonInfo* info = [[CHPDaemonInfo alloc] init];
			info.executablePath = XPCExecutablePath;

			if(![self daemonList:daemonListM containsDisplayName:info.displayName])
			{
				[daemonListM addObject:info];
			}
		}
	}

	NSMutableArray* additionalPotentialDaemons = [NSMutableArray new];

	// On A12 unc0ver, using contentsOfDirectoryAtURL on /usr/libexec locks the thread and leaves a kernel thread looping
	// This causes all sorts of issues and heats the device up
	// This has been fixed in unc0ver 4.0, but we still use the old solution because some people might not be updated to 4.0
	// The C API is not affected by this issue, so we just use it instead
	DIR *dir;
    struct dirent* dp;
    dir = opendir("/usr/libexec");
    while ((dp=readdir(dir)) != NULL)
	{
        if (!(!strcmp(dp->d_name, ".") || !strcmp(dp->d_name, "..")))
        {
            NSString* filename = [NSString stringWithCString:dp->d_name encoding:NSUTF8StringEncoding];
            if(filename)
			{
				NSURL* URL = [NSURL fileURLWithPath:[@"/usr/libexec" stringByAppendingPathComponent:filename]];
				HBLogDebug(@"added %@", URL);
				[additionalPotentialDaemons addObject:URL];
			}
        }
    }
    closedir(dir);

	/*[additionalPotentialDaemons addObjectsFromArray:[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/usr/libexec" isDirectory:YES] 
                    includingPropertiesForKeys:nil 
                                       options:0 
                                         error:nil]];*/
	
	[additionalPotentialDaemons addObjectsFromArray:[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/usr/bin" isDirectory:YES] 
                    includingPropertiesForKeys:nil 
                                       options:0 
                                         error:nil]];
	
	[additionalPotentialDaemons addObjectsFromArray:[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/usr/sbin" isDirectory:YES] 
                    includingPropertiesForKeys:nil 
                                       options:0 
                                         error:nil]];
	

	for(NSURL* URL in additionalPotentialDaemons)
	{
		if([URL.lastPathComponent hasSuffix:@"d"])
		{
			CHPDaemonInfo* info = [[CHPDaemonInfo alloc] init];
			info.executablePath = [URL path];

			if(![self daemonList:daemonListM containsDisplayName:info.displayName])
			{
				[daemonListM addObject:info];
			}
		}
	}

	[daemonListM sortUsingComparator:^NSComparisonResult(CHPDaemonInfo* a, CHPDaemonInfo* b)  //Sort alphabetically
	{
		return [[a displayName] localizedCaseInsensitiveCompare:[b displayName]];
	}];

	CHPTweakList* tweakList = [CHPTweakList sharedInstance];

	for(CHPDaemonInfo* daemonInfo in [daemonListM reverseObjectEnumerator])
	{
		daemonInfo.linkedFrameworkIdentifiers = frameworkBundleIDsForMachoAtPath(nil, daemonInfo.executablePath);

		if(![tweakList oneOrMoreTweaksInjectIntoDaemon:daemonInfo])
		{
			[daemonListM removeObject:daemonInfo];
		}
	}

	_daemonList = [daemonListM copy];
	_loading = NO;
	_loaded = YES;

	[self sendReloadToObservers];
}

- (void)addObserver:(id<CHPDaemonListObserver>)observer
{
	if(![_observers containsObject:observer])
	{
		[_observers addObject:observer];
	}
}

- (void)removeObserver:(id<CHPDaemonListObserver>)observer
{
	if([_observers containsObject:observer])
	{
		[_observers removeObject:observer];
	}
}

- (void)sendReloadToObservers
{
	for(id<CHPDaemonListObserver> observer in _observers)
	{
		dispatch_async(dispatch_get_main_queue(), ^
		{
			[observer daemonListDidUpdate:self];
		});
	}
}

@end