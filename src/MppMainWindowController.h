// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "MppEditPane.h"
#import "MppStatusBar.h"
#import "MppDocument.h"
#import "MppCommands.h"

NS_ASSUME_NONNULL_BEGIN

@class MppFindReplaceController, MppSearchResultsPanel, MppDockContainer, MppMacroManager, MppDocumentMapPanel;

// The Macpad++ main window: two edit views, dockable panels, search results, status bar.
@interface MppMainWindowController : NSWindowController <NSWindowDelegate, MppEditPaneDelegate, NSSplitViewDelegate,
                                                         NSToolbarDelegate, NSMenuItemValidation, NSMenuDelegate>

@property (nonatomic, readonly) MppEditPane *mainPane;
@property (nonatomic, readonly) MppEditPane *subPane;
@property (nonatomic, readonly) MppEditPane *activePane;
@property (nonatomic, readonly) MppEditPane *otherPane;
@property (nonatomic, readonly) MppScintillaView *activeEditor;
@property (nonatomic, readonly, nullable) MppDocument *currentDocument;
@property (nonatomic, readonly) MppStatusBar *statusBar;
@property (nonatomic, readonly) MppFindReplaceController *findReplace;
@property (nonatomic, readonly) MppSearchResultsPanel *searchResults;
@property (nonatomic, readonly) MppDockContainer *leftDock;
@property (nonatomic, readonly) MppDockContainer *rightDock;
@property (nonatomic, readonly) MppMacroManager *macros;
@property (nonatomic) BOOL syncVerticalScroll, syncHorizontalScroll;
@property (nonatomic) BOOL distractionFree;
@property (nonatomic, readonly, nullable) MppDocumentMapPanel *documentMapPanel;

+ (instancetype)shared;

// Scintilla access on the active editor
- (sptr_t)sci:(unsigned int)msg;
- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w;
- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w l:(sptr_t)l;
- (std::string)selectedText;
- (std::string)currentWordOrSelection;
- (std::string)textRangeFrom:(sptr_t)start to:(sptr_t)end;

// Documents
- (NSArray<MppDocument *> *)allDocuments;
- (nullable MppEditPane *)paneForDocument:(MppDocument *)doc;
- (nullable MppDocument *)openPath:(NSString *)path;
- (nullable MppDocument *)openPath:(NSString *)path activate:(BOOL)activate;
- (void)openPaths:(NSArray<NSString *> *)paths;
- (MppDocument *)newDocument;
- (void)activateDocument:(MppDocument *)doc;
- (BOOL)saveDocument:(MppDocument *)doc;
- (BOOL)saveDocumentAs:(MppDocument *)doc copy:(BOOL)copy;
- (BOOL)saveAll;
- (BOOL)closeDocument:(MppDocument *)doc inPane:(MppEditPane *)pane;
- (BOOL)closeDocuments:(NSArray<MppDocument *> *)docs;
- (void)setLanguage:(MppLangType)lang forDocument:(MppDocument *)doc;
- (void)restyleAllViews;         // after theme or preference changes
- (void)reloadThemeForced;       // reload the theme file (after editing it)
- (void)documentDisplayChanged:(MppDocument *)doc;  // re-apply settings (read-only, lang) where shown
- (void)updatePaneVisibility;
- (void)gotoLine:(sptr_t)line;
- (void)selectRangeFrom:(sptr_t)start to:(sptr_t)end;   // select and ensure visible in the active editor
- (void)setStatusMessage:(nullable NSString *)msg;

// Panels
- (void)showSearchResults:(BOOL)show;
- (void)toggleFunctionList;
- (void)toggleDocumentList;
- (void)toggleFolderAsWorkspace;
- (void)toggleDocumentMap;
- (void)toggleClipboardHistory;
- (void)toggleCharacterPanel;
- (void)openFolderAsWorkspace:(NSString *)folder;

// Sessions
- (void)restoreSession;
- (void)restoreSessionWithoutFiles;   // -nosession
- (void)saveSessionToPath:(nullable NSString *)path includeBackups:(BOOL)backups;
- (void)loadSessionFromPath:(NSString *)path;
- (BOOL)prepareToQuit;

// Commands
- (void)mppCommand:(id)sender;
- (void)executeCommand:(int)cmd;
- (void)updateStatusBar;
- (void)updateTitle;

@end

// Command handlers implemented in categories (return YES if the command was handled)
@interface MppMainWindowController (Edit)
- (BOOL)handleEditCommand:(int)cmd;
- (void)insertDateTime:(int)cmd;
- (void)toggleLineComment:(int)mode;   // 0 toggle, 1 comment, 2 uncomment
- (void)streamComment:(BOOL)comment;
@end

@interface MppMainWindowController (Search)
- (BOOL)handleSearchCommand:(int)cmd;
@end

@interface MppMainWindowController (View)
- (BOOL)handleViewCommand:(int)cmd;
- (void)handleUpdateUI:(SCNotification *)n pane:(MppEditPane *)pane;
- (void)handleCharAdded:(SCNotification *)n pane:(MppEditPane *)pane;
@end

@interface MppMainWindowController (Tools)
- (BOOL)handleToolsCommand:(int)cmd;
- (void)printDocument;
- (NSPrintOperation *)printOperationWithInfo:(NSPrintInfo *)info;   // without panels
@end

NS_ASSUME_NONNULL_END
