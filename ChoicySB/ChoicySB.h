#import "SpringBoard.h"

extern NSDictionary *preferences;

void choicy_reloadPreferences(void);
BOOL choicy_shouldDisableTweakInjectionForApplication(NSString *applicationID);
NSDictionary *choicy_applyEnvironmentChanges(NSDictionary *originalEnvironment, NSString *bundleIdentifier);
void choicy_applyEnvironmentChangesToLaunchContext(RBSLaunchContext *launchContext);
void choicy_applyEnvironmentChangesToExecutionContext(FBProcessExecutionContext *executionContext, NSString *bundleIdentifier);