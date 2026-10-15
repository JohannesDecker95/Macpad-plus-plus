// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMainWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "MppStyler.h"
#import "MppPrefs.h"
#import "MppPaths.h"
#import "MppMenu.h"
#import "MppFindReplace.h"
#import "MppSearchResults.h"
#import "MppDock.h"
#import "MppMacro.h"
#import "MppPanels.h"
#import "MppDialogs.h"
#import "MppEditing.h"
#import "MppUserLang.h"
#import "MppUserLangEditor.h"
#include "Scintilla.h"

static MppMainWindowController *g_shared;

static NSString *const kPanelFunctionList = @"functionList";
static NSString *const kPanelDocList = @"docList";
static NSString *const kPanelFileBrowser = @"fileBrowser";
static NSString *const kPanelDocMap = @"docMap";
static NSString *const kPanelClipboard = @"clipboard";
static NSString *const kPanelCharPanel = @"charPanel";

@interface MppMainWindowController ()
@property (nonatomic, readwrite) MppEditPane *activePane;
@end

@implementation MppMainWindowController {
	NSSplitView *_outerSplit;     // content | search results
	NSSplitView *_topSplit;       // left dock | editors | right dock
	NSSplitView *_editorSplit;    // main view | sub view
	NSMutableArray<NSString *> *_recentlyClosed;
	NSTimer *_monitorTimer;
	NSTimer *_backupTimer;
	BOOL _checkingFiles;
	BOOL _quitting;
	NSString *_statusMessage;
	MppFunctionListPanel *_functionList;
	MppDocumentListPanel *_docList;
	MppFileBrowserPanel *_fileBrowser;
	MppDocumentMapPanel *_docMap;
	MppClipboardHistoryPanel *_clipboardPanel;
	MppCharacterPanel *_charPanel;
	BOOL _syncingScroll;
	NSString *_appliedThemeName;
	BOOL _distractionFree;
	NSDictionary *_savedLayoutBeforeDF;
}

+ (instancetype)shared
{
	return g_shared;
}

- (instancetype)init
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1200, 800)
	                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
	                                                         NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
	                                                 backing:NSBackingStoreBuffered
	                                                   defer:NO];
	if ((self = [super initWithWindow:window])) {
		g_shared = self;
		_recentlyClosed = [NSMutableArray array];
		window.delegate = self;
		window.minSize = NSMakeSize(500, 300);
		window.title = @"Macpad++";
		window.tabbingMode = NSWindowTabbingModeDisallowed;
		window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
		[window setFrameAutosaveName:@"MacpadPlusPlusMainWindow"];
		if (![window setFrameUsingName:@"MacpadPlusPlusMainWindow"])
			[window center];

		[self applyThemeForAppearance];
		[self buildLayout];
		[self buildToolbar];

		_findReplace = [[MppFindReplaceController alloc] initWithOwner:self];
		_macros = [[MppMacroManager alloc] init];

		NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
		[nc addObserver:self selector:@selector(documentChanged:) name:MppDocumentChangedNotification object:nil];
		[nc addObserver:self selector:@selector(prefsChanged:) name:MppPrefsChangedNotification object:nil];
		[nc addObserver:self selector:@selector(userLangChanged:) name:MppUserLangDidChangeNotification object:nil];
		[nc addObserver:self selector:@selector(appDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
		[NSDistributedNotificationCenter.defaultCenter addObserver:self selector:@selector(systemAppearanceChanged:)
		                                                     name:@"AppleInterfaceThemeChangedNotification" object:nil];

		_monitorTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(checkFilesTimer:)
		                                               userInfo:nil repeats:YES];
		[self resetBackupTimer];
		window.level = [MppPrefs shared].alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
	}
	return self;
}

// ---- Layout -------------------------------------------------------------------

- (NSSplitView *)makeSplit:(BOOL)vertical
{
	NSSplitView *s = [[NSSplitView alloc] init];
	s.vertical = vertical;
	s.dividerStyle = NSSplitViewDividerStyleThin;
	s.delegate = self;
	s.translatesAutoresizingMaskIntoConstraints = NO;
	return s;
}

