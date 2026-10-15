// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppStatusBar.h"

@interface MppStatusLabel : NSTextField
@property (nonatomic) MppStatusField field;
@property (nonatomic, weak) MppStatusBar *bar;
@end

@interface MppStatusBar ()
- (void)fieldClicked:(MppStatusLabel *)field event:(NSEvent *)event;
@end

@implementation MppStatusLabel
- (void)mouseDown:(NSEvent *)event
{
	[_bar fieldClicked:self event:event];
}
- (void)resetCursorRects
{
	if (_field == MppStatusDocType || _field == MppStatusEOL || _field == MppStatusEncoding)
		[self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
@end

@implementation MppStatusBar {
	NSMutableArray<MppStatusLabel *> *_fields;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_fields = [NSMutableArray array];
		NSStackView *stack = [[NSStackView alloc] init];
		stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
		stack.spacing = 0;
		stack.distribution = NSStackViewDistributionFill;
		stack.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:stack];
		[NSLayoutConstraint activateConstraints:@[
			[stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
			[stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
			[stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:1],
			[stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
		const CGFloat widths[] = {0, 210, 260, 120, 120, 40};
		for (NSInteger i = 0; i < MppStatusFieldCount; ++i) {
			MppStatusLabel *f = [[MppStatusLabel alloc] init];
			f.field = (MppStatusField)i;
			f.bar = self;
			f.editable = NO;
			f.selectable = NO;
			f.bordered = NO;
			f.drawsBackground = NO;
			f.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
			f.textColor = NSColor.secondaryLabelColor;
			f.lineBreakMode = NSLineBreakByTruncatingTail;
			f.stringValue = @"";
			f.translatesAutoresizingMaskIntoConstraints = NO;
			[f setContentCompressionResistancePriority:(i == 0 ? 200 : 700) forOrientation:NSLayoutConstraintOrientationHorizontal];
			[f setContentHuggingPriority:(i == 0 ? 1 : 750) forOrientation:NSLayoutConstraintOrientationHorizontal];
			if (widths[i] > 0)
				[f.widthAnchor constraintEqualToConstant:widths[i]].active = YES;
			if (i > 0) {
				NSBox *sep = [[NSBox alloc] init];
				sep.boxType = NSBoxSeparator;
				sep.translatesAutoresizingMaskIntoConstraints = NO;
				[stack addArrangedSubview:sep];
				[sep.heightAnchor constraintEqualToConstant:14].active = YES;
				NSView *pad = [[NSView alloc] init];
				[pad.widthAnchor constraintEqualToConstant:6].active = YES;
				[stack addArrangedSubview:pad];
			}
			[stack addArrangedSubview:f];
			[_fields addObject:f];
		}
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(self.bounds);
	[NSColor.separatorColor setFill];
	NSRectFill(NSMakeRect(0, self.bounds.size.height - 1, self.bounds.size.width, 1));
}

- (BOOL)isFlipped
{
	return NO;
}

- (void)setText:(NSString *)text forField:(MppStatusField)field
{
	if (field < 0 || field >= MppStatusFieldCount)
		return;
	MppStatusLabel *f = _fields[(NSUInteger)field];
	if (![f.stringValue isEqualToString:text])
		f.stringValue = text ?: @"";
}

- (void)fieldClicked:(MppStatusLabel *)field event:(NSEvent *)event
{
	if (!_menuProvider)
		return;
	NSMenu *m = _menuProvider(field.field);
	if (m)
		[NSMenu popUpContextMenu:m withEvent:event forView:field];
}

@end
