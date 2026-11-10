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

#import "Shared.h"
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

BOOL parseNumberBool(id number, BOOL default_)
{
	if (!number) return default_;
	if (![number isKindOfClass:[NSNumber class]]) return default_;

	NSNumber *numberNum = number;
	return numberNum.boolValue;
}

NSInteger parseNumberInteger(id number, NSInteger default_)
{
	if (!number) return default_;
	if (![number isKindOfClass:[NSNumber class]]) return default_;

	NSNumber *numberNum = number;
	return numberNum.integerValue;
}

NSString *localize(NSString *key)
{	
	static NSBundle *CHBundle;
	static NSDictionary *englishLocalizations;

	if (key == nil) {
		return nil;
	}

	if (!CHBundle) {
		CHBundle = [NSBundle bundleWithPath:JBROOT_PATH_NSSTRING(@"/Library/Application Support/Choicy.bundle")];
	}

	NSString *localizedString = [CHBundle localizedStringForKey:key value:key table:nil];

	if ([localizedString isEqualToString:key]) {
		if (!englishLocalizations) {
			englishLocalizations = [NSDictionary dictionaryWithContentsOfFile:[CHBundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:@"en.lproj"]];
		}

		//If no localization was found, fallback to english
		NSString *engString = [englishLocalizations objectForKey:key];

		if (engString) {
			return engString;
		}
		else {
			//If an english localization was not found, just return the key itself
			return key;
		}
	}

	return localizedString;
}

NSDictionary *processPreferencesForApplication(NSDictionary *preferences, NSString *applicationID)
{
	if (![preferences isKindOfClass:[NSDictionary class]] || ![applicationID isKindOfClass:[NSString class]]) return nil;
	NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
	if (![appSettings isKindOfClass:[NSDictionary class]]) return nil;
	id processPreferences = [appSettings objectForKey:applicationID];
	return [processPreferences isKindOfClass:[NSDictionary class]] ? processPreferences : nil;
}

NSDictionary *processPreferencesForDaemon(NSDictionary *preferences, NSString *daemonDisplayName)
{
	if (![preferences isKindOfClass:[NSDictionary class]] || ![daemonDisplayName isKindOfClass:[NSString class]]) return nil;
	NSDictionary *daemonSettings = [preferences objectForKey:kChoicyPrefsKeyDaemonSettings];
	if (![daemonSettings isKindOfClass:[NSDictionary class]]) return nil;
	id processPreferences = [daemonSettings objectForKey:daemonDisplayName];
	return [processPreferences isKindOfClass:[NSDictionary class]] ? processPreferences : nil;
}

BOOL processPreferencesAreConfigured(NSDictionary *processPreferences)
{
	if (![processPreferences isKindOfClass:[NSDictionary class]]) return NO;
	return parseNumberBool(processPreferences[kChoicyProcessPrefsKeyTweakInjectionDisabled], NO)
		|| parseNumberBool(processPreferences[kChoicyProcessPrefsKeyCustomTweakConfigurationEnabled], NO);
}

static NSString *const kChoicyOpenRequestStaged = @"staged";
static NSString *const kChoicyOpenRequestReady = @"ready";

// SpringBoard and Settings use the same lock for every request-file change.
static int choicyLockOpenRequest(void)
{
	NSString *directory = [kChoicyOpenRequestPath stringByDeletingLastPathComponent];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
	int descriptor = open([[kChoicyOpenRequestPath stringByAppendingString:@".lock"] fileSystemRepresentation], O_CREAT | O_RDWR, 0600);
	if (descriptor >= 0 && flock(descriptor, LOCK_EX) != 0) {
		close(descriptor);
		return -1;
	}
	return descriptor;
}

static void choicyUnlockOpenRequest(int descriptor)
{
	flock(descriptor, LOCK_UN);
	close(descriptor);
}

