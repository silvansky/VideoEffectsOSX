//
//  StartViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "StartViewController.h"

@interface StartViewController ()

@property (weak) IBOutlet NSButton *slitScanButton;
@property (weak) IBOutlet NSButton *rollingShutterButton;
@property (weak) IBOutlet NSTextField *titleLabel;

@end

@implementation StartViewController

- (void)viewDidLoad
{
	NSString *path = [@"~/Pictures/Slit-Scan Maker/" stringByExpandingTildeInPath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path])
	{
		[[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	}

	@weakify(self);
	self.slitScanButton.rac_command = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id __unused input) {
		@strongify(self);
		[self.view.window close];
		[self performSegueWithIdentifier:@"slit-scan-segue" sender:self];
		return [RACSignal empty];
	}];

	self.rollingShutterButton.rac_command = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(id __unused input) {
		@strongify(self);
		[self.view.window close];
		[self performSegueWithIdentifier:@"rolling-shutter-segue" sender:self];
		return [RACSignal empty];
	}];

}

@end
