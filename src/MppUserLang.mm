// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppUserLang.h"
#import "MppUserLangModel.h"
#import "MppPaths.h"
#import "MppLanguages.h"
#import "MppPrefs.h"
#import "MppStyler.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"
#include <algorithm>
#include <map>
#include <string>
#include <vector>

namespace {

const std::map<std::string, int> &keywordIds()
{
	static const std::map<std::string, int> m = {
		// pre 2.0
		{"Operators", SCE_USER_KWLIST_OPERATORS1}, {"Folder+", SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN},
		{"Folder-", SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE}, {"Words1", SCE_USER_KWLIST_KEYWORDS1},
		{"Words2", SCE_USER_KWLIST_KEYWORDS2}, {"Words3", SCE_USER_KWLIST_KEYWORDS3}, {"Words4", SCE_USER_KWLIST_KEYWORDS4},
		// 2.0
		{"Comments", SCE_USER_KWLIST_COMMENTS}, {"Numbers, additional", SCE_USER_KWLIST_NUMBER_RANGE},
		{"Numbers, prefixes", SCE_USER_KWLIST_NUMBER_PREFIX2}, {"Numbers, extras with prefixes", SCE_USER_KWLIST_NUMBER_EXTRAS2},
		{"Numbers, suffixes", SCE_USER_KWLIST_NUMBER_SUFFIX2}, {"Operators1", SCE_USER_KWLIST_OPERATORS1},
		{"Operators2", SCE_USER_KWLIST_OPERATORS2},
		{"Folders in code1, open", SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN}, {"Folders in code1, middle", SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE},
		{"Folders in code1, close", SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE}, {"Folders in code2, open", SCE_USER_KWLIST_FOLDERS_IN_CODE2_OPEN},
		{"Folders in code2, middle", SCE_USER_KWLIST_FOLDERS_IN_CODE2_MIDDLE}, {"Folders in code2, close", SCE_USER_KWLIST_FOLDERS_IN_CODE2_CLOSE},
		{"Folders in comment, open", SCE_USER_KWLIST_FOLDERS_IN_COMMENT_OPEN}, {"Folders in comment, middle", SCE_USER_KWLIST_FOLDERS_IN_COMMENT_MIDDLE},
		{"Folders in comment, close", SCE_USER_KWLIST_FOLDERS_IN_COMMENT_CLOSE},
		{"Keywords1", SCE_USER_KWLIST_KEYWORDS1}, {"Keywords2", SCE_USER_KWLIST_KEYWORDS2}, {"Keywords3", SCE_USER_KWLIST_KEYWORDS3},
		{"Keywords4", SCE_USER_KWLIST_KEYWORDS4}, {"Keywords5", SCE_USER_KWLIST_KEYWORDS5}, {"Keywords6", SCE_USER_KWLIST_KEYWORDS6},
		{"Keywords7", SCE_USER_KWLIST_KEYWORDS7}, {"Keywords8", SCE_USER_KWLIST_KEYWORDS8}, {"Delimiters", SCE_USER_KWLIST_DELIMITERS},
		// 2.1
		{"Numbers, prefix1", SCE_USER_KWLIST_NUMBER_PREFIX1}, {"Numbers, prefix2", SCE_USER_KWLIST_NUMBER_PREFIX2},
		{"Numbers, extras1", SCE_USER_KWLIST_NUMBER_EXTRAS1}, {"Numbers, extras2", SCE_USER_KWLIST_NUMBER_EXTRAS2},
		{"Numbers, suffix1", SCE_USER_KWLIST_NUMBER_SUFFIX1}, {"Numbers, suffix2", SCE_USER_KWLIST_NUMBER_SUFFIX2},
		{"Numbers, range", SCE_USER_KWLIST_NUMBER_RANGE},
	};
	return m;
}

const std::map<std::string, int> &styleIds()
{
	static const std::map<std::string, int> m = {
		{"FOLDEROPEN", SCE_USER_STYLE_FOLDER_IN_CODE1}, {"FOLDERCLOSE", SCE_USER_STYLE_FOLDER_IN_CODE1},
		{"KEYWORD1", SCE_USER_STYLE_KEYWORD1}, {"KEYWORD2", SCE_USER_STYLE_KEYWORD2}, {"KEYWORD3", SCE_USER_STYLE_KEYWORD3},
		{"KEYWORD4", SCE_USER_STYLE_KEYWORD4}, {"COMMENT", SCE_USER_STYLE_COMMENT}, {"COMMENT LINE", SCE_USER_STYLE_COMMENTLINE},
		{"NUMBER", SCE_USER_STYLE_NUMBER}, {"OPERATOR", SCE_USER_STYLE_OPERATOR}, {"DELIMINER1", SCE_USER_STYLE_DELIMITER1},
		{"DELIMINER2", SCE_USER_STYLE_DELIMITER2}, {"DELIMINER3", SCE_USER_STYLE_DELIMITER3},
		{"DEFAULT", SCE_USER_STYLE_DEFAULT}, {"COMMENTS", SCE_USER_STYLE_COMMENT}, {"LINE COMMENTS", SCE_USER_STYLE_COMMENTLINE},
		{"NUMBERS", SCE_USER_STYLE_NUMBER}, {"KEYWORDS1", SCE_USER_STYLE_KEYWORD1}, {"KEYWORDS2", SCE_USER_STYLE_KEYWORD2},
		{"KEYWORDS3", SCE_USER_STYLE_KEYWORD3}, {"KEYWORDS4", SCE_USER_STYLE_KEYWORD4}, {"KEYWORDS5", SCE_USER_STYLE_KEYWORD5},
		{"KEYWORDS6", SCE_USER_STYLE_KEYWORD6}, {"KEYWORDS7", SCE_USER_STYLE_KEYWORD7}, {"KEYWORDS8", SCE_USER_STYLE_KEYWORD8},
		{"OPERATORS", SCE_USER_STYLE_OPERATOR}, {"FOLDER IN CODE1", SCE_USER_STYLE_FOLDER_IN_CODE1},
		{"FOLDER IN CODE2", SCE_USER_STYLE_FOLDER_IN_CODE2}, {"FOLDER IN COMMENT", SCE_USER_STYLE_FOLDER_IN_COMMENT},
		{"DELIMITERS1", SCE_USER_STYLE_DELIMITER1}, {"DELIMITERS2", SCE_USER_STYLE_DELIMITER2},
		{"DELIMITERS3", SCE_USER_STYLE_DELIMITER3}, {"DELIMITERS4", SCE_USER_STYLE_DELIMITER4},
		{"DELIMITERS5", SCE_USER_STYLE_DELIMITER5}, {"DELIMITERS6", SCE_USER_STYLE_DELIMITER6},
		{"DELIMITERS7", SCE_USER_STYLE_DELIMITER7}, {"DELIMITERS8", SCE_USER_STYLE_DELIMITER8},
	};
	return m;
}

const std::map<int, const char *> &setLexerMapper()
{
	static const std::map<int, const char *> m = {
		{SCE_USER_KWLIST_COMMENTS, "userDefine.comments"}, {SCE_USER_KWLIST_DELIMITERS, "userDefine.delimiters"},
		{SCE_USER_KWLIST_OPERATORS1, "userDefine.operators1"}, {SCE_USER_KWLIST_NUMBER_PREFIX1, "userDefine.numberPrefix1"},
		{SCE_USER_KWLIST_NUMBER_PREFIX2, "userDefine.numberPrefix2"}, {SCE_USER_KWLIST_NUMBER_EXTRAS1, "userDefine.numberExtras1"},
		{SCE_USER_KWLIST_NUMBER_EXTRAS2, "userDefine.numberExtras2"}, {SCE_USER_KWLIST_NUMBER_SUFFIX1, "userDefine.numberSuffix1"},
		{SCE_USER_KWLIST_NUMBER_SUFFIX2, "userDefine.numberSuffix2"}, {SCE_USER_KWLIST_NUMBER_RANGE, "userDefine.numberRange"},
		{SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN, "userDefine.foldersInCode1Open"},
		{SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE, "userDefine.foldersInCode1Middle"},
		{SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE, "userDefine.foldersInCode1Close"},
	};
	return m;
}

const char *keywordNameForId(int id)
{
	// names used by UDL 2.x for the Prefix element attributes
	static const char *names[] = {"Keywords1", "Keywords2", "Keywords3", "Keywords4",
	                              "Keywords5", "Keywords6", "Keywords7", "Keywords8"};
	return names[id - SCE_USER_KWLIST_KEYWORDS1];
}

bool boolAttr(NSXMLElement *e, NSString *name)
{
	return [[[e attributeForName:name] stringValue] isEqualToString:@"yes"];
}

std::string strAttr(NSXMLElement *e, NSString *name)
{
	NSString *v = [[e attributeForName:name] stringValue];
	return v ? v.UTF8String : "";
}

void parseUserLang(NSXMLElement *ul, UserLang &lang)
{
	lang.name = strAttr(ul, @"name");
	for (NSString *e in [[[ul attributeForName:@"ext"] stringValue] componentsSeparatedByString:@" "])
		if (e.length)
			lang.exts.push_back(e.lowercaseString.UTF8String);
	lang.udlVersion = strAttr(ul, @"udlVersion");
	lang.darkModeTheme = strAttr(ul, @"darkModeTheme") == "yes";

	NSXMLElement *settings = [ul elementsForName:@"Settings"].firstObject;
	if (NSXMLElement *g = [settings elementsForName:@"Global"].firstObject) {
		lang.caseIgnored = boolAttr(g, @"caseIgnored");
		lang.allowFoldOfComments = boolAttr(g, @"allowFoldOfComments");
		lang.foldCompact = boolAttr(g, @"foldCompact");
		lang.forcePureLC = [[[g attributeForName:@"forcePureLC"] stringValue] intValue];
		lang.decimalSeparator = [[[g attributeForName:@"decimalSeparator"] stringValue] intValue];
	}
	if (NSXMLElement *p = [settings elementsForName:@"Prefix"].firstObject) {
		if (lang.udlVersion == "2.1" || lang.udlVersion == "2.0") {
			for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i)
				lang.isPrefix[i] = boolAttr(p, @(keywordNameForId(i + SCE_USER_KWLIST_KEYWORDS1)));
		} else {
			NSArray *old = @[@"words1", @"words2", @"words3", @"words4"];
			for (int i = 0; i < 4; ++i)
				lang.isPrefix[i] = boolAttr(p, old[i]);
		}
	}

