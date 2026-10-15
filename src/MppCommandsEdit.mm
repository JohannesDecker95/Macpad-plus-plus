// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMainWindowController.h"
#import "MppEditing.h"
#import "MppPrefs.h"
#import "MppDialogs.h"
#import "MppAutoCompletion.h"
#import "MppUserLang.h"
#include "Scintilla.h"
#include <algorithm>
#include <random>
#include <set>
#include <unordered_set>

static NSString *ns(const std::string &s)
{
	return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static std::string utf8(NSString *s)
{
	const char *c = s.UTF8String;
	return c ? std::string(c) : std::string();
}

// Case conversions (Edit > Convert Case to)
static std::string properCase(const std::string &in, bool blend)
{
	NSString *s = ns(in);
	NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
	BOOL newWord = YES;
	for (NSUInteger i = 0; i < s.length; ++i) {
		unichar c = [s characterAtIndex:i];
		NSString *ch = [NSString stringWithCharacters:&c length:1];
		const BOOL isAlnum = [NSCharacterSet.alphanumericCharacterSet characterIsMember:c] || c == '\'';
		if (!isAlnum) {
			[out appendString:ch];
			newWord = YES;
			continue;
		}
		if (newWord)
			[out appendString:ch.uppercaseString];
		else
			[out appendString:blend ? ch : ch.lowercaseString];
		newWord = NO;
	}
	return utf8(out);
}

static std::string sentenceCase(const std::string &in, bool blend)
{
	NSString *s = ns(in);
	NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
	BOOL sentenceStart = YES;
	for (NSUInteger i = 0; i < s.length; ++i) {
		unichar c = [s characterAtIndex:i];
		NSString *ch = [NSString stringWithCharacters:&c length:1];
		if ([NSCharacterSet.letterCharacterSet characterIsMember:c]) {
			[out appendString:sentenceStart ? ch.uppercaseString : (blend ? ch : ch.lowercaseString)];
			sentenceStart = NO;
		} else {
			[out appendString:ch];
			if (c == '.' || c == '!' || c == '?' || c == '\n' || c == '\r')
				sentenceStart = YES;
		}
	}
	return utf8(out);
}

static std::string invertCase(const std::string &in)
{
	NSString *s = ns(in);
	NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
	for (NSUInteger i = 0; i < s.length; ++i) {
		unichar c = [s characterAtIndex:i];
		NSString *ch = [NSString stringWithCharacters:&c length:1];
		if ([NSCharacterSet.uppercaseLetterCharacterSet characterIsMember:c])
			[out appendString:ch.lowercaseString];
		else if ([NSCharacterSet.lowercaseLetterCharacterSet characterIsMember:c])
			[out appendString:ch.uppercaseString];
		else
			[out appendString:ch];
	}
	return utf8(out);
}

static std::string randomCase(const std::string &in)
{
	NSString *s = ns(in);
	NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
	for (NSUInteger i = 0; i < s.length; ++i) {
		unichar c = [s characterAtIndex:i];
		NSString *ch = [NSString stringWithCharacters:&c length:1];
		[out appendString:arc4random_uniform(2) ? ch.uppercaseString : ch.lowercaseString];
	}
	return utf8(out);
}

// Numeric sort keys ("Sort Lines As Integers/Decimals")
static bool parseNumber(const std::string &line, int mode, double &out)
{
	// mode 0 integer, 1 decimal comma, 2 decimal dot
	std::string s = line;
	const size_t b = s.find_first_not_of(" \t");
	if (b == std::string::npos)
		return false;
	s = s.substr(b);
	if (mode == 1) {
		std::replace(s.begin(), s.end(), '.', '\x01');
		std::replace(s.begin(), s.end(), ',', '.');
	}
	char *end = nullptr;
	if (mode == 0) {
		long long v = strtoll(s.c_str(), &end, 10);
		out = (double)v;
	} else {
		out = strtod(s.c_str(), &end);
	}
	return end != s.c_str();
}

static NSUInteger charCount(const std::string &s)
{
	return ns(s).length;
}

@implementation MppMainWindowController (Edit)

- (void)ensureSelectionOrWord
{
	if ([self sci:SCI_GETSELECTIONEMPTY] && [self sci:SCI_GETSELECTIONS] == 1) {
		const sptr_t pos = [self sci:SCI_GETCURRENTPOS];
		const sptr_t s = [self sci:SCI_WORDSTARTPOSITION w:(uptr_t)pos l:1];
		const sptr_t e = [self sci:SCI_WORDENDPOSITION w:(uptr_t)pos l:1];
		[self sci:SCI_SETSEL w:(uptr_t)s l:e];
	}
}

- (void)sortLines:(int)cmd
{
	const bool desc = cmd >= CMD_EDIT_SORT_LEX_DESC;
	MppScintillaView *v = self.activeEditor;
	bool nonNumeric = false;
	MppTransformLines(v, [&](std::vector<std::string> &lines) {
		switch (cmd) {
			case CMD_EDIT_SORT_REVERSE:
				std::reverse(lines.begin(), lines.end());
				return;
			case CMD_EDIT_SORT_RANDOM: {
				std::random_device rd;
				std::mt19937 g(rd());
				std::shuffle(lines.begin(), lines.end(), g);
				return;
			}
			case CMD_EDIT_SORT_LEX_ASC: case CMD_EDIT_SORT_LEX_DESC:
				std::stable_sort(lines.begin(), lines.end());
				break;
			case CMD_EDIT_SORT_LEX_CI_ASC: case CMD_EDIT_SORT_LEX_CI_DESC:
				std::stable_sort(lines.begin(), lines.end(), [](const std::string &a, const std::string &b) {
					return [ns(a) caseInsensitiveCompare:ns(b)] == NSOrderedAscending;
				});
				break;
			case CMD_EDIT_SORT_LOCALE_ASC: case CMD_EDIT_SORT_LOCALE_DESC:
				std::stable_sort(lines.begin(), lines.end(), [](const std::string &a, const std::string &b) {
					return [ns(a) localizedStandardCompare:ns(b)] == NSOrderedAscending;
				});
				break;
			case CMD_EDIT_SORT_LEN_ASC: case CMD_EDIT_SORT_LEN_DESC:
				std::stable_sort(lines.begin(), lines.end(), [](const std::string &a, const std::string &b) {
					return charCount(a) < charCount(b);
				});
				break;
			default: {
				const int mode = (cmd == CMD_EDIT_SORT_INT_ASC || cmd == CMD_EDIT_SORT_INT_DESC) ? 0
				               : (cmd == CMD_EDIT_SORT_DECCOMMA_ASC || cmd == CMD_EDIT_SORT_DECCOMMA_DESC) ? 1 : 2;
				for (const auto &l : lines) {
					double d;
					if (!l.empty() && !parseNumber(l, mode, d))
						nonNumeric = true;
				}
				if (nonNumeric)
					return;
				std::stable_sort(lines.begin(), lines.end(), [mode](const std::string &a, const std::string &b) {
					double da = 0, db = 0;
					const bool ha = parseNumber(a, mode, da), hb = parseNumber(b, mode, db);
					if (ha != hb)
						return !ha;   // empty lines first
					return da < db;
				});
				break;
			}
		}
		if (desc)
			std::reverse(lines.begin(), lines.end());
	});
	if (nonNumeric) {
		NSAlert *a = [[NSAlert alloc] init];
		a.messageText = @"Sorting failed: some lines are not numbers.";
		[a runModal];
	}
}

- (NSString *)lineCommentToken
{
	MppDocument *doc = self.currentDocument;
	if (doc.lang == L_USER)
		return [MppUserLangManager.shared commentLineForLanguage:doc.userLangName];
	const MppLangDef *d = [MppLanguages.shared langDefForType:doc.lang];
	if (d && !d->commentLine.empty())
		return @(d->commentLine.c_str());
	return nil;
}

- (void)toggleLineComment:(int)mode
{
	NSString *tokenNS = [self lineCommentToken];
	if (!tokenNS.length) {
		// fall back to stream comments when the language has no line comments (e.g. CSS, HTML)
		if (mode != 2)
			[self streamComment:YES];
		else
			[self streamComment:NO];
		return;
	}
	const std::string token = utf8(tokenNS);
	const std::string tokenSp = token + " ";
	MppScintillaView *v = self.activeEditor;
	const sptr_t selStart = [self sci:SCI_GETSELECTIONSTART], selEnd = [self sci:SCI_GETSELECTIONEND];
	sptr_t l1 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)selStart];
	sptr_t l2 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)selEnd];
	if (l2 > l1 && selEnd == [self sci:SCI_POSITIONFROMLINE w:(uptr_t)l2])
		--l2;

	// In toggle mode: uncomment if all non-empty lines are commented
	bool allCommented = true;
	for (sptr_t l = l1; l <= l2; ++l) {
		std::string line = MppGetLine(v, l);
		const size_t b = line.find_first_not_of(" \t");
		if (b == std::string::npos)
			continue;
		if (line.compare(b, token.size(), token) != 0) {
			allCommented = false;
			break;
		}
	}
	const bool uncomment = (mode == 2) || (mode == 0 && allCommented);
	[self sci:SCI_BEGINUNDOACTION];
	for (sptr_t l = l1; l <= l2; ++l) {
		const sptr_t lineStart = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)l];
		const sptr_t indentPos = [self sci:SCI_GETLINEINDENTPOSITION w:(uptr_t)l];
		const sptr_t lineEnd = [self sci:SCI_GETLINEENDPOSITION w:(uptr_t)l];
		if (indentPos == lineEnd && l1 != l2)
			continue;   // skip blank lines
		if (uncomment) {
			std::string rest = MppGetRange(v, indentPos, lineEnd);
			if (rest.compare(0, tokenSp.size(), tokenSp) == 0)
				[self sci:SCI_DELETERANGE w:(uptr_t)indentPos l:(sptr_t)tokenSp.size()];
			else if (rest.compare(0, token.size(), token) == 0)
				[self sci:SCI_DELETERANGE w:(uptr_t)indentPos l:(sptr_t)token.size()];
		} else {
			(void)lineStart;
			[self sci:SCI_INSERTTEXT w:(uptr_t)indentPos l:(sptr_t)tokenSp.c_str()];
		}
	}
	[self sci:SCI_ENDUNDOACTION];
}

