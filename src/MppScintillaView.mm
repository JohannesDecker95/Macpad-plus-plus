// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppScintillaView.h"
#import "MppPrefs.h"
#include "Scintilla.h"

// Implemented by SCIContentView but not declared in its public header
@interface SCIContentView (MppPrivate)
- (void)copy:(id)sender;
- (void)cut:(id)sender;
- (void)keyDown:(NSEvent *)event;
@end

@interface MppContentView : SCIContentView
@end

@implementation MppContentView

- (MppScintillaView *)mppOwner
{
	NSView *v = self.superview;
	while (v && ![v isKindOfClass:[MppScintillaView class]])
		v = v.superview;
	return (MppScintillaView *)v;
}

- (BOOL)selectionEmpty
{
	MppScintillaView *o = [self mppOwner];
	return [o message:SCI_GETSELECTIONEMPTY] != 0;
}

- (void)copy:(id)sender
{
	if ([self selectionEmpty] && [MppPrefs shared].copyLineWithoutSelection)
		[[self mppOwner] message:SCI_COPYALLOWLINE];
	else
		[super copy:sender];
}

- (void)cut:(id)sender
{
	MppScintillaView *o = [self mppOwner];
	if ([self selectionEmpty] && [MppPrefs shared].copyLineWithoutSelection) {
		if ([o message:SCI_GETREADONLY])
			return;
		[o message:SCI_LINECUT];
	} else {
		[super cut:sender];
	}
}

- (void)delete:(id)sender
{
	[[self mppOwner] message:SCI_CLEAR];
}

- (void)keyDown:(NSEvent *)event
{
	MppScintillaView *o = [self mppOwner];
	if (o.keyDownHandler && o.keyDownHandler(o, event))
		return;
	[super keyDown:event];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	SEL a = item.action;
	MppScintillaView *o = [self mppOwner];
	const BOOL readOnly = [o message:SCI_GETREADONLY] != 0;
	if (a == @selector(copy:))
		return ![self selectionEmpty] || [MppPrefs shared].copyLineWithoutSelection;
	if (a == @selector(cut:))
		return !readOnly && (![self selectionEmpty] || [MppPrefs shared].copyLineWithoutSelection);
	if (a == @selector(delete:))
		return !readOnly;
	if (a == @selector(paste:))
		return !readOnly && [super validateUserInterfaceItem:item];
	return [super validateUserInterfaceItem:item];
}

@end

// Scintilla's SCIScrollView -tile moves the clip view right of the margin ruler, assuming AppKit
// placed it underneath (macOS 10.14 behaviour). Recent AppKit versions already lay it out next to
// the ruler, so the original code subtracted the ruler width twice and left an unpainted strip on the
// right. This replacement only adjusts the frame when the clip view really overlaps the ruler.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
@implementation SCIScrollView (MppTileFix)
- (void)tile
{
	[super tile];
	NSRulerView *ruler = self.verticalRulerView;
	if (!ruler || !self.rulersVisible)
		return;
	const CGFloat thickness = ruler.requiredThickness;
	NSRect frame = self.contentView.frame;
	if (frame.origin.x < thickness) {
		const CGFloat delta = thickness - frame.origin.x;
		frame.origin.x = thickness;
		frame.size.width -= delta;
		self.contentView.frame = frame;
	}
}
@end
#pragma clang diagnostic pop

@implementation MppScintillaView

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		// Scroll bars only appear when the content does not fit
		self.scrollView.autohidesScrollers = YES;
	}
	return self;
}

+ (Class)contentViewClass
{
	return [MppContentView class];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	if (_contextMenuProvider)
		return _contextMenuProvider(self);
	return [super menuForEvent:event];
}

@end
