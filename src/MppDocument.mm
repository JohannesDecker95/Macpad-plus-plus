// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppDocument.h"
#import "MppPrefs.h"
#import "MppPaths.h"
#import "MppUserLang.h"
#include "Scintilla.h"
#include <map>

NSString *const MppDocumentChangedNotification = @"MppDocumentChangedNotification";
NSString *const MppErrorDomain = @"org.macpad-plus-plus.macos";

@implementation MppDocument {
	std::map<void *, MppViewPosition> _positions;
	sptr_t _sciDoc;
}

- (instancetype)initWithSciDocument:(sptr_t)doc
{
	if ((self = [super init])) {
		static int nextID = 1;
		_docID = nextID++;
		_sciDoc = doc;
		_lang = L_TEXT;
		_eolMode = SC_EOL_LF;
		_tabColor = -1;
	}
	return self;
}

- (sptr_t)sciDocument
{
	return _sciDoc;
}

- (void)invalidate
{
	_sciDoc = 0;
}

- (BOOL)isUntitled
{
	return _filePath == nil;
}

- (NSString *)displayName
{
	return _filePath ? _filePath.lastPathComponent : _untitledName;
}

- (BOOL)fileReadOnly
{
	if (!_filePath || _fileDeleted)
		return NO;
	NSFileManager *fm = NSFileManager.defaultManager;
	return [fm fileExistsAtPath:_filePath] && ![fm isWritableFileAtPath:_filePath];
}

- (MppViewPosition &)positionForView:(ScintillaView *)view
{
	return _positions[(__bridge void *)view];
}

- (NSString *)encodingDisplayName
{
	return MppEncodingName(_encoding);
}

- (NSString *)eolDisplayName
{
	switch (_eolMode) {
		case SC_EOL_CRLF: return @"Windows (CR LF)";
		case SC_EOL_CR: return @"Macintosh (CR)";
		default: return @"Unix (LF)";
	}
}

- (void)setDirty:(BOOL)dirty
{
	if (_dirty != dirty) {
		_dirty = dirty;
		[self notifyChanged];
	}
}

- (void)notifyChanged
{
	[NSNotificationCenter.defaultCenter postNotificationName:MppDocumentChangedNotification object:self];
}

@end

// ---------------------------------------------------------------------------

@implementation MppDocumentManager {
	NSMutableArray<MppDocument *> *_documents;
	ScintillaView *_scratch;
	sptr_t _scratchDefaultDoc;
}

+ (instancetype)shared
{
	static MppDocumentManager *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[MppDocumentManager alloc] init]; });
	return s;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_documents = [NSMutableArray array];
		_scratch = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
		_scratchDefaultDoc = [_scratch message:SCI_GETDOCPOINTER];
		// Keep the default document alive while the scratch view shows other documents
		[_scratch message:SCI_ADDREFDOCUMENT wParam:0 lParam:_scratchDefaultDoc];
	}
	return self;
}

- (NSArray<MppDocument *> *)documents
{
	return _documents;
}

- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w l:(sptr_t)l
{
	return [_scratch message:msg wParam:w lParam:l];
}

- (void)attachScratch:(MppDocument *)doc
{
	[self sci:SCI_SETDOCPOINTER w:0 l:doc.sciDocument];
}

- (void)detachScratch
{
	[self sci:SCI_SETDOCPOINTER w:0 l:_scratchDefaultDoc];
}

- (sptr_t)scratchMessage:(unsigned int)msg doc:(MppDocument *)doc wParam:(uptr_t)w lParam:(sptr_t)l
{
	[self attachScratch:doc];
	sptr_t r = [self sci:msg w:w l:l];
	[self detachScratch];
	return r;
}

- (NSInteger)nextUntitledNumber
{
	NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
	for (MppDocument *d in _documents)
		if (d.isUntitled && d.untitledNumber > 0)
			[used addIndex:(NSUInteger)d.untitledNumber];
	NSInteger n = 1;
	while ([used containsIndex:(NSUInteger)n])
		++n;
	return n;
}

- (MppDocument *)makeDocumentWithBytes:(size_t)bytes
{
	const int options = bytes > ((size_t)1 << 30) ? SC_DOCUMENTOPTION_TEXT_LARGE : SC_DOCUMENTOPTION_DEFAULT;
	sptr_t sciDoc = [self sci:SCI_CREATEDOCUMENT w:bytes l:options];
	MppDocument *doc = [[MppDocument alloc] initWithSciDocument:sciDoc];
	[self attachScratch:doc];
	[self sci:SCI_SETCODEPAGE w:SC_CP_UTF8 l:0];
	[self detachScratch];
	return doc;
}

- (ScintillaView *)attachScratchViewTo:(MppDocument *)doc
{
	[self attachScratch:doc];
	return _scratch;
}

