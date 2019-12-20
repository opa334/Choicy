#import "CHPListController.h"

@interface CHPGlobalTweakConfigurationController : CHPListController
{
	NSMutableArray* _globalTweakBlacklist;
}

- (void)loadGlobalTweakBlacklist;
- (void)saveGlobalTweakBlacklist;

@end