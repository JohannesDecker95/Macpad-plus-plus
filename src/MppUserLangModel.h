// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
// The in-memory form of a User Defined Language.
// C++ only; shared by the UDL manager and the "Define your language" editor.

#include "MppLanguages.h"
#include "SciLexer.h"
#include <string>
#include <vector>

struct UdlStyle {
	MppStyle style;
	int nesting = 0;     // SCE_USER_MASK_NESTING_* bits
};

struct UserLang {
	std::string name;
	std::vector<std::string> exts;
	std::string udlVersion;
	bool darkModeTheme = false;
	bool caseIgnored = false, allowFoldOfComments = false, foldCompact = false;
	int forcePureLC = 0, decimalSeparator = 0;
	bool isPrefix[SCE_USER_TOTAL_KEYWORD_GROUPS] = {};
	std::string keywordLists[SCE_USER_KWLIST_TOTAL];
	std::vector<UdlStyle> styles;
	std::string source;    // the XML file it was loaded from / is saved to
	bool bundled = false;  // shipped with the app (saving writes a user copy)

	UdlStyle *findStyle(int styleID);
};

// Names used in UDL 2.1 files
const char *MppUdlKeywordListName(int kwlist);   // "Keywords1", "Numbers, prefix1"...
const char *MppUdlStyleName(int styleID);        // "KEYWORDS1", "LINE COMMENTS"...

// Comments and delimiters are stored as one list with two-digit prefixes per field
// ("00//" "03/*" "04*/"); these convert one field to / from the text shown in the editor.
std::string MppUdlGetPrefixed(const std::string &list, const char *prefix);
std::string MppUdlSetPrefixed(const std::string *fields, int count);   // fields[i] gets prefix "%02d" % i
