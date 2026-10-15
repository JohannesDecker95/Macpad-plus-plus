// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppTabBar.h"
#import "MppDocument.h"
#import "MppPrefs.h"
#import "MppLanguages.h"

static const CGFloat kTabHeight = 28;
static const CGFloat kMinTabWidth = 90;
static const CGFloat kMaxTabWidth = 240;
static const CGFloat kChevronWidth = 22;

@implementation MppTabBar {
	std::vector<NSRect> _rects;       // content coordinates (before scroll)
	CGFloat _scroll;
	CGFloat _contentWidth;
	NSInteger _hoverIndex;
	BOOL _hoverClose;
	NSInteger _pressedIndex;
	BOOL _pressedClose;
	NSPoint _mouseDownPoint;
	BOOL _dragging;
	NSInteger _dropIndicator;         // insertion index while dragging inside the bar
	NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_hoverIndex = NSNotFound;
		_pressedIndex = NSNotFound;
		_dropIndicator = NSNotFound;
		_documents = @[];
	}
	return self;
}

- (BOOL)isFlipped
{
	return YES;
}

- (NSSize)intrinsicContentSize
{
	return NSMakeSize(NSViewNoIntrinsicMetric, kTabHeight);
}

- (void)updateTrackingAreas
{
	[super updateTrackingAreas];
	if (_tracking)
		[self removeTrackingArea:_tracking];
	_tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
	                                         options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
	                                                 NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
	                                           owner:self
	                                        userInfo:nil];
	[self addTrackingArea:_tracking];
}

- (NSDictionary *)titleAttributes:(BOOL)selected
{
	NSFont *font = selected ? [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:12];
	NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
	ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
	return @{NSFontAttributeName: font,
	         NSForegroundColorAttributeName: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
	         NSParagraphStyleAttributeName: ps};
}

- (void)layoutTabs
{
	_rects.clear();
	CGFloat x = 0;
	for (MppDocument *d in _documents) {
		NSSize sz = [d.displayName sizeWithAttributes:[self titleAttributes:YES]];
		CGFloat w = 10 + 16 + 6 + sz.width + 6 + ([MppPrefs shared].showTabCloseButton ? 18 : 4) + 8;
		w = std::min(std::max(w, kMinTabWidth), kMaxTabWidth);
		_rects.push_back(NSMakeRect(x, 0, w, kTabHeight));
		x += w;
	}
	_contentWidth = x;
	const CGFloat avail = [self availableWidth];
	_scroll = std::max<CGFloat>(0, std::min(_scroll, _contentWidth - avail));
}

- (BOOL)overflows
{
	return _contentWidth > self.bounds.size.width;
}

- (CGFloat)availableWidth
{
	return self.bounds.size.width - ([self overflows] ? kChevronWidth : 0);
}

- (NSRect)visibleRectForIndex:(NSInteger)i
{
	if (i < 0 || i >= (NSInteger)_rects.size())
		return NSZeroRect;
	return NSOffsetRect(_rects[i], -_scroll, 0);
}

- (NSRect)closeRectForTab:(NSRect)tab
{
	return NSMakeRect(NSMaxX(tab) - 8 - 16, NSMidY(tab) - 8, 16, 16);
}

- (void)reload
{
	[self layoutTabs];
	[self setNeedsDisplay:YES];
}

- (void)setDocuments:(NSArray<MppDocument *> *)documents
{
	_documents = [documents copy];
	[self reload];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex
{
	_selectedIndex = selectedIndex;
	[self scrollToSelected];
	[self setNeedsDisplay:YES];
}

- (void)setFocused:(BOOL)focused
{
	_focused = focused;
	[self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self layoutTabs];
}

- (void)scrollToSelected
{
	[self layoutTabs];
	if (_selectedIndex < 0 || _selectedIndex >= (NSInteger)_rects.size())
		return;
	NSRect r = _rects[_selectedIndex];
	const CGFloat avail = [self availableWidth];
	if (NSMinX(r) < _scroll)
		_scroll = NSMinX(r);
	else if (NSMaxX(r) > _scroll + avail)
		_scroll = NSMaxX(r) - avail;
	[self setNeedsDisplay:YES];
}

// ---- drawing ----------------------------------------------------------------

static NSColor *themeColor(const char *name, bool fg, NSColor *fallback)
{
	const MppStyle *s = [MppLanguages.shared theme]->global(name);
	if (!s)
		return fallback;
	return MppColorFromSci(fg ? s->fgColor : s->bgColor);
}

- (BOOL)isDarkAppearance
{
	NSAppearanceName n = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [n isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSImage *)iconForDocument:(MppDocument *)d tint:(NSColor **)tint
{
	NSString *name;
	if (d.monitoring) {
		name = @"eye";
		*tint = NSColor.systemGreenColor;
	} else if (d.userReadOnly || d.fileReadOnly) {
		name = @"lock.fill";
		*tint = NSColor.tertiaryLabelColor;
	} else if (d.dirty) {
		name = @"square.and.arrow.down.fill";
		*tint = NSColor.systemRedColor;
	} else {
		name = @"square.and.arrow.down";
		*tint = NSColor.systemBlueColor;
	}
	NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightRegular];
	return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:cfg];
}