- (void)buildLayout
{
	NSView *content = self.window.contentView;

	_mainPane = [[MppEditPane alloc] initWithFrame:NSMakeRect(0, 0, 600, 600)];
	_subPane = [[MppEditPane alloc] initWithFrame:NSMakeRect(0, 0, 600, 600)];
	for (MppEditPane *p in @[_mainPane, _subPane]) {
		p.delegate = self;
		[self configureEditor:p];
	}

	// NSSplitView arranged subviews must not carry autoresizing-mask constraints (they pin the size)
	for (NSView *v in @[_mainPane, _subPane])
		v.translatesAutoresizingMaskIntoConstraints = NO;

	_editorSplit = [self makeSplit:YES];
	[_editorSplit addArrangedSubview:_mainPane];
	[_editorSplit addArrangedSubview:_subPane];
	_subPane.hidden = YES;

	_leftDock = [[MppDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
	_rightDock = [[MppDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 260, 600)];
	_leftDock.hidden = YES;
	_rightDock.hidden = YES;
	_leftDock.translatesAutoresizingMaskIntoConstraints = NO;
	_rightDock.translatesAutoresizingMaskIntoConstraints = NO;
	__weak MppMainWindowController *weakSelf = self;
	void (^closed)(NSString *) = ^(NSString *ident) { [weakSelf dockPanelClosed:ident]; };
	_leftDock.onPanelClosed = closed;
	_rightDock.onPanelClosed = closed;

	_topSplit = [self makeSplit:YES];
	[_topSplit addArrangedSubview:_leftDock];
	[_topSplit addArrangedSubview:_editorSplit];
	[_topSplit addArrangedSubview:_rightDock];
	[_topSplit setHoldingPriority:NSLayoutPriorityDefaultLow - 10 forSubviewAtIndex:1];
	[_topSplit setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:0];
	[_topSplit setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:2];

	_searchResults = [[MppSearchResultsPanel alloc] initWithFrame:NSMakeRect(0, 0, 800, 200)];
	_searchResults.owner = self;
	_searchResults.hidden = YES;
	_searchResults.translatesAutoresizingMaskIntoConstraints = NO;
	_searchResults.onClose = ^{ [weakSelf showSearchResults:NO]; };

	_outerSplit = [self makeSplit:NO];
	[_outerSplit addArrangedSubview:_topSplit];
	[_outerSplit addArrangedSubview:_searchResults];
	[_outerSplit setHoldingPriority:NSLayoutPriorityDefaultLow - 10 forSubviewAtIndex:0];
	[_outerSplit setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:1];

	_statusBar = [[MppStatusBar alloc] initWithFrame:NSMakeRect(0, 0, 800, 22)];
	_statusBar.translatesAutoresizingMaskIntoConstraints = NO;
	_statusBar.menuProvider = ^NSMenu *(MppStatusField field) { return [weakSelf statusMenuForField:field]; };

	[content addSubview:_outerSplit];
	[content addSubview:_statusBar];
	NSLayoutConstraint *statusHeight = [_statusBar.heightAnchor constraintEqualToConstant:22];
	statusHeight.identifier = @"statusHeight";
	[NSLayoutConstraint activateConstraints:@[
		[_outerSplit.topAnchor constraintEqualToAnchor:content.topAnchor],
		[_outerSplit.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[_outerSplit.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[_outerSplit.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor],
		[_statusBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
		[_statusBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
		[_statusBar.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
		statusHeight,
	]];
	_statusBar.hidden = ![MppPrefs shared].showStatusBar;
	statusHeight.constant = _statusBar.hidden ? 0 : 22;

	self.activePane = _mainPane;
	_mainPane.active = YES;
}

- (void)configureEditor:(MppEditPane *)pane
{
	__weak MppMainWindowController *weakSelf = self;
	__weak MppEditPane *weakPane = pane;
	pane.editor.contextMenuProvider = ^NSMenu *(MppScintillaView *v) {
		[weakSelf setActivePaneIfNeeded:weakPane];
		return [weakSelf editorContextMenu];
	};
	pane.editor.keyDownHandler = ^BOOL(MppScintillaView *v, NSEvent *e) {
		return [weakSelf editorKeyDown:e pane:weakPane];
	};
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
	return proposedMin + 120;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
	return proposedMax - 120;
}

// Re-layout a split view after showing a subview, then place a divider (asynchronously, once
// NSSplitView has resized its subviews to the real bounds)
- (void)split:(NSSplitView *)split placeDivider:(NSInteger)index at:(CGFloat (^)(NSSplitView *))position
{
	[split adjustSubviews];
	dispatch_async(dispatch_get_main_queue(), ^{
		[split adjustSubviews];
		[split setPosition:position(split) ofDividerAtIndex:index];
	});
}

- (void)updatePaneVisibility
{
	const BOOL mainEmpty = _mainPane.documents.count == 0;
	const BOOL subEmpty = _subPane.documents.count == 0;
	const BOOL subWasHidden = _subPane.hidden;
	_mainPane.hidden = mainEmpty && !subEmpty;
	_subPane.hidden = subEmpty;
	if (subWasHidden && !_subPane.hidden && !_mainPane.hidden)
		[self split:_editorSplit placeDivider:0 at:^CGFloat(NSSplitView *sv) { return sv.bounds.size.width / 2; }];
	else
		[_editorSplit adjustSubviews];
	if (_activePane.hidden || _activePane.documents.count == 0)
		[self setActivePaneIfNeeded:(_activePane == _mainPane) ? _subPane : _mainPane];
}

// ---- Theme ----------------------------------------------------------------------

- (BOOL)systemIsDark
{
	NSAppearanceName n = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [n isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSString *)effectiveThemeName
{
	MppPrefs *p = [MppPrefs shared];
	if (p.followSystemAppearance && [self systemIsDark])
		return p.darkThemeName.length ? p.darkThemeName : @"DarkModeDefault";
	return p.themeName;
}

- (void)applyThemeForAppearance
{
	NSString *name = [self effectiveThemeName];
	if ([name isEqualToString:_appliedThemeName])
		return;
	_appliedThemeName = name;
	[MppLanguages.shared loadThemeAtPath:[MppLanguages.shared pathForThemeName:name]];
}

- (void)systemAppearanceChanged:(NSNotification *)n
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *before = self->_appliedThemeName;
		[self applyThemeForAppearance];
		if (![before isEqualToString:self->_appliedThemeName])
			[self restyleAllViews];
	});
}

- (void)restyleAllViews
{
	[self applyThemeForAppearance];
	for (MppEditPane *p in @[_mainPane, _subPane]) {
		[p restyleCurrentDocument];
		[p.tabBar setNeedsDisplay:YES];
	}
	[_searchResults applyTheme];
	[_docMap documentChanged];
}

// A user defined language was edited, renamed or removed in "Define your language"
- (void)userLangChanged:(NSNotification *)n
{
	NSString *name = n.userInfo[@"name"], *oldName = n.userInfo[@"oldName"];
	for (MppDocument *d in self.allDocuments) {
		if (d.lang != L_USER || !oldName || ![d.userLangName isEqualToString:oldName])
			continue;
		if (name)
			d.userLangName = name;
		else
			[self setLanguage:L_TEXT forDocument:d];
	}
	for (MppEditPane *p in @[_mainPane, _subPane]) {
		MppDocument *d = p.currentDocument;
		if (d.lang == L_USER && [d.userLangName isEqualToString:name])
			[p restyleCurrentDocument];
	}
	[self updateStatusBar];
}

- (void)reloadThemeForced
{
	_appliedThemeName = nil;
	[self restyleAllViews];
}

// ---- Toolbar --------------------------------------------------------------------

static NSArray *toolbarDefs()
{
	// identifier, label, SF symbol, command
	static NSArray *defs = @[
		@[@"new", @"New", @"doc.badge.plus", @(CMD_FILE_NEW)],
		@[@"open", @"Open", @"folder", @(CMD_FILE_OPEN)],
		@[@"save", @"Save", @"square.and.arrow.down", @(CMD_FILE_SAVE)],
		@[@"saveAll", @"Save All", @"square.and.arrow.down.on.square", @(CMD_FILE_SAVEALL)],
		@[@"close", @"Close", @"xmark.square", @(CMD_FILE_CLOSE)],
		@[@"closeAll", @"Close All", @"xmark.square.fill", @(CMD_FILE_CLOSEALL)],
		@[@"print", @"Print", @"printer", @(CMD_FILE_PRINT)],
		@[@"cut", @"Cut", @"scissors", @(-1)],
		@[@"copy", @"Copy", @"doc.on.doc", @(-2)],
		@[@"paste", @"Paste", @"doc.on.clipboard", @(-3)],
		@[@"undo", @"Undo", @"arrow.uturn.backward", @(-4)],
		@[@"redo", @"Redo", @"arrow.uturn.forward", @(-5)],
		@[@"find", @"Find", @"magnifyingglass", @(CMD_SEARCH_FIND)],
		@[@"replace", @"Replace", @"arrow.2.squarepath", @(CMD_SEARCH_REPLACE)],
		@[@"zoomIn", @"Zoom In", @"plus.magnifyingglass", @(CMD_VIEW_ZOOMIN)],
		@[@"zoomOut", @"Zoom Out", @"minus.magnifyingglass", @(CMD_VIEW_ZOOMOUT)],
		@[@"syncV", @"Sync V", @"arrow.up.and.down.square", @(CMD_VIEW_SYNSCROLLV)],
		@[@"syncH", @"Sync H", @"arrow.left.and.right.square", @(CMD_VIEW_SYNSCROLLH)],
		@[@"wrap", @"Word Wrap", @"text.append", @(CMD_VIEW_WRAP)],
		@[@"allChars", @"All Chars", @"paragraphsign", @(CMD_VIEW_ALL_CHARACTERS)],
		@[@"indentGuide", @"Indent Guide", @"increase.indent", @(CMD_VIEW_INDENT_GUIDE)],
		@[@"docMap", @"Doc Map", @"map", @(CMD_VIEW_DOC_MAP)],
		@[@"docList", @"Doc List", @"list.bullet.rectangle", @(CMD_VIEW_DOCLIST)],
		@[@"funcList", @"Function List", @"function", @(CMD_VIEW_FUNC_LIST)],
		@[@"fileBrowser", @"Workspace", @"sidebar.left", @(CMD_VIEW_FILEBROWSER)],
		@[@"monitoring", @"Monitoring", @"eye", @(CMD_VIEW_MONITORING)],
		@[@"record", @"Record", @"record.circle", @(CMD_MACRO_START_RECORDING)],
		@[@"stopRecord", @"Stop", @"stop.circle", @(CMD_MACRO_STOP_RECORDING)],
		@[@"play", @"Play", @"play.circle", @(CMD_MACRO_PLAYBACK)],
		@[@"playMulti", @"Run Multiple", @"forward.circle", @(CMD_MACRO_RUN_MULTI)],
		@[@"saveMacro", @"Save Macro", @"tray.and.arrow.down", @(CMD_MACRO_SAVE_CURRENT)],
	];
	return defs;
}

- (void)buildToolbar
{
	NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"MppMainToolbar"];
	tb.delegate = self;
	tb.displayMode = NSToolbarDisplayModeIconOnly;
	tb.allowsUserCustomization = YES;
	tb.autosavesConfiguration = YES;
	self.window.toolbar = tb;
	self.window.toolbarStyle = NSWindowToolbarStyleUnified;
	tb.visible = [MppPrefs shared].showToolbar;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
	NSMutableArray *a = [NSMutableArray array];
	for (NSArray *d in toolbarDefs())
		[a addObject:d[0]];
	[a addObjectsFromArray:@[NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier]];
	return a;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
	return @[@"new", @"open", @"save", @"saveAll", @"close", NSToolbarSpaceItemIdentifier, @"cut", @"copy", @"paste",
	         NSToolbarSpaceItemIdentifier, @"undo", @"redo", NSToolbarSpaceItemIdentifier, @"find", @"replace",
	         NSToolbarSpaceItemIdentifier, @"zoomIn", @"zoomOut", NSToolbarSpaceItemIdentifier, @"wrap", @"allChars",
	         @"indentGuide", NSToolbarFlexibleSpaceItemIdentifier, @"docMap", @"docList", @"funcList", @"fileBrowser",
	         NSToolbarSpaceItemIdentifier, @"record", @"stopRecord", @"play", @"playMulti"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)ident willBeInsertedIntoToolbar:(BOOL)flag
{
	for (NSArray *d in toolbarDefs()) {
		if (![d[0] isEqualToString:ident])
			continue;
		NSToolbarItem *it = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
		it.label = d[1];
		it.paletteLabel = d[1];
		it.toolTip = d[1];
		it.image = [NSImage imageWithSystemSymbolName:d[2] accessibilityDescription:d[1]];
		const int cmd = [d[3] intValue];
		it.target = nil;
		switch (cmd) {
			case -1: it.action = @selector(cut:); break;
			case -2: it.action = @selector(copy:); break;
			case -3: it.action = @selector(paste:); break;
			case -4: it.action = @selector(undo:); break;
			case -5: it.action = @selector(redo:); break;
			default: it.action = @selector(mppCommand:); it.tag = cmd; break;
		}
		it.bordered = YES;
		return it;
	}
	return nil;
}

// ---- Accessors ------------------------------------------------------------------

- (MppEditPane *)otherPane
{
	return _activePane == _mainPane ? _subPane : _mainPane;
}

- (MppScintillaView *)activeEditor
{
	return _activePane.editor;
}

- (MppDocument *)currentDocument
{
	return _activePane.currentDocument;
}

- (sptr_t)sci:(unsigned int)msg
{
	return [_activePane sci:msg];
}

- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w
{
	return [_activePane sci:msg w:w];
}

- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w l:(sptr_t)l
{
	return [_activePane sci:msg w:w l:l];
}

- (std::string)textRangeFrom:(sptr_t)start to:(sptr_t)end
{
	if (end <= start)
		return std::string();
	std::string s((size_t)(end - start), '\0');
	Sci_TextRangeFull tr;
	tr.chrg.cpMin = start;
	tr.chrg.cpMax = end;
	std::vector<char> buf((size_t)(end - start) + 1);
	tr.lpstrText = buf.data();
	[self sci:SCI_GETTEXTRANGEFULL w:0 l:(sptr_t)&tr];
	return std::string(buf.data(), (size_t)(end - start));
}

- (std::string)selectedText
{
	const sptr_t len = [self sci:SCI_GETSELTEXT w:0 l:0];
	if (len <= 0)
		return std::string();
	std::vector<char> buf((size_t)len + 1);
	[self sci:SCI_GETSELTEXT w:0 l:(sptr_t)buf.data()];
	return std::string(buf.data());
}

- (std::string)currentWordOrSelection
{
	if (![self sci:SCI_GETSELECTIONEMPTY])
		return [self selectedText];
	const sptr_t pos = [self sci:SCI_GETCURRENTPOS];
	const sptr_t s = [self sci:SCI_WORDSTARTPOSITION w:(uptr_t)pos l:1];
	const sptr_t e = [self sci:SCI_WORDENDPOSITION w:(uptr_t)pos l:1];
	return [self textRangeFrom:s to:e];
}

- (NSArray<MppDocument *> *)allDocuments
{
	NSMutableArray *a = [NSMutableArray arrayWithArray:_mainPane.documents];
	for (MppDocument *d in _subPane.documents)
		if (![a containsObject:d])
			[a addObject:d];
	return a;
}

- (MppEditPane *)paneForDocument:(MppDocument *)doc
{
	if ([_activePane indexOfDocument:doc] != NSNotFound)
		return _activePane;
	if ([self.otherPane indexOfDocument:doc] != NSNotFound)
		return self.otherPane;
	return nil;
}

- (MppDocumentMapPanel *)documentMapPanel
{
	return _docMap;
}

- (void)gotoLine:(sptr_t)line
{
	MppEditPane *pane = _activePane;
	[pane sci:SCI_ENSUREVISIBLEENFORCEPOLICY w:(uptr_t)line];
	[pane sci:SCI_GOTOLINE w:(uptr_t)line];
	const sptr_t first = [pane sci:SCI_GETFIRSTVISIBLELINE];
	const sptr_t onScreen = [pane sci:SCI_LINESONSCREEN];
	const sptr_t visLine = [pane sci:SCI_VISIBLEFROMDOCLINE w:(uptr_t)line];
	if (visLine < first + 2 || visLine > first + onScreen - 3)
		[pane sci:SCI_SETFIRSTVISIBLELINE w:(uptr_t)std::max<sptr_t>(0, visLine - onScreen / 3)];
	[self.window makeFirstResponder:pane.editor.content];
}

- (void)selectRangeFrom:(sptr_t)start to:(sptr_t)end
{
	MppEditPane *pane = _activePane;
	const sptr_t line = [pane sci:SCI_LINEFROMPOSITION w:(uptr_t)start];
	[pane sci:SCI_ENSUREVISIBLEENFORCEPOLICY w:(uptr_t)line];
	const sptr_t first = [pane sci:SCI_GETFIRSTVISIBLELINE];
	const sptr_t onScreen = [pane sci:SCI_LINESONSCREEN];
	const sptr_t visLine = [pane sci:SCI_VISIBLEFROMDOCLINE w:(uptr_t)line];
	if (visLine < first || visLine >= first + onScreen)
		[pane sci:SCI_SETFIRSTVISIBLELINE w:(uptr_t)std::max<sptr_t>(0, visLine - onScreen / 3)];
	[pane sci:SCI_SETSEL w:(uptr_t)start l:end];
	[pane sci:SCI_SCROLLRANGE w:(uptr_t)end l:start];
}

- (void)setActivePaneIfNeeded:(MppEditPane *)pane
{
	if (!pane || pane == _activePane)
		return;
	if (pane.documents.count == 0)
		return;
	_activePane.active = NO;
	self.activePane = pane;
	pane.active = YES;
	[self updateStatusBar];
	[self updateTitle];
	[_docList reload];
	[_functionList reload];
	[_docMap documentChanged];
}

// ---- Documents ------------------------------------------------------------------

- (BOOL)isPristineUntitled:(MppDocument *)d
{
	return d.isUntitled && !d.dirty && d.backupPath == nil &&
	       [MppDocumentManager.shared scratchMessage:SCI_GETLENGTH doc:d wParam:0 lParam:0] == 0;
}

- (MppDocument *)newDocument
{
	MppDocument *doc = [MppDocumentManager.shared createUntitledDocument];
	[_activePane addDocument:doc atIndex:-1 activate:YES];
	[self updatePaneVisibility];
	[self.window makeFirstResponder:_activePane.editor.content];
	return doc;
}

- (MppDocument *)openPath:(NSString *)path
{
	return [self openPath:path activate:YES];
}

- (MppDocument *)openPath:(NSString *)path activate:(BOOL)activate
{
	path = path.stringByStandardizingPath;
	BOOL isDir = NO;
	if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir) {
		[self openFolderAsWorkspace:path];
		return nil;
	}
	if (MppDocument *existing = [MppDocumentManager.shared documentForPath:path]) {
		if (activate)
			[self activateDocument:existing];
		return existing;
	}
	if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = [NSString stringWithFormat:@"\"%@\" doesn't exist. Create it?", path];
		[a addButtonWithTitle:@"Yes"];
		[a addButtonWithTitle:@"No"];
		if ([a runModal] != NSAlertFirstButtonReturn)
			return nil;
		if (![[NSData data] writeToFile:path options:0 error:nil]) {
			NSAlert *e = [[NSAlert alloc] init];
			e.messageText = [NSString stringWithFormat:@"Cannot create \"%@\".", path];
			[e runModal];
			return nil;
		}
	}
	NSError *err = nil;
	MppDocument *doc = [MppDocumentManager.shared openFile:path error:&err];
	if (!doc) {
		NSAlert *a = err ? [NSAlert alertWithError:err] : [[NSAlert alloc] init];
		if (!err)
			a.messageText = [NSString stringWithFormat:@"Cannot open file \"%@\".", path];
		[a runModal];
		[[MppPrefs shared] removeRecentFile:path];
		return nil;
	}
	// Replace an untouched "new 1" document
	MppDocument *pristine = nil;
	if (_activePane.documents.count == 1 && [self isPristineUntitled:_activePane.documents.firstObject] &&
	    [self.otherPane indexOfDocument:_activePane.documents.firstObject] == NSNotFound)
		pristine = _activePane.documents.firstObject;

	[_activePane addDocument:doc atIndex:-1 activate:activate];
	if (pristine) {
		[_activePane removeDocument:pristine];
		[MppDocumentManager.shared closeDocument:pristine];
	}
	[[MppPrefs shared] addRecentFile:path];
	[NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
	[_recentlyClosed removeObject:path];
	[self updatePaneVisibility];
	[_docList reload];
	return doc;
}

- (void)openPaths:(NSArray<NSString *> *)paths
{
	MppDocument *last = nil;
	for (NSString *p in paths)
		if (MppDocument *d = [self openPath:p activate:NO])
			last = d;
	if (last)
		[self activateDocument:last];
}

- (void)activateDocument:(MppDocument *)doc
{
	MppEditPane *pane = [self paneForDocument:doc];
	if (!pane)
		return;
	[self setActivePaneIfNeeded:pane];
	[pane activateDocument:doc];
	[self.window makeFirstResponder:pane.editor.content];
}

- (void)documentDisplayChanged:(MppDocument *)doc
{
	for (MppEditPane *p in @[_mainPane, _subPane])
		if (p.currentDocument == doc)
			[p restyleCurrentDocument];
	[self updateStatusBar];
	[self updateTitle];
}

- (void)setLanguage:(MppLangType)lang forDocument:(MppDocument *)doc
{
	doc.lang = lang;
	doc.langSetByUser = YES;
	[self documentDisplayChanged:doc];
	[_functionList reload];
}

// ---- Saving ---------------------------------------------------------------------

- (void)showError:(NSError *)err
{
	[[NSAlert alertWithError:err] runModal];
}

- (BOOL)writeDocument:(MppDocument *)doc toPath:(NSString *)path copy:(BOOL)copy
{
	if ([MppPrefs shared].trimTrailingOnSave && !copy) {
		MppEditPane *pane = [self paneForDocument:doc];
		if (pane && pane.currentDocument == doc)
			MppTrimTrailing(pane.editor);
	}
	NSError *err = nil;
	if ([MppDocumentManager.shared saveDocument:doc toPath:path copyOnly:copy lossy:NO error:&err])
		return YES;
	if ([err.domain isEqualToString:MppErrorDomain] && err.code == MppErrorUnencodable) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = err.localizedDescription;
		a.informativeText = @"Saving will replace those characters with \"?\". You can also convert the document to UTF-8 first (Encoding menu).";
		[a addButtonWithTitle:@"Save Anyway"];
		[a addButtonWithTitle:@"Convert to UTF-8 and Save"];
		[a addButtonWithTitle:@"Cancel"];
		NSModalResponse r = [a runModal];
		if (r == NSAlertThirdButtonReturn)
			return NO;
		if (r == NSAlertSecondButtonReturn) {
			MppEncoding e;
			e.mode = MppUniUTF8;
			doc.encoding = e;
		}
		err = nil;
		if ([MppDocumentManager.shared saveDocument:doc toPath:path copyOnly:copy lossy:YES error:&err])
			return YES;
	}
	if ([err.domain isEqualToString:NSCocoaErrorDomain] && err.code == NSFileWriteNoPermissionError) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = [NSString stringWithFormat:@"You don't have permission to save \"%@\".", path.lastPathComponent];
		a.informativeText = @"Do you want to save it with administrator privileges?";
		[a addButtonWithTitle:@"Save as Administrator"];
		[a addButtonWithTitle:@"Cancel"];
		if ([a runModal] == NSAlertFirstButtonReturn) {
			NSData *data = [MppDocumentManager.shared encodedContentOfDocument:doc lossy:YES];
			NSError *e2 = nil;
			if (data && [MppDocumentManager.shared saveDataWithAdminPrivileges:data toPath:path error:&e2])
				return YES;
			if (e2)
				[self showError:e2];
		}
		return NO;
	}
	if (err)
		[self showError:err];
	return NO;
}

- (BOOL)saveDocument:(MppDocument *)doc
{
	if (doc.isUntitled)
		return [self saveDocumentAs:doc copy:NO];
	if (doc.monitoring)
		return YES;
	BOOL ok = [self writeDocument:doc toPath:doc.filePath copy:NO];
	if (ok) {
		[self updateTitle];
		[_functionList reload];
	}
	return ok;
}

- (BOOL)saveDocumentAs:(MppDocument *)doc copy:(BOOL)copy
{
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.showsTagField = NO;
	panel.canCreateDirectories = YES;
	panel.extensionHidden = NO;
	panel.allowsOtherFileTypes = YES;
	if (doc.filePath) {
		panel.directoryURL = [NSURL fileURLWithPath:doc.filePath.stringByDeletingLastPathComponent];
		panel.nameFieldStringValue = doc.filePath.lastPathComponent;
	} else {
		panel.nameFieldStringValue = doc.displayName;
	}
	if (copy)
		panel.title = @"Save a Copy As";
	if ([panel runModal] != NSModalResponseOK)
		return NO;
	NSString *path = panel.URL.path;
	MppDocument *other = [MppDocumentManager.shared documentForPath:path];
	if (other && other != doc && !copy) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"The file is already opened in Macpad++. Close it first or choose another name.";
		[a runModal];
		return NO;
	}
	if (![self writeDocument:doc toPath:path copy:copy])
		return NO;
	if (!copy) {
		[[MppPrefs shared] addRecentFile:path];
		[self documentDisplayChanged:doc];
		[_docList reload];
	}
	return YES;
}

- (BOOL)saveAll
{
	for (MppDocument *d in [self allDocuments])
		if (d.dirty && ![self saveDocument:d])
			return NO;
	return YES;
}

// ---- Closing --------------------------------------------------------------------

// Returns NO if the user cancelled
- (BOOL)confirmCloseOfDirtyDocument:(MppDocument *)doc
{
	if (!doc.dirty)
		return YES;
	[self activateDocument:doc];
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = [NSString stringWithFormat:@"Save file \"%@\"?", doc.filePath ?: doc.displayName];
	[a addButtonWithTitle:@"Save"];
	[a addButtonWithTitle:@"Cancel"];
	NSButton *dont = [a addButtonWithTitle:@"Don't Save"];
	dont.keyEquivalent = @"d";
	dont.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	NSModalResponse r = [a runModal];
	if (r == NSAlertFirstButtonReturn)
		return [self saveDocument:doc];
	if (r == NSAlertSecondButtonReturn)
		return NO;
	return YES;
}

- (BOOL)closeDocument:(MppDocument *)doc inPane:(MppEditPane *)pane
{
	MppEditPane *other = (pane == _mainPane) ? _subPane : _mainPane;
	const BOOL cloned = [other indexOfDocument:doc] != NSNotFound;
	if (!cloned && ![self confirmCloseOfDirtyDocument:doc])
		return NO;

	if (!cloned && doc.filePath) {
		[_recentlyClosed removeObject:doc.filePath];
		[_recentlyClosed addObject:doc.filePath];
	}
	[pane removeDocument:doc];
	if (!cloned)
		[MppDocumentManager.shared closeDocument:doc];

	if (_mainPane.documents.count == 0 && _subPane.documents.count == 0) {
		MppDocument *fresh = [MppDocumentManager.shared createUntitledDocument];
		[_mainPane addDocument:fresh atIndex:-1 activate:YES];
		[self setActivePaneIfNeeded:_mainPane];
	}
	[self updatePaneVisibility];
	if (_activePane.currentDocument)
		[self editPane:_activePane didActivateDocument:_activePane.currentDocument];
	[_docList reload];
	return YES;
}

- (BOOL)closeDocuments:(NSArray<MppDocument *> *)docs
{
	for (MppDocument *d in [docs copy]) {
		MppEditPane *pane = [self paneForDocument:d];
		if (!pane)
			continue;
		if (![self closeDocument:d inPane:pane])
			return NO;
		// a cloned document lives in the other view too
		if (MppEditPane *p2 = [self paneForDocument:d])
			if (![self closeDocument:d inPane:p2])
				return NO;
	}
	return YES;
}

// ---- Status bar & title ---------------------------------------------------------

static NSString *grouped(sptr_t n)
{
	static NSNumberFormatter *f;
	if (!f) {
		f = [[NSNumberFormatter alloc] init];
		f.numberStyle = NSNumberFormatterDecimalStyle;
	}
	return [f stringFromNumber:@(n)];
}

- (void)updateStatusBar
{
	MppDocument *doc = self.currentDocument;
	if (!doc)
		return;
	NSString *langName = (doc.lang == L_USER && doc.userLangName.length)
	                         ? [NSString stringWithFormat:@"User Defined language file - %@", doc.userLangName]
	                         : [MppLanguages longNameForLang:doc.lang];
	[_statusBar setText:_statusMessage ?: langName forField:MppStatusDocType];
	const sptr_t len = [self sci:SCI_GETLENGTH];
	const sptr_t lines = [self sci:SCI_GETLINECOUNT];
	[_statusBar setText:[NSString stringWithFormat:@"length : %@    lines : %@", grouped(len), grouped(lines)]
	           forField:MppStatusDocSize];

	const sptr_t pos = [self sci:SCI_GETCURRENTPOS];
	const sptr_t line = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)pos];
	const sptr_t col = [self sci:SCI_GETCOLUMN w:(uptr_t)pos];
	NSString *cursor;
	const sptr_t nSel = [self sci:SCI_GETSELECTIONS];
	if ([self sci:SCI_GETSELECTIONEMPTY]) {
		cursor = [NSString stringWithFormat:@"Ln : %@    Col : %@    Pos : %@", grouped(line + 1), grouped(col + 1), grouped(pos + 1)];
	} else if ([self sci:SCI_SELECTIONISRECTANGLE] || nSel > 1) {
		sptr_t chars = 0;
		for (sptr_t i = 0; i < nSel; ++i)
			chars += [self sci:SCI_COUNTCHARACTERS w:(uptr_t)[self sci:SCI_GETSELECTIONNSTART w:(uptr_t)i]
			                l:[self sci:SCI_GETSELECTIONNEND w:(uptr_t)i]];
		cursor = [NSString stringWithFormat:@"Ln : %@    Col : %@    Sel : %@ | %@", grouped(line + 1), grouped(col + 1),
		                                    grouped(chars), grouped(nSel)];
	} else {
		const sptr_t s = [self sci:SCI_GETSELECTIONSTART], e = [self sci:SCI_GETSELECTIONEND];
		const sptr_t chars = [self sci:SCI_COUNTCHARACTERS w:(uptr_t)s l:e];
		const sptr_t l1 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)s], l2 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)e];
		cursor = [NSString stringWithFormat:@"Ln : %@    Col : %@    Sel : %@ | %@", grouped(line + 1), grouped(col + 1),
		                                    grouped(chars), grouped(l2 - l1 + 1)];
	}
	[_statusBar setText:cursor forField:MppStatusCursorPos];
	[_statusBar setText:doc.eolDisplayName forField:MppStatusEOL];
	[_statusBar setText:doc.encodingDisplayName forField:MppStatusEncoding];
	[_statusBar setText:[self sci:SCI_GETOVERTYPE] ? @"OVR" : @"INS" forField:MppStatusTypingMode];
}

