// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppUserLangEditor.h"
#import "MppUserLang.h"
#import "MppUserLangModel.h"
#import "MppMainWindowController.h"
#include <string>

// ---- small layout helpers -------------------------------------------------------------------------

static NSTextField *udlLabel(NSString *s)
{
	return [NSTextField labelWithString:s];
}

static NSTextField *udlHeader(NSString *s)
{
	NSTextField *t = [NSTextField labelWithString:s];
	t.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
	return t;
}

static NSStackView *udlStack(NSArray<NSView *> *views, BOOL vertical, CGFloat spacing)
{
	NSStackView *s = [NSStackView stackViewWithViews:views];
	s.orientation = vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal;
	s.alignment = vertical ? NSLayoutAttributeLeading : NSLayoutAttributeFirstBaseline;
	s.spacing = spacing;
	return s;
}

@implementation MppUserLangEditor {
	NSPopUpButton *_langPopup;
	NSButton *_ignoreCase, *_foldCompact, *_foldComments;
	NSButton *_prefix[SCE_USER_TOTAL_KEYWORD_GROUPS];
	NSButton *_pureLC[3], *_decSep[3];
	NSButton *_removeButton, *_renameButton;
	NSMutableDictionary<NSString *, NSView *> *_fields;   // key -> NSTextField / NSTextView
	NSTabView *_tabs;
	NSString *_name;
	BOOL _loading;
}

+ (instancetype)shared
{
	static MppUserLangEditor *s;
	if (!s)
		s = [[MppUserLangEditor alloc] init];
	return s;
}

- (instancetype)init
{
	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 640)
	                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                                                    NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
	                                            backing:NSBackingStoreBuffered defer:YES];
	w.title = @"User Defined Language";
	w.minSize = NSMakeSize(820, 560);
	w.releasedWhenClosed = NO;
	if ((self = [super initWithWindow:w])) {
		w.delegate = self;
		_fields = [NSMutableDictionary dictionary];
		[self build];
		[w center];
		w.frameAutosaveName = @"UserDefineLanguageWindow";
	}
	return self;
}

- (NSString *)languageName
{
	return _name;
}

// ---- building the window ----------------------------------------------------------------------------

