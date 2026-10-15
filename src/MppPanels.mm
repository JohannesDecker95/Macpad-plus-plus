// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppPanels.h"
#import "MppMainWindowController.h"
#import "MppFindReplace.h"
#import "MppStyler.h"
#import "MppPaths.h"
#import "MppEditing.h"
#import "MppLanguages.h"
#import "MppUserLang.h"
#include "Scintilla.h"
#include "BoostRegexSearch.h"
#include <map>
#include <memory>

// =====================================================================================
// Function list parsers (driven by functionList/*.xml)
// =====================================================================================

namespace {

typedef std::vector<std::pair<sptr_t, sptr_t>> Zones;

struct FoundInfo {
	std::string data;    // function name
	std::string data2;   // class name
	sptr_t pos = -1;
	sptr_t pos2 = -1;
};

constexpr int kParseFlags = SCFIND_REGEXP | SCFIND_POSIX | SCFIND_REGEXP_DOTMATCHESNL;

inline sptr_t S(ScintillaView *v, unsigned int m, uptr_t w = 0, sptr_t l = 0)
{
	return [v message:m wParam:w lParam:l];
}

sptr_t searchInTarget(ScintillaView *v, const std::string &expr, sptr_t begin, sptr_t end)
{
	S(v, SCI_SETTARGETRANGE, (uptr_t)begin, end);
	return S(v, SCI_SEARCHINTARGET, expr.size(), (sptr_t)expr.c_str());
}

std::string genericText(ScintillaView *v, sptr_t start, sptr_t end)
{
	if (end - start > 1023)
		end = start + 1023;
	return MppGetRange(v, start, end);
}

bool isInZones(sptr_t pos, const Zones &zones)
{
	for (const auto &z : zones)
		if (pos >= z.first && pos < z.second)
			return true;
	return false;
}

void getInvertZones(Zones &dest, const Zones &src, sptr_t begin, sptr_t end)
{
	if (src.empty()) {
		dest.emplace_back(begin, end);
		return;
	}
	if (begin < src[0].first)
		dest.emplace_back(begin, src[0].first - 1);
	size_t i = 0;
	for (size_t len = src.size() - 1; i < len; ++i) {
		const sptr_t nb = src[i].second + 1, ne = src[i + 1].first - 1;
		if (nb < ne)
			dest.emplace_back(nb, ne);
	}
	const sptr_t lastBegin = src[i].second + 1;
	if (lastBegin < end)
		dest.emplace_back(lastBegin, end);
}

class FunctionParser {
public:
	FunctionParser(std::string comment, std::string funcExpr, std::vector<std::string> funcNames, std::vector<std::string> classNames)
		: _commentExpr(std::move(comment)), _functionExpr(std::move(funcExpr)), _functionNameExprArray(std::move(funcNames)),
		  _classNameExprArray(std::move(classNames)) {}
	virtual ~FunctionParser() = default;
	virtual void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls = "") = 0;

	void funcParse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls,
	               const Zones *commentZones = nullptr)
	{
		if (begin >= end || _functionExpr.empty())
			return;
		S(v, SCI_SETSEARCHFLAGS, kParseFlags);
		sptr_t targetStart = searchInTarget(v, _functionExpr, begin, end);
		int guard = 0;
		while (targetStart >= 0 && guard++ < 100000) {
			targetStart = S(v, SCI_GETTARGETSTART);
			const sptr_t targetEnd = S(v, SCI_GETTARGETEND);
			if (targetEnd > end)
				break;
			const sptr_t foundLen = targetEnd - targetStart;
			if (targetStart + foundLen == end)
				break;
			FoundInfo fi;
			if (_functionNameExprArray.empty() && _classNameExprArray.empty()) {
				fi.data = genericText(v, targetStart, targetEnd);
				fi.pos = targetStart;
			} else {
				sptr_t foundPos = -1;
				if (!_functionNameExprArray.empty()) {
					fi.data = parseSubLevel(targetStart, targetEnd, _functionNameExprArray, foundPos, v);
					fi.pos = foundPos;
				}
				if (!cls.empty()) {
					fi.data2 = cls;
					fi.pos2 = -1;
				} else if (!_classNameExprArray.empty()) {
					fi.data2 = parseSubLevel(targetStart, targetEnd, _classNameExprArray, foundPos, v);
					fi.pos2 = foundPos;
				}
			}
			if (fi.pos != -1 || fi.pos2 != -1) {
				if (!commentZones || (!isInZones(fi.pos, *commentZones) && !isInZones(fi.pos2, *commentZones)))
					out.push_back(fi);
			}
			begin = targetStart + (foundLen > 0 ? foundLen : 1);
			S(v, SCI_SETSEARCHFLAGS, kParseFlags);
			targetStart = searchInTarget(v, _functionExpr, begin, end);
		}
	}

protected:
	std::string parseSubLevel(sptr_t begin, sptr_t end, std::vector<std::string> dataToSearch, sptr_t &foundPos, ScintillaView *v)
	{
		if (begin >= end) {
			foundPos = -1;
			return "";
		}
		if (dataToSearch.empty())
			return "";
		S(v, SCI_SETSEARCHFLAGS, kParseFlags);
		const sptr_t targetStart = searchInTarget(v, dataToSearch[0], begin, end);
		if (targetStart < 0) {
			foundPos = -1;
			return "";
		}
		const sptr_t targetEnd = S(v, SCI_GETTARGETEND);
		if (dataToSearch.size() >= 2) {
			dataToSearch.erase(dataToSearch.begin());
			return parseSubLevel(targetStart, targetEnd, dataToSearch, foundPos, v);
		}
		foundPos = targetStart;
		return genericText(v, targetStart, targetEnd);
	}

	void getCommentZones(Zones &zones, sptr_t begin, sptr_t end, ScintillaView *v)
	{
		if (begin >= end || _commentExpr.empty())
			return;
		S(v, SCI_SETSEARCHFLAGS, kParseFlags);
		sptr_t targetStart = searchInTarget(v, _commentExpr, begin, end);
		int guard = 0;
		while (targetStart >= 0 && guard++ < 1000000) {
			targetStart = S(v, SCI_GETTARGETSTART);
			const sptr_t targetEnd = S(v, SCI_GETTARGETEND);
			if (targetEnd > end)
				break;
			zones.emplace_back(targetStart, targetEnd);
			const sptr_t foundLen = targetEnd - targetStart;
			if (targetStart + foundLen == end)
				break;
			begin = targetStart + (foundLen > 0 ? foundLen : 1);
			targetStart = searchInTarget(v, _commentExpr, begin, end);
		}
	}

	std::string _commentExpr;
	std::string _functionExpr;
	std::vector<std::string> _functionNameExprArray;
	std::vector<std::string> _classNameExprArray;
};

