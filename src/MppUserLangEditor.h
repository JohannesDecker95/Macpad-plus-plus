// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// "Define your language": the editor for User Defined Languages (UserDefineDialog on Windows).
// Every change is applied to open documents right away and saved to the language's file.
@interface MppUserLangEditor : NSWindowController <NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate>

+ (instancetype)shared;
- (void)showLanguage:(nullable NSString *)name;   // nil: keep the current selection
@property (nonatomic, readonly, nullable) NSString *languageName;

// Field access by key (used by the self test): "ext", "kw<N>" (keyword list N), "cm<N>" (comment field N),
// "dl<N>" (delimiter field N)
- (void)setText:(NSString *)text forField:(NSString *)key;
- (nullable NSString *)textForField:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
