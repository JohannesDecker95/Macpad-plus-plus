// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

@class MppTabBar, MppDocument;

@protocol MppTabBarDelegate <NSObject>
- (void)tabBar:(MppTabBar *)bar didSelectIndex:(NSInteger)index;
- (void)tabBar:(MppTabBar *)bar closeIndex:(NSInteger)index;
- (void)tabBar:(MppTabBar *)bar moveIndex:(NSInteger)from toIndex:(NSInteger)to;
- (void)tabBar:(MppTabBar *)bar dropIndex:(NSInteger)index ontoBar:(MppTabBar *)target atIndex:(NSInteger)targetIndex;
- (NSMenu *)tabBar:(MppTabBar *)bar menuForIndex:(NSInteger)index;
- (void)tabBarDoubleClickedEmptyArea:(MppTabBar *)bar;
@end

// Document tab bar
@interface MppTabBar : NSView
@property (nonatomic, weak) id<MppTabBarDelegate> delegate;
@property (nonatomic, copy) NSArray<MppDocument *> *documents;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic) BOOL focused;       // pane has keyboard focus (active tab indicator colour)
- (void)reload;
- (void)scrollToSelected;
- (NSInteger)indexAtPoint:(NSPoint)p;     // in view coordinates; NSNotFound if none
- (NSInteger)insertionIndexAtPoint:(NSPoint)p;
@end
