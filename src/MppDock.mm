// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppDock.h"

@implementation MppDockContainer {
	NSMutableArray<NSString *> *_ids;
	NSMutableArray<NSString *> *_titles;
	NSMutableDictionary<NSString *, NSView *> *_views;
	NSSegmentedControl *_tabs;
	NSTextField *_title;
	NSView *_content;
	NSString *_selected;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_ids = [NSMutableArray array];
		_titles = [NSMutableArray array];
		_views = [NSMutableDictionary dictionary];

		_title = [NSTextField labelWithString:@""];
		_title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
		_title.lineBreakMode = NSLineBreakByTruncatingTail;
		[_title setContentCompressionResistancePriority:200 forOrientation:NSLayoutConstraintOrientationHorizontal];
		NSButton *close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"]
		                                     target:self action:@selector(closeSelected:)];
		close.bordered = NO;
		NSView *spacer = [[NSView alloc] init];
		[spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
		NSStackView *header = [NSStackView stackViewWithViews:@[_title, spacer, close]];
		header.edgeInsets = NSEdgeInsetsMake(3, 8, 3, 6);
		header.translatesAutoresizingMaskIntoConstraints = NO;

		_tabs = [[NSSegmentedControl alloc] init];
		_tabs.segmentStyle = NSSegmentStyleSmallSquare;
		_tabs.controlSize = NSControlSizeSmall;
		_tabs.target = self;
		_tabs.action = @selector(tabChanged:);
		_tabs.translatesAutoresizingMaskIntoConstraints = NO;
		_tabs.hidden = YES;

		_content = [[NSView alloc] init];
		_content.translatesAutoresizingMaskIntoConstraints = NO;

		for (NSView *v in @[header, _tabs, _content])
			[self addSubview:v];
		[NSLayoutConstraint activateConstraints:@[
			[header.topAnchor constraintEqualToAnchor:self.topAnchor],
			[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[header.heightAnchor constraintEqualToConstant:24],
			[_tabs.topAnchor constraintEqualToAnchor:header.bottomAnchor],
			[_tabs.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:4],
			[_tabs.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-4],
			[_content.topAnchor constraintEqualToAnchor:_tabs.bottomAnchor constant:2],
			[_content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[self.widthAnchor constraintGreaterThanOrEqualToConstant:150],
		]];
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(self.bounds);
}

- (BOOL)isEmpty
{
	return _ids.count == 0;
}

- (NSString *)selectedIdentifier
{
	return _selected;
}

- (BOOL)hasPanel:(NSString *)identifier
{
	return _views[identifier] != nil;
}

- (NSView *)panelView:(NSString *)identifier
{
	return _views[identifier];
}

- (void)rebuildTabs
{
	_tabs.segmentCount = (NSInteger)_ids.count;
	for (NSUInteger i = 0; i < _ids.count; ++i) {
		[_tabs setLabel:_titles[i] forSegment:(NSInteger)i];
		[_tabs setWidth:0 forSegment:(NSInteger)i];
	}
	_tabs.hidden = _ids.count < 2;
	if (_selected)
		_tabs.selectedSegment = (NSInteger)[_ids indexOfObject:_selected];
}

- (void)addPanel:(NSView *)view identifier:(NSString *)identifier title:(NSString *)title
{
	if (!_views[identifier]) {
		[_ids addObject:identifier];
		[_titles addObject:title];
		_views[identifier] = view;
	}
	[self rebuildTabs];
	[self selectPanel:identifier];
}

- (void)selectPanel:(NSString *)identifier
{
	NSView *v = _views[identifier];
	if (!v)
		return;
	for (NSView *sub in [_content.subviews copy])
		[sub removeFromSuperview];
	v.translatesAutoresizingMaskIntoConstraints = NO;
	[_content addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.topAnchor constraintEqualToAnchor:_content.topAnchor],
		[v.leadingAnchor constraintEqualToAnchor:_content.leadingAnchor],
		[v.trailingAnchor constraintEqualToAnchor:_content.trailingAnchor],
		[v.bottomAnchor constraintEqualToAnchor:_content.bottomAnchor],
	]];
	_selected = identifier;
	_title.stringValue = _titles[[_ids indexOfObject:identifier]];
	_tabs.selectedSegment = (NSInteger)[_ids indexOfObject:identifier];
}

- (void)removePanel:(NSString *)identifier
{
	NSUInteger i = [_ids indexOfObject:identifier];
	if (i == NSNotFound)
		return;
	[_views[identifier] removeFromSuperview];
	[_views removeObjectForKey:identifier];
	[_ids removeObjectAtIndex:i];
	[_titles removeObjectAtIndex:i];
	if ([_selected isEqualToString:identifier]) {
		_selected = nil;
		_title.stringValue = @"";
		if (_ids.count)
			[self selectPanel:_ids[MIN(i, _ids.count - 1)]];
	}
	[self rebuildTabs];
}

- (void)tabChanged:(id)sender
{
	NSInteger i = _tabs.selectedSegment;
	if (i >= 0 && i < (NSInteger)_ids.count)
		[self selectPanel:_ids[(NSUInteger)i]];
}

- (void)closeSelected:(id)sender
{
	NSString *ident = _selected;
	if (!ident)
		return;
	[self removePanel:ident];
	if (_onPanelClosed)
		_onPanelClosed(ident);
}

@end
