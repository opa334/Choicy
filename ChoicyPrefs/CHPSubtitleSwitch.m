#import "CHPSubtitleSwitch.h"

#import <Preferences/PSSpecifier.h>

@implementation CHPSubtitleSwitch

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString*)reuseIdentifier specifier:(PSSpecifier*)specifier
{
	self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier specifier:specifier];
	if(self)
	{
		self.detailTextLabel.text = [specifier propertyForKey:@"subtitle"];
	}
	return self;
}

@end