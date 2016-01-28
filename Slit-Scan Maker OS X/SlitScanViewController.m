//
//  SlitScanViewController.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "SlitScanViewController.h"
#import "SourceVideoView.h"
#import "NSImage+SampleBuffer.h"

@import AVFoundation;
@import AVKit;
@import CoreGraphics;

typedef enum : NSUInteger {
	LeftToRight,
	RightToLeft,
	TopToBottom,
	BottomToTop
} MovingSlitDirection;

@interface SlitScanViewController ()

@property (weak) IBOutlet SourceVideoView *sourceVideoView;
@property (weak) IBOutlet NSImageView *resultingImageView;

@property (weak) IBOutlet NSBox *slitModeBox;
@property (weak) IBOutlet NSBox *slitMoveDirectionBox;
@property (weak) IBOutlet NSBox *slitTypeBox;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (weak) IBOutlet NSButton *startButton;

// mode box
@property (weak) IBOutlet NSButton *slitModeStillRadioButton;
@property (weak) IBOutlet NSButton *slitModeMovingRadioButton;

// direction box
@property (weak) IBOutlet NSButton *slitMoveDirectonLtoRRadioButton;
@property (weak) IBOutlet NSButton *slitMoveDirectonRtoLRadioButton;
@property (weak) IBOutlet NSButton *slitMoveDirectionTtoBRadioButton;
@property (weak) IBOutlet NSButton *slitMoveDirectionBtoTRadioButton;

// type box
@property (weak) IBOutlet NSButton *slitTypeVerticalRadioButton;
@property (weak) IBOutlet NSButton *slitTypeHorizontalRadioButton;
@property (weak) IBOutlet NSSlider *slitPositionSlider;

// arrays of elements

@property (nonatomic, strong) NSArray<NSControl *> *modeBoxElements;
@property (nonatomic, strong) NSArray<NSControl *> *directionBoxElements;
@property (nonatomic, strong) NSArray<NSControl *> *typeBoxElements;

// helpers
@property (nonatomic, strong) AVURLAsset *currentAsset;
@property (nonatomic, assign) NSSize currentImageSize;
@property (nonatomic, assign) BOOL movingLine;
@property (nonatomic, assign) BOOL verticalSlit;
@property (nonatomic, assign) NSInteger currentLine;
@property (atomic, strong) NSImage *internalPartialImg;
@property (atomic, strong) NSImage *originalPreviewImage;
@property (nonatomic, assign) BOOL processing;
@property (nonatomic, assign) BOOL stopAfterNextFrame;
@property (nonatomic, assign) MovingSlitDirection slitDirection;

- (void)processAsset:(AVURLAsset *)asset;
- (void)saveCurrentImage;
- (void)enableBox:(NSArray<NSControl *> *)box;
- (void)disableBox:(NSArray<NSControl *> *)box;
- (void)updateBoxes;

@end

@implementation SlitScanViewController

- (IBAction)slitModeSwitched:(id)sender
{
	self.movingLine = (sender == self.slitModeMovingRadioButton);
	self.sourceVideoView.showSlit = !self.movingLine;
	[self updateBoxes];
}

- (IBAction)slitMoveDirectionSwitched:(id)sender
{
	MovingSlitDirection direction;
	if (sender == self.slitMoveDirectonLtoRRadioButton)
	{
		direction = LeftToRight;
	}
	else if (sender == self.slitMoveDirectonRtoLRadioButton)
	{
		direction = RightToLeft;
	}
	else if (sender == self.slitMoveDirectionTtoBRadioButton)
	{
		direction = TopToBottom;
	}
	else if (sender == self.slitMoveDirectionBtoTRadioButton)
	{
		direction = BottomToTop;
	}

	self.slitDirection = direction;
}

- (IBAction)slitTypeSwitched:(id)sender
{
	BOOL vertical = (sender == self.slitTypeVerticalRadioButton);
	self.sourceVideoView.verticalSlit = vertical;
	self.verticalSlit = vertical;
}