class FunctionUnitParser : public FunctionParser {
public:
	using FunctionParser::FunctionParser;
	void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) override
	{
		Zones comments, nonComments;
		getCommentZones(comments, begin, end, v);
		getInvertZones(nonComments, comments, begin, end);
		for (const auto &z : nonComments)
			funcParse(out, z.first, z.second, v, cls);
	}
};

class FunctionZoneParser : public FunctionParser {
public:
	FunctionZoneParser(std::string comment, std::string rangeExpr, std::string open, std::string close,
	                   std::vector<std::string> classNames, std::string funcExpr, std::vector<std::string> funcNames)
		: FunctionParser(std::move(comment), std::move(funcExpr), std::move(funcNames), std::move(classNames)),
		  _rangeExpr(std::move(rangeExpr)), _openSymbole(std::move(open)), _closeSymbole(std::move(close)) {}

	void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) override
	{
		Zones classZones, comments, nonComments;
		getCommentZones(comments, begin, end, v);
		getInvertZones(nonComments, comments, begin, end);
		for (const auto &z : nonComments)
			classParse(out, classZones, comments, z.first, z.second, v, cls);
	}

protected:
	sptr_t getBodyClosePos(sptr_t begin, const std::string &open, const std::string &close, const Zones &comments, ScintillaView *v)
	{
		size_t cntOpen = 1;
		const sptr_t docLen = S(v, SCI_GETLENGTH);
		if (begin >= docLen)
			return docLen;
		const std::string expr = "(" + open + "|" + close + ")";
		S(v, SCI_SETSEARCHFLAGS, kParseFlags);
		sptr_t targetStart = searchInTarget(v, expr, begin, docLen);
		sptr_t targetEnd = 0;
		int guard = 0;
		do {
			if (targetStart >= 0) {
				targetEnd = S(v, SCI_GETTARGETEND);
				if (!isInZones(targetStart, comments)) {
					const sptr_t tmp = searchInTarget(v, open, targetStart, targetEnd);
					if (tmp >= 0)
						++cntOpen;
					else
						--cntOpen;
				}
			} else {
				cntOpen = 0;
				targetEnd = begin;
			}
			targetStart = searchInTarget(v, expr, targetEnd, docLen);
		} while (cntOpen && guard++ < 1000000);
		return targetEnd;
	}

	void classParse(std::vector<FoundInfo> &out, Zones &scanned, const Zones &comments, sptr_t begin, sptr_t end,
	                ScintillaView *v, const std::string &)
	{
		if (begin >= end)
			return;
		S(v, SCI_SETSEARCHFLAGS, kParseFlags);
		sptr_t targetStart = searchInTarget(v, _rangeExpr, begin, end);
		int guard = 0;
		while (targetStart >= 0 && guard++ < 100000) {
			sptr_t targetEnd = S(v, SCI_GETTARGETEND);
			sptr_t foundPos = 0;
			std::string cls = parseSubLevel(targetStart, targetEnd, _classNameExprArray, foundPos, v);
			if (!_openSymbole.empty() && !_closeSymbole.empty())
				targetEnd = getBodyClosePos(targetEnd, _openSymbole, _closeSymbole, comments, v);
			if (targetEnd > end)
				break;
			scanned.emplace_back(targetStart, targetEnd);
			const sptr_t foundLen = targetEnd - targetStart;
			if (targetStart + foundLen == end)
				break;
			if (!isInZones(targetStart, comments))
				funcParse(out, targetStart, targetEnd, v, cls, &comments);
			begin = targetStart + (foundLen > 0 ? foundLen : 1);
			S(v, SCI_SETSEARCHFLAGS, kParseFlags);
			targetStart = searchInTarget(v, _rangeExpr, begin, end);
		}
	}

	std::string _rangeExpr, _openSymbole, _closeSymbole;
};

class FunctionMixParser : public FunctionZoneParser {
public:
	FunctionMixParser(std::string comment, std::string rangeExpr, std::string open, std::string close,
	                  std::vector<std::string> classNames, std::string funcExpr, std::vector<std::string> funcNames,
	                  std::unique_ptr<FunctionUnitParser> unit)
		: FunctionZoneParser(std::move(comment), std::move(rangeExpr), std::move(open), std::move(close), std::move(classNames),
		                     std::move(funcExpr), std::move(funcNames)),
		  _unit(std::move(unit)) {}

	void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) override
	{
		Zones comments, scanned, nonScanned;
		getCommentZones(comments, begin, end, v);
		classParse(out, scanned, comments, begin, end, v, cls);
		for (const auto &z : Zones(scanned)) {
			Zones tmp;
			classParse(out, tmp, comments, z.first, z.second, v, cls);
		}
		getInvertZones(nonScanned, scanned, begin, end);
		if (_unit)
			for (const auto &z : nonScanned)
				_unit->funcParse(out, z.first, z.second, v, cls, &comments);
	}

private:
	std::unique_ptr<FunctionUnitParser> _unit;
};

std::string attr(NSXMLElement *e, NSString *n)
{
	NSString *s = [[e attributeForName:n] stringValue];
	return s ? s.UTF8String : "";
}

std::vector<std::string> exprs(NSXMLElement *parent, NSString *child, NSString *exprName)
{
	std::vector<std::string> v;
	NSXMLElement *c = [parent elementsForName:child].firstObject;
	for (NSXMLElement *e in [c elementsForName:exprName]) {
		std::string x = attr(e, @"expr");
		if (!x.empty())
			v.push_back(x);
	}
	return v;
}

