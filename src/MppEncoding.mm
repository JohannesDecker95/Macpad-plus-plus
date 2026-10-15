// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppEncoding.h"
#include "uchardet.h"
#include <cstring>

static const MppCharsetInfo kAllCharsets[] = {
	{"Arabic", "ISO 8859-6", 28596}, {"Arabic", "OEM 720", 720}, {"Arabic", "Windows-1256", 1256},
	{"Baltic", "ISO 8859-4", 28594}, {"Baltic", "ISO 8859-13", 28603}, {"Baltic", "OEM 775", 775},
	{"Baltic", "Windows-1257", 1257},
	{"Celtic", "ISO 8859-14", 28604},
	{"Cyrillic", "ISO 8859-5", 28595}, {"Cyrillic", "KOI8-R", 20866}, {"Cyrillic", "KOI8-U", 21866},
	{"Cyrillic", "Macintosh", 10007}, {"Cyrillic", "OEM 855", 855}, {"Cyrillic", "OEM 866", 866},
	{"Cyrillic", "Windows-1251", 1251},
	{"Central European", "OEM 852", 852}, {"Central European", "Windows-1250", 1250},
	{"Chinese", "Big5 (Traditional)", 950}, {"Chinese", "GB2312 (Simplified)", 936},
	{"Eastern European", "ISO 8859-2", 28592},
	{"Greek", "ISO 8859-7", 28597}, {"Greek", "OEM 737", 737}, {"Greek", "OEM 869", 869},
	{"Greek", "Windows-1253", 1253},
	{"Hebrew", "ISO 8859-8", 28598}, {"Hebrew", "OEM 862", 862}, {"Hebrew", "Windows-1255", 1255},
	{"Japanese", "Shift-JIS", 932},
	{"Korean", "Windows 949", 949}, {"Korean", "EUC-KR", 51949},
	{"North European", "OEM 861 : Icelandic", 861}, {"North European", "OEM 865 : Nordic", 865},
	{"Thai", "TIS-620", 874},
	{"Turkish", "ISO 8859-3", 28593}, {"Turkish", "ISO 8859-9", 28599}, {"Turkish", "OEM 857", 857},
	{"Turkish", "Windows-1254", 1254},
	{"Western European", "ISO 8859-1", 28591}, {"Western European", "ISO 8859-15", 28605},
	{"Western European", "OEM 850", 850}, {"Western European", "OEM 858", 858},
	{"Western European", "OEM 860 : Portuguese", 860}, {"Western European", "OEM 863 : French", 863},
	{"Western European", "OEM-US : CP437", 437}, {"Western European", "Windows-1252", 1252},
	{"Vietnamese", "Windows-1258", 1258},
	{"Unicode", "Mac OS Roman", 10000},
};

static CFStringEncoding cfEncodingForCodepage(int cp)
{
	if (cp < 0)
		cp = 1252;
	switch (cp) {
		case 10000: return kCFStringEncodingMacRoman;
		case 858: return kCFStringEncodingDOSLatin1;  // CP858 = CP850 + euro sign
		default: return CFStringConvertWindowsCodepageToEncoding((UInt32)cp);
	}
}

const std::vector<MppCharsetInfo> &MppCharsets()
{
	static std::vector<MppCharsetInfo> v;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		for (const auto &c : kAllCharsets) {
			CFStringEncoding e = cfEncodingForCodepage(c.codepage);
			if (e != kCFStringEncodingInvalidId && CFStringIsEncodingAvailable(e))
				v.push_back(c);
		}
	});
	return v;
}

NSString *MppEncodingName(MppEncoding enc)
{
	switch (enc.mode) {
		case MppUniUTF8: return @"UTF-8";
		case MppUniUTF8BOM: return @"UTF-8-BOM";
		case MppUni16BE: return @"UTF-16 BE BOM";
		case MppUni16LE: return @"UTF-16 LE BOM";
		case MppUni16BENoBOM: return @"UTF-16 Big Endian";
		case MppUni16LENoBOM: return @"UTF-16 Little Endian";
		case MppUni7Bit:
		case MppUni8Bit:
			if (enc.codepage < 0)
				return @"ANSI";
			for (const auto &c : kAllCharsets)
				if (c.codepage == enc.codepage)
					return @(c.name);
			return [NSString stringWithFormat:@"CP%d", enc.codepage];
	}
	return @"UTF-8";
}

