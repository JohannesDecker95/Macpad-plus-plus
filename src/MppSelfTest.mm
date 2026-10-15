// Macpad++ for macOS - built-in self test (only compiled into `make selftest` builds)
// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
//
// Runs the editor commands that are hard to drive from outside (dialog-backed commands, printing,
// user defined languages...) against real documents and writes PASS / FAIL lines to a log file.
// Started with: Macpad++ -selftest=<log> -settingsDir=<tmp dir> -nosession

#ifdef MPP_SELFTEST

#import "MppSelfTest.h"
#import "MppMainWindowController.h"
#import "MppFindReplace.h"
#import "MppDialogs.h"
#import "MppStyler.h"
#import "MppUserLang.h"
#import "MppUserLangModel.h"
#import "MppUserLangEditor.h"
#import "MppPaths.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include <string>

namespace {

NSMutableString *g_log;
int g_failures;

void check(BOOL ok, NSString *name, NSString *detail)
{
	if (!ok)
		++g_failures;
	[g_log appendFormat:@"%@  %@%@\n", ok ? @"PASS" : @"FAIL", name, detail.length ? [@"  -- " stringByAppendingString:detail] : @""];
}

NSString *docText(MppMainWindowController *o)
{
	const sptr_t len = [o sci:SCI_GETLENGTH];
	std::string s = [o textRangeFrom:0 to:len];
	return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

MppDocument *newDocWithText(MppMainWindowController *o, const char *text)
{
	MppDocument *d = [o newDocument];
	[o sci:SCI_SETTEXT w:0 l:(sptr_t)text];
	[o sci:SCI_GOTOPOS w:0];
	return d;
}

int indicatorRanges(MppMainWindowController *o, int indic)
{
	const sptr_t len = [o sci:SCI_GETLENGTH];
	int n = 0;
	for (sptr_t p = 0; p < len;) {
		const sptr_t e = [o sci:SCI_INDICATOREND w:(uptr_t)indic l:p];
		if ([o sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p])
			++n;
		if (e <= p)
			break;
		p = e;
	}
	return n;
}

// Lets queued work (timers, async layout, lexing) run without blocking the main thread
void pump(NSTimeInterval seconds)
{
	[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// Captures a window as shown on screen into a PNG (the window is ordered front without taking the focus)
void snapshot(NSWindow *w, NSString *path)
{
	[w orderFront:nil];
	[w.contentView layoutSubtreeIfNeeded];
	[w displayIfNeeded];
	pump(0.3);
	NSTask *t = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/sbin/screencapture"]
	                                        arguments:@[@"-x", @"-o", [NSString stringWithFormat:@"-l%ld", (long)w.windowNumber], path]
	                                            error:nil
	                               terminationHandler:nil];
	[t waitUntilExit];
}

NSString *esc(NSString *s)
{
	return [[s stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}

} // namespace

void MppRunSelfTest(MppMainWindowController *o, NSString *logPath)
{
	g_log = [NSMutableString string];
	NSString *tmp = MppPaths.userDataDirectory;   // the -settingsDir scratch directory
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	NSString *savedClipboard = [pb stringForType:NSPasteboardTypeString];

	// ---- Layout ----------------------------------------------------------------------------------------
	auto scrollInfo = [o]() {
		NSScrollView *sv = o.activeEditor.scrollView;
		return [NSString stringWithFormat:@"scrollWidth=%ld clip=%.0f doc=%.0f", (long)[o sci:SCI_GETSCROLLWIDTH],
		                                  sv.contentView.bounds.size.width, sv.documentView.frame.size.width];
	};
	if (o.currentDocument.filePath) {   // a file given on the command line
		NSScrollView *sv = o.activeEditor.scrollView;
		check(!sv.hasHorizontalScroller || sv.horizontalScroller.isHidden, @"Layout: file opened at launch has no horizontal scroll bar",
		      scrollInfo());
	}
	{
		newDocWithText(o, "short\nlines\n");
		pump(0.5);
		NSScrollView *sv = o.activeEditor.scrollView;
		const BOOL hidden = !sv.hasHorizontalScroller || sv.horizontalScroller.isHidden;
		check(hidden, @"Layout: no horizontal scroll bar when lines fit",
		      [NSString stringWithFormat:@"scrollWidth=%ld clip=%.0f doc=%.0f margins=%ld", (long)[o sci:SCI_GETSCROLLWIDTH],
		                                 sv.contentView.bounds.size.width, sv.documentView.frame.size.width,
		                                 (long)[o sci:SCI_GETMARGINLEFT]]);
		NSMutableString *longLine = [NSMutableString string];
		for (int i = 0; i < 400; ++i)
			[longLine appendString:@"word "];
		[o sci:SCI_SETTEXT w:0 l:(sptr_t)longLine.UTF8String];
		[o sci:SCI_GOTOPOS w:0];
		pump(0.5);
		check(sv.hasHorizontalScroller && !sv.horizontalScroller.isHidden, @"Layout: horizontal scroll bar for a long line",
		      [NSString stringWithFormat:@"scrollWidth=%ld", (long)[o sci:SCI_GETSCROLLWIDTH]]);
	}

	// ---- Mark (Search > Mark...) ------------------------------------------------------------------
	{
		newDocWithText(o, "alpha beta\nbeta gamma\ndelta\nBeta\n");
		MppFindReplaceController *fr = o.findReplace;
		[fr showTab:MppFindTabMark];
		[fr.window orderOut:nil];
		[fr setFindText:@"beta"];
		NSButton *bookmark = [fr valueForKey:@"_bookmarkLine"], *matchCase = [fr valueForKey:@"_matchCase"],
		         *purge = [fr valueForKey:@"_purge"];
		bookmark.state = NSControlStateValueOn;
		matchCase.state = NSControlStateValueOff;
		purge.state = NSControlStateValueOn;
		[fr performSelector:@selector(markAllClicked:) withObject:nil];
		const int marks = indicatorRanges(o, MPP_INDIC_FOUND_STYLE);
		check(marks == 3, @"Mark: all occurrences (case-insensitive)", [NSString stringWithFormat:@"%d marks", marks]);
		NSMutableArray *lines = [NSMutableArray array];
		for (sptr_t l = [o sci:SCI_MARKERNEXT w:0 l:1 << MPP_MARK_BOOKMARK]; l >= 0;
		     l = [o sci:SCI_MARKERNEXT w:(uptr_t)l + 1 l:1 << MPP_MARK_BOOKMARK])
			[lines addObject:@(l + 1)];
		check([lines isEqual:(@[@1, @2, @4])], @"Mark: bookmark lines", [lines componentsJoinedByString:@","]);
		[fr performSelector:@selector(copyMarkedClicked:) withObject:nil];
		NSString *clip = [pb stringForType:NSPasteboardTypeString];
		check([clip isEqualToString:@"beta\nbeta\nBeta"], @"Mark: copy marked text", esc(clip));
		matchCase.state = NSControlStateValueOn;
		[fr performSelector:@selector(markAllClicked:) withObject:nil];
		const int marks2 = indicatorRanges(o, MPP_INDIC_FOUND_STYLE);
		check(marks2 == 2, @"Mark: match case with purge", [NSString stringWithFormat:@"%d marks", marks2]);
		matchCase.state = NSControlStateValueOff;
		[fr setFindText:@"(\\w+)a\\b"];
		[(NSButton *)[fr valueForKey:@"_modeRegex"] performClick:nil];
		[fr performSelector:@selector(markAllClicked:) withObject:nil];
		const int marks3 = indicatorRanges(o, MPP_INDIC_FOUND_STYLE);
		check(marks3 == 6, @"Mark: regular expression", [NSString stringWithFormat:@"%d marks", marks3]);
		[(NSButton *)[fr valueForKey:@"_modeNormal"] performClick:nil];
		[fr performSelector:@selector(clearMarksClicked:) withObject:nil];
		check(indicatorRanges(o, MPP_INDIC_FOUND_STYLE) == 0 && [o sci:SCI_MARKERNEXT w:0 l:1 << MPP_MARK_BOOKMARK] < 0,
		      @"Mark: clear all marks", nil);
		bookmark.state = NSControlStateValueOff;
		purge.state = NSControlStateValueOff;
	}

	// ---- Incremental search --------------------------------------------------------------------------
	{
		newDocWithText(o, "one two three\ntwo three\nthree\n");
		MppFindReplaceController *fr = o.findReplace;
		[fr showIncrementalSearch];
		NSSearchField *field = [fr valueForKey:@"_incField"];
		field.stringValue = @"thr";
		[fr performSelector:@selector(incChanged:) withObject:field];
		check([o sci:SCI_GETSELECTIONSTART] == 8 && [o sci:SCI_GETSELECTIONEND] == 11, @"Incremental search: first match",
		      [NSString stringWithFormat:@"%ld-%ld", (long)[o sci:SCI_GETSELECTIONSTART], (long)[o sci:SCI_GETSELECTIONEND]]);
		const int hl = indicatorRanges(o, MPP_INDIC_FOUND_STYLE_INC);
		check(hl == 3, @"Incremental search: highlight all", [NSString stringWithFormat:@"%d", hl]);
		[fr performSelector:@selector(incNext:) withObject:nil];
		check([o sci:SCI_GETSELECTIONSTART] == 18, @"Incremental search: next",
		      [NSString stringWithFormat:@"%ld", (long)[o sci:SCI_GETSELECTIONSTART]]);
		[fr performSelector:@selector(incPrev:) withObject:nil];
		check([o sci:SCI_GETSELECTIONSTART] == 8, @"Incremental search: previous",
		      [NSString stringWithFormat:@"%ld", (long)[o sci:SCI_GETSELECTIONSTART]]);
		field.stringValue = @"xyz";
		[fr performSelector:@selector(incChanged:) withObject:field];
		NSTextField *status = [fr valueForKey:@"_incStatus"];
		check([status.stringValue isEqualToString:@"Phrase not found"], @"Incremental search: not found status", status.stringValue);
		[(NSPanel *)[fr valueForKey:@"_incPanel"] orderOut:nil];
	}

	// ---- Column editor --------------------------------------------------------------------------------
	{
		newDocWithText(o, "a\nb\nc\nd");
		[o sci:SCI_GOTOPOS w:0];
		MppColumnInsert(o, NO, nil, 8, 1, 1, 10, 1);
		check([docText(o) isEqualToString:@"08a\n09b\n10c\n11d"], @"Column editor: numbers with leading zeros", esc(docText(o)));
		[o sci:SCI_SETTEXT w:0 l:(sptr_t)"ab\nab\nab\nab"];
		MppColumnInsert(o, NO, nil, 1, 2, 2, 16, 0);
		check([docText(o) isEqualToString:@"1ab\n1ab\n3ab\n3ab"], @"Column editor: increase and repeat", esc(docText(o)));
		[o sci:SCI_SETTEXT w:0 l:(sptr_t)"abc\nabc\nabc\nabc"];
		// rectangular selection over lines 2-3, column 1
		[o sci:SCI_SETRECTANGULARSELECTIONANCHOR w:5];
		[o sci:SCI_SETRECTANGULARSELECTIONCARET w:9];
		MppColumnInsert(o, YES, @"XY", 0, 0, 1, 10, 0);
		check([docText(o) isEqualToString:@"abc\naXYbc\naXYbc\nabc"], @"Column editor: text into a column selection", esc(docText(o)));
		[o sci:SCI_SETTEXT w:0 l:(sptr_t)"abcdef\nab\nabcdef"];
		[o sci:SCI_GOTOPOS w:4];
		MppColumnInsert(o, YES, @"|", 0, 0, 1, 10, 0);
		check([docText(o) isEqualToString:@"abcd|ef\nab  |\nabcd|ef"], @"Column editor: pads short lines", esc(docText(o)));
		[o sci:SCI_SETTEXT w:0 l:(sptr_t)"\n\n\n\n\n\n\n\n\n\n"];
		MppColumnInsert(o, NO, nil, 5, 1, 1, 2, 2);
		NSString *first = [docText(o) componentsSeparatedByString:@"\n"].firstObject, *last = [docText(o) componentsSeparatedByString:@"\n"].lastObject;
		check([first isEqualToString:@" 101"] && [last isEqualToString:@"1111"], @"Column editor: binary, space padded",
		      [NSString stringWithFormat:@"%@ ... %@", first, last]);
	}

	// ---- Find characters in range ------------------------------------------------------------------------
	{
		newDocWithText(o, "abc \xC3\xA9t\xC3\xA9 \xE2\x82\xAC end");
		BOOL ok = MppFindCharsInRange(o, 128, 0x10FFFF, YES, YES);
		check(ok && [o sci:SCI_GETSELECTIONSTART] == 4 && [o sci:SCI_GETSELECTIONEND] == 6, @"Find chars in range: non-ASCII",
		      [NSString stringWithFormat:@"%ld-%ld", (long)[o sci:SCI_GETSELECTIONSTART], (long)[o sci:SCI_GETSELECTIONEND]]);
		ok = MppFindCharsInRange(o, 0x20AC, 0x20AC, YES, YES);
		check(ok && [o sci:SCI_GETSELECTIONSTART] == 10 && [o sci:SCI_GETSELECTIONEND] == 13, @"Find chars in range: custom range (euro sign)",
		      [NSString stringWithFormat:@"%ld-%ld", (long)[o sci:SCI_GETSELECTIONSTART], (long)[o sci:SCI_GETSELECTIONEND]]);
		ok = MppFindCharsInRange(o, 128, 0x10FFFF, NO, YES);
		check(ok && [o sci:SCI_GETSELECTIONSTART] == 7, @"Find chars in range: backwards",
		      [NSString stringWithFormat:@"%ld", (long)[o sci:SCI_GETSELECTIONSTART]]);
		ok = MppFindCharsInRange(o, 0x4E00, 0x9FFF, YES, YES);
		check(!ok, @"Find chars in range: not found", nil);
	}

	// ---- Hashes ---------------------------------------------------------------------------------------
	{
		NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
		check([MppHashData(abc, 0) isEqualToString:@"900150983cd24fb0d6963f7d28e17f72"], @"Hash: MD5", MppHashData(abc, 0));
		check([MppHashData(abc, 1) isEqualToString:@"a9993e364706816aba3e25717850c26c9cd0d89d"], @"Hash: SHA-1", MppHashData(abc, 1));
		check([MppHashData(abc, 2) isEqualToString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],
		      @"Hash: SHA-256", MppHashData(abc, 2));
		check([MppHashData(abc, 3) hasPrefix:@"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"],
		      @"Hash: SHA-512", MppHashData(abc, 3));
		newDocWithText(o, "xxabcxx");
		[o sci:SCI_SETSEL w:2 l:5];
		[o executeCommand:CMD_TOOL_MD5_SELECTION];
		check([[pb stringForType:NSPasteboardTypeString] isEqualToString:@"900150983cd24fb0d6963f7d28e17f72"],
		      @"Hash: MD5 of selection to clipboard", [pb stringForType:NSPasteboardTypeString]);
	}

	// ---- Run ------------------------------------------------------------------------------------------
	{
		NSString *file = [tmp stringByAppendingPathComponent:@"run test.txt"];
		[@"line1\nhello world\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
		[o openPath:file];
		[o sci:SCI_GOTOPOS w:9];   // inside "hello" on line 2
		NSString *out = [tmp stringByAppendingPathComponent:@"run-out.txt"];
		MppRunCommandLine(o, [NSString stringWithFormat:@"echo \"$(FILE_NAME)|$(NAME_PART)|$(EXT_PART)|$(CURRENT_WORD)|$(CURRENT_LINE)|$(CURRENT_COLUMN)|$(SYS.HOME)|$(CURRENT_DIRECTORY)\" > '%@'", out]);
		for (int i = 0; i < 50 && ![NSFileManager.defaultManager fileExistsAtPath:out]; ++i)
			pump(0.1);
		pump(0.2);
		NSString *got = [[NSString stringWithContentsOfFile:out encoding:NSUTF8StringEncoding error:nil]
		    stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
		NSString *want = [NSString stringWithFormat:@"run test.txt|run test|.txt|hello|2|4|%@|%@", NSHomeDirectory(), tmp];
		check([got isEqualToString:want], @"Run: command with variables", got);
	}

	// ---- Printing (rendered to PDF instead of a printer) ------------------------------------------------
	{
		NSMutableString *big = [NSMutableString string];
		for (int i = 1; i <= 150; ++i)
			[big appendFormat:@"int line%d = %d; // comment\n", i, i];
		MppDocument *d = newDocWithText(o, big.UTF8String);
		[o setLanguage:L_CPP forDocument:d];
		NSString *pdf = [tmp stringByAppendingPathComponent:@"print.pdf"];
		NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{
			NSPrintJobDisposition: NSPrintSaveJob, NSPrintJobSavingURL: [NSURL fileURLWithPath:pdf]}];
		info.paperSize = NSMakeSize(595, 842);   // A4
		NSPrintOperation *op = [o printOperationWithInfo:info];
		op.showsPrintPanel = NO;
		op.showsProgressPanel = NO;
		const BOOL ran = [op runOperation];
		CGPDFDocumentRef doc = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:pdf]);
		const size_t pages = doc ? CGPDFDocumentGetNumberOfPages(doc) : 0;
		if (doc)
			CGPDFDocumentRelease(doc);
		check(ran && pages >= 2 && pages <= 6, @"Print: styled document to PDF", [NSString stringWithFormat:@"%zu pages", pages]);
	}

	// ---- User defined languages ---------------------------------------------------------------------
	{
		MppUserLangManager *m = MppUserLangManager.shared;
		check([m.languageNames containsObject:@"Markdown (preinstalled)"] && [m.languageNames containsObject:@"Markdown (preinstalled dark mode)"],
		      @"UDL: preinstalled Markdown languages", [m.languageNames componentsJoinedByString:@", "]);
		NSString *md = [tmp stringByAppendingPathComponent:@"readme.md"];
		[@"# Title\n\nSome **bold** text and `code`.\n\n- item\n" writeToFile:md atomically:YES encoding:NSUTF8StringEncoding error:nil];
		MppDocument *d = [o openPath:md];
		pump(0.3);
		char lexer[64] = {0};
		[o sci:SCI_GETLEXERLANGUAGE w:0 l:(sptr_t)lexer];
		[o sci:SCI_COLOURISE w:0 l:-1];
		const int titleStyle = (int)[o sci:SCI_GETSTYLEAT w:2], plainStyle = (int)[o sci:SCI_GETSTYLEAT w:10];
		check(d.lang == L_USER && [d.userLangName hasPrefix:@"Markdown (preinstalled"] && !strcmp(lexer, "user"),
		      @"UDL: .md file uses the Markdown UDL", [NSString stringWithFormat:@"%@ lexer=%s", d.userLangName, lexer]);
		check(titleStyle != plainStyle, @"UDL: Markdown is highlighted", [NSString stringWithFormat:@"styles %d / %d", titleStyle, plainStyle]);

		NSString *udl = [tmp stringByAppendingPathComponent:@"TestLang.xml"];
		[@"<MacpadPlus><UserLang name=\"SelfTestLang\" ext=\"stl\" udlVersion=\"2.1\"><Settings><Global caseIgnored=\"no\" /></Settings>"
		 @"<KeywordLists><Keywords name=\"Comments\">00# 01 02 03 04</Keywords><Keywords name=\"Keywords1\">begin end</Keywords></KeywordLists>"
		 @"<Styles><WordsStyle name=\"DEFAULT\" fgColor=\"000000\" bgColor=\"FFFFFF\" fontStyle=\"0\" nesting=\"0\" />"
		 @"<WordsStyle name=\"KEYWORDS1\" fgColor=\"0000FF\" bgColor=\"FFFFFF\" fontStyle=\"1\" nesting=\"0\" /></Styles>"
		 @"</UserLang></MacpadPlus>" writeToFile:udl atomically:YES encoding:NSUTF8StringEncoding error:nil];
		const NSInteger n = [m importFile:udl];
		check(n == 1 && [m.languageNames containsObject:@"SelfTestLang"], @"UDL: import", [NSString stringWithFormat:@"%ld", (long)n]);
		NSString *stl = [tmp stringByAppendingPathComponent:@"x.stl"];
		[@"begin\n# note\nend\n" writeToFile:stl atomically:YES encoding:NSUTF8StringEncoding error:nil];
		MppDocument *d2 = [o openPath:stl];
		[o sci:SCI_COLOURISE w:0 l:-1];
		const int kw = (int)[o sci:SCI_GETSTYLEAT w:1], cm = (int)[o sci:SCI_GETSTYLEAT w:8];
		check([d2.userLangName isEqualToString:@"SelfTestLang"] && kw == SCE_USER_STYLE_KEYWORD1 && cm == SCE_USER_STYLE_COMMENTLINE,
		      @"UDL: imported language highlights keywords and comments", [NSString stringWithFormat:@"%@ kw=%d comment=%d", d2.userLangName, kw, cm]);
		[o toggleLineComment:0];
		check([docText(o) hasPrefix:@"# begin"] || [docText(o) hasPrefix:@"#begin"], @"UDL: toggle comment uses the UDL comment token",
		      esc([docText(o) substringToIndex:MIN(10u, docText(o).length)]));
	}


	// ---- Define your language (UDL editor) ----------------------------------------------------------
	{
		// prefixed list encoding (comments / delimiters) round trip, including (( )) groups
		std::string f[5] = {"// #", "", "", "((EOL)) /*", "*/"};
		const std::string enc = MppUdlSetPrefixed(f, 5);
		bool same = true;
		for (int i = 0; i < 5; ++i) {
			char p[3];
			snprintf(p, sizeof p, "%02d", i);
			same = same && MppUdlGetPrefixed(enc, p) == f[i];
		}
		check(same && enc == "00// 00# 01 02 03((EOL)) 03/* 04*/", @"UDL editor: comment field encoding", @(enc.c_str()));

		MppUserLangManager *m = MppUserLangManager.shared;
		check([m createLanguage:@"Self Test UDL" copyOf:nil], @"UDL editor: create new language", nil);
		MppUserLangEditor *ed = MppUserLangEditor.shared;
		[ed showLanguage:@"Self Test UDL"];
		[ed.window orderOut:nil];
		[ed setText:@"stu" forField:@"ext"];
		[ed setText:@"alpha beta" forField:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_KEYWORDS1]];
		[ed setText:@"if" forField:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN]];
		[ed setText:@"end" forField:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE]];
		[ed setText:@"+ -" forField:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_OPERATORS1]];
		[ed setText:@"//" forField:@"cm0"];
		[ed setText:@"/*" forField:@"cm3"];
		[ed setText:@"*/" forField:@"cm4"];
		[ed setText:@"\"" forField:@"dl0"];
		[ed setText:@"\\" forField:@"dl1"];
		[ed setText:@"\"" forField:@"dl2"];