- (void)viewDidLoad
{
	// set up elements arrays
	self.modeBoxElements = @[ self.slitModeMovingRadioButton, self.slitModeStillRadioButton ];
	self.directionBoxElements = @[ self.slitMoveDirectionBtoTRadioButton, self.slitMoveDirectionTtoBRadioButton, self.slitMoveDirectonLtoRRadioButton, self.slitMoveDirectonRtoLRadioButton ];
	self.typeBoxElements = @[ self.slitTypeHorizontalRadioButton, self.slitTypeVerticalRadioButton, self.slitPositionSlider ];

	// initial state
	self.verticalSlit = YES;
	self.movingLine = NO;
	self.slitDirection = LeftToRight;
	[self updateBoxes];

	self.sourceVideoView.showSlit = YES;
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
			[self updateBoxes];
			[self processAsset:self.currentAsset];
		}
		else
		{
			self.stopAfterNextFrame = YES;
		}
		return [RACSignal empty];
	}];
	self.startButton.rac_command = cmd;

	[self.slitPositionSlider bind:@"value" toObject:self.sourceVideoView withKeyPath:@"slitPosition" options:nil];
}

#pragma mark - Private

- (NSImage *)partialImageWithSource:(NSImage *)source
{
	if (source == nil)
	{
		return nil;
	}

	CGImageRef sourceQuartzImage = [source CGImageForProposedRect:nil context:nil hints:nil];
	size_t width = CGImageGetWidth(sourceQuartzImage);
	size_t height = CGImageGetHeight(sourceQuartzImage);
	CGSize size = CGSizeMake((CGFloat)width, (CGFloat)height);
	CGRect rect;
	rect.origin = CGPointMake(0.f, 0.f);
	rect.size = size;

	CGRect lineRect;
	if (self.movingLine)
	{
		switch (self.slitDirection)
		{
			case LeftToRight:
				lineRect = CGRectMake((CGFloat)self.currentLine, 0.f, 1.f, (CGFloat)height);
				break;
			case RightToLeft:
				lineRect = CGRectMake((CGFloat)(width - self.currentLine), 0.f, 1.f, (CGFloat)height);
				break;
			case TopToBottom:
				lineRect = CGRectMake(0.f, (CGFloat)self.currentLine, (CGFloat)width, 1.f);
				break;
			case BottomToTop:
				lineRect = CGRectMake(0.f, (CGFloat)(height - self.currentLine), (CGFloat)width, 1.f);
				break;
		}
	}
	else if (self.verticalSlit)
	{
		lineRect = CGRectMake((CGFloat)(width * self.sourceVideoView.slitPosition / 100.f), 0.f, 1.f, (CGFloat)height);
	}
	else
	{
		lineRect = CGRectMake(0.f, (CGFloat)(height - height * self.sourceVideoView.slitPosition / 100.f), (CGFloat)width, 1.f);
	}

	CGRect lineDrawRect;
	if (self.movingLine)
	{
		switch (self.slitDirection)
		{
			case LeftToRight:
				lineDrawRect = CGRectMake((CGFloat)self.currentLine, 0.f, 1.f, (CGFloat)height);
				break;
			case RightToLeft:
				lineDrawRect = CGRectMake((CGFloat)(width - self.currentLine), 0.f, 1.f, (CGFloat)height);
				break;
			case BottomToTop:
				lineDrawRect = CGRectMake(0.f, (CGFloat)self.currentLine, (CGFloat)width, 1.f);
				break;
			case TopToBottom:
				lineDrawRect = CGRectMake(0.f, (CGFloat)(height - self.currentLine), (CGFloat)width, 1.f);
				break;
		}
	}
	else if (self.verticalSlit)
	{
		lineDrawRect = CGRectMake((CGFloat)self.currentLine, 0.f, 1.f, (CGFloat)height);
	}
	else
	{
		lineDrawRect = CGRectMake(0.f, (CGFloat)(height - self.currentLine), (CGFloat)width, 1.f);
	}

	CGImageRef line = CGImageCreateWithImageInRect(sourceQuartzImage, lineRect);

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);

	if (!ctx)
	{
		NSLog(@"Hey, no context in partialImageWithSource! Debug me plz. =/");
	}

	if (self.internalPartialImg)
	{
		CGContextDrawImage(ctx, rect, [self.internalPartialImg CGImageForProposedRect:nil context:nil hints:nil]);
	}

	CGContextDrawImage(ctx, lineDrawRect, line);

	NSImage *image = nil;

	CGImageRef quartzImage = CGBitmapContextCreateImage(ctx);

	CGContextRelease(ctx);
	CGColorSpaceRelease(colorSpace);

	image = [[NSImage alloc] initWithCGImage:quartzImage size:size];

	CGImageRelease(quartzImage);
	CGImageRelease(line);

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
			NSError *error = nil;
			AVAssetReader *assetReader = [[AVAssetReader alloc] initWithAsset:self.currentAsset error:&error];
			AVAssetTrack *videoTrack = [self.currentAsset tracksWithMediaType:AVMediaTypeVideo][0];
			NSDictionary *dict = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };

			AVAssetReaderTrackOutput *assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:dict];

			NSInteger i = 0;
			self.currentLine = 0;
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
							NSImage *partialImage = [self partialImageWithSource:currentImage];

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
							self.currentLine++;

							BOOL verticalSlit = ((!self.movingLine && self.verticalSlit) || (self.movingLine && (self.slitDirection == LeftToRight || self.slitDirection == RightToLeft)));
							CGFloat maxLines = (verticalSlit ? self.currentImageSize.width : self.currentImageSize.height);

							if (self.currentLine > maxLines)
							{
								self.currentLine = 0;
								[self saveCurrentImage];
								self.internalPartialImg = nil;
							}

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
					[self saveCurrentImage];
					self.internalPartialImg = nil;
					NSLog(@"Processed %@ frames in %@ seconds, FPS: %@", @(i), @(duration), @(i/duration));

					dispatch_async(dispatch_get_main_queue(), ^{
						@autoreleasepool {
							self.sourceVideoView.locked = NO;
							[self.progressIndicator stopAnimation:nil];
							self.processing = NO;
							self.startButton.title = @"Start";
							[self.sourceVideoView updatePreview:self.originalPreviewImage];
							[self updateBoxes];
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

- (void)saveCurrentImage
{
	NSData *imageData = [self.internalPartialImg TIFFRepresentation];
	NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:imageData];
	NSData *data = [imageRep representationUsingType:NSPNGFileType properties:@{}];
	NSString *fileName = [NSString stringWithFormat:@"/Users/valentine/Pictures/SSM/slit-scan-%@.png", @([[NSDate date] timeIntervalSince1970])];
	BOOL ok = [data writeToFile:fileName atomically:NO];
	NSLog(@"Saved image to %@ (%@)", fileName, @(ok));
}

- (void)enableBox:(NSArray<NSControl *> *)box
{
	[box each:^(NSControl *object) {
		object.enabled = YES;
	}];
}

- (void)disableBox:(NSArray<NSControl *> *)box
{
	[box each:^(NSControl *object) {
		object.enabled = NO;
	}];
}

- (void)updateBoxes
{
	if (self.processing)
	{
		[self disableBox:self.modeBoxElements];
		[self disableBox:self.typeBoxElements];
		[self disableBox:self.directionBoxElements];
	}
	else
	{
		[self enableBox:self.modeBoxElements];
		if (self.movingLine)
		{
			[self disableBox:self.typeBoxElements];
			[self enableBox:self.directionBoxElements];
		}
		else
		{
			[self disableBox:self.directionBoxElements];
			[self enableBox:self.typeBoxElements];
		}
	}
}

@end
