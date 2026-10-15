// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppEditing.h"
#import "MppStyler.h"
#import "MppPrefs.h"
#include "Scintilla.h"
#include "BoostRegexSearch.h"
#include <algorithm>

static inline sptr_t S(ScintillaView *v, unsigned int m, uptr_t w = 0, sptr_t l = 0)
{
	return [v message:m wParam:w lParam:l];
}

std::string MppGetRange(ScintillaView *v, sptr_t start, sptr_t end)
{
	if (end <= start)
		return std::string();
	std::vector<char> buf((size_t)(end - start) + 1);
	Sci_TextRangeFull tr;
	tr.chrg.cpMin = start;
	tr.chrg.cpMax = end;
	tr.lpstrText = buf.data();
	S(v, SCI_GETTEXTRANGEFULL, 0, (sptr_t)&tr);
	return std::string(buf.data(), (size_t)(end - start));
}

std::string MppGetLine(ScintillaView *v, sptr_t line)
{
	return MppGetRange(v, S(v, SCI_POSITIONFROMLINE, (uptr_t)line), S(v, SCI_GETLINEENDPOSITION, (uptr_t)line));
}

std::string MppEOLString(ScintillaView *v)
{
	switch (S(v, SCI_GETEOLMODE)) {
		case SC_EOL_CRLF: return "\r\n";
		case SC_EOL_CR: return "\r";
		default: return "\n";
	}
}

static bool isWordChar(ScintillaView *v, int c)
{
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c >= 0x80;
}

// ---- Smart highlighting ------------------------------------------------------------

void MppSmartHighlight(ScintillaView *v, BOOL force)
{
	const sptr_t docLen = S(v, SCI_GETLENGTH);
	S(v, SCI_SETINDICATORCURRENT, MPP_INDIC_FOUND_STYLE_SMART);
	S(v, SCI_INDICATORCLEARRANGE, 0, docLen);
	MppPrefs *p = [MppPrefs shared];
	if (!p.smartHighlighting || S(v, SCI_GETSELECTIONS) > 1 || S(v, SCI_GETSELECTIONEMPTY))
		return;
	const sptr_t selStart = S(v, SCI_GETSELECTIONSTART), selEnd = S(v, SCI_GETSELECTIONEND);
	if (selEnd - selStart > 1024)
		return;
	std::string text = MppGetRange(v, selStart, selEnd);
	if (text.find_first_of("\r\n") != std::string::npos)
		return;
	if (p.smartHighlightWholeWord) {
		// the selection must be exactly a word
		const sptr_t ws = S(v, SCI_WORDSTARTPOSITION, (uptr_t)selStart, 1);
		const sptr_t we = S(v, SCI_WORDENDPOSITION, (uptr_t)selStart, 1);
		if (ws != selStart || we != selEnd)
			return;
		for (char c : text)
			if (!isWordChar(v, (unsigned char)c))
				return;
	}
	// Visible range (plus a margin)
	const sptr_t firstVisible = S(v, SCI_GETFIRSTVISIBLELINE);
	const sptr_t linesOnScreen = S(v, SCI_LINESONSCREEN);
	const sptr_t firstLine = S(v, SCI_DOCLINEFROMVISIBLE, (uptr_t)std::max<sptr_t>(0, firstVisible - 5));
	const sptr_t lastLine = S(v, SCI_DOCLINEFROMVISIBLE, (uptr_t)(firstVisible + linesOnScreen + 5));
	sptr_t start = S(v, SCI_POSITIONFROMLINE, (uptr_t)firstLine);
	const sptr_t end = S(v, SCI_GETLINEENDPOSITION, (uptr_t)lastLine);

	int flags = 0;
	if (p.smartHighlightMatchCase)
		flags |= SCFIND_MATCHCASE;
	if (p.smartHighlightWholeWord)
		flags |= SCFIND_WHOLEWORD;
	const sptr_t oldTargetStart = S(v, SCI_GETTARGETSTART), oldTargetEnd = S(v, SCI_GETTARGETEND);
	S(v, SCI_SETSEARCHFLAGS, (uptr_t)flags);
	int count = 0;
	while (start < end && count < 5000) {
		S(v, SCI_SETTARGETRANGE, (uptr_t)start, end);
		const sptr_t pos = S(v, SCI_SEARCHINTARGET, text.size(), (sptr_t)text.c_str());
		if (pos < 0)
			break;
		const sptr_t te = S(v, SCI_GETTARGETEND);
		if (pos != selStart)
			S(v, SCI_INDICATORFILLRANGE, (uptr_t)pos, te - pos);
		start = std::max(te, pos + 1);
		++count;
	}
	S(v, SCI_SETTARGETRANGE, (uptr_t)oldTargetStart, oldTargetEnd);
}