- (void)streamComment:(BOOL)comment
{
	MppDocument *doc = self.currentDocument;
	const MppLangDef *d = [MppLanguages.shared langDefForType:doc.lang];
	if (!d || d->commentStart.empty() || d->commentEnd.empty()) {
		NSBeep();
		return;
	}
	const std::string open = d->commentStart, close = d->commentEnd;
	MppScintillaView *v = self.activeEditor;
	sptr_t s = [self sci:SCI_GETSELECTIONSTART], e = [self sci:SCI_GETSELECTIONEND];
	[self sci:SCI_BEGINUNDOACTION];
	if (comment) {
		if (s == e) {
			s = [self sci:SCI_WORDSTARTPOSITION w:(uptr_t)s l:1];
			e = [self sci:SCI_WORDENDPOSITION w:(uptr_t)e l:1];
		}
		[self sci:SCI_INSERTTEXT w:(uptr_t)e l:(sptr_t)close.c_str()];
		[self sci:SCI_INSERTTEXT w:(uptr_t)s l:(sptr_t)open.c_str()];
		[self sci:SCI_SETSEL w:(uptr_t)s l:e + (sptr_t)open.size() + (sptr_t)close.size()];
	} else {
		// find enclosing comment around the caret/selection
		const sptr_t len = [self sci:SCI_GETLENGTH];
		std::string before = MppGetRange(v, std::max<sptr_t>(0, s - 100000), std::min(len, s + (sptr_t)open.size()));
		size_t o = before.rfind(open);
		if (o == std::string::npos) {
			[self sci:SCI_ENDUNDOACTION];
			NSBeep();
			return;
		}
		const sptr_t openPos = std::max<sptr_t>(0, s - 100000) + (sptr_t)o;
		std::string after = MppGetRange(v, openPos + (sptr_t)open.size(), std::min(len, e + 100000));
		size_t c = after.find(close);
		if (c == std::string::npos) {
			[self sci:SCI_ENDUNDOACTION];
			NSBeep();
			return;
		}
		const sptr_t closePos = openPos + (sptr_t)open.size() + (sptr_t)c;
		[self sci:SCI_DELETERANGE w:(uptr_t)closePos l:(sptr_t)close.size()];
		[self sci:SCI_DELETERANGE w:(uptr_t)openPos l:(sptr_t)open.size()];
	}
	[self sci:SCI_ENDUNDOACTION];
}