- (NSTextField *)field:(NSString *)key width:(CGFloat)width
{
	NSTextField *f = [NSTextField textFieldWithString:@""];
	f.delegate = self;
	f.identifier = key;
	f.font = [NSFont userFixedPitchFontOfSize:12];
	f.translatesAutoresizingMaskIntoConstraints = NO;
	if (width > 0)
		[f.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
	_fields[key] = f;
	return f;
}

- (NSScrollView *)textArea:(NSString *)key height:(CGFloat)height
{
	NSScrollView *sv = [NSTextView scrollableTextView];
	NSTextView *tv = sv.documentView;
	tv.font = [NSFont userFixedPitchFontOfSize:12];
	tv.richText = NO;
	tv.allowsUndo = YES;
	tv.automaticQuoteSubstitutionEnabled = NO;
	tv.automaticDashSubstitutionEnabled = NO;
	tv.automaticTextReplacementEnabled = NO;
	tv.automaticSpellingCorrectionEnabled = NO;
	tv.continuousSpellCheckingEnabled = NO;
	tv.delegate = self;
	tv.identifier = key;
	sv.borderType = NSBezelBorder;
	sv.translatesAutoresizingMaskIntoConstraints = NO;
	[sv.heightAnchor constraintEqualToConstant:height].active = YES;
	_fields[key] = tv;
	return sv;
}

- (NSButton *)stylerButton:(int)styleID
{
	NSButton *b = [NSButton buttonWithTitle:@"Styler…" target:self action:@selector(editStyle:)];
	b.tag = styleID;
	b.controlSize = NSControlSizeSmall;
	b.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
	return b;
}

- (NSButton *)check:(NSString *)title
{
	return [NSButton checkboxWithTitle:title target:self action:@selector(optionChanged:)];
}

- (NSView *)groupTitled:(NSString *)title styler:(int)styleID rows:(NSArray<NSArray<NSView *> *> *)rows
{
	NSGridView *g = [NSGridView gridViewWithViews:rows];
	g.rowSpacing = 6;
	g.columnSpacing = 8;
	[g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
	g.rowAlignment = NSGridRowAlignmentFirstBaseline;
	[g setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
	NSMutableArray *head = [NSMutableArray arrayWithObject:udlHeader(title)];
	if (styleID >= 0)
		[head addObject:[self stylerButton:styleID]];
	NSStackView *s = udlStack(@[udlStack(head, NO, 8), g], YES, 6);
	return s;
}

- (NSView *)pageWithContent:(NSView *)content
{
	NSView *page = [[NSView alloc] init];
	content.translatesAutoresizingMaskIntoConstraints = NO;
	[page addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[content.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:16],
		[content.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-16],
		[content.topAnchor constraintEqualToAnchor:page.topAnchor constant:12],
		[content.bottomAnchor constraintLessThanOrEqualToAnchor:page.bottomAnchor constant:-12],
	]];
	return page;
}

- (NSView *)folderPage
{
	_foldCompact = [self check:@"Fold compact (fold empty lines too)"];
	NSMutableArray *groups = [NSMutableArray array];
	NSArray *titles = @[@"Folding in code 1 style:", @"Folding in code 2 style (separators needed):", @"Folding in comment style:"];
	const int styles[] = {SCE_USER_STYLE_FOLDER_IN_CODE1, SCE_USER_STYLE_FOLDER_IN_CODE2, SCE_USER_STYLE_FOLDER_IN_COMMENT};
	for (int g = 0; g < 3; ++g) {
		const int base = SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN + g * 3;
		NSArray *rows = @[
			@[udlLabel(@"Open:"), [self field:[NSString stringWithFormat:@"kw%d", base] width:300]],
			@[udlLabel(@"Middle:"), [self field:[NSString stringWithFormat:@"kw%d", base + 1] width:300]],
			@[udlLabel(@"Close:"), [self field:[NSString stringWithFormat:@"kw%d", base + 2] width:300]],
		];
		[groups addObject:[self groupTitled:titles[g] styler:styles[g] rows:rows]];
	}
	NSView *def = udlStack(@[udlHeader(@"Default style:"), [self stylerButton:SCE_USER_STYLE_DEFAULT]], NO, 8);
	NSStackView *col = udlStack([@[def, _foldCompact] arrayByAddingObjectsFromArray:groups], YES, 16);
	for (NSView *v in groups)
		[v.widthAnchor constraintEqualToAnchor:col.widthAnchor].active = YES;
	return [self pageWithContent:col];
}

- (NSView *)keywordsPage
{
	static NSString *const ordinals[] = {@"1st", @"2nd", @"3rd", @"4th", @"5th", @"6th", @"7th", @"8th"};
	NSMutableArray *cells = [NSMutableArray array];
	for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i) {
		_prefix[i] = [self check:@"Prefix mode"];
		_prefix[i].tag = i;
		NSView *head = udlStack(@[udlHeader([NSString stringWithFormat:@"%@ group", ordinals[i]]),
		                          [self stylerButton:SCE_USER_STYLE_KEYWORD1 + i], _prefix[i]], NO, 8);
		NSScrollView *area = [self textArea:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_KEYWORDS1 + i] height:90];
		NSStackView *cell = udlStack(@[head, area], YES, 4);
		[area.widthAnchor constraintEqualToAnchor:cell.widthAnchor].active = YES;
		[cells addObject:cell];
	}
	NSGridView *g = [NSGridView gridViewWithViews:@[@[cells[0], cells[1]], @[cells[2], cells[3]],
	                                                 @[cells[4], cells[5]], @[cells[6], cells[7]]]];
	g.rowSpacing = 12;
	g.columnSpacing = 16;
	NSView *page = [self pageWithContent:g];
	for (NSView *c in cells)
		[c.widthAnchor constraintEqualToAnchor:page.widthAnchor multiplier:0.5 constant:-24].active = YES;
	return page;
}

