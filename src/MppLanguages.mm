// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppLanguages.h"
#import "MppPaths.h"

#include <algorithm>
#include <cstring>

const MppLangNameInfo g_mppLangNameInfo[L_EXTERNAL + 1] = {
	{"normal",        "Normal text",            "Normal text file",                                L_TEXT,          "null"},
	{"php",           "PHP",                    "PHP Hypertext Preprocessor file",                 L_PHP,           "phpscript"},
	{"c",             "C",                      "C source file",                                   L_C,             "cpp"},
	{"cpp",           "C++",                    "C++ source file",                                 L_CPP,           "cpp"},
	{"cs",            "C#",                     "C# source file",                                  L_CS,            "cpp"},
	{"objc",          "Objective-C",            "Objective-C source file",                         L_OBJC,          "objc"},
	{"java",          "Java",                   "Java source file",                                L_JAVA,          "cpp"},
	{"rc",            "RC",                     "Windows Resource file",                           L_RC,            "cpp"},
	{"html",          "HTML",                   "Hyper Text Markup Language file",                 L_HTML,          "hypertext"},
	{"xml",           "XML",                    "eXtensible Markup Language file",                 L_XML,           "xml"},
	{"makefile",      "Makefile",               "Makefile",                                        L_MAKEFILE,      "makefile"},
	{"pascal",        "Pascal",                 "Pascal source file",                              L_PASCAL,        "pascal"},
	{"batch",         "Batch",                  "Batch file",                                      L_BATCH,         "batch"},
	{"ini",           "ini",                    "MS ini file",                                     L_INI,           "props"},
	{"nfo",           "NFO",                    "MSDOS Style/ASCII Art",                           L_ASCII,         "null"},
	{"udf",           "udf",                    "User Defined language file",                      L_USER,          "user"},
	{"asp",           "ASP",                    "Active Server Pages script file",                 L_ASP,           "hypertext"},
	{"sql",           "SQL",                    "Structured Query Language file",                  L_SQL,           "sql"},
	{"vb",            "Visual Basic",           "Visual Basic file",                               L_VB,            "vb"},
	{"javascript",    "Embedded JS",            "Embedded JavaScript",                             L_JS_EMBEDDED,   "cpp"},
	{"css",           "CSS",                    "Cascade Style Sheets File",                       L_CSS,           "css"},
	{"perl",          "Perl",                   "Perl source file",                                L_PERL,          "perl"},
	{"python",        "Python",                 "Python file",                                     L_PYTHON,        "python"},
	{"lua",           "Lua",                    "Lua source File",                                 L_LUA,           "lua"},
	{"tex",           "TeX",                    "TeX file",                                        L_TEX,           "tex"},
	{"fortran",       "Fortran free form",      "Fortran free form source file",                   L_FORTRAN,       "fortran"},
	{"bash",          "Shell",                  "Unix script file",                                L_BASH,          "bash"},
	{"actionscript",  "ActionScript",           "Flash ActionScript file",                         L_FLASH,         "cpp"},
	{"nsis",          "NSIS",                   "Nullsoft Scriptable Install System script file",  L_NSIS,          "nsis"},
	{"tcl",           "TCL",                    "Tool Command Language file",                      L_TCL,           "tcl"},
	{"lisp",          "Lisp",                   "List Processing language file",                   L_LISP,          "lisp"},
	{"scheme",        "Scheme",                 "Scheme file",                                     L_SCHEME,        "lisp"},
	{"asm",           "Assembly",               "Assembly language source file",                   L_ASM,           "asm"},
	{"diff",          "Diff",                   "Diff file",                                       L_DIFF,          "diff"},
	{"props",         "Properties file",        "Properties file",                                 L_PROPS,         "props"},
	{"postscript",    "PostScript",             "PostScript file",                                 L_PS,            "ps"},
	{"ruby",          "Ruby",                   "Ruby file",                                       L_RUBY,          "ruby"},
	{"smalltalk",     "Smalltalk",              "Smalltalk file",                                  L_SMALLTALK,     "smalltalk"},
	{"vhdl",          "VHDL",                   "VHSIC Hardware Description Language file",        L_VHDL,          "vhdl"},
	{"kix",           "KiXtart",                "KiXtart file",                                    L_KIX,           "kix"},
	{"autoit",        "AutoIt",                 "AutoIt",                                          L_AU3,           "au3"},
	{"caml",          "CAML",                   "Categorical Abstract Machine Language",           L_CAML,          "caml"},
	{"ada",           "Ada",                    "Ada file",                                        L_ADA,           "ada"},
	{"verilog",       "Verilog",                "Verilog file",                                    L_VERILOG,       "verilog"},
	{"matlab",        "MATLAB",                 "MATrix LABoratory",                               L_MATLAB,        "matlab"},
	{"haskell",       "Haskell",                "Haskell",                                         L_HASKELL,       "haskell"},
	{"inno",          "Inno Setup",             "Inno Setup script",                               L_INNO,          "inno"},
	{"searchResult",  "Internal Search",        "Internal Search",                                 L_SEARCHRESULT,  "searchResult"},
	{"cmake",         "CMake",                  "CMake file",                                      L_CMAKE,         "cmake"},
	{"yaml",          "YAML",                   "YAML Ain't Markup Language",                      L_YAML,          "yaml"},
	{"cobol",         "COBOL",                  "COmmon Business Oriented Language",               L_COBOL,         "COBOL"},
	{"gui4cli",       "Gui4Cli",                "Gui4Cli file",                                    L_GUI4CLI,       "gui4cli"},
	{"d",             "D",                      "D programming language",                          L_D,             "d"},
	{"powershell",    "PowerShell",             "Windows PowerShell",                              L_POWERSHELL,    "powershell"},
	{"r",             "R",                      "R programming language",                          L_R,             "r"},
	{"jsp",           "JSP",                    "JavaServer Pages script file",                    L_JSP,           "hypertext"},
	{"coffeescript",  "CoffeeScript",           "CoffeeScript file",                               L_COFFEESCRIPT,  "coffeescript"},
	{"json",          "json",                   "JSON file",                                       L_JSON,          "json"},
	{"javascript.js", "JavaScript",             "JavaScript file",                                 L_JAVASCRIPT,    "cpp"},
	{"fortran77",     "Fortran fixed form",     "Fortran fixed form source file",                  L_FORTRAN_77,    "f77"},
	{"baanc",         "BaanC",                  "BaanC File",                                      L_BAANC,         "baan"},
	{"srec",          "S-Record",               "Motorola S-Record binary data",                   L_SREC,          "srec"},
	{"ihex",          "Intel HEX",              "Intel HEX binary data",                           L_IHEX,          "ihex"},
	{"tehex",         "Tektronix extended HEX", "Tektronix extended HEX binary data",              L_TEHEX,         "tehex"},
	{"swift",         "Swift",                  "Swift file",                                      L_SWIFT,         "cpp"},
	{"asn1",          "ASN.1",                  "Abstract Syntax Notation One file",               L_ASN1,          "asn1"},
	{"avs",           "AviSynth",               "AviSynth scripts files",                          L_AVS,           "avs"},
	{"blitzbasic",    "BlitzBasic",             "BlitzBasic file",                                 L_BLITZBASIC,    "blitzbasic"},
	{"purebasic",     "PureBasic",              "PureBasic file",                                  L_PUREBASIC,     "purebasic"},
	{"freebasic",     "FreeBasic",              "FreeBasic file",                                  L_FREEBASIC,     "freebasic"},
	{"csound",        "Csound",                 "Csound file",                                     L_CSOUND,        "csound"},
	{"erlang",        "Erlang",                 "Erlang file",                                     L_ERLANG,        "erlang"},
	{"escript",       "ESCRIPT",                "ESCRIPT file",                                    L_ESCRIPT,       "escript"},
	{"forth",         "Forth",                  "Forth file",                                      L_FORTH,         "forth"},
	{"latex",         "LaTeX",                  "LaTeX file",                                      L_LATEX,         "latex"},
	{"mmixal",        "MMIXAL",                 "MMIXAL file",                                     L_MMIXAL,        "mmixal"},
	{"nim",           "Nim",                    "Nim file",                                        L_NIM,           "nimrod"},
	{"nncrontab",     "Nncrontab",              "extended crontab file",                           L_NNCRONTAB,     "nncrontab"},
	{"oscript",       "OScript",                "OScript source file",                             L_OSCRIPT,       "oscript"},
	{"rebol",         "REBOL",                  "REBOL file",                                      L_REBOL,         "rebol"},
	{"registry",      "registry",               "registry file",                                   L_REGISTRY,      "registry"},
	{"rust",          "Rust",                   "Rust file",                                       L_RUST,          "rust"},
	{"spice",         "Spice",                  "spice file",                                      L_SPICE,         "spice"},
	{"txt2tags",      "txt2tags",               "txt2tags file",                                   L_TXT2TAGS,      "txt2tags"},
	{"visualprolog",  "Visual Prolog",          "Visual Prolog file",                              L_VISUALPROLOG,  "visualprolog"},
	{"typescript",    "TypeScript",             "TypeScript file",                                 L_TYPESCRIPT,    "cpp"},
	{"json5",         "json5",                  "JSON5 file",                                      L_JSON5,         "json"},
	{"mssql",         "mssql",                  "Microsoft Transact-SQL (SQL Server) file",        L_MSSQL,         "mssql"},
	{"gdscript",      "GDScript",               "GDScript file",                                   L_GDSCRIPT,      "gdscript"},
	{"hollywood",     "Hollywood",              "Hollywood script",                                L_HOLLYWOOD,     "hollywood"},
	{"go",            "Go",                     "Go source file",                                  L_GOLANG,        "cpp"},
	{"raku",          "Raku",                   "Raku source file",                                L_RAKU,          "raku"},
	{"toml",          "TOML",                   "Tom's Obvious Minimal Language file",             L_TOML,          "toml"},
	{"sas",           "SAS",                    "SAS file",                                        L_SAS,           "sas"},
	{"errorlist",     "ErrorList",              "ErrorList file",                                  L_ERRORLIST,     "errorlist"},
	{"escseq",        "EscapeSequence (ANSI)",  "Escape Sequence (ANSI) file",                     L_ESCSEQ,        "escseq"},
	{"fcST",          "Structured Text",        "IEC 61131-3 Structured Text file",                L_STTXT,         "fcST"},
	{"ext",           "External",               "External",                                        L_EXTERNAL,      "null"}
};

