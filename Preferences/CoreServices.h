#import <MobileCoreServices/LSApplicationProxy.h>

@interface LSApplicationProxy ()
+ (instancetype)applicationProxyForIdentifier:(NSString*)identifier;
@property (nonatomic,readonly) NSString* canonicalExecutablePath;
@property (nonatomic,readonly) NSURL * bundleURL;
@property (nonatomic,readonly) NSString * bundleExecutable;
@property (nonatomic,readonly) NSArray * VPNPlugins;
@end

@interface LSBundleRecord : NSObject
@property (readonly) NSURL* executableURL;
@end

@interface LSApplicationExtensionRecord : LSBundleRecord
@end