NSString *MppEncodingToName(MppEncoding enc)
{
	switch (enc.mode) {
		case MppUniUTF8: return @"UTF-8";
		case MppUniUTF8BOM: return @"UTF-8-BOM";
		case MppUni16BE: return @"UTF-16 BE BOM";
		case MppUni16LE: return @"UTF-16 LE BOM";
		case MppUni16BENoBOM: return @"UTF-16 BE";
		case MppUni16LENoBOM: return @"UTF-16 LE";
		default: return enc.codepage < 0 ? @"ANSI" : [NSString stringWithFormat:@"cp:%d", enc.codepage];
	}
}

MppEncoding MppEncodingFromName(NSString *name)
{
	MppEncoding e;
	if ([name isEqualToString:@"UTF-8-BOM"]) e.mode = MppUniUTF8BOM;
	else if ([name isEqualToString:@"UTF-16 BE BOM"]) e.mode = MppUni16BE;
	else if ([name isEqualToString:@"UTF-16 LE BOM"]) e.mode = MppUni16LE;
	else if ([name isEqualToString:@"UTF-16 BE"]) e.mode = MppUni16BENoBOM;
	else if ([name isEqualToString:@"UTF-16 LE"]) e.mode = MppUni16LENoBOM;
	else if ([name isEqualToString:@"ANSI"]) { e.mode = MppUni8Bit; e.codepage = -1; }
	else if ([name hasPrefix:@"cp:"]) { e.mode = MppUni8Bit; e.codepage = [name substringFromIndex:3].intValue; }
	else e.mode = MppUniUTF8;
	return e;
}

bool MppIsValidUTF8(const unsigned char *s, size_t len, bool *isPureASCII)
{
	bool ascii = true;
	size_t i = 0;
	while (i < len) {
		unsigned char c = s[i];
		if (c < 0x80) { ++i; continue; }
		ascii = false;
		size_t n;
		uint32_t cp;
		if ((c & 0xE0) == 0xC0) { n = 1; cp = c & 0x1F; }
		else if ((c & 0xF0) == 0xE0) { n = 2; cp = c & 0x0F; }
		else if ((c & 0xF8) == 0xF0) { n = 3; cp = c & 0x07; }
		else return false;
		for (size_t k = 1; k <= n; ++k) {
			if (i + k >= len || (s[i + k] & 0xC0) != 0x80)
				return false;
			cp = (cp << 6) | (s[i + k] & 0x3F);
		}
		if ((n == 1 && cp < 0x80) || (n == 2 && cp < 0x800) || (n == 3 && (cp < 0x10000 || cp > 0x10FFFF)))
			return false;
		i += n + 1;
	}
	if (isPureASCII)
		*isPureASCII = ascii;
	return true;
}

static bool convertToUTF8(const void *bytes, size_t len, CFStringEncoding enc, std::string &out)
{
	if (len == 0) {
		out.clear();
		return true;
	}
	CFStringRef s = CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)bytes, (CFIndex)len, enc, false);
	if (!s)
		return false;
	CFIndex chars = CFStringGetLength(s);
	CFIndex needed = 0;
	CFStringGetBytes(s, CFRangeMake(0, chars), kCFStringEncodingUTF8, 0, false, nullptr, 0, &needed);
	out.resize((size_t)needed);
	CFStringGetBytes(s, CFRangeMake(0, chars), kCFStringEncodingUTF8, 0, false, (UInt8 *)out.data(), needed, &needed);
	CFRelease(s);
	return true;
}