NSString *choicyStageApplicationSettingsRequest(NSString *applicationID)
{
	if (![applicationID isKindOfClass:[NSString class]] || !applicationID.length) return nil;
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return nil;
	NSString *requestID = [NSUUID UUID].UUIDString;
	NSDictionary *request = @{
		@"applicationIdentifier": applicationID,
		@"requestID": requestID,
		@"createdAt": [NSDate date],
		@"state": kChoicyOpenRequestStaged
	};
	BOOL written = [request writeToFile:kChoicyOpenRequestPath atomically:YES];
	if (!written) {
		// This tap supersedes the previous selection even if staging fails.
		[[NSFileManager defaultManager] removeItemAtPath:kChoicyOpenRequestPath error:nil];
	}
	choicyUnlockOpenRequest(descriptor);
	return written ? requestID : nil;
}

// Read while the request lock is held.
static NSDictionary *choicyReadValidOpenRequest(void)
{
	NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:kChoicyOpenRequestPath];
	NSString *applicationID = request[@"applicationIdentifier"];
	NSString *requestID = request[@"requestID"];
	NSDate *createdAt = request[@"createdAt"];
	id state = request[@"state"];
	if (![applicationID isKindOfClass:[NSString class]] || !applicationID.length
		|| ![requestID isKindOfClass:[NSString class]] || ![[NSUUID alloc] initWithUUIDString:requestID]
		|| ![createdAt isKindOfClass:[NSDate class]]
		|| (![kChoicyOpenRequestStaged isEqual:state] && ![kChoicyOpenRequestReady isEqual:state])) return nil;

	NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:createdAt];
	return age >= 0 && age < kChoicyOpenRequestLifetime ? request : nil;
}

NSDictionary *choicyPendingApplicationSettingsRequest(BOOL readyOnly)
{
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return nil;
	NSDictionary *request = choicyReadValidOpenRequest();
	if (!request) {
		[[NSFileManager defaultManager] removeItemAtPath:kChoicyOpenRequestPath error:nil];
	}
	choicyUnlockOpenRequest(descriptor);
	if (readyOnly && ![kChoicyOpenRequestReady isEqual:request[@"state"]]) return nil;
	return request;
}

BOOL choicyMarkApplicationSettingsRequestReady(NSString *requestID)
{
	if (!requestID.length) return NO;
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return NO;
	NSDictionary *request = choicyReadValidOpenRequest();
	BOOL written = NO;
	if ([requestID isEqual:request[@"requestID"]] && [kChoicyOpenRequestStaged isEqual:request[@"state"]]) {
		NSMutableDictionary *readyRequest = [request mutableCopy];
		readyRequest[@"state"] = kChoicyOpenRequestReady;
		written = [readyRequest writeToFile:kChoicyOpenRequestPath atomically:YES];
	}
	choicyUnlockOpenRequest(descriptor);
	return written;
}

static BOOL choicyRemoveOpenRequest(NSString *requestID, BOOL readyOnly)
{
	if (!requestID.length) return NO;
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return NO;
	// Cancellation can remove an expired request. Consumption requires a live, ready one.
	NSDictionary *request = readyOnly ? choicyReadValidOpenRequest() : [NSDictionary dictionaryWithContentsOfFile:kChoicyOpenRequestPath];
	BOOL matches = [requestID isEqual:request[@"requestID"]];
	BOOL removed = matches && (!readyOnly || [kChoicyOpenRequestReady isEqual:request[@"state"]])
		&& [[NSFileManager defaultManager] removeItemAtPath:kChoicyOpenRequestPath error:nil];
	choicyUnlockOpenRequest(descriptor);
	return removed;
}

BOOL choicyConsumeApplicationSettingsRequest(NSString *requestID)
{
	return choicyRemoveOpenRequest(requestID, YES);
}

BOOL choicyCancelApplicationSettingsRequest(NSString *requestID)
{
	return choicyRemoveOpenRequest(requestID, NO);
}
