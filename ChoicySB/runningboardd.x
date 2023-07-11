#import <Foundation/Foundation.h>
#import "../Shared.h"
#import "ChoicyOverrideManager.h"
#import "ChoicySB.h"
#import "RunningBoard.h"

%hook RBProcessManager

- (id)executeLaunchRequest:(RBSLaunchRequest *)launchRequest withError:(NSError **)errorOut
{
	choicy_applyEnvironmentChangesToLaunchContext(launchRequest.context);
	return %orig;
}

%end

void choicy_initRunningBoardd(void)
{
	%init();
}