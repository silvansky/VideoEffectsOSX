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

typedef enum : NSUInteger {
	LeftToRight,
	RightToLeft,
	TopToBottom,
	BottomToTop
} ShutterDirection;

@interface RollingShutterViewController ()

@property (weak) IBOutlet SourceVideoView *sourceVideoView;
@property (weak) IBOutlet NSImageView *resultingImageView;
@property (weak) IBOutlet NSButton *startButton;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

@property (weak) IBOutlet NSBox *shutterDirectionBox;
@property (weak) IBOutlet NSBox *outputFPSBox;

@property (weak) IBOutlet NSButton *shutterDirectionLtoRRadioButton;
@property (weak) IBOutlet NSButton *shutterDirectionRtoLRadioButton;
@property (weak) IBOutlet NSButton *shutterDirectionTtoBRadioButton;
@property (weak) IBOutlet NSButton *shutterDirectionBtoTRadioButton;

@property (weak) IBOutlet NSButton *outputFPS30RadioButton;
@property (weak) IBOutlet NSButton *outputFPS60RadioButton;
@property (weak) IBOutlet NSButton *outputFPS120RadioButton;

@property (weak) IBOutlet NSButton *skipFirstFramesCheckButton;

@property (atomic, strong) AVURLAsset *currentAsset;
@property (atomic, strong) AVAssetReader *assetReader;

@property (atomic, strong) AVAssetWriter *outputAssetWriter;
@property (atomic, strong) AVAssetWriterInput *outputWriterInput;
@property (atomic, strong) AVAssetReaderTrackOutput *assetReaderOutput;
@property (atomic, strong) AVAssetWriterInputPixelBufferAdaptor *writerAdaptor;

@property (atomic, strong) NSDate *startDate;

@property (atomic, assign) NSSize currentImageSize;

@property (atomic, strong) NSImage *internalPartialImg;
@property (atomic, strong) NSImage *originalPreviewImage;
@property (atomic, strong) NSMutableArray *imagesQueue;
@property (atomic, assign) NSInteger imagesQueueLength;
@property (atomic, assign) NSInteger currentFrameIndex;
@property (atomic, assign) BOOL writingQueueRequested;

@property (nonatomic, assign) int32_t outputFPS;
@property (nonatomic, assign) ShutterDirection shutterDirection;
@property (nonatomic, assign, readonly) BOOL verticalShutter;

@property (nonatomic, strong) NSArray<NSControl *> *controls;

@property (nonatomic, assign) BOOL processing;
@property (nonatomic, assign) BOOL skipFirstFrames;
@property (nonatomic, assign) BOOL stopAfterNextFrame;

- (void)processAsset:(AVURLAsset *)asset;
- (void)setControlsEnabled:(BOOL)enabled;
- (void)cleanUp;

@end

@implementation RollingShutterViewController

- (BOOL)verticalShutter
{
	return (self.shutterDirection == LeftToRight) || (self.shutterDirection == RightToLeft);
}

- (IBAction)shutterDirectionChanged:(id)sender
{
	ShutterDirection d = LeftToRight;

	if (sender == self.shutterDirectionRtoLRadioButton)
	{
		d = RightToLeft;
	}
	else if (sender == self.shutterDirectionTtoBRadioButton)
	{
		d = TopToBottom;
	}
	else if (sender == self.shutterDirectionBtoTRadioButton)
	{
		d = BottomToTop;
	}

	self.shutterDirection = d;
}

- (IBAction)outputFPSChanged:(id)sender
{
	int32_t fps = 30;

	if (sender == self.outputFPS60RadioButton)
	{
		fps = 60;
	}
	else if (sender == self.outputFPS120RadioButton)
	{
		fps = 120;
	}

	self.outputFPS = fps;
}

