// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

// A docking area for Macpad++ panels (Function List, Document List, Folder as Workspace...).
// Several panels in the same dock are shown as tabs.
@interface MppDockContainer : NSView

@property (nonatomic, copy) void (^onPanelClosed)(NSString *identifier);
@property (nonatomic, readonly) BOOL isEmpty;
@property (nonatomic, readonly) NSString *selectedIdentifier;

- (void)addPanel:(NSView *)view identifier:(NSString *)identifier title:(NSString *)title;
- (void)removePanel:(NSString *)identifier;
- (BOOL)hasPanel:(NSString *)identifier;
- (void)selectPanel:(NSString *)identifier;
- (NSView *)panelView:(NSString *)identifier;

@end
