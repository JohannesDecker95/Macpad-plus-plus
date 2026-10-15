// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMainWindowController.h"
#import "MppFindReplace.h"
#import "MppSearchResults.h"
#import "MppEditing.h"
#import "MppStyler.h"
#import "MppDialogs.h"
#include "Scintilla.h"

static const int kExtIndicators[5] = {MPP_INDIC_FOUND_STYLE_EXT1, MPP_INDIC_FOUND_STYLE_EXT2, MPP_INDIC_FOUND_STYLE_EXT3,
                                      MPP_INDIC_FOUND_STYLE_EXT4, MPP_INDIC_FOUND_STYLE_EXT5};

@implementation MppMainWindowController (Search)

- (NSString *)findTextFromSelection
{
	std::string s = [self sci:SCI_GETSELECTIONEMPTY] ? std::string() : [self selectedText];
	if (s.empty() || s.find_first_of("\r\n") != std::string::npos)
		s = [self currentWordOrSelection];
	if (s.find_first_of("\r\n") != std::string::npos)
		return nil;
	return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
}

- (void)jumpToIndicator:(int)indic forward:(BOOL)forward
{
	const sptr_t len = [self sci:SCI_GETLENGTH];
	sptr_t pos = forward ? [self sci:SCI_GETSELECTIONEND] : [self sci:SCI_GETSELECTIONSTART];
	auto findFrom = [&](sptr_t p, BOOL fwd) -> sptr_t {
		if (fwd) {
			// skip current range if inside one
			if ([self sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p])
				p = [self sci:SCI_INDICATOREND w:(uptr_t)indic l:p];
			while (p < len) {
				if ([self sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p])
					return p;
				const sptr_t next = [self sci:SCI_INDICATOREND w:(uptr_t)indic l:p];
				if (next <= p)
					break;
				p = next;
			}
		} else {
			if (p > 0 && [self sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p - 1])
				p = [self sci:SCI_INDICATORSTART w:(uptr_t)indic l:p - 1];
			while (p > 0) {
				if ([self sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p - 1])
					return [self sci:SCI_INDICATORSTART w:(uptr_t)indic l:p - 1];
				const sptr_t prev = [self sci:SCI_INDICATORSTART w:(uptr_t)indic l:p - 1];
				if (prev >= p)
					break;
				p = prev;
			}
		}
		return -1;
	};
	sptr_t found = findFrom(pos, forward);
	if (found < 0)
		found = findFrom(forward ? 0 : len, forward);   // wrap around
	if (found < 0) {
		NSBeep();
		return;
	}
	const sptr_t end = [self sci:SCI_INDICATOREND w:(uptr_t)indic l:found];
	[self selectRangeFrom:found to:end];
}