	NSXMLElement *kwl = [ul elementsForName:@"KeywordLists"].firstObject;
	for (NSXMLElement *k in [kwl elementsForName:@"Keywords"]) {
		std::string name = strAttr(k, @"name");
		std::string value = k.stringValue ? k.stringValue.UTF8String : "";
		if (lang.udlVersion.empty() && name == "Delimiters" && value.size() >= 6) {
			std::string t;
			const std::string &v = value;
			t += "00"; if (v[0] != '0') t += v[0]; t += " 01";
			t += " 02"; if (v[3] != '0') t += v[3];
			t += " 03"; if (v[1] != '0') t += v[1]; t += " 04";
			t += " 05"; if (v[4] != '0') t += v[4];
			t += " 06"; if (v[2] != '0') t += v[2]; t += " 07";
			t += " 08"; if (v[5] != '0') t += v[5];
			t += " 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23";
			lang.keywordLists[SCE_USER_KWLIST_DELIMITERS] = t;
		} else if (name == "Comment") {
			std::string t = " " + value;
			auto repl = [&t](const char *from, const char *to) {
				size_t pos = t.find(from);
				while (pos != std::string::npos) {
					t.replace(pos, 2, to);
					pos = t.find(from, pos + 1);
				}
			};
			repl(" 0", " 00");
			repl(" 1", " 03");
			repl(" 2", " 04");
			t += " 01 02";
			if (!t.empty() && t[0] == ' ')
				t.erase(0, 1);
			lang.keywordLists[SCE_USER_KWLIST_COMMENTS] = t;
		} else {
			auto it = keywordIds().find(name);
			if (it != keywordIds().end())
				lang.keywordLists[it->second] = value;
		}
	}

