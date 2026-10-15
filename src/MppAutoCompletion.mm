// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppAutoCompletion.h"
#import "MppPrefs.h"
#import "MppPaths.h"
#import "MppEditing.h"
#include "Scintilla.h"
#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace {

struct Overload {
	std::string retVal, descr;
	std::vector<std::string> params;
};

struct ApiKeyword {
	std::string name;
	bool func = false;
	std::vector<Overload> overloads;
};

struct ApiData {
	bool loaded = false;
	bool ignoreCase = false;
	char startFunc = '(', stopFunc = ')', paramSep = ',', terminal = 0;
	std::string additionalWordChars;
	std::vector<ApiKeyword> keywords;   // sorted by name
};

std::map<int, ApiData> g_api;

NSString *apiFileName(MppLangType lang)
{
	switch (lang) {
		case L_JAVASCRIPT: case L_JS_EMBEDDED: return @"javascript";
		case L_COFFEESCRIPT: return @"coffee";
		case L_BAANC: return @"BaanC";
		default: return @(g_mppLangNameInfo[lang].langName);
	}
}

const ApiData &apiFor(MppLangType lang)
{
	ApiData &d = g_api[lang];
	if (d.loaded)
		return d;
	d.loaded = true;
	NSString *file = [apiFileName(lang) stringByAppendingPathExtension:@"xml"];
	NSString *path = [[MppPaths.userDataDirectory stringByAppendingPathComponent:@"APIs"] stringByAppendingPathComponent:file];
	if (![NSFileManager.defaultManager fileExistsAtPath:path])
		path = [[MppPaths.resourceDirectory stringByAppendingPathComponent:@"APIs"] stringByAppendingPathComponent:file];
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data)
		return d;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
	NSXMLElement *env = [[doc nodesForXPath:@"/*/AutoComplete/Environment" error:nil] firstObject];
	if (env) {
		d.ignoreCase = [[[env attributeForName:@"ignoreCase"] stringValue] isEqualToString:@"yes"];
		NSString *s;
		if ((s = [[env attributeForName:@"startFunc"] stringValue]).length) d.startFunc = (char)[s characterAtIndex:0];
		if ((s = [[env attributeForName:@"stopFunc"] stringValue]).length) d.stopFunc = (char)[s characterAtIndex:0];
		if ((s = [[env attributeForName:@"paramSeparator"] stringValue]).length) d.paramSep = (char)[s characterAtIndex:0];
		if ((s = [[env attributeForName:@"terminal"] stringValue]).length) d.terminal = (char)[s characterAtIndex:0];
		if ((s = [[env attributeForName:@"additionalWordChar"] stringValue]).length) d.additionalWordChars = s.UTF8String;
	}
	for (NSXMLElement *kw in [doc nodesForXPath:@"/*/AutoComplete/KeyWord" error:nil]) {
		ApiKeyword k;
		NSString *name = [[kw attributeForName:@"name"] stringValue];
		if (!name.length)
			continue;
		k.name = name.UTF8String;
		k.func = [[[kw attributeForName:@"func"] stringValue] isEqualToString:@"yes"];
		for (NSXMLElement *ov in [kw elementsForName:@"Overload"]) {
			Overload o;
			o.retVal = [[[ov attributeForName:@"retVal"] stringValue] UTF8String] ?: "";
			o.descr = [[[ov attributeForName:@"descr"] stringValue] UTF8String] ?: "";
			for (NSXMLElement *p in [ov elementsForName:@"Param"])
				o.params.push_back([[[p attributeForName:@"name"] stringValue] UTF8String] ?: "");
			k.overloads.push_back(o);
		}
		d.keywords.push_back(k);
	}
	std::sort(d.keywords.begin(), d.keywords.end(), [](const ApiKeyword &a, const ApiKeyword &b) { return a.name < b.name; });
	return d;
}

inline sptr_t S(ScintillaView *v, unsigned int m, uptr_t w = 0, sptr_t l = 0)
{
	return [v message:m wParam:w lParam:l];
}

bool isWordChar(int c, const std::string &extra)
{
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c >= 0x80 ||
	       (c && extra.find((char)c) != std::string::npos);
}