- (ScintillaView *)attachScratchViewToSciDocument:(sptr_t)sciDoc
{
	[self sci:SCI_SETDOCPOINTER w:0 l:sciDoc];
	return _scratch;
}

- (void)detachScratchView
{
	[self detachScratch];
}

- (sptr_t)createSciDocumentWithText:(const std::string &)utf8
{
	sptr_t d = [self sci:SCI_CREATEDOCUMENT w:utf8.size() l:SC_DOCUMENTOPTION_STYLES_NONE];
	[self sci:SCI_SETDOCPOINTER w:0 l:d];
	[self sci:SCI_SETCODEPAGE w:SC_CP_UTF8 l:0];
	[self sci:SCI_SETUNDOCOLLECTION w:0 l:0];
	[self sci:SCI_APPENDTEXT w:utf8.size() l:(sptr_t)utf8.data()];
	[self sci:SCI_SETUNDOCOLLECTION w:1 l:0];
	[self detachScratch];
	return d;
}

- (void)releaseSciDocument:(sptr_t)sciDoc
{
	[self sci:SCI_RELEASEDOCUMENT w:0 l:sciDoc];
}

- (MppDocument *)createUntitledDocument
{
	MppDocument *doc = [self makeDocumentWithBytes:0];
	MppPrefs *p = [MppPrefs shared];
	doc.untitledNumber = [self nextUntitledNumber];
	doc.untitledName = [NSString stringWithFormat:@"new %ld", (long)doc.untitledNumber];
	doc.encoding = MppEncodingFromName(p.defaultDocEncoding);
	doc.eolMode = (int)p.defaultDocEOL;
	doc.lang = (MppLangType)p.defaultDocLang;
	[self attachScratch:doc];
	[self sci:SCI_SETEOLMODE w:(uptr_t)doc.eolMode l:0];
	[self detachScratch];
	[_documents addObject:doc];
	return doc;
}

- (MppDocument *)documentForPath:(NSString *)path
{
	NSString *std = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
	for (MppDocument *d in _documents)
		if (d.filePath && [d.filePath.stringByStandardizingPath.stringByResolvingSymlinksInPath isEqualToString:std])
			return d;
	return nil;
}

static int detectEOL(const std::string &s)
{
	const size_t n = std::min<size_t>(s.size(), 1 << 20);
	for (size_t i = 0; i < n; ++i) {
		if (s[i] == '\r')
			return (i + 1 < s.size() && s[i + 1] == '\n') ? SC_EOL_CRLF : SC_EOL_CR;
		if (s[i] == '\n')
			return SC_EOL_LF;
	}
	return -1;
}

static NSError *makeError(NSInteger code, NSString *msg)
{
	return [NSError errorWithDomain:MppErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
}

- (BOOL)loadPath:(NSString *)path into:(MppDocument *)doc forcedEncoding:(const MppEncoding *)forced
          isReload:(BOOL)reload error:(NSError **)error
{
	NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:error];
	if (!attrs)
		return NO;
	if ([attrs[NSFileSize] unsignedLongLongValue] > (2ULL << 30)) {
		if (error)
			*error = makeError(MppErrorTooLarge, @"File size is too large to be opened (more than 2 GB).");
		return NO;
	}
	NSData *raw = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
	if (!raw)
		return NO;

	std::string utf8;
	MppEncoding enc;
	MppDecode(raw, forced, [MppPrefs shared].autoDetectEncoding, utf8, enc);

	[self attachScratch:doc];
	[self sci:SCI_SETCODEPAGE w:SC_CP_UTF8 l:0];
	if (reload) {
		// Keep undo history: replace the text as one undoable action
		[self sci:SCI_SETREADONLY w:0 l:0];
		[self sci:SCI_BEGINUNDOACTION w:0 l:0];
		[self sci:SCI_CLEARALL w:0 l:0];
		[self sci:SCI_APPENDTEXT w:utf8.size() l:(sptr_t)utf8.data()];
		[self sci:SCI_ENDUNDOACTION w:0 l:0];
	} else {
		[self sci:SCI_SETUNDOCOLLECTION w:0 l:0];
		[self sci:SCI_CLEARALL w:0 l:0];
		[self sci:SCI_APPENDTEXT w:utf8.size() l:(sptr_t)utf8.data()];
		[self sci:SCI_SETUNDOCOLLECTION w:1 l:0];
		[self sci:SCI_EMPTYUNDOBUFFER w:0 l:0];
	}
	int eol = detectEOL(utf8);
	if (eol < 0)
		eol = reload ? doc.eolMode : (int)[MppPrefs shared].defaultDocEOL;
	[self sci:SCI_SETEOLMODE w:(uptr_t)eol l:0];
	[self sci:SCI_SETSAVEPOINT w:0 l:0];
	[self detachScratch];

	doc.encoding = enc;
	doc.eolMode = eol;
	doc.fileModificationDate = attrs[NSFileModificationDate];
	doc.fileDeleted = NO;
	doc.dirty = NO;

	if (!doc.langSetByUser) {
		// User defined languages take priority over built-in ones
		if (NSString *udl = [MppUserLangManager.shared languageForFileName:path]) {
			doc.userLangName = udl;
			doc.lang = L_USER;
			return YES;
		}
		MppLangType lang = [MppLanguages.shared langTypeForFileName:path];
		if (lang == L_TEXT)
			lang = [MppLanguages.shared langTypeFromTextBeginning:(const unsigned char *)utf8.data() length:utf8.size()];
		doc.lang = lang;
	}
	return YES;
}

