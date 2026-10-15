// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppStyler.h"
#import "MppPrefs.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "rgba_icons.h"

#include <string>

namespace {

// Keyword list masks (LIST_0 .. LIST_8 in ScintillaEditView.h)
enum : int {
	LIST_NONE = 0, LIST_0 = 1, LIST_1 = 2, LIST_2 = 4, LIST_3 = 8, LIST_4 = 16,
	LIST_5 = 32, LIST_6 = 64, LIST_7 = 128, LIST_8 = 256
};

constexpr int STYLE_NOT_USED = -1;

class Styler {
public:
	explicit Styler(ScintillaView *v) : _v(v), _theme([MppLanguages.shared theme]) {}

	sptr_t exec(unsigned int msg, uptr_t w = 0, sptr_t l = 0) const { return [_v message:msg wParam:w lParam:l]; }
	void prop(const char *key, const char *value) const { exec(SCI_SETPROPERTY, (uptr_t)key, (sptr_t)value); }

	// ---- styles -----------------------------------------------------------
	void setSpecialStyle(const MppStyle &s) const
	{
		const int id = s.styleID;
		if (s.colorStyle & COLORSTYLE_FOREGROUND)
			exec(SCI_STYLESETFORE, id, s.fgColor);
		if (s.colorStyle & COLORSTYLE_BACKGROUND)
			exec(SCI_STYLESETBACK, id, s.bgColor);
		if (!s.fontName.empty()) {
			NSString *f = @(s.fontName.c_str());
			if (![NSFont fontWithName:f size:12])
				f = [MppStyler effectiveFontName];
			exec(SCI_STYLESETFONT, id, (sptr_t)f.UTF8String);
		}
		if (s.fontStyle != STYLE_NOT_USED) {
			exec(SCI_STYLESETBOLD, id, (s.fontStyle & FONTSTYLE_BOLD) != 0);
			exec(SCI_STYLESETITALIC, id, (s.fontStyle & FONTSTYLE_ITALIC) != 0);
			exec(SCI_STYLESETUNDERLINE, id, (s.fontStyle & FONTSTYLE_UNDERLINE) != 0);
		}
		if (s.fontSize > 0)
			exec(SCI_STYLESETSIZE, id, s.fontSize);
	}

	void setStyle(const MppStyle &s) const
	{
		if (s.styleID < 0 || s.styleID > STYLE_MAX)
			return;
		MppStyle copy = s;
		// When the macOS editor font is in use, keep a single font/size across all styles
		if ([MppPrefs shared].useMacFont) {
			copy.fontName.clear();
			copy.fontSize = -1;
		}
		setSpecialStyle(copy);
	}

	// makeStyle: apply every style of a lexer styler and collect the user keywords
	void makeStyle(MppLangType lang, const char **kwArray = nullptr) const
	{
		const MppLexerStyler *ls = _theme->lexer(g_mppLangNameInfo[lang].langName);
		if (!ls)
			return;
		for (const auto &s : ls->styles) {
			setStyle(s);
			if (kwArray && s.keywordClass >= 0 && s.keywordClass < NB_LIST && !s.keywords.empty())
				kwArray[s.keywordClass] = s.keywords.c_str();
		}
	}

	// ---- keywords ---------------------------------------------------------
	std::string concat(const char *userWords, MppLangType lang, int index) const
	{
		std::string kwl = userWords ? userWords : "";
		kwl += " ";
		const char *def = [MppLanguages.shared wordListForLang:lang index:index];
		if (def)
			kwl += def;
		return kwl;
	}

	void setKeywords(MppLangType lang, const char *userWords, int index) const
	{
		std::string wl = concat(userWords, lang, index);
		exec(SCI_SETKEYWORDS, index, (sptr_t)wl.c_str());
	}

	void setKeywordsAt(int sciIndex, MppLangType lang, const char *userWords, int index) const
	{
		std::string wl = concat(userWords, lang, index);
		exec(SCI_SETKEYWORDS, sciIndex, (sptr_t)wl.c_str());
	}

	void populateSubStyleKeywords(MppLangType lang, int baseStyleID, int numSubStyles, int firstLangIndex, const char **kwArray) const
	{
		const int firstID = (int)(exec(SCI_ALLOCATESUBSTYLES, baseStyleID, numSubStyles) & 0xFF);
		if (kwArray && firstID >= 0) {
			for (int i = 0; i < numSubStyles; i++) {
				const int ss = firstLangIndex + i;
				std::string words = concat(kwArray[ss], lang, ss);
				exec(SCI_SETIDENTIFIERS, firstID + i, (sptr_t)words.c_str());
			}
		}
	}

	bool setLexerFromLangID(MppLangType lang) const
	{
		if (lang >= L_EXTERNAL)
			return false;
		exec(SCI_SETILEXER, 0, (sptr_t)CreateLexer(g_mppLangNameInfo[lang].lexerID));
		return true;
	}

	void setLexer(MppLangType lang, int whichList, int baseStyleID = STYLE_NOT_USED, int numSubStyles = 8) const
	{
		setLexerFromLangID(lang);
		const char *kw[NB_LIST] = {};
		makeStyle(lang, kw);
		for (int i = 0; i <= 8; ++i)
			if (whichList & (1 << i))
				setKeywords(lang, kw[i], i);
		if (baseStyleID != STYLE_NOT_USED)
			populateSubStyleKeywords(lang, baseStyleID, numSubStyles, LANG_INDEX_SUBSTYLE1, kw);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
	}