	NSXMLElement *styles = [ul elementsForName:@"Styles"].firstObject;
	for (NSXMLElement *ws in [styles elementsForName:@"WordsStyle"]) {
		std::string name = strAttr(ws, @"name");
		auto it = styleIds().find(name);
		if (it == styleIds().end())
			continue;
		UdlStyle s;
		s.style.styleID = it->second;
		s.style.name = name;
		int cs = 0;
		if ([ws attributeForName:@"fgColor"]) {
			s.style.fgColor = MppParseHexColor(strAttr(ws, @"fgColor").c_str());
			cs |= COLORSTYLE_FOREGROUND;
		}
		if ([ws attributeForName:@"bgColor"]) {
			s.style.bgColor = MppParseHexColor(strAttr(ws, @"bgColor").c_str());
			cs |= COLORSTYLE_BACKGROUND;
		}
		if ([ws attributeForName:@"colorStyle"])
			cs &= [[[ws attributeForName:@"colorStyle"] stringValue] intValue];
		s.style.colorStyle = cs;
		s.style.fontName = strAttr(ws, @"fontName");
		std::string fs = strAttr(ws, @"fontStyle");
		s.style.fontStyle = fs.empty() ? -1 : atoi(fs.c_str());
		std::string sz = strAttr(ws, @"fontSize");
		s.style.fontSize = sz.empty() ? -1 : atoi(sz.c_str());
		s.nesting = [[[ws attributeForName:@"nesting"] stringValue] intValue];
		lang.styles.push_back(s);
	}
}