- (void)insertDateTime:(int)cmd
{
	NSDateFormatter *f = [[NSDateFormatter alloc] init];
	switch (cmd) {
		case CMD_EDIT_INSERT_DATETIME_SHORT:
			f.dateStyle = NSDateFormatterShortStyle;
			f.timeStyle = NSDateFormatterShortStyle;
			break;
		case CMD_EDIT_INSERT_DATETIME_LONG:
			f.dateStyle = NSDateFormatterFullStyle;
			f.timeStyle = NSDateFormatterShortStyle;
			break;
		default:
			f.dateFormat = [MppPrefs shared].dateTimeFormat;
			break;
	}
	std::string s = utf8([f stringFromDate:NSDate.date]);
	[self sci:SCI_REPLACESEL w:0 l:(sptr_t)s.c_str()];
}

- (void)copyToClipboard:(NSString *)s
{
	if (!s)
		return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:s forType:NSPasteboardTypeString];
}

- (void)multiSelect:(int)cmd
{
	const bool all = cmd <= CMD_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD;
	const int variant = all ? cmd - CMD_EDIT_MULTISELECTALL : cmd - CMD_EDIT_MULTISELECTNEXT;
	int flags = 0;
	switch (variant) {
		case 0: flags = SCFIND_WHOLEWORD; break;            // ignore case & whole word
		case 1: flags = SCFIND_MATCHCASE; break;            // match case only
		case 2: flags = SCFIND_WHOLEWORD; break;            // whole word only (case insensitive)
		case 3: flags = SCFIND_MATCHCASE | SCFIND_WHOLEWORD; break;
	}
	if ([self sci:SCI_GETSELECTIONEMPTY]) {
		const sptr_t pos = [self sci:SCI_GETCURRENTPOS];
		[self sci:SCI_SETSEL w:(uptr_t)[self sci:SCI_WORDSTARTPOSITION w:(uptr_t)pos l:1]
		       l:[self sci:SCI_WORDENDPOSITION w:(uptr_t)pos l:1]];
		if ([self sci:SCI_GETSELECTIONEMPTY])
			return;
		if (!all)
			return;   // first invocation only selects the word
	}
	[self sci:SCI_TARGETWHOLEDOCUMENT];
	[self sci:SCI_SETSEARCHFLAGS w:(uptr_t)flags];
	if (all)
		[self sci:SCI_MULTIPLESELECTADDEACH];
	else
		[self sci:SCI_MULTIPLESELECTADDNEXT];
	[self sci:SCI_SCROLLRANGE w:(uptr_t)[self sci:SCI_GETSELECTIONNANCHOR w:(uptr_t)[self sci:SCI_GETMAINSELECTION]]
	       l:[self sci:SCI_GETSELECTIONNCARET w:(uptr_t)[self sci:SCI_GETMAINSELECTION]]];
}

