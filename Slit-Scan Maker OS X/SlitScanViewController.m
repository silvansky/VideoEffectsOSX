//
//  SlitScanViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "SlitScanViewController.h"
#import "SourceVideoView.h"

@interface SlitScanViewController ()

@property (weak) IBOutlet SourceVideoView *sourceVideoView;
@property (weak) IBOutlet NSImageView *resultingImageView;

@property (weak) IBOutlet NSBox *slitModeBox;
@property (weak) IBOutlet NSBox *slitMoveDirectionBox;
@property (weak) IBOutlet NSBox *slitTypeBox;

@end

@implementation SlitScanViewController

- (void)viewDidLoad
{
	[self setupSignals];
}

- (void)setupSignals
{
	[self.sourceVideoView.draggedFilesSignal subscribeNext:^(NSString *file) {
		NSLog(@"Got video file: %@", file);
	}];
}

@end
