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

// Serialize the read/consume pair with SpringBoard's next write, so consuming an
// older request cannot accidentally remove a newer app selection.
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

BOOL choicyWriteApplicationSettingsRequest(NSString *applicationID)
{
	if (![applicationID isKindOfClass:[NSString class]] || !applicationID.length) return NO;
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return NO;
	NSDictionary *request = @{@"applicationIdentifier": applicationID, @"requestID": [NSUUID UUID].UUIDString, @"createdAt": [NSDate date]};
	BOOL written = [request writeToFile:kChoicyOpenRequestPath atomically:YES];
	choicyUnlockOpenRequest(descriptor);
	return written;
}

NSDictionary *choicyPendingApplicationSettingsRequest(void)
{
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return nil;
	NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:kChoicyOpenRequestPath];
	NSString *applicationID = request[@"applicationIdentifier"];
	NSString *requestID = request[@"requestID"];
	NSDate *createdAt = request[@"createdAt"];
	BOOL valid = [applicationID isKindOfClass:[NSString class]] && applicationID.length
		&& [requestID isKindOfClass:[NSString class]] && requestID.length
		&& [createdAt isKindOfClass:[NSDate class]]
		&& createdAt.timeIntervalSinceNow <= 0 && createdAt.timeIntervalSinceNow >= -60;
	if (!valid) {
		[[NSFileManager defaultManager] removeItemAtPath:kChoicyOpenRequestPath error:nil];
		request = nil;
	}
	choicyUnlockOpenRequest(descriptor);
	return request;
}

BOOL choicyConsumeApplicationSettingsRequest(NSString *requestID)
{
	if (!requestID.length) return NO;
	int descriptor = choicyLockOpenRequest();
	if (descriptor < 0) return NO;
	NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:kChoicyOpenRequestPath];
	BOOL matches = [requestID isEqual:request[@"requestID"]];
	BOOL consumed = matches && [[NSFileManager defaultManager] removeItemAtPath:kChoicyOpenRequestPath error:nil];
	choicyUnlockOpenRequest(descriptor);
	return consumed;
}
