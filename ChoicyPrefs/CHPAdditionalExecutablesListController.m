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

#import "CHPAdditionalExecutablesListController.h"
#import <Preferences/PSSpecifier.h>
#import "CHPPreferences.h"
#import "../Shared.h"
#import "CHPProcessConfigurationListController.h"
#import "CHPMachoParser.h"
#import "CHPApplicationListSubcontrollerController.h"
#import "CHPTweakList.h"

@implementation CHPAdditionalExecutablesListController

- (id)_editButtonBarItem
{
	UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonPressed)];
	return addButton;
}

- (PSSpecifier *)newSpecifierForExecutable:(NSString *)executablePath
{
	PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:executablePath
		target:self
		set:nil
		get:@selector(previewStringForSpecifier:)
		detail:[CHPProcessConfigurationListController class]
		cell:PSLinkListCell
		edit:nil];

	if ([executablePath.stringByDeletingLastPathComponent.pathExtension isEqualToString:@"app"]) {
		NSString *appDirectory = executablePath.stringByDeletingLastPathComponent;
		NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:[appDirectory stringByAppendingPathComponent:@"Info.plist"]];
		NSString *appIdentifier = appInfo[@"CFBundleIdentifier"];
		[specifier setProperty:appIdentifier forKey:@"applicationIdentifier"];
	}
	else if ([executablePath.stringByDeletingLastPathComponent.pathExtension isEqualToString:@"appex"]) {
		NSString *pluginDirectory = executablePath.stringByDeletingLastPathComponent;
		NSDictionary *pluginInfo = [NSDictionary dictionaryWithContentsOfFile:[pluginDirectory stringByAppendingPathComponent:@"Info.plist"]];
		NSString *pluginIdentifier = pluginInfo[@"CFBundleIdentifier"];
		[specifier setProperty:pluginIdentifier forKey:@"pluginIdentifier"];
	}
	else {
		[specifier setProperty:executablePath forKey:@"executablePath"];
	}

	[specifier setProperty:@YES forKey:@"enabled"];
	return specifier;
}

- (id)previewStringForSpecifier:(PSSpecifier *)specifier
{
	NSString *appIdentifier = [specifier propertyForKey:@"applicationIdentifier"];
	NSString *pluginIdentifier = [specifier propertyForKey:@"pluginIdentifier"];
	NSString *executablePath = [specifier propertyForKey:@"executablePath"];

	NSString *identifierToUse = appIdentifier ? appIdentifier : pluginIdentifier;

	if (identifierToUse) {
		NSDictionary *appSettings = [preferences objectForKey:kChoicyPrefsKeyAppSettings];
		NSDictionary *settingsForApplication = [appSettings objectForKey:identifierToUse];
		return [CHPApplicationListSubcontrollerController previewStringForProcessPreferences:settingsForApplication];
	}
	else {
		NSDictionary *daemonSettings = [preferences objectForKey:kChoicyPrefsKeyDaemonSettings];
		NSDictionary *settingsForDaemon = [daemonSettings objectForKey:executablePath.lastPathComponent];
		return [CHPApplicationListSubcontrollerController previewStringForProcessPreferences:settingsForDaemon];
	}
}

- (void)loadAdditionalExecutables
{
	NSArray *additionalExecutables = preferences[kChoicyPrefsKeyAdditionalExecutables];
	if (additionalExecutables) {
		_additionalExecutables = additionalExecutables.mutableCopy;
	}
	else {
		_additionalExecutables = [NSMutableArray new];
	}
}

- (void)saveAdditionalExecutables
{
	NSMutableDictionary *mutablePrefs = preferencesForWriting();
	mutablePrefs[kChoicyPrefsKeyAdditionalExecutables] = _additionalExecutables.copy;
	writePreferences(mutablePrefs);
}

- (void)addButtonPressed
{
	UIAlertController *executableAlert = [UIAlertController alertControllerWithTitle:localize(@"SELECT_EXECUTABLE") message:localize(@"SELECT_EXECUTABLE_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];

	[executableAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = localize(@"PATH");
		if (@available(iOS 13, *)) {
			textField.textColor = [UIColor labelColor];
		}
		else {
			textField.textColor = [UIColor blackColor];
		}
		textField.keyboardType = UIKeyboardTypeDefault;
		textField.clearButtonMode = UITextFieldViewModeWhileEditing;
		textField.borderStyle = UITextBorderStyleNone;
	}];

	UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:localize(@"CANCEL") style:UIAlertActionStyleCancel handler:nil];
	[executableAlert addAction:cancelAction];

	UIAlertAction *addAction = [UIAlertAction actionWithTitle:localize(@"ADD") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		UITextField *pathField = executableAlert.textFields[0];
		[self addExecutableAtPath:pathField.text];
	}];
	[executableAlert addAction:addAction];

	[self presentViewController:executableAlert animated:YES completion:nil];
}

- (void)showErrorMessage:(NSString *)message
{
	UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:localize(@"ERROR") message:message preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction *closeAction = [UIAlertAction actionWithTitle:localize(@"CLOSE") style:UIAlertActionStyleDefault handler:nil];
	[errorAlert addAction:closeAction];

	[self presentViewController:errorAlert animated:YES completion:nil];
}

- (void)addExecutableAtPath:(NSString *)executablePath
{
	if ([_additionalExecutables containsObject:executablePath]) return;

	if (![[NSFileManager defaultManager] fileExistsAtPath:executablePath]) {
		[self showErrorMessage:localize(@"ERROR_FILE_NOT_FOUND")];
		return;
	}

	if (!isFileAtPathMacho(executablePath)) {
		[self showErrorMessage:localize(@"ERROR_FILE_NO_EXECUTABLE")];
		return;
	}

	if (![[CHPTweakList sharedInstance] oneOrMoreTweaksInjectIntoExecutableAtPath:executablePath]) {
		[self showErrorMessage:localize(@"ERROR_NO_TWEAKS_INJECT")];
		return;
	}

	[_additionalExecutables addObject:executablePath];
	[self saveAdditionalExecutables];

	PSSpecifier *newSpecifier = [self newSpecifierForExecutable:executablePath];
	[self insertSpecifier:newSpecifier atEndOfGroup:0 animated:YES];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleDelete;
}

- (BOOL)performDeletionActionForSpecifier:(PSSpecifier *)specifier
{
	BOOL orig = [super performDeletionActionForSpecifier:specifier];

	NSString *executablePath = [specifier propertyForKey:@"executablePath"];
	[_additionalExecutables removeObject:executablePath];
	[self saveAdditionalExecutables];

	return orig;
}

- (NSMutableArray *)specifiers
{
	if (!_specifiers) {
		_specifiers = [NSMutableArray new];

		[self loadAdditionalExecutables];

		PSSpecifier *groupSpecifier = [PSSpecifier emptyGroupSpecifier];
		[groupSpecifier setProperty:localize(@"ADDITIONAL_EXECUTABLES_FOOTER") forKey:@"footerText"];

		[_specifiers addObject:groupSpecifier];

		[_additionalExecutables enumerateObjectsUsingBlock:^(NSString *executablePath, NSUInteger idx, BOOL *stop) {
			[_specifiers addObject:[self newSpecifierForExecutable:executablePath]];
		}];
	}

	return _specifiers;
}

@end