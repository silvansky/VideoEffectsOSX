//
//  NSImage+NSImage_SampleBuffer.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 28.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "NSImage+SampleBuffer.h"

@implementation NSImage (SampleBuffer)

+ (instancetype)imageWithSampleBuffer:(CMSampleBufferRef)buffer
{
	// From Apple sample
	// Get a CMSampleBuffer's Core Video image buffer for the media data
	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);

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

- (CVPixelBufferRef)pixelBuffer
{
	CGImageRef image = [self CGImageForProposedRect:nil context:nil hints:nil];

	CGSize frameSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
	NSDictionary *options = @{ (id)kCVPixelBufferCGImageCompatibilityKey : @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES };
	CVPixelBufferRef pxbuffer = NULL;

	CVReturn status =
	CVPixelBufferCreate(
						kCFAllocatorDefault, frameSize.width, frameSize.height,
						kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options,
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

	CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image)), image);
	CGColorSpaceRelease(rgbColorSpace);
	CGContextRelease(context);

	CVPixelBufferUnlockBaseAddress(pxbuffer, 0);

	return pxbuffer;
}

@end