// Names shown in the Language menu
static const std::map<int, const char *> &menuNames()
{
	static const std::map<int, const char *> m = {
		{L_TEXT, "None (Normal Text)"}, {L_FLASH, "ActionScript"}, {L_ADA, "Ada"}, {L_ASN1, "ASN.1"},
		{L_ASP, "ASP"}, {L_ASM, "Assembly"}, {L_AU3, "AutoIt"}, {L_AVS, "AviSynth"}, {L_BAANC, "BaanC"},
		{L_BATCH, "Batch"}, {L_BLITZBASIC, "Blitzbasic"}, {L_C, "C"}, {L_CS, "C#"}, {L_CPP, "C++"},
		{L_CAML, "Caml"}, {L_CMAKE, "CMake"}, {L_COBOL, "COBOL"}, {L_CSOUND, "CSound"},
		{L_COFFEESCRIPT, "CoffeeScript"}, {L_CSS, "CSS"}, {L_D, "D"}, {L_DIFF, "Diff"},
		{L_ERLANG, "Erlang"}, {L_ERRORLIST, "ErrorList"}, {L_ESCSEQ, "Escape Sequence (ANSI)"},
		{L_ESCRIPT, "ESCRIPT"}, {L_FORTH, "Forth"}, {L_FORTRAN, "Fortran (free form)"},
		{L_FORTRAN_77, "Fortran (fixed form)"}, {L_FREEBASIC, "Freebasic"}, {L_GDSCRIPT, "GDScript"},
		{L_GOLANG, "Go"}, {L_GUI4CLI, "Gui4Cli"}, {L_HASKELL, "Haskell"}, {L_HOLLYWOOD, "Hollywood"},
		{L_HTML, "HTML"}, {L_INI, "INI file"}, {L_INNO, "Inno Setup"}, {L_IHEX, "Intel HEX"},
		{L_JAVA, "Java"}, {L_JAVASCRIPT, "JavaScript"}, {L_JSON, "JSON"}, {L_JSON5, "JSON5"},
		{L_JSP, "JSP"}, {L_KIX, "KIXtart"}, {L_LISP, "LISP"}, {L_LATEX, "LaTeX"}, {L_LUA, "Lua"},
		{L_MAKEFILE, "Makefile"}, {L_MATLAB, "Matlab"}, {L_MSSQL, "Microsoft Transact-SQL"},
		{L_MMIXAL, "MMIXAL"}, {L_ASCII, "MS-DOS Style"}, {L_NIM, "Nim"}, {L_NNCRONTAB, "Nncrontab"},
		{L_NSIS, "NSIS"}, {L_OBJC, "Objective-C"}, {L_OSCRIPT, "OScript"}, {L_PASCAL, "Pascal"},
		{L_PERL, "Perl"}, {L_PHP, "PHP"}, {L_PS, "PostScript"}, {L_POWERSHELL, "PowerShell"},
		{L_PROPS, "Properties"}, {L_PUREBASIC, "Purebasic"}, {L_PYTHON, "Python"}, {L_R, "R"},
		{L_RAKU, "Raku"}, {L_REBOL, "REBOL"}, {L_REGISTRY, "Registry"}, {L_RC, "Resource file"},
		{L_RUBY, "Ruby"}, {L_RUST, "Rust"}, {L_SAS, "SAS"}, {L_BASH, "Shell"}, {L_SCHEME, "Scheme"},
		{L_SMALLTALK, "Smalltalk"}, {L_SPICE, "Spice"}, {L_SQL, "SQL"}, {L_STTXT, "Structured Text"},
		{L_SWIFT, "Swift"}, {L_SREC, "S-Record"}, {L_TCL, "TCL"}, {L_TEHEX, "Tektronix extended HEX"},
		{L_TEX, "TeX"}, {L_TOML, "TOML"}, {L_TXT2TAGS, "txt2tags"}, {L_TYPESCRIPT, "TypeScript"},
		{L_VERILOG, "Verilog"}, {L_VHDL, "VHDL"}, {L_VB, "Visual Basic"},
		{L_VISUALPROLOG, "Visual Prolog"}, {L_XML, "XML"}, {L_YAML, "YAML"},
	};
	return m;
}