// Heuristic used for BOM-less UTF-16: lots of NULs on one side of the byte pairs
static int detectUTF16NoBOM(const unsigned char *d, size_t len)
{
	if (len < 4 || (len & 1))
		return 0;
	const size_t n = std::min<size_t>(len, 4096);
	size_t evenZero = 0, oddZero = 0;
	for (size_t i = 0; i + 1 < n; i += 2) {
		if (d[i] == 0) ++evenZero;
		if (d[i + 1] == 0) ++oddZero;
	}
	const size_t pairs = n / 2;
	if (oddZero > pairs * 6 / 10 && evenZero < pairs / 20)
		return 1;  // LE
	if (evenZero > pairs * 6 / 10 && oddZero < pairs / 20)
		return 2;  // BE
	return 0;
}

static int codepageFromCharsetName(const char *name)
{
	if (!name || !*name)
		return -1;
	// uchardet charset names -> Windows code pages
	static const std::pair<const char *, int> known[] = {
		{"SHIFT_JIS", 932}, {"EUC-JP", 51932}, {"ISO-2022-JP", 50220}, {"GB18030", 936}, {"GB2312", 936},
		{"HZ-GB-2312", 52936}, {"BIG5", 950}, {"EUC-TW", 950}, {"EUC-KR", 51949}, {"UHC", 949}, {"ISO-2022-KR", 50225},
		{"ISO-2022-CN", 50227}, {"KOI8-R", 20866}, {"KOI8-U", 21866}, {"IBM855", 855}, {"IBM866", 866},
		{"MAC-CYRILLIC", 10007}, {"X-MAC-CYRILLIC", 10007}, {"TIS-620", 874}, {"WINDOWS-874", 874},
		{"WINDOWS-1250", 1250}, {"WINDOWS-1251", 1251}, {"WINDOWS-1252", 1252}, {"WINDOWS-1253", 1253},
		{"WINDOWS-1254", 1254}, {"WINDOWS-1255", 1255}, {"WINDOWS-1256", 1256}, {"WINDOWS-1257", 1257},
		{"WINDOWS-1258", 1258}, {"ISO-8859-1", 28591}, {"ISO-8859-2", 28592}, {"ISO-8859-3", 28593},
		{"ISO-8859-4", 28594}, {"ISO-8859-5", 28595}, {"ISO-8859-6", 28596}, {"ISO-8859-7", 28597},
		{"ISO-8859-8", 28598}, {"ISO-8859-9", 28599}, {"ISO-8859-13", 28603}, {"ISO-8859-15", 28605},
		{"UTF-8", 65001},
	};
	for (const auto &k : known)
		if (strcasecmp(k.first, name) == 0)
			return k.second;
	CFStringRef cfName = CFStringCreateWithCString(nullptr, name, kCFStringEncodingASCII);
	CFStringEncoding e = CFStringConvertIANACharSetNameToEncoding(cfName);
	CFRelease(cfName);
	if (e == kCFStringEncodingInvalidId)
		return -1;
	UInt32 cp = CFStringConvertEncodingToWindowsCodepage(e);
	return cp == kCFStringEncodingInvalidId ? -1 : (int)cp;
}

