// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "MppScintillaView.h"
#import "MppTabBar.h"
#import "MppDocument.h"

NS_ASSUME_NONNULL_BEGIN

@class MppEditPane;

@protocol MppEditPaneDelegate <NSObject>
- (void)editPane:(MppEditPane *)pane didActivateDocument:(MppDocument *)doc;
- (void)editPane:(MppEditPane *)pane notification:(SCNotification *)n;
- (void)editPane:(MppEditPane *)pane requestCloseDocument:(MppDocument *)doc;
- (void)editPane:(MppEditPane *)pane moveDocument:(MppDocument *)doc toPane:(MppEditPane *)target atIndex:(NSInteger)index;
- (NSMenu *)editPane:(MppEditPane *)pane tabMenuForDocument:(MppDocument *)doc;
- (void)editPaneRequestsNewDocument:(MppEditPane *)pane;
@end

// One editor "view": a tab bar and a Scintilla editor that switches between documents
@interface MppEditPane : NSView <MppTabBarDelegate, ScintillaNotificationProtocol>

@property (nonatomic, weak) id<MppEditPaneDelegate> delegate;
@property (nonatomic, readonly) MppTabBar *tabBar;
@property (nonatomic, readonly) MppScintillaView *editor;
@property (nonatomic, readonly) NSArray<MppDocument *> *documents;
@property (nonatomic, readonly, nullable) MppDocument *currentDocument;
@property (nonatomic) BOOL active;

- (void)addDocument:(MppDocument *)doc atIndex:(NSInteger)index activate:(BOOL)activate;
- (void)activateDocument:(MppDocument *)doc;
- (void)removeDocument:(MppDocument *)doc;           // does not release the document
- (void)moveDocumentFromIndex:(NSInteger)from toIndex:(NSInteger)to;
- (NSInteger)indexOfDocument:(MppDocument *)doc;
- (void)saveCurrentPosition;
- (void)restyleCurrentDocument;                       // re-apply lexer/theme/prefs to the current document
- (void)refreshTabs;
- (sptr_t)sci:(unsigned int)msg;
- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w;
- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w l:(sptr_t)l;

@end

NS_ASSUME_NONNULL_END