std::string hexColor(int c)
{
	char b[8];
	snprintf(b, sizeof b, "%02X%02X%02X", c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF);
	return b;
}

NSXMLElement *element(NSString *name, NSDictionary<NSString *, NSString *> *attrs)
{
	NSXMLElement *e = [NSXMLElement elementWithName:name];
	for (NSString *k in attrs)
		[e addAttribute:[NSXMLNode attributeWithName:k stringValue:attrs[k]]];
	return e;
}

// Serialises a language into the UDL 2.1 XML tree
NSXMLElement *serializeUserLang(const UserLang &l)
{
	NSMutableArray *exts = [NSMutableArray array];
	for (const auto &e : l.exts)
		[exts addObject:@(e.c_str())];
	NSXMLElement *ul = element(@"UserLang", @{@"name": @(l.name.c_str()), @"ext": [exts componentsJoinedByString:@" "]});
	if (l.darkModeTheme)
		[ul addAttribute:[NSXMLNode attributeWithName:@"darkModeTheme" stringValue:@"yes"]];
	[ul addAttribute:[NSXMLNode attributeWithName:@"udlVersion" stringValue:@"2.1"]];

	auto yn = [](bool b) { return b ? @"yes" : @"no"; };
	NSXMLElement *settings = element(@"Settings", @{});
	// canonical UDL 2.1 attribute order
	NSXMLElement *global = [NSXMLElement elementWithName:@"Global"];
	for (NSArray *kv in @[@[@"caseIgnored", yn(l.caseIgnored)], @[@"allowFoldOfComments", yn(l.allowFoldOfComments)],
	                      @[@"foldCompact", yn(l.foldCompact)], @[@"forcePureLC", [NSString stringWithFormat:@"%d", l.forcePureLC]],
	                      @[@"decimalSeparator", [NSString stringWithFormat:@"%d", l.decimalSeparator]]])
		[global addAttribute:[NSXMLNode attributeWithName:kv[0] stringValue:kv[1]]];
	[settings addChild:global];
	NSXMLElement *prefix = [NSXMLElement elementWithName:@"Prefix"];
	for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i)
		[prefix addAttribute:[NSXMLNode attributeWithName:@(MppUdlKeywordListName(SCE_USER_KWLIST_KEYWORDS1 + i)) stringValue:yn(l.isPrefix[i])]];
	[settings addChild:prefix];
	[ul addChild:settings];

	NSXMLElement *kwl = element(@"KeywordLists", @{});
	for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) {
		NSXMLElement *k = element(@"Keywords", @{@"name": @(MppUdlKeywordListName(i))});
		k.stringValue = @(l.keywordLists[i].c_str()) ?: @"";
		[kwl addChild:k];
	}
	[ul addChild:kwl];

	NSXMLElement *styles = element(@"Styles", @{});
	for (const auto &us : l.styles) {
		const MppStyle &st = us.style;
		NSXMLElement *w = [NSXMLElement elementWithName:@"WordsStyle"];
		auto add = [w](NSString *k, NSString *v) { [w addAttribute:[NSXMLNode attributeWithName:k stringValue:v]]; };
		add(@"name", @(MppUdlStyleName(st.styleID)));
		add(@"fgColor", @(hexColor(st.fgColor).c_str()));
		add(@"bgColor", @(hexColor(st.bgColor).c_str()));
		if (st.colorStyle != COLORSTYLE_ALL)
			add(@"colorStyle", [NSString stringWithFormat:@"%d", st.colorStyle]);
		if (!st.fontName.empty())
			add(@"fontName", @(st.fontName.c_str()));
		add(@"fontStyle", [NSString stringWithFormat:@"%d", st.fontStyle < 0 ? 0 : st.fontStyle]);
		if (st.fontSize > 0)
			add(@"fontSize", [NSString stringWithFormat:@"%d", st.fontSize]);
		add(@"nesting", [NSString stringWithFormat:@"%d", us.nesting]);
		[styles addChild:w];
	}
	[ul addChild:styles];
	return ul;
}

// A new language as created by "Create New..." (all styles transparent, i.e. using the theme's default)
UserLang makeUserLang(const std::string &name)
{
	UserLang l;
	l.name = name;
	l.udlVersion = "2.1";
	std::string comments[5], delims[24];
	l.keywordLists[SCE_USER_KWLIST_COMMENTS] = MppUdlSetPrefixed(comments, 5);
	l.keywordLists[SCE_USER_KWLIST_DELIMITERS] = MppUdlSetPrefixed(delims, 24);
	for (int id = SCE_USER_STYLE_DEFAULT; id < SCE_USER_STYLE_TOTAL_STYLES; ++id) {
		UdlStyle us;
		us.style.styleID = id;
		us.style.name = MppUdlStyleName(id);
		us.style.fgColor = 0;
		us.style.bgColor = 0xFFFFFF;
		us.style.colorStyle = 0;
		us.style.fontStyle = 0;
		l.styles.push_back(us);
	}
	return l;
}

