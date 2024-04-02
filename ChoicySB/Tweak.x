#import <Foundation/Foundation.h>
#import "../Shared.h"
#import "../ChoicyPrefsMigrator.h"
#import "ChoicyOverrideManager.h"
#import "ChoicySB.h"

NSDictionary *preferences;
BOOL gIsSpringBoard = NO;

extern void choicy_initSpringBoard(void);
extern void choicy_initRunningBoardd(void);

extern char** *_NSGetArgv();
NSString *safe_getExecutablePath()
{
	char *executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

void choicy_reloadPreferences(void)
{
	if (preferences) {
		NSDictionary *oldPreferences = [preferences copy];
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];

		if (gIsSpringBoard) {
			NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
			NSDictionary *oldAppSettings = [oldPreferences objectForKey:kChoicyPrefsKeyAppSettings];

			NSMutableSet *allApps = [NSMutableSet setWithArray:[appSettings allKeys]];
			[allApps unionSet:[NSMutableSet setWithArray:[oldAppSettings allKeys]]];

			NSMutableSet *changedApps = [NSMutableSet new];

			for (NSString *appKey in allApps) {
				if (![((NSDictionary *)[appSettings objectForKey:appKey]) isEqualToDictionary:((NSDictionary *)[oldAppSettings objectForKey:appKey])]) {
					[changedApps addObject:appKey];
				}
			}

			for (NSString *applicationID in changedApps) {
				if (![applicationID isEqualToString:kSpringboardBundleID] && ![applicationID isEqualToString:kPreferencesBundleID]) {
					BKSTerminateApplicationForReasonAndReportWithDescription(applicationID, 5, false, @"Choicy - prefs changed, killed");
				}
			}
		}
	}
	else {
		NSString *parentDir = [kChoicyPrefsPlistPath stringByDeletingLastPathComponent];
		if (![[NSFileManager defaultManager] fileExistsAtPath:parentDir]) {
			[[NSFileManager defaultManager] createDirectoryAtPath:parentDir withIntermediateDirectories:YES attributes:nil error:nil];
		}
		preferences = [NSDictionary dictionaryWithContentsOfFile:kChoicyPrefsPlistPath];
	}
}

BOOL choicy_shouldDisableTweakInjectionForApplication(NSString *applicationID)
{
	BOOL safeMode = NO;

	BOOL overrideExists;
	BOOL disableTweakInjectionOverrideValue = [[ChoicyOverrideManager sharedManager] disableTweakInjectionOverrideForApplication:applicationID overrideExists:&overrideExists];
	if (overrideExists) {
		return disableTweakInjectionOverrideValue;
	}

	NSDictionary *settingsForApp = processPreferencesForApplication(preferences, applicationID);

	if (settingsForApp && [settingsForApp isKindOfClass:[NSDictionary class]]) {
		if (![applicationID isEqualToString:kPreferencesBundleID]) {
			safeMode = ((NSNumber *)[settingsForApp objectForKey:kChoicyProcessPrefsKeyTweakInjectionDisabled]).boolValue;
		}
	}

	return safeMode;
}

NSDictionary *choicy_applyEnvironmentChanges(NSDictionary *originalEnvironment, NSString *bundleIdentifier)
{
	if (originalEnvironment[@"_MSSafeMode"] || originalEnvironment[@"_SafeMode"]) {
		// If this is set, it was set by the SpringBoard hook and that should act as an override
		// To support the haptic touch app option
		return originalEnvironment;
	}

	NSMutableDictionary *newEnvironment = originalEnvironment.mutableCopy ?: [NSMutableDictionary new];
	if (choicy_shouldDisableTweakInjectionForApplication(bundleIdentifier)) {
		[newEnvironment setObject:@(1) forKey:@"_MSSafeMode"];
		[newEnvironment setObject:@(1) forKey:@"_SafeMode"];
	}
	else {
		ChoicyOverrideManager *overrideManager = [ChoicyOverrideManager sharedManager];
		BOOL overrideExists = NO;

		BOOL customTweakConfigurationEnabledOverride = [overrideManager customTweakConfigurationEnabledOverwriteForApplication:bundleIdentifier overrideExists:&overrideExists];
		if (overrideExists) {
			if (!customTweakConfigurationEnabledOverride) {
				// if custom tweak configuration has been overwritten with NO
				// set up an empty deny list
				[newEnvironment setObject:@"" forKey:@kEnvDeniedTweaksOverride];
			}
			else {
				BOOL customTweakAllowDenyOverride = [overrideManager customTweakConfigurationAllowDenyModeOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];
				NSArray *allowDenyList = [overrideManager customTweakConfigurationAllowOrDenyListOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];

				if (overrideManager && allowDenyList) {
					NSString *allowDenyString = [allowDenyList componentsJoinedByString:@"/"];

					NSString *envName;
					if (customTweakAllowDenyOverride) { // DENY
						envName = @kEnvDeniedTweaksOverride;
					}
					else { //ALLOW
						envName = @kEnvAllowedTweaksOverride;
					}

					//NSLog(@"set %@ to %@", envName, allowDenyString);

					[newEnvironment setObject:allowDenyString forKey:envName];
				}
			}
		}

		BOOL overwriteGlobalConfigurationOverride = [overrideManager overwriteGlobalConfigurationOverrideForApplication:bundleIdentifier overrideExists:&overrideExists];
		//NSLog(@"overwriteGlobalConfigurationOverride=%i overrideExists=%i", overwriteGlobalConfigurationOverride, overrideExists);
		if (overrideExists) {
			NSString *envToSet;
			if (overwriteGlobalConfigurationOverride) {
				envToSet = @"1";
			}
			else {
				envToSet = @"0";
			}

			[newEnvironment setObject:envToSet forKey:@kEnvOverwriteGlobalConfigurationOverride];
		}
	}
	return newEnvironment;
}

void choicy_applyEnvironmentChangesToLaunchContext(RBSLaunchContext *launchContext)
{
	NSString *bundleIdentifier;
	if ([launchContext respondsToSelector:@selector(bundleIdentifier)]) {
		bundleIdentifier = launchContext.bundleIdentifier;
	}
	else {
		bundleIdentifier = launchContext.identity.embeddedApplicationIdentifier;
	}
	launchContext._additionalEnvironment = choicy_applyEnvironmentChanges(launchContext._additionalEnvironment, bundleIdentifier);
}

void choicy_applyEnvironmentChangesToExecutionContext(FBProcessExecutionContext *executionContext, NSString *bundleIdentifier)
{
	executionContext.environment = choicy_applyEnvironmentChanges(executionContext.environment, bundleIdentifier);
}

%ctor
{
	choicy_reloadPreferences();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)choicy_reloadPreferences, CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

	if (preferences && [ChoicyPrefsMigrator preferencesNeedMigration:preferences]) {
		NSMutableDictionary *preferencesM = preferences.mutableCopy;
		[ChoicyPrefsMigrator migratePreferences:preferencesM];
		[ChoicyPrefsMigrator updatePreferenceVersion:preferencesM];
		[preferencesM writeToFile:kChoicyPrefsPlistPath atomically:NO];
		CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.opa334.choicyprefs/ReloadPrefs"), NULL, NULL, YES);
	}

	NSString *executablePath = safe_getExecutablePath();
	if ([executablePath.lastPathComponent isEqualToString:@"SpringBoard"]) {
		gIsSpringBoard = YES;
		choicy_initSpringBoard();
	}
	else if ([executablePath.lastPathComponent isEqualToString:@"runningboardd"]) {
		choicy_initRunningBoardd();
	}
}