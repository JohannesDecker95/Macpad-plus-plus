// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppPrefs.h"
#import "MppPaths.h"

NSString *const MppPrefsChangedNotification = @"MppPrefsChangedNotification";

#define MPP_BOOL(getter, setter, key) \
	- (BOOL)getter { return [_d boolForKey:@key]; } \
	- (void)setter:(BOOL)v { [_d setBool:v forKey:@key]; }
#define MPP_INT(type, getter, setter, key) \
	- (type)getter { return (type)[_d integerForKey:@key]; } \
	- (void)setter:(type)v { [_d setInteger:v forKey:@key]; }
#define MPP_STR(getter, setter, key) \
	- (NSString *)getter { return [_d stringForKey:@key]; } \
	- (void)setter:(NSString *)v { [_d setObject:v forKey:@key]; }
#define MPP_ARR(getter, setter, key) \
	- (NSArray *)getter { return [_d stringArrayForKey:@key] ?: @[]; } \
	- (void)setter:(NSArray *)v { [_d setObject:v ?: @[] forKey:@key]; }

@implementation MppPrefs {
	NSUserDefaults *_d;
}

+ (instancetype)shared
{
	static MppPrefs *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[MppPrefs alloc] init]; });
	return s;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_d = MppDefaults();
		[_d registerDefaults:@{
			@"tabSize": @4, @"useSpaces": @NO, @"autoIndent": @YES,
			@"autoCloseParen": @NO, @"autoCloseBracket": @NO, @"autoCloseCurly": @NO,
			@"autoCloseQuote": @NO, @"autoCloseDoubleQuote": @NO, @"autoCloseHtmlXmlTag": @NO,
			@"multiEditing": @YES, @"virtualSpace": @NO, @"scrollBeyondLastLine": @NO,
			@"copyLineWithoutSelection": @YES, @"caretWidth": @1, @"caretBlinkRate": @600,
			@"showLineNumbers": @YES, @"showBookmarkMargin": @YES, @"showChangeHistory": @YES,
			@"foldStyle": @(MppFoldStyleBoxTree), @"wordWrap": @NO, @"showWrapSymbol": @NO,
			@"showWhitespace": @NO, @"showEOL": @NO, @"showIndentGuides": @YES, @"showNonPrinting": @NO,
			@"highlightCurrentLine": @YES, @"edgeMode": @(MppEdgeNone), @"edgeColumn": @80,
			@"smartHighlighting": @YES, @"smartHighlightMatchCase": @NO, @"smartHighlightWholeWord": @YES,
			@"matchTagHighlighting": @YES,
			@"showStatusBar": @YES, @"showToolbar": @YES, @"showTabCloseButton": @YES,
			@"doubleClickClosesTab": @NO, @"alwaysOnTop": @NO, @"zoom": @0,
			@"themeName": @"Default (stylers.xml)", @"darkThemeName": @"DarkModeDefault",
			@"followSystemAppearance": @YES,
			@"useMacFont": @YES, @"macFontName": @"Menlo", @"macFontSize": @12,
			@"defaultDocEOL": @(MppEOLUnix), @"defaultDocEncoding": @"UTF-8", @"defaultDocLang": @0,
			@"rememberSession": @YES, @"sessionSnapshot": @YES, @"backupInterval": @7,
			@"fileAutoDetection": @(MppFileAutoDetectAsk), @"autoDetectEncoding": @YES,
			@"maxRecentFiles": @15, @"trimTrailingOnSave": @NO,
			@"autoCompleteMode": @(MppAutoCompleteBoth), @"autoCompleteFromChar": @1,
			@"autoCompleteIgnoreNumbers": @YES, @"funcParamsHint": @YES,
			@"searchEngineURL": @"https://www.google.com/search?q=$(CURRENT_WORD)",
			@"dateTimeFormat": @"yyyy-MM-dd HH:mm:ss", @"backslashEscapeSQL": @NO,
		}];
	}
	return self;
}

- (void)notifyChanged
{
	[NSNotificationCenter.defaultCenter postNotificationName:MppPrefsChangedNotification object:self];
}

MPP_INT(NSInteger, tabSize, setTabSize, "tabSize")
MPP_BOOL(useSpaces, setUseSpaces, "useSpaces")
MPP_BOOL(autoIndent, setAutoIndent, "autoIndent")
MPP_BOOL(autoCloseParen, setAutoCloseParen, "autoCloseParen")
MPP_BOOL(autoCloseBracket, setAutoCloseBracket, "autoCloseBracket")
MPP_BOOL(autoCloseCurly, setAutoCloseCurly, "autoCloseCurly")
MPP_BOOL(autoCloseQuote, setAutoCloseQuote, "autoCloseQuote")
MPP_BOOL(autoCloseDoubleQuote, setAutoCloseDoubleQuote, "autoCloseDoubleQuote")
MPP_BOOL(autoCloseHtmlXmlTag, setAutoCloseHtmlXmlTag, "autoCloseHtmlXmlTag")
MPP_BOOL(multiEditing, setMultiEditing, "multiEditing")
MPP_BOOL(virtualSpace, setVirtualSpace, "virtualSpace")
MPP_BOOL(scrollBeyondLastLine, setScrollBeyondLastLine, "scrollBeyondLastLine")
MPP_BOOL(copyLineWithoutSelection, setCopyLineWithoutSelection, "copyLineWithoutSelection")
MPP_INT(NSInteger, caretWidth, setCaretWidth, "caretWidth")
MPP_INT(NSInteger, caretBlinkRate, setCaretBlinkRate, "caretBlinkRate")