- (void)setStatusMessage:(NSString *)msg
{
	_statusMessage = [msg copy];
	[self updateStatusBar];
	if (msg) {
		NSString *captured = _statusMessage;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (self->_statusMessage == captured) {
				self->_statusMessage = nil;
				[self updateStatusBar];
			}
		});
	}
}

- (void)updateTitle
{
	MppDocument *doc = self.currentDocument;
	if (!doc)
		return;
	// macOS style: file name as title, folder as subtitle
	self.window.title = [NSString stringWithFormat:@"%@%@", doc.dirty ? @"*" : @"", doc.displayName];
	NSString *sub = doc.filePath ? doc.filePath.stringByDeletingLastPathComponent.stringByAbbreviatingWithTildeInPath : @"Macpad++";
	if (_macros.recording)
		sub = [sub stringByAppendingString:@"  —  Recording macro…"];
	self.window.subtitle = sub;
	self.window.representedURL = doc.filePath ? [NSURL fileURLWithPath:doc.filePath] : nil;
	self.window.documentEdited = doc.dirty;
}

- (NSMenu *)statusMenuForField:(MppStatusField)field
{
	switch (field) {
		case MppStatusDocType: return [MppMenu languageMenu];
		case MppStatusEOL: return [MppMenu eolMenu];
		case MppStatusEncoding: return [MppMenu encodingMenu];
		default: return nil;
	}
}