- (void)viewDidLoad
{
	self.outputFPS = 30;
	self.shutterDirection = BottomToTop;

	self.controls = @[
					  self.shutterDirectionBtoTRadioButton,
					  self.shutterDirectionLtoRRadioButton,
					  self.shutterDirectionRtoLRadioButton,
					  self.shutterDirectionTtoBRadioButton,
					  self.outputFPS120RadioButton,
					  self.outputFPS30RadioButton,
					  self.outputFPS60RadioButton,
					  self.skipFirstFramesCheckButton
					  ];

	self.imagesQueue = [NSMutableArray array];

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

		NSImage *firstFrame = [[NSImage alloc] initWithCGImage:cgImage size:size];
		self.originalPreviewImage = firstFrame;
		self.internalPartialImg = firstFrame;
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
			[self setControlsEnabled:NO];
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

- (NSImage *)partialImageWithSource:(NSImage *)source
{
	if (source == nil)
	{
		return nil;
	}

	[self.imagesQueue removeObjectAtIndex:0];
	CGImageRef sourceQuartzImage = [source CGImageForProposedRect:nil context:nil hints:nil];
	[self.imagesQueue addObject:(__bridge id)sourceQuartzImage];

	size_t width = CGImageGetWidth(sourceQuartzImage);
	size_t height = CGImageGetHeight(sourceQuartzImage);
	CGSize size = CGSizeMake((CGFloat)width, (CGFloat)height);
	CGRect rect;
	rect.origin = CGPointMake(0.f, 0.f);
	rect.size = size;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);

	if (!ctx)
	{
		NSLog(@"Hey, no context in partialImageWithSource! Debug me plz. =/");
	}

	for (NSInteger lineIndex = 0; lineIndex < self.imagesQueueLength; lineIndex++)
	{
		sourceQuartzImage = (__bridge CGImageRef)self.imagesQueue[lineIndex];

		CGRect lineRect;// = CGRectMake(0.f, (CGFloat)lineIndex, (CGFloat)width, 1.f);
		CGRect lineDrawRect;// = CGRectMake(0.f, (CGFloat)(height - lineIndex), (CGFloat)width, 1.f);

		switch (self.shutterDirection)
		{
			case RightToLeft:
				lineRect = CGRectMake((CGFloat)lineIndex, 0.f, 1.f, (CGFloat)height);
				lineDrawRect = CGRectMake((CGFloat)lineIndex, 0.f, 1.f, (CGFloat)height);
				break;
			case LeftToRight:
				lineRect = CGRectMake((CGFloat)(width - lineIndex), 0.f, 1.f, (CGFloat)height);
				lineDrawRect = CGRectMake((CGFloat)(width - lineIndex), 0.f, 1.f, (CGFloat)height);
				break;
			case BottomToTop:
				lineRect = CGRectMake(0.f, (CGFloat)lineIndex, (CGFloat)width, 1.f);
				lineDrawRect = CGRectMake(0.f, (CGFloat)(height - lineIndex), (CGFloat)width, 1.f);
				break;
			case TopToBottom:
				lineRect = CGRectMake(0.f, (CGFloat)(height - lineIndex), (CGFloat)width, 1.f);
				lineDrawRect = CGRectMake(0.f, (CGFloat)lineIndex, (CGFloat)width, 1.f);
				break;
		}

		CGImageRef line = CGImageCreateWithImageInRect(sourceQuartzImage, lineRect);

		CGContextDrawImage(ctx, lineDrawRect, line);

		CGImageRelease(line);
	}

	NSImage *image = nil;

	CGImageRef quartzImage = CGBitmapContextCreateImage(ctx);

	CGContextRelease(ctx);
	CGColorSpaceRelease(colorSpace);

	image = [[NSImage alloc] initWithCGImage:quartzImage size:size];

	CGImageRelease(quartzImage);

	return image;
}

- (CVPixelBufferRef)copyNextBuffer
{
	if ([self.assetReader status] == AVAssetReaderStatusReading)
	{
		CMSampleBufferRef buffer;
		@autoreleasepool
		{
			buffer = [self.assetReaderOutput copyNextSampleBuffer];
			CVPixelBufferRef outBuffer = NULL;

			NSImage *currentImage = [NSImage imageWithSampleBuffer:buffer];
			NSImage *partialImage = [self partialImageWithSource:currentImage];

			if (partialImage != nil)
			{
				self.internalPartialImg = partialImage;

				outBuffer = [partialImage pixelBuffer];
			}

			if (currentImage && (self.currentFrameIndex % 5 == 0))
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					@autoreleasepool {
						[self.sourceVideoView updatePreview:currentImage];
						self.resultingImageView.image = partialImage;
					}
				});
			}

			self.currentFrameIndex++;

			if (buffer != NULL)
			{
				CFRelease(buffer);
			}

			if (self.stopAfterNextFrame)
			{
				[self.assetReader cancelReading];
				self.stopAfterNextFrame = NO;
			}

			return outBuffer;
		} // pool
	}
	else
	{
		return NULL;
	}
}

