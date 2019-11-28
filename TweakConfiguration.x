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

#import "Shared.h"

#import <dlfcn.h>

NSArray* tweakWhitelist;
NSArray* tweakBlacklist;

%group BlockAllTweaks

%hookf(void *, dlopen, const char *path, int mode)
{
    if(path != NULL)
    {
        NSString* NSPath = @(path);

        if([NSPath containsString:@"TweakInject"] || [NSPath containsString:@"MobileSubstrate/DynamicLibraries"])
        {
            return NULL;
        }
    }

    return %orig;
}

%end

%group CustomConfiguration

%hookf(void *, dlopen, const char *path, int mode)
{
    if(path != NULL)
    {
        NSString* NSPath = @(path);

        if([NSPath containsString:@"TweakInject"] || [NSPath containsString:@"MobileSubstrate/DynamicLibraries"])
        {
            NSString* dylibName = [NSPath.lastPathComponent stringByDeletingPathExtension];

            if(tweakWhitelist)
            {
                if(![tweakWhitelist containsObject:dylibName])
                {
                    return NULL;
                }
            }

            if(tweakBlacklist)
            {
                if([tweakBlacklist containsObject:dylibName])
                {
                    return NULL;
                }
            }
        }
    }

    return %orig;
}

%end

void initTweakConfiguration()
{
    BOOL isApplication = [executablePath containsString:@"/Application"];
    BOOL isSpringBoard = [executablePath.lastPathComponent isEqualToString:@"SpringBoard"];
    NSDictionary* settings;

    if(isApplication || isSpringBoard)
    {
        settings = preferencesForApplicationWithID([NSBundle mainBundle].bundleIdentifier);
    }
    else
    {
        settings = preferencesForDaemonWithDisplayName(executablePath.lastPathComponent);
    }

    if(settings)
    {
        BOOL tweakInjectionDisabled = ((NSNumber*)[settings objectForKey:@"tweakInjectionDisabled"]).boolValue;
        BOOL customTweakConfigurationEnabled = ((NSNumber*)[settings objectForKey:@"customTweakConfigurationEnabled"]).boolValue;

        if(!isApplication && tweakInjectionDisabled)
        {
            %init(BlockAllTweaks);
        }
        else if(customTweakConfigurationEnabled)
        {
            NSInteger whitelistBlacklistSegment = ((NSNumber*)[settings objectForKey:@"whitelistBlacklistSegment"]).intValue;

            if(whitelistBlacklistSegment == 2) //blacklist
            {
                tweakBlacklist = [settings objectForKey:@"tweakBlacklist"];
            }
            else //whitelist
            {
                tweakWhitelist = [settings objectForKey:@"tweakWhitelist"];
            }

            %init(CustomConfiguration);
        }
    }
}