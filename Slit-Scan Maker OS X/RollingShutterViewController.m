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

@property (nonatomic, strong) AVURLAsset *currentAsset;
@property (nonatomic, strong) AVAssetWriter *outputAssetWriter;
@property (nonatomic, assign) NSSize currentImageSize;

@property (atomic, strong) NSImage *internalPartialImg;
@property (atomic, strong) NSImage *originalPreviewImage;
@property (atomic, strong) NSMutableArray<NSImage *> *imagesQueue;
@property (atomic, assign) NSInteger imagesQueueLength;
@property (nonatomic, assign) NSInteger currentLine;
@property (nonatomic, assign) int32_t outputFPS;
@property (nonatomic, assign) ShutterDirection shutterDirection;

@property (nonatomic, strong) NSArray<NSControl *> *controls;

@property (nonatomic, assign) BOOL processing;
@property (nonatomic, assign) BOOL stopAfterNextFrame;

- (void)processAsset:(AVURLAsset *)asset;
- (void)setControlsEnabled:(BOOL)enabled;

@end

@implementation RollingShutterViewController

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

	self.controls = @[self.shutterDirectionBtoTRadioButton, self.shutterDirectionLtoRRadioButton, self.shutterDirectionRtoLRadioButton, self.shutterDirectionTtoBRadioButton, self.outputFPS120RadioButton, self.outputFPS30RadioButton, self.outputFPS60RadioButton];

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

		self.imagesQueueLength = (NSInteger)size.height;

		self.currentImageSize = size;

		NSImage *firstFrame = [[NSImage alloc] initWithCGImage:cgImage size:size];
		self.originalPreviewImage = firstFrame;
		self.internalPartialImg = firstFrame;
		[self.sourceVideoView updatePreview:self.originalPreviewImage];

		self.imagesQueue = [NSMutableArray arrayWithCapacity:self.imagesQueueLength];

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
	[self.imagesQueue addObject:source];

	CGImageRef sourceQuartzImage = [source CGImageForProposedRect:nil context:nil hints:nil];
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
		NSImage *currentFrame = self.imagesQueue[lineIndex];
		sourceQuartzImage = [currentFrame CGImageForProposedRect:nil context:nil hints:nil];

		CGRect lineRect = CGRectMake(0.f, (CGFloat)lineIndex, (CGFloat)width, 1.f);

		CGRect lineDrawRect = CGRectMake(0.f, (CGFloat)(height - lineIndex), (CGFloat)width, 1.f);

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

- (void)processAsset:(AVURLAsset *)asset
{
	self.currentAsset = asset;
	@weakify(self);
	dispatch_async(dispatch_queue_create("processAsset", DISPATCH_QUEUE_SERIAL), ^{
		@autoreleasepool
		{
			@strongify(self);

			[@(self.imagesQueueLength) times:^{
				[self.imagesQueue addObject:self.originalPreviewImage];
			}];

			NSError *error = nil;
			AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:&error];
			AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo][0];
			NSDictionary *dict = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };

			AVAssetReaderTrackOutput *assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:dict];

			NSInteger i = 0;
//			self.currentLine = 0;
			NSDate *startDate = [NSDate date];
			dispatch_queue_t dataQueue = dispatch_queue_create("add-data-to-output", DISPATCH_QUEUE_SERIAL);
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
					NSString *path = [@"~/Pictures/Slit-Scan Maker/" stringByExpandingTildeInPath];
					NSString *outFile = [NSString stringWithFormat:@"%@/rolling-shutter-%@.mov", path, @([[NSDate date] timeIntervalSince1970])];
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
							NSImage *partialImage = [self partialImageWithSource:currentImage];

							if (partialImage != nil)
							{
								self.internalPartialImg = partialImage;

								CVPixelBufferRef outBuffer = [partialImage pixelBuffer];

								dispatch_block_t writeBlock = ^{
									[adaptor appendPixelBuffer:outBuffer withPresentationTime:CMTimeMake(i, self.outputFPS)];
									CVPixelBufferRelease(outBuffer);
								};

								// TODO: make buffer of buffers
								if (!output.readyForMoreMediaData)
								{
									[output requestMediaDataWhenReadyOnQueue:dataQueue usingBlock:writeBlock];
									NSLog(@"Not ready! Help! %@", self.outputAssetWriter.error);
								}
								else
								{
									dispatch_async(dataQueue, writeBlock);
								}
							}

							if (currentImage && (i % 5 == 0))
							{
								dispatch_async(dispatch_get_main_queue(), ^{
									@autoreleasepool {
										[self.sourceVideoView updatePreview:currentImage];
										self.resultingImageView.image = partialImage;
									}
								});
							}

							i++;
							self.currentLine++;

//							BOOL verticalSlit = ((!self.movingLine && self.verticalSlit) || (self.movingLine && (self.slitDirection == LeftToRight || self.slitDirection == RightToLeft)));
							CGFloat maxLines = self.currentImageSize.height;

							if (self.currentLine > maxLines)
							{
								self.currentLine = 0;
							}

							if (buffer != NULL)
							{
								CFRelease(buffer);
							}

							if (self.stopAfterNextFrame)
							{
								[assetReader cancelReading];
								self.stopAfterNextFrame = NO;
								break;
							}
						} // pool
					}

					[self.imagesQueue removeAllObjects];

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
							[self setControlsEnabled:YES];
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

- (void)setControlsEnabled:(BOOL)enabled
{
	[self.controls each:^(NSControl *c) {
		c.enabled = enabled;
	}];
}

@end