// ---------------------------------------------------------------------------

int MppParseHexColor(const char *s)
{
	if (!s || !*s)
		return 0;
	unsigned long v = strtoul(s, nullptr, 16);
	const int r = (v >> 16) & 0xFF, g = (v >> 8) & 0xFF, b = v & 0xFF;
	return r | (g << 8) | (b << 16);
}

NSColor *MppColorFromSci(int c)
{
	return [NSColor colorWithSRGBRed:(c & 0xFF) / 255.0
	                           green:((c >> 8) & 0xFF) / 255.0
	                            blue:((c >> 16) & 0xFF) / 255.0
	                           alpha:1.0];
}

int MppSciFromColor(NSColor *color)
{
	NSColor *c = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	if (!c)
		return 0;
	const int r = (int)lround(c.redComponent * 255), g = (int)lround(c.greenComponent * 255),
	          b = (int)lround(c.blueComponent * 255);
	return r | (g << 8) | (b << 16);
}

const MppStyle *MppLexerStyler::findByID(int id) const
{
	for (const auto &s : styles)
		if (s.styleID == id)
			return &s;
	return nullptr;
}

const MppStyle *MppLexerStyler::findByName(const std::string &n) const
{
	for (const auto &s : styles)
		if (s.name == n)
			return &s;
	return nullptr;
}

