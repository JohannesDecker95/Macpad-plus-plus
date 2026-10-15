// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppDialogs.h"
#import "MppPrefs.h"
#import "MppLanguages.h"
#import "MppEncoding.h"
#import "MppMainWindowController.h"
#import "MppPaths.h"

// Small binding helper: every control writes back to MppPrefs through a block
@interface MppPrefBinding : NSObject
@property (nonatomic, copy) void (^apply)(id sender);
- (void)changed:(id)sender;
@end

@implementation MppPrefBinding
- (void)changed:(id)sender
{
	if (_apply)
		_apply(sender);
	[[MppPrefs shared] notifyChanged];
}
@end

@implementation MppPreferencesController {
	NSMutableArray<MppPrefBinding *> *_bindings;
}

static MppPreferencesController *g_prefs;

+ (void)show
{
	if (!g_prefs)
		g_prefs = [[MppPreferencesController alloc] init];
	[g_prefs.window center];
	[g_prefs showWindow:nil];
}

- (instancetype)init
{
	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 520)
	                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                                            backing:NSBackingStoreBuffered defer:YES];
	if ((self = [super initWithWindow:w])) {
		w.title = @"Preferences";
		w.delegate = self;
		_bindings = [NSMutableArray array];
		[self build];
	}
	return self;
}

- (MppPrefBinding *)bind:(void (^)(id sender))apply
{
	MppPrefBinding *b = [[MppPrefBinding alloc] init];
	b.apply = apply;
	[_bindings addObject:b];
	return b;
}

- (NSButton *)check:(NSString *)title value:(BOOL)value apply:(void (^)(BOOL on))apply
{
	MppPrefBinding *b = [self bind:^(NSButton *s) { apply(s.state == NSControlStateValueOn); }];
	NSButton *c = [NSButton checkboxWithTitle:title target:b action:@selector(changed:)];
	c.state = value ? NSControlStateValueOn : NSControlStateValueOff;
	return c;
}

- (NSPopUpButton *)popup:(NSArray<NSString *> *)items selected:(NSInteger)sel apply:(void (^)(NSInteger index, NSString *title))apply
{
	MppPrefBinding *b = [self bind:^(NSPopUpButton *s) { apply(s.indexOfSelectedItem, s.titleOfSelectedItem); }];
	NSPopUpButton *p = [[NSPopUpButton alloc] init];
	[p addItemsWithTitles:items];
	if (sel >= 0 && sel < (NSInteger)items.count)
		[p selectItemAtIndex:sel];
	p.target = b;
	p.action = @selector(changed:);
	return p;
}

- (NSView *)number:(NSInteger)value min:(NSInteger)min max:(NSInteger)max apply:(void (^)(NSInteger v))apply
{
	NSTextField *f = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%ld", (long)value]];
	NSStepper *st = [[NSStepper alloc] init];
	st.minValue = min;
	st.maxValue = max;
	st.integerValue = value;
	st.valueWraps = NO;
	__weak NSTextField *wf = f;
	__weak NSStepper *ws = st;
	MppPrefBinding *bf = [self bind:^(NSTextField *s) {
		NSInteger v = MIN(MAX(s.integerValue, min), max);
		ws.integerValue = v;
		apply(v);
	}];
	MppPrefBinding *bs = [self bind:^(NSStepper *s) {
		wf.integerValue = s.integerValue;
		apply(s.integerValue);
	}];
	f.target = bf;
	f.action = @selector(changed:);
	st.target = bs;
	st.action = @selector(changed:);
	f.translatesAutoresizingMaskIntoConstraints = NO;
	[f.widthAnchor constraintEqualToConstant:60].active = YES;
	NSStackView *s = [NSStackView stackViewWithViews:@[f, st]];
	s.spacing = 2;
	return s;
}

- (NSView *)text:(NSString *)value width:(CGFloat)width apply:(void (^)(NSString *v))apply
{
	MppPrefBinding *b = [self bind:^(NSTextField *s) { apply(s.stringValue); }];
	NSTextField *f = [NSTextField textFieldWithString:value ?: @""];
	f.target = b;
	f.action = @selector(changed:);
	f.translatesAutoresizingMaskIntoConstraints = NO;
	[f.widthAnchor constraintEqualToConstant:width].active = YES;
	return f;
}

static NSView *row(NSString *label, NSView *control)
{
	NSTextField *l = [NSTextField labelWithString:label];
	NSStackView *s = [NSStackView stackViewWithViews:@[l, control]];
	s.alignment = NSLayoutAttributeFirstBaseline;
	s.spacing = 8;
	return s;
}