// ---- Brace matching ------------------------------------------------------------------

void MppBraceMatch(ScintillaView *v)
{
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	sptr_t braceAt = -1;
	auto isBrace = [](int c) { return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}'; };
	if (caret > 0 && isBrace((int)S(v, SCI_GETCHARAT, (uptr_t)caret - 1)))
		braceAt = caret - 1;
	else if (isBrace((int)S(v, SCI_GETCHARAT, (uptr_t)caret)))
		braceAt = caret;
	if (braceAt < 0) {
		S(v, SCI_BRACEHIGHLIGHT, (uptr_t)-1, -1);
		S(v, SCI_SETHIGHLIGHTGUIDE, 0);
		return;
	}
	const sptr_t match = S(v, SCI_BRACEMATCH, (uptr_t)braceAt, 0);
	if (match < 0) {
		S(v, SCI_BRACEBADLIGHT, (uptr_t)braceAt);
		S(v, SCI_SETHIGHLIGHTGUIDE, 0);
	} else {
		S(v, SCI_BRACEHIGHLIGHT, (uptr_t)braceAt, match);
		if ([MppPrefs shared].showIndentGuides) {
			const sptr_t col1 = S(v, SCI_GETCOLUMN, (uptr_t)braceAt), col2 = S(v, SCI_GETCOLUMN, (uptr_t)match);
			S(v, SCI_SETHIGHLIGHTGUIDE, (uptr_t)std::min(col1, col2));
		}
	}
}

// ---- XML / HTML tag matching -----------------------------------------------------------

namespace {
struct TagInfo {
	bool valid = false, isClose = false, selfClosing = false;
	sptr_t tagStart = 0, tagEnd = 0, nameStart = 0, nameEnd = 0;
	std::string name;
};

bool isTagNameChar(int c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == ':' || c == '.' || c == '-' || c >= 0x80;
}

TagInfo parseTagAt(ScintillaView *v, sptr_t lt)
{
	TagInfo t;
	const sptr_t len = S(v, SCI_GETLENGTH);
	if (S(v, SCI_GETCHARAT, (uptr_t)lt) != '<')
		return t;
	sptr_t p = lt + 1;
	if (S(v, SCI_GETCHARAT, (uptr_t)p) == '/') {
		t.isClose = true;
		++p;
	}
	t.nameStart = p;
	while (p < len && isTagNameChar((unsigned char)S(v, SCI_GETCHARAT, (uptr_t)p)))
		++p;
	t.nameEnd = p;
	if (t.nameEnd == t.nameStart)
		return t;
	// find end of tag, respecting quotes
	char quote = 0;
	while (p < len) {
		const char c = (char)S(v, SCI_GETCHARAT, (uptr_t)p);
		if (quote) {
			if (c == quote)
				quote = 0;
		} else if (c == '"' || c == '\'') {
			quote = c;
		} else if (c == '<') {
			return t;
		} else if (c == '>') {
			break;
		}
		++p;
	}
	if (p >= len)
		return t;
	t.tagStart = lt;
	t.tagEnd = p + 1;
	t.selfClosing = S(v, SCI_GETCHARAT, (uptr_t)p - 1) == '/';
	t.name = MppGetRange(v, t.nameStart, t.nameEnd);
	t.valid = true;
	return t;
}

TagInfo tagAroundCaret(ScintillaView *v, sptr_t caret)
{
	// Walk backwards to the nearest '<' without crossing a '>'
	sptr_t p = caret;
	const sptr_t limit = std::max<sptr_t>(0, caret - 4096);
	while (p > limit) {
		const char c = (char)S(v, SCI_GETCHARAT, (uptr_t)p - 1);
		if (c == '>' && p != caret)
			break;
		if (c == '<') {
			TagInfo t = parseTagAt(v, p - 1);
			if (t.valid && caret >= t.tagStart && caret <= t.tagEnd)
				return t;
			break;
		}
		--p;
	}
	return TagInfo();
}
} // namespace

