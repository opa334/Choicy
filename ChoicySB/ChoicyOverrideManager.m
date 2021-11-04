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

#import "ChoicyOverrideManager.h"

@implementation ChoicyOverrideManager

+ (instancetype)sharedManager
{
	static ChoicyOverrideManager *sharedManager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^
	{
		sharedManager = [[ChoicyOverrideManager alloc] init];
	});
	return sharedManager;
}

- (instancetype)init
{
	self = [super init];

	_overrideProviders = [NSMutableArray new];

	return self;
}

- (void)registerOverrideProvider:(NSObject<ChoicyOverrideProvider>*)provider
{
	[_overrideProviders addObject:provider];
}

- (void)unregisterOverrideProvider:(NSObject<ChoicyOverrideProvider>*)provider
{
	[_overrideProviders removeObject:provider];
}

- (BOOL)disableTweakInjectionOverrideForApplication:(NSString*)applicationID overrideExists:(BOOL*)overrideExists
{
	__block BOOL overrideExists_ = NO;
	__block BOOL overrideValue = NO;

	[_overrideProviders enumerateObjectsUsingBlock:^(NSObject<ChoicyOverrideProvider>* overrideProvider, NSUInteger idx, BOOL *stop)
	{
		uint32_t providedOverrides = [overrideProvider providedOverridesForApplication:applicationID];
		if((providedOverrides & Choicy_Override_DisableTweakInjection) == Choicy_Override_DisableTweakInjection)
		{
			overrideExists_ = YES;
			if([overrideProvider respondsToSelector:@selector(disableTweakInjectionOverrideForApplication:)])
			{
				overrideValue = [overrideProvider disableTweakInjectionOverrideForApplication:applicationID];
				*stop = YES;
			}
		}
	}];

	if(overrideExists) *overrideExists = overrideExists_;
	return overrideValue;
}

- (BOOL)customTweakConfigurationEnabledOverwriteForApplication:(NSString*)applicationID overrideExists:(BOOL*)overrideExists
{
	__block BOOL overrideExists_ = NO;
	__block BOOL overrideValue = NO;

	[_overrideProviders enumerateObjectsUsingBlock:^(NSObject<ChoicyOverrideProvider>* overrideProvider, NSUInteger idx, BOOL *stop)
	{
		uint32_t providedOverrides = [overrideProvider providedOverridesForApplication:applicationID];
		if((providedOverrides & Choicy_Override_CustomTweakConfiguration) == Choicy_Override_CustomTweakConfiguration)
		{
			overrideExists_ = YES;
			if([overrideProvider respondsToSelector:@selector(customTweakConfigurationEnabledOverrideForApplication:)])
			{
				overrideValue = [overrideProvider customTweakConfigurationEnabledOverrideForApplication:applicationID];
				*stop = YES;
			}
		}
	}];

	if(overrideExists) *overrideExists = overrideExists_;
	return overrideValue;
}

- (BOOL)customTweakConfigurationAllowDenyModeOverrideForApplication:(NSString*)applicationID overrideExists:(BOOL*)overrideExists
{
	__block BOOL overrideExists_ = NO;
	__block BOOL overrideValue = NO;

	[_overrideProviders enumerateObjectsUsingBlock:^(NSObject<ChoicyOverrideProvider>* overrideProvider, NSUInteger idx, BOOL *stop)
	{
		uint32_t providedOverrides = [overrideProvider providedOverridesForApplication:applicationID];
		if((providedOverrides & Choicy_Override_CustomTweakConfiguration) == Choicy_Override_CustomTweakConfiguration)
		{
			overrideExists_ = YES;
			if([overrideProvider respondsToSelector:@selector(customTweakConfigurationAllowDenyModeOverrideForApplication:)])
			{
				overrideValue = [overrideProvider customTweakConfigurationAllowDenyModeOverrideForApplication:applicationID];
				*stop = YES;
			}
		}
	}];

	if(overrideExists) *overrideExists = overrideExists_;
	return overrideValue;
}

- (NSArray*)customTweakConfigurationAllowOrDenyListOverrideForApplication:(NSString*)applicationID overrideExists:(BOOL*)overrideExists
{
	__block BOOL overrideExists_ = NO;
	__block NSArray* overrideValue = nil;

	[_overrideProviders enumerateObjectsUsingBlock:^(NSObject<ChoicyOverrideProvider>* overrideProvider, NSUInteger idx, BOOL *stop)
	{
		uint32_t providedOverrides = [overrideProvider providedOverridesForApplication:applicationID];
		if((providedOverrides & Choicy_Override_CustomTweakConfiguration) == Choicy_Override_CustomTweakConfiguration)
		{
			overrideExists_ = YES;
			if([overrideProvider respondsToSelector:@selector(customTweakConfigurationAllowOrDenyListOverrideForApplication:)])
			{
				overrideValue = [overrideProvider customTweakConfigurationAllowOrDenyListOverrideForApplication:applicationID];
				*stop = YES;
			}
		}
	}];

	if(overrideExists) *overrideExists = overrideExists_;
	return overrideValue;
}

- (BOOL)overwriteGlobalConfigurationOverrideForApplication:(NSString*)applicationID overrideExists:(BOOL*)overrideExists
{
	__block BOOL overrideExists_ = NO;
	__block BOOL overrideValue = NO;

	[_overrideProviders enumerateObjectsUsingBlock:^(NSObject<ChoicyOverrideProvider>* overrideProvider, NSUInteger idx, BOOL *stop)
	{
		uint32_t providedOverrides = [overrideProvider providedOverridesForApplication:applicationID];
		if((providedOverrides & Choicy_Override_OverrideGlobalConfiguration) == Choicy_Override_OverrideGlobalConfiguration)
		{
			overrideExists_ = YES;
			if([overrideProvider respondsToSelector:@selector(overwriteGlobalConfigurationOverrideForApplication:)])
			{
				overrideValue = [overrideProvider overwriteGlobalConfigurationOverrideForApplication:applicationID];
				*stop = YES;
			}
		}
	}];

	if(overrideExists) *overrideExists = overrideExists_;
	return overrideValue;
}

@end