		NSString *path = [tmp stringByAppendingPathComponent:@"t.stu"];
		[@"alpha x // c\n/* b */ \"s\\\"t\" + beta\nif\n  x\nend\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		MppDocument *d = [o openPath:path];
		[o sci:SCI_COLOURISE w:0 l:-1];
		auto st = [o](sptr_t pos) { return (int)[o sci:SCI_GETSTYLEAT w:(uptr_t)pos]; };
		const int sKw = st(0), sLine = st(8), sBlock = st(13), sStr = st(21), sOp = st(28), sKw2 = st(30);
		check([d.userLangName isEqualToString:@"Self Test UDL"] && sKw == SCE_USER_STYLE_KEYWORD1 && sLine == SCE_USER_STYLE_COMMENTLINE &&
		      sBlock == SCE_USER_STYLE_COMMENT && sStr == SCE_USER_STYLE_DELIMITER1 && sOp == SCE_USER_STYLE_OPERATOR &&
		      sKw2 == SCE_USER_STYLE_KEYWORD1,
		      @"UDL editor: edits drive highlighting", [NSString stringWithFormat:@"%@ kw=%d line=%d block=%d str=%d op=%d kw=%d",
		                                                d.userLangName, sKw, sLine, sBlock, sStr, sOp, sKw2]);
		const sptr_t ifLine = 2;
		const int lvl = (int)[o sci:SCI_GETFOLDLEVEL w:ifLine];
		check(lvl & SC_FOLDLEVELHEADERFLAG, @"UDL editor: folding keywords", [NSString stringWithFormat:@"level=0x%x", lvl]);

		// a change in the editor reaches the open document right away
		[ed setText:@"alpha beta x" forField:[NSString stringWithFormat:@"kw%d", SCE_USER_KWLIST_KEYWORDS1]];
		[o sci:SCI_COLOURISE w:0 l:-1];
		check(st(6) == SCE_USER_STYLE_KEYWORD1, @"UDL editor: live update of open documents", [NSString stringWithFormat:@"%d", st(6)]);

		// Styler: colour and bold for keywords, then back to transparent
		UserLang *l = [m languageNamed:@"Self Test UDL"];
		UdlStyle *kw = l->findStyle(SCE_USER_STYLE_KEYWORD1);
		kw->style.fgColor = 0x0000FF;   // red (BGR)
		kw->style.colorStyle = COLORSTYLE_FOREGROUND;
		kw->style.fontStyle = FONTSTYLE_BOLD;
		[m languageDidChange:@"Self Test UDL"];
		const sptr_t fore = [o sci:SCI_STYLEGETFORE w:SCE_USER_STYLE_KEYWORD1];
		const BOOL bold = [o sci:SCI_STYLEGETBOLD w:SCE_USER_STYLE_KEYWORD1];
		check(fore == 0x0000FF && bold, @"UDL editor: styler colour and bold", [NSString stringWithFormat:@"fore=%06lx bold=%d", (long)fore, bold]);
		kw->style.colorStyle = 0;
		kw->style.fontStyle = 0;
		[m languageDidChange:@"Self Test UDL"];
		const sptr_t fore2 = [o sci:SCI_STYLEGETFORE w:SCE_USER_STYLE_KEYWORD1], def = [o sci:SCI_STYLEGETFORE w:STYLE_DEFAULT];
		check(fore2 == def && ![o sci:SCI_STYLEGETBOLD w:SCE_USER_STYLE_KEYWORD1], @"UDL editor: transparent style uses the default colour",
		      [NSString stringWithFormat:@"fore=%06lx default=%06lx", (long)fore2, (long)def]);

		// saved shortly after editing, in the UDL 2.1 format
		[m saveLanguage:@"Self Test UDL"];
		NSString *file = [[m directory] stringByAppendingPathComponent:@"Self Test UDL.xml"];
		NSString *xml = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
		check([xml containsString:@"<Keywords name=\"Keywords1\">alpha beta x</Keywords>"] &&
		      [xml containsString:@"<Keywords name=\"Comments\">00// 01 02 03/* 04*/</Keywords>"] &&
		      [xml containsString:@"ext=\"stu\""] && [xml containsString:@"udlVersion=\"2.1\""],
		      @"UDL editor: saved file", file.lastPathComponent);
		[m reload];
		[ed showLanguage:@"Self Test UDL"];
		[ed.window orderOut:nil];
		check([[ed textForField:@"cm3"] isEqualToString:@"/*"] && [[ed textForField:@"dl1"] isEqualToString:@"\\"] &&
		      [[ed textForField:@"ext"] isEqualToString:@"stu"],
		      @"UDL editor: reloads saved language", [NSString stringWithFormat:@"%@ %@ %@", [ed textForField:@"cm3"],
		                                                [ed textForField:@"dl1"], [ed textForField:@"ext"]]);

		// window layout snapshots (one per tab)
		[ed showLanguage:@"Self Test UDL"];
		NSTabView *tabs = [ed valueForKey:@"_tabs"];
		for (NSInteger i = 0; i < tabs.numberOfTabViewItems; ++i) {
			[tabs selectTabViewItemAtIndex:i];
			snapshot(ed.window, [tmp stringByAppendingPathComponent:[NSString stringWithFormat:@"udl-tab%ld.png", (long)i]]);
		}
		NSButton *styler = [NSButton buttonWithTitle:@"" target:nil action:nil];
		styler.tag = SCE_USER_STYLE_DELIMITER1;
		[ed performSelector:@selector(editStyle:) withObject:styler];
		pump(0.5);
		NSWindow *sheet = ed.window.attachedSheet;
		check(sheet != nil, @"UDL editor: styler sheet opens", nil);
		if (sheet) {
			snapshot(sheet, [tmp stringByAppendingPathComponent:@"udl-styler.png"]);
			[ed.window endSheet:sheet returnCode:NSAlertSecondButtonReturn];
		}
		[tabs selectTabViewItemAtIndex:0];
		[ed.window orderOut:nil];

		check([m renameLanguage:@"Self Test UDL" to:@"Renamed UDL"] && [d.userLangName isEqualToString:@"Renamed UDL"] &&
		      [NSFileManager.defaultManager fileExistsAtPath:[[m directory] stringByAppendingPathComponent:@"Renamed UDL.xml"]] &&
		      ![NSFileManager.defaultManager fileExistsAtPath:file],
		      @"UDL editor: rename follows documents and file", d.userLangName);
		[m removeLanguage:@"Renamed UDL"];
		check(d.lang == L_TEXT && ![m.languageNames containsObject:@"Renamed UDL"] &&
		      ![NSFileManager.defaultManager fileExistsAtPath:[[m directory] stringByAppendingPathComponent:@"Renamed UDL.xml"]],
		      @"UDL editor: remove", [NSString stringWithFormat:@"lang=%d", (int)d.lang]);

		// Language > User Defined Language > Define your language... opens the editor on the document's language
		NSMenuItem *defineItem = nil;
		for (NSMenuItem *top in NSApp.mainMenu.itemArray)
			for (NSMenuItem *it in top.submenu.itemArray)
				for (NSMenuItem *sub in it.submenu.itemArray)
					if (sub.tag == CMD_LANG_DEFINE_UDL)
						defineItem = sub;
		[o openPath:[tmp stringByAppendingPathComponent:@"readme.md"]];
		[o executeCommand:CMD_LANG_DEFINE_UDL];
		check(defineItem && [defineItem.title isEqualToString:@"Define your language…"] && ed.window.isVisible &&
		      [ed.languageName hasPrefix:@"Markdown (preinstalled"],
		      @"UDL editor: menu command opens it on the current language", ed.languageName);
		[ed.window orderOut:nil];

		// editing a preinstalled language writes a user copy
		UserLang *md = [m languageNamed:@"Markdown (preinstalled)"];
		md->caseIgnored = !md->caseIgnored;
		[m saveLanguage:@"Markdown (preinstalled)"];
		check([NSFileManager.defaultManager fileExistsAtPath:[[m directory] stringByAppendingPathComponent:@"markdown._preinstalled.udl.xml"]] &&
		      ![m isBundledLanguage:@"Markdown (preinstalled)"], @"UDL editor: edited preinstalled language saved as user copy", nil);
	}

	if (savedClipboard) {
		[pb clearContents];
		[pb setString:savedClipboard forType:NSPasteboardTypeString];
	}
	// the throw-away preferences domain of the test run
	if (NSString *suite = MppDefaultsSuiteName()) {
		[MppDefaults() removePersistentDomainForName:suite];
		[MppDefaults() synchronize];
	}
	[g_log appendFormat:@"\n%d failure(s)\n", g_failures];
	[g_log writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#endif