void MppXmlTagMatch(ScintillaView *v, MppLangType lang)
{
	const sptr_t docLen = S(v, SCI_GETLENGTH);
	S(v, SCI_SETINDICATORCURRENT, MPP_INDIC_TAGMATCH);
	S(v, SCI_INDICATORCLEARRANGE, 0, docLen);
	if (![MppPrefs shared].matchTagHighlighting)
		return;
	if (!(lang == L_XML || lang == L_HTML || lang == L_PHP || lang == L_ASP || lang == L_JSP))
		return;
	if (docLen > 20 * 1024 * 1024)
		return;
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	TagInfo t = tagAroundCaret(v, caret);
	if (!t.valid || t.selfClosing)
		return;

	const sptr_t oldTS = S(v, SCI_GETTARGETSTART), oldTE = S(v, SCI_GETTARGETEND);
	std::string pattern = "</?" + t.name + "(?=[\\s/>])";
	S(v, SCI_SETSEARCHFLAGS, SCFIND_REGEXP | SCFIND_MATCHCASE);
	int depth = 0;
	TagInfo match;
	if (!t.isClose) {
		sptr_t pos = t.tagEnd;
		while (pos < docLen) {
			S(v, SCI_SETTARGETRANGE, (uptr_t)pos, docLen);
			const sptr_t f = S(v, SCI_SEARCHINTARGET, pattern.size(), (sptr_t)pattern.c_str());
			if (f < 0)
				break;
			TagInfo o = parseTagAt(v, f);
			pos = S(v, SCI_GETTARGETEND);
			if (!o.valid || o.name != t.name || o.selfClosing)
				continue;
			if (o.isClose) {
				if (depth == 0) {
					match = o;
					break;
				}
				--depth;
			} else {
				++depth;
			}
		}
	} else {
		sptr_t pos = t.tagStart;
		while (pos > 0) {
			S(v, SCI_SETTARGETRANGE, (uptr_t)pos, 0);
			const sptr_t f = S(v, SCI_SEARCHINTARGET, pattern.size(), (sptr_t)pattern.c_str());
			if (f < 0)
				break;
			TagInfo o = parseTagAt(v, f);
			pos = f;
			if (!o.valid || o.name != t.name || o.selfClosing)
				continue;
			if (!o.isClose) {
				if (depth == 0) {
					match = o;
					break;
				}
				--depth;
			} else {
				++depth;
			}
		}
	}
	S(v, SCI_SETTARGETRANGE, (uptr_t)oldTS, oldTE);
	if (!match.valid)
		return;
	S(v, SCI_INDICATORFILLRANGE, (uptr_t)t.nameStart, t.nameEnd - t.nameStart);
	S(v, SCI_INDICATORFILLRANGE, (uptr_t)match.nameStart, match.nameEnd - match.nameStart);
}

// ---- Clickable links -----------------------------------------------------------------