- (MppDocument *)openFile:(NSString *)path error:(NSError **)error
{
	return [self openFile:path forcedEncoding:nullptr error:error];
}

- (MppDocument *)openFile:(NSString *)path forcedEncoding:(const MppEncoding *)forced error:(NSError **)error
{
	if (MppDocument *existing = [self documentForPath:path])
		return existing;
	NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:error];
	if (!attrs)
		return nil;
	MppDocument *doc = [self makeDocumentWithBytes:(size_t)[attrs[NSFileSize] unsignedLongLongValue]];
	doc.filePath = path;
	if (![self loadPath:path into:doc forcedEncoding:forced isReload:NO error:error]) {
		[self sci:SCI_RELEASEDOCUMENT w:0 l:doc.sciDocument];
		return nil;
	}
	[_documents addObject:doc];
	return doc;
}

- (BOOL)reloadDocument:(MppDocument *)doc forcedEncoding:(const MppEncoding *)forced error:(NSError **)error
{
	if (!doc.filePath)
		return NO;
	BOOL ok = [self loadPath:doc.filePath into:doc forcedEncoding:forced isReload:YES error:error];
	if (ok)
		[doc notifyChanged];
	return ok;
}

- (std::string)textOfDocument:(MppDocument *)doc
{
	[self attachScratch:doc];
	const sptr_t len = [self sci:SCI_GETLENGTH w:0 l:0];
	const char *p = (const char *)[self sci:SCI_GETCHARACTERPOINTER w:0 l:0];
	std::string s(p ? p : "", p ? (size_t)len : 0);
	[self detachScratch];
	return s;
}

- (void)setText:(const std::string &)text ofDocument:(MppDocument *)doc
{
	[self attachScratch:doc];
	[self sci:SCI_BEGINUNDOACTION w:0 l:0];
	[self sci:SCI_TARGETWHOLEDOCUMENT w:0 l:0];
	[self sci:SCI_REPLACETARGET w:text.size() l:(sptr_t)text.data()];
	[self sci:SCI_ENDUNDOACTION w:0 l:0];
	const BOOL modified = [self sci:SCI_GETMODIFY w:0 l:0] != 0;
	[self detachScratch];
	doc.dirty = modified;
}

- (NSData *)encodedContentOfDocument:(MppDocument *)doc lossy:(BOOL)lossy
{
	[self attachScratch:doc];
	const sptr_t len = [self sci:SCI_GETLENGTH w:0 l:0];
	const char *p = (const char *)[self sci:SCI_GETCHARACTERPOINTER w:0 l:0];
	NSData *data = MppEncode(p ? p : "", p ? (size_t)len : 0, doc.encoding, lossy);
	[self detachScratch];
	return data;
}

- (BOOL)saveDocument:(MppDocument *)doc toPath:(NSString *)path copyOnly:(BOOL)copyOnly lossy:(BOOL)lossy error:(NSError **)error
{
	NSData *data = [self encodedContentOfDocument:doc lossy:lossy];
	if (!data) {
		if (error)
			*error = makeError(MppErrorUnencodable,
			                   [NSString stringWithFormat:@"Some characters of \"%@\" cannot be represented in %@.",
			                                              doc.displayName, doc.encodingDisplayName]);
		return NO;
	}
	// Write in place (not atomically) to keep the file's permissions, owner, links and xattrs
	if (![data writeToFile:path options:0 error:error])
		return NO;
	if (copyOnly)
		return YES;
	[self markSaved:doc path:path];
	return YES;
}

- (void)markSaved:(MppDocument *)doc path:(NSString *)path
{
	const BOOL renamed = ![doc.filePath isEqualToString:path];
	[self attachScratch:doc];
	[self sci:SCI_SETSAVEPOINT w:0 l:0];
	[self detachScratch];
	doc.filePath = path;
	doc.untitledNumber = 0;
	doc.fileDeleted = NO;
	doc.fileModificationDate = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileModificationDate];
	if (renamed && !doc.langSetByUser) {
		MppLangType lang = [MppLanguages.shared langTypeForFileName:path];
		if (lang != L_TEXT || doc.lang == L_TEXT)
			doc.lang = lang;
	}
	if (doc.backupPath) {
		[NSFileManager.defaultManager removeItemAtPath:doc.backupPath error:nil];
		doc.backupPath = nil;
	}
	doc.dirty = NO;
	[doc notifyChanged];
}

