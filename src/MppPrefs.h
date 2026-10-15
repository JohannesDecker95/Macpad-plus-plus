// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

extern NSString *const MppPrefsChangedNotification;

typedef NS_ENUM(NSInteger, MppFoldStyle) {
	MppFoldStyleNone = 0, MppFoldStyleSimple, MppFoldStyleArrow, MppFoldStyleCircleTree, MppFoldStyleBoxTree
};

typedef NS_ENUM(NSInteger, MppEdgeMode) { MppEdgeNone = 0, MppEdgeLine, MppEdgeBackground };

typedef NS_ENUM(NSInteger, MppFileAutoDetect) {
	MppFileAutoDetectDisabled = 0, MppFileAutoDetectAsk, MppFileAutoDetectSilent
};

typedef NS_ENUM(NSInteger, MppEOLType) { MppEOLWindows = 0, MppEOLMac = 1, MppEOLUnix = 2 }; // = SC_EOL_*

typedef NS_ENUM(NSInteger, MppAutoCompleteMode) {
	MppAutoCompleteOff = 0, MppAutoCompleteFunction, MppAutoCompleteWord, MppAutoCompleteBoth
};

// User preferences (Settings > Preferences). Stored in NSUserDefaults.
@interface MppPrefs : NSObject

+ (instancetype)shared;
- (void)notifyChanged;   // post MppPrefsChangedNotification

// Editing
@property (nonatomic) NSInteger tabSize;
@property (nonatomic) BOOL useSpaces;
@property (nonatomic) BOOL autoIndent;
@property (nonatomic) BOOL autoCloseParen, autoCloseBracket, autoCloseCurly, autoCloseQuote, autoCloseDoubleQuote;
@property (nonatomic) BOOL autoCloseHtmlXmlTag;
@property (nonatomic) BOOL multiEditing;
@property (nonatomic) BOOL virtualSpace;
@property (nonatomic) BOOL scrollBeyondLastLine;
@property (nonatomic) BOOL copyLineWithoutSelection;
@property (nonatomic) NSInteger caretWidth;
@property (nonatomic) NSInteger caretBlinkRate;

// Display
@property (nonatomic) BOOL showLineNumbers, showBookmarkMargin, showChangeHistory;
@property (nonatomic) MppFoldStyle foldStyle;
@property (nonatomic) BOOL wordWrap, showWrapSymbol;
@property (nonatomic) BOOL showWhitespace, showEOL, showIndentGuides, showNonPrinting;
@property (nonatomic) BOOL highlightCurrentLine;
@property (nonatomic) MppEdgeMode edgeMode;
@property (nonatomic) NSInteger edgeColumn;
@property (nonatomic) BOOL smartHighlighting, smartHighlightMatchCase, smartHighlightWholeWord;
@property (nonatomic) BOOL matchTagHighlighting;
@property (nonatomic) BOOL showStatusBar, showToolbar, showTabCloseButton, doubleClickClosesTab;
@property (nonatomic) BOOL alwaysOnTop;
@property (nonatomic) NSInteger zoom;

// Fonts & themes
@property (nonatomic, copy) NSString *themeName;
@property (nonatomic, copy) NSString *darkThemeName;
@property (nonatomic) BOOL followSystemAppearance;
@property (nonatomic) BOOL useMacFont;
@property (nonatomic, copy) NSString *macFontName;
@property (nonatomic) NSInteger macFontSize;

// New document
@property (nonatomic) MppEOLType defaultDocEOL;
@property (nonatomic, copy) NSString *defaultDocEncoding;   // "UTF-8", "UTF-8-BOM", ...
@property (nonatomic) NSInteger defaultDocLang;

// Files & sessions
@property (nonatomic) BOOL rememberSession;
@property (nonatomic) BOOL sessionSnapshot;
@property (nonatomic) NSInteger backupInterval;
@property (nonatomic) MppFileAutoDetect fileAutoDetection;
@property (nonatomic) BOOL autoDetectEncoding;
@property (nonatomic) NSInteger maxRecentFiles;
@property (nonatomic, copy) NSArray<NSString *> *recentFiles;
@property (nonatomic) BOOL trimTrailingOnSave;

// Auto-completion
@property (nonatomic) MppAutoCompleteMode autoCompleteMode;
@property (nonatomic) NSInteger autoCompleteFromChar;
@property (nonatomic) BOOL autoCompleteIgnoreNumbers;
@property (nonatomic) BOOL funcParamsHint;

// Misc
@property (nonatomic, copy) NSString *searchEngineURL;
@property (nonatomic, copy) NSString *dateTimeFormat;
@property (nonatomic) BOOL backslashEscapeSQL;
@property (nonatomic, copy) NSArray<NSString *> *findHistory, *replaceHistory, *filterHistory, *dirHistory;

- (void)addRecentFile:(NSString *)path;
- (void)removeRecentFile:(NSString *)path;
@end