void MppHighlightURLs(ScintillaView *v)
{
	S(v, SCI_INDICSETSTYLE, MPP_URL_INDIC, INDIC_PLAIN);
	S(v, SCI_INDICSETHOVERSTYLE, MPP_URL_INDIC, INDIC_TEXTFORE);
	S(v, SCI_INDICSETFORE, MPP_URL_INDIC, 0x808080);
	S(v, SCI_INDICSETHOVERFORE, MPP_URL_INDIC, 0xFF0000);

	const sptr_t firstVisible = S(v, SCI_GETFIRSTVISIBLELINE);
	const sptr_t linesOnScreen = S(v, SCI_LINESONSCREEN);
	const sptr_t firstLine = S(v, SCI_DOCLINEFROMVISIBLE, (uptr_t)firstVisible);
	const sptr_t lastLine = S(v, SCI_DOCLINEFROMVISIBLE, (uptr_t)(firstVisible + linesOnScreen + 1));
	sptr_t start = S(v, SCI_POSITIONFROMLINE, (uptr_t)firstLine);
	const sptr_t end = S(v, SCI_GETLINEENDPOSITION, (uptr_t)lastLine);
	S(v, SCI_SETINDICATORCURRENT, MPP_URL_INDIC);
	S(v, SCI_INDICATORCLEARRANGE, (uptr_t)start, end - start);
	if (end - start > 200000)
		return;
	static const char *re = "\\b(?:https?|ftp|file|mailto):(?://)?[^\\s\"'<>\\x00-\\x1F]+[^\\s\"'<>.,;:!?)\\]}\\x00-\\x1F]";
	const sptr_t oldTS = S(v, SCI_GETTARGETSTART), oldTE = S(v, SCI_GETTARGETEND);
	S(v, SCI_SETSEARCHFLAGS, SCFIND_REGEXP);
	int n = 0;
	while (start < end && n++ < 500) {
		S(v, SCI_SETTARGETRANGE, (uptr_t)start, end);
		const sptr_t f = S(v, SCI_SEARCHINTARGET, strlen(re), (sptr_t)re);
		if (f < 0)
			break;
		const sptr_t te = S(v, SCI_GETTARGETEND);
		S(v, SCI_INDICATORFILLRANGE, (uptr_t)f, te - f);
		start = std::max(te, f + 1);
	}
	S(v, SCI_SETTARGETRANGE, (uptr_t)oldTS, oldTE);
}

void MppHandleIndicatorClick(ScintillaView *v, SCNotification *n)
{
	if (!(n->modifiers & (SCMOD_CTRL | SCMOD_META)))
		return;
	const sptr_t pos = n->position;
	if (!S(v, SCI_INDICATORVALUEAT, MPP_URL_INDIC, pos))
		return;
	const sptr_t s = S(v, SCI_INDICATORSTART, MPP_URL_INDIC, pos);
	const sptr_t e = S(v, SCI_INDICATOREND, MPP_URL_INDIC, pos);
	std::string url = MppGetRange(v, s, e);
	NSURL *u = [NSURL URLWithString:@(url.c_str())];
	if (u)
		[NSWorkspace.sharedWorkspace openURL:u];
}

// ---- Auto-indentation (MaintainIndentation, "advanced" mode) ---------------------------

static bool isCLikeLang(MppLangType l)
{
	switch (l) {
		case L_C: case L_CPP: case L_CS: case L_JAVA: case L_OBJC: case L_JAVASCRIPT: case L_JS_EMBEDDED:
		case L_TYPESCRIPT: case L_PHP: case L_CSS: case L_RUST: case L_GOLANG: case L_SWIFT: case L_D:
		case L_FLASH: case L_JSON: case L_JSON5: case L_PERL: case L_POWERSHELL: case L_COFFEESCRIPT:
		case L_RC: case L_TCL: case L_AU3: case L_ASP: case L_JSP: case L_R:
			return true;
		default:
			return false;
	}
}