NSString *safeFileName(const std::string &name)
{
	NSString *n = [@(name.c_str()) stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	n = [n stringByReplacingOccurrencesOfString:@":" withString:@"_"];
	return [n stringByAppendingString:@".xml"];
}

} // namespace

UdlStyle *UserLang::findStyle(int styleID)
{
	for (auto &s : styles)
		if (s.style.styleID == styleID)
			return &s;
	UdlStyle us;
	us.style.styleID = styleID;
	us.style.name = MppUdlStyleName(styleID);
	us.style.colorStyle = 0;
	us.style.fontStyle = 0;
	styles.push_back(us);
	return &styles.back();
}

const char *MppUdlKeywordListName(int kwlist)
{
	static const char *names[SCE_USER_KWLIST_TOTAL] = {
		"Comments", "Numbers, prefix1", "Numbers, prefix2", "Numbers, extras1", "Numbers, extras2",
		"Numbers, suffix1", "Numbers, suffix2", "Numbers, range", "Operators1", "Operators2",
		"Folders in code1, open", "Folders in code1, middle", "Folders in code1, close",
		"Folders in code2, open", "Folders in code2, middle", "Folders in code2, close",
		"Folders in comment, open", "Folders in comment, middle", "Folders in comment, close",
		"Keywords1", "Keywords2", "Keywords3", "Keywords4", "Keywords5", "Keywords6", "Keywords7", "Keywords8",
		"Delimiters"};
	return kwlist >= 0 && kwlist < SCE_USER_KWLIST_TOTAL ? names[kwlist] : "";
}

const char *MppUdlStyleName(int styleID)
{
	static const char *names[SCE_USER_STYLE_TOTAL_STYLES] = {
		"DEFAULT", "COMMENTS", "LINE COMMENTS", "NUMBERS", "KEYWORDS1", "KEYWORDS2", "KEYWORDS3", "KEYWORDS4",
		"KEYWORDS5", "KEYWORDS6", "KEYWORDS7", "KEYWORDS8", "OPERATORS", "FOLDER IN CODE1", "FOLDER IN CODE2",
		"FOLDER IN COMMENT", "DELIMITERS1", "DELIMITERS2", "DELIMITERS3", "DELIMITERS4", "DELIMITERS5",
		"DELIMITERS6", "DELIMITERS7", "DELIMITERS8"};
	return styleID >= 0 && styleID < SCE_USER_STYLE_TOTAL_STYLES ? names[styleID] : "";
}

// CommentStyleDialog::retrieve
std::string MppUdlGetPrefixed(const std::string &l, const char *prefix)
{
	std::string out;
	bool begin2Copy = false, inGroup = false;
	const size_t len = l.size();
	auto at = [&](size_t i) { return i < len ? l[i] : '\0'; };
	for (size_t i = 0; i < len; ++i) {
		if ((i == 0 || l[i - 1] == ' ') && l[i] == prefix[0] && at(i + 1) == prefix[1]) {
			if (!out.empty())
				out += ' ';
			begin2Copy = true;
			++i;
			continue;
		}
		if (l[i] == '(' && at(i + 1) == '(' && !inGroup && begin2Copy)
			inGroup = true;
		if (l[i] != ')' && i >= 2 && l[i - 1] == ')' && l[i - 2] == ')' && inGroup)
			inGroup = false;
		if (l[i] == ' ' && begin2Copy)
			begin2Copy = false;
		if (begin2Copy || inGroup)
			out += l[i];
	}
	return out;
}

// convertTo() from UserDefineDialog.cpp, applied to each field
std::string MppUdlSetPrefixed(const std::string *fields, int count)
{
	std::string dest;
	for (int f = 0; f < count; ++f) {
		char prefix[3];
		snprintf(prefix, sizeof prefix, "%02d", f);
		const std::string &t = fields[f];
		const size_t len = t.size();
		auto at = [&](size_t i) { return i < len ? t[i] : '\0'; };
		bool inGroup = false;
		if (!dest.empty())
			dest += ' ';
		dest += prefix;
		for (size_t i = 0; i < len; ++i) {
			if (i == 0 && t[i] == '(' && at(i + 1) == '(') {
				inGroup = true;
			} else if (t[i] == ' ' && at(i + 1) == '(' && at(i + 2) == '(') {
				inGroup = true;
				dest += ' ';
				dest += prefix;
				++i;
			}
			if (inGroup && i >= 2 && t[i - 1] == ')' && t[i - 2] == ')')
				inGroup = false;
			if (t[i] == ' ') {
				if (at(i + 1) != ' ' && at(i + 1) != '\0') {
					dest += ' ';
					if (!inGroup)
						dest += prefix;
				}
			} else {
				dest += t[i];
			}
		}
	}
	return dest;
}