- (NSView *)commentPage
{
	NSArray *posTitles = @[@"Allow anywhere", @"Force at beginning of line", @"Allow preceding whitespace"];
	NSMutableArray *pos = [NSMutableArray array];
	for (int i = 0; i < 3; ++i) {
		_pureLC[i] = [NSButton radioButtonWithTitle:posTitles[i] target:self action:@selector(pureLCChanged:)];
		_pureLC[i].tag = i;
		[pos addObject:_pureLC[i]];
	}
	NSView *position = udlStack([@[udlHeader(@"Line comment position:")] arrayByAddingObjectsFromArray:pos], YES, 4);
	NSView *line = [self groupTitled:@"Comment line style:" styler:SCE_USER_STYLE_COMMENTLINE rows:@[
		@[udlLabel(@"Open:"), [self field:@"cm0" width:200]],
		@[udlLabel(@"Continue character:"), [self field:@"cm1" width:200]],
		@[udlLabel(@"Close:"), [self field:@"cm2" width:200]],
	]];
	_foldComments = [self check:@"Allow folding of comments"];
	NSView *block = [self groupTitled:@"Comment style:" styler:SCE_USER_STYLE_COMMENT rows:@[
		@[udlLabel(@"Open:"), [self field:@"cm3" width:200]],
		@[udlLabel(@"Close:"), [self field:@"cm4" width:200]],
	]];
	NSStackView *left = udlStack(@[position, line, _foldComments, block], YES, 16);

	NSArray *numTitles = @[@"Prefix 1:", @"Prefix 2:", @"Extras 1:", @"Extras 2:", @"Suffix 1:", @"Suffix 2:", @"Range:"];
	NSMutableArray *numRows = [NSMutableArray array];
	for (int i = 0; i < 7; ++i)
		[numRows addObject:@[udlLabel(numTitles[(NSUInteger)i]),
		                     [self field:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_NUMBER_PREFIX1 + i] width:200]]];
	NSView *numbers = [self groupTitled:@"Number style:" styler:SCE_USER_STYLE_NUMBER rows:numRows];
	NSArray *sepTitles = @[@"Dot", @"Comma", @"Both"];
	NSMutableArray *seps = [NSMutableArray array];
	for (int i = 0; i < 3; ++i) {
		_decSep[i] = [NSButton radioButtonWithTitle:sepTitles[i] target:self action:@selector(decSepChanged:)];
		_decSep[i].tag = i;
		[seps addObject:_decSep[i]];
	}
	NSView *dec = udlStack(@[udlHeader(@"Decimal separator:"), udlStack(seps, NO, 12)], YES, 4);
	NSStackView *right = udlStack(@[numbers, dec], YES, 16);
	// two top-aligned columns that keep their natural heights
	NSView *cols = [[NSView alloc] init];
	for (NSView *v in @[left, right]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[cols addSubview:v];
		[v.topAnchor constraintEqualToAnchor:cols.topAnchor].active = YES;
		[v.bottomAnchor constraintLessThanOrEqualToAnchor:cols.bottomAnchor].active = YES;
	}
	[NSLayoutConstraint activateConstraints:@[
		[left.leadingAnchor constraintEqualToAnchor:cols.leadingAnchor],
		[left.trailingAnchor constraintLessThanOrEqualToAnchor:cols.centerXAnchor constant:-16],
		[right.leadingAnchor constraintEqualToAnchor:cols.centerXAnchor],
		[right.trailingAnchor constraintLessThanOrEqualToAnchor:cols.trailingAnchor],
	]];
	NSLayoutConstraint *h = [cols.heightAnchor constraintEqualToConstant:0];
	h.priority = NSLayoutPriorityDefaultLow;   // as small as the taller column allows
	h.active = YES;
	return [self pageWithContent:cols];
}

- (NSView *)operatorsPage
{
	NSView *ops = [self groupTitled:@"Operators style:" styler:SCE_USER_STYLE_OPERATOR rows:@[
		@[udlLabel(@"Operators 1:"), [self field:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_OPERATORS1] width:420]],
		@[udlLabel(@"Operators 2 (separators required):"), [self field:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_OPERATORS2] width:420]],
	]];
	NSMutableArray *rows = [NSMutableArray arrayWithObject:@[udlLabel(@""), udlHeader(@"Open"), udlHeader(@"Escape"), udlHeader(@"Close"), udlLabel(@"")]];
	for (int d = 0; d < SCE_USER_TOTAL_DELIMITERS; ++d)
		[rows addObject:@[udlLabel([NSString stringWithFormat:@"Delimiter %d style:", d + 1]),
		                  [self field:[NSString stringWithFormat:@"dl%d", d * 3] width:150],
		                  [self field:[NSString stringWithFormat:@"dl%d", d * 3 + 1] width:70],
		                  [self field:[NSString stringWithFormat:@"dl%d", d * 3 + 2] width:150],
		                  [self stylerButton:SCE_USER_STYLE_DELIMITER1 + d]]];
	NSGridView *g = [NSGridView gridViewWithViews:rows];
	g.rowSpacing = 6;
	g.columnSpacing = 8;
	g.rowAlignment = NSGridRowAlignmentFirstBaseline;
	[g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
	NSView *delims = udlStack(@[udlHeader(@"Delimiters (with escape character and nesting):"), g], YES, 6);
	return [self pageWithContent:udlStack(@[ops, delims], YES, 20)];
}

