#import "CHPApplicationListSubcontrollerController.h"
#import "../Shared.h"

NSString* previewStringForSettings(NSDictionary* settings)
{
	NSNumber* tweakInjectionDisabled = [settings objectForKey:@"tweakInjectionDisabled"];
	NSNumber* customTweakConfigurationEnabled = [settings objectForKey:@"customTweakConfigurationEnabled"];

	if(tweakInjectionDisabled.boolValue)
	{
		return localize(@"TWEAKS_DISABLED");
	}
	else if(customTweakConfigurationEnabled.boolValue)
	{
		return localize(@"CUSTOM");
	}
	else
	{
		return @"";
	}
}

@implementation CHPApplicationListSubcontrollerController

- (NSString*)previewStringForApplicationWithIdentifier:(NSString*)applicationID
{
	NSDictionary* appSettings = [preferences objectForKey:@"appSettings"];
	NSDictionary* settingsForApplication = [appSettings objectForKey:applicationID];
	return previewStringForSettings(settingsForApplication);
}

@end