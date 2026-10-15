// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#include <string>

@class MppMainWindowController;

typedef NS_ENUM(NSInteger, MppFindTab) { MppFindTabFind = 0, MppFindTabReplace, MppFindTabFindInFiles, MppFindTabMark };
typedef NS_ENUM(NSInteger, MppSearchMode) { MppSearchNormal = 0, MppSearchExtended, MppSearchRegex };

struct MppFindOptions {
	bool matchCase = false;
	bool wholeWord = false;
	bool wrapAround = true;
	bool backward = false;
	bool inSelection = false;
	bool dotMatchesNewline = false;
	MppSearchMode mode = MppSearchNormal;
	bool bookmarkLine = false;
	bool purgeBeforeMark = false;
	bool inSubfolders = true;
	bool inHidden = false;
};

// Converts the "Extended" search syntax (\n \r \t \0 \\ \xNN \uNNNN \dNNN \oNNN \bNNNNNNNN) into raw text
std::string MppExpandExtended(const std::string &s);
// Scintilla search flags for the options (Boost regex flags included)
int MppSearchFlags(const MppFindOptions &o);

// The Find / Replace / Find in Files / Mark dialog (FindReplaceDlg)
@interface MppFindReplaceController : NSWindowController <NSWindowDelegate, NSTabViewDelegate, NSComboBoxDelegate>

@property (nonatomic, weak) MppMainWindowController *owner;
@property (nonatomic, readonly) MppFindOptions options;
@property (nonatomic, readonly) NSString *findText;

- (instancetype)initWithOwner:(MppMainWindowController *)owner;
- (void)showTab:(MppFindTab)tab;
- (void)setFindText:(NSString *)text;
- (void)setFindDirectory:(NSString *)dir;
- (BOOL)findNext:(BOOL)forward;                       // F3 / Shift+F3 with dialog options
- (BOOL)findText:(const std::string &)text forward:(BOOL)forward options:(MppFindOptions)o
          showStatus:(BOOL)status;                   // core "find next"
- (int)markAll:(const std::string &)text options:(MppFindOptions)o indicator:(int)indicator
         bookmark:(BOOL)bookmark;                    // used by "Style all occurrences"
- (void)showIncrementalSearch;

@end