sptr_t wordStartBefore(ScintillaView *v, sptr_t pos, const std::string &extra)
{
	sptr_t p = pos;
	while (p > 0 && isWordChar((unsigned char)S(v, SCI_GETCHARAT, (uptr_t)p - 1), extra))
		--p;
	return p;
}

bool startsWith(const std::string &s, const std::string &prefix, bool ignoreCase)
{
	if (s.size() < prefix.size())
		return false;
	if (!ignoreCase)
		return s.compare(0, prefix.size(), prefix) == 0;
	return strncasecmp(s.c_str(), prefix.c_str(), prefix.size()) == 0;
}

std::vector<std::string> documentWords(ScintillaView *v, const std::string &prefix, sptr_t excludeStart, const std::string &extra)
{
	std::set<std::string> words;
	const sptr_t len = S(v, SCI_GETLENGTH);
	if (len > 50 * 1024 * 1024)
		return {};
	const char *text = (const char *)S(v, SCI_GETCHARACTERPOINTER);
	if (!text)
		return {};
	sptr_t i = 0;
	while (i < len) {
		while (i < len && !isWordChar((unsigned char)text[i], extra))
			++i;
		const sptr_t s = i;
		while (i < len && isWordChar((unsigned char)text[i], extra))
			++i;
		if (i > s && s != excludeStart && (sptr_t)prefix.size() < i - s) {
			std::string w(text + s, (size_t)(i - s));
			if (startsWith(w, prefix, false))
				words.insert(w);
		}
		if (words.size() > 2000)
			break;
	}
	return std::vector<std::string>(words.begin(), words.end());
}

void showList(ScintillaView *v, sptr_t prefixLen, std::vector<std::string> items, bool ignoreCase)
{
	if (items.empty()) {
		S(v, SCI_AUTOCCANCEL);
		return;
	}
	std::sort(items.begin(), items.end(), [ignoreCase](const std::string &a, const std::string &b) {
		return ignoreCase ? strcasecmp(a.c_str(), b.c_str()) < 0 : a < b;
	});
	items.erase(std::unique(items.begin(), items.end()), items.end());
	std::string list;
	for (const auto &i : items) {
		if (!list.empty())
			list += '\n';
		list += i;
	}
	S(v, SCI_AUTOCSETSEPARATOR, '\n');
	S(v, SCI_AUTOCSETIGNORECASE, ignoreCase);
	S(v, SCI_AUTOCSETCASEINSENSITIVEBEHAVIOUR, SC_CASEINSENSITIVEBEHAVIOUR_IGNORECASE);
	S(v, SCI_AUTOCSETORDER, SC_ORDER_PRESORTED);
	S(v, SCI_AUTOCSETAUTOHIDE, 1);
	S(v, SCI_AUTOCSETDROPRESTOFWORD, 0);
	S(v, SCI_AUTOCSETMAXHEIGHT, 10);
	S(v, SCI_AUTOCSHOW, (uptr_t)prefixLen, (sptr_t)list.c_str());
}

// Call tip state
struct CallTipState {
	__weak ScintillaView *view = nil;
	MppLangType lang = L_TEXT;
	std::string func;
	size_t overload = 0;
	sptr_t startPos = -1;
	int param = 0;
};
CallTipState g_tip;

const ApiKeyword *findKeyword(const ApiData &d, const std::string &name)
{
	for (const auto &k : d.keywords)
		if (d.ignoreCase ? strcasecmp(k.name.c_str(), name.c_str()) == 0 : k.name == name)
			return &k;
	return nullptr;
}