- (void)build
{
	NSView *cv = self.window.contentView;
	_langPopup = [[NSPopUpButton alloc] init];
	_langPopup.target = self;
	_langPopup.action = @selector(languageSelected:);
	[_langPopup.widthAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
	NSButton *create = [NSButton buttonWithTitle:@"Create New…" target:self action:@selector(createNew:)];
	NSButton *saveAs = [NSButton buttonWithTitle:@"Save As…" target:self action:@selector(saveAs:)];
	_renameButton = [NSButton buttonWithTitle:@"Rename…" target:self action:@selector(rename:)];
	_removeButton = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(remove:)];
	NSButton *import = [NSButton buttonWithTitle:@"Import…" target:self action:@selector(import:)];
	NSButton *exportB = [NSButton buttonWithTitle:@"Export…" target:self action:@selector(export:)];
	NSStackView *top = udlStack(@[udlLabel(@"User language:"), _langPopup, create, saveAs, _renameButton, _removeButton, import, exportB], NO, 8);
	_ignoreCase = [self check:@"Ignore case"];
	NSTextField *ext = [self field:@"ext" width:200];
	[ext.widthAnchor constraintLessThanOrEqualToConstant:320].active = YES;
	NSStackView *top2 = udlStack(@[udlLabel(@"Ext.:"), ext, _ignoreCase,
	                               udlLabel(@"(extensions separated by spaces, without the dot)")], NO, 8);

	_tabs = [[NSTabView alloc] init];
	NSArray *titles = @[@"Folder & Default", @"Keywords Lists", @"Comment & Number", @"Operators & Delimiters"];
	NSArray *pages = @[[self folderPage], [self keywordsPage], [self commentPage], [self operatorsPage]];
	for (NSUInteger i = 0; i < titles.count; ++i) {
		NSTabViewItem *it = [[NSTabViewItem alloc] initWithIdentifier:titles[i]];
		it.label = titles[i];
		it.view = pages[i];
		[_tabs addTabViewItem:it];
	}
	for (NSView *v in @[top, top2, _tabs]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[cv addSubview:v];
	}
	[NSLayoutConstraint activateConstraints:@[
		[top.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
		[top.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
		[top.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
		[top2.topAnchor constraintEqualToAnchor:top.bottomAnchor constant:10],
		[top2.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
		[top2.trailingAnchor constraintLessThanOrEqualToAnchor:cv.trailingAnchor constant:-16],
		[_tabs.topAnchor constraintEqualToAnchor:top2.bottomAnchor constant:10],
		[_tabs.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
		[_tabs.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[_tabs.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
	]];
}

// ---- model <-> controls -------------------------------------------------------------------------------

- (void)showLanguage:(NSString *)name
{
	[self reloadLanguageList:name ?: _name];
	[self showWindow:nil];
}

- (void)reloadLanguageList:(NSString *)select
{
	NSArray *names = MppUserLangManager.shared.languageNames;
	[_langPopup removeAllItems];
	[_langPopup addItemsWithTitles:names];
	if (select && [names containsObject:select])
		[_langPopup selectItemWithTitle:select];
	_name = _langPopup.titleOfSelectedItem;
	[self loadLanguage];
}

static NSString *str(const std::string &s)
{
	return @(s.c_str()) ?: @"";
}

- (void)setFieldText:(NSString *)text key:(NSString *)key
{
	NSView *v = _fields[key];
	if ([v isKindOfClass:[NSTextView class]])
		((NSTextView *)v).string = text;
	else
		((NSTextField *)v).stringValue = text;
}

- (NSString *)fieldText:(NSString *)key
{
	NSView *v = _fields[key];
	if ([v isKindOfClass:[NSTextView class]])
		return ((NSTextView *)v).string;
	return ((NSTextField *)v).stringValue;
}

- (void)loadLanguage
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	_loading = YES;
	const BOOL enabled = l != nullptr;
	for (NSString *key in _fields) {
		NSView *v = _fields[key];
		if ([v isKindOfClass:[NSTextView class]])
			((NSTextView *)v).editable = enabled;
		else
			((NSTextField *)v).enabled = enabled;
		[self setFieldText:@"" key:key];
	}
	_removeButton.enabled = enabled && ![MppUserLangManager.shared isBundledLanguage:_name];
	_renameButton.enabled = enabled;
	self.window.title = enabled ? [NSString stringWithFormat:@"User Defined Language – %@", _name] : @"User Defined Language";
	if (!l) {
		_loading = NO;
		return;
	}
	NSMutableArray *exts = [NSMutableArray array];
	for (const auto &e : l->exts)
		[exts addObject:str(e)];
	[self setFieldText:[exts componentsJoinedByString:@" "] key:@"ext"];
	for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) {
		NSString *key = [NSString stringWithFormat:@"kw%d", i];
		if (_fields[key])
			[self setFieldText:str(l->keywordLists[i]) key:key];
	}
	for (int i = 0; i < 5; ++i) {
		char p[3];
		snprintf(p, sizeof p, "%02d", i);
		[self setFieldText:str(MppUdlGetPrefixed(l->keywordLists[SCE_USER_KWLIST_COMMENTS], p)) key:[NSString stringWithFormat:@"cm%d", i]];
	}
	for (int i = 0; i < 24; ++i) {
		char p[3];
		snprintf(p, sizeof p, "%02d", i);
		[self setFieldText:str(MppUdlGetPrefixed(l->keywordLists[SCE_USER_KWLIST_DELIMITERS], p)) key:[NSString stringWithFormat:@"dl%d", i]];
	}
	auto on = [](bool b) { return b ? NSControlStateValueOn : NSControlStateValueOff; };
	_ignoreCase.state = on(l->caseIgnored);
	_foldCompact.state = on(l->foldCompact);
	_foldComments.state = on(l->allowFoldOfComments);
	for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i)
		_prefix[i].state = on(l->isPrefix[i]);
	for (int i = 0; i < 3; ++i) {
		_pureLC[i].state = on(l->forcePureLC == i);
		_decSep[i].state = on(l->decimalSeparator == i);
	}
	_loading = NO;
}

- (void)commitField:(NSString *)key
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	if (!l || _loading)
		return;
	NSString *text = [self fieldText:key];
	if ([key isEqualToString:@"ext"]) {
		l->exts.clear();
		for (NSString *e in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
			if (e.length)
				l->exts.push_back([e hasPrefix:@"."] ? [e substringFromIndex:1].lowercaseString.UTF8String : e.lowercaseString.UTF8String);
	} else if ([key hasPrefix:@"kw"]) {
		const int i = [key substringFromIndex:2].intValue;
		if (i >= 0 && i < SCE_USER_KWLIST_TOTAL)
			l->keywordLists[i] = text.UTF8String;
	} else if ([key hasPrefix:@"cm"] || [key hasPrefix:@"dl"]) {
		const BOOL comments = [key hasPrefix:@"cm"];
		const int n = comments ? 5 : 24;
		std::string parts[24];
		for (int i = 0; i < n; ++i)
			parts[i] = [self fieldText:[NSString stringWithFormat:@"%@%d", comments ? @"cm" : @"dl", i]].UTF8String;
		l->keywordLists[comments ? SCE_USER_KWLIST_COMMENTS : SCE_USER_KWLIST_DELIMITERS] = MppUdlSetPrefixed(parts, n);
	}
	[MppUserLangManager.shared languageDidChange:_name];
}

- (void)setText:(NSString *)text forField:(NSString *)key
{
	[self setFieldText:text key:key];
	[self commitField:key];
}

- (NSString *)textForField:(NSString *)key
{
	return _fields[key] ? [self fieldText:key] : nil;
}

- (void)controlTextDidChange:(NSNotification *)n
{
	NSTextField *f = n.object;
	if (f.identifier)
		[self commitField:f.identifier];
}

- (void)textDidChange:(NSNotification *)n
{
	NSTextView *tv = n.object;
	if (tv.identifier)
		[self commitField:tv.identifier];
}

- (void)optionChanged:(NSButton *)b
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	if (!l)
		return;
	const bool on = b.state == NSControlStateValueOn;
	if (b == _ignoreCase)
		l->caseIgnored = on;
	else if (b == _foldCompact)
		l->foldCompact = on;
	else if (b == _foldComments)
		l->allowFoldOfComments = on;
	else
		for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i)
			if (b == _prefix[i])
				l->isPrefix[i] = on;
	[MppUserLangManager.shared languageDidChange:_name];
}

- (void)pureLCChanged:(NSButton *)b
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	if (!l)
		return;
	l->forcePureLC = (int)b.tag;
	for (int i = 0; i < 3; ++i)
		_pureLC[i].state = i == b.tag ? NSControlStateValueOn : NSControlStateValueOff;
	[MppUserLangManager.shared languageDidChange:_name];
}

- (void)decSepChanged:(NSButton *)b
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	if (!l)
		return;
	l->decimalSeparator = (int)b.tag;
	for (int i = 0; i < 3; ++i)
		_decSep[i].state = i == b.tag ? NSControlStateValueOn : NSControlStateValueOff;
	[MppUserLangManager.shared languageDidChange:_name];
}

