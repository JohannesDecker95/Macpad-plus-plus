// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

@class MppMainWindowController;

NSString *MppAskString(NSString *title, NSString *prompt, NSString *defaultValue);
void MppShowTextResult(NSString *title, NSString *text);
NSString *MppHashData(NSData *data, int algo);   // 0 MD5, 1 SHA-1, 2 SHA-256, 3 SHA-512

void MppShowGoToDialog(MppMainWindowController *owner);
void MppShowColumnEditor(MppMainWindowController *owner);
void MppShowFindCharsInRange(MppMainWindowController *owner);
// The actions behind the two dialogs above
void MppColumnInsert(MppMainWindowController *owner, BOOL isText, NSString *text, long long initial, long long step,
                     long long repeat, int base, int leading);   // leading: 0 none, 1 zeros, 2 spaces
BOOL MppFindCharsInRange(MppMainWindowController *owner, long lo, long hi, BOOL forward, BOOL wrap);
void MppShowWindowsDialog(MppMainWindowController *owner);
void MppShowHashDialog(int algo);
void MppShowShortcutList(NSMenu *mainMenu);
void MppShowAbout(void);
void MppShowCommandLineHelp(void);
void MppShowDebugInfo(void);

// Run menu
NSArray<NSDictionary *> *MppSavedRunCommands(void);   // {name, command}
void MppShowRunDialog(MppMainWindowController *owner);
void MppShowManageRunCommands(MppMainWindowController *owner);
void MppRunCommandLine(MppMainWindowController *owner, NSString *command);

// Macro menu
void MppShowRunMacroMultiple(MppMainWindowController *owner);
void MppShowManageMacros(MppMainWindowController *owner);

@interface MppPreferencesController : NSWindowController <NSWindowDelegate>
+ (void)show;
@end

@interface MppStyleConfiguratorController : NSWindowController <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
+ (void)show;
@end
