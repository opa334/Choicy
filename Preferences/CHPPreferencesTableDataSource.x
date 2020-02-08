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

#import "../Shared.h"
#import "CHPApplicationPreferenceViewController.h"

@interface CHPPreferencesTableDataSource : NSObject
@end

%subclass CHPPreferencesTableDataSource : ALPreferencesTableDataSource
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return localize(%orig);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell* cell = %orig;
	ALApplicationTableDataSourceSection* section = [[self valueForKey:@"_sectionDescriptors"] objectAtIndex:indexPath.section];
	NSString* displayIdentifier = [section displayIdentifierForRow:indexPath.row];
	if([displayIdentifier isEqualToString:@"com.apple.CarPlaySettings"] && ![cell.textLabel.text hasSuffix:@"(CarPlay)"])
	{
		cell.textLabel.text = [cell.textLabel.text stringByAppendingString:@" (CarPlay)"];
	}
	return cell;
}
%end

void initCHPPreferencesTableDataSource()
{
	%config(generator=internal)
	%init;
}