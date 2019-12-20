#import "CHPGlobalTweakConfigurationController.h"
#import "CHPTweakList.h"
#import "CHPTweakInfo.h"
#import "../Shared.h"

@implementation CHPGlobalTweakConfigurationController

- (NSString*)topTitle
{
	return localize(@"GLOBAL_TWEAK_CONFIGURATION");
}

- (NSString*)plistName
{
	return @"GlobalTweakConfiguration";
}

- (NSMutableArray*)specifiers
{
	if(![self valueForKey:@"_specifiers"])
	{
		NSMutableArray* specifiers = [super specifiers];

		[self loadGlobalTweakBlacklist];

		for(CHPTweakInfo* tweakInfo in [CHPTweakList sharedInstance].tweakList)
		{
			if([tweakInfo.dylibName containsString:@"Choicy"])
			{
				continue;
			}

			PSSpecifier* tweakSpecifier = [PSSpecifier preferenceSpecifierNamed:tweakInfo.dylibName
						  target:self
						  set:@selector(setValue:forTweakWithSpecifier:)
						  get:@selector(readValueForTweakWithSpecifier:)
						  detail:nil
						  cell:PSSwitchCell
						  edit:nil];
			
			[tweakSpecifier setProperty:@YES forKey:@"enabled"];
			[tweakSpecifier setProperty:tweakInfo.dylibName forKey:@"key"];
			[tweakSpecifier setProperty:@YES forKey:@"default"];

			[specifiers addObject:tweakSpecifier];
		}

		[self setValue:specifiers forKey:@"_specifiers"];
	}

	return [self valueForKey:@"_specifiers"];
}

- (void)setValue:(id)value forTweakWithSpecifier:(PSSpecifier*)specifier
{
	NSNumber* numberValue = value;

	if(numberValue.boolValue)
	{
		[_globalTweakBlacklist removeObject:[specifier propertyForKey:@"key"]];
	}
	else
	{
		[_globalTweakBlacklist addObject:[specifier propertyForKey:@"key"]];
	}

	[self saveGlobalTweakBlacklist];
	[self sendPostNotificationForSpecifier:specifier];
}

- (id)readValueForTweakWithSpecifier:(PSSpecifier*)specifier
{
	if([_globalTweakBlacklist containsObject:[specifier propertyForKey:@"key"]])
	{
		return @0;
	}
	else
	{
		return @1;
	}
}

- (void)loadGlobalTweakBlacklist
{
	NSDictionary* dict = [NSDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	_globalTweakBlacklist = [[dict objectForKey:@"globalTweakBlacklist"] mutableCopy] ?: [NSMutableArray new];
}

- (void)saveGlobalTweakBlacklist
{
	NSMutableDictionary* mutableDict = [NSMutableDictionary dictionaryWithContentsOfFile:CHPPlistPath];
	if(!mutableDict)
	{
		mutableDict = [NSMutableDictionary new];
	}

	[mutableDict setObject:[_globalTweakBlacklist copy] forKey:@"globalTweakBlacklist"];
	[mutableDict writeToFile:CHPPlistPath atomically:YES];
}

@end