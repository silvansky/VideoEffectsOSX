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
@property (nonatomic, strong) AVAssetWriter *outputAssetWriter;
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

+ (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image
{
	CGSize frameSize = CGSizeMake(CGImageGetWidth(image),
								  CGImageGetHeight(image));
	NSDictionary *options =
	[NSDictionary dictionaryWithObjectsAndKeys:
	 [NSNumber numberWithBool:YES],
	 kCVPixelBufferCGImageCompatibilityKey,
	 [NSNumber numberWithBool:YES],
	 kCVPixelBufferCGBitmapContextCompatibilityKey,
	 nil];
	CVPixelBufferRef pxbuffer = NULL;

	CVReturn status =
	CVPixelBufferCreate(
						kCFAllocatorDefault, frameSize.width, frameSize.height,
						kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)options,
						&pxbuffer);
	NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);

	CVPixelBufferLockBaseAddress(pxbuffer, 0);
	void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);

	CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(
												 pxdata, frameSize.width, frameSize.height,
												 8, CVPixelBufferGetBytesPerRow(pxbuffer),
												 rgbColorSpace,
												 (CGBitmapInfo)kCGBitmapByteOrder32Little |
												 kCGImageAlphaPremultipliedFirst);

	CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
										   CGImageGetHeight(image)), image);
	CGColorSpaceRelease(rgbColorSpace);
	CGContextRelease(context);

	CVPixelBufferUnlockBaseAddress(pxbuffer, 0);

	return pxbuffer;
}

+ (CMSampleBufferRef)sampleBufferFromCGImage:(CGImageRef)image
{
	CVPixelBufferRef pixelBuffer = [self pixelBufferFromCGImage:image];
	CMSampleBufferRef newSampleBuffer = NULL;
	CMSampleTimingInfo timimgInfo = kCMTimingInfoInvalid;
	CMVideoFormatDescriptionRef videoInfo = NULL;
	CMVideoFormatDescriptionCreateForImageBuffer(
												 NULL, pixelBuffer, &videoInfo);
	CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
									   pixelBuffer,
									   true,
									   NULL,
									   NULL,
									   videoInfo,
									   &timimgInfo,
									   &newSampleBuffer);

	return newSampleBuffer;
}

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

					NSError *error = nil;
					NSString *outFile = [NSString stringWithFormat:@"/Users/valentine/Pictures/SSM/rolling-shutter-%@.mov", @([[NSDate date] timeIntervalSince1970])];
					self.outputAssetWriter = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:outFile] fileType:AVFileTypeQuickTimeMovie error:&error];
					if (error != nil)
					{
						NSLog(@"Failed to create asset writer: %@", error);
						return;
					}

					NSDictionary *settings = @{ AVVideoCodecKey : AVVideoCodecH264, AVVideoWidthKey : @(self.currentImageSize.width), AVVideoHeightKey : @(self.currentImageSize.height) };
					AVAssetWriterInput *output = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
					output.expectsMediaDataInRealTime = YES;
					AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:output sourcePixelBufferAttributes:nil];
					[self.outputAssetWriter addInput:output];

					BOOL ok = [self.outputAssetWriter startWriting];

					[self.outputAssetWriter startSessionAtSourceTime:kCMTimeZero];

					if (!ok)
					{
						NSLog(@"Failed to start writing: %@", self.outputAssetWriter.error);
						return;
					}

					/* read off the samples */
					CMSampleBufferRef buffer;
					while ([assetReader status] == AVAssetReaderStatusReading)
					{
						@autoreleasepool
						{
							buffer = [assetReaderOutput copyNextSampleBuffer];

							NSImage *currentImage = [NSImage imageWithSampleBuffer:buffer];
							NSImage *partialImage = nil;//[self partialImageWithSource:currentImage];

							if (currentImage != nil)
							{
								CVPixelBufferRef outBuffer = [RollingShutterViewController pixelBufferFromCGImage:[currentImage CGImageForProposedRect:nil context:nil hints:nil]];
								[adaptor appendPixelBuffer:outBuffer withPresentationTime:CMTimeMake(i, 30)]; // 30 FPS
							}

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
					[self.outputAssetWriter finishWritingWithCompletionHandler:^{
						NSLog(@"Writing finished!");
					}];
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
