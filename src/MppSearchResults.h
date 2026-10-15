// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "MppScintillaView.h"
#include <string>
#include <vector>

@class MppMainWindowController, MppDocument;

struct MppSearchHit {
	std::string lineText;                      // the matching line (UTF-8, without EOL)
	sptr_t lineNumber = 0;                     // 0-based
	sptr_t docStart = 0, docEnd = 0;           // absolute positions of the first match (for navigation)
	std::vector<std::pair<sptr_t, sptr_t>> ranges;  // match ranges relative to line start
};

// The "Search results" panel (styled with the searchResult lexer)
@interface MppSearchResultsPanel : NSView <ScintillaNotificationProtocol>

@property (nonatomic, weak) MppMainWindowController *owner;
@property (nonatomic, readonly) MppScintillaView *resultView;
@property (nonatomic, copy) void (^onClose)(void);

- (void)beginSearch:(NSString *)what;
- (void)addFile:(NSString *)path hits:(const std::vector<MppSearchHit> &)hits;
- (void)finishSearchWithFileCount:(NSInteger)files searched:(NSInteger)searched inSelection:(BOOL)sel;
- (void)gotoResult:(BOOL)forward;   // F4 / Shift+F4
- (void)applyTheme;
- (void)clearAll;

@end
