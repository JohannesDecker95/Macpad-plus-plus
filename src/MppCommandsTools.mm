// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMainWindowController.h"
#import "MppMacro.h"
#import "MppDialogs.h"
#import "MppLanguages.h"
#import "MppEditing.h"
#include "Scintilla.h"
#include <CommonCrypto/CommonDigest.h>

NSString *MppHashData(NSData *data, int algo)
{
	unsigned char buf[CC_SHA512_DIGEST_LENGTH];
	size_t n = 0;
	switch (algo) {
		case 0: CC_MD5(data.bytes, (CC_LONG)data.length, buf); n = CC_MD5_DIGEST_LENGTH; break;
		case 1: CC_SHA1(data.bytes, (CC_LONG)data.length, buf); n = CC_SHA1_DIGEST_LENGTH; break;
		case 2: CC_SHA256(data.bytes, (CC_LONG)data.length, buf); n = CC_SHA256_DIGEST_LENGTH; break;
		default: CC_SHA512(data.bytes, (CC_LONG)data.length, buf); n = CC_SHA512_DIGEST_LENGTH; break;
	}
	NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
	for (size_t i = 0; i < n; ++i)
		[s appendFormat:@"%02x", buf[i]];
	return s;
}

static NSData *hashFile(NSString *path, int algo)
{
	NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
	return d;
}

// Printing view with a header (file name) and footer (page number)
@interface MppPrintTextView : NSTextView
@property (nonatomic, copy) NSString *headerText;
@end

@implementation MppPrintTextView
- (NSAttributedString *)pageHeader
{
	return [[NSAttributedString alloc] initWithString:_headerText ?: @""
	                                       attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:9]}];
}
- (NSAttributedString *)pageFooter
{
	NSPrintOperation *op = NSPrintOperation.currentOperation;
	NSString *s = [NSString stringWithFormat:@"Page %ld", (long)op.currentPage];
	NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
	ps.alignment = NSTextAlignmentRight;
	return [[NSAttributedString alloc] initWithString:s attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:9],
	                                                                 NSParagraphStyleAttributeName: ps}];
}
@end

@implementation MppMainWindowController (Tools)