void MppMaintainIndentation(ScintillaView *v, int ch, MppLangType lang)
{
	if (![MppPrefs shared].autoIndent)
		return;
	const int eolMode = (int)S(v, SCI_GETEOLMODE);
	if (!((eolMode == SC_EOL_CRLF || eolMode == SC_EOL_LF) && ch == '\n') && !(eolMode == SC_EOL_CR && ch == '\r'))
		return;
	const sptr_t curLine = S(v, SCI_LINEFROMPOSITION, (uptr_t)S(v, SCI_GETCURRENTPOS));
	if (curLine == 0)
		return;
	// previous non-blank line
	sptr_t prevLine = curLine - 1;
	while (prevLine > 0 && S(v, SCI_GETLINEINDENTPOSITION, (uptr_t)prevLine) == S(v, SCI_GETLINEENDPOSITION, (uptr_t)prevLine))
		--prevLine;
	sptr_t indent = S(v, SCI_GETLINEINDENTATION, (uptr_t)prevLine);
	const sptr_t indentUnit = S(v, SCI_GETINDENT) ? S(v, SCI_GETINDENT) : S(v, SCI_GETTABWIDTH);

	std::string prev = MppGetLine(v, prevLine);
	while (!prev.empty() && (prev.back() == ' ' || prev.back() == '\t'))
		prev.pop_back();
	const char last = prev.empty() ? 0 : prev.back();
	std::string cur = MppGetLine(v, curLine);
	const size_t firstNonBlank = cur.find_first_not_of(" \t");
	const char curFirst = firstNonBlank == std::string::npos ? 0 : cur[firstNonBlank];

	if (isCLikeLang(lang)) {
		if (last == '{' || last == '[' || last == '(') {
			indent += indentUnit;
			if ((last == '{' && curFirst == '}') || (last == '[' && curFirst == ']') || (last == '(' && curFirst == ')')) {
				// caret between braces: put the closing brace on its own line
				const sptr_t pos = S(v, SCI_GETCURRENTPOS);
				std::string eol = MppEOLString(v);
				S(v, SCI_INSERTTEXT, (uptr_t)pos, (sptr_t)eol.c_str());
				S(v, SCI_SETLINEINDENTATION, (uptr_t)curLine + 1, indent - indentUnit);
			}
		}
	} else if (lang == L_PYTHON || lang == L_NIM || lang == L_GDSCRIPT) {
		if (last == ':')
			indent += indentUnit;
	}
	S(v, SCI_SETLINEINDENTATION, (uptr_t)curLine, indent);
	const sptr_t indentPos = S(v, SCI_GETLINEINDENTPOSITION, (uptr_t)curLine);
	S(v, SCI_GOTOPOS, (uptr_t)indentPos);
}

// ---- Auto-close brackets/quotes and HTML/XML tags -------------------------------------

