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

#import "CHPDaemonList.h"
#import "CHPDaemonInfo.h"

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

- (void)updateDaemonListIfNeeded
{
    if(_loaded || _loading)
    {
        return;
    }

    _loading = YES;

    NSMutableArray<NSURL*>* daemonPlists = [[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:@"/System/Library/LaunchDaemons"] includingPropertiesForKeys:nil options:0 error:nil] mutableCopy];

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
        NSNumber* disabled = [daemonDictionary objectForKey:@"Disabled"];
        if(!disabled.boolValue)
        {
            CHPDaemonInfo* info = [[CHPDaemonInfo alloc] init];

            NSArray* programArguments = [daemonDictionary objectForKey:@"ProgramArguments"];

            info.executablePath = programArguments.firstObject;

            if(!info.executablePath)
            {
                NSString* program = [daemonDictionary objectForKey:@"Program"];
                if(program)
                {
                    info.executablePath = program;
                }
            }

            info.plistIdentifier = [daemonPlistURL lastPathComponent].stringByDeletingPathExtension;

            if(info.executablePath && ![info.plistIdentifier hasSuffix:@"Jetsam"] && ![info.plistIdentifier hasSuffix:@"SimulateCrash"] && ![info.plistIdentifier hasSuffix:@"_v2"]) //Filter out some useless entries
            {
                [daemonListM addObject:info];
            }
        }
    }

    NSDirectoryEnumerator* systemLibraryAppPlaceholdersEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"/System/Library/AppPlaceholders" isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^(NSURL *url, NSError *error)
    {
        return YES;
    }];

    NSDirectoryEnumerator* systemLibraryFrameworksEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"/System/Library/Frameworks" isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^(NSURL *url, NSError *error)
    {
        return YES;
    }];

    NSDirectoryEnumerator* systemLibraryPrivateFrameworksEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks" isDirectory:YES] includingPropertiesForKeys:nil options:0 errorHandler:^(NSURL *url, NSError *error)
    {
        return YES;
    }];

    NSMutableArray* XPCUrls = [NSMutableArray new];

    for(NSURL* fileURL in systemLibraryAppPlaceholdersEnumerator)
    {
        if([fileURL.path hasSuffix:@".xpc"])
        {
            [XPCUrls addObject:fileURL];
        }
    }

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

        if([XPCPath isEqualToString:@"/System/Library/PrivateFrameworks/Accessibility.framework/Frameworks/com.apple.accessibility.AccessibilityUIServer.xpc"]) //Fix duplicate?
        {
            continue;
        }

        NSString* XPCName = [XPCUrl.lastPathComponent stringByReplacingOccurrencesOfString:@".xpc" withString:@""];

        NSString* XPCExecutablePath = [XPCPath stringByAppendingPathComponent:XPCName];

        CHPDaemonInfo* info = [[CHPDaemonInfo alloc] init];
        info.executablePath = XPCExecutablePath;

        [daemonListM addObject:info];
    }

    [daemonListM sortUsingComparator:^NSComparisonResult(CHPDaemonInfo* a, CHPDaemonInfo* b)  //Sort alphabetically
    {
        return [[a displayName] localizedCaseInsensitiveCompare:[b displayName]];
    }];

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
            [observer reloadSpecifiers];
        });
    }
}

@end