// XML attribute-value normalisation turns newlines into spaces, which breaks the (?x) regexes
// (their '#' comments end at a newline). Other XML parsers keep them, so escape
// whitespace inside attribute values as character references before parsing.
NSData *preserveAttributeNewlines(NSData *in)
{
	if (!in)
		return nil;
	const char *p = (const char *)in.bytes;
	const size_t n = in.length;
	std::string out;
	out.reserve(n + n / 8);
	bool inTag = false;
	char quote = 0;
	for (size_t i = 0; i < n; ++i) {
		const char c = p[i];
		if (!inTag) {
			if (c == '<') {
				if (n - i >= 4 && memcmp(p + i, "<!--", 4) == 0) {
					const char *end = strstr(p + i + 4, "-->");
					const size_t stop = end ? (size_t)(end - p) + 3 : n;
					out.append(p + i, stop - i);
					i = stop - 1;
					continue;
				}
				if (n - i >= 9 && memcmp(p + i, "<![CDATA[", 9) == 0) {
					const char *end = strstr(p + i + 9, "]]>");
					const size_t stop = end ? (size_t)(end - p) + 3 : n;
					out.append(p + i, stop - i);
					i = stop - 1;
					continue;
				}
				inTag = (i + 1 < n && p[i + 1] != '?');
			}
			out += c;
			continue;
		}
		if (quote) {
			if (c == quote)
				quote = 0;
			if (c == '\n') { out += "&#10;"; continue; }
			if (c == '\r') { out += "&#13;"; continue; }
			if (c == '\t') { out += "&#9;"; continue; }
		} else if (c == '"' || c == '\'') {
			quote = c;
		} else if (c == '>') {
			inTag = false;
		}
		out += c;
	}
	return [NSData dataWithBytes:out.data() length:out.size()];
}

std::unique_ptr<FunctionParser> loadParser(NSString *path)
{
	NSData *data = preserveAttributeNewlines([NSData dataWithContentsOfFile:path]);
	if (!data)
		return nullptr;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
	NSXMLElement *parser = [[doc nodesForXPath:@"/*/functionList/parser" error:nil] firstObject];
	if (!parser)
		return nullptr;
	const std::string comment = attr(parser, @"commentExpr");
	NSXMLElement *classRange = [parser elementsForName:@"classRange"].firstObject;
	NSXMLElement *function = [parser elementsForName:@"function"].firstObject;
	auto unitFrom = [&](NSXMLElement *f) -> std::unique_ptr<FunctionUnitParser> {
		std::string main = attr(f, @"mainExpr");
		if (main.empty())
			return nullptr;
		return std::make_unique<FunctionUnitParser>(comment, main, exprs(f, @"functionName", @"nameExpr"), exprs(f, @"className", @"nameExpr"));
	};
	if (classRange) {
		std::string main = attr(classRange, @"mainExpr");
		NSXMLElement *cf = [classRange elementsForName:@"function"].firstObject;
		std::string funcExpr = attr(cf, @"mainExpr");
		if (main.empty() || funcExpr.empty())
			return function ? unitFrom(function) : nullptr;
		auto classNames = exprs(classRange, @"className", @"nameExpr");
		auto funcNames = exprs(cf, @"functionName", @"funcNameExpr");
		if (function)
			return std::make_unique<FunctionMixParser>(comment, main, attr(classRange, @"openSymbole"), attr(classRange, @"closeSymbole"),
			                                           classNames, funcExpr, funcNames, unitFrom(function));
		return std::make_unique<FunctionZoneParser>(comment, main, attr(classRange, @"openSymbole"), attr(classRange, @"closeSymbole"),
		                                            classNames, funcExpr, funcNames);
	}
	if (function)
		return unitFrom(function);
	return nullptr;
}

NSString *functionListDir(NSString *file)
{
	NSString *user = [[MppPaths.userDataDirectory stringByAppendingPathComponent:@"functionList"] stringByAppendingPathComponent:file];
	if ([NSFileManager.defaultManager fileExistsAtPath:user])
		return user;
	return [[MppPaths.resourceDirectory stringByAppendingPathComponent:@"functionList"] stringByAppendingPathComponent:file];
}

// overrideMap.xml: langID -> parser file, userDefinedLangName -> parser file
NSDictionary *overrideMap()
{
	static NSDictionary *map;
	if (map)
		return map;
	NSMutableDictionary *m = [NSMutableDictionary dictionary];
	NSData *data = [NSData dataWithContentsOfFile:functionListDir(@"overrideMap.xml")];
	if (data) {
		NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
		for (NSXMLElement *a in [doc nodesForXPath:@"/*/functionList/associationMap/association" error:nil]) {
			NSString *ident = [[a attributeForName:@"id"] stringValue];
			NSString *langID = [[a attributeForName:@"langID"] stringValue];
			NSString *udl = [[a attributeForName:@"userDefinedLangName"] stringValue];
			if (!ident.length)
				continue;
			if (langID.length)
				m[@(langID.intValue)] = ident;
			else if (udl.length)
				m[udl] = ident;
		}
	}
	map = m;
	return map;
}

std::map<std::string, std::unique_ptr<FunctionParser>> g_parsers;

FunctionParser *parserFor(MppDocument *doc)
{
	NSString *file = nil;
	if (doc.lang == L_USER) {
		file = overrideMap()[doc.userLangName ?: @""];
	} else {
		file = overrideMap()[@(doc.lang)] ?: [@(g_mppLangNameInfo[doc.lang].langName) stringByAppendingPathExtension:@"xml"];
	}
	if (!file)
		return nullptr;
	const std::string key = file.UTF8String;
	auto it = g_parsers.find(key);
	if (it != g_parsers.end())
		return it->second.get();
	auto p = loadParser(functionListDir(file));
	FunctionParser *raw = p.get();
	g_parsers[key] = std::move(p);
	return raw;
}

} // namespace

// =====================================================================================
// Function List panel
// =====================================================================================

@interface MppFuncNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) sptr_t pos;
@property (nonatomic, strong) NSMutableArray<MppFuncNode *> *children;
@property (nonatomic) BOOL isClass;
@end
@implementation MppFuncNode
@end

