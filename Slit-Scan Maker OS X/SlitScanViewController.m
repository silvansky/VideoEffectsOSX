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
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

@property (nonatomic, strong) AVURLAsset *currentAsset;
@property (nonatomic, assign) NSSize currentImageSize;
@property (nonatomic, assign) BOOL movingLine;
@property (nonatomic, assign) NSInteger currentLine;
@property (atomic, strong) NSImage *internalPartialImg;

- (void)processAsset:(AVURLAsset *)asset;
- (void)saveCurrentImage;

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
		self.currentImageSize = size;
		[self.sourceVideoView updatePreview:[[NSImage alloc] initWithCGImage:cgImage size:size]];
		[self processAsset:asset];
		CGImageRelease(cgImage);
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
		CGColorSpaceRelease(colorSpace);
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

	CGRect lineRect = self.movingLine ? CGRectMake((CGFloat)self.currentLine, 0.f, 1.f, (CGFloat)height) : CGRectMake((CGFloat)(width / 2.f), 0.f, 1.f, (CGFloat)height);
	CGRect lineDrawRect = CGRectMake((CGFloat)self.currentLine, 0.f, 1.f, (CGFloat)height);
	CGRect cursorLineRect = lineDrawRect;
	cursorLineRect.origin.x += 1.f;

	CGImageRef line = CGImageCreateWithImageInRect(sourceQuartzImage, lineRect);

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);

	if (!ctx)
	{
		NSLog(@"WTF!");
	}

	if (self.internalPartialImg)
	{
		CGContextDrawImage(ctx, rect, [self.internalPartialImg CGImageForProposedRect:nil context:nil hints:nil]);
	}

	CGContextDrawImage(ctx, lineDrawRect, line);

//	CGContextSetFillColorWithColor(ctx, [NSColor colorWithRed:(117.f/255.f) green:(205.f/255.f) blue:0.f alpha:1.f].CGColor);
//	CGContextFillRect(ctx, cursorLineRect);

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
	dispatch_async(dispatch_queue_create("prc", DISPATCH_QUEUE_SERIAL), ^{
		@autoreleasepool {
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
						@autoreleasepool {
							buffer = [assetReaderOutput copyNextSampleBuffer];
							NSImage *currentImage = [self imageFromSampleBuffer:buffer];
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
							if (self.currentLine > self.currentImageSize.width)
							{
								self.currentLine = 0;
								[self saveCurrentImage];
								self.internalPartialImg = nil;
							}
						}
					}

					NSDate *endDate = [NSDate date];
					NSTimeInterval duration = [endDate timeIntervalSinceDate:startDate];
					[self saveCurrentImage];
					NSLog(@"Processed %@ frames in %@ seconds, FPS: %@", @(i), @(duration), @(i/duration));

					dispatch_async(dispatch_get_main_queue(), ^{
						@autoreleasepool {
							self.sourceVideoView.locked = NO;
							[self.progressIndicator stopAnimation:nil];
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

@end