// ---- Notifications --------------------------------------------------------------

- (void)documentChanged:(NSNotification *)n
{
	MppDocument *doc = n.object;
	for (MppEditPane *p in @[_mainPane, _subPane])
		if ([p indexOfDocument:doc] != NSNotFound)
			[p.tabBar setNeedsDisplay:YES];
	[_mainPane.tabBar reload];
	[_subPane.tabBar reload];
	if (doc == self.currentDocument) {
		[self updateTitle];
		[self updateStatusBar];
	}
	[_docList reload];
}

- (void)prefsChanged:(NSNotification *)n
{
	MppPrefs *p = [MppPrefs shared];
	self.window.toolbar.visible = p.showToolbar;
	_statusBar.hidden = !p.showStatusBar;
	for (NSLayoutConstraint *c in _statusBar.constraints)
		if ([c.identifier isEqualToString:@"statusHeight"])
			c.constant = _statusBar.hidden ? 0 : 22;
	self.window.level = p.alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
	[self resetBackupTimer];
	[self restyleAllViews];
}

- (void)editPane:(MppEditPane *)pane didActivateDocument:(MppDocument *)doc
{
	if (pane == _activePane || _activePane.documents.count == 0)
		[self setActivePaneIfNeeded:pane];
	if (pane != _activePane)
		return;
	[self updateTitle];
	[self updateStatusBar];
	[_functionList reload];
	[_docList reload];
	[_docMap documentChanged];
	MppSmartHighlight(pane.editor, YES);
}

- (void)editPane:(MppEditPane *)pane notification:(SCNotification *)n
{
	switch (n->nmhdr.code) {
		case SCN_FOCUSIN:
			[self setActivePaneIfNeeded:pane];
			break;
		case SCN_UPDATEUI:
			[self handleUpdateUI:n pane:pane];
			break;
		case SCN_CHARADDED:
			[self handleCharAdded:n pane:pane];
			break;
		case SCN_MARGINCLICK:
			if (n->margin == MPP_MARGIN_SYMBOL || n->margin == MPP_MARGIN_LINENUMBER || n->margin == MPP_MARGIN_CHANGEHISTORY) {
				const sptr_t line = [pane sci:SCI_LINEFROMPOSITION w:(uptr_t)n->position];
				MppToggleBookmark(pane.editor, line);
			}
			break;
		case SCN_MACRORECORD:
			[_macros recordNotification:n];
			break;
		case SCN_SAVEPOINTLEFT:
		case SCN_SAVEPOINTREACHED:
			if (pane == _activePane)
				[self updateTitle];
			break;
		case SCN_MODIFIED:
			if ((n->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) && pane == _activePane) {
				[_functionList performSelector:@selector(reload) withObject:nil afterDelay:1.0];
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateStatusBar) object:nil];
				[self performSelector:@selector(updateStatusBar) withObject:nil afterDelay:0.05];
			}
			break;
		case SCN_ZOOM:
			[MppStyler updateLineNumberWidth:pane.editor];
			[MppPrefs shared].zoom = [pane sci:SCI_GETZOOM];
			break;
		case SCN_INDICATORRELEASE:
			MppHandleIndicatorClick(pane.editor, n);
			break;
		default:
			break;
	}
}

- (void)editPane:(MppEditPane *)pane requestCloseDocument:(MppDocument *)doc
{
	[self closeDocument:doc inPane:pane];
}

- (void)editPane:(MppEditPane *)pane moveDocument:(MppDocument *)doc toPane:(MppEditPane *)target atIndex:(NSInteger)index
{
	if (target == pane)
		return;
	if ([target indexOfDocument:doc] != NSNotFound) {
		[target activateDocument:doc];
	} else {
		[target addDocument:doc atIndex:index activate:YES];
	}
	[pane removeDocument:doc];
	[self updatePaneVisibility];
	[self setActivePaneIfNeeded:target];
	[self.window makeFirstResponder:target.editor.content];
	[_docList reload];
}

- (void)editPaneRequestsNewDocument:(MppEditPane *)pane
{
	[self setActivePaneIfNeeded:pane];
	[self newDocument];
}

- (NSMenu *)editPane:(MppEditPane *)pane tabMenuForDocument:(MppDocument *)doc
{
	[self setActivePaneIfNeeded:pane];
	NSMenu *m = [[NSMenu alloc] init];
	auto add = ^(NSString *t, int c) { [m addItem:[MppMenu itemWithTitle:t command:c key:@"" modifiers:0]]; };
	add(@"Close", CMD_FILE_CLOSE);
	add(@"Close All BUT This", CMD_FILE_CLOSEALL_BUT_CURRENT);
	add(@"Close All to the Left", CMD_FILE_CLOSEALL_TOLEFT);
	add(@"Close All to the Right", CMD_FILE_CLOSEALL_TORIGHT);
	add(@"Close All Unchanged", CMD_FILE_CLOSEALL_UNCHANGED);
	[m addItem:NSMenuItem.separatorItem];
	add(@"Save", CMD_FILE_SAVE);
	add(@"Save As…", CMD_FILE_SAVEAS);
	add(@"Rename…", CMD_FILE_RENAME);
	add(@"Move to Trash", CMD_FILE_DELETE);
	add(@"Reload", CMD_FILE_RELOAD);
	add(@"Print…", CMD_FILE_PRINT);
	[m addItem:NSMenuItem.separatorItem];
	add(@"Reveal in Finder", CMD_FILE_REVEAL_IN_FINDER);
	add(@"Open in Terminal", CMD_FILE_OPEN_TERMINAL);
	add(@"Open Containing Folder as Workspace", CMD_FILE_CONTAININGFOLDER_AS_WORKSPACE);
	add(@"Open in Default Viewer", CMD_FILE_OPEN_DEFAULT_VIEWER);
	[m addItem:NSMenuItem.separatorItem];
	add(@"Read-Only in Macpad++", CMD_EDIT_TOGGLEREADONLY);
	[m addItem:NSMenuItem.separatorItem];
	add(@"Copy Full File Path", CMD_EDIT_FULLPATHTOCLIP);
	add(@"Copy Filename", CMD_EDIT_FILENAMETOCLIP);
	add(@"Copy Current Dir. Path", CMD_EDIT_CURRENTDIRTOCLIP);
	[m addItem:NSMenuItem.separatorItem];
	add(@"Move to Other View", CMD_VIEW_GOTO_ANOTHER_VIEW);
	add(@"Clone to Other View", CMD_VIEW_CLONE_TO_ANOTHER_VIEW);
	[m addItem:NSMenuItem.separatorItem];
	NSMenuItem *colors = [m addItemWithTitle:@"Apply Color to Tab" action:nil keyEquivalent:@""];
	NSMenu *cm = [[NSMenu alloc] init];
	for (int i = 0; i < 5; ++i)
		[cm addItem:[MppMenu itemWithTitle:[NSString stringWithFormat:@"Apply Color %d", i + 1] command:CMD_VIEW_TAB_COLOUR_1 + i key:@"" modifiers:0]];
	[cm addItem:[MppMenu itemWithTitle:@"Remove Color" command:CMD_VIEW_TAB_COLOUR_NONE key:@"" modifiers:0]];
	colors.submenu = cm;
	return m;
}