- (void)drawImage:(NSImage *)img tinted:(NSColor *)tint inRect:(NSRect)r
{
	NSImage *copy = [NSImage imageWithSize:img.size flipped:NO drawingHandler:^BOOL(NSRect dst) {
		[img drawInRect:dst];
		[tint set];
		NSRectFillUsingOperation(dst, NSCompositingOperationSourceAtop);
		return YES;
	}];
	NSSize s = img.size;
	NSRect dst = NSMakeRect(NSMidX(r) - s.width / 2, NSMidY(r) - s.height / 2, s.width, s.height);
	[copy drawInRect:dst fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}

- (void)drawRect:(NSRect)dirtyRect
{
	const BOOL dark = [self isDarkAppearance];
	NSColor *barBg = dark ? [NSColor colorWithWhite:0.13 alpha:1] : [NSColor colorWithWhite:0.86 alpha:1];
	[barBg setFill];
	NSRectFill(self.bounds);

	const CGFloat avail = [self availableWidth];
	[NSGraphicsContext saveGraphicsState];
	NSRectClip(NSMakeRect(0, 0, avail, kTabHeight));

	NSColor *activeBg = dark ? [NSColor colorWithWhite:0.20 alpha:1] : NSColor.whiteColor;
	NSColor *inactiveBg = dark ? [NSColor colorWithWhite:0.16 alpha:1] : [NSColor colorWithWhite:0.92 alpha:1];
	NSColor *hoverBg = dark ? [NSColor colorWithWhite:0.18 alpha:1] : [NSColor colorWithWhite:0.96 alpha:1];
	NSColor *separator = dark ? [NSColor colorWithWhite:0.28 alpha:1] : [NSColor colorWithWhite:0.72 alpha:1];

	for (NSInteger i = 0; i < (NSInteger)_documents.count; ++i) {
		NSRect r = [self visibleRectForIndex:i];
		if (NSMaxX(r) < 0 || NSMinX(r) > avail)
			continue;
		MppDocument *d = _documents[i];
		const BOOL sel = (i == _selectedIndex);

		NSColor *bg = sel ? activeBg : (i == _hoverIndex ? hoverBg : inactiveBg);
		if (d.tabColor >= 0 && d.tabColor <= 4) {
			char name[32];
			snprintf(name, sizeof name, dark ? "Tab color dark mode %d" : "Tab color %d", (int)d.tabColor + 1);
			NSColor *tc = themeColor(name, false, bg);
			bg = sel ? tc : [tc blendedColorWithFraction:0.35 ofColor:inactiveBg];
		}
		[bg setFill];
		NSRect body = NSInsetRect(r, 0, 0);
		body.origin.y += sel ? 0 : 2;
		body.size.height -= sel ? 0 : 2;
		NSRectFill(body);

		// separators
		[separator setFill];
		NSRectFill(NSMakeRect(NSMaxX(r) - 1, r.origin.y + 5, 1, r.size.height - 10));

		if (sel) {
			NSColor *ind = _focused ? themeColor("Active tab focused indicator", true, NSColor.orangeColor)
			                        : themeColor("Active tab unfocused indicator", true, [NSColor colorWithCalibratedRed:1 green:0.8 blue:0.7 alpha:1]);
			[ind setFill];
			NSRectFill(NSMakeRect(r.origin.x, 0, r.size.width - 1, 3));
		}

		NSColor *tint = nil;
		NSImage *icon = [self iconForDocument:d tint:&tint];
		[self drawImage:icon tinted:tint inRect:NSMakeRect(r.origin.x + 8, r.origin.y, 16, kTabHeight)];

		const BOOL closeBtn = [MppPrefs shared].showTabCloseButton;
		NSRect titleRect = NSMakeRect(r.origin.x + 30, r.origin.y, r.size.width - 30 - (closeBtn ? 28 : 8), kTabHeight);
		NSDictionary *attrs = [self titleAttributes:sel];
		NSSize ts = [d.displayName sizeWithAttributes:attrs];
		titleRect.origin.y = NSMidY(r) - ts.height / 2;
		titleRect.size.height = ts.height;
		[d.displayName drawInRect:titleRect withAttributes:attrs];

		if (closeBtn && (sel || i == _hoverIndex)) {
			NSRect cr = [self closeRectForTab:r];
			if (i == _hoverIndex && _hoverClose) {
				[(dark ? [NSColor colorWithWhite:1 alpha:0.15] : [NSColor colorWithWhite:0 alpha:0.12]) setFill];
				[[NSBezierPath bezierPathWithRoundedRect:cr xRadius:3 yRadius:3] fill];
			}
			NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:9 weight:NSFontWeightBold];
			NSImage *x = [[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"] imageWithSymbolConfiguration:cfg];
			[self drawImage:x tinted:(i == _hoverIndex && _hoverClose) ? NSColor.systemRedColor : NSColor.secondaryLabelColor inRect:cr];
		}
	}

	if (_dragging && _dropIndicator != NSNotFound) {
		CGFloat x = (_dropIndicator < (NSInteger)_rects.size()) ? NSMinX([self visibleRectForIndex:_dropIndicator])
		                                                       : _contentWidth - _scroll;
		[NSColor.controlAccentColor setFill];
		NSRectFill(NSMakeRect(x - 1, 2, 2, kTabHeight - 4));
	}
	[NSGraphicsContext restoreGraphicsState];

	// bottom line
	[separator setFill];
	NSRectFill(NSMakeRect(0, kTabHeight - 1, self.bounds.size.width, 1));

	if ([self overflows]) {
		NSRect cr = NSMakeRect(avail, 0, kChevronWidth, kTabHeight);
		[barBg setFill];
		NSRectFill(cr);
		NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold];
		NSImage *img = [[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"All documents"] imageWithSymbolConfiguration:cfg];
		[self drawImage:img tinted:NSColor.secondaryLabelColor inRect:cr];
	}
}

// ---- hit testing ------------------------------------------------------------

- (NSInteger)indexAtPoint:(NSPoint)p
{
	if (p.x > [self availableWidth])
		return NSNotFound;
	for (NSInteger i = 0; i < (NSInteger)_rects.size(); ++i)
		if (NSPointInRect(p, [self visibleRectForIndex:i]))
			return i;
	return NSNotFound;
}

- (NSInteger)insertionIndexAtPoint:(NSPoint)p
{
	for (NSInteger i = 0; i < (NSInteger)_rects.size(); ++i) {
		NSRect r = [self visibleRectForIndex:i];
		if (p.x < NSMidX(r))
			return i;
	}
	return (NSInteger)_rects.size();
}

- (void)mouseMoved:(NSEvent *)event
{
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	NSInteger i = [self indexAtPoint:p];
	BOOL onClose = (i != NSNotFound) && NSPointInRect(p, [self closeRectForTab:[self visibleRectForIndex:i]]);
	if (i != _hoverIndex || onClose != _hoverClose) {
		_hoverIndex = i;
		_hoverClose = onClose;
		[self setNeedsDisplay:YES];
	}
	MppDocument *d = (i != NSNotFound) ? _documents[i] : nil;
	self.toolTip = d ? (d.filePath ?: d.displayName) : nil;
}

- (void)mouseExited:(NSEvent *)event
{
	_hoverIndex = NSNotFound;
	_hoverClose = NO;
	[self setNeedsDisplay:YES];
}

- (void)showOverflowMenu
{
	NSMenu *m = [[NSMenu alloc] init];
	for (NSInteger i = 0; i < (NSInteger)_documents.count; ++i) {
		MppDocument *d = _documents[i];
		NSMenuItem *it = [m addItemWithTitle:[NSString stringWithFormat:@"%@%@", d.dirty ? @"*" : @"", d.displayName]
		                              action:@selector(overflowPick:)
		                       keyEquivalent:@""];
		it.target = self;
		it.tag = i;
		it.state = (i == _selectedIndex) ? NSControlStateValueOn : NSControlStateValueOff;
	}
	[m popUpMenuPositioningItem:nil atLocation:NSMakePoint(self.bounds.size.width - kChevronWidth, kTabHeight) inView:self];
}

- (void)overflowPick:(NSMenuItem *)item
{
	[_delegate tabBar:self didSelectIndex:item.tag];
}

- (void)mouseDown:(NSEvent *)event
{
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	_mouseDownPoint = p;
	_dragging = NO;
	if ([self overflows] && p.x > [self availableWidth]) {
		[self showOverflowMenu];
		return;
	}
	NSInteger i = [self indexAtPoint:p];
	if (event.clickCount == 2) {
		if (i == NSNotFound)
			[_delegate tabBarDoubleClickedEmptyArea:self];
		else if ([MppPrefs shared].doubleClickClosesTab)
			[_delegate tabBar:self closeIndex:i];
		return;
	}
	_pressedIndex = i;
	_pressedClose = (i != NSNotFound) && [MppPrefs shared].showTabCloseButton &&
	                NSPointInRect(p, [self closeRectForTab:[self visibleRectForIndex:i]]);
	if (i != NSNotFound && !_pressedClose)
		[_delegate tabBar:self didSelectIndex:i];
}

- (MppTabBar *)tabBarUnderWindowPoint:(NSPoint)wp
{
	NSView *v = [self.window.contentView hitTest:wp];
	while (v && ![v isKindOfClass:[MppTabBar class]])
		v = v.superview;
	return (MppTabBar *)v;
}

- (void)mouseDragged:(NSEvent *)event
{
	if (_pressedIndex == NSNotFound || _pressedClose)
		return;
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	if (!_dragging && hypot(p.x - _mouseDownPoint.x, p.y - _mouseDownPoint.y) < 5)
		return;
	if (!_dragging) {
		_dragging = YES;
		[[NSCursor closedHandCursor] push];
	}
	MppTabBar *target = [self tabBarUnderWindowPoint:event.locationInWindow];
	_dropIndicator = (target == self) ? [self insertionIndexAtPoint:p] : NSNotFound;
	// auto scroll
	if (target == self) {
		if (p.x < 10)
			_scroll = std::max<CGFloat>(0, _scroll - 10);
		else if (p.x > [self availableWidth] - 10)
			_scroll = std::min<CGFloat>(std::max<CGFloat>(0, _contentWidth - [self availableWidth]), _scroll + 10);
	}
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
	NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
	if (_dragging) {
		[NSCursor pop];
		_dragging = NO;
		_dropIndicator = NSNotFound;
		MppTabBar *target = [self tabBarUnderWindowPoint:event.locationInWindow];
		if (target == self) {
			NSInteger to = [self insertionIndexAtPoint:p];
			if (to > _pressedIndex)
				--to;
			if (to != _pressedIndex)
				[_delegate tabBar:self moveIndex:_pressedIndex toIndex:to];
		} else if (target) {
			NSPoint tp = [target convertPoint:event.locationInWindow fromView:nil];
			[_delegate tabBar:self dropIndex:_pressedIndex ontoBar:target atIndex:[target insertionIndexAtPoint:tp]];
		}
		_pressedIndex = NSNotFound;
		[self setNeedsDisplay:YES];
		return;
	}
	if (_pressedClose && _pressedIndex != NSNotFound) {
		NSInteger i = [self indexAtPoint:p];
		if (i == _pressedIndex && NSPointInRect(p, [self closeRectForTab:[self visibleRectForIndex:i]]))
			[_delegate tabBar:self closeIndex:i];
	}
	_pressedIndex = NSNotFound;
	_pressedClose = NO;
}

- (void)otherMouseUp:(NSEvent *)event
{
	if (event.buttonNumber != 2)
		return;
	NSInteger i = [self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
	if (i != NSNotFound)
		[_delegate tabBar:self closeIndex:i];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
	NSInteger i = [self indexAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
	if (i == NSNotFound)
		return nil;
	[_delegate tabBar:self didSelectIndex:i];
	return [_delegate tabBar:self menuForIndex:i];
}

- (void)scrollWheel:(NSEvent *)event
{
	if (![self overflows])
		return;
	CGFloat delta = fabs(event.scrollingDeltaX) > fabs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY;
	if (!event.hasPreciseScrollingDeltas)
		delta *= 20;
	_scroll = std::max<CGFloat>(0, std::min(_scroll - delta, _contentWidth - [self availableWidth]));
	[self setNeedsDisplay:YES];
}

@end
