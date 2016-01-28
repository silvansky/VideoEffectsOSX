//
//  RollingShutterViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "RollingShutterViewController.h"

#import "SourceVideoView.h"

@import AVFoundation;

@interface RollingShutterViewController ()

@property (weak) IBOutlet SourceVideoView *sourceVideoView;
@property (weak) IBOutlet NSImageView *resultingImageView;
@property (weak) IBOutlet NSButton *startButton;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

@property (nonatomic, strong) AVURLAsset *currentAsset;
@property (nonatomic, assign) NSSize currentImageSize;

@property (atomic, strong) NSImage *internalPartialImg;
@property (atomic, strong) NSImage *originalPreviewImage;

@property (nonatomic, assign) BOOL processing;
@property (nonatomic, assign) BOOL stopAfterNextFrame;

- (void)processAsset:(AVURLAsset *)asset;

@end

@implementation RollingShutterViewController

- (void)viewDidLoad
{
	self.sourceVideoView.showSlit = NO;
	self.sourceVideoView.verticalSlit = YES;
	self.sourceVideoView.slitPosition = 50;
	[self setupSignals];
}

- (void)setupSignals
{
	@weakify(self);

	[self.sourceVideoView.draggedFilesSignal subscribeNext:^(NSString *file) {
		@strongify(self);
		NSLog(@"Got video file: %@", file);

		AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:file] options:nil];
		AVAssetImageGenerator *imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
		[imageGenerator setAppliesPreferredTrackTransform:YES];

		CGImageRef cgImage = [imageGenerator copyCGImageAtTime:CMTimeMake(0, 1) actualTime:nil error:nil];

		NSSize size;
		size.width = CGImageGetWidth(cgImage);
		size.height = CGImageGetHeight(cgImage);

		self.currentImageSize = size;

		self.originalPreviewImage = [[NSImage alloc] initWithCGImage:cgImage size:size];
		[self.sourceVideoView updatePreview:self.originalPreviewImage];

		self.currentAsset = asset;
		CGImageRelease(cgImage);
	}];

	RACCommand *cmd = [[RACCommand alloc] initWithEnabled:[RACObserve(self, currentAsset) map:^id(id value) {
		return @(value != nil);
	}] signalBlock:^RACSignal *(id input) {
		@strongify(self);
		if (!self.processing)
		{
			self.processing = YES;
			self.startButton.title = @"Stop";
			[self processAsset:self.currentAsset];
		}
		else
		{
			self.stopAfterNextFrame = YES;
		}
		return [RACSignal empty];
	}];
	self.startButton.rac_command = cmd;
}

#pragma mark - Private

- (void)processAsset:(AVURLAsset *)asset
{

}

@end