- (NSMenu *)editorContextMenu
{
	NSMenu *m = [[NSMenu alloc] init];
	[m addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@""];
	[m addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
	[m addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@""];
	[m addItemWithTitle:@"Delete" action:@selector(delete:) keyEquivalent:@""];
	[m addItem:NSMenuItem.separatorItem];
	[m addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@""];
	[m addItem:[MppMenu itemWithTitle:@"Begin/End Select" command:CMD_EDIT_BEGINENDSELECT key:@"" modifiers:0]];
	[m addItem:NSMenuItem.separatorItem];
	NSArray *ord = @[@"1st", @"2nd", @"3rd", @"4th", @"5th"];
	NSMenu *all = [[NSMenu alloc] init], *one = [[NSMenu alloc] init], *clear = [[NSMenu alloc] init];
	for (int i = 0; i < 5; ++i) {
		[all addItem:[MppMenu itemWithTitle:[NSString stringWithFormat:@"Using %@ Style", ord[i]] command:CMD_SEARCH_MARKALLEXT1 + i key:@"" modifiers:0]];
		[one addItem:[MppMenu itemWithTitle:[NSString stringWithFormat:@"Using %@ Style", ord[i]] command:CMD_SEARCH_MARKONEEXT1 + i key:@"" modifiers:0]];
		[clear addItem:[MppMenu itemWithTitle:[NSString stringWithFormat:@"Clear %@ Style", ord[i]] command:CMD_SEARCH_UNMARKALLEXT1 + i key:@"" modifiers:0]];
	}
	[clear addItem:[MppMenu itemWithTitle:@"Clear all Styles" command:CMD_SEARCH_CLEARALLMARKS key:@"" modifiers:0]];
	[m addItemWithTitle:@"Style All Occurrences of Token" action:nil keyEquivalent:@""].submenu = all;
	[m addItemWithTitle:@"Style One Token" action:nil keyEquivalent:@""].submenu = one;
	[m addItemWithTitle:@"Clear Style" action:nil keyEquivalent:@""].submenu = clear;
	[m addItem:NSMenuItem.separatorItem];
	[m addItem:[MppMenu itemWithTitle:@"UPPERCASE" command:CMD_EDIT_UPPERCASE key:@"" modifiers:0]];
	[m addItem:[MppMenu itemWithTitle:@"lowercase" command:CMD_EDIT_LOWERCASE key:@"" modifiers:0]];
	[m addItem:NSMenuItem.separatorItem];
	[m addItem:[MppMenu itemWithTitle:@"Open File" command:CMD_EDIT_OPENSELECTEDFILE key:@"" modifiers:0]];
	[m addItem:[MppMenu itemWithTitle:@"Search on Internet" command:CMD_EDIT_SEARCHONINTERNET key:@"" modifiers:0]];
	[m addItem:NSMenuItem.separatorItem];
	[m addItem:[MppMenu itemWithTitle:@"Toggle Single Line Comment" command:CMD_EDIT_BLOCK_COMMENT key:@"" modifiers:0]];
	[m addItem:[MppMenu itemWithTitle:@"Block Comment" command:CMD_EDIT_STREAM_COMMENT key:@"" modifiers:0]];
	[m addItem:[MppMenu itemWithTitle:@"Block Uncomment" command:CMD_EDIT_STREAM_UNCOMMENT key:@"" modifiers:0]];
	[m addItem:NSMenuItem.separatorItem];
	[m addItem:[MppMenu itemWithTitle:@"Hide Lines" command:CMD_VIEW_HIDELINES key:@"" modifiers:0]];
	return m;
}

- (BOOL)editorKeyDown:(NSEvent *)e pane:(MppEditPane *)pane
{
	// Escape: close auto-completion/calltip or the search results panel
	if (e.keyCode == 53 /* esc */) {
		if ([pane sci:SCI_AUTOCACTIVE] || [pane sci:SCI_CALLTIPACTIVE])
			return NO;
		if (_macros.recording)
			return NO;
	}
	return NO;
}

// ---- Panels ---------------------------------------------------------------------

- (void)showSearchResults:(BOOL)show
{
	if (show == !_searchResults.hidden)
		return;
	_searchResults.hidden = !show;
	if (show) {
		[self split:_outerSplit placeDivider:0 at:^CGFloat(NSSplitView *sv) { return sv.bounds.size.height - 220; }];
	} else {
		[_outerSplit adjustSubviews];
		[self.window makeFirstResponder:self.activeEditor.content];
	}
}

- (void)toggleDock:(MppDockContainer *)dock identifier:(NSString *)ident title:(NSString *)title make:(NSView * (^)(void))make
{
	if ([dock hasPanel:ident]) {
		if ([dock.selectedIdentifier isEqualToString:ident] || dock.hidden) {
			[dock removePanel:ident];
			[self dockPanelClosed:ident];
		} else {
			[dock selectPanel:ident];
		}
	} else {
		const BOOL wasHidden = dock.hidden;
		[dock addPanel:make() identifier:ident title:title];
		dock.hidden = NO;
		if (wasHidden) {
			if (dock == _leftDock)
				[self split:_topSplit placeDivider:0 at:^CGFloat(NSSplitView *sv) { return 240; }];
			else
				[self split:_topSplit placeDivider:1 at:^CGFloat(NSSplitView *sv) { return sv.bounds.size.width - 280; }];
		}
	}
	dock.hidden = dock.isEmpty;
	[_topSplit adjustSubviews];
}

- (void)dockPanelClosed:(NSString *)ident
{
	if ([ident isEqualToString:kPanelFunctionList]) _functionList = nil;
	else if ([ident isEqualToString:kPanelDocList]) _docList = nil;
	else if ([ident isEqualToString:kPanelFileBrowser]) _fileBrowser = nil;
	else if ([ident isEqualToString:kPanelDocMap]) _docMap = nil;
	else if ([ident isEqualToString:kPanelClipboard]) _clipboardPanel = nil;
	else if ([ident isEqualToString:kPanelCharPanel]) _charPanel = nil;
	_leftDock.hidden = _leftDock.isEmpty;
	_rightDock.hidden = _rightDock.isEmpty;
	[_topSplit adjustSubviews];
}

- (void)toggleFunctionList
{
	[self toggleDock:_rightDock identifier:kPanelFunctionList title:@"Function List" make:^NSView * {
		self->_functionList = [[MppFunctionListPanel alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
		self->_functionList.owner = self;
		[self->_functionList reload];
		return self->_functionList;
	}];
}

- (void)toggleDocumentList
{
	[self toggleDock:_rightDock identifier:kPanelDocList title:@"Document List" make:^NSView * {
		self->_docList = [[MppDocumentListPanel alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
		self->_docList.owner = self;
		[self->_docList reload];
		return self->_docList;
	}];
}

- (void)toggleDocumentMap
{
	[self toggleDock:_rightDock identifier:kPanelDocMap title:@"Document Map" make:^NSView * {
		self->_docMap = [[MppDocumentMapPanel alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
		self->_docMap.owner = self;
		[self->_docMap documentChanged];
		return self->_docMap;
	}];
}

- (void)toggleClipboardHistory
{
	[self toggleDock:_rightDock identifier:kPanelClipboard title:@"Clipboard History" make:^NSView * {
		self->_clipboardPanel = [[MppClipboardHistoryPanel alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
		self->_clipboardPanel.owner = self;
		return self->_clipboardPanel;
	}];
}

- (void)toggleCharacterPanel
{
	[self toggleDock:_rightDock identifier:kPanelCharPanel title:@"ASCII Codes Insertion Panel" make:^NSView * {
		self->_charPanel = [[MppCharacterPanel alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
		self->_charPanel.owner = self;
		return self->_charPanel;
	}];
}

- (void)toggleFolderAsWorkspace
{
	[self toggleDock:_leftDock identifier:kPanelFileBrowser title:@"Folder as Workspace" make:^NSView * {
		self->_fileBrowser = [[MppFileBrowserPanel alloc] initWithFrame:NSMakeRect(0, 0, 240, 400)];
		self->_fileBrowser.owner = self;
		for (NSString *f in [MppDefaults() stringArrayForKey:@"workspaceFolders"])
			[self->_fileBrowser addRootFolder:f];
		return self->_fileBrowser;
	}];
}

- (void)openFolderAsWorkspace:(NSString *)folder
{
	if (!_fileBrowser)
		[self toggleFolderAsWorkspace];
	[_fileBrowser addRootFolder:folder];
	[MppDefaults() setObject:_fileBrowser.rootFolders forKey:@"workspaceFolders"];
}

// ---- File monitoring & backup -----------------------------------------------------

- (void)appDidBecomeActive:(NSNotification *)n
{
	[self checkFiles];
}

- (void)checkFilesTimer:(NSTimer *)t
{
	if (NSApp.isActive || [self.allDocuments indexOfObjectPassingTest:^BOOL(MppDocument *d, NSUInteger i, BOOL *s) { return d.monitoring; }] != NSNotFound)
		[self checkFiles];
}

- (void)checkFiles
{
	if (_checkingFiles || _quitting || ([MppPrefs shared].fileAutoDetection == MppFileAutoDetectDisabled && !self.hasMonitoredDocuments))
		return;
	_checkingFiles = YES;
	for (MppDocument *doc in [self allDocuments]) {
		if (!doc.filePath)
			continue;
		NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:doc.filePath error:nil];
		if (!attrs) {
			if (!doc.fileDeleted) {
				doc.fileDeleted = YES;
				[doc notifyChanged];
				if ([MppPrefs shared].fileAutoDetection == MppFileAutoDetectDisabled)
					continue;
				[self activateDocument:doc];
				NSAlert *a = [[NSAlert alloc] init];
				a.messageText = [NSString stringWithFormat:@"The file \"%@\" doesn't exist anymore.", doc.filePath];
				a.informativeText = @"Keep this file in editor?";
				[a addButtonWithTitle:@"Keep"];
				[a addButtonWithTitle:@"Close"];
				if ([a runModal] == NSAlertSecondButtonReturn) {
					doc.dirty = NO;
					[self closeDocuments:@[doc]];
				} else {
					doc.dirty = YES;
				}
			}
			continue;
		}
		NSDate *mod = attrs[NSFileModificationDate];
		if (doc.fileDeleted) {
			doc.fileDeleted = NO;
			[doc notifyChanged];
		}
		if (!doc.fileModificationDate || [mod isEqualToDate:doc.fileModificationDate])
			continue;
		doc.fileModificationDate = mod;
		BOOL reload = NO;
		if (doc.monitoring || ([MppPrefs shared].fileAutoDetection == MppFileAutoDetectSilent && !doc.dirty)) {
			reload = YES;
		} else if ([MppPrefs shared].fileAutoDetection != MppFileAutoDetectDisabled) {
			[self activateDocument:doc];
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = [NSString stringWithFormat:@"\"%@\"\n\nThis file has been modified by another program.", doc.filePath];
			a.informativeText = doc.dirty ? @"Do you want to reload it and lose the changes made in Macpad++?"
			                              : @"Do you want to reload it?";
			[a addButtonWithTitle:@"Yes"];
			[a addButtonWithTitle:@"No"];
			reload = [a runModal] == NSAlertFirstButtonReturn;
		}
		if (reload) {
			MppEditPane *pane = [self paneForDocument:doc];
			if (pane.currentDocument == doc)
				[pane saveCurrentPosition];
			MppEncoding enc = doc.encoding;
			NSError *err = nil;
			[MppDocumentManager.shared reloadDocument:doc forcedEncoding:(doc.encoding.mode == MppUni8Bit ? &enc : nullptr) error:&err];
			[self documentDisplayChanged:doc];
			if (doc.monitoring && pane.currentDocument == doc)
				[pane sci:SCI_DOCUMENTEND];
		}
	}
	_checkingFiles = NO;
}

- (BOOL)hasMonitoredDocuments
{
	for (MppDocument *d in [self allDocuments])
		if (d.monitoring)
			return YES;
	return NO;
}

- (void)resetBackupTimer
{
	[_backupTimer invalidate];
	_backupTimer = nil;
	MppPrefs *p = [MppPrefs shared];
	if (p.sessionSnapshot && p.backupInterval > 0)
		_backupTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)p.backupInterval target:self
		                                              selector:@selector(backupTimer:) userInfo:nil repeats:YES];
}

- (void)backupTimer:(NSTimer *)t
{
	[self writeBackups];
}

- (void)writeBackups
{
	for (MppDocument *d in [self allDocuments]) {
		if (d.dirty && d.backupDirty)
			[MppDocumentManager.shared writeBackupOfDocument:d];
		else if (!d.dirty && d.backupPath && !d.isUntitled) {
			[NSFileManager.defaultManager removeItemAtPath:d.backupPath error:nil];
			d.backupPath = nil;
		}
	}
	[self saveSessionToPath:nil includeBackups:YES];
}

// ---- Session --------------------------------------------------------------------

- (NSString *)defaultSessionPath
{
	return [MppPaths.userDataDirectory stringByAppendingPathComponent:@"session.plist"];
}

- (NSDictionary *)sessionEntryForDocument:(MppDocument *)d pane:(MppEditPane *)pane backups:(BOOL)backups
{
	NSMutableDictionary *e = [NSMutableDictionary dictionary];
	if (d.filePath)
		e[@"path"] = d.filePath;
	else
		e[@"untitledName"] = d.untitledName ?: @"new 1";
	if (backups && d.backupPath && d.dirty)
		e[@"backup"] = d.backupPath;
	e[@"lang"] = @(d.lang);
	e[@"langSetByUser"] = @(d.langSetByUser);
	if (d.userLangName)
		e[@"userLang"] = d.userLangName;
	e[@"encoding"] = MppEncodingToName(d.encoding);
	e[@"readOnly"] = @(d.userReadOnly);
	e[@"tabColor"] = @(d.tabColor);
	if (pane.currentDocument == d)
		[pane saveCurrentPosition];
	MppViewPosition &pos = [d positionForView:pane.editor];
	e[@"anchor"] = @(pos.anchor);
	e[@"caret"] = @(pos.caret);
	e[@"firstLine"] = @(pos.firstVisibleDocLine);
	NSMutableArray *folds = [NSMutableArray array];
	for (sptr_t l : pos.foldedLines)
		[folds addObject:@(l)];
	e[@"folds"] = folds;
	return e;
}

- (void)saveSessionToPath:(NSString *)path includeBackups:(BOOL)backups
{
	NSMutableDictionary *s = [NSMutableDictionary dictionary];
	for (MppEditPane *pane in @[_mainPane, _subPane]) {
		NSMutableArray *docs = [NSMutableArray array];
		for (MppDocument *d in pane.documents) {
			if (d.isUntitled && !(backups && d.backupPath && d.dirty))
				continue;   // nothing to restore
			[docs addObject:[self sessionEntryForDocument:d pane:pane backups:backups]];
		}
		NSString *key = (pane == _mainPane) ? @"mainView" : @"subView";
		s[key] = docs;
		MppDocument *cur = pane.currentDocument;
		NSInteger idx = 0, k = 0;
		for (MppDocument *d in pane.documents) {
			if (d.isUntitled && !(backups && d.backupPath && d.dirty))
				continue;
			if (d == cur)
				idx = k;
			++k;
		}
		s[[key stringByAppendingString:@"Active"]] = @(idx);
	}
	s[@"activeView"] = (_activePane == _subPane) ? @1 : @0;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:s format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
	[data writeToFile:path ?: [self defaultSessionPath] atomically:YES];
}

- (void)loadSessionDictionary:(NSDictionary *)s
{
	MppDocumentManager *dm = MppDocumentManager.shared;
	for (MppEditPane *pane in @[_mainPane, _subPane]) {
		NSString *key = (pane == _mainPane) ? @"mainView" : @"subView";
		NSArray *entries = s[key];
		NSMutableArray *opened = [NSMutableArray array];
		for (NSDictionary *e in entries) {
			NSString *path = e[@"path"], *backup = e[@"backup"];
			MppDocument *doc = nil;
			if (backup && [NSFileManager.defaultManager fileExistsAtPath:backup]) {
				doc = [dm restoreDocumentFromBackup:backup originalPath:path untitledName:e[@"untitledName"]];
			} else if (path && [NSFileManager.defaultManager fileExistsAtPath:path]) {
				doc = [dm documentForPath:path];
				if (!doc) {
					MppEncoding enc = MppEncodingFromName(e[@"encoding"] ?: @"UTF-8");
					const BOOL forceEnc = (enc.mode == MppUni8Bit);
					doc = [dm openFile:path forcedEncoding:forceEnc ? &enc : nullptr error:nil];
				}
			}
			if (!doc)
				continue;
			if ([e[@"langSetByUser"] boolValue]) {
				doc.lang = (MppLangType)[e[@"lang"] intValue];
				doc.langSetByUser = YES;
			}
			if (e[@"userLang"]) {
				doc.userLangName = e[@"userLang"];
				doc.lang = L_USER;
			}
			if (backup && e[@"encoding"])
				doc.encoding = MppEncodingFromName(e[@"encoding"]);
			doc.userReadOnly = [e[@"readOnly"] boolValue];
			doc.tabColor = e[@"tabColor"] ? [e[@"tabColor"] integerValue] : -1;
			MppViewPosition &pos = [doc positionForView:pane.editor];
			pos.anchor = [e[@"anchor"] longValue];
			pos.caret = [e[@"caret"] longValue];
			pos.firstVisibleDocLine = [e[@"firstLine"] longValue];
			for (NSNumber *f in e[@"folds"])
				pos.foldedLines.push_back(f.longValue);
			pos.valid = true;
			[pane addDocument:doc atIndex:-1 activate:NO];
			[opened addObject:doc];
		}
		NSInteger active = [s[[key stringByAppendingString:@"Active"]] integerValue];
		if (opened.count)
			[pane activateDocument:opened[(NSUInteger)MIN(MAX(active, 0), (NSInteger)opened.count - 1)]];
	}
	[self updatePaneVisibility];
	if ([s[@"activeView"] intValue] == 1 && _subPane.documents.count)
		[self setActivePaneIfNeeded:_subPane];
}

- (void)restoreSession
{
	MppPrefs *p = [MppPrefs shared];
	if (p.rememberSession || p.sessionSnapshot) {
		NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:[self defaultSessionPath]];
		if (s)
			[self loadSessionDictionary:s];
	}
	if (_mainPane.documents.count == 0 && _subPane.documents.count == 0) {
		MppDocument *d = [MppDocumentManager.shared createUntitledDocument];
		[_mainPane addDocument:d atIndex:-1 activate:YES];
	}
	[self updatePaneVisibility];
	[self.window makeFirstResponder:_activePane.editor.content];
}

- (void)restoreSessionWithoutFiles
{
	if (_mainPane.documents.count == 0 && _subPane.documents.count == 0) {
		MppDocument *d = [MppDocumentManager.shared createUntitledDocument];
		[_mainPane addDocument:d atIndex:-1 activate:YES];
	}
	[self updatePaneVisibility];
	[self.window makeFirstResponder:_activePane.editor.content];
}

- (void)loadSessionFromPath:(NSString *)path
{
	NSDictionary *s = [NSDictionary dictionaryWithContentsOfFile:path];
	if (!s) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"This session file is not valid.";
		[a runModal];
		return;
	}
	[self loadSessionDictionary:s];
}

- (BOOL)prepareToQuit
{
	MppPrefs *p = [MppPrefs shared];
	if (p.sessionSnapshot) {
		[self writeBackups];
	} else {
		for (MppDocument *d in [self allDocuments])
			if (![self confirmCloseOfDirtyDocument:d])
				return NO;
		if (p.rememberSession)
			[self saveSessionToPath:nil includeBackups:NO];
		else
			[NSFileManager.defaultManager removeItemAtPath:[self defaultSessionPath] error:nil];
	}
	_quitting = YES;
	return YES;
}

- (BOOL)windowShouldClose:(NSWindow *)sender
{
	[NSApp terminate:self];
	return NO;
}

// ---- Commands -------------------------------------------------------------------

- (void)mppCommand:(id)sender
{
	[self executeCommand:(int)[sender tag]];
}

- (NSArray<MppDocument *> *)documentsOfActivePaneFrom:(NSInteger)from to:(NSInteger)to
{
	NSArray *docs = _activePane.documents;
	NSMutableArray *r = [NSMutableArray array];
	for (NSInteger i = MAX(from, 0); i < MIN(to, (NSInteger)docs.count); ++i)
		[r addObject:docs[(NSUInteger)i]];
	return r;
}

- (void)reinterpretEncoding:(MppEncoding)enc
{
	MppDocument *doc = self.currentDocument;
	if (!doc)
		return;
	if (doc.isUntitled) {
		doc.encoding = enc;
		[doc notifyChanged];
		return;
	}
	if (doc.dirty) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"You should save the current modification. All the saved modifications can not be undone.";
		a.informativeText = @"Continue?";
		[a addButtonWithTitle:@"Save & Continue"];
		[a addButtonWithTitle:@"Cancel"];
		if ([a runModal] != NSAlertFirstButtonReturn || ![self saveDocument:doc])
			return;
	}
	[_activePane saveCurrentPosition];
	NSError *err = nil;
	if (![MppDocumentManager.shared reloadDocument:doc forcedEncoding:&enc error:&err] && err)
		[self showError:err];
	[self documentDisplayChanged:doc];
}

- (void)convertEncoding:(MppEncoding)enc
{
	MppDocument *doc = self.currentDocument;
	if (!doc || doc.encoding == enc)
		return;
	doc.encoding = enc;
	doc.dirty = YES;
	[doc notifyChanged];
}

- (void)executeCommand:(int)cmd
{
	if (_macros.recording && [MppMacroManager isRecordableCommand:cmd])
		[_macros recordCommand:cmd];

	MppDocument *doc = self.currentDocument;
	MppPrefs *prefs = [MppPrefs shared];

	if (cmd >= CMD_FILE_RECENT_BASE && cmd < CMD_FILE_RECENT_BASE + 100) {
		NSArray *recent = prefs.recentFiles;
		NSInteger i = cmd - CMD_FILE_RECENT_BASE;
		if (i < (NSInteger)recent.count)
			[self openPath:recent[(NSUInteger)i]];
		return;
	}
	if (cmd >= CMD_LANG_BASE && cmd <= CMD_LANG_BASE + L_EXTERNAL) {
		if (doc) {
			doc.userLangName = nil;
			[self setLanguage:(MppLangType)(cmd - CMD_LANG_BASE) forDocument:doc];
		}
		return;
	}
	if (cmd >= CMD_LANG_USER_BASE && cmd < CMD_LANG_USER_BASE + 300) {
		NSArray *names = [MppUserLangManager.shared languageNames];
		NSInteger i = cmd - CMD_LANG_USER_BASE;
		if (doc && i < (NSInteger)names.count) {
			doc.userLangName = names[(NSUInteger)i];
			[self setLanguage:L_USER forDocument:doc];
		}
		return;
	}
	if (cmd >= CMD_FORMAT_CHARSET_BASE && cmd < CMD_FORMAT_CHARSET_BASE + 200) {
		const auto &cs = MppCharsets();
		size_t i = (size_t)(cmd - CMD_FORMAT_CHARSET_BASE);
		if (i < cs.size()) {
			MppEncoding e;
			e.mode = MppUni8Bit;
			e.codepage = cs[i].codepage;
			[self reinterpretEncoding:e];
		}
		return;
	}

	switch (cmd) {
		// ---- File
		case CMD_FILE_NEW: [self newDocument]; return;
		case CMD_FILE_OPEN: {
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			panel.allowsMultipleSelection = YES;
			panel.canChooseDirectories = NO;
			if (doc.filePath)
				panel.directoryURL = [NSURL fileURLWithPath:doc.filePath.stringByDeletingLastPathComponent];
			if ([panel runModal] == NSModalResponseOK) {
				NSMutableArray *paths = [NSMutableArray array];
				for (NSURL *u in panel.URLs)
					[paths addObject:u.path];
				[self openPaths:paths];
			}
			return;
		}
		case CMD_FILE_REVEAL_IN_FINDER:
			if (doc.filePath)
				[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:doc.filePath]]];
			return;
		case CMD_FILE_OPEN_TERMINAL:
			if (doc.filePath) {
				NSURL *term = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
				NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
				[NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:doc.filePath.stringByDeletingLastPathComponent]]
				                 withApplicationAtURL:term configuration:cfg completionHandler:nil];
			}
			return;
		case CMD_FILE_CONTAININGFOLDER_AS_WORKSPACE:
			if (doc.filePath)
				[self openFolderAsWorkspace:doc.filePath.stringByDeletingLastPathComponent];
			return;
		case CMD_FILE_OPEN_DEFAULT_VIEWER:
			if (doc.filePath)
				[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:doc.filePath]];
			return;
		case CMD_FILE_OPEN_FOLDER_AS_WORKSPACE: {
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			panel.canChooseDirectories = YES;
			panel.canChooseFiles = NO;
			if ([panel runModal] == NSModalResponseOK)
				[self openFolderAsWorkspace:panel.URL.path];
			return;
		}
		case CMD_FILE_RELOAD:
			if (doc.filePath) {
				if (doc.dirty) {
					NSAlert *a = [[NSAlert alloc] init];
					a.messageText = [NSString stringWithFormat:@"Are you sure you want to reload the current file and lose the changes made in Macpad++?"];
					[a addButtonWithTitle:@"Reload"];
					[a addButtonWithTitle:@"Cancel"];
					if ([a runModal] != NSAlertFirstButtonReturn)
						return;
				}
				[_activePane saveCurrentPosition];
				MppEncoding enc = doc.encoding;
				NSError *err = nil;
				if (![MppDocumentManager.shared reloadDocument:doc forcedEncoding:(enc.mode == MppUni8Bit ? &enc : nullptr) error:&err] && err)
					[self showError:err];
				[self documentDisplayChanged:doc];
			}
			return;
		case CMD_FILE_SAVE: if (doc) [self saveDocument:doc]; return;
		case CMD_FILE_SAVEAS: if (doc) [self saveDocumentAs:doc copy:NO]; return;
		case CMD_FILE_SAVECOPYAS: if (doc) [self saveDocumentAs:doc copy:YES]; return;
		case CMD_FILE_SAVEALL: [self saveAll]; return;
		case CMD_FILE_RENAME: {
			if (!doc)
				return;
			NSString *newName = MppAskString(@"Rename", @"New name:", doc.displayName);
			if (!newName.length || [newName isEqualToString:doc.displayName])
				return;
			if (doc.isUntitled) {
				doc.untitledName = newName;
				[doc notifyChanged];
				return;
			}
			NSString *newPath = [doc.filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:newName];
			NSError *err = nil;
			if (![NSFileManager.defaultManager moveItemAtPath:doc.filePath toPath:newPath error:&err]) {
				[self showError:err];
				return;
			}
			doc.filePath = newPath;
			if (!doc.langSetByUser)
				doc.lang = [MppLanguages.shared langTypeForFileName:newPath];
			[self documentDisplayChanged:doc];
			[doc notifyChanged];
			return;
		}
		case CMD_FILE_CLOSE: if (doc) [self closeDocument:doc inPane:_activePane]; return;
		case CMD_FILE_CLOSEALL: [self closeDocuments:[self allDocuments]]; return;
		case CMD_FILE_CLOSEALL_BUT_CURRENT: {
			NSMutableArray *a = [[self allDocuments] mutableCopy];
			[a removeObject:doc];
			[self closeDocuments:a];
			return;
		}
		case CMD_FILE_CLOSEALL_TOLEFT:
			[self closeDocuments:[self documentsOfActivePaneFrom:0 to:[_activePane indexOfDocument:doc]]];
			return;
		case CMD_FILE_CLOSEALL_TORIGHT:
			[self closeDocuments:[self documentsOfActivePaneFrom:[_activePane indexOfDocument:doc] + 1 to:NSIntegerMax]];
			return;
		case CMD_FILE_CLOSEALL_UNCHANGED: {
			NSMutableArray *a = [NSMutableArray array];
			for (MppDocument *d in [self allDocuments])
				if (!d.dirty)
					[a addObject:d];
			[self closeDocuments:a];
			return;
		}
		case CMD_FILE_DELETE: {
			if (!doc.filePath)
				return;
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = [NSString stringWithFormat:@"Move \"%@\" to the Trash?", doc.filePath.lastPathComponent];
			[a addButtonWithTitle:@"Move to Trash"];
			[a addButtonWithTitle:@"Cancel"];
			if ([a runModal] != NSAlertFirstButtonReturn)
				return;
			NSError *err = nil;
			if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:doc.filePath] resultingItemURL:nil error:&err]) {
				[self showError:err];
				return;
			}
			doc.dirty = NO;
			[self closeDocuments:@[doc]];
			return;
		}
		case CMD_FILE_LOADSESSION: {
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			if ([panel runModal] == NSModalResponseOK)
				[self loadSessionFromPath:panel.URL.path];
			return;
		}
		case CMD_FILE_SAVESESSION: {
			NSSavePanel *panel = [NSSavePanel savePanel];
			panel.nameFieldStringValue = @"session.mppsession";
			if ([panel runModal] == NSModalResponseOK)
				[self saveSessionToPath:panel.URL.path includeBackups:NO];
			return;
		}
		case CMD_FILE_PRINT: [self printDocument]; return;
		case CMD_FILE_RESTORE_LAST_CLOSED: {
			NSString *p = _recentlyClosed.lastObject;
			if (p) {
				[_recentlyClosed removeLastObject];
				[self openPath:p];
			}
			return;
		}
		case CMD_FILE_OPEN_ALL_RECENT: [self openPaths:prefs.recentFiles]; return;
		case CMD_FILE_CLEAN_RECENT: prefs.recentFiles = @[]; return;

		// ---- Encoding
		case CMD_FORMAT_ANSI: { MppEncoding e; e.mode = MppUni8Bit; e.codepage = -1; [self reinterpretEncoding:e]; return; }
		case CMD_FORMAT_AS_UTF_8: { MppEncoding e; e.mode = MppUniUTF8; [self reinterpretEncoding:e]; return; }
		case CMD_FORMAT_UTF_8: { MppEncoding e; e.mode = MppUniUTF8BOM; [self reinterpretEncoding:e]; return; }
		case CMD_FORMAT_UTF_16BE: { MppEncoding e; e.mode = MppUni16BE; [self reinterpretEncoding:e]; return; }
		case CMD_FORMAT_UTF_16LE: { MppEncoding e; e.mode = MppUni16LE; [self reinterpretEncoding:e]; return; }
		case CMD_FORMAT_CONV2_ANSI: { MppEncoding e; e.mode = MppUni8Bit; e.codepage = -1; [self convertEncoding:e]; return; }
		case CMD_FORMAT_CONV2_AS_UTF_8: { MppEncoding e; e.mode = MppUniUTF8; [self convertEncoding:e]; return; }
		case CMD_FORMAT_CONV2_UTF_8: { MppEncoding e; e.mode = MppUniUTF8BOM; [self convertEncoding:e]; return; }
		case CMD_FORMAT_CONV2_UTF_16BE: { MppEncoding e; e.mode = MppUni16BE; [self convertEncoding:e]; return; }
		case CMD_FORMAT_CONV2_UTF_16LE: { MppEncoding e; e.mode = MppUni16LE; [self convertEncoding:e]; return; }

		// ---- Language / UDL
		case CMD_LANG_IMPORT_UDL: {
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			panel.allowsMultipleSelection = YES;
			panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xml"]];
			if ([panel runModal] == NSModalResponseOK) {
				NSInteger n = 0;
				for (NSURL *u in panel.URLs)
					n += [MppUserLangManager.shared importFile:u.path];
				NSAlert *a = [[NSAlert alloc] init];
				a.messageText = n ? [NSString stringWithFormat:@"%ld user defined language(s) imported.", (long)n]
				                  : @"No user defined language found in the selected file(s).";
				[a runModal];
			}
			return;
		}
		case CMD_LANG_DEFINE_UDL: {
			MppDocument *d = self.currentDocument;
			[MppUserLangEditor.shared showLanguage:d.lang == L_USER ? d.userLangName : nil];
			return;
		}
		case CMD_LANG_OPENUDLDIR:
			[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:[MppUserLangManager.shared directory]]];
			return;

		// ---- Settings
		case CMD_SETTING_PREFERENCE: [MppPreferencesController show]; return;
		case CMD_SETTING_STYLE_CONFIG: [MppStyleConfiguratorController show]; return;
		case CMD_SETTING_SHORTCUT_MAPPER: MppShowShortcutList(NSApp.mainMenu); return;
		case CMD_SETTING_IMPORT_THEMES: {
			NSOpenPanel *panel = [NSOpenPanel openPanel];
			panel.allowsMultipleSelection = YES;
			panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"xml"]];
			if ([panel runModal] == NSModalResponseOK) {
				NSString *dir = [MppPaths.userDataDirectory stringByAppendingPathComponent:@"themes"];
				[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
				for (NSURL *u in panel.URLs) {
					NSString *dst = [dir stringByAppendingPathComponent:u.lastPathComponent];
					[NSFileManager.defaultManager removeItemAtPath:dst error:nil];
					[NSFileManager.defaultManager copyItemAtPath:u.path toPath:dst error:nil];
				}
			}
			return;
		}
		case CMD_SETTING_OPEN_SETTINGS_DIR:
			[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:MppPaths.userDataDirectory]];
			return;

		// ---- Window
		case CMD_WINDOW_SORT_FN_ASC: case CMD_WINDOW_SORT_FN_DSC: case CMD_WINDOW_SORT_FP_ASC:
		case CMD_WINDOW_SORT_FP_DSC: case CMD_WINDOW_SORT_FT_ASC: case CMD_WINDOW_SORT_FT_DSC:
		case CMD_WINDOW_SORT_FS_ASC: case CMD_WINDOW_SORT_FS_DSC:
			[self sortTabs:cmd];
			return;
		case CMD_WINDOW_WINDOWS: MppShowWindowsDialog(self); return;

		// ---- Help
		case CMD_HELP_ABOUT: MppShowAbout(); return;
		case CMD_HELP_CMDLINE: MppShowCommandLineHelp(); return;
		case CMD_HELP_DEBUGINFO: MppShowDebugInfo(); return;
		case CMD_HELP_PLUGINS_INFO: {
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = @"Plugins";
			a.informativeText = @"Plugins for Windows text editors are DLLs and cannot be loaded by the native macOS version. "
			                    @"Many popular plugin features (Function List, Folder as Workspace, Document Map, "
			                    @"hash tools, macros, Run commands) are built in.";
			[a runModal];
			return;
		}
		default:
			break;
	}

	if ([self handleEditCommand:cmd])
		return;
	if ([self handleSearchCommand:cmd])
		return;
	if ([self handleViewCommand:cmd])
		return;
	[self handleToolsCommand:cmd];
}