NSString *const MppUserLangDidChangeNotification = @"MppUserLangDidChangeNotification";

@implementation MppUserLangManager {
	std::vector<UserLang> _langs;
}

+ (instancetype)shared
{
	static MppUserLangManager *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		s = [[MppUserLangManager alloc] init];
		[s reload];
	});
	return s;
}

- (NSString *)directory
{
	NSString *d = [MppPaths.userDataDirectory stringByAppendingPathComponent:@"userDefineLangs"];
	[NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
	return d;
}

- (void)loadFile:(NSString *)path into:(std::vector<UserLang> &)out
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data)
		return;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
	for (NSXMLElement *ul in [doc nodesForXPath:@"//UserLang" error:nil]) {
		UserLang l;
		parseUserLang(ul, l);
		l.source = path.UTF8String;
		if (!l.name.empty())
			out.push_back(l);
	}
}

- (void)reload
{
	std::vector<UserLang> langs;
	NSString *single = [MppPaths.userDataDirectory stringByAppendingPathComponent:@"userDefineLang.xml"];
	if ([NSFileManager.defaultManager fileExistsAtPath:single])
		[self loadFile:single into:langs];
	NSString *dir = [self directory];
	for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]
	         sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
		if ([f.pathExtension.lowercaseString isEqualToString:@"xml"])
			[self loadFile:[dir stringByAppendingPathComponent:f] into:langs];
	// Languages shipped with the app (the preinstalled Markdown UDLs) unless the user has their own copy
	NSString *bundled = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"userDefineLangs"];
	for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:bundled error:nil]
	         sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
		std::vector<UserLang> tmp;
		[self loadFile:[bundled stringByAppendingPathComponent:f] into:tmp];
		for (auto &l : tmp) {
			l.bundled = true;
			if (std::none_of(langs.begin(), langs.end(), [&](const UserLang &x) { return x.name == l.name; }))
				langs.push_back(l);
		}
	}
	_langs = langs;
}

- (NSArray<NSString *> *)languageNames
{
	NSMutableArray *a = [NSMutableArray array];
	for (const auto &l : _langs)
		[a addObject:@(l.name.c_str())];
	return a;
}

- (const UserLang *)find:(NSString *)name
{
	if (!name)
		return nullptr;
	for (const auto &l : _langs)
		if (l.name == name.UTF8String)
			return &l;
	return nullptr;
}

- (NSString *)languageForFileName:(NSString *)fileName
{
	NSString *ext = fileName.pathExtension.lowercaseString;
	NSString *name = fileName.lastPathComponent.lowercaseString;
	// Prefer the variant made for the current (light / dark) theme
	const bool dark = [MppLanguages.shared theme]->isDark();
	const UserLang *fallback = nullptr;
	for (const auto &l : _langs)
		for (const auto &e : l.exts)
			if ((ext.length && e == ext.UTF8String) || e == name.UTF8String) {
				if (l.darkModeTheme == dark)
					return @(l.name.c_str());
				if (!fallback)
					fallback = &l;
			}
	return fallback ? @(fallback->name.c_str()) : nil;
}

- (NSInteger)importFile:(NSString *)path
{
	std::vector<UserLang> tmp;
	[self loadFile:path into:tmp];
	if (tmp.empty())
		return 0;
	NSString *dst = [[self directory] stringByAppendingPathComponent:path.lastPathComponent];
	[NSFileManager.defaultManager removeItemAtPath:dst error:nil];
	[NSFileManager.defaultManager copyItemAtPath:path toPath:dst error:nil];
	[self reload];
	return (NSInteger)tmp.size();
}

- (NSString *)commentLineForLanguage:(NSString *)name
{
	const UserLang *l = [self find:name];
	if (!l)
		return nil;
	// Comments list: "00<open line> 01<cont> 02<close line> 03<open block> 04<close block>"
	NSString *list = @(l->keywordLists[SCE_USER_KWLIST_COMMENTS].c_str());
	for (NSString *tok in [list componentsSeparatedByString:@" "])
		if ([tok hasPrefix:@"00"] && tok.length > 2)
			return [tok substringFromIndex:2];
	return nil;
}

