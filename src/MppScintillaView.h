// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

// ScintillaView with editor behaviours: custom context menu, copy/cut of the current
// line when nothing is selected, and Delete (delete:) support.
@interface MppScintillaView : ScintillaView
@property (nonatomic, copy) NSMenu *(^contextMenuProvider)(MppScintillaView *view);
@property (nonatomic, copy) BOOL (^keyDownHandler)(MppScintillaView *view, NSEvent *event);  // return YES if handled
@end