const MppLexerStyler *MppTheme::lexer(const std::string &name) const
{
	auto it = lexers.find(name);
	return it == lexers.end() ? nullptr : &it->second;
}

const MppStyle *MppTheme::global(const std::string &name) const
{
	for (const auto &s : globals)
		if (s.name == name)
			return &s;
	return nullptr;
}

const MppStyle *MppTheme::globalByID(int id) const
{
	for (const auto &s : globals)
		if (s.styleID == id)
			return &s;
	return nullptr;
}

bool MppTheme::isDark() const
{
	const MppStyle *def = global("Default Style");
	if (!def)
		return false;
	const int c = def->bgColor;
	const int lum = ((c & 0xFF) * 299 + ((c >> 8) & 0xFF) * 587 + ((c >> 16) & 0xFF) * 114) / 1000;
	return lum < 110;
}

static int keywordClassFromName(const char *str)
{
	if (!str)
		return -1;
	static const char *names[] = {"instre1", "instre2", "type1", "type2", "type3", "type4", "type5",
	                              "type6", "type7", "substyle1", "substyle2", "substyle3", "substyle4",
	                              "substyle5", "substyle6", "substyle7", "substyle8"};
	for (int i = 0; i < NB_LIST; ++i)
		if (strcmp(str, names[i]) == 0)
			return i;
	if (str[0] >= '0' && str[0] <= '8' && str[1] == '\0')
		return str[0] - '0';
	return -1;
}