- (void)applyLanguage:(NSString *)name toView:(ScintillaView *)view documentID:(int)docID
{
	const UserLang *ul = [self find:name];
	if (!ul)
		return;
	auto exec = [view](unsigned int m, uptr_t w, sptr_t l) { return [view message:m wParam:w lParam:l]; };
	auto prop = [&exec](const char *k, const char *v) { exec(SCI_SETPROPERTY, (uptr_t)k, (sptr_t)v); };

	exec(SCI_SETILEXER, 0, (sptr_t)CreateLexer("user"));
	prop("fold", "1");
	prop("userDefine.isCaseIgnored", ul->caseIgnored ? "1" : "0");
	prop("userDefine.allowFoldOfComments", ul->allowFoldOfComments ? "1" : "0");
	prop("userDefine.foldCompact", ul->foldCompact ? "1" : "0");
	char key[64];
	for (int i = 0; i < SCE_USER_TOTAL_KEYWORD_GROUPS; ++i) {
		snprintf(key, sizeof key, "userDefine.prefixKeywords%d", i + 1);
		prop(key, ul->isPrefix[i] ? "1" : "0");
	}

	int setKeywordsCounter = 0;
	for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) {
		const std::string &kw = ul->keywordLists[i];
		auto mapped = setLexerMapper().find(i);
		if (mapped != setLexerMapper().end()) {
			prop(mapped->second, kw.c_str());
			continue;
		}
		// Same quoting rules as ScintillaEditView::setUserLexer
		std::string temp;
		bool inDouble = false, inSingle = false, nonWSFound = false;
		const size_t len = kw.size();
		for (size_t j = 0; j < len; ++j) {
			const char c = kw[j];
			if (!inSingle && c == '"') { inDouble = !inDouble; continue; }
			if (!inDouble && c == '\'') { inSingle = !inSingle; continue; }
			if (c == '\\' && j + 1 < len && (kw[j + 1] == '"' || kw[j + 1] == '\'' || kw[j + 1] == '\\')) {
				++j;
				temp += kw[j];
				continue;
			}
			if (inDouble || inSingle) {
				if (c > ' ') {
					temp += c;
					nonWSFound = true;
				} else if (nonWSFound && j > 0 && kw[j - 1] != '"' && j + 1 < len && kw[j + 1] != '"' && kw[j + 1] > ' ') {
					temp += inDouble ? '\v' : '\b';
				}
			} else {
				temp += c;
			}
		}
		exec(SCI_SETKEYWORDS, (uptr_t)setKeywordsCounter++, (sptr_t)temp.c_str());
	}

	char buf[32];
	snprintf(buf, sizeof buf, "%d", ul->forcePureLC);
	prop("userDefine.forcePureLC", buf);
	snprintf(buf, sizeof buf, "%d", ul->decimalSeparator);
	prop("userDefine.decimalSeparator", buf);
	snprintf(buf, sizeof buf, "%d", (int)(ul - _langs.data()) + 1);
	prop("userDefine.udlName", buf);
	snprintf(buf, sizeof buf, "%d", docID);
	prop("userDefine.currentBufferID", buf);

	const bool macFont = [MppPrefs shared].useMacFont;
	for (const auto &us : ul->styles) {
		const MppStyle &s = us.style;
		snprintf(key, sizeof key, "userDefine.nesting.%02d", s.styleID);
		snprintf(buf, sizeof buf, "%d", us.nesting);
		prop(key, buf);
		const int id = s.styleID;
		if (s.colorStyle & COLORSTYLE_FOREGROUND)
			exec(SCI_STYLESETFORE, (uptr_t)id, s.fgColor);
		if (s.colorStyle & COLORSTYLE_BACKGROUND)
			exec(SCI_STYLESETBACK, (uptr_t)id, s.bgColor);
		if (!macFont && !s.fontName.empty() && [NSFont fontWithName:@(s.fontName.c_str()) size:12])
			exec(SCI_STYLESETFONT, (uptr_t)id, (sptr_t)s.fontName.c_str());
		if (s.fontStyle >= 0) {
			exec(SCI_STYLESETBOLD, (uptr_t)id, (s.fontStyle & FONTSTYLE_BOLD) != 0);
			exec(SCI_STYLESETITALIC, (uptr_t)id, (s.fontStyle & FONTSTYLE_ITALIC) != 0);
			exec(SCI_STYLESETUNDERLINE, (uptr_t)id, (s.fontStyle & FONTSTYLE_UNDERLINE) != 0);
		}
		if (!macFont && s.fontSize > 0)
			exec(SCI_STYLESETSIZE, (uptr_t)id, s.fontSize);
	}
}