@implementation MppFunctionListPanel {
	NSOutlineView *_outline;
	NSSearchField *_search;
	NSButton *_sortButton;
	MppFuncNode *_root;
	NSArray<MppFuncNode *> *_items;   // after filter / sort
	BOOL _sorted;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_sorted = [MppDefaults() boolForKey:@"funcListSorted"];
		_search = [[NSSearchField alloc] init];
		_search.placeholderString = @"Search";
		_search.delegate = self;
		_search.controlSize = NSControlSizeSmall;
		_sortButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.up.arrow.down" accessibilityDescription:@"Sort"]
		                                 target:self action:@selector(toggleSort:)];
		_sortButton.bordered = NO;
		_sortButton.toolTip = @"Sort";
		NSButton *reload = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Reload"]
		                                      target:self action:@selector(reload)];
		reload.bordered = NO;
		reload.toolTip = @"Reload";
		NSStackView *bar = [NSStackView stackViewWithViews:@[_search, _sortButton, reload]];
		bar.edgeInsets = NSEdgeInsetsMake(2, 4, 2, 4);
		bar.translatesAutoresizingMaskIntoConstraints = NO;

		_outline = [[NSOutlineView alloc] init];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		[_outline addTableColumn:col];
		_outline.outlineTableColumn = col;
		_outline.headerView = nil;
		_outline.dataSource = self;
		_outline.delegate = self;
		_outline.target = self;
		_outline.action = @selector(clicked:);
		_outline.doubleAction = @selector(clicked:);
		_outline.style = NSTableViewStyleSourceList;
		_outline.floatsGroupRows = NO;
		NSScrollView *sv = [[NSScrollView alloc] init];
		sv.documentView = _outline;
		sv.hasVerticalScroller = YES;
		sv.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:bar];
		[self addSubview:sv];
		[NSLayoutConstraint activateConstraints:@[
			[bar.topAnchor constraintEqualToAnchor:self.topAnchor],
			[bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[bar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[sv.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
			[sv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[sv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[sv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
	}
	return self;
}

static NSString *trimName(const std::string &s)
{
	NSString *n = [[NSString alloc] initWithBytes:s.c_str() length:strlen(s.c_str()) encoding:NSUTF8StringEncoding] ?: @"";
	n = [n stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
	n = [n stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
	n = [n stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
	while ([n containsString:@"  "])
		n = [n stringByReplacingOccurrencesOfString:@"  " withString:@" "];
	return [n stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

- (void)reload
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
	MppDocument *doc = _owner.currentDocument;
	_root = [[MppFuncNode alloc] init];
	_root.name = doc.displayName ?: @"";
	_root.children = [NSMutableArray array];
	FunctionParser *fp = doc ? parserFor(doc) : nullptr;
	if (fp) {
		MppDocumentManager *dm = MppDocumentManager.shared;
		ScintillaView *v = [dm attachScratchViewTo:doc];
		std::vector<FoundInfo> found;
		if (S(v, SCI_GETLENGTH) < 30 * 1024 * 1024)
			fp->parse(found, 0, S(v, SCI_GETLENGTH), v, "");
		[dm detachScratchView];
		NSMutableDictionary<NSString *, MppFuncNode *> *classes = [NSMutableDictionary dictionary];
		for (const auto &fi : found) {
			NSString *name = trimName(fi.data);
			NSString *cls = trimName(fi.data2);
			MppFuncNode *n = [[MppFuncNode alloc] init];
			n.name = name.length ? name : cls;
			n.pos = fi.pos >= 0 ? fi.pos : fi.pos2;
			if (cls.length && name.length) {
				MppFuncNode *c = classes[cls];
				if (!c) {
					c = [[MppFuncNode alloc] init];
					c.name = cls;
					c.isClass = YES;
					c.pos = fi.pos2 >= 0 ? fi.pos2 : fi.pos;
					c.children = [NSMutableArray array];
					classes[cls] = c;
					[_root.children addObject:c];
				}
				[c.children addObject:n];
			} else {
				[_root.children addObject:n];
			}
		}
	}
	[self applyFilter];
}

- (NSArray<MppFuncNode *> *)filtered:(NSArray<MppFuncNode *> *)nodes
{
	NSString *q = _search.stringValue;
	NSMutableArray *out = [NSMutableArray array];
	for (MppFuncNode *n in nodes) {
		if (n.children) {
			MppFuncNode *c = [[MppFuncNode alloc] init];
			c.name = n.name;
			c.pos = n.pos;
			c.isClass = n.isClass;
			c.children = [[self filtered:n.children] mutableCopy];
			if (c.children.count || !q.length || [n.name localizedCaseInsensitiveContainsString:q])
				[out addObject:c];
		} else if (!q.length || [n.name localizedCaseInsensitiveContainsString:q]) {
			[out addObject:n];
		}
	}
	if (_sorted)
		[out sortUsingComparator:^NSComparisonResult(MppFuncNode *a, MppFuncNode *b) { return [a.name localizedStandardCompare:b.name]; }];
	return out;
}

- (void)applyFilter
{
	MppFuncNode *root = [[MppFuncNode alloc] init];
	root.name = _root.name;
	root.children = [[self filtered:_root.children ?: @[]] mutableCopy];
	_items = @[root];
	[_outline reloadData];
	[_outline expandItem:nil expandChildren:YES];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	[self applyFilter];
}

- (void)toggleSort:(id)sender
{
	_sorted = !_sorted;
	[MppDefaults() setBool:_sorted forKey:@"funcListSorted"];
	[self applyFilter];
}

- (void)clicked:(id)sender
{
	MppFuncNode *n = [_outline itemAtRow:_outline.clickedRow];
	if (!n || n == _items.firstObject)
		return;
	const sptr_t line = [_owner sci:SCI_LINEFROMPOSITION w:(uptr_t)n.pos];
	[_owner gotoLine:line];
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
	return item ? (NSInteger)[(MppFuncNode *)item children].count : (NSInteger)_items.count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
	return item ? [(MppFuncNode *)item children][(NSUInteger)index] : _items[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
	return [(MppFuncNode *)item children] != nil;
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item
{
	MppFuncNode *n = item;
	NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:self];
	if (!cell) {
		cell = [[NSTableCellView alloc] init];
		cell.identifier = @"cell";
		NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"function" accessibilityDescription:nil]];
		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.lineBreakMode = NSLineBreakByTruncatingTail;
		iv.translatesAutoresizingMaskIntoConstraints = NO;
		tf.translatesAutoresizingMaskIntoConstraints = NO;
		[cell addSubview:iv];
		[cell addSubview:tf];
		cell.imageView = iv;
		cell.textField = tf;
		[NSLayoutConstraint activateConstraints:@[
			[iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
			[iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
			[iv.widthAnchor constraintEqualToConstant:16],
			[tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
			[tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
			[tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
		]];
	}
	NSString *symbol = (n == _items.firstObject) ? @"doc.text" : (n.isClass ? @"cube" : @"function");
	cell.imageView.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
	cell.imageView.contentTintColor = n.isClass ? NSColor.systemPurpleColor : NSColor.systemBlueColor;
	cell.textField.stringValue = n.name ?: @"";
	return cell;
}

@end

// =====================================================================================
// Document List panel
// =====================================================================================

@implementation MppDocumentListPanel {
	NSTableView *_table;
	NSArray<MppDocument *> *_docs;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_table = [[NSTableView alloc] init];
		for (NSArray *c in @[@[@"name", @"Name", @170], @[@"ext", @"Ext.", @50]]) {
			NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
			col.title = c[1];
			col.width = [c[2] doubleValue];
			[_table addTableColumn:col];
		}
		_table.dataSource = self;
		_table.delegate = self;
		_table.target = self;
		_table.action = @selector(clicked:);
		_table.style = NSTableViewStyleFullWidth;
		_table.usesAlternatingRowBackgroundColors = YES;
		NSMenu *menu = [[NSMenu alloc] init];
		[menu addItemWithTitle:@"Close" action:@selector(closeSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Save" action:@selector(saveSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealSelected:) keyEquivalent:@""].target = self;
		_table.menu = menu;
		NSScrollView *sv = [[NSScrollView alloc] initWithFrame:self.bounds];
		sv.documentView = _table;
		sv.hasVerticalScroller = YES;
		sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:sv];
	}
	return self;
}

- (void)reload
{
	_docs = _owner.allDocuments;
	[_table reloadData];
	NSUInteger cur = [_docs indexOfObject:_owner.currentDocument];
	if (cur != NSNotFound)
		[_table selectRowIndexes:[NSIndexSet indexSetWithIndex:cur] byExtendingSelection:NO];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
	return (NSInteger)_docs.count;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	MppDocument *d = _docs[(NSUInteger)row];
	if ([col.identifier isEqualToString:@"ext"])
		return d.displayName.pathExtension;
	NSString *name = d.displayName.pathExtension.length ? d.displayName.stringByDeletingPathExtension : d.displayName;
	return [NSString stringWithFormat:@"%@%@", name, d.dirty ? @" ●" : @""];
}

- (void)clicked:(id)sender
{
	NSInteger row = _table.clickedRow;
	if (row >= 0 && row < (NSInteger)_docs.count)
		[_owner activateDocument:_docs[(NSUInteger)row]];
}

- (MppDocument *)clickedDoc
{
	NSInteger row = _table.clickedRow >= 0 ? _table.clickedRow : _table.selectedRow;
	return (row >= 0 && row < (NSInteger)_docs.count) ? _docs[(NSUInteger)row] : nil;
}

- (void)closeSelected:(id)s { if (MppDocument *d = [self clickedDoc]) [_owner closeDocuments:@[d]]; }
- (void)saveSelected:(id)s { if (MppDocument *d = [self clickedDoc]) [_owner saveDocument:d]; }
- (void)revealSelected:(id)s
{
	MppDocument *d = [self clickedDoc];
	if (d.filePath)
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:d.filePath]]];
}

@end

// =====================================================================================
// Folder as Workspace panel
// =====================================================================================

@interface MppFileNode : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL isDir;
@property (nonatomic, strong) NSArray<MppFileNode *> *children;  // nil = not loaded
@end
@implementation MppFileNode
- (NSArray<MppFileNode *> *)loadChildren
{
	if (_children)
		return _children;
	NSMutableArray *a = [NSMutableArray array];
	NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:_path error:nil]
	    sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
	NSMutableArray *dirs = [NSMutableArray array], *files = [NSMutableArray array];
	for (NSString *n in names) {
		if ([n hasPrefix:@"."])
			continue;
		MppFileNode *c = [[MppFileNode alloc] init];
		c.path = [_path stringByAppendingPathComponent:n];
		BOOL isDir = NO;
		[NSFileManager.defaultManager fileExistsAtPath:c.path isDirectory:&isDir];
		c.isDir = isDir && ![NSWorkspace.sharedWorkspace isFilePackageAtPath:c.path];
		[(c.isDir ? dirs : files) addObject:c];
	}
	[a addObjectsFromArray:dirs];
	[a addObjectsFromArray:files];
	_children = a;
	return a;
}
@end

@implementation MppFileBrowserPanel {
	NSOutlineView *_outline;
	NSMutableArray<MppFileNode *> *_roots;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_roots = [NSMutableArray array];
		NSButton *add = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"folder.badge.plus" accessibilityDescription:@"Add folder"]
		                                   target:self action:@selector(addFolder:)];
		NSButton *refresh = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"Refresh"]
		                                       target:self action:@selector(refresh:)];
		NSButton *collapse = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.down.right.and.arrow.up.left" accessibilityDescription:@"Fold all"]
		                                        target:self action:@selector(collapseAll:)];
		NSButton *locate = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"scope" accessibilityDescription:@"Locate current file"]
		                                      target:self action:@selector(locateCurrent:)];
		for (NSButton *b in @[add, refresh, collapse, locate])
			b.bordered = NO;
		add.toolTip = @"Add folder";
		refresh.toolTip = @"Refresh";
		collapse.toolTip = @"Fold all";
		locate.toolTip = @"Locate current file";
		NSStackView *bar = [NSStackView stackViewWithViews:@[add, refresh, collapse, locate]];
		bar.edgeInsets = NSEdgeInsetsMake(2, 6, 2, 6);
		bar.translatesAutoresizingMaskIntoConstraints = NO;

		_outline = [[NSOutlineView alloc] init];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		[_outline addTableColumn:col];
		_outline.outlineTableColumn = col;
		_outline.headerView = nil;
		_outline.dataSource = self;
		_outline.delegate = self;
		_outline.target = self;
		_outline.doubleAction = @selector(openClicked:);
		_outline.style = NSTableViewStyleSourceList;
		NSMenu *menu = [[NSMenu alloc] init];
		[menu addItemWithTitle:@"Open" action:@selector(openSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Reveal in Finder" action:@selector(revealSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Open in Terminal" action:@selector(terminalSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Find in Files…" action:@selector(findInFilesSelected:) keyEquivalent:@""].target = self;
		[menu addItem:NSMenuItem.separatorItem];
		[menu addItemWithTitle:@"Copy Path" action:@selector(copyPathSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Copy File Name" action:@selector(copyNameSelected:) keyEquivalent:@""].target = self;
		[menu addItem:NSMenuItem.separatorItem];
		[menu addItemWithTitle:@"Remove from Workspace" action:@selector(removeSelected:) keyEquivalent:@""].target = self;
		[menu addItemWithTitle:@"Remove All Folders" action:@selector(removeAll:) keyEquivalent:@""].target = self;
		_outline.menu = menu;
		NSScrollView *sv = [[NSScrollView alloc] init];
		sv.documentView = _outline;
		sv.hasVerticalScroller = YES;
		sv.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:bar];
		[self addSubview:sv];
		[NSLayoutConstraint activateConstraints:@[
			[bar.topAnchor constraintEqualToAnchor:self.topAnchor],
			[bar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[sv.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
			[sv.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[sv.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[sv.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
	}
	return self;
}

- (NSArray<NSString *> *)rootFolders
{
	NSMutableArray *a = [NSMutableArray array];
	for (MppFileNode *n in _roots)
		[a addObject:n.path];
	return a;
}

- (void)persist
{
	[MppDefaults() setObject:self.rootFolders forKey:@"workspaceFolders"];
}

- (void)addRootFolder:(NSString *)path
{
	for (MppFileNode *n in _roots)
		if ([n.path isEqualToString:path])
			return;
	MppFileNode *n = [[MppFileNode alloc] init];
	n.path = path;
	n.isDir = YES;
	[_roots addObject:n];
	[_outline reloadData];
	[_outline expandItem:n];
	[self persist];
}

- (void)removeAllRoots
{
	[_roots removeAllObjects];
	[_outline reloadData];
	[self persist];
}

- (void)addFolder:(id)sender
{
	NSOpenPanel *p = [NSOpenPanel openPanel];
	p.canChooseDirectories = YES;
	p.canChooseFiles = NO;
	p.allowsMultipleSelection = YES;
	if ([p runModal] == NSModalResponseOK)
		for (NSURL *u in p.URLs)
			[self addRootFolder:u.path];
}

- (void)resetNode:(MppFileNode *)n
{
	n.children = nil;
}

- (void)refresh:(id)sender
{
	NSMutableSet *expanded = [NSMutableSet set];
	for (NSInteger r = 0; r < _outline.numberOfRows; ++r) {
		MppFileNode *n = [_outline itemAtRow:r];
		if ([_outline isItemExpanded:n])
			[expanded addObject:n.path];
	}
	for (MppFileNode *n in _roots)
		[self resetNode:n];
	[_outline reloadData];
	// re-expand
	for (NSInteger r = 0; r < _outline.numberOfRows; ++r) {
		MppFileNode *n = [_outline itemAtRow:r];
		if ([expanded containsObject:n.path])
			[_outline expandItem:n];
	}
}

- (void)collapseAll:(id)sender
{
	[_outline collapseItem:nil collapseChildren:YES];
}

- (void)locateCurrent:(id)sender
{
	NSString *path = _owner.currentDocument.filePath;
	if (!path)
		return;
	for (MppFileNode *root in _roots) {
		if (![path hasPrefix:[root.path stringByAppendingString:@"/"]])
			continue;
		MppFileNode *n = root;
		[_outline expandItem:n];
		NSArray *comps = [[path substringFromIndex:root.path.length + 1] pathComponents];
		for (NSString *c in comps) {
			MppFileNode *next = nil;
			for (MppFileNode *ch in [n loadChildren])
				if ([ch.path.lastPathComponent isEqualToString:c])
					next = ch;
			if (!next)
				break;
			n = next;
			if (n.isDir)
				[_outline expandItem:n];
		}
		NSInteger row = [_outline rowForItem:n];
		if (row >= 0) {
			[_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
			[_outline scrollRowToVisible:row];
		}
		return;
	}
}

- (MppFileNode *)targetNode
{
	NSInteger row = _outline.clickedRow >= 0 ? _outline.clickedRow : _outline.selectedRow;
	return row >= 0 ? [_outline itemAtRow:row] : nil;
}

- (void)openClicked:(id)sender
{
	MppFileNode *n = [_outline itemAtRow:_outline.clickedRow];
	if (!n)
		return;
	if (n.isDir) {
		if ([_outline isItemExpanded:n])
			[_outline collapseItem:n];
		else
			[_outline expandItem:n];
	} else {
		[_owner openPath:n.path];
	}
}

- (void)openSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (n && !n.isDir)
		[_owner openPath:n.path];
}

- (void)revealSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (n)
		[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:n.path]]];
}

- (void)terminalSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (!n)
		return;
	NSString *dir = n.isDir ? n.path : n.path.stringByDeletingLastPathComponent;
	NSURL *term = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
	[NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:dir]] withApplicationAtURL:term
	                        configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
}

- (void)findInFilesSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (!n)
		return;
	[_owner executeCommand:CMD_SEARCH_FINDINFILES];
	[_owner.findReplace setFindDirectory:n.isDir ? n.path : n.path.stringByDeletingLastPathComponent];
}

- (void)copyPathSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (!n)
		return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:n.path forType:NSPasteboardTypeString];
}

- (void)copyNameSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	if (!n)
		return;
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:n.path.lastPathComponent forType:NSPasteboardTypeString];
}

- (void)removeSelected:(id)s
{
	MppFileNode *n = [self targetNode];
	while (n && ![_roots containsObject:n])
		n = [_outline parentForItem:n];
	if (n) {
		[_roots removeObject:n];
		[_outline reloadData];
		[self persist];
	}
}

- (void)removeAll:(id)s
{
	[self removeAllRoots];
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
	return item ? (NSInteger)[(MppFileNode *)item loadChildren].count : (NSInteger)_roots.count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
	return item ? [(MppFileNode *)item loadChildren][(NSUInteger)index] : _roots[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
	return [(MppFileNode *)item isDir];
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(id)item
{
	MppFileNode *n = item;
	NSTableCellView *cell = [ov makeViewWithIdentifier:@"fcell" owner:self];
	if (!cell) {
		cell = [[NSTableCellView alloc] init];
		cell.identifier = @"fcell";
		NSImageView *iv = [[NSImageView alloc] init];
		NSTextField *tf = [NSTextField labelWithString:@""];
		tf.lineBreakMode = NSLineBreakByTruncatingMiddle;
		iv.translatesAutoresizingMaskIntoConstraints = NO;
		tf.translatesAutoresizingMaskIntoConstraints = NO;
		[cell addSubview:iv];
		[cell addSubview:tf];
		cell.imageView = iv;
		cell.textField = tf;
		[NSLayoutConstraint activateConstraints:@[
			[iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
			[iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
			[iv.widthAnchor constraintEqualToConstant:16],
			[iv.heightAnchor constraintEqualToConstant:16],
			[tf.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4],
			[tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
			[tf.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
		]];
	}
	cell.imageView.image = [NSWorkspace.sharedWorkspace iconForFile:n.path];
	cell.textField.stringValue = n.path.lastPathComponent;
	cell.toolTip = n.path;
	return cell;
}

@end

// =====================================================================================
// Clipboard History panel
// =====================================================================================

@implementation MppClipboardHistoryPanel {
	NSTableView *_table;
	NSMutableArray<NSString *> *_items;
	NSInteger _changeCount;
	NSTimer *_timer;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_items = [NSMutableArray array];
		_table = [[NSTableView alloc] init];
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"text"];
		col.title = @"Clipboard Data";
		[_table addTableColumn:col];
		_table.headerView = nil;
		_table.dataSource = self;
		_table.delegate = self;
		_table.target = self;
		_table.doubleAction = @selector(insertClicked:);
		_table.usesAlternatingRowBackgroundColors = YES;
		NSScrollView *sv = [[NSScrollView alloc] initWithFrame:self.bounds];
		sv.documentView = _table;
		sv.hasVerticalScroller = YES;
		sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:sv];
		_changeCount = -1;
		[self poll];
		_timer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(poll) userInfo:nil repeats:YES];
	}
	return self;
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
	if (!newWindow) {
		[_timer invalidate];
		_timer = nil;
	} else if (!_timer) {
		_timer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(poll) userInfo:nil repeats:YES];
	}
}

- (void)poll
{
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	if (pb.changeCount == _changeCount)
		return;
	_changeCount = pb.changeCount;
	NSString *s = [pb stringForType:NSPasteboardTypeString];
	if (!s.length)
		return;
	[_items removeObject:s];
	[_items insertObject:s atIndex:0];
	while (_items.count > 30)
		[_items removeLastObject];
	[_table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
	return (NSInteger)_items.count;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	NSString *s = _items[(NSUInteger)row];
	s = [[s stringByReplacingOccurrencesOfString:@"\r" withString:@" "] stringByReplacingOccurrencesOfString:@"\n" withString:@" ⏎ "];
	return s.length > 200 ? [[s substringToIndex:200] stringByAppendingString:@"…"] : s;
}

- (void)insertClicked:(id)sender
{
	NSInteger row = _table.clickedRow;
	if (row < 0 || row >= (NSInteger)_items.count)
		return;
	std::string s = _items[(NSUInteger)row].UTF8String;
	[_owner sci:SCI_REPLACESEL w:0 l:(sptr_t)s.c_str()];
	[_owner.window makeFirstResponder:_owner.activeEditor.content];
}

@end

// =====================================================================================
// Character Panel (ASCII Codes Insertion Panel)
// =====================================================================================

@implementation MppCharacterPanel {
	NSTableView *_table;
}

static NSString *htmlName(int c)
{
	static NSDictionary *names = @{
		@34: @"&quot;", @38: @"&amp;", @60: @"&lt;", @62: @"&gt;", @160: @"&nbsp;", @161: @"&iexcl;", @162: @"&cent;",
		@163: @"&pound;", @164: @"&curren;", @165: @"&yen;", @166: @"&brvbar;", @167: @"&sect;", @168: @"&uml;",
		@169: @"&copy;", @170: @"&ordf;", @171: @"&laquo;", @172: @"&not;", @173: @"&shy;", @174: @"&reg;",
		@175: @"&macr;", @176: @"&deg;", @177: @"&plusmn;", @178: @"&sup2;", @179: @"&sup3;", @180: @"&acute;",
		@181: @"&micro;", @182: @"&para;", @183: @"&middot;", @184: @"&cedil;", @185: @"&sup1;", @186: @"&ordm;",
		@187: @"&raquo;", @188: @"&frac14;", @189: @"&frac12;", @190: @"&frac34;", @191: @"&iquest;", @215: @"&times;",
		@247: @"&divide;", @196: @"&Auml;", @214: @"&Ouml;", @220: @"&Uuml;", @223: @"&szlig;", @228: @"&auml;",
		@246: @"&ouml;", @252: @"&uuml;", @233: @"&eacute;", @232: @"&egrave;", @224: @"&agrave;", @231: @"&ccedil;",
	};
	return names[@(c)] ?: @"";
}

static NSString *charName(int c)
{
	static const char *ctrl[] = {"NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "TAB", "LF", "VT", "FF", "CR",
	                             "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB",
	                             "ESC", "FS", "GS", "RS", "US"};
	if (c < 32)
		return @(ctrl[c]);
	if (c == 32)
		return @"Space";
	if (c == 127)
		return @"DEL";
	unichar u = (unichar)c;
	return [NSString stringWithCharacters:&u length:1];
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_table = [[NSTableView alloc] init];
		for (NSArray *c in @[@[@"dec", @"Value", @50], @[@"hex", @"Hex", @40], @[@"char", @"Character", @70],
		                     @[@"html", @"HTML Name", @70], @[@"num", @"HTML Number", @80]]) {
			NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
			col.title = c[1];
			col.width = [c[2] doubleValue];
			[_table addTableColumn:col];
		}
		_table.dataSource = self;
		_table.delegate = self;
		_table.target = self;
		_table.doubleAction = @selector(insertClicked:);
		_table.usesAlternatingRowBackgroundColors = YES;
		NSScrollView *sv = [[NSScrollView alloc] initWithFrame:self.bounds];
		sv.documentView = _table;
		sv.hasVerticalScroller = YES;
		sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		[self addSubview:sv];
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
	return 256;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	const int c = (int)row;
	NSString *ident = col.identifier;
	if ([ident isEqualToString:@"dec"]) return [NSString stringWithFormat:@"%d", c];
	if ([ident isEqualToString:@"hex"]) return [NSString stringWithFormat:@"%02X", c];
	if ([ident isEqualToString:@"char"]) return charName(c);
	if ([ident isEqualToString:@"html"]) return htmlName(c);
	return c >= 32 ? [NSString stringWithFormat:@"&#%d;", c] : @"";
}

- (void)insertClicked:(id)sender
{
	NSInteger row = _table.clickedRow;
	if (row < 0)
		return;
	NSString *ident = _table.clickedColumn >= 0 ? _table.tableColumns[(NSUInteger)_table.clickedColumn].identifier : @"char";
	NSString *ins;
	if ([ident isEqualToString:@"html"] && htmlName((int)row).length)
		ins = htmlName((int)row);
	else if ([ident isEqualToString:@"num"])
		ins = [NSString stringWithFormat:@"&#%ld;", (long)row];
	else {
		unichar u = (unichar)row;
		ins = [NSString stringWithCharacters:&u length:1];
	}
	std::string s = ins.UTF8String;
	if (row == 0)
		[_owner sci:SCI_ADDTEXT w:1 l:(sptr_t)"\0"];
	else
		[_owner sci:SCI_REPLACESEL w:0 l:(sptr_t)s.c_str()];
	[_owner.window makeFirstResponder:_owner.activeEditor.content];
}

@end

// =====================================================================================
// Document Map
// =====================================================================================

@interface MppDocMapOverlay : NSView
@property (nonatomic, weak) MppDocumentMapPanel *panel;
@property (nonatomic) NSRect highlight;
@end

@interface MppDocumentMapPanel ()
- (void)scrollEditorToMapPoint:(NSPoint)p;
- (void)forwardScroll:(NSEvent *)e;
@end

@implementation MppDocMapOverlay
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect
{
	const MppStyle *s = [MppLanguages.shared theme]->global("Document map");
	NSColor *c = s ? MppColorFromSci(s->fgColor) : NSColor.systemOrangeColor;
	[[c colorWithAlphaComponent:0.22] setFill];
	NSRectFillUsingOperation(_highlight, NSCompositingOperationSourceOver);
	[[c colorWithAlphaComponent:0.6] setStroke];
	NSBezierPath *p = [NSBezierPath bezierPathWithRect:NSInsetRect(_highlight, 0.5, 0.5)];
	[p stroke];
}
- (void)mouseDown:(NSEvent *)e { [_panel scrollEditorToMapPoint:[self convertPoint:e.locationInWindow fromView:nil]]; }
- (void)mouseDragged:(NSEvent *)e { [_panel scrollEditorToMapPoint:[self convertPoint:e.locationInWindow fromView:nil]]; }
- (void)scrollWheel:(NSEvent *)e { [_panel forwardScroll:e]; }
@end

@implementation MppDocumentMapPanel {
	MppScintillaView *_map;
	MppDocMapOverlay *_overlay;
	__weak MppDocument *_doc;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_map = [[MppScintillaView alloc] initWithFrame:self.bounds];
		_map.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_map.delegate = self;
		[self addSubview:_map];
		_overlay = [[MppDocMapOverlay alloc] initWithFrame:self.bounds];
		_overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_overlay.panel = self;
		_overlay.wantsLayer = YES;   // Scintilla's views are layer-backed; stay above them
		[self addSubview:_overlay positioned:NSWindowAbove relativeTo:_map];
		[MppStyler initializeView:_map];
	}
	return self;
}

- (void)notification:(SCNotification *)n
{
	if (n->nmhdr.code == SCN_UPDATEUI && (n->updated & SC_UPDATE_V_SCROLL))
		[self updateHighlight];
}

- (void)documentChanged
{
	MppDocument *doc = _owner.currentDocument;
	_doc = doc;
	if (!doc)
		return;
	[_map message:SCI_SETDOCPOINTER wParam:0 lParam:doc.sciDocument];
	[MppStyler defineDocType:doc.lang inView:_map];
	for (int m = 0; m < 5; ++m)
		[_map message:SCI_SETMARGINWIDTHN wParam:(uptr_t)m lParam:0];
	[_map message:SCI_SETZOOM wParam:(uptr_t)-10];
	[_map message:SCI_SETCARETSTYLE wParam:CARETSTYLE_INVISIBLE];
	[_map message:SCI_SETCARETLINEVISIBLEALWAYS wParam:0];
	[_map message:SCI_SETELEMENTCOLOUR wParam:SC_ELEMENT_CARET_LINE_BACK lParam:0];
	[_map message:SCI_SETHSCROLLBAR wParam:0];
	[_map message:SCI_SETVSCROLLBAR wParam:0];
	[_map message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE];
	[_map message:SCI_SETINDENTATIONGUIDES wParam:SC_IV_NONE];
	[self syncWithEditor];
}

- (void)syncWithEditor
{
	MppMainWindowController *o = _owner;
	if (!o || o.currentDocument != _doc) {
		if (o.currentDocument != _doc)
			[self documentChanged];
		return;
	}
	const sptr_t firstDisplay = [o sci:SCI_GETFIRSTVISIBLELINE];
	const sptr_t firstDoc = [o sci:SCI_DOCLINEFROMVISIBLE w:(uptr_t)firstDisplay];
	const sptr_t onScreen = [o sci:SCI_LINESONSCREEN];
	const sptr_t lastDoc = [o sci:SCI_DOCLINEFROMVISIBLE w:(uptr_t)(firstDisplay + onScreen)];
	const sptr_t mapFirst = [_map message:SCI_GETFIRSTVISIBLELINE];
	const sptr_t mapLines = [_map message:SCI_LINESONSCREEN];
	if (mapLines <= 1)
		return;   // not laid out yet
	sptr_t desired = mapFirst;
	if (firstDoc < mapFirst)
		desired = firstDoc;
	else if (lastDoc >= mapFirst + mapLines)
		desired = lastDoc - mapLines + 1;
	if ([_map message:SCI_GETLINECOUNT] <= mapLines)
		desired = 0;
	if (desired != mapFirst)
		[_map message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)std::max<sptr_t>(0, desired)];
	[self updateHighlight];
}

- (void)layout
{
	[super layout];
	[self syncWithEditor];
}

- (void)updateHighlight
{
	MppMainWindowController *o = _owner;
	if (!o)
		return;
	const sptr_t firstDisplay = [o sci:SCI_GETFIRSTVISIBLELINE];
	const sptr_t firstDoc = [o sci:SCI_DOCLINEFROMVISIBLE w:(uptr_t)firstDisplay];
	const sptr_t lastDoc = [o sci:SCI_DOCLINEFROMVISIBLE w:(uptr_t)(firstDisplay + [o sci:SCI_LINESONSCREEN])];
	const sptr_t mapFirst = [_map message:SCI_GETFIRSTVISIBLELINE];
	const CGFloat lh = (CGFloat)[_map message:SCI_TEXTHEIGHT wParam:0];
	const CGFloat y = (firstDoc - mapFirst) * lh;
	const CGFloat h = std::max<CGFloat>(lh, (lastDoc - firstDoc + 1) * lh);
	_overlay.highlight = NSMakeRect(0, y, self.bounds.size.width, h);
	[_overlay setNeedsDisplay:YES];
}

- (void)scrollEditorToMapPoint:(NSPoint)p
{
	MppMainWindowController *o = _owner;
	const CGFloat lh = (CGFloat)[_map message:SCI_TEXTHEIGHT wParam:0];
	if (lh <= 0)
		return;
	const sptr_t mapFirst = [_map message:SCI_GETFIRSTVISIBLELINE];
	sptr_t line = mapFirst + (sptr_t)(p.y / lh);
	line = std::max<sptr_t>(0, std::min(line, [_map message:SCI_GETLINECOUNT] - 1));
	const sptr_t onScreen = [o sci:SCI_LINESONSCREEN];
	const sptr_t display = [o sci:SCI_VISIBLEFROMDOCLINE w:(uptr_t)line];
	[o sci:SCI_SETFIRSTVISIBLELINE w:(uptr_t)std::max<sptr_t>(0, display - onScreen / 2)];
	[self syncWithEditor];
}

- (void)forwardScroll:(NSEvent *)e
{
	[_owner.activeEditor.content scrollWheel:e];
}

@end