static std::string attr(NSXMLElement *e, NSString *name)
{
	NSString *v = [[e attributeForName:name] stringValue];
	return v ? std::string(v.UTF8String) : std::string();
}

static bool hasAttr(NSXMLElement *e, NSString *name)
{
	return [e attributeForName:name] != nil;
}

static MppStyle parseStyle(NSXMLElement *e)
{
	MppStyle s;
	NSString *idStr = [[e attributeForName:@"styleID"] stringValue];
	s.styleID = idStr ? idStr.intValue : -1;
	s.name = attr(e, @"name");
	int colorStyle = 0;
	if (hasAttr(e, @"fgColor")) {
		s.fgColor = MppParseHexColor(attr(e, @"fgColor").c_str());
		colorStyle |= COLORSTYLE_FOREGROUND;
	}
	if (hasAttr(e, @"bgColor")) {
		s.bgColor = MppParseHexColor(attr(e, @"bgColor").c_str());
		colorStyle |= COLORSTYLE_BACKGROUND;
	}
	if (hasAttr(e, @"colorStyle"))
		colorStyle &= [[[e attributeForName:@"colorStyle"] stringValue] intValue];
	s.colorStyle = colorStyle;
	s.fontName = attr(e, @"fontName");
	std::string fs = attr(e, @"fontStyle");
	s.fontStyle = fs.empty() ? -1 : atoi(fs.c_str());
	std::string sz = attr(e, @"fontSize");
	s.fontSize = sz.empty() ? -1 : atoi(sz.c_str());
	std::string kw = attr(e, @"keywordClass");
	s.keywordClass = kw.empty() ? -1 : keywordClassFromName(kw.c_str());
	NSString *text = [e stringValue];
	if (text.length)
		s.keywords = text.UTF8String;
	return s;
}

static NSXMLDocument *openXML(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data)
		return nil;
	NSError *err = nil;
	NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:&err];
	if (!doc)
		NSLog(@"Macpad++: cannot parse %@: %@", path, err);
	return doc;
}

static bool parseStylers(NSString *path, MppTheme &theme)
{
	NSXMLDocument *doc = openXML(path);
	if (!doc)
		return false;
	theme.path = path.UTF8String;
	for (NSXMLElement *lt in [doc nodesForXPath:@"/*/LexerStyles/LexerType" error:nil]) {
		MppLexerStyler ls;
		ls.name = attr(lt, @"name");
		ls.desc = attr(lt, @"desc");
		ls.userExt = attr(lt, @"ext");
		for (NSXMLElement *ws in [lt elementsForName:@"WordsStyle"])
			ls.styles.push_back(parseStyle(ws));
		theme.lexers[ls.name] = ls;
	}
	for (NSXMLElement *ws in [doc nodesForXPath:@"/*/GlobalStyles/WidgetStyle" error:nil])
		theme.globals.push_back(parseStyle(ws));
	return true;
}