- (void)processAsset:(AVURLAsset *)asset
{
	self.currentFrameIndex = 0;
	self.currentAsset = asset;

	self.imagesQueueLength = (NSInteger)(self.verticalShutter ? self.currentImageSize.width : self.currentImageSize.height);
	self.imagesQueue = [NSMutableArray arrayWithCapacity:self.imagesQueueLength];

	@weakify(self);
	dispatch_async(dispatch_queue_create("processAsset", DISPATCH_QUEUE_SERIAL), ^{
		@autoreleasepool
		{
			@strongify(self);

			CGImageRef originalQuartzImage = [self.originalPreviewImage CGImageForProposedRect:nil context:nil hints:nil];

			[@(self.imagesQueueLength) times:^{
				[self.imagesQueue addObject:(__bridge id)originalQuartzImage];
			}];

			NSError *error = nil;
			self.assetReader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:&error];
			AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo][0];
			NSDictionary *dict = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };

			self.assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:dict];

			self.startDate = [NSDate date];
			dispatch_queue_t dataQueue = dispatch_queue_create("add-data-to-output", DISPATCH_QUEUE_SERIAL);
			if ([self.assetReader canAddOutput:self.assetReaderOutput])
			{
				[self.assetReader addOutput:self.assetReaderOutput];
				if ([self.assetReader startReading])
				{
					dispatch_sync(dispatch_get_main_queue(), ^{
						self.sourceVideoView.locked = YES;
						[self.progressIndicator startAnimation:nil];
					});

					NSError *error = nil;
					NSString *path = [@"~/Pictures/Slit-Scan Maker/" stringByExpandingTildeInPath];
					NSString *outFile = [NSString stringWithFormat:@"%@/rolling-shutter-%@.mov", path, @([[NSDate date] timeIntervalSince1970])];
					self.outputAssetWriter = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:outFile] fileType:AVFileTypeQuickTimeMovie error:&error];
					if (error != nil)
					{
						NSLog(@"Failed to create asset writer: %@", error);
						return;
					}

					NSDictionary *settings = @{ AVVideoCodecKey : AVVideoCodecH264, AVVideoWidthKey : @(self.currentImageSize.width), AVVideoHeightKey : @(self.currentImageSize.height) };
					self.outputWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
					self.outputWriterInput.expectsMediaDataInRealTime = YES;
					self.writerAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.outputWriterInput sourcePixelBufferAttributes:nil];
					[self.outputAssetWriter addInput:self.outputWriterInput];

					BOOL ok = [self.outputAssetWriter startWriting];

					[self.outputAssetWriter startSessionAtSourceTime:kCMTimeZero];

					if (!ok)
					{
						NSLog(@"Failed to start writing: %@", self.outputAssetWriter.error);
						return;
					}

					dispatch_block_t writeBlock = ^{
						while (self.outputWriterInput.readyForMoreMediaData)
						{
							CVPixelBufferRef outBuffer = [self copyNextBuffer];
							if (outBuffer != NULL)
							{
								[self.writerAdaptor appendPixelBuffer:outBuffer withPresentationTime:CMTimeMake(self.currentFrameIndex, self.outputFPS)];
							}
							else
							{
								[self.outputWriterInput markAsFinished];
								[self cleanUp];
								break;
							}
							CVPixelBufferRelease(outBuffer);
						}
					};

					[self.outputWriterInput requestMediaDataWhenReadyOnQueue:dataQueue usingBlock:writeBlock];
				}
				else
				{
					NSLog(@"could not start reading asset.");
					NSLog(@"reader status: %ld", [self.assetReader status]);
				}
			}
		}
	});
}

- (void)setControlsEnabled:(BOOL)enabled
{
	[self.controls each:^(NSControl *c) {
		c.enabled = enabled;
	}];
}

- (void)cleanUp
{
	[self.imagesQueue removeAllObjects];

	NSDate *endDate = [NSDate date];
	NSTimeInterval duration = [endDate timeIntervalSinceDate:self.startDate];

	self.internalPartialImg = nil;

	[self.outputAssetWriter finishWritingWithCompletionHandler:^{
		NSLog(@"Writing finished!");
	}];

	NSLog(@"Processed %@ frames in %@ seconds, FPS: %@", @(self.currentFrameIndex), @(duration), @(self.currentFrameIndex / duration));

	dispatch_async(dispatch_get_main_queue(), ^{
		@autoreleasepool {
			self.sourceVideoView.locked = NO;
			[self.progressIndicator stopAnimation:nil];
			self.processing = NO;
			self.startButton.title = @"Start";
			[self.sourceVideoView updatePreview:self.originalPreviewImage];
			[self setControlsEnabled:YES];
		}
	});
}

@end
