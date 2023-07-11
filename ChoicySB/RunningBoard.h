#import <Foundation/Foundation.h>

@interface RBSProcessIdentity : NSObject
@property(readonly, copy, nonatomic) NSString *executablePath;
@property(readonly, copy, nonatomic) NSString *embeddedApplicationIdentifier;
@end

@interface RBSLaunchContext : NSObject
@property (setter=_setAdditionalEnvironment:,nonatomic,copy) NSDictionary *_additionalEnvironment;
@property (nonatomic,copy) RBSProcessIdentity *identity;
@property (nonatomic,copy) NSString *bundleIdentifier;
@end

@interface RBSLaunchRequest : NSObject
@property (nonatomic,readonly) RBSLaunchContext *context;
@end