- (void)copyIndicatorText:(std::vector<int>)indics
{
	const sptr_t len = [self sci:SCI_GETLENGTH];
	std::vector<std::pair<sptr_t, sptr_t>> ranges;
	for (int indic : indics) {
		sptr_t p = 0;
		while (p < len) {
			if ([self sci:SCI_INDICATORVALUEAT w:(uptr_t)indic l:p]) {
				const sptr_t e = [self sci:SCI_INDICATOREND w:(uptr_t)indic l:p];
				ranges.emplace_back(p, e);
				p = e;
			} else {
				const sptr_t n = [self sci:SCI_INDICATOREND w:(uptr_t)indic l:p];
				if (n <= p)
					break;
				p = n;
			}
		}
	}
	std::sort(ranges.begin(), ranges.end());
	NSMutableArray *parts = [NSMutableArray array];
	for (auto &r : ranges) {
		std::string s = [self textRangeFrom:r.first to:r.second];
		[parts addObject:[[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @""];
	}
	[NSPasteboard.generalPasteboard clearContents];
	const int eol = (int)[self sci:SCI_GETEOLMODE];
	NSString *sep = eol == SC_EOL_CRLF ? @"\r\n" : eol == SC_EOL_CR ? @"\r" : @"\n";
	[NSPasteboard.generalPasteboard setString:[parts componentsJoinedByString:sep] forType:NSPasteboardTypeString];
}

- (std::vector<sptr_t>)bookmarkedLines
{
	std::vector<sptr_t> lines;
	for (sptr_t l = [self sci:SCI_MARKERNEXT w:0 l:1 << MPP_MARK_BOOKMARK]; l >= 0;
	     l = [self sci:SCI_MARKERNEXT w:(uptr_t)(l + 1) l:1 << MPP_MARK_BOOKMARK])
		lines.push_back(l);
	return lines;
}

- (void)deleteLines:(const std::vector<sptr_t> &)lines
{
	[self sci:SCI_BEGINUNDOACTION];
	for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
		const sptr_t s = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)*it];
		const sptr_t e = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)(*it + 1)];
		sptr_t end = e;
		if (*it == [self sci:SCI_GETLINECOUNT] - 1)
			end = [self sci:SCI_GETLENGTH];
		sptr_t start = s;
		if (*it == [self sci:SCI_GETLINECOUNT] - 1 && *it > 0)   // last line: remove the preceding EOL instead
			start = [self sci:SCI_GETLINEENDPOSITION w:(uptr_t)(*it - 1)];
		[self sci:SCI_DELETERANGE w:(uptr_t)start l:end - start];
	}
	[self sci:SCI_ENDUNDOACTION];
}

- (NSString *)textOfLines:(const std::vector<sptr_t> &)lines
{
	std::string out;
	for (sptr_t l : lines) {
		out += [self textRangeFrom:[self sci:SCI_POSITIONFROMLINE w:(uptr_t)l]
		                        to:[self sci:SCI_POSITIONFROMLINE w:(uptr_t)(l + 1)]];
		if (l == [self sci:SCI_GETLINECOUNT] - 1)
			out += MppEOLString(self.activeEditor);
	}
	return [[NSString alloc] initWithBytes:out.data() length:out.size() encoding:NSUTF8StringEncoding];
}

- (void)gotoChange:(BOOL)forward
{
	const int mask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) | (1 << SC_MARKNUM_HISTORY_SAVED) |
	                 (1 << SC_MARKNUM_HISTORY_MODIFIED) | (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
	const sptr_t cur = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]];
	const sptr_t lines = [self sci:SCI_GETLINECOUNT];
	sptr_t l;
	if (forward) {
		// skip the current block of changed lines
		l = cur;
		while (l < lines && ([self sci:SCI_MARKERGET w:(uptr_t)l] & mask))
			++l;
		l = [self sci:SCI_MARKERNEXT w:(uptr_t)l l:mask];
		if (l < 0)
			l = [self sci:SCI_MARKERNEXT w:0 l:mask];
	} else {
		l = cur;
		while (l >= 0 && ([self sci:SCI_MARKERGET w:(uptr_t)l] & mask))
			--l;
		l = l >= 0 ? [self sci:SCI_MARKERPREVIOUS w:(uptr_t)l l:mask] : -1;
		if (l < 0)
			l = [self sci:SCI_MARKERPREVIOUS w:(uptr_t)(lines - 1) l:mask];
		while (l > 0 && ([self sci:SCI_MARKERGET w:(uptr_t)(l - 1)] & mask))
			--l;
	}
	if (l < 0) {
		NSBeep();
		return;
	}
	[self gotoLine:l];
}

