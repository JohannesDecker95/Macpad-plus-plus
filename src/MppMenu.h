// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

// Identifiers of menus whose content is rebuilt on demand (via NSMenuDelegate)
extern NSString *const MppMenuRecent;
extern NSString *const MppMenuMacros;
extern NSString *const MppMenuRun;
extern NSString *const MppMenuUserLangs;

@interface MppMenu : NSObject
+ (NSMenu *)buildMainMenuWithDelegate:(id<NSMenuDelegate>)delegate;
+ (NSMenuItem *)itemWithTitle:(NSString *)title command:(int)cmd key:(NSString *)key modifiers:(NSEventModifierFlags)mods;
+ (NSMenu *)languageMenu;          // grouped by first letter
+ (NSMenu *)encodingMenu;
+ (NSMenu *)eolMenu;
@end