static NSView *section(NSString *title)
{
	NSTextField *t = [NSTextField labelWithString:title];
	t.font = [NSFont boldSystemFontOfSize:12];
	return t;
}

- (NSView *)page:(NSArray<NSView *> *)views
{
	NSStackView *s = [NSStackView stackViewWithViews:views];
	s.orientation = NSUserInterfaceLayoutOrientationVertical;
	s.alignment = NSLayoutAttributeLeading;
	s.spacing = 8;
	s.edgeInsets = NSEdgeInsetsMake(16, 20, 16, 20);
	s.translatesAutoresizingMaskIntoConstraints = NO;
	NSView *container = [[NSView alloc] init];
	[container addSubview:s];
	[NSLayoutConstraint activateConstraints:@[
		[s.topAnchor constraintEqualToAnchor:container.topAnchor],
		[s.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[s.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
	]];
	return container;
}

- (void)build
{
	MppPrefs *p = [MppPrefs shared];
	NSTabView *tabs = [[NSTabView alloc] initWithFrame:self.window.contentView.bounds];
	tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	auto addTab = [&](NSString *title, NSView *v) {
		NSTabViewItem *it = [[NSTabViewItem alloc] initWithIdentifier:title];
		it.label = title;
		it.view = v;
		[tabs addTabViewItem:it];
	};

	// General
	addTab(@"General", [self page:@[
		section(@"Window"),
		[self check:@"Show toolbar" value:p.showToolbar apply:^(BOOL on) { p.showToolbar = on; }],
		[self check:@"Show status bar" value:p.showStatusBar apply:^(BOOL on) { p.showStatusBar = on; }],
		section(@"Tab Bar"),
		[self check:@"Show close button on each tab" value:p.showTabCloseButton apply:^(BOOL on) { p.showTabCloseButton = on; }],
		[self check:@"Double click to close document" value:p.doubleClickClosesTab apply:^(BOOL on) { p.doubleClickClosesTab = on; }],
		section(@"Recent Files History"),
		row(@"Max. number of entries:", [self number:p.maxRecentFiles min:0 max:50 apply:^(NSInteger v) { p.maxRecentFiles = v; }]),
	]]);

	// Editing
	addTab(@"Editing", [self page:@[
		section(@"Caret"),
		row(@"Width:", [self number:p.caretWidth min:1 max:4 apply:^(NSInteger v) { p.caretWidth = v; }]),
		row(@"Blink rate (ms, 0 = no blink):", [self number:p.caretBlinkRate min:0 max:2000 apply:^(NSInteger v) { p.caretBlinkRate = v; }]),
		section(@"Display"),
		[self check:@"Highlight current line" value:p.highlightCurrentLine apply:^(BOOL on) { p.highlightCurrentLine = on; }],
		[self check:@"Display line number" value:p.showLineNumbers apply:^(BOOL on) { p.showLineNumbers = on; }],
		[self check:@"Display bookmark margin" value:p.showBookmarkMargin apply:^(BOOL on) { p.showBookmarkMargin = on; }],
		[self check:@"Display change history" value:p.showChangeHistory apply:^(BOOL on) { p.showChangeHistory = on; }],
		row(@"Folder margin style:", [self popup:@[@"None", @"Simple", @"Arrow", @"Circle tree", @"Box tree"] selected:p.foldStyle
		                                   apply:^(NSInteger i, NSString *t) { p.foldStyle = (MppFoldStyle)i; }]),
		row(@"Vertical edge:", [self popup:@[@"None", @"Line", @"Background"] selected:p.edgeMode
		                             apply:^(NSInteger i, NSString *t) { p.edgeMode = (MppEdgeMode)i; }]),
		row(@"Edge column:", [self number:p.edgeColumn min:1 max:500 apply:^(NSInteger v) { p.edgeColumn = v; }]),
		section(@"Behaviour"),
		[self check:@"Enable multi-editing (⌘+click / selection)" value:p.multiEditing apply:^(BOOL on) { p.multiEditing = on; }],
		[self check:@"Enable virtual space" value:p.virtualSpace apply:^(BOOL on) { p.virtualSpace = on; }],
		[self check:@"Enable scrolling beyond last line" value:p.scrollBeyondLastLine apply:^(BOOL on) { p.scrollBeyondLastLine = on; }],
		[self check:@"Copy/cut the current line when nothing is selected" value:p.copyLineWithoutSelection
		      apply:^(BOOL on) { p.copyLineWithoutSelection = on; }],
	]]);

	// New Document
	NSMutableArray *langNames = [NSMutableArray arrayWithObject:@"Normal Text"];
	std::vector<MppLangType> langs = [MppLanguages.shared menuLanguages];
	NSInteger langSel = 0;
	for (size_t i = 0; i < langs.size(); ++i) {
		[langNames addObject:[MppLanguages menuNameForLang:langs[i]]];
		if (langs[i] == p.defaultDocLang)
			langSel = (NSInteger)i + 1;
	}
	std::vector<MppLangType> langsCopy = langs;
	NSArray *encNames = @[@"ANSI", @"UTF-8", @"UTF-8-BOM", @"UTF-16 BE BOM", @"UTF-16 LE BOM"];
	addTab(@"New Document", [self page:@[
		section(@"Format (Line ending)"),
		row(@"", [self popup:@[@"Windows (CR LF)", @"Macintosh (CR)", @"Unix (LF)"] selected:p.defaultDocEOL
		               apply:^(NSInteger i, NSString *t) { p.defaultDocEOL = (MppEOLType)i; }]),
		section(@"Encoding"),
		row(@"", [self popup:encNames selected:(NSInteger)[encNames indexOfObject:p.defaultDocEncoding]
		               apply:^(NSInteger i, NSString *t) { p.defaultDocEncoding = t; }]),
		section(@"Default language"),
		row(@"", [self popup:langNames selected:langSel apply:^(NSInteger i, NSString *t) {
			p.defaultDocLang = i == 0 ? L_TEXT : langsCopy[(size_t)i - 1];
		}]),
	]]);

	// Language
	addTab(@"Language", [self page:@[
		section(@"Tab Settings (default)"),
		row(@"Tab size:", [self number:p.tabSize min:1 max:16 apply:^(NSInteger v) { p.tabSize = v; }]),
		[self check:@"Replace by space" value:p.useSpaces apply:^(BOOL on) { p.useSpaces = on; }],
		[NSTextField wrappingLabelWithString:@"Python and YAML keep their language-specific tab settings from langs.xml."],
		section(@"Indentation"),
		[self check:@"Auto-indent" value:p.autoIndent apply:^(BOOL on) { p.autoIndent = on; }],
		section(@"SQL"),
		[self check:@"Treat backslash as escape character for SQL" value:p.backslashEscapeSQL
		      apply:^(BOOL on) { p.backslashEscapeSQL = on; }],
	]]);

	// Highlighting
	addTab(@"Highlighting", [self page:@[
		section(@"Smart Highlighting"),
		[self check:@"Enable" value:p.smartHighlighting apply:^(BOOL on) { p.smartHighlighting = on; }],
		[self check:@"Match case" value:p.smartHighlightMatchCase apply:^(BOOL on) { p.smartHighlightMatchCase = on; }],
		[self check:@"Match whole word only" value:p.smartHighlightWholeWord apply:^(BOOL on) { p.smartHighlightWholeWord = on; }],
		section(@"Highlight Matching Tags"),
		[self check:@"Enable" value:p.matchTagHighlighting apply:^(BOOL on) { p.matchTagHighlighting = on; }],
	]]);

	// Backup
	addTab(@"Backup", [self page:@[
		section(@"Session"),
		[self check:@"Remember current session for next launch" value:p.rememberSession apply:^(BOOL on) { p.rememberSession = on; }],
		[self check:@"Enable session snapshot and periodic backup" value:p.sessionSnapshot apply:^(BOOL on) { p.sessionSnapshot = on; }],
		row(@"Backup in every (seconds):", [self number:p.backupInterval min:1 max:3600 apply:^(NSInteger v) { p.backupInterval = v; }]),
		[NSTextField wrappingLabelWithString:@"With session snapshot, unsaved documents (including new ones) are kept when you quit "
		                                     @"and restored on the next launch, without asking to save them."],
	]]);

	// Auto-Completion
	addTab(@"Auto-Completion", [self page:@[
		section(@"Auto-Completion"),
		row(@"Mode:", [self popup:@[@"Disabled", @"Function completion", @"Word completion", @"Function and word completion"]
		                 selected:p.autoCompleteMode apply:^(NSInteger i, NSString *t) { p.autoCompleteMode = (MppAutoCompleteMode)i; }]),
		row(@"From the Nth character:", [self number:p.autoCompleteFromChar min:1 max:9 apply:^(NSInteger v) { p.autoCompleteFromChar = v; }]),
		[self check:@"Ignore numbers" value:p.autoCompleteIgnoreNumbers apply:^(BOOL on) { p.autoCompleteIgnoreNumbers = on; }],
		[self check:@"Function parameters hint on input" value:p.funcParamsHint apply:^(BOOL on) { p.funcParamsHint = on; }],
		section(@"Auto-Insert"),
		[self check:@"( )" value:p.autoCloseParen apply:^(BOOL on) { p.autoCloseParen = on; }],
		[self check:@"[ ]" value:p.autoCloseBracket apply:^(BOOL on) { p.autoCloseBracket = on; }],
		[self check:@"{ }" value:p.autoCloseCurly apply:^(BOOL on) { p.autoCloseCurly = on; }],
		[self check:@"\" \"" value:p.autoCloseDoubleQuote apply:^(BOOL on) { p.autoCloseDoubleQuote = on; }],
		[self check:@"' '" value:p.autoCloseQuote apply:^(BOOL on) { p.autoCloseQuote = on; }],
		[self check:@"html/xml close tag" value:p.autoCloseHtmlXmlTag apply:^(BOOL on) { p.autoCloseHtmlXmlTag = on; }],
	]]);

	// MISC.
	addTab(@"MISC.", [self page:@[
		section(@"File Status Auto-Detection"),
		row(@"", [self popup:@[@"Disabled", @"Enabled (ask before reload)", @"Update silently"] selected:p.fileAutoDetection
		               apply:^(NSInteger i, NSString *t) { p.fileAutoDetection = (MppFileAutoDetect)i; }]),
		[self check:@"Autodetect character encoding" value:p.autoDetectEncoding apply:^(BOOL on) { p.autoDetectEncoding = on; }],
		[self check:@"Trim trailing whitespace on save" value:p.trimTrailingOnSave apply:^(BOOL on) { p.trimTrailingOnSave = on; }],
		section(@"Date Time (customized format)"),
		row(@"Format:", [self text:p.dateTimeFormat width:240 apply:^(NSString *v) { p.dateTimeFormat = v; }]),
		section(@"Search Engine"),
		row(@"URL:", [self text:p.searchEngineURL width:380 apply:^(NSString *v) { p.searchEngineURL = v; }]),
	]]);

	[self.window.contentView addSubview:tabs];
}

@end

// =====================================================================================
// Style Configurator
// =====================================================================================

@implementation MppStyleConfiguratorController {
	NSPopUpButton *_themePopup;
	NSPopUpButton *_fontPopup;
	NSTextField *_fontSize;
	NSButton *_useMacFont, *_followAppearance;
	NSPopUpButton *_darkThemePopup;
	NSTableView *_langTable, *_styleTable;
	NSColorWell *_fg, *_bg;
	NSButton *_bold, *_italic, *_underline;
	NSTextField *_userExt;
	NSTextView *_userKeywords;
	NSTextField *_defaultExt;
	std::vector<std::string> _lexerNames;   // "" = Global Styles
	BOOL _loading;
}

static MppStyleConfiguratorController *g_style;

+ (void)show
{
	if (!g_style)
		g_style = [[MppStyleConfiguratorController alloc] init];
	[g_style reloadAll];
	[g_style.window center];
	[g_style showWindow:nil];
}

- (instancetype)init
{
	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 560)
	                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
	                                            backing:NSBackingStoreBuffered defer:YES];
	if ((self = [super initWithWindow:w])) {
		w.title = @"Style Configurator";
		w.delegate = self;
		[self build];
	}
	return self;
}