	// ---- complex lexers ---------------------------------------------------
	void setCppLexer(MppLangType lang) const
	{
		setLexerFromLangID(L_CPP);
		if (lang == L_GOLANG)
			prop("lexer.cpp.backquoted.strings", "1");
		if (lang != L_RC) {
			const char *doxygen = [MppLanguages.shared wordListForLang:L_CPP index:LANG_INDEX_TYPE2];
			if (doxygen)
				exec(SCI_SETKEYWORDS, 2, (sptr_t)doxygen);
		}
		const char *kw[NB_LIST] = {};
		makeStyle(lang, kw);
		setKeywordsAt(0, lang, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(1, lang, kw[LANG_INDEX_TYPE], LANG_INDEX_TYPE);
		setKeywordsAt(3, lang, kw[LANG_INDEX_INSTR2], LANG_INDEX_INSTR2);
		populateSubStyleKeywords(lang, SCE_C_IDENTIFIER, 8, LANG_INDEX_SUBSTYLE1, kw);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
		prop("fold.cpp.comment.explicit", "0");
		prop("fold.preprocessor", "1");
		prop("lexer.cpp.track.preprocessor", "0");
	}

	void setJsLexer() const
	{
		const char *doxygen = [MppLanguages.shared wordListForLang:L_CPP index:LANG_INDEX_TYPE2];
		setLexerFromLangID(L_JAVASCRIPT);
		const char *kw[NB_LIST] = {};
		makeStyle(L_JAVASCRIPT, kw);
		if (doxygen)
			exec(SCI_SETKEYWORDS, 2, (sptr_t)doxygen);
		setKeywordsAt(0, L_JAVASCRIPT, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(1, L_JAVASCRIPT, kw[LANG_INDEX_TYPE], LANG_INDEX_TYPE);
		setKeywordsAt(3, L_JAVASCRIPT, kw[LANG_INDEX_INSTR2], LANG_INDEX_INSTR2);
		populateSubStyleKeywords(L_JAVASCRIPT, SCE_C_IDENTIFIER, 8, LANG_INDEX_SUBSTYLE1, kw);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
		prop("fold.cpp.comment.explicit", "0");
		prop("fold.preprocessor", "1");
		prop("lexer.cpp.track.preprocessor", "0");
		prop("lexer.cpp.backquoted.strings", "2");
	}

	void setTypeScriptLexer() const
	{
		const char *doxygen = [MppLanguages.shared wordListForLang:L_CPP index:LANG_INDEX_TYPE2];
		setLexerFromLangID(L_TYPESCRIPT);
		if (doxygen)
			exec(SCI_SETKEYWORDS, 2, (sptr_t)doxygen);
		const char *kw[NB_LIST] = {};
		makeStyle(L_TYPESCRIPT, kw);
		setKeywordsAt(0, L_TYPESCRIPT, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(1, L_TYPESCRIPT, kw[LANG_INDEX_TYPE], LANG_INDEX_TYPE);
		populateSubStyleKeywords(L_TYPESCRIPT, SCE_C_IDENTIFIER, 8, LANG_INDEX_SUBSTYLE1, kw);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
		prop("fold.cpp.comment.explicit", "0");
		prop("fold.preprocessor", "1");
		prop("lexer.cpp.track.preprocessor", "0");
		prop("lexer.cpp.backquoted.strings", "1");
	}

	void setObjCLexer(MppLangType lang) const
	{
		setLexerFromLangID(L_OBJC);
		const char *kw[NB_LIST] = {};
		makeStyle(lang, kw);
		const char *doxygen = [MppLanguages.shared wordListForLang:L_CPP index:LANG_INDEX_TYPE2];
		setKeywordsAt(0, lang, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(1, lang, kw[LANG_INDEX_TYPE], LANG_INDEX_TYPE);
		exec(SCI_SETKEYWORDS, 2, (sptr_t)(doxygen ? doxygen : ""));
		setKeywordsAt(3, lang, kw[LANG_INDEX_INSTR2], LANG_INDEX_INSTR2);
		setKeywordsAt(4, lang, kw[LANG_INDEX_TYPE2], LANG_INDEX_TYPE2);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
		prop("fold.cpp.comment.explicit", "0");
		prop("fold.preprocessor", "1");
	}

	void setTclLexer() const
	{
		setLexerFromLangID(L_TCL);
		const char *kw[NB_LIST] = {};
		makeStyle(L_TCL, kw);
		// Scintilla list index -> keyword class
		const int map[9] = {LANG_INDEX_INSTR, LANG_INDEX_TYPE, LANG_INDEX_INSTR2, LANG_INDEX_TYPE2,
		                    LANG_INDEX_TYPE3, LANG_INDEX_TYPE4, LANG_INDEX_TYPE5, LANG_INDEX_TYPE6, LANG_INDEX_TYPE7};
		for (int i = 0; i < 9; ++i)
			setKeywordsAt(i, L_TCL, kw[map[i]], map[i]);
	}

	void setHTMLLexer() const
	{
		const char *kw[NB_LIST] = {};
		makeStyle(L_HTML, kw);
		setKeywordsAt(0, L_HTML, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(5, L_HTML, kw[LANG_INDEX_INSTR2], LANG_INDEX_INSTR2);
		populateSubStyleKeywords(L_HTML, SCE_H_TAG, 4, LANG_INDEX_SUBSTYLE1, kw);
		populateSubStyleKeywords(L_HTML, SCE_H_ATTRIBUTE, 4, LANG_INDEX_SUBSTYLE5, kw);
	}

	void setEmbeddedJSLexer() const
	{
		const char *kw[NB_LIST] = {};
		makeStyle(L_JS_EMBEDDED, kw);
		setKeywordsAt(1, L_JS_EMBEDDED, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		populateSubStyleKeywords(L_JS_EMBEDDED, SCE_HJ_WORD, 8, LANG_INDEX_SUBSTYLE1, kw);
		exec(SCI_STYLESETEOLFILLED, SCE_HJ_DEFAULT, true);
		exec(SCI_STYLESETEOLFILLED, SCE_HJ_COMMENT, true);
		exec(SCI_STYLESETEOLFILLED, SCE_HJ_COMMENTDOC, true);
		exec(SCI_STYLESETEOLFILLED, SCE_HJ_TEMPLATELITERAL, true);
		exec(SCI_STYLESETEOLFILLED, SCE_HJA_TEMPLATELITERAL, true);
	}

	void setEmbeddedPhpLexer() const
	{
		const char *kw[NB_LIST] = {};
		makeStyle(L_PHP, kw);
		setKeywordsAt(4, L_PHP, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		populateSubStyleKeywords(L_PHP, SCE_HPHP_WORD, 8, LANG_INDEX_SUBSTYLE1, kw);
		exec(SCI_STYLESETEOLFILLED, SCE_HPHP_DEFAULT, true);
		exec(SCI_STYLESETEOLFILLED, SCE_HPHP_COMMENT, true);
	}

	void setEmbeddedAspLexer() const
	{
		const char *kw[NB_LIST] = {};
		makeStyle(L_ASP, kw);
		prop("asp.default.language", "2");
		std::string wl = concat(kw[LANG_INDEX_INSTR], L_VB, LANG_INDEX_INSTR);
		exec(SCI_SETKEYWORDS, 2, (sptr_t)wl.c_str());
		populateSubStyleKeywords(L_ASP, SCE_HB_WORD, 8, LANG_INDEX_SUBSTYLE1, kw);
		exec(SCI_STYLESETEOLFILLED, SCE_HBA_DEFAULT, true);
	}

	void setXmlLexer(MppLangType type) const
	{
		if (type == L_XML) {
			const char *kw[NB_LIST] = {};
			setLexerFromLangID(L_XML);
			makeStyle(type, kw);
			setKeywordsAt(5, L_XML, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
			populateSubStyleKeywords(type, SCE_H_ATTRIBUTE, 8, LANG_INDEX_SUBSTYLE1, kw);
			prop("lexer.xml.allow.scripts", "0");
		} else {
			setLexerFromLangID(L_HTML);
			setHTMLLexer();
			setEmbeddedJSLexer();
			setEmbeddedPhpLexer();
			setEmbeddedAspLexer();
		}
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.html", "1");
		prop("fold.hypertext.comment", "1");
	}

	void setJsonLexer(bool json5) const
	{
		setLexerFromLangID(json5 ? L_JSON5 : L_JSON);
		const char *kw[NB_LIST] = {};
		makeStyle(L_JSON, kw);
		setKeywordsAt(0, L_JSON, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		setKeywordsAt(1, L_JSON, kw[LANG_INDEX_INSTR2], LANG_INDEX_INSTR2);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("lexer.json.escape.sequence", "1");
		if (json5)
			prop("lexer.json.allow.comments", "1");
	}

	void setBashLexer() const
	{
		setLexerFromLangID(L_BASH);
		const char *kw[NB_LIST] = {};
		makeStyle(L_BASH, kw);
		setKeywords(L_BASH, kw[LANG_INDEX_INSTR], LANG_INDEX_INSTR);
		populateSubStyleKeywords(L_BASH, SCE_SH_IDENTIFIER, 4, LANG_INDEX_SUBSTYLE1, kw);
		populateSubStyleKeywords(L_BASH, SCE_SH_SCALAR, 4, LANG_INDEX_SUBSTYLE5, kw);
		prop("fold", "1");
		prop("fold.compact", "0");
		prop("fold.comment", "1");
	}

	void setAsciiLexer() const
	{
		// MS-DOS Style / ASCII art uses a dedicated font
		MppStyle nfo;
		nfo.styleID = STYLE_DEFAULT;
		nfo.fontName = "Menlo";
		const MppLexerStyler *ls = _theme->lexer("nfo");
		if (ls) {
			if (const MppStyle *d = ls->findByName("DEFAULT")) {
				nfo.fgColor = d->fgColor;
				nfo.bgColor = d->bgColor;
				nfo.colorStyle = d->colorStyle;
				if (!d->fontName.empty()) {
					nfo.fontName = d->fontName;
					nfo.fontSize = d->fontSize;
					nfo.fontStyle = d->fontStyle;
				}
			}
		}
		setSpecialStyle(nfo);
		exec(SCI_STYLECLEARALL);
		setLexerFromLangID(L_TEXT);
	}

	void setSearchResultLexer() const
	{
		exec(SCI_STYLESETEOLFILLED, SCE_SEARCHRESULT_FILE_HEADER, true);
		exec(SCI_STYLESETEOLFILLED, SCE_SEARCHRESULT_SEARCH_HEADER, true);
		setLexer(L_SEARCHRESULT, LIST_NONE);
	}

	// ---- defineDocType ----------------------------------------------------
	void defaultStyle() const
	{
		const MppStyle *def = _theme->global("Default Style");
		MppStyle s = def ? *def : MppStyle();
		s.styleID = STYLE_DEFAULT;
		s.colorStyle = COLORSTYLE_ALL;
		if ([MppPrefs shared].useMacFont || s.fontName.empty() || ![NSFont fontWithName:@(s.fontName.c_str()) size:12]) {
			s.fontName = [MppStyler effectiveFontName].UTF8String;
		}
		if ([MppPrefs shared].useMacFont || s.fontSize <= 0)
			s.fontSize = [MppStyler effectiveFontSize];
		setSpecialStyle(s);
		exec(SCI_STYLECLEARALL);
	}

	void indicators() const
	{
		struct { int id; int def; } inds[] = {
			{MPP_INDIC_FOUND_STYLE, 0x0000FF}, {MPP_INDIC_FOUND_STYLE_SMART, 0x00FF00},
			{MPP_INDIC_FOUND_STYLE_INC, 0xFF0000}, {MPP_INDIC_TAGMATCH, 0xFF0080},
			{MPP_INDIC_TAGATTR, 0x00FFFF}, {MPP_INDIC_FOUND_STYLE_EXT1, 0xFFFF00},
			{MPP_INDIC_FOUND_STYLE_EXT2, 0x0080FF}, {MPP_INDIC_FOUND_STYLE_EXT3, 0x00FFFF},
			{MPP_INDIC_FOUND_STYLE_EXT4, 0xFF0080}, {MPP_INDIC_FOUND_STYLE_EXT5, 0x008000},
		};
		for (const auto &i : inds) {
			const MppStyle *s = _theme->globalByID(i.id);
			exec(SCI_INDICSETFORE, i.id, s ? s->bgColor : i.def);
		}
	}

	void defineDocType(MppLangType lang) const
	{
		defaultStyle();
		indicators();

		switch (lang) {
			case L_C: case L_CPP: case L_JAVA: case L_RC: case L_CS: case L_FLASH: case L_SWIFT: case L_GOLANG:
				setCppLexer(lang); break;
			case L_JS_EMBEDDED: case L_JAVASCRIPT: setJsLexer(); break;
			case L_TCL: setTclLexer(); break;
			case L_OBJC: setObjCLexer(lang); break;
			case L_PHP: case L_ASP: case L_JSP: case L_HTML: case L_XML: setXmlLexer(lang); break;
			case L_JSON: setJsonLexer(false); break;
			case L_JSON5: setJsonLexer(true); break;
			case L_CSS: setLexer(L_CSS, LIST_0 | LIST_1 | LIST_4 | LIST_6); break;
			case L_LUA: setLexer(L_LUA, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6 | LIST_7, SCE_LUA_IDENTIFIER, 4); break;
			case L_MAKEFILE: setLexer(L_MAKEFILE, LIST_NONE); break;
			case L_INI: setLexer(L_INI, LIST_NONE); exec(SCI_STYLESETEOLFILLED, SCE_PROPS_SECTION, true); break;
			case L_PROPS: setLexer(L_PROPS, LIST_NONE); exec(SCI_STYLESETEOLFILLED, SCE_PROPS_SECTION, true); break;
			case L_ASCII: setAsciiLexer(); break;
			case L_SQL:
				setLexer(L_SQL, LIST_0 | LIST_1 | LIST_4);
				prop("sql.backslash.escapes", [MppPrefs shared].backslashEscapeSQL ? "1" : "0");
				break;
			case L_MSSQL: setLexer(L_MSSQL, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_VB: setLexer(L_VB, LIST_0); break;
			case L_PASCAL: setLexer(L_PASCAL, LIST_0); prop("fold.preprocessor", "1"); break;
			case L_PERL: setLexer(L_PERL, LIST_0); break;
			case L_PYTHON:
				setLexer(L_PYTHON, LIST_0 | LIST_1, SCE_P_IDENTIFIER);
				prop("fold.quotes.python", "1");
				prop("lexer.python.decorator.attributes", "1");
				prop("lexer.python.identifier.attributes", "1");
				break;
			case L_GDSCRIPT:
				setLexer(L_GDSCRIPT, LIST_0 | LIST_1, SCE_GD_IDENTIFIER);
				prop("lexer.gdscript.keywords2.no.sub.identifiers", "1");
				prop("lexer.gdscript.whinge.level", "1");
				break;
			case L_BATCH: setLexer(L_BATCH, LIST_0); break;
			case L_TEX:
				for (int i = 0; i < 4; ++i)
					exec(SCI_SETKEYWORDS, i, (sptr_t)"");
				setLexer(L_TEX, LIST_NONE);
				break;
			case L_NSIS: setLexer(L_NSIS, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_BASH: setBashLexer(); break;
			case L_FORTRAN: setLexer(L_FORTRAN, LIST_0 | LIST_1 | LIST_2); break;
			case L_FORTRAN_77: setLexer(L_FORTRAN_77, LIST_0 | LIST_1 | LIST_2); break;
			case L_LISP: setLexer(L_LISP, LIST_0 | LIST_1); break;
			case L_SCHEME: setLexer(L_SCHEME, LIST_0 | LIST_1); break;
			case L_ASM:
				setLexer(L_ASM, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6 | LIST_7);
				prop("fold.asm.syntax.based", "1");
				prop("fold.asm.comment.multiline", "1");
				prop("fold.asm.comment.explicit", "1");
				break;
			case L_DIFF: setLexer(L_DIFF, LIST_NONE); break;
			case L_PS: setLexer(L_PS, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_RUBY: setLexer(L_RUBY, LIST_0); exec(SCI_STYLESETEOLFILLED, SCE_RB_POD, true); break;
			case L_SMALLTALK: setLexer(L_SMALLTALK, LIST_0); break;
			case L_VHDL: setLexer(L_VHDL, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6); break;
			case L_KIX: setLexer(L_KIX, LIST_0 | LIST_1 | LIST_2); break;
			case L_AU3: setLexer(L_AU3, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6); prop("fold.preprocessor", "1"); break;
			case L_CAML: setLexer(L_CAML, LIST_0 | LIST_1 | LIST_2); break;
			case L_ADA: setLexer(L_ADA, LIST_0); break;
			case L_VERILOG: setLexer(L_VERILOG, LIST_0 | LIST_1); prop("fold.preprocessor", "1"); break;
			case L_MATLAB: setLexer(L_MATLAB, LIST_0); break;
			case L_HASKELL: setLexer(L_HASKELL, LIST_0); break;
			case L_INNO: setLexer(L_INNO, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_CMAKE: setLexer(L_CMAKE, LIST_0 | LIST_1 | LIST_2); break;
			case L_YAML: setLexer(L_YAML, LIST_0); break;
			case L_COBOL: setLexer(L_COBOL, LIST_0 | LIST_1 | LIST_2); break;
			case L_GUI4CLI: setLexer(L_GUI4CLI, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4); break;
			case L_D: setLexer(L_D, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6); break;
			case L_POWERSHELL: setLexer(L_POWERSHELL, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_R: setLexer(L_R, LIST_0 | LIST_1 | LIST_2); break;
			case L_COFFEESCRIPT: setLexer(L_COFFEESCRIPT, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_BAANC:
				setLexer(L_BAANC, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6 | LIST_7 | LIST_8);
				prop("lexer.baan.styling.within.preprocessor", "1");
				prop("fold.preprocessor", "1");
				prop("fold.baan.syntax.based", "1");
				prop("fold.baan.keywords.based", "1");
				prop("fold.baan.sections", "1");
				prop("fold.baan.inner.level", "1");
				break;
			case L_SREC: setLexer(L_SREC, LIST_NONE); break;
			case L_IHEX: setLexer(L_IHEX, LIST_NONE); break;
			case L_TEHEX: setLexer(L_TEHEX, LIST_NONE); break;
			case L_ASN1: setLexer(L_ASN1, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_AVS: setLexer(L_AVS, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_BLITZBASIC: setLexer(L_BLITZBASIC, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_PUREBASIC: setLexer(L_PUREBASIC, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_FREEBASIC: setLexer(L_FREEBASIC, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_CSOUND: setLexer(L_CSOUND, LIST_0 | LIST_1 | LIST_2); break;
			case L_ERLANG: setLexer(L_ERLANG, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_ESCRIPT: setLexer(L_ESCRIPT, LIST_0 | LIST_1 | LIST_2); break;
			case L_FORTH: setLexer(L_FORTH, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_LATEX: setLexer(L_LATEX, LIST_NONE); break;
			case L_MMIXAL: setLexer(L_MMIXAL, LIST_0 | LIST_1 | LIST_2); break;
			case L_NIM: setLexer(L_NIM, LIST_0); break;
			case L_NNCRONTAB: setLexer(L_NNCRONTAB, LIST_0 | LIST_1 | LIST_2); break;
			case L_OSCRIPT: setLexer(L_OSCRIPT, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5); break;
			case L_REBOL: setLexer(L_REBOL, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6); break;
			case L_REGISTRY: setLexer(L_REGISTRY, LIST_NONE); break;
			case L_RUST: setLexer(L_RUST, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6); break;
			case L_SPICE: setLexer(L_SPICE, LIST_0 | LIST_1 | LIST_2); break;
			case L_TXT2TAGS: setLexer(L_TXT2TAGS, LIST_NONE); break;
			case L_VISUALPROLOG: setLexer(L_VISUALPROLOG, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_TYPESCRIPT: setTypeScriptLexer(); break;
			case L_HOLLYWOOD: setLexer(L_HOLLYWOOD, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_RAKU:
				setLexer(L_RAKU, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5 | LIST_6);
				prop("fold.raku.comment.multiline", "1");
				prop("fold.raku.comment.pod", "1");
				break;
			case L_TOML: setLexer(L_TOML, LIST_0); break;
			case L_SAS: setLexer(L_SAS, LIST_0 | LIST_1 | LIST_2 | LIST_3); break;
			case L_STTXT:
				setLexer(L_STTXT, LIST_0 | LIST_1 | LIST_2 | LIST_3 | LIST_4 | LIST_5);
				prop("fold.preprocessor", "1");
				break;
			case L_ERRORLIST:
				setLexer(L_ERRORLIST, LIST_NONE);
				prop("lexer.errorlist.value.separate", "0");
				prop("lexer.errorlist.escape.sequences", "1");
				break;
			case L_ESCSEQ:
				setLexer(L_ESCSEQ, LIST_NONE);
				prop("lexer.escseq.colour.text", "1");
				break;
			case L_SEARCHRESULT: setSearchResultLexer(); break;
			case L_TEXT:
			default:
				setLexerFromLangID(L_TEXT);
				break;
		}

		// global styles
		if (const MppStyle *s = _theme->globalByID(STYLE_INDENTGUIDE)) setStyle(*s);
		if (const MppStyle *s = _theme->globalByID(STYLE_BRACELIGHT)) setStyle(*s);
		if (const MppStyle *s = _theme->globalByID(STYLE_BRACEBAD)) setStyle(*s);
		if (const MppStyle *s = _theme->globalByID(STYLE_LINENUMBER)) {
			MppStyle ln = *s;
			if ([MppPrefs shared].useMacFont) {
				ln.fontName.clear();
				ln.fontSize = -1;
			}
			setSpecialStyle(ln);
		}
	}

	// ---- performGlobalStyles ------------------------------------------------
	int colorOf(const char *name, bool fg, int def) const
	{
		const MppStyle *s = _theme->global(name);
		if (!s)
			return def;
		return fg ? s->fgColor : s->bgColor;
	}

	void element(int el, int colour) const
	{
		exec(SCI_SETELEMENTCOLOUR, el, (sptr_t)(colour | 0xFF000000));
	}

	void globalStyles() const
	{
		MppPrefs *p = [MppPrefs shared];

		if (p.highlightCurrentLine) {
			element(SC_ELEMENT_CARET_LINE_BACK, colorOf("Current line background colour", false, 0xFFE8E8));
		} else {
			exec(SCI_RESETELEMENTCOLOUR, SC_ELEMENT_CARET_LINE_BACK);
		}
		exec(SCI_SETCARETLINEVISIBLEALWAYS, true);

		const int selBack = colorOf("Selected text colour", false, 0xC0C0C0);
		element(SC_ELEMENT_SELECTION_BACK, selBack);
		element(SC_ELEMENT_SELECTION_INACTIVE_BACK, selBack);
		element(SC_ELEMENT_SELECTION_ADDITIONAL_BACK, colorOf("Multi-selected text color", false, 0xC0C0C0));
		element(SC_ELEMENT_CARET, colorOf("Caret colour", true, 0x000000));
		element(SC_ELEMENT_CARET_ADDITIONAL, colorOf("Multi-edit carets color", true, 0x404040));
		exec(SCI_SETEDGECOLOUR, colorOf("Edge colour", true, 0xC0C0C0));

		exec(SCI_SETFOLDMARGINCOLOUR, true, colorOf("Fold margin", false, 0xE9E9E9));
		exec(SCI_SETFOLDMARGINHICOLOUR, true, colorOf("Fold margin", true, 0xFFFFFF));

		const int lnBack = colorOf("Line number margin", false, 0xE4E4E4);
		exec(SCI_SETMARGINTYPEN, MPP_MARGIN_SYMBOL, SC_MARGIN_COLOUR);
		exec(SCI_SETMARGINBACKN, MPP_MARGIN_SYMBOL, colorOf("Bookmark margin", false, lnBack));
		exec(SCI_SETMARGINTYPEN, MPP_MARGIN_CHANGEHISTORY, SC_MARGIN_COLOUR);
		exec(SCI_SETMARGINBACKN, MPP_MARGIN_CHANGEHISTORY, colorOf("Change History margin", false, lnBack));

		struct { const char *name; int marker; int indIns; int indDel; int def; } hist[] = {
			{"Change History modified", SC_MARKNUM_HISTORY_MODIFIED, INDICATOR_HISTORY_MODIFIED_INSERTION, INDICATOR_HISTORY_MODIFIED_DELETION, 0x0080FF},
			{"Change History revert modified", SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED, INDICATOR_HISTORY_REVERTED_TO_MODIFIED_INSERTION, INDICATOR_HISTORY_REVERTED_TO_MODIFIED_DELETION, 0x00C0A0},
			{"Change History revert origin", SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN, INDICATOR_HISTORY_REVERTED_TO_ORIGIN_INSERTION, INDICATOR_HISTORY_REVERTED_TO_ORIGIN_DELETION, 0xBFA040},
			{"Change History saved", SC_MARKNUM_HISTORY_SAVED, INDICATOR_HISTORY_SAVED_INSERTION, INDICATOR_HISTORY_SAVED_DELETION, 0x00A000},
		};
		for (const auto &h : hist) {
			const int fg = colorOf(h.name, true, h.def), bg = colorOf(h.name, false, h.def);
			exec(SCI_MARKERSETFORE, h.marker, fg);
			exec(SCI_MARKERSETBACK, h.marker, bg);
			exec(SCI_INDICSETFORE, h.indIns, fg);
			exec(SCI_INDICSETFORE, h.indDel, fg);
		}

		// Folder markers
		static const int markers[5][7] = {
			{SC_MARKNUM_FOLDEROPEN, SC_MARKNUM_FOLDER, SC_MARKNUM_FOLDERSUB, SC_MARKNUM_FOLDERTAIL, SC_MARKNUM_FOLDEREND, SC_MARKNUM_FOLDEROPENMID, SC_MARKNUM_FOLDERMIDTAIL},
			{SC_MARK_MINUS, SC_MARK_PLUS, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY},
			{SC_MARK_ARROWDOWN, SC_MARK_ARROW, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY},
			{SC_MARK_CIRCLEMINUS, SC_MARK_CIRCLEPLUS, SC_MARK_VLINE, SC_MARK_LCORNERCURVE, SC_MARK_CIRCLEPLUSCONNECTED, SC_MARK_CIRCLEMINUSCONNECTED, SC_MARK_TCORNERCURVE},
			{SC_MARK_BOXMINUS, SC_MARK_BOXPLUS, SC_MARK_VLINE, SC_MARK_LCORNER, SC_MARK_BOXPLUSCONNECTED, SC_MARK_BOXMINUSCONNECTED, SC_MARK_TCORNER},
		};
		int style = (int)p.foldStyle;
		if (style < MppFoldStyleSimple || style > MppFoldStyleBoxTree)
			style = MppFoldStyleBoxTree;
		const MppStyle *fold = _theme->global("Fold");
		const int foldFg = fold ? fold->bgColor : 0xFFFFFF;
		const int foldBg = fold ? fold->fgColor : 0x808080;
		const int foldActive = colorOf("Fold active", true, 0x0000FF);
		for (int j = 0; j < 7; ++j) {
			exec(SCI_MARKERDEFINE, markers[0][j], markers[style][j]);
			exec(SCI_MARKERSETFORE, markers[0][j], foldFg);
			exec(SCI_MARKERSETBACK, markers[0][j], foldBg);
			exec(SCI_MARKERSETBACKSELECTED, markers[0][j], foldActive);
		}
		exec(SCI_MARKERENABLEHIGHLIGHT, true);

		exec(SCI_SETWHITESPACEFORE, true, colorOf("White space symbol", true, 0x6AB5FF));

		// EOL representation colour (rounded rectangle with custom colour, the default)
		const int eolColor = colorOf("EOL custom color", true, 0xDADADA);
		static const char *eols[] = {"\r\n", "\r", "\n"};
		static const char *eolText[] = {"CRLF", "CR", "LF"};
		for (int i = 0; i < 3; ++i) {
			exec(SCI_SETREPRESENTATION, (uptr_t)eols[i], (sptr_t)eolText[i]);
			exec(SCI_SETREPRESENTATIONAPPEARANCE, (uptr_t)eols[i], SC_REPRESENTATION_BLOB | SC_REPRESENTATION_COLOUR);
			exec(SCI_SETREPRESENTATIONCOLOUR, (uptr_t)eols[i], (sptr_t)(eolColor | 0xFF000000));
		}
	}

private:
	ScintillaView *_v;
	MppTheme *_theme;
};

} // namespace

@implementation MppStyler

+ (NSString *)effectiveFontName
{
	MppPrefs *p = [MppPrefs shared];
	NSString *name = p.macFontName.length ? p.macFontName : @"Menlo";
	if (![NSFont fontWithName:name size:12])
		name = @"Menlo";
	return name;
}

+ (int)effectiveFontSize
{
	NSInteger s = [MppPrefs shared].macFontSize;
	return (int)(s > 4 ? s : 12);
}

+ (void)initializeView:(ScintillaView *)view
{
	Styler st(view);
	st.exec(SCI_SETCODEPAGE, SC_CP_UTF8);
	st.exec(SCI_SETIDLESTYLING, SC_IDLESTYLING_ALL);
	st.exec(SCI_SETMARGINS, 4);
	st.exec(SCI_SETMARGINTYPEN, MPP_MARGIN_LINENUMBER, SC_MARGIN_NUMBER);
	st.exec(SCI_SETMARGINMASKN, MPP_MARGIN_LINENUMBER, 0);
	st.exec(SCI_SETMARGINMASKN, MPP_MARGIN_FOLDER, SC_MASK_FOLDERS);
	st.exec(SCI_SETMARGINTYPEN, MPP_MARGIN_FOLDER, SC_MARGIN_SYMBOL);
	st.exec(SCI_SETMARGINMASKN, MPP_MARGIN_SYMBOL,
	        (1 << MPP_MARK_BOOKMARK) | (1 << MPP_MARK_HIDELINESBEGIN) | (1 << MPP_MARK_HIDELINESEND));
	st.exec(SCI_SETMARGINMASKN, MPP_MARGIN_CHANGEHISTORY,
	        (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) | (1 << SC_MARKNUM_HISTORY_SAVED) |
	        (1 << SC_MARKNUM_HISTORY_MODIFIED) | (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED));
	st.exec(SCI_SETMARGINSENSITIVEN, MPP_MARGIN_FOLDER, true);
	st.exec(SCI_SETMARGINSENSITIVEN, MPP_MARGIN_SYMBOL, true);

	st.exec(SCI_RGBAIMAGESETWIDTH, 14);
	st.exec(SCI_RGBAIMAGESETHEIGHT, 14);
	st.exec(SCI_MARKERDEFINERGBAIMAGE, MPP_MARK_BOOKMARK, (sptr_t)bookmark14);
	st.exec(SCI_MARKERDEFINERGBAIMAGE, MPP_MARK_HIDELINESBEGIN, (sptr_t)hidelines_begin14);
	st.exec(SCI_MARKERDEFINERGBAIMAGE, MPP_MARK_HIDELINESEND, (sptr_t)hidelines_end14);
	st.exec(SCI_MARKERSETALPHA, MPP_MARK_BOOKMARK, 70);
	st.exec(SCI_SETELEMENTCOLOUR, SC_ELEMENT_HIDDEN_LINE, (sptr_t)(0x77CC77 | 0xFF000000));

	st.exec(SCI_SETFOLDFLAGS, SC_FOLDFLAG_LINEAFTER_CONTRACTED);
	st.exec(SCI_SETAUTOMATICFOLD, SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE);
	st.exec(SCI_SETSCROLLWIDTHTRACKING, true);
	st.exec(SCI_SETSCROLLWIDTH, 1);

	const int inds[] = {MPP_INDIC_FOUND_STYLE_SMART, MPP_INDIC_FOUND_STYLE, MPP_INDIC_FOUND_STYLE_INC,
	                    MPP_INDIC_TAGMATCH, MPP_INDIC_TAGATTR, MPP_INDIC_FOUND_STYLE_EXT1,
	                    MPP_INDIC_FOUND_STYLE_EXT2, MPP_INDIC_FOUND_STYLE_EXT3, MPP_INDIC_FOUND_STYLE_EXT4,
	                    MPP_INDIC_FOUND_STYLE_EXT5};
	for (int i : inds) {
		st.exec(SCI_INDICSETSTYLE, i, INDIC_ROUNDBOX);
		st.exec(SCI_INDICSETALPHA, i, 100);
		st.exec(SCI_INDICSETUNDER, i, true);
	}

	st.exec(SCI_SETMULTIPASTE, SC_MULTIPASTE_EACH);
	st.exec(SCI_SETADDITIONALSELECTIONTYPING, true);
	st.exec(SCI_SETMOUSESELECTIONRECTANGULARSWITCH, true);
	st.exec(SCI_SETCARETSTICKY, SC_CARETSTICKY_OFF);
	st.exec(SCI_SETENDATLASTLINE, true);
	st.exec(SCI_SETLAYOUTCACHE, SC_CACHE_PAGE);
	st.exec(SCI_SETMOUSEDWELLTIME, 500);
	st.exec(SCI_SETCHARACTERCATEGORYOPTIMIZATION, 0x10000);
	st.exec(SCI_SETUNDOSELECTIONHISTORY, SC_UNDO_SELECTION_HISTORY_ENABLED);
	// Prefer a sane "word" behaviour (default Scintilla word chars)
}

+ (void)defineDocType:(MppLangType)lang inView:(ScintillaView *)view
{
	Styler st(view);
	st.defineDocType(lang);
	st.globalStyles();
}

+ (void)applyGlobalStyles:(ScintillaView *)view
{
	Styler(view).globalStyles();
}

+ (void)updateLineNumberWidth:(ScintillaView *)view
{
	Styler st(view);
	if (![MppPrefs shared].showLineNumbers) {
		st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_LINENUMBER, 0);
		return;
	}
	const sptr_t lines = st.exec(SCI_GETLINECOUNT);
	int digits = 1;
	for (sptr_t n = lines; n >= 10; n /= 10)
		++digits;
	digits = std::max(digits, 3);
	std::string sample(digits + 1, '8');
	const sptr_t w = st.exec(SCI_TEXTWIDTH, STYLE_LINENUMBER, (sptr_t)sample.c_str());
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_LINENUMBER, w + 4);
}

+ (void)applyViewPreferences:(ScintillaView *)view lang:(MppLangType)lang
{
	Styler st(view);
	MppPrefs *p = [MppPrefs shared];

	[self updateLineNumberWidth:view];
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_SYMBOL, p.showBookmarkMargin ? 16 : 0);
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_CHANGEHISTORY, p.showChangeHistory ? 9 : 0);
	st.exec(SCI_SETCHANGEHISTORY, p.showChangeHistory ? (SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS) : SC_CHANGE_HISTORY_DISABLED);

	const bool needFold = !(lang == L_TEXT || lang == L_ASCII || lang == L_BATCH || lang == L_DIFF ||
	                        lang == L_REGISTRY || lang == L_ERRORLIST || lang == L_SREC ||
	                        lang == L_IHEX || lang == L_TEHEX);
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_FOLDER, (p.foldStyle != MppFoldStyleNone && needFold) ? 14 : 0);

	// Tabs
	int tabSize = (int)p.tabSize;
	bool useSpaces = p.useSpaces;
	if (const MppLangDef *d = [MppLanguages.shared langDefForType:lang]) {
		if (d->tabSettings >= 0) {
			tabSize = d->tabSettings & 0x7F;
			useSpaces = (d->tabSettings & 0x80) != 0;
		}
	}
	st.exec(SCI_SETTABWIDTH, tabSize > 0 ? tabSize : 4);
	st.exec(SCI_SETUSETABS, !useSpaces);
	st.exec(SCI_SETINDENT, 0);
	st.exec(SCI_SETTABINDENTS, true);
	st.exec(SCI_SETBACKSPACEUNINDENTS, true);

	st.exec(SCI_SETWRAPMODE, p.wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE);
	st.exec(SCI_SETWRAPVISUALFLAGS, p.showWrapSymbol ? SC_WRAPVISUALFLAG_END : SC_WRAPVISUALFLAG_NONE);
	st.exec(SCI_SETWRAPINDENTMODE, SC_WRAPINDENT_SAME);
	st.exec(SCI_SETVIEWWS, p.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE);
	st.exec(SCI_SETVIEWEOL, p.showEOL);
	// Python-like indentation includes trailing blank lines in the block (isPythonStyleIndentation)
	const int indentMode = (lang == L_PYTHON || lang == L_COFFEESCRIPT || lang == L_HASKELL || lang == L_NIM ||
	                        lang == L_YAML || lang == L_GDSCRIPT) ? SC_IV_LOOKFORWARD : SC_IV_LOOKBOTH;
	st.exec(SCI_SETINDENTATIONGUIDES, p.showIndentGuides ? indentMode : SC_IV_NONE);

	switch (p.edgeMode) {
		case MppEdgeLine: st.exec(SCI_SETEDGEMODE, EDGE_LINE); break;
		case MppEdgeBackground: st.exec(SCI_SETEDGEMODE, EDGE_BACKGROUND); break;
		default: st.exec(SCI_SETEDGEMODE, EDGE_NONE); break;
	}
	st.exec(SCI_SETEDGECOLUMN, p.edgeColumn);

	st.exec(SCI_SETCARETWIDTH, p.caretWidth);
	st.exec(SCI_SETCARETPERIOD, p.caretBlinkRate);
	st.exec(SCI_SETMULTIPLESELECTION, p.multiEditing);
	st.exec(SCI_SETVIRTUALSPACEOPTIONS, p.virtualSpace ? (SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE) : SCVS_RECTANGULARSELECTION);
	st.exec(SCI_SETENDATLASTLINE, !p.scrollBeyondLastLine);
	st.exec(SCI_SETZOOM, p.zoom);
}

+ (void)setupSearchResultView:(ScintillaView *)view
{
	[self initializeView:view];
	Styler st(view);
	st.defineDocType(L_SEARCHRESULT);
	st.globalStyles();
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_LINENUMBER, 0);
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_SYMBOL, 0);
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_CHANGEHISTORY, 0);
	st.exec(SCI_SETMARGINWIDTHN, MPP_MARGIN_FOLDER, 14);
	st.exec(SCI_SETCARETLINEVISIBLEALWAYS, true);
	st.exec(SCI_SETUNDOCOLLECTION, 0);
	st.exec(SCI_SETREADONLY, 1);
	st.exec(SCI_SETWRAPMODE, SC_WRAP_NONE);
}

@end
