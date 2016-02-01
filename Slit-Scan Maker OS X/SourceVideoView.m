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

	[RACObserve(self, slitPosition) subscribeNext:^(id x) {
		[self setNeedsDisplay:YES];
	}];

	[RACObserve(self, verticalSlit) subscribeNext:^(id x) {
		[self setNeedsDisplay:YES];
	}];

	[RACObserve(self, showSlit) subscribeNext:^(id x) {
		[self setNeedsDisplay:YES];
	}];
}

- (RACSignal *)draggedFilesSignal
{
	return self.draggedFilesSubject;
}

- (void)updatePreview:(NSImage *)preview
{
	self.previewImage = preview;
	[self setNeedsDisplay:YES];
}

#pragma mark - Drag

+ (NSArray *)supportedExtensions
{
	static __strong NSArray *_extensions = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_extensions = @[ @"mov", @"mp4", @"m4v", @"qt" ];
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
	if (self.locked)
	{
		return NSDragOperationNone;
	}

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

		[[NSColor blackColor] set];

		NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		style.alignment = NSCenterTextAlignment;

		NSDictionary *attrs = @{ NSFontAttributeName : [NSFont systemFontOfSize:20], NSParagraphStyleAttributeName : style };
		[[NSString stringWithFormat:@"Drop movie file here!"] drawInRect:self.bounds withAttributes:attrs];
	}

	if (self.draggingInProgress)
	{
		[[NSColor colorWithRed:0.3 green:0.4 blue:1 alpha:0.2] setFill];
		NSRectFillUsingOperation(self.bounds, NSCompositeSourceOver);
	}

	if (self.showSlit)
	{
		NSRect lineRect;
		if (self.verticalSlit)
		{
			CGFloat x = self.bounds.size.width * self.slitPosition * 0.01;
			lineRect = NSMakeRect(x, 0.f, 1.f, self.bounds.size.height);
		}
		else
		{
			CGFloat y = self.bounds.size.height * self.slitPosition * 0.01;
			lineRect = NSMakeRect(0.f, y, self.bounds.size.width, 1.f);
		}

		[[NSColor colorWithRed:1 green:0 blue:0 alpha:1] setFill];
		NSRectFill(lineRect);
	}
}

@end