bool MppDecode(NSData *raw, const MppEncoding *forced, bool autoDetect, std::string &utf8Out, MppEncoding &encOut)
{
	const unsigned char *d = (const unsigned char *)raw.bytes;
	const size_t len = raw.length;

	MppEncoding enc;
	size_t skip = 0;

	if (forced) {
		enc = *forced;
	} else if (len >= 3 && d[0] == 0xEF && d[1] == 0xBB && d[2] == 0xBF) {
		enc.mode = MppUniUTF8BOM;
	} else if (len >= 2 && d[0] == 0xFE && d[1] == 0xFF) {
		enc.mode = MppUni16BE;
	} else if (len >= 2 && d[0] == 0xFF && d[1] == 0xFE) {
		enc.mode = MppUni16LE;
	} else {
		bool ascii = false;
		if (MppIsValidUTF8(d, len, &ascii)) {
			enc.mode = MppUniUTF8;
		} else if (int u16 = detectUTF16NoBOM(d, len)) {
			enc.mode = (u16 == 1) ? MppUni16LENoBOM : MppUni16BENoBOM;
		} else {
			enc.mode = MppUni8Bit;
			enc.codepage = -1;
			if (autoDetect) {
				uchardet_t ud = uchardet_new();
				uchardet_handle_data(ud, (const char *)d, std::min<size_t>(len, 1 << 20));
				uchardet_data_end(ud);
				int cp = codepageFromCharsetName(uchardet_get_charset(ud));
				uchardet_delete(ud);
				if (cp == 65001)
					cp = -1;
				if (cp > 0 && cp != 1252)
					enc.codepage = cp;
			}
		}
	}

	// Skip the BOM matching the chosen mode
	if (enc.mode == MppUniUTF8BOM && len >= 3 && d[0] == 0xEF && d[1] == 0xBB && d[2] == 0xBF) skip = 3;
	if (enc.mode == MppUni16BE && len >= 2 && d[0] == 0xFE && d[1] == 0xFF) skip = 2;
	if (enc.mode == MppUni16LE && len >= 2 && d[0] == 0xFF && d[1] == 0xFE) skip = 2;

	bool ok = true;
	switch (enc.mode) {
		case MppUniUTF8:
		case MppUniUTF8BOM:
		case MppUni7Bit:
			utf8Out.assign((const char *)d + skip, len - skip);
			break;
		case MppUni16BE:
		case MppUni16BENoBOM:
			ok = convertToUTF8(d + skip, (len - skip) & ~size_t(1), kCFStringEncodingUTF16BE, utf8Out);
			break;
		case MppUni16LE:
		case MppUni16LENoBOM:
			ok = convertToUTF8(d + skip, (len - skip) & ~size_t(1), kCFStringEncodingUTF16LE, utf8Out);
			break;
		case MppUni8Bit:
			ok = convertToUTF8(d, len, cfEncodingForCodepage(enc.codepage), utf8Out);
			if (!ok) {
				enc.codepage = -1;
				ok = convertToUTF8(d, len, kCFStringEncodingWindowsLatin1, utf8Out);
			}
			break;
	}
	if (!ok) {
		// Last resort: show the bytes as Latin-1 so nothing is lost visually
		enc.mode = MppUni8Bit;
		enc.codepage = 28591;
		ok = convertToUTF8(d, len, kCFStringEncodingISOLatin1, utf8Out);
	}
	encOut = enc;
	return ok;
}

NSData *MppEncode(const char *utf8, size_t len, MppEncoding enc, bool allowLossy)
{
	NSMutableData *out = [NSMutableData data];
	CFStringEncoding target;
	switch (enc.mode) {
		case MppUniUTF8BOM:
			[out appendBytes:"\xEF\xBB\xBF" length:3];
			// fall through
		case MppUniUTF8:
		case MppUni7Bit:
			[out appendBytes:utf8 length:len];
			return out;
		case MppUni16BE:
			[out appendBytes:"\xFE\xFF" length:2];
			target = kCFStringEncodingUTF16BE;
			break;
		case MppUni16LE:
			[out appendBytes:"\xFF\xFE" length:2];
			target = kCFStringEncodingUTF16LE;
			break;
		case MppUni16BENoBOM: target = kCFStringEncodingUTF16BE; break;
		case MppUni16LENoBOM: target = kCFStringEncodingUTF16LE; break;
		case MppUni8Bit:
		default:
			target = cfEncodingForCodepage(enc.codepage);
			break;
	}
	if (len == 0)
		return out;
	CFStringRef s = CFStringCreateWithBytes(nullptr, (const UInt8 *)utf8, (CFIndex)len, kCFStringEncodingUTF8, false);
	if (!s)
		return nil;
	CFIndex chars = CFStringGetLength(s);
	CFIndex needed = 0;
	const UInt8 lossByte = allowLossy ? '?' : 0;
	CFIndex converted = CFStringGetBytes(s, CFRangeMake(0, chars), target, lossByte, false, nullptr, 0, &needed);
	if (converted < chars) {
		CFRelease(s);
		return nil;
	}
	NSMutableData *body = [NSMutableData dataWithLength:(NSUInteger)needed];
	CFStringGetBytes(s, CFRangeMake(0, chars), target, lossByte, false, (UInt8 *)body.mutableBytes, needed, &needed);
	CFRelease(s);
	[out appendData:body];
	return out;
}