void displayTip(ScintillaView *v)
{
	const ApiData &d = apiFor(g_tip.lang);
	const ApiKeyword *k = findKeyword(d, g_tip.func);
	if (!k || k->overloads.empty()) {
		S(v, SCI_CALLTIPCANCEL);
		return;
	}
	if (g_tip.overload >= k->overloads.size())
		g_tip.overload = 0;
	const Overload &o = k->overloads[g_tip.overload];
	std::string tip;
	if (k->overloads.size() > 1) {
		char buf[64];
		snprintf(buf, sizeof buf, "\001%zu of %zu\002", g_tip.overload + 1, k->overloads.size());
		tip += buf;
	}
	if (!o.retVal.empty())
		tip += o.retVal + " ";
	tip += k->name;
	tip += d.startFunc;
	sptr_t hlStart = -1, hlEnd = -1;
	for (size_t i = 0; i < o.params.size(); ++i) {
		if (i) {
			tip += d.paramSep;
			tip += ' ';
		}
		if ((int)i == g_tip.param)
			hlStart = (sptr_t)tip.size();
		tip += o.params[i];
		if ((int)i == g_tip.param)
			hlEnd = (sptr_t)tip.size();
	}
	tip += d.stopFunc;
	if (!o.descr.empty())
		tip += "\n" + o.descr;
	S(v, SCI_CALLTIPSHOW, (uptr_t)g_tip.startPos, (sptr_t)tip.c_str());
	if (hlStart >= 0)
		S(v, SCI_CALLTIPSETHLT, (uptr_t)hlStart, hlEnd);
}

// Find the function name and the current parameter index for the caret position
bool locateFunction(ScintillaView *v, const ApiData &d, std::string &func, sptr_t &namePos, int &param)
{
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	sptr_t p = caret;
	int depth = 0;
	param = 0;
	const sptr_t limit = std::max<sptr_t>(0, caret - 2000);
	while (p > limit) {
		const char c = (char)S(v, SCI_GETCHARAT, (uptr_t)p - 1);
		if (c == d.stopFunc) {
			++depth;
		} else if (c == d.startFunc) {
			if (depth == 0)
				break;
			--depth;
		} else if (c == d.paramSep && depth == 0) {
			++param;
		} else if (d.terminal && c == d.terminal) {
			return false;
		}
		--p;
	}
	if (p <= limit)
		return false;
	sptr_t nameEnd = p - 1;
	while (nameEnd > 0 && (S(v, SCI_GETCHARAT, (uptr_t)nameEnd - 1) == ' ' || S(v, SCI_GETCHARAT, (uptr_t)nameEnd - 1) == '\t'))
		--nameEnd;
	const sptr_t nameStart = wordStartBefore(v, nameEnd, d.additionalWordChars);
	if (nameStart == nameEnd)
		return false;
	func = MppGetRange(v, nameStart, nameEnd);
	namePos = nameStart;
	return true;
}

} // namespace

@implementation MppAutoCompletion

+ (void)showFunctionCompletion:(ScintillaView *)v lang:(MppLangType)lang
{
	const ApiData &d = apiFor(lang);
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	const sptr_t start = wordStartBefore(v, caret, d.additionalWordChars);
	std::string prefix = MppGetRange(v, start, caret);
	std::vector<std::string> items;
	for (const auto &k : d.keywords)
		if (startsWith(k.name, prefix, d.ignoreCase))
			items.push_back(k.name);
	showList(v, caret - start, items, d.ignoreCase);
}

+ (void)showWordCompletion:(ScintillaView *)v lang:(MppLangType)lang
{
	const ApiData &d = apiFor(lang);
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	const sptr_t start = wordStartBefore(v, caret, d.additionalWordChars);
	std::string prefix = MppGetRange(v, start, caret);
	showList(v, caret - start, documentWords(v, prefix, start, d.additionalWordChars), false);
}

+ (void)showCallTip:(ScintillaView *)v lang:(MppLangType)lang
{
	const ApiData &d = apiFor(lang);
	std::string func;
	sptr_t namePos;
	int param;
	if (!locateFunction(v, d, func, namePos, param)) {
		S(v, SCI_CALLTIPCANCEL);
		return;
	}
	if (!(g_tip.view == v && g_tip.func == func && g_tip.startPos == namePos))
		g_tip.overload = 0;
	g_tip.view = v;
	g_tip.lang = lang;
	g_tip.func = func;
	g_tip.startPos = namePos;
	g_tip.param = param;
	displayTip(v);
}