void MppAutoCloseChar(ScintillaView *v, int ch, MppLangType lang)
{
	MppPrefs *p = [MppPrefs shared];
	if (S(v, SCI_GETSELECTIONS) > 1)
		return;
	const sptr_t pos = S(v, SCI_GETCURRENTPOS);
	const int next = (int)S(v, SCI_GETCHARAT, (uptr_t)pos);
	const int prev2 = pos >= 2 ? (int)S(v, SCI_GETCHARAT, (uptr_t)pos - 2) : 0;

	// Typing a closing char right before the same auto-inserted char: just skip over it
	auto skipIfSame = [&](int c) -> bool {
		if (next == c) {
			S(v, SCI_DELETERANGE, (uptr_t)pos, 1);
			return true;
		}
		return false;
	};

	const char *close = nullptr;
	switch (ch) {
		case '(': if (p.autoCloseParen) close = ")"; break;
		case '[': if (p.autoCloseBracket) close = "]"; break;
		case '{': if (p.autoCloseCurly) close = "}"; break;
		case '"':
			if (p.autoCloseDoubleQuote) {
				if (skipIfSame('"'))
					return;
				if (!isWordChar(v, prev2) && !isWordChar(v, next))
					close = "\"";
			}
			break;
		case '\'':
			if (p.autoCloseQuote) {
				if (skipIfSame('\''))
					return;
				if (!isWordChar(v, prev2) && !isWordChar(v, next))
					close = "'";
			}
			break;
		case ')': if (p.autoCloseParen) skipIfSame(')'); return;
		case ']': if (p.autoCloseBracket) skipIfSame(']'); return;
		case '}': if (p.autoCloseCurly) skipIfSame('}'); return;
		case '>':
			if (p.autoCloseHtmlXmlTag && (lang == L_XML || lang == L_HTML || lang == L_PHP || lang == L_ASP || lang == L_JSP)) {
				// find the opening '<' of this tag
				sptr_t q = pos - 2;
				const sptr_t limit = std::max<sptr_t>(0, pos - 2048);
				while (q >= limit) {
					const int c = (int)S(v, SCI_GETCHARAT, (uptr_t)q);
					if (c == '<' || c == '>')
						break;
					--q;
				}
				if (q < limit || S(v, SCI_GETCHARAT, (uptr_t)q) != '<')
					return;
				if (S(v, SCI_GETCHARAT, (uptr_t)pos - 2) == '/')
					return;   // self-closing
				const int c1 = (int)S(v, SCI_GETCHARAT, (uptr_t)q + 1);
				if (c1 == '/' || c1 == '!' || c1 == '?' || c1 == '%')
					return;
				sptr_t e = q + 1;
				while (e < pos && isTagNameChar((unsigned char)S(v, SCI_GETCHARAT, (uptr_t)e)))
					++e;
				std::string name = MppGetRange(v, q + 1, e);
				if (name.empty())
					return;
				static const char *voidTags[] = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
				                                 "meta", "param", "source", "track", "wbr", nullptr};
				if (lang != L_XML) {
					std::string lower = name;
					std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
					for (const char **t = voidTags; *t; ++t)
						if (lower == *t)
							return;
				}
				std::string closing = "</" + name + ">";
				S(v, SCI_INSERTTEXT, (uptr_t)pos, (sptr_t)closing.c_str());
			}
			return;
		default:
			return;
	}
	if (close)
		S(v, SCI_INSERTTEXT, (uptr_t)pos, (sptr_t)close);
}

// ---- Bookmarks / trimming ---------------------------------------------------------------

void MppToggleBookmark(ScintillaView *v, sptr_t line)
{
	if (S(v, SCI_MARKERGET, (uptr_t)line) & (1 << MPP_MARK_BOOKMARK))
		S(v, SCI_MARKERDELETE, (uptr_t)line, MPP_MARK_BOOKMARK);
	else
		S(v, SCI_MARKERADD, (uptr_t)line, MPP_MARK_BOOKMARK);
}

void MppTrimTrailing(ScintillaView *v)
{
	const sptr_t lines = S(v, SCI_GETLINECOUNT);
	S(v, SCI_BEGINUNDOACTION);
	for (sptr_t l = 0; l < lines; ++l) {
		const sptr_t s = S(v, SCI_POSITIONFROMLINE, (uptr_t)l);
		const sptr_t e = S(v, SCI_GETLINEENDPOSITION, (uptr_t)l);
		sptr_t p = e;
		while (p > s) {
			const int c = (int)S(v, SCI_GETCHARAT, (uptr_t)p - 1);
			if (c != ' ' && c != '\t')
				break;
			--p;
		}
		if (p < e)
			S(v, SCI_DELETERANGE, (uptr_t)p, e - p);
	}
	S(v, SCI_ENDUNDOACTION);
}

// ---- Generic transformations ------------------------------------------------------------