// ---- language list actions -------------------------------------------------------------------------

- (void)languageSelected:(id)sender
{
	_name = _langPopup.titleOfSelectedItem;
	[self loadLanguage];
}

- (NSString *)askName:(NSString *)title initial:(NSString *)initial
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = title;
	[a addButtonWithTitle:@"OK"];
	[a addButtonWithTitle:@"Cancel"];
	NSTextField *f = [NSTextField textFieldWithString:initial ?: @""];
	f.frame = NSMakeRect(0, 0, 260, 24);
	a.accessoryView = f;
	a.window.initialFirstResponder = f;
	if ([a runModal] != NSAlertFirstButtonReturn)
		return nil;
	NSString *name = [f.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if (!name.length)
		return nil;
	if ([MppUserLangManager.shared.languageNames containsObject:name]) {
		NSAlert *e = [[NSAlert alloc] init];
		e.messageText = [NSString stringWithFormat:@"A user defined language named \"%@\" already exists.", name];
		[e runModal];
		return nil;
	}
	return name;
}

- (void)createNew:(id)sender
{
	NSString *name = [self askName:@"Name of the new language:" initial:@""];
	if (name && [MppUserLangManager.shared createLanguage:name copyOf:nil])
		[self reloadLanguageList:name];
}

- (void)saveAs:(id)sender
{
	if (!_name)
		return;
	NSString *name = [self askName:@"Save the current language as:" initial:[_name stringByAppendingString:@" copy"]];
	if (name && [MppUserLangManager.shared createLanguage:name copyOf:_name])
		[self reloadLanguageList:name];
}