MPP_BOOL(showLineNumbers, setShowLineNumbers, "showLineNumbers")
MPP_BOOL(showBookmarkMargin, setShowBookmarkMargin, "showBookmarkMargin")
MPP_BOOL(showChangeHistory, setShowChangeHistory, "showChangeHistory")
MPP_INT(MppFoldStyle, foldStyle, setFoldStyle, "foldStyle")
MPP_BOOL(wordWrap, setWordWrap, "wordWrap")
MPP_BOOL(showWrapSymbol, setShowWrapSymbol, "showWrapSymbol")
MPP_BOOL(showWhitespace, setShowWhitespace, "showWhitespace")
MPP_BOOL(showEOL, setShowEOL, "showEOL")
MPP_BOOL(showIndentGuides, setShowIndentGuides, "showIndentGuides")
MPP_BOOL(showNonPrinting, setShowNonPrinting, "showNonPrinting")
MPP_BOOL(highlightCurrentLine, setHighlightCurrentLine, "highlightCurrentLine")
MPP_INT(MppEdgeMode, edgeMode, setEdgeMode, "edgeMode")
MPP_INT(NSInteger, edgeColumn, setEdgeColumn, "edgeColumn")
MPP_BOOL(smartHighlighting, setSmartHighlighting, "smartHighlighting")
MPP_BOOL(smartHighlightMatchCase, setSmartHighlightMatchCase, "smartHighlightMatchCase")
MPP_BOOL(smartHighlightWholeWord, setSmartHighlightWholeWord, "smartHighlightWholeWord")
MPP_BOOL(matchTagHighlighting, setMatchTagHighlighting, "matchTagHighlighting")
MPP_BOOL(showStatusBar, setShowStatusBar, "showStatusBar")
MPP_BOOL(showToolbar, setShowToolbar, "showToolbar")
MPP_BOOL(showTabCloseButton, setShowTabCloseButton, "showTabCloseButton")
MPP_BOOL(doubleClickClosesTab, setDoubleClickClosesTab, "doubleClickClosesTab")
MPP_BOOL(alwaysOnTop, setAlwaysOnTop, "alwaysOnTop")
MPP_INT(NSInteger, zoom, setZoom, "zoom")

MPP_STR(themeName, setThemeName, "themeName")
MPP_STR(darkThemeName, setDarkThemeName, "darkThemeName")
MPP_BOOL(followSystemAppearance, setFollowSystemAppearance, "followSystemAppearance")
MPP_BOOL(useMacFont, setUseMacFont, "useMacFont")
MPP_STR(macFontName, setMacFontName, "macFontName")
MPP_INT(NSInteger, macFontSize, setMacFontSize, "macFontSize")

MPP_INT(MppEOLType, defaultDocEOL, setDefaultDocEOL, "defaultDocEOL")
MPP_STR(defaultDocEncoding, setDefaultDocEncoding, "defaultDocEncoding")
MPP_INT(NSInteger, defaultDocLang, setDefaultDocLang, "defaultDocLang")

MPP_BOOL(rememberSession, setRememberSession, "rememberSession")
MPP_BOOL(sessionSnapshot, setSessionSnapshot, "sessionSnapshot")
MPP_INT(NSInteger, backupInterval, setBackupInterval, "backupInterval")
MPP_INT(MppFileAutoDetect, fileAutoDetection, setFileAutoDetection, "fileAutoDetection")
MPP_BOOL(autoDetectEncoding, setAutoDetectEncoding, "autoDetectEncoding")
MPP_INT(NSInteger, maxRecentFiles, setMaxRecentFiles, "maxRecentFiles")
MPP_ARR(recentFiles, setRecentFiles, "recentFiles")
MPP_BOOL(trimTrailingOnSave, setTrimTrailingOnSave, "trimTrailingOnSave")

MPP_INT(MppAutoCompleteMode, autoCompleteMode, setAutoCompleteMode, "autoCompleteMode")
MPP_INT(NSInteger, autoCompleteFromChar, setAutoCompleteFromChar, "autoCompleteFromChar")
MPP_BOOL(autoCompleteIgnoreNumbers, setAutoCompleteIgnoreNumbers, "autoCompleteIgnoreNumbers")
MPP_BOOL(funcParamsHint, setFuncParamsHint, "funcParamsHint")

MPP_STR(searchEngineURL, setSearchEngineURL, "searchEngineURL")
MPP_STR(dateTimeFormat, setDateTimeFormat, "dateTimeFormat")
MPP_BOOL(backslashEscapeSQL, setBackslashEscapeSQL, "backslashEscapeSQL")
MPP_ARR(findHistory, setFindHistory, "findHistory")
MPP_ARR(replaceHistory, setReplaceHistory, "replaceHistory")
MPP_ARR(filterHistory, setFilterHistory, "filterHistory")
MPP_ARR(dirHistory, setDirHistory, "dirHistory")

- (void)addRecentFile:(NSString *)path
{
	if (!path.length)
		return;
	NSMutableArray *a = [self.recentFiles mutableCopy];
	[a removeObject:path];
	[a insertObject:path atIndex:0];
	while ((NSInteger)a.count > MAX(self.maxRecentFiles, 0))
		[a removeLastObject];
	self.recentFiles = a;
}

- (void)removeRecentFile:(NSString *)path
{
	NSMutableArray *a = [self.recentFiles mutableCopy];
	[a removeObject:path];
	self.recentFiles = a;
}

@end
