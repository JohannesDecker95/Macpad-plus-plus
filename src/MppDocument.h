// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "MppLanguages.h"
#import "MppEncoding.h"
#include <vector>

NS_ASSUME_NONNULL_BEGIN

@class MppDocument;

extern NSString *const MppDocumentChangedNotification;  // object = document; title/dirty/lang/encoding changed
extern NSString *const MppErrorDomain;
enum { MppErrorUnencodable = 2, MppErrorTooLarge = 3 };

// Saved caret/scroll state of a document inside one particular view
struct MppViewPosition {
	sptr_t anchor = 0, caret = 0;
	sptr_t firstVisibleDocLine = 0;
	sptr_t xOffset = 0;
	int selMode = 0;
	std::vector<sptr_t> foldedLines;
	bool valid = false;
};

// One open file (or untitled document) backed by a
// Scintilla document that can be shown in one or two views.
@interface MppDocument : NSObject

@property (nonatomic, copy, nullable) NSString *filePath;  // nil for untitled documents
@property (nonatomic, copy) NSString *untitledName;        // "new 1"...
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic) MppLangType lang;
@property (nonatomic) BOOL langSetByUser;
@property (nonatomic, copy, nullable) NSString *userLangName;   // when lang == L_USER
@property (nonatomic) MppEncoding encoding;
@property (nonatomic) int eolMode;                         // SC_EOL_CRLF / SC_EOL_CR / SC_EOL_LF
@property (nonatomic) BOOL dirty;
@property (nonatomic) BOOL userReadOnly;                   // Macpad++ "Read-Only" flag
@property (nonatomic, readonly) BOOL fileReadOnly;         // no write permission on disk
@property (nonatomic, strong, nullable) NSDate *fileModificationDate;
@property (nonatomic) BOOL fileDeleted;                    // file vanished from disk
@property (nonatomic) BOOL monitoring;                     // tail -f
@property (nonatomic) NSInteger tabColor;                  // -1 = none, 0..4
@property (nonatomic, readonly) sptr_t sciDocument;
@property (nonatomic, readonly) int docID;                 // unique id (used by the UDL lexer)
@property (nonatomic, copy, nullable) NSString *backupPath; // session snapshot file
@property (nonatomic) BOOL backupDirty;                    // modified since last backup
@property (nonatomic) NSInteger untitledNumber;
@property (nonatomic, readonly) BOOL isUntitled;

- (MppViewPosition &)positionForView:(ScintillaView *)view;

- (NSString *)encodingDisplayName;
- (NSString *)eolDisplayName;
- (void)notifyChanged;

@end

// Owns all documents and a hidden Scintilla view used to create/load/save documents
// (managed by MppDocumentManager with its "scratch" Scintilla).
@interface MppDocumentManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<MppDocument *> *documents;

- (MppDocument *)createUntitledDocument;
- (nullable MppDocument *)documentForPath:(NSString *)path;
- (nullable MppDocument *)openFile:(NSString *)path error:(NSError **)error;
- (nullable MppDocument *)openFile:(NSString *)path forcedEncoding:(const MppEncoding *_Nullable)forced error:(NSError **)error;
- (BOOL)reloadDocument:(MppDocument *)doc forcedEncoding:(const MppEncoding *_Nullable)forced error:(NSError **)error;
// Error MppErrorUnencodable means some characters cannot be represented; retry with lossy:YES.
- (BOOL)saveDocument:(MppDocument *)doc toPath:(NSString *)path copyOnly:(BOOL)copyOnly lossy:(BOOL)lossy error:(NSError **)error;
- (BOOL)saveDataWithAdminPrivileges:(NSData *)data toPath:(NSString *)path error:(NSError **)error;
- (nullable NSData *)encodedContentOfDocument:(MppDocument *)doc lossy:(BOOL)lossy;
- (void)closeDocument:(MppDocument *)doc;   // releases the Scintilla document
- (std::string)textOfDocument:(MppDocument *)doc;
- (void)setText:(const std::string &)text ofDocument:(MppDocument *)doc;  // undoable replace of full text
- (BOOL)writeBackupOfDocument:(MppDocument *)doc;
- (nullable MppDocument *)restoreDocumentFromBackup:(NSString *)backupPath originalPath:(nullable NSString *)path
                                          untitledName:(nullable NSString *)untitledName;
- (sptr_t)scratchMessage:(unsigned int)msg doc:(MppDocument *)doc wParam:(uptr_t)w lParam:(sptr_t)l;
// Direct access to the hidden view, e.g. to search a document that is not displayed.
// Every attach must be balanced by detachScratchView.
- (ScintillaView *)attachScratchViewTo:(MppDocument *)doc;
- (ScintillaView *)attachScratchViewToSciDocument:(sptr_t)sciDoc;
- (void)detachScratchView;
- (sptr_t)createSciDocumentWithText:(const std::string &)utf8;   // caller releases with releaseSciDocument
- (void)releaseSciDocument:(sptr_t)sciDoc;

@end

NS_ASSUME_NONNULL_END
