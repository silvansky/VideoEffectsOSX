//
//  RollingShutterViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "RollingShutterViewController.h"

#import "SourceVideoView.h"

#import "NSImage+SampleBuffer.h"

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
	self.currentAsset = asset;
	@weakify(self);
	dispatch_async(dispatch_queue_create("processAsset", DISPATCH_QUEUE_SERIAL), ^{
		@autoreleasepool
		{
			@strongify(self);
			NSError *error = nil;
			AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:&error];
			AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo][0];
			NSDictionary *dict = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };

			AVAssetReaderTrackOutput *assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:dict];

			NSInteger i = 0;
//			self.currentLine = 0;
			NSDate *startDate = [NSDate date];
			if ([assetReader canAddOutput:assetReaderOutput])
			{
				[assetReader addOutput:assetReaderOutput];
				if ([assetReader startReading])
				{
					dispatch_sync(dispatch_get_main_queue(), ^{
						self.sourceVideoView.locked = YES;
						[self.progressIndicator startAnimation:nil];
					});

					/* read off the samples */
					CMSampleBufferRef buffer;
					while ([assetReader status] == AVAssetReaderStatusReading)
					{
						@autoreleasepool
						{
							buffer = [assetReaderOutput copyNextSampleBuffer];

							NSImage *currentImage = [NSImage imageWithSampleBuffer:buffer];
							NSImage *partialImage = nil;//[self partialImageWithSource:currentImage];

							if (partialImage != nil)
							{
								self.internalPartialImg = partialImage;
							}

							if (partialImage && (i % 100 == 0))
							{
								dispatch_async(dispatch_get_main_queue(), ^{
									@autoreleasepool {
										[self.sourceVideoView updatePreview:currentImage];
										self.resultingImageView.image = partialImage;
									}
								});
							}

							i++;
							//self.currentLine++;

//							BOOL verticalSlit = ((!self.movingLine && self.verticalSlit) || (self.movingLine && (self.slitDirection == LeftToRight || self.slitDirection == RightToLeft)));
//							CGFloat maxLines = (verticalSlit ? self.currentImageSize.width : self.currentImageSize.height);

//							if (self.currentLine > maxLines)
//							{
//								self.currentLine = 0;
//								[self saveCurrentImage];
//								self.internalPartialImg = nil;
//							}

							if (buffer != NULL)
							{
								CFRelease(buffer);
							}
							if (self.stopAfterNextFrame)
							{
								self.stopAfterNextFrame = NO;
								break;
							}
						} // pool
					}

					NSDate *endDate = [NSDate date];
					NSTimeInterval duration = [endDate timeIntervalSinceDate:startDate];
//					[self saveCurrentImage];
					self.internalPartialImg = nil;
					NSLog(@"Processed %@ frames in %@ seconds, FPS: %@", @(i), @(duration), @(i/duration));

					dispatch_async(dispatch_get_main_queue(), ^{
						@autoreleasepool {
							self.sourceVideoView.locked = NO;
							[self.progressIndicator stopAnimation:nil];
							self.processing = NO;
							self.startButton.title = @"Start";
							[self.sourceVideoView updatePreview:self.originalPreviewImage];
//							[self updateBoxes];
						}
					});
				}
				else
				{
					NSLog(@"could not start reading asset.");
					NSLog(@"reader status: %ld", [assetReader status]);
				}
			}
		}
	});
}


@end