- (NSTableView *)makeTable:(NSString *)title
{
	NSTableView *t = [[NSTableView alloc] init];
	NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"c"];
	c.title = title;
	[t addTableColumn:c];
	t.dataSource = self;
	t.delegate = self;
	t.usesAlternatingRowBackgroundColors = YES;
	return t;
}

- (NSScrollView *)scroll:(NSView *)doc
{
	NSScrollView *sv = [[NSScrollView alloc] init];
	sv.documentView = doc;
	sv.hasVerticalScroller = YES;
	sv.translatesAutoresizingMaskIntoConstraints = NO;
	return sv;
}

- (void)build
{
	NSView *cv = self.window.contentView;
	_themePopup = [[NSPopUpButton alloc] init];
	_themePopup.target = self;
	_themePopup.action = @selector(themeChanged:);
	_darkThemePopup = [[NSPopUpButton alloc] init];
	_darkThemePopup.target = self;
	_darkThemePopup.action = @selector(themeChanged:);
	_followAppearance = [NSButton checkboxWithTitle:@"Follow macOS appearance; in Dark Mode use:" target:self action:@selector(themeChanged:)];

	_fontPopup = [[NSPopUpButton alloc] init];
	NSArray *fonts = [[NSFontManager.sharedFontManager availableFontFamilies] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	NSMutableArray *mono = [NSMutableArray array];
	for (NSString *f in fonts) {
		NSFont *font = [NSFont fontWithName:f size:12];
		if (font.isFixedPitch || [f containsString:@"Mono"] || [f containsString:@"Code"] || [f containsString:@"Courier"] || [f isEqualToString:@"Menlo"])
			[mono addObject:f];
	}
	[_fontPopup addItemsWithTitles:mono];
	[_fontPopup.menu addItem:NSMenuItem.separatorItem];
	[_fontPopup addItemsWithTitles:fonts];
	_fontPopup.target = self;
	_fontPopup.action = @selector(fontChanged:);
	_fontSize = [NSTextField textFieldWithString:@"12"];
	_fontSize.target = self;
	_fontSize.action = @selector(fontChanged:);
	[_fontSize.widthAnchor constraintEqualToConstant:44].active = YES;
	_useMacFont = [NSButton checkboxWithTitle:@"Use this font for all styles (recommended on macOS)" target:self action:@selector(fontChanged:)];

	_langTable = [self makeTable:@"Language"];
	_styleTable = [self makeTable:@"Style"];
	_fg = [[NSColorWell alloc] init];
	_bg = [[NSColorWell alloc] init];
	for (NSColorWell *w in @[_fg, _bg]) {
		w.target = self;
		w.action = @selector(styleEdited:);
		[w.widthAnchor constraintEqualToConstant:44].active = YES;
		[w.heightAnchor constraintEqualToConstant:24].active = YES;
	}
	_bold = [NSButton checkboxWithTitle:@"Bold" target:self action:@selector(styleEdited:)];
	_italic = [NSButton checkboxWithTitle:@"Italic" target:self action:@selector(styleEdited:)];
	_underline = [NSButton checkboxWithTitle:@"Underline" target:self action:@selector(styleEdited:)];
	_defaultExt = [NSTextField labelWithString:@""];
	_userExt = [NSTextField textFieldWithString:@""];
	_userExt.target = self;
	_userExt.action = @selector(userExtEdited:);
	NSScrollView *kwScroll = [NSTextView scrollableTextView];
	_userKeywords = kwScroll.documentView;
	_userKeywords.font = [NSFont userFixedPitchFontOfSize:11];
	_userKeywords.delegate = (id)self;
	kwScroll.translatesAutoresizingMaskIntoConstraints = NO;

	NSButton *save = [NSButton buttonWithTitle:@"Save & Close" target:self action:@selector(saveAndClose:)];
	save.keyEquivalent = @"\r";
	NSButton *saveTheme = [NSButton buttonWithTitle:@"Save as Theme…" target:self action:@selector(saveAsTheme:)];
	NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];

	NSStackView *top1 = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"Select theme:"], _themePopup]];
	NSStackView *top2 = [NSStackView stackViewWithViews:@[_followAppearance, _darkThemePopup]];
	NSStackView *top3 = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"Editor font:"], _fontPopup,
	                                                      [NSTextField labelWithString:@"Size:"], _fontSize, _useMacFont]];
	NSStackView *colors = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"Foreground:"], _fg,
	                                                        [NSTextField labelWithString:@"Background:"], _bg]];
	NSStackView *fontStyle = [NSStackView stackViewWithViews:@[_bold, _italic, _underline]];
	NSStackView *ext = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"Default ext.:"], _defaultExt]];
	NSStackView *uext = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"User ext.:"], _userExt]];
	[_userExt.widthAnchor constraintEqualToConstant:200].active = YES;
	NSTextField *kwLabel = [NSTextField labelWithString:@"User-defined keywords:"];
	NSStackView *details = [NSStackView stackViewWithViews:@[colors, fontStyle, ext, uext, kwLabel, kwScroll]];
	details.orientation = NSUserInterfaceLayoutOrientationVertical;
	details.alignment = NSLayoutAttributeLeading;
	details.spacing = 10;
	details.translatesAutoresizingMaskIntoConstraints = NO;
	NSStackView *buttons = [NSStackView stackViewWithViews:@[saveTheme, cancel, save]];

	NSScrollView *langScroll = [self scroll:_langTable], *styleScroll = [self scroll:_styleTable];
	for (NSView *v in @[top1, top2, top3, langScroll, styleScroll, details, buttons]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[cv addSubview:v];
	}
	[NSLayoutConstraint activateConstraints:@[
		[top1.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
		[top1.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
		[top2.centerYAnchor constraintEqualToAnchor:top1.centerYAnchor],
		[top2.leadingAnchor constraintEqualToAnchor:top1.trailingAnchor constant:24],
		[top3.topAnchor constraintEqualToAnchor:top1.bottomAnchor constant:10],
		[top3.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
		[langScroll.topAnchor constraintEqualToAnchor:top3.bottomAnchor constant:14],
		[langScroll.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
		[langScroll.widthAnchor constraintEqualToConstant:180],
		[langScroll.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-14],
		[styleScroll.topAnchor constraintEqualToAnchor:langScroll.topAnchor],
		[styleScroll.leadingAnchor constraintEqualToAnchor:langScroll.trailingAnchor constant:10],
		[styleScroll.widthAnchor constraintEqualToConstant:220],
		[styleScroll.bottomAnchor constraintEqualToAnchor:langScroll.bottomAnchor],
		[details.topAnchor constraintEqualToAnchor:langScroll.topAnchor],
		[details.leadingAnchor constraintEqualToAnchor:styleScroll.trailingAnchor constant:16],
		[details.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
		[details.bottomAnchor constraintEqualToAnchor:langScroll.bottomAnchor],
		[kwScroll.widthAnchor constraintEqualToAnchor:details.widthAnchor],
		[kwScroll.heightAnchor constraintGreaterThanOrEqualToConstant:120],
		[buttons.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
		[buttons.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-14],
	]];
}

- (void)reloadAll
{
	_loading = YES;
	self.window.title = [NSString stringWithFormat:@"Style Configurator — editing \"%@\"", [MppLanguages.shared currentThemeName]];
	MppPrefs *p = [MppPrefs shared];
	NSArray *names = [MppLanguages.shared themeNames];
	[_themePopup removeAllItems];
	[_themePopup addItemsWithTitles:names];
	[_themePopup selectItemWithTitle:p.themeName];
	[_darkThemePopup removeAllItems];
	[_darkThemePopup addItemsWithTitles:names];
	[_darkThemePopup selectItemWithTitle:p.darkThemeName];
	_followAppearance.state = p.followSystemAppearance ? NSControlStateValueOn : NSControlStateValueOff;
	[_fontPopup selectItemWithTitle:p.macFontName];
	_fontSize.integerValue = p.macFontSize;
	_useMacFont.state = p.useMacFont ? NSControlStateValueOn : NSControlStateValueOff;

	MppTheme *t = [MppLanguages.shared theme];
	_lexerNames.clear();
	_lexerNames.push_back("");
	std::vector<std::pair<std::string, std::string>> sorted;
	for (const auto &kv : t->lexers)
		if (kv.first != "searchResult")
			sorted.emplace_back(kv.second.desc.empty() ? kv.first : kv.second.desc, kv.first);
	std::sort(sorted.begin(), sorted.end(), [](auto &a, auto &b) { return strcasecmp(a.first.c_str(), b.first.c_str()) < 0; });
	for (auto &s : sorted)
		_lexerNames.push_back(s.second);
	[_langTable reloadData];
	[_langTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[_styleTable reloadData];
	[_styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	_loading = NO;
	[self showSelectedStyle];
}

- (std::vector<MppStyle> *)currentStyles
{
	MppTheme *t = [MppLanguages.shared theme];
	NSInteger li = _langTable.selectedRow;
	if (li <= 0)
		return &t->globals;
	auto it = t->lexers.find(_lexerNames[(size_t)li]);
	return it == t->lexers.end() ? nullptr : &it->second.styles;
}

- (MppStyle *)currentStyle
{
	std::vector<MppStyle> *styles = [self currentStyles];
	NSInteger si = _styleTable.selectedRow;
	if (!styles || si < 0 || si >= (NSInteger)styles->size())
		return nullptr;
	return &(*styles)[(size_t)si];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
	if (tv == _langTable)
		return (NSInteger)_lexerNames.size();
	std::vector<MppStyle> *s = [self currentStyles];
	return s ? (NSInteger)s->size() : 0;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	if (tv == _langTable) {
		if (row == 0)
			return @"Global Styles";
		const MppLexerStyler *ls = [MppLanguages.shared theme]->lexer(_lexerNames[(size_t)row]);
		return ls && !ls->desc.empty() ? @(ls->desc.c_str()) : @(_lexerNames[(size_t)row].c_str());
	}
	std::vector<MppStyle> *s = [self currentStyles];
	return s ? @((*s)[(size_t)row].name.c_str()) : @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	if (_loading)
		return;
	if (n.object == _langTable) {
		[_styleTable reloadData];
		[_styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
	[self showSelectedStyle];
}

- (void)showSelectedStyle
{
	MppStyle *s = [self currentStyle];
	_loading = YES;
	_fg.enabled = s && (s->colorStyle & COLORSTYLE_FOREGROUND);
	_bg.enabled = s && (s->colorStyle & COLORSTYLE_BACKGROUND);
	if (s) {
		_fg.color = MppColorFromSci(s->fgColor);
		_bg.color = MppColorFromSci(s->bgColor);
		const int fs = s->fontStyle < 0 ? 0 : s->fontStyle;
		_bold.state = (fs & FONTSTYLE_BOLD) ? NSControlStateValueOn : NSControlStateValueOff;
		_italic.state = (fs & FONTSTYLE_ITALIC) ? NSControlStateValueOn : NSControlStateValueOff;
		_underline.state = (fs & FONTSTYLE_UNDERLINE) ? NSControlStateValueOn : NSControlStateValueOff;
		_userKeywords.string = @(s->keywords.c_str());
		_userKeywords.editable = s->keywordClass >= 0;
	}
	NSInteger li = _langTable.selectedRow;
	const BOOL isLexer = li > 0;
	_userExt.enabled = isLexer;
	if (isLexer) {
		MppTheme *t = [MppLanguages.shared theme];
		auto it = t->lexers.find(_lexerNames[(size_t)li]);
		_userExt.stringValue = it != t->lexers.end() ? @(it->second.userExt.c_str()) : @"";
		NSString *defExt = @"";
		for (int i = 0; i < L_EXTERNAL; ++i)
			if (_lexerNames[(size_t)li] == g_mppLangNameInfo[i].langName)
				if (const MppLangDef *d = [MppLanguages.shared langDefForType:(MppLangType)i]) {
					NSMutableArray *a = [NSMutableArray array];
					for (auto &e : d->exts)
						[a addObject:@(e.c_str())];
					defExt = [a componentsJoinedByString:@" "];
				}
		_defaultExt.stringValue = defExt;
	} else {
		_userExt.stringValue = @"";
		_defaultExt.stringValue = @"";
	}
	_loading = NO;
}

- (void)applyLive
{
	[MppMainWindowController.shared restyleAllViews];
}

- (void)styleEdited:(id)sender
{
	if (_loading)
		return;
	MppStyle *s = [self currentStyle];
	if (!s)
		return;
	if (sender == _fg)
		s->fgColor = MppSciFromColor(_fg.color);
	else if (sender == _bg)
		s->bgColor = MppSciFromColor(_bg.color);
	else {
		int fs = 0;
		if (_bold.state == NSControlStateValueOn) fs |= FONTSTYLE_BOLD;
		if (_italic.state == NSControlStateValueOn) fs |= FONTSTYLE_ITALIC;
		if (_underline.state == NSControlStateValueOn) fs |= FONTSTYLE_UNDERLINE;
		s->fontStyle = fs;
	}
	[self applyLive];
}

- (void)textDidChange:(NSNotification *)n
{
	MppStyle *s = [self currentStyle];
	if (s && s->keywordClass >= 0) {
		s->keywords = _userKeywords.string.UTF8String;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyLive) object:nil];
		[self performSelector:@selector(applyLive) withObject:nil afterDelay:0.5];
	}
}

- (void)userExtEdited:(id)sender
{
	NSInteger li = _langTable.selectedRow;
	if (li <= 0)
		return;
	MppTheme *t = [MppLanguages.shared theme];
	auto it = t->lexers.find(_lexerNames[(size_t)li]);
	if (it != t->lexers.end())
		it->second.userExt = _userExt.stringValue.UTF8String;
}

- (void)themeChanged:(id)sender
{
	if (_loading)
		return;
	MppPrefs *p = [MppPrefs shared];
	p.themeName = _themePopup.titleOfSelectedItem;
	p.darkThemeName = _darkThemePopup.titleOfSelectedItem;
	p.followSystemAppearance = _followAppearance.state == NSControlStateValueOn;
	[MppMainWindowController.shared reloadThemeForced];
	[self reloadAll];
}

- (void)fontChanged:(id)sender
{
	if (_loading)
		return;
	MppPrefs *p = [MppPrefs shared];
	p.macFontName = _fontPopup.titleOfSelectedItem;
	p.macFontSize = MAX(6, MIN(_fontSize.integerValue, 72));
	p.useMacFont = _useMacFont.state == NSControlStateValueOn;
	[p notifyChanged];
}

// Write the in-memory theme back to an XML file (updating the original document)
- (BOOL)writeThemeTo:(NSString *)dest
{
	MppTheme *t = [MppLanguages.shared theme];
	NSData *data = [NSData dataWithContentsOfFile:@(t->path.c_str())];
	NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil] : nil;
	if (!doc)
		return NO;
	auto hex = [](int c) { return [NSString stringWithFormat:@"%02X%02X%02X", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF]; };
	auto writeStyle = [&](NSXMLElement *e, const MppStyle &s) {
		if (s.colorStyle & COLORSTYLE_FOREGROUND)
			[e addAttribute:[NSXMLNode attributeWithName:@"fgColor" stringValue:hex(s.fgColor)]];
		if (s.colorStyle & COLORSTYLE_BACKGROUND)
			[e addAttribute:[NSXMLNode attributeWithName:@"bgColor" stringValue:hex(s.bgColor)]];
		if (s.fontStyle >= 0)
			[e addAttribute:[NSXMLNode attributeWithName:@"fontStyle" stringValue:[NSString stringWithFormat:@"%d", s.fontStyle]]];
		if (s.keywordClass >= 0)
			e.stringValue = @(s.keywords.c_str());
	};
	for (NSXMLElement *lt in [doc nodesForXPath:@"/*/LexerStyles/LexerType" error:nil]) {
		NSString *name = [[lt attributeForName:@"name"] stringValue];
		const MppLexerStyler *ls = t->lexer(name.UTF8String);
		if (!ls)
			continue;
		[lt addAttribute:[NSXMLNode attributeWithName:@"ext" stringValue:@(ls->userExt.c_str())]];
		for (NSXMLElement *ws in [lt elementsForName:@"WordsStyle"]) {
			const MppStyle *s = ls->findByID([[[ws attributeForName:@"styleID"] stringValue] intValue]);
			if (s)
				writeStyle(ws, *s);
		}
	}
	for (NSXMLElement *ws in [doc nodesForXPath:@"/*/GlobalStyles/WidgetStyle" error:nil]) {
		const MppStyle *s = t->global([[[ws attributeForName:@"name"] stringValue] UTF8String] ?: "");
		if (s)
			writeStyle(ws, *s);
	}
	NSData *out = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
	[[NSFileManager defaultManager] createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES
	                                           attributes:nil error:nil];
	return [out writeToFile:dest atomically:YES];
}

- (NSString *)destinationForCurrentTheme
{
	NSString *name = [MppLanguages.shared currentThemeName];
	if ([name hasPrefix:@"Default ("])
		return [MppPaths.userDataDirectory stringByAppendingPathComponent:@"stylers.xml"];
	return [[MppPaths.userDataDirectory stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:
	        [name stringByAppendingPathExtension:@"xml"]];
}

- (void)saveAndClose:(id)sender
{
	if (![self writeThemeTo:[self destinationForCurrentTheme]]) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"The theme could not be saved.";
		[a runModal];
		return;
	}
	[self.window orderOut:nil];
}

- (void)saveAsTheme:(id)sender
{
	NSString *name = MppAskString(@"Save as Theme", @"Theme name:", @"My Theme");
	if (!name.length)
		return;
	NSString *dest = [[MppPaths.userDataDirectory stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:
	                  [name stringByAppendingPathExtension:@"xml"]];
	if ([self writeThemeTo:dest]) {
		[MppPrefs shared].themeName = name;
		[MppMainWindowController.shared reloadThemeForced];
		[self reloadAll];
	}
}

- (void)cancel:(id)sender
{
	// discard edits: reload the theme from disk
	[MppMainWindowController.shared reloadThemeForced];
	[self.window orderOut:nil];
}

@end
