// Copyright (c) 2019-2020 Lars Fröder

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

@interface RBSProcessIdentity : NSObject
@property(readonly, copy, nonatomic) NSString *executablePath;
@property(readonly, copy, nonatomic) NSString *embeddedApplicationIdentifier;
@end

@interface FBProcessExecutionContext : NSObject
@property (nonatomic,copy) NSDictionary* environment;
@property (nonatomic,copy) RBSProcessIdentity* identity;
@end

@interface FBProcessManager : NSObject
- (void)handleSafeModeForExecutionContext:(FBProcessExecutionContext*)executionContext withApplicationID:(NSString*)applicationID;
@end



@interface SBApplicationInfo : NSObject
@property (nonatomic,readonly) NSURL* executableURL;
@property (nonatomic,readonly) BOOL hasHiddenTag;
@property (nonatomic,retain,readonly) NSArray* tags;
@end

@interface SBApplication : NSObject
- (SBApplicationInfo*)_appInfo;
@end

@interface SBSApplicationShortcutIcon : NSObject
@end

@interface SBSApplicationShortcutSystemItem : SBSApplicationShortcutIcon
- (instancetype)initWithSystemImageName:(NSString*)systemImageName;
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic,copy) NSString* type;
@property (nonatomic,copy) NSString* localizedTitle;
@property (nonatomic,copy) NSString* localizedSubtitle;
@property (nonatomic,copy) SBSApplicationShortcutIcon* icon;
@property (nonatomic,copy) NSDictionary* userInfo; 
@property (assign,nonatomic) NSUInteger activationMode;
@property (nonatomic,copy) NSString* bundleIdentifierToLaunch;
@end

@interface SBIconView : NSObject
- (NSString*)applicationBundleIdentifier;
- (NSString*)applicationBundleIdentifierForShortcuts;
@end

@interface SBUIAppIconForceTouchControllerDataProvider : NSObject
- (NSString*)applicationBundleIdentifier;
@end