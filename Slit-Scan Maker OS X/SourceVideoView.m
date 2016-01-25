//
//  SourceVideoView.m
//  Slit-Scan Maker OS X
//
//  Created by Valentine on 25.01.16.
//  Copyright © 2016 Songsterr. All rights reserved.
//

#import "SourceVideoView.h"

@interface SourceVideoView ()

@property (nonatomic, assign) BOOL draggingInProgress;
@property (nonatomic, strong) NSImage *previewImage;
@property (nonatomic, strong) NSString *draggedFileName;

@property (nonatomic, strong) RACSubject *draggedFilesSubject;

@end

@implementation SourceVideoView

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self)
	{
		self.draggedFilesSubject = [RACSubject subject];
	}

	return self;
}

- (void)awakeFromNib
{
	[self registerForDraggedTypes:@[ NSFilenamesPboardType ]];
}

- (RACSignal *)draggedFilesSignal
{
	return self.draggedFilesSubject;
}

#pragma mark - Drag

+ (NSArray *)supportedExtensions
{
	static __strong NSArray *_extensions = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_extensions = @[ @"mov", @"mp4", @"avi" ];
	});

	return _extensions;
}

+ (NSString *)fileNameForDragged:(id<NSDraggingInfo>)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];

	if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		NSArray *fileList = [pboard propertyListForType:NSFilenamesPboardType];
		if (fileList.count == 1)
		{
			NSString *draggedFile = fileList[0];

			NSString *extension = [[draggedFile pathExtension] lowercaseString];
			for (NSString *supportedExtension in [self supportedExtensions])
			{
				if ([supportedExtension isEqualToString:extension])
				{
					return draggedFile;
				}
			}
		}
	}

	return nil;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
	NSString *file = [SourceVideoView fileNameForDragged:sender];

	self.draggingInProgress = file ? YES : NO;
	[self setNeedsDisplay:YES];

	return file ? NSDragOperationLink : NSDragOperationNone;
}

- (void)draggingExited:(nullable id <NSDraggingInfo>)sender
{
	self.draggingInProgress = NO;
	[self setNeedsDisplay:YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
//	NSString *file = [SourceVideoView fileNameForDragged:sender];
//	NSLog(@"prepareForDragOperation: %@",file);
	return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	NSString *file = [SourceVideoView fileNameForDragged:sender];
	self.draggedFileName = file;
	[self.draggedFilesSubject sendNext:file];
//	NSLog(@"performDragOperation: %@",file);
	return YES;
}

- (void)concludeDragOperation:(nullable id <NSDraggingInfo>)sender
{
//	NSString *file = [SourceVideoView fileNameForDragged:sender];
//	NSLog(@"concludeDragOperation: %@",file);
}

- (void)draggingEnded:(nullable id <NSDraggingInfo>)sender
{
//	NSString *file = [SourceVideoView fileNameForDragged:sender];
//	NSLog(@"draggingEnded: %@",file);
	self.draggingInProgress = NO;
	[self setNeedsDisplay:YES];
}

#pragma mark - Draw

- (void)drawRect:(NSRect)dirtyRect
{
	if (self.previewImage != nil)
	{
		[self.previewImage drawInRect:self.bounds];
	}
	else
	{
		[[NSColor whiteColor] setFill];
		NSRectFill(self.bounds);
	}

	if (self.draggingInProgress)
	{
		[[NSColor colorWithRed:0 green:0 blue:1 alpha:0.2] setFill];
		NSRectFillUsingOperation(self.bounds, NSCompositeSourceOver);
	}
}

@end