void MppTransformLines(ScintillaView *v, const std::function<void(std::vector<std::string> &)> &fn, bool wholeDocIfNoSel)
{
	sptr_t selStart = S(v, SCI_GETSELECTIONSTART), selEnd = S(v, SCI_GETSELECTIONEND);
	sptr_t l1 = S(v, SCI_LINEFROMPOSITION, (uptr_t)selStart);
	sptr_t l2 = S(v, SCI_LINEFROMPOSITION, (uptr_t)selEnd);
	if (l2 > l1 && selEnd == S(v, SCI_POSITIONFROMLINE, (uptr_t)l2))
		--l2;   // selection ending at column 0 doesn't include that line
	if (l1 == l2 && wholeDocIfNoSel) {
		l1 = 0;
		l2 = S(v, SCI_GETLINECOUNT) - 1;
	}
	std::vector<std::string> lines;
	for (sptr_t l = l1; l <= l2; ++l)
		lines.push_back(MppGetLine(v, l));
	// keep a trailing empty last line out of the operation (document ending with EOL)
	bool trailingEmpty = false;
	if (l2 == S(v, SCI_GETLINECOUNT) - 1 && lines.size() > 1 && lines.back().empty()) {
		lines.pop_back();
		trailingEmpty = true;
	}
	std::vector<std::string> before = lines;
	fn(lines);
	if (lines == before)
		return;
	const std::string eol = MppEOLString(v);
	std::string out;
	for (size_t i = 0; i < lines.size(); ++i) {
		if (i)
			out += eol;
		out += lines[i];
	}
	if (trailingEmpty && !lines.empty())
		out += eol;
	const sptr_t start = S(v, SCI_POSITIONFROMLINE, (uptr_t)l1);
	const sptr_t end = S(v, SCI_GETLINEENDPOSITION, (uptr_t)l2);
	S(v, SCI_BEGINUNDOACTION);
	S(v, SCI_SETTARGETRANGE, (uptr_t)start, end);
	S(v, SCI_REPLACETARGET, out.size(), (sptr_t)out.c_str());
	S(v, SCI_ENDUNDOACTION);
	S(v, SCI_SETSEL, (uptr_t)start, start + (sptr_t)out.size());
}

void MppTransformSelection(ScintillaView *v, const std::function<std::string(const std::string &)> &fn, bool wholeDocIfEmpty)
{
	const sptr_t n = S(v, SCI_GETSELECTIONS);
	S(v, SCI_BEGINUNDOACTION);
	if (n == 1 && S(v, SCI_GETSELECTIONEMPTY)) {
		if (wholeDocIfEmpty) {
			const sptr_t len = S(v, SCI_GETLENGTH);
			std::string t = fn(MppGetRange(v, 0, len));
			S(v, SCI_TARGETWHOLEDOCUMENT);
			S(v, SCI_REPLACETARGET, t.size(), (sptr_t)t.c_str());
		}
		S(v, SCI_ENDUNDOACTION);
		return;
	}
	std::vector<std::pair<sptr_t, sptr_t>> ranges;
	for (sptr_t i = 0; i < n; ++i)
		ranges.emplace_back(S(v, SCI_GETSELECTIONNSTART, (uptr_t)i), S(v, SCI_GETSELECTIONNEND, (uptr_t)i));
	std::sort(ranges.begin(), ranges.end());
	sptr_t delta = 0;
	std::vector<std::pair<sptr_t, sptr_t>> newRanges;
	for (auto &r : ranges) {
		const sptr_t s = r.first + delta, e = r.second + delta;
		std::string t = fn(MppGetRange(v, s, e));
		S(v, SCI_SETTARGETRANGE, (uptr_t)s, e);
		S(v, SCI_REPLACETARGET, t.size(), (sptr_t)t.c_str());
		newRanges.emplace_back(s, s + (sptr_t)t.size());
		delta += (sptr_t)t.size() - (e - s);
	}
	S(v, SCI_ENDUNDOACTION);
	if (newRanges.size() == 1) {
		S(v, SCI_SETSEL, (uptr_t)newRanges[0].first, newRanges[0].second);
	} else {
		S(v, SCI_SETSELECTION, (uptr_t)newRanges[0].second, newRanges[0].first);
		for (size_t i = 1; i < newRanges.size(); ++i)
			S(v, SCI_ADDSELECTION, (uptr_t)newRanges[i].second, newRanges[i].first);
	}
}