- (NSAttributedString *)styledTextForPrinting
{
	MppScintillaView *v = self.activeEditor;
	const BOOL selectionOnly = ![self sci:SCI_GETSELECTIONEMPTY];
	const sptr_t start = selectionOnly ? [self sci:SCI_GETSELECTIONSTART] : 0;
	const sptr_t end = selectionOnly ? [self sci:SCI_GETSELECTIONEND] : [self sci:SCI_GETLENGTH];
	[self sci:SCI_COLOURISE w:(uptr_t)start l:end];

	std::vector<char> styled((size_t)(end - start) * 2 + 2);
	Sci_TextRangeFull tr;
	tr.chrg.cpMin = start;
	tr.chrg.cpMax = end;
	tr.lpstrText = styled.data();
	[self sci:SCI_GETSTYLEDTEXTFULL w:0 l:(sptr_t)&tr];

	const BOOL darkTheme = [MppLanguages.shared theme]->isDark();
	NSMutableDictionary<NSNumber *, NSDictionary *> *attrCache = [NSMutableDictionary dictionary];
	auto attrsFor = [&](int style) -> NSDictionary * {
		NSDictionary *a = attrCache[@(style)];
		if (a)
			return a;
		char fontName[256] = {0};
		[self sci:SCI_STYLEGETFONT w:(uptr_t)style l:(sptr_t)fontName];
		CGFloat size = (CGFloat)[self sci:SCI_STYLEGETSIZE w:(uptr_t)style];
		if (size < 6)
			size = 10;
		NSFont *font = [NSFont fontWithName:@(fontName) size:size] ?: [NSFont userFixedPitchFontOfSize:size];
		NSFontTraitMask traits = 0;
		if ([self sci:SCI_STYLEGETBOLD w:(uptr_t)style]) traits |= NSBoldFontMask;
		if ([self sci:SCI_STYLEGETITALIC w:(uptr_t)style]) traits |= NSItalicFontMask;
		if (traits)
			font = [NSFontManager.sharedFontManager convertFont:font toHaveTrait:traits];
		NSColor *fg = darkTheme ? NSColor.blackColor : MppColorFromSci((int)[self sci:SCI_STYLEGETFORE w:(uptr_t)style]);
		NSMutableDictionary *d = [@{NSFontAttributeName: font, NSForegroundColorAttributeName: fg} mutableCopy];
		if ([self sci:SCI_STYLEGETUNDERLINE w:(uptr_t)style])
			d[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
		attrCache[@(style)] = d;
		return d;
	};

	NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
	const size_t n = (size_t)(end - start);
	size_t i = 0;
	std::string run;
	while (i < n) {
		const int style = (unsigned char)styled[i * 2 + 1];
		run.clear();
		while (i < n && (unsigned char)styled[i * 2 + 1] == style) {
			run += styled[i * 2];
			++i;
		}
		// do not split UTF-8 sequences: extend run while continuation bytes follow
		while (i < n && ((unsigned char)styled[i * 2] & 0xC0) == 0x80) {
			run += styled[i * 2];
			++i;
		}
		NSString *s = [[NSString alloc] initWithBytes:run.data() length:run.size() encoding:NSUTF8StringEncoding];
		if (!s)
			s = [[NSString alloc] initWithBytes:run.data() length:run.size() encoding:NSISOLatin1StringEncoding];
		[out appendAttributedString:[[NSAttributedString alloc] initWithString:s attributes:attrsFor(style)]];
	}
	(void)v;
	return out;
}

- (void)printDocument
{
	NSPrintOperation *op = [self printOperationWithInfo:[NSPrintInfo.sharedPrintInfo copy]];
	op.showsPrintPanel = YES;
	op.showsProgressPanel = YES;
	[op runOperationModalForWindow:self.window delegate:nil didRunSelector:nil contextInfo:nil];
}

- (NSPrintOperation *)printOperationWithInfo:(NSPrintInfo *)info
{
	info.horizontalPagination = NSPrintingPaginationModeFit;
	info.verticallyCentered = NO;
	info.topMargin = 36;
	info.bottomMargin = 36;
	info.leftMargin = 36;
	info.rightMargin = 36;
	info.dictionary[NSPrintHeaderAndFooter] = @YES;
	const CGFloat width = info.paperSize.width - info.leftMargin - info.rightMargin;
	MppPrintTextView *tv = [[MppPrintTextView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)];
	tv.headerText = self.currentDocument.filePath ?: self.currentDocument.displayName;
	[tv.textStorage setAttributedString:[self styledTextForPrinting]];
	tv.horizontallyResizable = NO;
	tv.verticallyResizable = YES;
	[tv sizeToFit];
	NSPrintOperation *op = [NSPrintOperation printOperationWithView:tv printInfo:info];
	op.jobTitle = self.currentDocument.displayName;
	return op;
}

- (void)hashCommand:(int)cmd
{
	int algo, action;
	if (cmd >= CMD_TOOL_SHA512_GENERATE) { algo = 3; action = cmd - CMD_TOOL_SHA512_GENERATE; }
	else if (cmd >= CMD_TOOL_SHA256_GENERATE) { algo = 2; action = cmd - CMD_TOOL_SHA256_GENERATE; }
	else if (cmd >= CMD_TOOL_SHA1_GENERATE) { algo = 1; action = cmd - CMD_TOOL_SHA1_GENERATE; }
	else { algo = 0; action = cmd - CMD_TOOL_MD5_GENERATE; }

	switch (action) {
		case 0:
			MppShowHashDialog(algo);
			break;
		case 1: {
			NSOpenPanel *p = [NSOpenPanel openPanel];
			p.allowsMultipleSelection = YES;
			if ([p runModal] != NSModalResponseOK)
				return;
			NSMutableString *out = [NSMutableString string];
			for (NSURL *u in p.URLs) {
				NSData *d = hashFile(u.path, algo);
				if (d)
					[out appendFormat:@"%@  %@\n", MppHashData(d, algo), u.path.lastPathComponent];
			}
			MppShowTextResult(@"Hashes of files", out);
			break;
		}
		default: {
			std::string sel = [self selectedText];
			if (sel.empty()) {
				NSBeep();
				return;
			}
			NSString *h = MppHashData([NSData dataWithBytes:sel.data() length:sel.size()], algo);
			[NSPasteboard.generalPasteboard clearContents];
			[NSPasteboard.generalPasteboard setString:h forType:NSPasteboardTypeString];
			[self setStatusMessage:[NSString stringWithFormat:@"Hash copied to clipboard: %@", h]];
			break;
		}
	}
}

- (BOOL)handleToolsCommand:(int)cmd
{
	MppMacroManager *m = self.macros;
	if (cmd >= CMD_TOOL_MD5_GENERATE && cmd <= CMD_TOOL_SHA512_SELECTION) {
		[self hashCommand:cmd];
		return YES;
	}
	if (cmd >= CMD_MACRO_BASE && cmd < CMD_MACRO_BASE + 300) {
		[m playSaved:cmd - CMD_MACRO_BASE on:self];
		return YES;
	}
	if (cmd >= CMD_RUN_BASE && cmd < CMD_RUN_BASE + 300) {
		NSArray *cmds = MppSavedRunCommands();
		NSInteger i = cmd - CMD_RUN_BASE;
		if (i < (NSInteger)cmds.count)
			MppRunCommandLine(self, cmds[(NSUInteger)i][@"command"]);
		return YES;
	}
	switch (cmd) {
		case CMD_MACRO_START_RECORDING:
			if (m.recording)
				[m stopRecording:self.activeEditor];
			else
				[m startRecording:self.activeEditor];
			[self updateTitle];
			return YES;
		case CMD_MACRO_STOP_RECORDING:
			[m stopRecording:self.activeEditor];
			[self updateTitle];
			return YES;
		case CMD_MACRO_PLAYBACK: [m playCurrentOn:self times:1 untilEnd:NO]; return YES;
		case CMD_MACRO_SAVE_CURRENT: {
			NSString *name = MppAskString(@"Save Macro", @"Name:", @"");
			if (name.length)
				[m saveCurrentAs:name];
			return YES;
		}
		case CMD_MACRO_RUN_MULTI: MppShowRunMacroMultiple(self); return YES;
		case CMD_MACRO_MANAGE: MppShowManageMacros(self); return YES;
		case CMD_RUN_EXECUTE: MppShowRunDialog(self); return YES;
		case CMD_RUN_MANAGE: MppShowManageRunCommands(self); return YES;
		default:
			return NO;
	}
}

@end