- (void)rename:(id)sender
{
	if (!_name)
		return;
	NSString *name = [self askName:@"New name:" initial:_name];
	if (name && [MppUserLangManager.shared renameLanguage:_name to:name])
		[self reloadLanguageList:name];
}

- (void)remove:(id)sender
{
	if (!_name || [MppUserLangManager.shared isBundledLanguage:_name])
		return;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = [NSString stringWithFormat:@"Remove the user defined language \"%@\"?", _name];
	a.informativeText = @"Its definition file is deleted. Documents using it switch to Normal Text.";
	[a addButtonWithTitle:@"Remove"];
	[a addButtonWithTitle:@"Cancel"];
	a.buttons.firstObject.hasDestructiveAction = YES;
	if ([a runModal] != NSAlertFirstButtonReturn)
		return;
	[MppUserLangManager.shared removeLanguage:_name];
	[self reloadLanguageList:nil];
}

- (void)import:(id)sender
{
	NSOpenPanel *p = [NSOpenPanel openPanel];
	p.allowsMultipleSelection = YES;
	p.allowedFileTypes = @[@"xml"];
	if ([p runModal] != NSModalResponseOK)
		return;
	NSSet *before = [NSSet setWithArray:MppUserLangManager.shared.languageNames];
	NSInteger n = 0;
	for (NSURL *u in p.URLs)
		n += [MppUserLangManager.shared importFile:u.path];
	NSString *added = nil;
	for (NSString *name in MppUserLangManager.shared.languageNames)
		if (![before containsObject:name])
			added = name;
	[self reloadLanguageList:added ?: _name];
	if (!n) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"No user defined language found in the selected file(s).";
		[a runModal];
	}
}

- (void)export:(id)sender
{
	if (!_name)
		return;
	NSSavePanel *p = [NSSavePanel savePanel];
	p.nameFieldStringValue = [[_name stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByAppendingString:@".xml"];
	if ([p runModal] != NSModalResponseOK)
		return;
	if (![MppUserLangManager.shared exportLanguage:_name toPath:p.URL.path]) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"The language could not be exported.";
		[a runModal];
	}
}

// ---- Styler ----------------------------------------------------------------------------------------------

static NSString *const kNestingNames[] = {
	@"Delimiter 1", @"Delimiter 2", @"Delimiter 3", @"Delimiter 4", @"Delimiter 5", @"Delimiter 6", @"Delimiter 7",
	@"Delimiter 8", @"Comment", @"Comment line", @"Keyword 1", @"Keyword 2", @"Keyword 3", @"Keyword 4",
	@"Keyword 5", @"Keyword 6", @"Keyword 7", @"Keyword 8", @"Operators 1", @"Operators 2", @"Numbers"};