- (void)blankOperation:(int)cmd
{
	MppScintillaView *v = self.activeEditor;
	const sptr_t tabWidth = [self sci:SCI_GETTABWIDTH];
	switch (cmd) {
		case CMD_EDIT_TRIMTRAILING:
			MppTransformLines(v, [](std::vector<std::string> &lines) {
				for (auto &l : lines) {
					size_t e = l.find_last_not_of(" \t");
					l.erase(e == std::string::npos ? 0 : e + 1);
				}
			});
			break;
		case CMD_EDIT_TRIMLINEHEAD:
			MppTransformLines(v, [](std::vector<std::string> &lines) {
				for (auto &l : lines) {
					size_t b = l.find_first_not_of(" \t");
					l.erase(0, b == std::string::npos ? l.size() : b);
				}
			});
			break;
		case CMD_EDIT_TRIM_BOTH:
			MppTransformLines(v, [](std::vector<std::string> &lines) {
				for (auto &l : lines) {
					size_t e = l.find_last_not_of(" \t");
					l.erase(e == std::string::npos ? 0 : e + 1);
					size_t b = l.find_first_not_of(" \t");
					l.erase(0, b == std::string::npos ? l.size() : b);
				}
			});
			break;
		case CMD_EDIT_EOL2WS:
		case CMD_EDIT_TRIMALL:
			MppTransformLines(v, [cmd](std::vector<std::string> &lines) {
				std::string joined;
				for (size_t i = 0; i < lines.size(); ++i) {
					std::string l = lines[i];
					if (cmd == CMD_EDIT_TRIMALL) {
						size_t e = l.find_last_not_of(" \t");
						l.erase(e == std::string::npos ? 0 : e + 1);
						size_t b = l.find_first_not_of(" \t");
						l.erase(0, b == std::string::npos ? l.size() : b);
						if (l.empty())
							continue;
					}
					if (!joined.empty())
						joined += ' ';
					joined += l;
				}
				lines.assign(1, joined);
			});
			break;
		case CMD_EDIT_TAB2SW:
			MppTransformLines(v, [tabWidth](std::vector<std::string> &lines) {
				for (auto &l : lines) {
					std::string out;
					size_t col = 0;
					for (size_t i = 0; i < l.size(); ++i) {
						const unsigned char c = (unsigned char)l[i];
						if (c == '\t') {
							const size_t n = (size_t)tabWidth - (col % (size_t)tabWidth);
							out.append(n, ' ');
							col += n;
						} else {
							out += (char)c;
							if ((c & 0xC0) != 0x80)
								++col;
						}
					}
					l = out;
				}
			});
			break;
		case CMD_EDIT_SW2TAB_ALL:
		case CMD_EDIT_SW2TAB_LEADING: {
			const bool leadingOnly = cmd == CMD_EDIT_SW2TAB_LEADING;
			MppTransformLines(v, [tabWidth, leadingOnly](std::vector<std::string> &lines) {
				for (auto &l : lines) {
					std::string out;
					size_t col = 0, pendingSpaces = 0;
					bool leading = true;
					for (size_t i = 0; i < l.size(); ++i) {
						const unsigned char c = (unsigned char)l[i];
						const bool convert = !leadingOnly || leading;
						if (c == ' ' && convert) {
							++pendingSpaces;
							++col;
							if (col % (size_t)tabWidth == 0) {
								out += pendingSpaces > 1 ? '\t' : ' ';
								pendingSpaces = 0;
							}
							continue;
						}
						out.append(pendingSpaces, ' ');
						pendingSpaces = 0;
						if (c == '\t') {
							out += '\t';
							col += (size_t)tabWidth - (col % (size_t)tabWidth);
						} else {
							leading = false;
							out += (char)c;
							if ((c & 0xC0) != 0x80)
								++col;
						}
					}
					out.append(pendingSpaces, ' ');
					l = out;
				}
			});
			break;
		}
		default:
			break;
	}
}

