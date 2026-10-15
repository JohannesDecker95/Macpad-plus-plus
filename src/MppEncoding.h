// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Foundation/Foundation.h>
#include <string>
#include <vector>

// Values are stored in session files; keep them stable
typedef NS_ENUM(NSInteger, MppUniMode) {
	MppUni8Bit = 0,        // legacy code page (see codepage)
	MppUniUTF8BOM = 1,     // UTF-8 with BOM
	MppUni16BE = 2,        // UTF-16 BE with BOM
	MppUni16LE = 3,        // UTF-16 LE with BOM
	MppUniUTF8 = 4,        // UTF-8 without BOM ("uniCookie")
	MppUni7Bit = 5,
	MppUni16BENoBOM = 6,
	MppUni16LENoBOM = 7,
};

struct MppEncoding {
	MppUniMode mode = MppUniUTF8;
	int codepage = -1;  // Windows code page when mode == MppUni8Bit; -1 = ANSI (Windows-1252)

	bool operator==(const MppEncoding &o) const { return mode == o.mode && (mode != MppUni8Bit || codepage == o.codepage); }
	bool operator!=(const MppEncoding &o) const { return !(*this == o); }
};

struct MppCharsetInfo {
	const char *group;  // menu group (Arabic, Baltic, ...)
	const char *name;   // menu item text
	int codepage;
};

const std::vector<MppCharsetInfo> &MppCharsets();   // only those supported by CoreFoundation

NSString *MppEncodingName(MppEncoding enc);         // for the status bar
MppEncoding MppEncodingFromName(NSString *name);    // "UTF-8", "UTF-8-BOM", "UTF-16 LE BOM", "ANSI", "cp:1252"
NSString *MppEncodingToName(MppEncoding enc);       // inverse of MppEncodingFromName

// Decode raw file bytes into UTF-8 for Scintilla.
// If forced is non-null, that encoding is used instead of detection.
bool MppDecode(NSData *raw, const MppEncoding *forced, bool autoDetect, std::string &utf8Out, MppEncoding &encOut);

// Encode UTF-8 text from Scintilla into bytes for the given encoding.
// Returns nil if some characters cannot be represented (lossy == false), otherwise substitutes '?'.
NSData *MppEncode(const char *utf8, size_t len, MppEncoding enc, bool allowLossy);

bool MppIsValidUTF8(const unsigned char *s, size_t len, bool *isPureASCII);
