//
//  SlitScanViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "SlitScanViewController.h"
#import "SourceVideoView.h"

@import AVFoundation;
@import AVKit;
@import CoreGraphics;

@interface SlitScanViewController ()

@property (weak) IBOutlet SourceVideoView *sourceVideoView;
@property (weak) IBOutlet NSImageView *resultingImageView;

@property (weak) IBOutlet NSBox *slitModeBox;
@property (weak) IBOutlet NSBox *slitMoveDirectionBox;
@property (weak) IBOutlet NSBox *slitTypeBox;

@property (nonatomic, strong) AVURLAsset *currentAsset;

- (void)processAsset:(AVURLAsset *)asset;

@end

@implementation SlitScanViewController

- (void)viewDidLoad
{
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
		[self.sourceVideoView updatePreview:[[NSImage alloc] initWithCGImage:cgImage size:size]];
		[self processAsset:asset];
	}];
}

#pragma mark - Private

- (NSImage *)imageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
	// From Apple sample
	// Get a CMSampleBuffer's Core Video image buffer for the media data
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);

	// Lock the base address of the pixel buffer
	CVPixelBufferLockBaseAddress(imageBuffer, 0);

	// Get the number of bytes per row for the pixel buffer
	void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);

	// Get the number of bytes per row for the pixel buffer
	size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);

	// Get the pixel buffer width and height
	size_t width = CVPixelBufferGetWidth(imageBuffer);
	size_t height = CVPixelBufferGetHeight(imageBuffer);

	// Create a device-dependent RGB color space
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	// Create a bitmap graphics context with the sample buffer data
	CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

	if (!context)
	{
		return nil;
	}

	// Create a Quartz image from the pixel data in the bitmap graphics context
	CGImageRef quartzImage = CGBitmapContextCreateImage(context);

	// Unlock the pixel buffer
	CVPixelBufferUnlockBaseAddress(imageBuffer,0);

	// Free up the context and color space
	CGContextRelease(context);
	CGColorSpaceRelease(colorSpace);

	// Create an image object from the Quartz image
	NSImage *image = [[NSImage alloc] initWithCGImage:quartzImage size:NSMakeSize(width, height)];

	// Release the Quartz image
	CGImageRelease(quartzImage);

	return (image);
}

- (void)processAsset:(AVURLAsset *)asset
{
	self.currentAsset = asset;
	@weakify(self);
	dispatch_async(dispatch_queue_create("prc", DISPATCH_QUEUE_SERIAL), ^{
		@strongify(self);
		NSError *error = nil;
		AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:&error];
		AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo][0];
		NSDictionary *dict = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };

		AVAssetReaderTrackOutput *assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:dict];

		NSInteger i = 0;
		if ([assetReader canAddOutput:assetReaderOutput])
		{
			[assetReader addOutput:assetReaderOutput];
			if ([assetReader startReading])
			{
				self.sourceVideoView.locked = YES;

				/* read off the samples */
				CMSampleBufferRef buffer;
				while ([assetReader status] == AVAssetReaderStatusReading)
				{
					buffer = [assetReaderOutput copyNextSampleBuffer];
					NSImage *currentImage = [self imageFromSampleBuffer:buffer];
					if (currentImage)
					{
						[self.sourceVideoView updatePreview:currentImage];
					}
					i++;
//					NSLog(@"decoding frame #%ld done. %@", i, currentImage);
				}

				self.sourceVideoView.locked = NO;
			}
			else
			{
				NSLog(@"could not start reading asset.");
				NSLog(@"reader status: %ld", [assetReader status]);
			}
		}
	});
}

@end
