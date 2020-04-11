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

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <HBLog.h>

extern NSBundle* CHBundle;
extern NSString* localize(NSString* key);
extern NSDictionary* preferences;

#define CHPPlistPath @"/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"
#define CHOICY_DYLIB_NAME @"   Choicy"

extern NSDictionary* preferencesForApplicationWithID(NSString* applicationID);
extern NSDictionary* preferencesForDaemonWithDisplayName(NSString* daemonDisplayName);

extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description);

#ifndef kCFCoreFoundationVersionNumber_iOS_11_0
#define kCFCoreFoundationVersionNumber_iOS_11_0 1443.00
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_13_0
#define kCFCoreFoundationVersionNumber_iOS_13_0 1665.15
#endif