// ---- Editing -----------------------------------------------------------------------------------

- (UserLang *)languageNamed:(NSString *)name
{
	return const_cast<UserLang *>([self find:name]);
}

- (BOOL)isBundledLanguage:(NSString *)name
{
	const UserLang *l = [self find:name];
	return l && l->bundled;
}

- (BOOL)createLanguage:(NSString *)name copyOf:(NSString *)sourceName
{
	if (!name.length || [self find:name])
		return NO;
	const UserLang *src = [self find:sourceName];
	UserLang l = src ? *src : makeUserLang(name.UTF8String);
	l.name = name.UTF8String;
	l.bundled = false;
	l.source = [[self directory] stringByAppendingPathComponent:safeFileName(l.name)].UTF8String;
	_langs.push_back(l);
	[self saveLanguage:name];
	[NSNotificationCenter.defaultCenter postNotificationName:MppUserLangDidChangeNotification object:self userInfo:@{@"name": name}];
	return YES;
}

- (BOOL)renameLanguage:(NSString *)name to:(NSString *)newName
{
	UserLang *l = [self languageNamed:name];
	if (!l || !newName.length || [self find:newName])
		return NO;
	if (l->bundled)
		return [self createLanguage:newName copyOf:name];
	const std::string oldSource = l->source;
	l->name = newName.UTF8String;
	// A file holding just this language follows the new name
	if ([@(oldSource.c_str()).lastPathComponent isEqualToString:safeFileName(name.UTF8String)]) {
		[NSFileManager.defaultManager removeItemAtPath:@(oldSource.c_str()) error:nil];
		l->source = [[self directory] stringByAppendingPathComponent:safeFileName(l->name)].UTF8String;
	}
	[self saveLanguage:newName];
	[NSNotificationCenter.defaultCenter postNotificationName:MppUserLangDidChangeNotification object:self
	                                                  userInfo:@{@"name": newName, @"oldName": name}];
	return YES;
}

- (void)removeLanguage:(NSString *)name
{
	const UserLang *l = [self find:name];
	if (!l || l->bundled)
		return;
	const std::string source = l->source;
	_langs.erase(_langs.begin() + (l - _langs.data()));
	[self writeSource:source];
	[NSNotificationCenter.defaultCenter postNotificationName:MppUserLangDidChangeNotification object:self userInfo:@{@"oldName": name}];
}

- (void)languageDidChange:(NSString *)name
{
	[NSNotificationCenter.defaultCenter postNotificationName:MppUserLangDidChangeNotification object:self userInfo:@{@"name": name}];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveLanguage:) object:name];
	[self performSelector:@selector(saveLanguage:) withObject:name afterDelay:0.5];
}

// Writes every language that lives in the given file (userDefineLang.xml can hold several)
- (BOOL)writeSource:(const std::string &)source
{
	NSXMLElement *root = [NSXMLElement elementWithName:@"MacpadPlus"];
	for (const auto &l : _langs)
		if (l.source == source)
			[root addChild:serializeUserLang(l)];
	NSString *path = @(source.c_str());
	if (!root.childCount)
		return [NSFileManager.defaultManager removeItemAtPath:path error:nil];
	NSXMLDocument *doc = [NSXMLDocument documentWithRootElement:root];
	doc.characterEncoding = @"UTF-8";
	doc.version = @"1.0";
	NSData *data = [doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
	return [data writeToFile:path atomically:YES];
}

- (BOOL)saveLanguage:(NSString *)name
{
	UserLang *l = [self languageNamed:name];
	if (!l)
		return NO;
	if (l->bundled) {
		// Edited preinstalled language: from now on the user's copy is used
		l->bundled = false;
		l->source = [[self directory] stringByAppendingPathComponent:@(l->source.c_str()).lastPathComponent].UTF8String;
	}
	return [self writeSource:l->source];
}

- (BOOL)exportLanguage:(NSString *)name toPath:(NSString *)path
{
	const UserLang *l = [self find:name];
	if (!l)
		return NO;
	NSXMLElement *root = [NSXMLElement elementWithName:@"MacpadPlus"];
	[root addChild:serializeUserLang(*l)];
	NSXMLDocument *doc = [NSXMLDocument documentWithRootElement:root];
	doc.characterEncoding = @"UTF-8";
	doc.version = @"1.0";
	return [[doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement] writeToFile:path atomically:YES];
}


@end