- (void)sortTabs:(int)cmd
{
	NSMutableArray<MppDocument *> *docs = [_activePane.documents mutableCopy];
	MppDocumentManager *dm = MppDocumentManager.shared;
	[docs sortUsingComparator:^NSComparisonResult(MppDocument *a, MppDocument *b) {
		switch (cmd) {
			case CMD_WINDOW_SORT_FN_ASC: case CMD_WINDOW_SORT_FN_DSC:
				return [a.displayName localizedStandardCompare:b.displayName];
			case CMD_WINDOW_SORT_FP_ASC: case CMD_WINDOW_SORT_FP_DSC:
				return [(a.filePath ?: a.displayName) localizedStandardCompare:(b.filePath ?: b.displayName)];
			case CMD_WINDOW_SORT_FT_ASC: case CMD_WINDOW_SORT_FT_DSC:
				return [a.displayName.pathExtension localizedStandardCompare:b.displayName.pathExtension];
			default: {
				sptr_t la = [dm scratchMessage:SCI_GETLENGTH doc:a wParam:0 lParam:0];
				sptr_t lb = [dm scratchMessage:SCI_GETLENGTH doc:b wParam:0 lParam:0];
				return la < lb ? NSOrderedAscending : (la > lb ? NSOrderedDescending : NSOrderedSame);
			}
		}
	}];
	const BOOL desc = (cmd == CMD_WINDOW_SORT_FN_DSC || cmd == CMD_WINDOW_SORT_FP_DSC || cmd == CMD_WINDOW_SORT_FT_DSC ||
	                   cmd == CMD_WINDOW_SORT_FS_DSC);
	if (desc)
		docs = [[[docs reverseObjectEnumerator] allObjects] mutableCopy];
	for (NSInteger i = 0; i < (NSInteger)docs.count; ++i)
		[_activePane moveDocumentFromIndex:[_activePane indexOfDocument:docs[(NSUInteger)i]] toIndex:i];
}

