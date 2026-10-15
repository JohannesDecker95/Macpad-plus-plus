// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

#ifdef __cplusplus
struct UserLang;
#endif

// Posted after a language was edited, renamed or removed. userInfo: @"name" (new name or nil when removed), @"oldName"
extern NSString *const MppUserLangDidChangeNotification;

// User Defined Languages: loads UDL files (userDefineLang.xml and
// userDefineLangs/*.xml) and drives the "user" lexer (LexUser.cxx) with them.
@interface MppUserLangManager : NSObject

+ (instancetype)shared;
- (void)reload;
- (NSString *)directory;                                 // ~/Library/Application Support/Macpad++/userDefineLangs
- (NSArray<NSString *> *)languageNames;
- (NSString *)languageForFileName:(NSString *)fileName;  // nil if no UDL claims the extension
- (NSInteger)importFile:(NSString *)path;                // returns number of languages imported
- (void)applyLanguage:(NSString *)name toView:(ScintillaView *)view documentID:(int)docID;
- (NSString *)commentLineForLanguage:(NSString *)name;   // first line-comment token, for Toggle Comment

// Editing ("Define your language")
#ifdef __cplusplus
- (UserLang *)languageNamed:(NSString *)name;            // mutable; only valid until the next create / remove
#endif
- (BOOL)isBundledLanguage:(NSString *)name;
- (BOOL)createLanguage:(NSString *)name copyOf:(NSString *)source;   // source nil: an empty language
- (BOOL)renameLanguage:(NSString *)name to:(NSString *)newName;
- (void)removeLanguage:(NSString *)name;
- (void)languageDidChange:(NSString *)name;             // re-applies it to open documents and saves it shortly after
- (BOOL)saveLanguage:(NSString *)name;
- (BOOL)exportLanguage:(NSString *)name toPath:(NSString *)path;

@end