static const int kNestingMasks[] = {
	SCE_USER_MASK_NESTING_DELIMITER1, SCE_USER_MASK_NESTING_DELIMITER2, SCE_USER_MASK_NESTING_DELIMITER3,
	SCE_USER_MASK_NESTING_DELIMITER4, SCE_USER_MASK_NESTING_DELIMITER5, SCE_USER_MASK_NESTING_DELIMITER6,
	SCE_USER_MASK_NESTING_DELIMITER7, SCE_USER_MASK_NESTING_DELIMITER8, SCE_USER_MASK_NESTING_COMMENT,
	SCE_USER_MASK_NESTING_COMMENT_LINE, SCE_USER_MASK_NESTING_KEYWORD1, SCE_USER_MASK_NESTING_KEYWORD2,
	SCE_USER_MASK_NESTING_KEYWORD3, SCE_USER_MASK_NESTING_KEYWORD4, SCE_USER_MASK_NESTING_KEYWORD5,
	SCE_USER_MASK_NESTING_KEYWORD6, SCE_USER_MASK_NESTING_KEYWORD7, SCE_USER_MASK_NESTING_KEYWORD8,
	SCE_USER_MASK_NESTING_OPERATORS1, SCE_USER_MASK_NESTING_OPERATORS2, SCE_USER_MASK_NESTING_NUMBERS};