// Themes are completed with the model's styles (with theme default colours) when a
// lexer or a style is missing in the theme file.
static void completeThemeWithModel(MppTheme &theme, const MppTheme &model)
{
	const MppStyle *def = theme.global("Default Style");
	const int defFg = def ? def->fgColor : 0;
	const int defBg = def ? def->bgColor : 0xFFFFFF;

	for (const auto &kv : model.lexers) {
		auto it = theme.lexers.find(kv.first);
		if (it == theme.lexers.end()) {
			MppLexerStyler copy = kv.second;
			for (auto &s : copy.styles) {
				s.fgColor = defFg;
				s.bgColor = defBg;
			}
			theme.lexers[kv.first] = copy;
		} else {
			for (const auto &ms : kv.second.styles) {
				if (!it->second.findByID(ms.styleID)) {
					MppStyle s = ms;
					s.fgColor = defFg;
					s.bgColor = defBg;
					it->second.styles.push_back(s);
				}
			}
		}
	}
	for (const auto &mg : model.globals) {
		if (!theme.global(mg.name))
			theme.globals.push_back(mg);
	}
}

// ---------------------------------------------------------------------------

@implementation MppLanguages {
	NSString *_resourceDir;
	std::vector<MppLangDef> _langs;            // indexed by order in langs.xml
	std::map<int, size_t> _langIndexByType;    // MppLangType -> _langs index
	MppTheme _model;
	MppTheme _theme;
	NSString *_currentThemeName;
}

+ (instancetype)shared
{
	static MppLanguages *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[MppLanguages alloc] init]; });
	return s;
}

static MppLangType langTypeFromName(const std::string &name)
{
	for (int i = 0; i <= L_EXTERNAL; ++i)
		if (name == g_mppLangNameInfo[i].langName)
			return (MppLangType)i;
	return L_EXTERNAL;
}