+ (void)callTipClicked:(ScintillaView *)v arrow:(int)position
{
	if (g_tip.view != v)
		return;
	const ApiData &d = apiFor(g_tip.lang);
	const ApiKeyword *k = findKeyword(d, g_tip.func);
	if (!k || k->overloads.size() < 2)
		return;
	if (position == 1)
		g_tip.overload = (g_tip.overload + k->overloads.size() - 1) % k->overloads.size();
	else if (position == 2)
		g_tip.overload = (g_tip.overload + 1) % k->overloads.size();
	displayTip(v);
}

+ (void)showPathCompletion:(ScintillaView *)v baseDir:(NSString *)baseDir
{
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	const sptr_t line = S(v, SCI_LINEFROMPOSITION, (uptr_t)caret);
	const sptr_t lineStart = S(v, SCI_POSITIONFROMLINE, (uptr_t)line);
	std::string before = MppGetRange(v, lineStart, caret);
	size_t b = before.find_last_of(" \t\"'<>|=(");
	std::string raw = b == std::string::npos ? before : before.substr(b + 1);
	NSString *typed = [[NSString alloc] initWithBytes:raw.data() length:raw.size() encoding:NSUTF8StringEncoding] ?: @"";
	NSString *expanded = typed.stringByExpandingTildeInPath;
	if (!expanded.isAbsolutePath)
		expanded = [(baseDir.length ? baseDir : NSHomeDirectory()) stringByAppendingPathComponent:expanded];
	NSString *dir, *prefix;
	if ([typed hasSuffix:@"/"] || typed.length == 0) {
		dir = expanded;
		prefix = @"";
	} else {
		dir = expanded.stringByDeletingLastPathComponent;
		prefix = expanded.lastPathComponent;
	}
	std::vector<std::string> items;
	for (NSString *f in [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]) {
		if (prefix.length && ![f.lowercaseString hasPrefix:prefix.lowercaseString])
			continue;
		BOOL isDir = NO;
		[NSFileManager.defaultManager fileExistsAtPath:[dir stringByAppendingPathComponent:f] isDirectory:&isDir];
		NSString *entry = isDir ? [f stringByAppendingString:@"/"] : f;
		items.push_back(entry.UTF8String);
	}
	showList(v, (sptr_t)[prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding], items, true);
}

+ (void)charAdded:(int)ch view:(ScintillaView *)v lang:(MppLangType)lang
{
	MppPrefs *p = [MppPrefs shared];
	const ApiData &d = apiFor(lang);

	if (p.funcParamsHint) {
		if (ch == d.startFunc || (ch == d.paramSep && S(v, SCI_CALLTIPACTIVE))) {
			[self showCallTip:v lang:lang];
		} else if (ch == d.stopFunc && S(v, SCI_CALLTIPACTIVE)) {
			std::string func;
			sptr_t namePos;
			int param;
			if (locateFunction(v, d, func, namePos, param))
				[self showCallTip:v lang:lang];
			else
				S(v, SCI_CALLTIPCANCEL);
		}
	}

	if (p.autoCompleteMode == MppAutoCompleteOff || !isWordChar(ch, d.additionalWordChars))
		return;
	const sptr_t caret = S(v, SCI_GETCURRENTPOS);
	const sptr_t start = wordStartBefore(v, caret, d.additionalWordChars);
	if (caret - start < MAX(p.autoCompleteFromChar, 1))
		return;
	std::string prefix = MppGetRange(v, start, caret);
	if (p.autoCompleteIgnoreNumbers && prefix.find_first_not_of("0123456789.xXabcdefABCDEF") == std::string::npos &&
	    isdigit((unsigned char)prefix[0]))
		return;

	std::vector<std::string> items;
	if (p.autoCompleteMode == MppAutoCompleteFunction || p.autoCompleteMode == MppAutoCompleteBoth)
		for (const auto &k : d.keywords)
			if (startsWith(k.name, prefix, d.ignoreCase) && k.name.size() > prefix.size())
				items.push_back(k.name);
	if (p.autoCompleteMode == MppAutoCompleteWord || p.autoCompleteMode == MppAutoCompleteBoth) {
		auto words = documentWords(v, prefix, start, d.additionalWordChars);
		items.insert(items.end(), words.begin(), words.end());
	}
	showList(v, caret - start, items, d.ignoreCase);
}

@end