- (BOOL)handleSearchCommand:(int)cmd
{
	MppFindReplaceController *fr = self.findReplace;
	MppScintillaView *v = self.activeEditor;

	if (cmd >= CMD_SEARCH_MARKALLEXT1 && cmd <= CMD_SEARCH_MARKALLEXT5) {
		NSString *t = [self findTextFromSelection];
		if (!t.length)
			return YES;
		MppFindOptions o;
		o.matchCase = true;
		o.wholeWord = [self sci:SCI_GETSELECTIONEMPTY] != 0;
		[fr markAll:t.UTF8String options:o indicator:kExtIndicators[cmd - CMD_SEARCH_MARKALLEXT1] bookmark:NO];
		return YES;
	}
	if (cmd >= CMD_SEARCH_MARKONEEXT1 && cmd <= CMD_SEARCH_MARKONEEXT5) {
		sptr_t s = [self sci:SCI_GETSELECTIONSTART], e = [self sci:SCI_GETSELECTIONEND];
		if (s == e) {
			s = [self sci:SCI_WORDSTARTPOSITION w:(uptr_t)s l:1];
			e = [self sci:SCI_WORDENDPOSITION w:(uptr_t)e l:1];
		}
		[self sci:SCI_SETINDICATORCURRENT w:(uptr_t)kExtIndicators[cmd - CMD_SEARCH_MARKONEEXT1]];
		[self sci:SCI_INDICATORFILLRANGE w:(uptr_t)s l:e - s];
		return YES;
	}
	if (cmd >= CMD_SEARCH_UNMARKALLEXT1 && cmd <= CMD_SEARCH_UNMARKALLEXT5) {
		[self sci:SCI_SETINDICATORCURRENT w:(uptr_t)kExtIndicators[cmd - CMD_SEARCH_UNMARKALLEXT1]];
		[self sci:SCI_INDICATORCLEARRANGE w:0 l:[self sci:SCI_GETLENGTH]];
		return YES;
	}
	if (cmd >= CMD_SEARCH_GOPREVMARKER1 && cmd <= CMD_SEARCH_GOPREVMARKER_DEF) {
		const int i = cmd - CMD_SEARCH_GOPREVMARKER1;
		[self jumpToIndicator:(i < 5 ? kExtIndicators[i] : MPP_INDIC_FOUND_STYLE) forward:NO];
		return YES;
	}
	if (cmd >= CMD_SEARCH_GONEXTMARKER1 && cmd <= CMD_SEARCH_GONEXTMARKER_DEF) {
		const int i = cmd - CMD_SEARCH_GONEXTMARKER1;
		[self jumpToIndicator:(i < 5 ? kExtIndicators[i] : MPP_INDIC_FOUND_STYLE) forward:YES];
		return YES;
	}
	if (cmd >= CMD_SEARCH_STYLE1TOCLIP && cmd <= CMD_SEARCH_STYLE5TOCLIP) {
		[self copyIndicatorText:{kExtIndicators[cmd - CMD_SEARCH_STYLE1TOCLIP]}];
		return YES;
	}

	switch (cmd) {
		case CMD_SEARCH_FIND:
		case CMD_SEARCH_REPLACE:
		case CMD_SEARCH_FINDINFILES:
		case CMD_SEARCH_MARK: {
			NSString *t = [self findTextFromSelection];
			if (t.length && ![self sci:SCI_GETSELECTIONEMPTY])
				[fr setFindText:t];
			else if (t.length && !fr.findText.length)
				[fr setFindText:t];
			if (cmd == CMD_SEARCH_FINDINFILES && self.currentDocument.filePath)
				[fr setFindDirectory:self.currentDocument.filePath.stringByDeletingLastPathComponent];
			MppFindTab tab = cmd == CMD_SEARCH_FIND ? MppFindTabFind : cmd == CMD_SEARCH_REPLACE ? MppFindTabReplace
			               : cmd == CMD_SEARCH_FINDINFILES ? MppFindTabFindInFiles : MppFindTabMark;
			[fr showTab:tab];
			return YES;
		}
		case CMD_SEARCH_FINDNEXT: [fr findNext:YES]; return YES;
		case CMD_SEARCH_FINDPREV: [fr findNext:NO]; return YES;
		case CMD_SEARCH_SETANDFINDNEXT:
		case CMD_SEARCH_SETANDFINDPREV: {
			NSString *t = [self findTextFromSelection];
			if (!t.length)
				return YES;
			[fr setFindText:t];
			[fr findNext:cmd == CMD_SEARCH_SETANDFINDNEXT];
			return YES;
		}
		case CMD_SEARCH_VOLATILE_FINDNEXT:
		case CMD_SEARCH_VOLATILE_FINDPREV: {
			NSString *t = [self findTextFromSelection];
			if (!t.length)
				return YES;
			MppFindOptions o;
			o.matchCase = false;
			o.wrapAround = true;
			[fr findText:t.UTF8String forward:cmd == CMD_SEARCH_VOLATILE_FINDNEXT options:o showStatus:NO];
			return YES;
		}
		case CMD_SEARCH_FINDINCREMENT: [fr showIncrementalSearch]; return YES;
		case CMD_SEARCH_FOCUS_ON_FOUND_RESULTS:
			[self showSearchResults:YES];
			[self.window makeFirstResponder:self.searchResults.resultView.content];
			return YES;
		case CMD_SEARCH_GOTONEXTFOUND: [self.searchResults gotoResult:YES]; return YES;
		case CMD_SEARCH_GOTOPREVFOUND: [self.searchResults gotoResult:NO]; return YES;
		case CMD_SEARCH_GOTOLINE: MppShowGoToDialog(self); return YES;
		case CMD_SEARCH_GOTOMATCHINGBRACE:
		case CMD_SEARCH_SELECTMATCHINGBRACES: {
			const sptr_t caret = [self sci:SCI_GETCURRENTPOS];
			sptr_t brace = -1;
			auto isBrace = [](int c) { return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}'; };
			if (caret > 0 && isBrace((int)[self sci:SCI_GETCHARAT w:(uptr_t)caret - 1]))
				brace = caret - 1;
			else if (isBrace((int)[self sci:SCI_GETCHARAT w:(uptr_t)caret]))
				brace = caret;
			if (brace < 0) {
				NSBeep();
				return YES;
			}
			const sptr_t match = [self sci:SCI_BRACEMATCH w:(uptr_t)brace l:0];
			if (match < 0) {
				NSBeep();
				return YES;
			}
			if (cmd == CMD_SEARCH_GOTOMATCHINGBRACE) {
				[self sci:SCI_GOTOPOS w:(uptr_t)(match < brace ? match : match + 1)];
			} else {
				const sptr_t a = std::min(brace, match) + 1, b = std::max(brace, match);
				[self sci:SCI_SETSEL w:(uptr_t)a l:b];
			}
			return YES;
		}
		case CMD_SEARCH_CHANGED_NEXT: [self gotoChange:YES]; return YES;
		case CMD_SEARCH_CHANGED_PREV: [self gotoChange:NO]; return YES;
		case CMD_SEARCH_CLEAR_CHANGE_HISTORY: {
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = @"Clear Change History";
			a.informativeText = @"Clearing the change history also clears the undo history of this document. Continue?";
			[a addButtonWithTitle:@"Clear"];
			[a addButtonWithTitle:@"Cancel"];
			if ([a runModal] != NSAlertFirstButtonReturn)
				return YES;
			const sptr_t mode = [self sci:SCI_GETCHANGEHISTORY];
			[self sci:SCI_EMPTYUNDOBUFFER];
			[self sci:SCI_SETCHANGEHISTORY w:SC_CHANGE_HISTORY_DISABLED];
			[self sci:SCI_SETCHANGEHISTORY w:(uptr_t)mode];
			return YES;
		}
		case CMD_SEARCH_CLEARALLMARKS:
			for (int i : kExtIndicators) {
				[self sci:SCI_SETINDICATORCURRENT w:(uptr_t)i];
				[self sci:SCI_INDICATORCLEARRANGE w:0 l:[self sci:SCI_GETLENGTH]];
			}
			return YES;
		case CMD_SEARCH_ALLSTYLESTOCLIP:
			[self copyIndicatorText:std::vector<int>(std::begin(kExtIndicators), std::end(kExtIndicators))];
			return YES;
		case CMD_SEARCH_MARKEDTOCLIP:
			[self copyIndicatorText:{MPP_INDIC_FOUND_STYLE}];
			return YES;
		case CMD_SEARCH_TOGGLE_BOOKMARK:
			MppToggleBookmark(v, [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]]);
			return YES;
		case CMD_SEARCH_NEXT_BOOKMARK:
		case CMD_SEARCH_PREV_BOOKMARK: {
			const sptr_t cur = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]];
			const int mask = 1 << MPP_MARK_BOOKMARK;
			sptr_t l;
			if (cmd == CMD_SEARCH_NEXT_BOOKMARK) {
				l = [self sci:SCI_MARKERNEXT w:(uptr_t)(cur + 1) l:mask];
				if (l < 0)
					l = [self sci:SCI_MARKERNEXT w:0 l:mask];
			} else {
				l = cur > 0 ? [self sci:SCI_MARKERPREVIOUS w:(uptr_t)(cur - 1) l:mask] : -1;
				if (l < 0)
					l = [self sci:SCI_MARKERPREVIOUS w:(uptr_t)[self sci:SCI_GETLINECOUNT] l:mask];
			}
			if (l >= 0)
				[self gotoLine:l];
			else
				NSBeep();
			return YES;
		}
		case CMD_SEARCH_CLEAR_BOOKMARKS: [self sci:SCI_MARKERDELETEALL w:MPP_MARK_BOOKMARK]; return YES;
		case CMD_SEARCH_COPYMARKEDLINES:
		case CMD_SEARCH_CUTMARKEDLINES: {
			auto lines = [self bookmarkedLines];
			if (lines.empty())
				return YES;
			[NSPasteboard.generalPasteboard clearContents];
			[NSPasteboard.generalPasteboard setString:[self textOfLines:lines] forType:NSPasteboardTypeString];
			if (cmd == CMD_SEARCH_CUTMARKEDLINES)
				[self deleteLines:lines];
			return YES;
		}
		case CMD_SEARCH_DELETEMARKEDLINES: [self deleteLines:[self bookmarkedLines]]; return YES;
		case CMD_SEARCH_DELETEUNMARKEDLINES: {
			auto marked = [self bookmarkedLines];
			std::vector<sptr_t> unmarked;
			const sptr_t n = [self sci:SCI_GETLINECOUNT];
			size_t k = 0;
			for (sptr_t l = 0; l < n; ++l) {
				if (k < marked.size() && marked[k] == l) {
					++k;
					continue;
				}
				unmarked.push_back(l);
			}
			[self deleteLines:unmarked];
			return YES;
		}
		case CMD_SEARCH_PASTEMARKEDLINES: {
			auto lines = [self bookmarkedLines];
			NSString *clip = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
			if (lines.empty() || !clip)
				return YES;
			std::string text = clip.UTF8String;
			[self sci:SCI_BEGINUNDOACTION];
			for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
				const sptr_t s = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)*it];
				const sptr_t e = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)(*it + 1)];
				[self sci:SCI_SETTARGETRANGE w:(uptr_t)s l:(e > s ? e : [self sci:SCI_GETLENGTH])];
				[self sci:SCI_REPLACETARGET w:text.size() l:(sptr_t)text.c_str()];
			}
			[self sci:SCI_ENDUNDOACTION];
			return YES;
		}
		case CMD_SEARCH_INVERSEMARKS: {
			const sptr_t n = [self sci:SCI_GETLINECOUNT];
			for (sptr_t l = 0; l < n; ++l)
				MppToggleBookmark(v, l);
			return YES;
		}
		case CMD_SEARCH_FINDCHARINRANGE: MppShowFindCharsInRange(self); return YES;
		default:
			return NO;
	}
}

@end