- (void)loadFromDirectory:(NSString *)resourceDir
{
	_resourceDir = resourceDir;

	NSString *langsPath = [MppPaths userFileOrBundled:@"langs.xml"];
	NSXMLDocument *doc = openXML(langsPath);
	for (NSXMLElement *le in [doc nodesForXPath:@"/*/Languages/Language" error:nil]) {
		MppLangDef def;
		def.name = attr(le, @"name");
		NSString *ext = [[le attributeForName:@"ext"] stringValue];
		for (NSString *e in [ext componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
			if (e.length)
				def.exts.push_back(e.lowercaseString.UTF8String);
		def.commentLine = attr(le, @"commentLine");
		def.commentStart = attr(le, @"commentStart");
		def.commentEnd = attr(le, @"commentEnd");
		std::string ts = attr(le, @"tabSettings");
		if (!ts.empty())
			def.tabSettings = atoi(ts.c_str());
		for (NSXMLElement *kw in [le elementsForName:@"Keywords"]) {
			int idx = keywordClassFromName(attr(kw, @"name").c_str());
			if (idx >= 0) {
				NSString *v = kw.stringValue ?: @"";
				def.keywords[idx] = v.UTF8String;
				def.hasKeywords[idx] = true;
			}
		}
		MppLangType t = langTypeFromName(def.name);
		_langs.push_back(def);
		if (t != L_EXTERNAL)
			_langIndexByType[t] = _langs.size() - 1;
	}

	parseStylers([resourceDir stringByAppendingPathComponent:@"stylers.xml"], _model);
	_theme = _model;
	_currentThemeName = @"Default (stylers.xml)";
}

- (BOOL)loadThemeAtPath:(NSString *)path
{
	NSString *bundledDefault = [_resourceDir stringByAppendingPathComponent:@"stylers.xml"];
	MppTheme t;
	if (!path || [path isEqualToString:bundledDefault]) {
		NSString *userStylers = [MppPaths.userDataDirectory stringByAppendingPathComponent:@"stylers.xml"];
		if ([NSFileManager.defaultManager fileExistsAtPath:userStylers] && parseStylers(userStylers, t)) {
			completeThemeWithModel(t, _model);
			_theme = t;
		} else {
			_theme = _model;
		}
		_currentThemeName = @"Default (stylers.xml)";
		return YES;
	}
	if (!parseStylers(path, t))
		return NO;
	completeThemeWithModel(t, _model);
	_theme = t;
	_currentThemeName = path.lastPathComponent.stringByDeletingPathExtension;
	return YES;
}

- (MppTheme *)theme
{
	return &_theme;
}

- (const MppLangDef *)langDefForType:(MppLangType)type
{
	auto it = _langIndexByType.find(type);
	return it == _langIndexByType.end() ? nullptr : &_langs[it->second];
}

- (const char *)wordListForLang:(MppLangType)type index:(int)index
{
	const MppLangDef *d = [self langDefForType:type];
	if (!d || index < 0 || index >= NB_LIST || !d->hasKeywords[index])
		return nullptr;
	return d->keywords[index].c_str();
}

static bool isInList(const std::string &ext, const std::string &list)
{
	NSArray *items = [[NSString stringWithUTF8String:list.c_str()] componentsSeparatedByString:@" "];
	NSString *e = [NSString stringWithUTF8String:ext.c_str()];
	for (NSString *i in items)
		if (i.length && [i caseInsensitiveCompare:e] == NSOrderedSame)
			return true;
	return false;
}

- (MppLangType)langTypeForExtension:(NSString *)extension
{
	const std::string ext = extension.lowercaseString.UTF8String;
	// user defined extensions for styles first
	for (const auto &kv : _theme.lexers)
		if (!kv.second.userExt.empty() && isInList(ext, kv.second.userExt)) {
			MppLangType t = langTypeFromName(kv.first);
			if (t != L_EXTERNAL)
				return t;
		}
	// then language default extensions; the list is scanned backwards
	for (size_t i = _langs.size(); i-- > 0;) {
		const auto &l = _langs[i];
		if (std::find(l.exts.begin(), l.exts.end(), ext) != l.exts.end()) {
			MppLangType t = langTypeFromName(l.name);
			if (t != L_EXTERNAL)
				return t;
		}
	}
	return L_TEXT;
}

- (MppLangType)langTypeForFileName:(NSString *)fileName
{
	NSString *name = fileName.lastPathComponent;
	NSString *ext = name.pathExtension;
	MppLangType t = L_TEXT;
	if (ext.length && !(name.length == ext.length + 1)) // ".zshrc" has no extension in our sense
		t = [self langTypeForExtension:ext];

	if (t == L_TEXT) {
		NSString *lower = name.lowercaseString;
		if ([lower isEqualToString:@"makefile"] || [lower isEqualToString:@"gnumakefile"])
			t = L_MAKEFILE;
		else if ([lower isEqualToString:@"cmakelists.txt"])
			t = L_CMAKE;
		else if ([lower isEqualToString:@"sconstruct"] || [lower isEqualToString:@"sconscript"] ||
		         [lower isEqualToString:@"wscript"])
			t = L_PYTHON;
		else if ([lower isEqualToString:@"rakefile"] || [lower isEqualToString:@"vagrantfile"] ||
		         [lower isEqualToString:@"gemfile"] || [lower isEqualToString:@"podfile"] ||
		         [lower isEqualToString:@"brewfile"])
			t = L_RUBY;
		else if ([lower isEqualToString:@"crontab"] || [lower isEqualToString:@"pkgbuild"] ||
		         [lower isEqualToString:@"apkbuild"])
			t = L_BASH;
		// macOS/Unix shell dotfiles
		else if ([@[@".zshrc", @".zprofile", @".zshenv", @".zlogin", @".bashrc", @".bash_profile",
		            @".profile", @".bash_aliases", @".bash_logout"] containsObject:lower])
			t = L_BASH;
		else if ([lower isEqualToString:@".gitconfig"] || [lower isEqualToString:@".editorconfig"])
			t = L_INI;
	}
	return t;
}

- (MppLangType)langTypeFromTextBeginning:(const unsigned char *)data length:(size_t)dataLen
{
	if (dataLen <= 3)
		return L_TEXT;
	size_t i = 0;
	if ((data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) ||
	    (data[0] == 0xFE && data[1] == 0xFF && data[2] == 0x00) ||
	    (data[0] == 0xFF && data[1] == 0xFE && data[2] == 0x00))
		i += 3;
	for (; i < dataLen; ++i)
		if (data[i] != ' ' && data[i] != '\t' && data[i] != '\n' && data[i] != '\r')
			break;
	if (i == dataLen)
		return L_TEXT;

	const size_t longestLength = std::min<size_t>(40, dataLen - i);
	std::string buf2Test((const char *)data + i, longestLength);
	const size_t crnl = std::min(buf2Test.find('\r'), buf2Test.find('\n'));
	if (crnl != std::string::npos)
		buf2Test.resize(crnl);

	if (buf2Test.rfind("#!", 0) == 0) {
		static const std::pair<const char *, MppLangType> shebang[] = {
			{"sh", L_BASH}, {"python", L_PYTHON}, {"perl", L_PERL}, {"php", L_PHP},
			{"ruby", L_RUBY}, {"node", L_JAVASCRIPT}};
		for (const auto &p : shebang)
			if (buf2Test.find(p.first) != std::string::npos)
				return p.second;
		return L_TEXT;
	}
	static const std::pair<const char *, MppLangType> firstLine[] = {
		{"<?xml", L_XML}, {"<?php", L_PHP}, {"<html", L_HTML}, {"<!DOCTYPE html", L_HTML}, {"<?", L_PHP}};
	for (const auto &p : firstLine)
		if (buf2Test.rfind(p.first, 0) == 0)
			return p.second;
	return L_TEXT;
}

- (NSArray<NSString *> *)themeNames
{
	NSMutableArray *names = [NSMutableArray arrayWithObject:@"Default (stylers.xml)"];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSString *dir in @[[MppPaths.userDataDirectory stringByAppendingPathComponent:@"themes"],
	                        [_resourceDir stringByAppendingPathComponent:@"themes"]]) {
		for (NSString *f in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil]
		         sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
			if (![f.pathExtension.lowercaseString isEqualToString:@"xml"])
				continue;
			NSString *n = f.stringByDeletingPathExtension;
			if (![seen containsObject:n]) {
				[seen addObject:n];
				[names addObject:n];
			}
		}
	}
	return names;
}

