// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

@class MppMainWindowController;

// Macro recording/playback (Macro menu). A macro is a list of Scintilla
// messages (from SCN_MACRORECORD) and Macpad++ menu commands.
@interface MppMacroManager : NSObject

@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) BOOL hasRecordedMacro;
@property (nonatomic, readonly) NSArray<NSDictionary *> *savedMacros;   // {name, steps}

- (void)startRecording:(ScintillaView *)view;
- (void)stopRecording:(ScintillaView *)view;
- (void)recordNotification:(SCNotification *)n;
- (void)recordCommand:(int)cmd;
- (void)recordFind:(NSDictionary *)findStep;   // find/replace action (replayed through the find dialog)
+ (BOOL)isRecordableCommand:(int)cmd;

- (void)playCurrentOn:(MppMainWindowController *)owner times:(NSInteger)times untilEnd:(BOOL)untilEnd;
- (void)playSaved:(NSInteger)index on:(MppMainWindowController *)owner;
- (void)playSteps:(NSArray<NSDictionary *> *)steps on:(MppMainWindowController *)owner times:(NSInteger)times untilEnd:(BOOL)untilEnd;
- (BOOL)saveCurrentAs:(NSString *)name;
- (void)deleteSaved:(NSInteger)index;
- (void)renameSaved:(NSInteger)index to:(NSString *)name;
- (NSArray *)stepsOfSaved:(NSInteger)index;
- (void)setCurrentSteps:(NSArray *)steps;

@end
