// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "MppLanguages.h"

// Auto-completion and function call tips driven by the APIs/*.xml files
// (AutoCompletion.cpp / FunctionCallTip.cpp)
@interface MppAutoCompletion : NSObject
+ (void)showFunctionCompletion:(ScintillaView *)v lang:(MppLangType)lang;
+ (void)showWordCompletion:(ScintillaView *)v lang:(MppLangType)lang;
+ (void)showCallTip:(ScintillaView *)v lang:(MppLangType)lang;
+ (void)showPathCompletion:(ScintillaView *)v baseDir:(NSString *)dir;
+ (void)charAdded:(int)ch view:(ScintillaView *)v lang:(MppLangType)lang;
+ (void)callTipClicked:(ScintillaView *)v arrow:(int)position;
@end