// ---- Menu validation ------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu *)menu
{
	if ([menu.identifier isEqualToString:MppMenuRecent]) {
		[menu removeAllItems];
		NSArray *recent = [MppPrefs shared].recentFiles;
		for (NSUInteger i = 0; i < recent.count; ++i) {
			NSString *title = [NSString stringWithFormat:@"%lu: %@", (unsigned long)i + 1, [recent[i] stringByAbbreviatingWithTildeInPath]];
			[menu addItem:[MppMenu itemWithTitle:title command:CMD_FILE_RECENT_BASE + (int)i key:@"" modifiers:0]];
		}
		if (recent.count)
			[menu addItem:NSMenuItem.separatorItem];
		[menu addItem:[MppMenu itemWithTitle:@"Open All Recent Files" command:CMD_FILE_OPEN_ALL_RECENT key:@"" modifiers:0]];
		[menu addItem:[MppMenu itemWithTitle:@"Empty Recent Files List" command:CMD_FILE_CLEAN_RECENT key:@"" modifiers:0]];
	} else if ([menu.identifier isEqualToString:MppMenuMacros]) {
		while (menu.numberOfItems > 6)
			[menu removeItemAtIndex:6];
		NSArray *saved = _macros.savedMacros;
		if (saved.count)
			[menu addItem:NSMenuItem.separatorItem];
		for (NSUInteger i = 0; i < saved.count; ++i)
			[menu addItem:[MppMenu itemWithTitle:saved[i][@"name"] command:CMD_MACRO_BASE + (int)i key:@"" modifiers:0]];
	} else if ([menu.identifier isEqualToString:MppMenuRun]) {
		while (menu.numberOfItems > 2)
			[menu removeItemAtIndex:2];
		NSArray *cmds = MppSavedRunCommands();
		if (cmds.count)
			[menu addItem:NSMenuItem.separatorItem];
		for (NSUInteger i = 0; i < cmds.count; ++i)
			[menu addItem:[MppMenu itemWithTitle:cmds[i][@"name"] command:CMD_RUN_BASE + (int)i key:@"" modifiers:0]];
	} else if ([menu.identifier isEqualToString:MppMenuUserLangs]) {
		while (menu.numberOfItems > 4)
			[menu removeItemAtIndex:4];
		NSArray *names = [MppUserLangManager.shared languageNames];
		if (names.count)
			[menu addItem:NSMenuItem.separatorItem];
		for (NSUInteger i = 0; i < names.count; ++i)
			[menu addItem:[MppMenu itemWithTitle:names[i] command:CMD_LANG_USER_BASE + (int)i key:@"" modifiers:0]];
	}
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
	if (item.action != @selector(mppCommand:))
		return [self respondsToSelector:item.action];
	NSMenuItem *mi = [(id)item isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)item : nil;
	const int cmd = (int)item.tag;
	MppDocument *doc = self.currentDocument;
	MppPrefs *p = [MppPrefs shared];
	auto check = ^(BOOL on) { if (mi) mi.state = on ? NSControlStateValueOn : NSControlStateValueOff; };
	const BOOL readOnly = doc && (doc.userReadOnly || doc.fileReadOnly || doc.monitoring);

	if (cmd >= CMD_LANG_BASE && cmd <= CMD_LANG_BASE + L_EXTERNAL) {
		check(doc && doc.lang == cmd - CMD_LANG_BASE && !(doc.lang == L_USER));
		return YES;
	}
	if (cmd >= CMD_LANG_USER_BASE && cmd < CMD_LANG_USER_BASE + 300) {
		NSArray *names = [MppUserLangManager.shared languageNames];
		NSInteger i = cmd - CMD_LANG_USER_BASE;
		check(doc && doc.lang == L_USER && i < (NSInteger)names.count && [doc.userLangName isEqualToString:names[(NSUInteger)i]]);
		return YES;
	}
	if (cmd >= CMD_FORMAT_CHARSET_BASE && cmd < CMD_FORMAT_CHARSET_BASE + 200) {
		const auto &cs = MppCharsets();
		size_t i = (size_t)(cmd - CMD_FORMAT_CHARSET_BASE);
		check(doc && doc.encoding.mode == MppUni8Bit && i < cs.size() && doc.encoding.codepage == cs[i].codepage);
		return YES;
	}
	switch (cmd) {
		case CMD_FORMAT_ANSI: check(doc.encoding.mode == MppUni8Bit && doc.encoding.codepage < 0); return YES;
		case CMD_FORMAT_AS_UTF_8: check(doc.encoding.mode == MppUniUTF8); return YES;
		case CMD_FORMAT_UTF_8: check(doc.encoding.mode == MppUniUTF8BOM); return YES;
		case CMD_FORMAT_UTF_16BE: check(doc.encoding.mode == MppUni16BE); return YES;
		case CMD_FORMAT_UTF_16LE: check(doc.encoding.mode == MppUni16LE); return YES;
		case CMD_FORMAT_TODOS: check(doc.eolMode == SC_EOL_CRLF); return !readOnly;
		case CMD_FORMAT_TOUNIX: check(doc.eolMode == SC_EOL_LF); return !readOnly;
		case CMD_FORMAT_TOMAC: check(doc.eolMode == SC_EOL_CR); return !readOnly;
		case CMD_FILE_RELOAD:
		case CMD_FILE_REVEAL_IN_FINDER:
		case CMD_FILE_OPEN_TERMINAL:
		case CMD_FILE_OPEN_DEFAULT_VIEWER:
		case CMD_FILE_DELETE:
		case CMD_FILE_CONTAININGFOLDER_AS_WORKSPACE:
		case CMD_VIEW_MONITORING:
			if (cmd == CMD_VIEW_MONITORING)
				check(doc.monitoring);
			return doc.filePath != nil;
		case CMD_VIEW_IN_SAFARI: case CMD_VIEW_IN_CHROME: case CMD_VIEW_IN_FIREFOX: case CMD_VIEW_IN_EDGE:
			return doc.filePath != nil;
		case CMD_FILE_SAVE: return doc && (doc.dirty || doc.isUntitled);
		case CMD_FILE_RESTORE_LAST_CLOSED: return _recentlyClosed.count > 0;
		case CMD_EDIT_TOGGLEREADONLY: check(doc.userReadOnly); return doc != nil;
		case CMD_VIEW_ALWAYSONTOP: check(p.alwaysOnTop); return YES;
		case CMD_VIEW_TAB_SPACE: check(p.showWhitespace); return YES;
		case CMD_VIEW_EOL: check(p.showEOL); return YES;
		case CMD_VIEW_NPC: check(p.showNonPrinting); return YES;
		case CMD_VIEW_ALL_CHARACTERS: check(p.showWhitespace && p.showEOL); return YES;
		case CMD_VIEW_INDENT_GUIDE: check(p.showIndentGuides); return YES;
		case CMD_VIEW_WRAP_SYMBOL: check(p.showWrapSymbol); return YES;
		case CMD_VIEW_WRAP: check(p.wordWrap); return YES;
		case CMD_VIEW_TOOLBAR: check(p.showToolbar); return YES;
		case CMD_VIEW_STATUSBAR: check(p.showStatusBar); return YES;
		case CMD_VIEW_LINENUMBER: check(p.showLineNumbers); return YES;
		case CMD_VIEW_BOOKMARK_MARGIN: check(p.showBookmarkMargin); return YES;
		case CMD_VIEW_CHANGE_HISTORY_MARGIN: check(p.showChangeHistory); return YES;
		case CMD_VIEW_SYNSCROLLV: check(_syncVerticalScroll); return !_subPane.hidden && !_mainPane.hidden;
		case CMD_VIEW_SYNSCROLLH: check(_syncHorizontalScroll); return !_subPane.hidden && !_mainPane.hidden;
		case CMD_VIEW_DISTRACTIONFREE: check(_distractionFree); return YES;
		case CMD_VIEW_ZOOM_SYNC: check([MppDefaults() boolForKey:@"zoomSync"]); return YES;
		case CMD_VIEW_FUNC_LIST: check(_functionList != nil); return YES;
		case CMD_VIEW_DOCLIST: check(_docList != nil); return YES;
		case CMD_VIEW_DOC_MAP: check(_docMap != nil); return YES;
		case CMD_VIEW_FILEBROWSER: check(_fileBrowser != nil); return YES;
		case CMD_EDIT_CLIPBOARDHISTORY_PANEL: check(_clipboardPanel != nil); return YES;
		case CMD_EDIT_CHAR_PANEL: check(_charPanel != nil); return YES;
		case CMD_VIEW_SWITCHTO_OTHER_VIEW: return self.otherPane.documents.count > 0;
		case CMD_VIEW_TAB_COLOUR_1: case CMD_VIEW_TAB_COLOUR_2: case CMD_VIEW_TAB_COLOUR_3:
		case CMD_VIEW_TAB_COLOUR_4: case CMD_VIEW_TAB_COLOUR_5:
			check(doc.tabColor == cmd - CMD_VIEW_TAB_COLOUR_1);
			return doc != nil;
		case CMD_MACRO_START_RECORDING: return YES;   // also stops recording (same shortcut)
		case CMD_MACRO_STOP_RECORDING: return _macros.recording;
		case CMD_MACRO_PLAYBACK: case CMD_MACRO_RUN_MULTI: case CMD_MACRO_SAVE_CURRENT:
			return !_macros.recording && _macros.hasRecordedMacro;
		case CMD_SEARCH_GOTONEXTFOUND: case CMD_SEARCH_GOTOPREVFOUND: return YES;
		case CMD_EDIT_UNDO: return [self sci:SCI_CANUNDO] != 0;
		case CMD_EDIT_REDO: return [self sci:SCI_CANREDO] != 0;
		default:
			break;
	}
	// Commands which modify the document
	if (readOnly) {
		static const int modifying[] = {
			CMD_EDIT_INSERT_DATETIME_SHORT, CMD_EDIT_INSERT_DATETIME_LONG, CMD_EDIT_INSERT_DATETIME_CUSTOM,
			CMD_EDIT_INS_TAB, CMD_EDIT_RMV_TAB, CMD_EDIT_UPPERCASE, CMD_EDIT_LOWERCASE, CMD_EDIT_PROPERCASE_FORCE,
			CMD_EDIT_PROPERCASE_BLEND, CMD_EDIT_SENTENCECASE_FORCE, CMD_EDIT_SENTENCECASE_BLEND, CMD_EDIT_INVERTCASE,
			CMD_EDIT_RANDOMCASE, CMD_EDIT_DUP_LINE, CMD_EDIT_REMOVE_ANY_DUP_LINES, CMD_EDIT_REMOVE_CONSECUTIVE_DUP_LINES,
			CMD_EDIT_SPLIT_LINES, CMD_EDIT_JOIN_LINES, CMD_EDIT_LINE_UP, CMD_EDIT_LINE_DOWN, CMD_EDIT_REMOVEEMPTYLINES,
			CMD_EDIT_REMOVEEMPTYLINESWITHBLANK, CMD_EDIT_BLANKLINEABOVECURRENT, CMD_EDIT_BLANKLINEBELOWCURRENT,
			CMD_EDIT_DELETE_LINE, CMD_EDIT_BLOCK_COMMENT, CMD_EDIT_BLOCK_COMMENT_SET, CMD_EDIT_BLOCK_UNCOMMENT,
			CMD_EDIT_STREAM_COMMENT, CMD_EDIT_STREAM_UNCOMMENT, CMD_EDIT_TRIMTRAILING, CMD_EDIT_TRIMLINEHEAD,
			CMD_EDIT_TRIM_BOTH, CMD_EDIT_EOL2WS, CMD_EDIT_TRIMALL, CMD_EDIT_TAB2SW, CMD_EDIT_SW2TAB_ALL,
			CMD_EDIT_SW2TAB_LEADING, CMD_EDIT_PASTE_AS_HTML, CMD_EDIT_PASTE_AS_RTF, CMD_EDIT_COLUMNMODE,
			CMD_EDIT_REDACT_SELECTION, CMD_SEARCH_REPLACE, CMD_SEARCH_CUTMARKEDLINES, CMD_SEARCH_PASTEMARKEDLINES,
			CMD_SEARCH_DELETEMARKEDLINES, CMD_SEARCH_DELETEUNMARKEDLINES, CMD_MACRO_PLAYBACK,
		};
		for (int m : modifying)
			if (m == cmd)
				return NO;
		if (cmd >= CMD_EDIT_SORT_REVERSE && cmd <= CMD_EDIT_SORT_LEN_DESC)
			return NO;
	}
	return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	return [self validateUserInterfaceItem:menuItem];
}

// Standard edit actions sent when the editor is not first responder (e.g. toolbar)
- (void)undo:(id)sender { [self sci:SCI_UNDO]; }
- (void)redo:(id)sender { [self sci:SCI_REDO]; }
- (void)cut:(id)sender { [self.activeEditor.content performSelector:@selector(cut:) withObject:sender]; }
- (void)copy:(id)sender { [self.activeEditor.content performSelector:@selector(copy:) withObject:sender]; }
- (void)paste:(id)sender { [self sci:SCI_PASTE]; }
- (void)selectAll:(id)sender { [self sci:SCI_SELECTALL]; }
- (void)delete:(id)sender { [self sci:SCI_CLEAR]; }

// ---- Window delegate ------------------------------------------------------------

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self updateStatusBar];
}

- (NSApplicationPresentationOptions)window:(NSWindow *)window willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)proposedOptions
{
	return proposedOptions | NSApplicationPresentationAutoHideToolbar;
}

@end