- (BOOL)saveDataWithAdminPrivileges:(NSData *)data toPath:(NSString *)path error:(NSError **)error
{
	NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	if (![data writeToFile:tmp options:NSDataWritingAtomic error:error])
		return NO;
	NSString *(^quote)(NSString *) = ^NSString *(NSString *s) {
		return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
	};
	NSString *shell = [NSString stringWithFormat:@"/bin/cat %@ > %@", quote(tmp), quote(path)];
	NSString *src = [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",
	                 [[shell stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
	                     stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
	NSDictionary *err = nil;
	NSAppleScript *script = [[NSAppleScript alloc] initWithSource:src];
	NSAppleEventDescriptor *res = [script executeAndReturnError:&err];
	[NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
	if (!res) {
		if (error)
			*error = makeError(1, err[NSAppleScriptErrorMessage] ?: @"The file could not be saved with administrator privileges.");
		return NO;
	}
	for (MppDocument *d in _documents)
		if ([d.filePath isEqualToString:path])
			[self markSaved:d path:path];
	return YES;
}

- (void)closeDocument:(MppDocument *)doc
{
	if (doc.backupPath)
		[NSFileManager.defaultManager removeItemAtPath:doc.backupPath error:nil];
	if (doc.sciDocument)
		[self sci:SCI_RELEASEDOCUMENT w:0 l:doc.sciDocument];
	[doc invalidate];
	[_documents removeObject:doc];
}

- (BOOL)writeBackupOfDocument:(MppDocument *)doc
{
	if (!doc.backupPath) {
		NSDateFormatter *f = [[NSDateFormatter alloc] init];
		f.dateFormat = @"yyyy-MM-dd_HHmmss";
		NSString *name = [NSString stringWithFormat:@"%@@%@_%@", doc.displayName, [f stringFromDate:NSDate.date],
		                  [NSUUID.UUID.UUIDString substringToIndex:8]];
		doc.backupPath = [MppPaths.backupDirectory stringByAppendingPathComponent:name];
	}
	std::string text = [self textOfDocument:doc];
	NSData *data = [NSData dataWithBytes:text.data() length:text.size()];
	BOOL ok = [data writeToFile:doc.backupPath options:NSDataWritingAtomic error:nil];
	if (ok)
		doc.backupDirty = NO;
	return ok;
}

- (MppDocument *)restoreDocumentFromBackup:(NSString *)backupPath originalPath:(NSString *)path untitledName:(NSString *)untitledName
{
	NSData *raw = [NSData dataWithContentsOfFile:backupPath];
	if (!raw)
		return nil;
	MppDocument *doc = [self makeDocumentWithBytes:raw.length];
	[self attachScratch:doc];
	[self sci:SCI_SETUNDOCOLLECTION w:0 l:0];
	[self sci:SCI_APPENDTEXT w:raw.length l:(sptr_t)raw.bytes];
	[self sci:SCI_SETUNDOCOLLECTION w:1 l:0];
	[self sci:SCI_EMPTYUNDOBUFFER w:0 l:0];
	std::string head((const char *)raw.bytes, std::min<size_t>(raw.length, 1 << 20));
	int eol = detectEOL(head);
	if (eol < 0)
		eol = (int)[MppPrefs shared].defaultDocEOL;
	[self sci:SCI_SETEOLMODE w:(uptr_t)eol l:0];
	// Restored content differs from disk: leave it without save point so that it is dirty
	[self detachScratch];
	doc.eolMode = eol;
	doc.backupPath = backupPath;
	doc.dirty = YES;
	if (path.length) {
		doc.filePath = path;
		doc.fileModificationDate = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileModificationDate];
		doc.fileDeleted = ![NSFileManager.defaultManager fileExistsAtPath:path];
		doc.lang = [MppLanguages.shared langTypeForFileName:path];
		doc.encoding = MppEncodingFromName(@"UTF-8");
	} else {
		doc.untitledName = untitledName.length ? untitledName : @"new 1";
		NSInteger n = 0;
		if ([doc.untitledName hasPrefix:@"new "])
			n = [doc.untitledName substringFromIndex:4].integerValue;
		doc.untitledNumber = n;
		doc.encoding = MppEncodingFromName([MppPrefs shared].defaultDocEncoding);
	}
	[_documents addObject:doc];
	return doc;
}

@end