- (BOOL)handleEditCommand:(int)cmd
{
	MppDocument *doc = self.currentDocument;
	MppScintillaView *v = self.activeEditor;
	MppPrefs *prefs = [MppPrefs shared];

	if (cmd >= CMD_EDIT_SORT_REVERSE && cmd <= CMD_EDIT_SORT_LEN_DESC) {
		[self sortLines:cmd];
		return YES;
	}
	if (cmd >= CMD_EDIT_MULTISELECTALL && cmd <= CMD_EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD) {
		[self multiSelect:cmd];
		return YES;
	}

	static sptr_t beginSelectPos = -1;
	static __weak MppDocument *beginSelectDoc = nil;

	switch (cmd) {
		case CMD_EDIT_UNDO: [self sci:SCI_UNDO]; return YES;
		case CMD_EDIT_REDO: [self sci:SCI_REDO]; return YES;
		case CMD_EDIT_CUT: [v.content performSelector:@selector(cut:) withObject:nil]; return YES;
		case CMD_EDIT_COPY: [v.content performSelector:@selector(copy:) withObject:nil]; return YES;
		case CMD_EDIT_PASTE: [self sci:SCI_PASTE]; return YES;
		case CMD_EDIT_DELETE: [self sci:SCI_CLEAR]; return YES;
		case CMD_EDIT_SELECTALL: [self sci:SCI_SELECTALL]; return YES;
		case CMD_EDIT_BEGINENDSELECT:
		case CMD_EDIT_BEGINENDSELECT_COLUMN: {
			const sptr_t pos = [self sci:SCI_GETCURRENTPOS];
			if (beginSelectPos < 0 || beginSelectDoc != doc) {
				beginSelectPos = pos;
				beginSelectDoc = doc;
				[self setStatusMessage:@"Begin select: move the caret and use Begin/End Select again"];
			} else {
				if (cmd == CMD_EDIT_BEGINENDSELECT_COLUMN) {
					[self sci:SCI_SETSELECTIONMODE w:SC_SEL_RECTANGLE];
					[self sci:SCI_SETANCHOR w:(uptr_t)beginSelectPos];
					[self sci:SCI_SETCURRENTPOS w:(uptr_t)pos];
					[self sci:SCI_SETSELECTIONMODE w:SC_SEL_STREAM];
				} else {
					[self sci:SCI_SETSEL w:(uptr_t)beginSelectPos l:pos];
				}
				beginSelectPos = -1;
				[self setStatusMessage:nil];
			}
			return YES;
		}
		case CMD_EDIT_INSERT_DATETIME_SHORT:
		case CMD_EDIT_INSERT_DATETIME_LONG:
		case CMD_EDIT_INSERT_DATETIME_CUSTOM:
			[self insertDateTime:cmd];
			return YES;
		case CMD_EDIT_FULLPATHTOCLIP: [self copyToClipboard:doc.filePath ?: doc.displayName]; return YES;
		case CMD_EDIT_FILENAMETOCLIP: [self copyToClipboard:doc.displayName]; return YES;
		case CMD_EDIT_CURRENTDIRTOCLIP: [self copyToClipboard:doc.filePath.stringByDeletingLastPathComponent]; return YES;
		case CMD_EDIT_COPY_ALL_NAMES:
		case CMD_EDIT_COPY_ALL_PATHS: {
			NSMutableArray *a = [NSMutableArray array];
			for (MppDocument *d in [self allDocuments])
				[a addObject:(cmd == CMD_EDIT_COPY_ALL_PATHS && d.filePath) ? d.filePath : d.displayName];
			[self copyToClipboard:[a componentsJoinedByString:@"\n"]];
			return YES;
		}
		case CMD_EDIT_INS_TAB: [self sci:SCI_TAB]; return YES;
		case CMD_EDIT_RMV_TAB: [self sci:SCI_BACKTAB]; return YES;
		case CMD_EDIT_UPPERCASE: [self ensureSelectionOrWord]; [self sci:SCI_UPPERCASE]; return YES;
		case CMD_EDIT_LOWERCASE: [self ensureSelectionOrWord]; [self sci:SCI_LOWERCASE]; return YES;
		case CMD_EDIT_PROPERCASE_FORCE:
		case CMD_EDIT_PROPERCASE_BLEND: {
			const bool blend = cmd == CMD_EDIT_PROPERCASE_BLEND;
			[self ensureSelectionOrWord];
			MppTransformSelection(v, [blend](const std::string &s) { return properCase(s, blend); }, false);
			return YES;
		}
		case CMD_EDIT_SENTENCECASE_FORCE:
		case CMD_EDIT_SENTENCECASE_BLEND: {
			const bool blend = cmd == CMD_EDIT_SENTENCECASE_BLEND;
			[self ensureSelectionOrWord];
			MppTransformSelection(v, [blend](const std::string &s) { return sentenceCase(s, blend); }, false);
			return YES;
		}
		case CMD_EDIT_INVERTCASE:
			[self ensureSelectionOrWord];
			MppTransformSelection(v, invertCase, false);
			return YES;
		case CMD_EDIT_RANDOMCASE:
			[self ensureSelectionOrWord];
			MppTransformSelection(v, randomCase, false);
			return YES;
		case CMD_EDIT_DUP_LINE: [self sci:SCI_LINEDUPLICATE]; return YES;
		case CMD_EDIT_DELETE_LINE: [self sci:SCI_LINEDELETE]; return YES;
		case CMD_EDIT_REMOVE_ANY_DUP_LINES:
			MppTransformLines(v, [](std::vector<std::string> &lines) {
				std::unordered_set<std::string> seen;
				std::vector<std::string> out;
				for (auto &l : lines)
					if (seen.insert(l).second)
						out.push_back(l);
				lines.swap(out);
			});
			return YES;
		case CMD_EDIT_REMOVE_CONSECUTIVE_DUP_LINES:
			MppTransformLines(v, [](std::vector<std::string> &lines) {
				lines.erase(std::unique(lines.begin(), lines.end()), lines.end());
			});
			return YES;
		case CMD_EDIT_SPLIT_LINES: {
			[self sci:SCI_TARGETFROMSELECTION];
			sptr_t width = 0;
			if (prefs.edgeMode != MppEdgeNone)
				width = prefs.edgeColumn * [self sci:SCI_TEXTWIDTH w:STYLE_DEFAULT l:(sptr_t)"P"];
			[self sci:SCI_LINESSPLIT w:(uptr_t)width];
			return YES;
		}
		case CMD_EDIT_JOIN_LINES: {
			const sptr_t s = [self sci:SCI_GETSELECTIONSTART], e = [self sci:SCI_GETSELECTIONEND];
			const sptr_t l1 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)s];
			sptr_t l2 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)e];
			if (l1 == l2)
				l2 = std::min(l1 + 1, [self sci:SCI_GETLINECOUNT] - 1);
			[self sci:SCI_SETTARGETRANGE w:(uptr_t)[self sci:SCI_POSITIONFROMLINE w:(uptr_t)l1]
			       l:[self sci:SCI_GETLINEENDPOSITION w:(uptr_t)l2]];
			[self sci:SCI_LINESJOIN];
			return YES;
		}
		case CMD_EDIT_LINE_UP: [self sci:SCI_MOVESELECTEDLINESUP]; return YES;
		case CMD_EDIT_LINE_DOWN: [self sci:SCI_MOVESELECTEDLINESDOWN]; return YES;
		case CMD_EDIT_REMOVEEMPTYLINES:
		case CMD_EDIT_REMOVEEMPTYLINESWITHBLANK: {
			const bool blank = cmd == CMD_EDIT_REMOVEEMPTYLINESWITHBLANK;
			MppTransformLines(v, [blank](std::vector<std::string> &lines) {
				std::vector<std::string> out;
				for (auto &l : lines) {
					if (l.empty())
						continue;
					if (blank && l.find_first_not_of(" \t") == std::string::npos)
						continue;
					out.push_back(l);
				}
				lines.swap(out);
			});
			return YES;
		}
		case CMD_EDIT_BLANKLINEABOVECURRENT: {
			const sptr_t line = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]];
			const sptr_t pos = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)line];
			std::string eol = MppEOLString(v);
			[self sci:SCI_INSERTTEXT w:(uptr_t)pos l:(sptr_t)eol.c_str()];
			[self sci:SCI_GOTOPOS w:(uptr_t)pos];
			return YES;
		}
		case CMD_EDIT_BLANKLINEBELOWCURRENT: {
			const sptr_t line = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]];
			const sptr_t pos = [self sci:SCI_GETLINEENDPOSITION w:(uptr_t)line];
			std::string eol = MppEOLString(v);
			[self sci:SCI_INSERTTEXT w:(uptr_t)pos l:(sptr_t)eol.c_str()];
			[self sci:SCI_GOTOPOS w:(uptr_t)(pos + (sptr_t)eol.size())];
			return YES;
		}
		case CMD_EDIT_BLOCK_COMMENT: [self toggleLineComment:0]; return YES;
		case CMD_EDIT_BLOCK_COMMENT_SET: [self toggleLineComment:1]; return YES;
		case CMD_EDIT_BLOCK_UNCOMMENT: [self toggleLineComment:2]; return YES;
		case CMD_EDIT_STREAM_COMMENT: [self streamComment:YES]; return YES;
		case CMD_EDIT_STREAM_UNCOMMENT: [self streamComment:NO]; return YES;
		case CMD_EDIT_AUTOCOMPLETE: [MppAutoCompletion showFunctionCompletion:v lang:doc.lang]; return YES;
		case CMD_EDIT_AUTOCOMPLETE_CURRENTFILE: [MppAutoCompletion showWordCompletion:v lang:doc.lang]; return YES;
		case CMD_EDIT_FUNCCALLTIP: [MppAutoCompletion showCallTip:v lang:doc.lang]; return YES;
		case CMD_EDIT_AUTOCOMPLETE_PATH: [MppAutoCompletion showPathCompletion:v baseDir:doc.filePath.stringByDeletingLastPathComponent]; return YES;
		case CMD_FORMAT_TODOS:
		case CMD_FORMAT_TOUNIX:
		case CMD_FORMAT_TOMAC: {
			const int mode = cmd == CMD_FORMAT_TODOS ? SC_EOL_CRLF : (cmd == CMD_FORMAT_TOUNIX ? SC_EOL_LF : SC_EOL_CR);
			[self sci:SCI_CONVERTEOLS w:(uptr_t)mode];
			[self sci:SCI_SETEOLMODE w:(uptr_t)mode];
			doc.eolMode = mode;
			[doc notifyChanged];
			return YES;
		}
		case CMD_EDIT_TRIMTRAILING: case CMD_EDIT_TRIMLINEHEAD: case CMD_EDIT_TRIM_BOTH: case CMD_EDIT_EOL2WS:
		case CMD_EDIT_TRIMALL: case CMD_EDIT_TAB2SW: case CMD_EDIT_SW2TAB_ALL: case CMD_EDIT_SW2TAB_LEADING:
			[self blankOperation:cmd];
			return YES;
		case CMD_EDIT_PASTE_AS_HTML:
		case CMD_EDIT_PASTE_AS_RTF: {
			NSPasteboardType type = cmd == CMD_EDIT_PASTE_AS_HTML ? NSPasteboardTypeHTML : NSPasteboardTypeRTF;
			NSData *data = [NSPasteboard.generalPasteboard dataForType:type];
			if (!data) {
				NSBeep();
				return YES;
			}
			std::string s((const char *)data.bytes, data.length);
			[self sci:SCI_REPLACESEL w:0 l:(sptr_t)s.c_str()];
			return YES;
		}
		case CMD_EDIT_OPENSELECTEDFILE:
		case CMD_EDIT_REVEALSELECTEDFILE: {
			NSString *sel = [ns([self selectedText]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
			if (!sel.length)
				sel = ns([self currentWordOrSelection]);
			NSString *path = sel.stringByExpandingTildeInPath;
			if (!path.isAbsolutePath && doc.filePath)
				path = [doc.filePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:path];
			if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
				NSBeep();
				return YES;
			}
			if (cmd == CMD_EDIT_OPENSELECTEDFILE)
				[self openPath:path];
			else
				[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
			return YES;
		}
		case CMD_EDIT_SEARCHONINTERNET: {
			NSString *word = ns([self currentWordOrSelection]);
			if (!word.length)
				return YES;
			NSString *q = [word stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
			q = [q stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
			NSString *url = [prefs.searchEngineURL stringByReplacingOccurrencesOfString:@"$(CURRENT_WORD)" withString:q];
			if (NSURL *u = [NSURL URLWithString:url])
				[NSWorkspace.sharedWorkspace openURL:u];
			return YES;
		}
		case CMD_EDIT_CHANGESEARCHENGINE: {
			NSString *s = MppAskString(@"Search Engine", @"URL ($(CURRENT_WORD) is replaced by the selected text):", prefs.searchEngineURL);
			if (s.length)
				prefs.searchEngineURL = s;
			return YES;
		}
		case CMD_EDIT_MULTISELECTUNDO:
			if ([self sci:SCI_GETSELECTIONS] > 1)
				[self sci:SCI_DROPSELECTIONN w:(uptr_t)[self sci:SCI_GETMAINSELECTION]];
			return YES;
		case CMD_EDIT_MULTISELECTSKIP:
			if ([self sci:SCI_GETSELECTIONS] > 1) {
				[self sci:SCI_DROPSELECTIONN w:(uptr_t)[self sci:SCI_GETMAINSELECTION]];
				[self sci:SCI_TARGETWHOLEDOCUMENT];
				[self sci:SCI_MULTIPLESELECTADDNEXT];
			}
			return YES;
		case CMD_EDIT_COLUMNMODETIP: {
			NSAlert *a = [[NSAlert alloc] init];
			a.messageText = @"Column Mode";
			a.informativeText = @"There are 2 ways to switch to column-select mode:\n\n"
			                    @"1. (Keyboard and Mouse) Hold Option while left-click dragging\n\n"
			                    @"2. (Keyboard only) Hold Option+Shift while using the arrow keys";
			[a runModal];
			return YES;
		}
		case CMD_EDIT_COLUMNMODE: MppShowColumnEditor(self); return YES;
		case CMD_EDIT_CHAR_PANEL: [self toggleCharacterPanel]; return YES;
		case CMD_EDIT_CLIPBOARDHISTORY_PANEL: [self toggleClipboardHistory]; return YES;
		case CMD_EDIT_TOGGLEREADONLY:
			doc.userReadOnly = !doc.userReadOnly;
			[self documentDisplayChanged:doc];
			[doc notifyChanged];
			return YES;
		case CMD_EDIT_SETREADONLYFORALLDOCS:
		case CMD_EDIT_CLEARREADONLYFORALLDOCS:
			for (MppDocument *d in [self allDocuments]) {
				d.userReadOnly = cmd == CMD_EDIT_SETREADONLYFORALLDOCS;
				[self documentDisplayChanged:d];
				[d notifyChanged];
			}
			return YES;
		case CMD_EDIT_REDACT_SELECTION:
			MppTransformSelection(v, [](const std::string &s) {
				std::string out;
				for (size_t i = 0; i < s.size(); ++i) {
					const unsigned char c = (unsigned char)s[i];
					if ((c & 0xC0) == 0x80)
						continue;
					if (c == '\r' || c == '\n')
						out += (char)c;
					else
						out += "\xE2\x96\x88";   // █
				}
				return out;
			}, false);
			return YES;
		default:
			return NO;
	}
}

@end