- (NSString *)pathForThemeName:(NSString *)name
{
	if (!name.length || [name hasPrefix:@"Default ("])
		return nil;
	NSString *file = [name stringByAppendingPathExtension:@"xml"];
	NSString *user = [[MppPaths.userDataDirectory stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:file];
	if ([NSFileManager.defaultManager fileExistsAtPath:user])
		return user;
	NSString *bundled = [[_resourceDir stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:file];
	if ([NSFileManager.defaultManager fileExistsAtPath:bundled])
		return bundled;
	return nil;
}

- (NSString *)currentThemeName
{
	return _currentThemeName;
}

- (std::vector<MppLangType>)menuLanguages
{
	std::vector<MppLangType> v;
	for (const auto &kv : menuNames())
		if (kv.first != L_TEXT)
			v.push_back((MppLangType)kv.first);
	std::sort(v.begin(), v.end(), [](MppLangType a, MppLangType b) {
		return strcasecmp(menuNames().at(a), menuNames().at(b)) < 0;
	});
	return v;
}

+ (NSString *)menuNameForLang:(MppLangType)type
{
	auto it = menuNames().find(type);
	if (it != menuNames().end())
		return @(it->second);
	return @(g_mppLangNameInfo[type].shortName);
}

+ (NSString *)shortNameForLang:(MppLangType)type
{
	return @(g_mppLangNameInfo[type].shortName);
}

+ (NSString *)longNameForLang:(MppLangType)type
{
	return @(g_mppLangNameInfo[type].longName);
}

@end
