// Language and style model for Macpad++ macOS.
// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
// Defines the language table and parses the very same
// langs.xml / stylers.xml / theme files that the Windows version uses.

#pragma once

#import <Cocoa/Cocoa.h>
#include <string>
#include <vector>
#include <map>

// The order of this enum must not change: the values are stored in sessions and theme files
enum MppLangType : int {
	L_TEXT, L_PHP, L_C, L_CPP, L_CS, L_OBJC, L_JAVA, L_RC,
	L_HTML, L_XML, L_MAKEFILE, L_PASCAL, L_BATCH, L_INI, L_ASCII, L_USER,
	L_ASP, L_SQL, L_VB, L_JS_EMBEDDED, L_CSS, L_PERL, L_PYTHON, L_LUA,
	L_TEX, L_FORTRAN, L_BASH, L_FLASH, L_NSIS, L_TCL, L_LISP, L_SCHEME,
	L_ASM, L_DIFF, L_PROPS, L_PS, L_RUBY, L_SMALLTALK, L_VHDL, L_KIX, L_AU3,
	L_CAML, L_ADA, L_VERILOG, L_MATLAB, L_HASKELL, L_INNO, L_SEARCHRESULT,
	L_CMAKE, L_YAML, L_COBOL, L_GUI4CLI, L_D, L_POWERSHELL, L_R, L_JSP,
	L_COFFEESCRIPT, L_JSON, L_JAVASCRIPT, L_FORTRAN_77, L_BAANC, L_SREC,
	L_IHEX, L_TEHEX, L_SWIFT, L_ASN1, L_AVS, L_BLITZBASIC, L_PUREBASIC,
	L_FREEBASIC, L_CSOUND, L_ERLANG, L_ESCRIPT, L_FORTH, L_LATEX, L_MMIXAL,
	L_NIM, L_NNCRONTAB, L_OSCRIPT, L_REBOL, L_REGISTRY, L_RUST, L_SPICE,
	L_TXT2TAGS, L_VISUALPROLOG, L_TYPESCRIPT, L_JSON5, L_MSSQL, L_GDSCRIPT,
	L_HOLLYWOOD, L_GOLANG, L_RAKU, L_TOML, L_SAS, L_ERRORLIST, L_ESCSEQ, L_STTXT,
	L_EXTERNAL
};

struct MppLangNameInfo {
	const char *langName;   // name used in langs.xml / stylers.xml
	const char *shortName;  // shown in the status bar
	const char *longName;   // shown in the status bar as file type description
	MppLangType langID;
	const char *lexerID;    // Lexilla lexer name
};

extern const MppLangNameInfo g_mppLangNameInfo[L_EXTERNAL + 1];

// Keyword list indexes (index of the <Keywords> lists in langs.xml)
enum {
	LANG_INDEX_INSTR = 0, LANG_INDEX_INSTR2, LANG_INDEX_TYPE, LANG_INDEX_TYPE2, LANG_INDEX_TYPE3,
	LANG_INDEX_TYPE4, LANG_INDEX_TYPE5, LANG_INDEX_TYPE6, LANG_INDEX_TYPE7,
	LANG_INDEX_SUBSTYLE1, LANG_INDEX_SUBSTYLE2, LANG_INDEX_SUBSTYLE3, LANG_INDEX_SUBSTYLE4,
	LANG_INDEX_SUBSTYLE5, LANG_INDEX_SUBSTYLE6, LANG_INDEX_SUBSTYLE7, LANG_INDEX_SUBSTYLE8,
	NB_LIST = 17
};

enum { FONTSTYLE_BOLD = 1, FONTSTYLE_ITALIC = 2, FONTSTYLE_UNDERLINE = 4 };
enum { COLORSTYLE_FOREGROUND = 1, COLORSTYLE_BACKGROUND = 2, COLORSTYLE_ALL = 3 };

struct MppStyle {
	int styleID = -1;
	std::string name;
	int fgColor = 0;        // Scintilla colour (0x00BBGGRR)
	int bgColor = 0xFFFFFF;
	int colorStyle = 0;     // which of fg/bg are set
	std::string fontName;
	int fontStyle = -1;     // FONTSTYLE_* bits, -1 = not set
	int fontSize = -1;
	int keywordClass = -1;
	std::string keywords;   // user keywords stored in stylers.xml
};

struct MppLexerStyler {
	std::string name;
	std::string desc;
	std::string userExt;
	std::vector<MppStyle> styles;

	const MppStyle *findByID(int id) const;
	const MppStyle *findByName(const std::string &n) const;
};

struct MppTheme {
	std::string path;
	std::map<std::string, MppLexerStyler> lexers;
	std::vector<MppLexerStyler *> lexerOrder;
	std::vector<MppStyle> globals;

	const MppLexerStyler *lexer(const std::string &name) const;
	const MppStyle *global(const std::string &name) const;
	const MppStyle *globalByID(int id) const;   // first global style with this (non-zero) ID
	bool isDark() const;                        // Default Style background is dark
};

struct MppLangDef {
	std::string name;
	std::vector<std::string> exts;
	std::string commentLine, commentStart, commentEnd;
	int tabSettings = -1;   // (useSpaces ? 128 : 0) | tabSize, -1 = use global setting
	std::string keywords[NB_LIST];
	bool hasKeywords[NB_LIST] = {};
};

// Parses a hex colour string "RRGGBB" into a Scintilla colour (0x00BBGGRR)
int MppParseHexColor(const char *s);
NSColor *MppColorFromSci(int sciColor);
int MppSciFromColor(NSColor *color);

@interface MppLanguages : NSObject

+ (instancetype)shared;

- (void)loadFromDirectory:(NSString *)resourceDir;
- (BOOL)loadThemeAtPath:(NSString *)path;   // replace current theme
- (MppTheme *)theme;
- (const MppLangDef *)langDefForType:(MppLangType)type;
- (const char *)wordListForLang:(MppLangType)type index:(int)index;

// Detection
- (MppLangType)langTypeForFileName:(NSString *)fileName;
- (MppLangType)langTypeFromTextBeginning:(const unsigned char *)data length:(size_t)len;

// Themes available: display name -> path. "Default (stylers.xml)" is always first.
- (NSArray<NSString *> *)themeNames;
- (NSString *)pathForThemeName:(NSString *)name;
- (NSString *)currentThemeName;

// For the Language menu: lang types sorted by menu name (excludes internal ones)
- (std::vector<MppLangType>)menuLanguages;
+ (NSString *)menuNameForLang:(MppLangType)type;
+ (NSString *)shortNameForLang:(MppLangType)type;
+ (NSString *)longNameForLang:(MppLangType)type;

@end
