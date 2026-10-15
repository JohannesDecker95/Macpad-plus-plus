// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "MppLanguages.h"

// Indicators reserved by the application (indicator numbers 21..31)
enum {
	MPP_INDIC_FOUND_STYLE_EXT5 = 21,
	MPP_INDIC_FOUND_STYLE_EXT4 = 22,
	MPP_INDIC_FOUND_STYLE_EXT3 = 23,
	MPP_INDIC_FOUND_STYLE_EXT2 = 24,
	MPP_INDIC_FOUND_STYLE_EXT1 = 25,
	MPP_INDIC_TAGATTR = 26,
	MPP_INDIC_TAGMATCH = 27,
	MPP_INDIC_FOUND_STYLE_INC = 28,
	MPP_INDIC_FOUND_STYLE_SMART = 29,
	MPP_INDIC_FOUND_STYLE = 31,
};

// Margins and markers (numbers shared with theme and session files)
enum {
	MPP_MARGIN_LINENUMBER = 0,
	MPP_MARGIN_SYMBOL = 1,
	MPP_MARGIN_CHANGEHISTORY = 2,
	MPP_MARGIN_FOLDER = 3,
	MPP_MARK_BOOKMARK = 20,
	MPP_MARK_HIDELINESBEGIN = 19,
	MPP_MARK_HIDELINESEND = 18,
};

// Applies language definitions, themes and view preferences to a ScintillaView.
// This is a port of ScintillaEditView::defineDocType / performGlobalStyles / setXXXLexer.
@interface MppStyler : NSObject

+ (void)initializeView:(ScintillaView *)view;                    // one-time setup of a new view
+ (void)defineDocType:(MppLangType)lang inView:(ScintillaView *)view;  // lexer + styles
+ (void)applyGlobalStyles:(ScintillaView *)view;                  // theme colours for caret, margins...
+ (void)applyViewPreferences:(ScintillaView *)view lang:(MppLangType)lang;  // prefs: wrap, margins, tabs...
+ (void)updateLineNumberWidth:(ScintillaView *)view;
+ (void)setupSearchResultView:(ScintillaView *)view;
+ (NSString *)effectiveFontName;
+ (int)effectiveFontSize;

@end
