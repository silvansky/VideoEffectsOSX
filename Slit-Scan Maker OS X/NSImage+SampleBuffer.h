//
//  NSImage+NSImage_SampleBuffer.h
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 28.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@import AVFoundation;

@interface NSImage (SampleBuffer)

+ (instancetype)imageWithSampleBuffer:(CMSampleBufferRef)buffer;

@end