- (void)editStyle:(NSButton *)sender
{
	UserLang *l = [MppUserLangManager.shared languageNamed:_name];
	if (!l)
		return;
	const int styleID = (int)sender.tag;
	const UdlStyle current = *l->findStyle(styleID);
	const MppStyle &st = current.style;
	// Only delimiters and comments can contain other styles
	const BOOL nestable = (styleID >= SCE_USER_STYLE_DELIMITER1 && styleID <= SCE_USER_STYLE_DELIMITER8) ||
	                      styleID == SCE_USER_STYLE_COMMENT || styleID == SCE_USER_STYLE_COMMENTLINE;

	NSPopUpButton *font = [[NSPopUpButton alloc] init];
	[font addItemWithTitle:@"(default)"];
	[font.menu addItem:NSMenuItem.separatorItem];
	[font addItemsWithTitles:[NSFontManager.sharedFontManager.availableFontFamilies
	                             sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
	if (!st.fontName.empty() && [font itemWithTitle:str(st.fontName)])
		[font selectItemWithTitle:str(st.fontName)];
	NSPopUpButton *size = [[NSPopUpButton alloc] init];
	[size addItemWithTitle:@"(default)"];
	for (int s : {5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36})
		[size addItemWithTitle:[NSString stringWithFormat:@"%d", s]];
	if (st.fontSize > 0) {
		NSString *t = [NSString stringWithFormat:@"%d", st.fontSize];
		if (![size itemWithTitle:t])
			[size addItemWithTitle:t];
		[size selectItemWithTitle:t];
	}
	const int fs = st.fontStyle < 0 ? 0 : st.fontStyle;
	NSButton *bold = [NSButton checkboxWithTitle:@"Bold" target:nil action:nil];
	NSButton *italic = [NSButton checkboxWithTitle:@"Italic" target:nil action:nil];
	NSButton *underline = [NSButton checkboxWithTitle:@"Underline" target:nil action:nil];
	bold.state = (fs & FONTSTYLE_BOLD) ? NSControlStateValueOn : NSControlStateValueOff;
	italic.state = (fs & FONTSTYLE_ITALIC) ? NSControlStateValueOn : NSControlStateValueOff;
	underline.state = (fs & FONTSTYLE_UNDERLINE) ? NSControlStateValueOn : NSControlStateValueOff;

	NSColorWell *fg = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
	NSColorWell *bg = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
	fg.color = MppColorFromSci(st.fgColor);
	bg.color = MppColorFromSci(st.bgColor);
	for (NSColorWell *w in @[fg, bg]) {
		[w.widthAnchor constraintEqualToConstant:44].active = YES;
		[w.heightAnchor constraintEqualToConstant:24].active = YES;
	}
	NSButton *fgT = [NSButton checkboxWithTitle:@"Transparent" target:nil action:nil];
	NSButton *bgT = [NSButton checkboxWithTitle:@"Transparent" target:nil action:nil];
	fgT.state = (st.colorStyle & COLORSTYLE_FOREGROUND) ? NSControlStateValueOff : NSControlStateValueOn;
	bgT.state = (st.colorStyle & COLORSTYLE_BACKGROUND) ? NSControlStateValueOff : NSControlStateValueOn;

	NSGridView *grid = [NSGridView gridViewWithViews:@[
		@[udlLabel(@"Font name:"), font],
		@[udlLabel(@"Font size:"), size],
		@[udlLabel(@"Font style:"), udlStack(@[bold, italic, underline], NO, 12)],
		@[udlLabel(@"Foreground colour:"), udlStack(@[fg, fgT], NO, 10)],
		@[udlLabel(@"Background colour:"), udlStack(@[bg, bgT], NO, 10)],
	]];
	for (NSInteger r = 3; r <= 4; ++r) {   // colour wells have no baseline
		[grid rowAtIndex:r].rowAlignment = NSGridRowAlignmentNone;
		[grid rowAtIndex:r].yPlacement = NSGridCellPlacementCenter;
		((NSStackView *)[grid cellAtColumnIndex:1 rowIndex:r].contentView).alignment = NSLayoutAttributeCenterY;
	}
	grid.rowSpacing = 8;
	grid.columnSpacing = 8;
	grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
	[grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
	NSMutableArray<NSView *> *content = [NSMutableArray arrayWithObject:grid];
	NSMutableArray<NSButton *> *nestChecks = [NSMutableArray array];
	if (nestable) {
		const int count = sizeof(kNestingMasks) / sizeof(kNestingMasks[0]);
		for (int i = 0; i < count; ++i) {
			NSButton *c = [NSButton checkboxWithTitle:kNestingNames[i] target:nil action:nil];
			c.tag = kNestingMasks[i];
			c.state = (current.nesting & kNestingMasks[i]) ? NSControlStateValueOn : NSControlStateValueOff;
			[nestChecks addObject:c];
		}
		NSMutableArray *rows = [NSMutableArray array];
		for (int r = 0; r < 7; ++r)
			[rows addObject:@[nestChecks[(NSUInteger)r], nestChecks[(NSUInteger)r + 7], nestChecks[(NSUInteger)r + 14]]];
		NSGridView *ng = [NSGridView gridViewWithViews:rows];
		ng.rowSpacing = 4;
		ng.columnSpacing = 16;
		[content addObject:udlHeader(@"Nesting (styles allowed inside this one):")];
		[content addObject:ng];
	}
	NSStackView *body = udlStack(content, YES, 12);
	body.frame = NSMakeRect(0, 0, nestable ? 440 : 380, body.fittingSize.height);

	NSAlert *a = [[NSAlert alloc] init];
	static NSString *const titles[SCE_USER_STYLE_TOTAL_STYLES] = {
		@"Default", @"Comment", @"Comment line", @"Number", @"Keywords 1st group", @"Keywords 2nd group",
		@"Keywords 3rd group", @"Keywords 4th group", @"Keywords 5th group", @"Keywords 6th group",
		@"Keywords 7th group", @"Keywords 8th group", @"Operators", @"Folding in code 1", @"Folding in code 2",
		@"Folding in comment", @"Delimiter 1", @"Delimiter 2", @"Delimiter 3", @"Delimiter 4", @"Delimiter 5",
		@"Delimiter 6", @"Delimiter 7", @"Delimiter 8"};
	a.messageText = [NSString stringWithFormat:@"Styler: %@ style", titles[styleID]];
	a.accessoryView = body;
	[a addButtonWithTitle:@"OK"];
	[a addButtonWithTitle:@"Cancel"];
	[a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
		if (r != NSAlertFirstButtonReturn)
			return;
		UserLang *lang = [MppUserLangManager.shared languageNamed:self->_name];
		if (!lang)
			return;
		UdlStyle *us = lang->findStyle(styleID);
		MppStyle &s = us->style;
		s.fontName = font.indexOfSelectedItem > 0 ? font.titleOfSelectedItem.UTF8String : "";
		s.fontSize = size.indexOfSelectedItem > 0 ? size.titleOfSelectedItem.intValue : -1;
		s.fontStyle = (bold.state == NSControlStateValueOn ? FONTSTYLE_BOLD : 0) |
		              (italic.state == NSControlStateValueOn ? FONTSTYLE_ITALIC : 0) |
		              (underline.state == NSControlStateValueOn ? FONTSTYLE_UNDERLINE : 0);
		s.fgColor = MppSciFromColor(fg.color);
		s.bgColor = MppSciFromColor(bg.color);
		s.colorStyle = (fgT.state == NSControlStateValueOn ? 0 : COLORSTYLE_FOREGROUND) |
		               (bgT.state == NSControlStateValueOn ? 0 : COLORSTYLE_BACKGROUND);
		if (nestable) {
			int nesting = 0;
			for (NSButton *c in nestChecks)
				if (c.state == NSControlStateValueOn)
					nesting |= (int)c.tag;
			us->nesting = nesting;
		}
		[MppUserLangManager.shared languageDidChange:self->_name];
	}];
}

- (void)windowWillClose:(NSNotification *)n
{
	[self.window makeFirstResponder:nil];   // commits a field being edited
}

@end
