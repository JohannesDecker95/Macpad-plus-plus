// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Foundation/Foundation.h>

// File-system locations. User settings live in ~/Library/Application Support/Macpad++,
// (or in the directory given with -settingsDir).
@interface MppPaths : NSObject
+ (NSString *)resourceDirectory;
+ (void)setUserDataDirectory:(NSString *)dir;   // -settingsDir=<path>; call before anything reads settings
+ (NSString *)userDataDirectory;      // created on demand
+ (NSString *)backupDirectory;        // session snapshot backups
+ (NSString *)userFileOrBundled:(NSString *)name;  // user override if present, else bundled copy
@end

// The preferences store: the standard user defaults, or a separate domain when -settingsDir is used
NSUserDefaults *MppDefaults(void);
NSString *MppDefaultsSuiteName(void);   // nil unless -settingsDir is used
