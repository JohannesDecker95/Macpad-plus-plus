// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "MppScintillaView.h"

@class MppMainWindowController, MppDocument;

// Function List panel: parses the current document with the functionList/*.xml rules
@interface MppFunctionListPanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
- (void)reload;
@end

// Document List panel
@interface MppDocumentListPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
- (void)reload;
@end

// Folder as Workspace panel
@interface MppFileBrowserPanel : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
@property (nonatomic, readonly) NSArray<NSString *> *rootFolders;
- (void)addRootFolder:(NSString *)path;
- (void)removeAllRoots;
@end

// Clipboard History panel
@interface MppClipboardHistoryPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
@end

// Character Panel (ASCII Codes Insertion Panel)
@interface MppCharacterPanel : NSView <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
@end

// Document Map: a zoomed-out view of the current document
@interface MppDocumentMapPanel : NSView <ScintillaNotificationProtocol>
@property (nonatomic, weak) MppMainWindowController *owner;
- (void)syncWithEditor;
- (void)documentChanged;
@end
