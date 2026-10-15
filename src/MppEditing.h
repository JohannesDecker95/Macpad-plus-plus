// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#import "MppLanguages.h"
#include <functional>
#include <string>
#include <vector>

enum { MPP_URL_INDIC = 8 };

// Editing behaviours implemented on top of Scintilla
void MppSmartHighlight(ScintillaView *v, BOOL force);
void MppBraceMatch(ScintillaView *v);
void MppXmlTagMatch(ScintillaView *v, MppLangType lang);
void MppHighlightURLs(ScintillaView *v);
void MppHandleIndicatorClick(ScintillaView *v, SCNotification *n);
void MppMaintainIndentation(ScintillaView *v, int ch, MppLangType lang);
void MppAutoCloseChar(ScintillaView *v, int ch, MppLangType lang);
void MppToggleBookmark(ScintillaView *v, sptr_t line);
void MppTrimTrailing(ScintillaView *v);

// Line helpers
std::string MppGetLine(ScintillaView *v, sptr_t line);          // without EOL
std::string MppGetRange(ScintillaView *v, sptr_t start, sptr_t end);
std::string MppEOLString(ScintillaView *v);
// Applies a transformation to the selected lines (or all lines if the selection is within one line)
void MppTransformLines(ScintillaView *v, const std::function<void(std::vector<std::string> &)> &fn, bool wholeDocIfNoSel = true);
// Replace the selection (or each selection), or the whole document if nothing is selected
void MppTransformSelection(ScintillaView *v, const std::function<std::string(const std::string &)> &fn, bool wholeDocIfEmpty);
