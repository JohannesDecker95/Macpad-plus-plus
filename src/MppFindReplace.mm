// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppFindReplace.h"
#import "MppPaths.h"
#import "MppMainWindowController.h"
#import "MppSearchResults.h"
#import "MppStyler.h"
#import "MppPrefs.h"
#import "MppMacro.h"
#import "MppEditing.h"
#import "MppLanguages.h"
#include "Scintilla.h"
#include "BoostRegexSearch.h"
#include <map>
#include <fnmatch.h>

// ---- helpers ----------------------------------------------------------------------------

static bool readBase(const char *s, int *res, int base, int size)
{
	int r = 0;
	for (int i = 0; i < size; ++i) {
		const char c = s[i];
		int d;
		if (c >= '0' && c <= '9') d = c - '0';
		else if (c >= 'a' && c <= 'f') d = c - 'a' + 10;
		else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
		else return false;
		if (d >= base)
			return false;
		r = r * base + d;
	}
	*res = r;
	return true;
}

static void appendUTF8(std::string &out, unsigned cp)
{
	if (cp < 0x80) {
		out += (char)cp;
	} else if (cp < 0x800) {
		out += (char)(0xC0 | (cp >> 6));
		out += (char)(0x80 | (cp & 0x3F));
	} else if (cp < 0x10000) {
		out += (char)(0xE0 | (cp >> 12));
		out += (char)(0x80 | ((cp >> 6) & 0x3F));
		out += (char)(0x80 | (cp & 0x3F));
	} else {
		out += (char)(0xF0 | (cp >> 18));
		out += (char)(0x80 | ((cp >> 12) & 0x3F));
		out += (char)(0x80 | ((cp >> 6) & 0x3F));
		out += (char)(0x80 | (cp & 0x3F));
	}
}

std::string MppExpandExtended(const std::string &q)
{
	std::string r;
	const size_t len = q.size();
	for (size_t i = 0; i < len; ++i) {
		const char c = q[i];
		if (c != '\\' || i + 1 >= len) {
			r += c;
			continue;
		}
		const char e = q[++i];
		switch (e) {
			case 'r': r += '\r'; break;
			case 'n': r += '\n'; break;
			case '0': r += '\0'; break;
			case 't': r += '\t'; break;
			case '\\': r += '\\'; break;
			case 'b': case 'd': case 'o': case 'x': case 'u': {
				int size = 0, base = 0;
				switch (e) {
					case 'b': size = 8; base = 2; break;
					case 'o': size = 3; base = 8; break;
					case 'd': size = 3; base = 10; break;
					case 'x': size = 2; base = 16; break;
					default: size = 4; base = 16; break;
				}
				int v = 0;
				if (len - (i + 1) >= (size_t)size && readBase(q.c_str() + i + 1, &v, base, size)) {
					appendUTF8(r, (unsigned)v);
					i += (size_t)size;
					break;
				}
				r += '\\';
				r += e;
				break;
			}
			default:
				r += '\\';
				r += e;
				break;
		}
	}
	return r;
}

int MppSearchFlags(const MppFindOptions &o)
{
	return (o.wholeWord ? SCFIND_WHOLEWORD : 0) | (o.matchCase ? SCFIND_MATCHCASE : 0) |
	       (o.mode == MppSearchRegex ? (SCFIND_REGEXP | SCFIND_POSIX) : 0) |
	       ((o.mode == MppSearchRegex && o.dotMatchesNewline) ? SCFIND_REGEXP_DOTMATCHESNL : 0);
}

static inline sptr_t S(ScintillaView *v, unsigned int m, uptr_t w = 0, sptr_t l = 0)
{
	return [v message:m wParam:w lParam:l];
}

enum MppProcessOp { OpCount, OpMark, OpReplaceAll, OpFindAll };

struct ProcessResult {
	int count = 0;
	bool invalidRegex = false;
	bool emptyMatch = false;
	std::vector<MppSearchHit> hits;
};

// Port of FindReplaceDlg::processRange: count / mark / replace all / find all inside [start, end)
static ProcessResult processRange(ScintillaView *v, MppProcessOp op, const std::string &find, const std::string &replace,
                                  const MppFindOptions &o, sptr_t start, sptr_t end, int markIndicator = MPP_INDIC_FOUND_STYLE)
{
	ProcessResult res;
	if (find.empty())
		return res;
	const bool isRegex = o.mode == MppSearchRegex;
	int flags = MppSearchFlags(o) | SCFIND_REGEXP_SKIPCRLFASONE | SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH;
	S(v, SCI_SETSEARCHFLAGS, (uptr_t)flags);
	if (op == OpReplaceAll)
		S(v, SCI_BEGINUNDOACTION);
	sptr_t startRange = start, endRange = end;
	sptr_t lastHitLine = -1;
	while (true) {
		S(v, SCI_SETTARGETRANGE, (uptr_t)startRange, endRange);
		const sptr_t targetStart = S(v, SCI_SEARCHINTARGET, find.size(), (sptr_t)find.data());
		if (targetStart == -1)
			break;
		if (targetStart == -2) {
			res.invalidRegex = true;
			break;
		}
		const sptr_t targetEnd = S(v, SCI_GETTARGETEND);
		if (targetEnd > endRange)
			break;
		const sptr_t foundLen = targetEnd - targetStart;
		sptr_t replaceDelta = 0;
		switch (op) {
			case OpReplaceAll: {
				sptr_t replaced;
				if (isRegex)
					replaced = S(v, SCI_REPLACETARGETRE, (uptr_t)-1, (sptr_t)replace.c_str());
				else
					replaced = S(v, SCI_REPLACETARGET, replace.size(), (sptr_t)replace.data());
				replaceDelta = replaced - foundLen;
				break;
			}
			case OpMark:
				if (foundLen > 0) {
					S(v, SCI_SETINDICATORCURRENT, (uptr_t)markIndicator);
					S(v, SCI_INDICATORFILLRANGE, (uptr_t)targetStart, foundLen);
				} else if (isRegex) {
					res.emptyMatch = true;
				}
				if (o.bookmarkLine) {
					const sptr_t l1 = S(v, SCI_LINEFROMPOSITION, (uptr_t)targetStart);
					const sptr_t l2 = foundLen > 0 ? S(v, SCI_LINEFROMPOSITION, (uptr_t)targetEnd - 1) : l1;
					for (sptr_t l = l1; l <= l2; ++l)
						if (!(S(v, SCI_MARKERGET, (uptr_t)l) & (1 << MPP_MARK_BOOKMARK)))
							S(v, SCI_MARKERADD, (uptr_t)l, MPP_MARK_BOOKMARK);
				}
				break;
			case OpFindAll: {
				const sptr_t line = S(v, SCI_LINEFROMPOSITION, (uptr_t)targetStart);
				const sptr_t ls = S(v, SCI_POSITIONFROMLINE, (uptr_t)line);
				if (line == lastHitLine && !res.hits.empty()) {
					res.hits.back().ranges.emplace_back(targetStart - ls, std::min(targetEnd, S(v, SCI_GETLINEENDPOSITION, (uptr_t)line)) - ls);
				} else {
					MppSearchHit h;
					sptr_t le = S(v, SCI_GETLINEENDPOSITION, (uptr_t)line);
					if (le - ls > 1024)
						le = ls + 1024;
					h.lineText = MppGetRange(v, ls, le);
					h.lineNumber = line;
					h.docStart = targetStart;
					h.docEnd = targetEnd;
					h.ranges.emplace_back(targetStart - ls, std::min(targetEnd, le) - ls);
					res.hits.push_back(h);
					lastHitLine = line;
				}
				break;
			}
			case OpCount:
				if (foundLen == 0 && isRegex)
					res.emptyMatch = true;
				break;
		}
		++res.count;
		if (targetStart + foundLen == endRange)
			break;
		startRange = targetStart + foundLen + replaceDelta;
		endRange += replaceDelta;
	}
	if (op == OpReplaceAll)
		S(v, SCI_ENDUNDOACTION);
	return res;
}

// ---- controller ---------------------------------------------------------------------------

@implementation MppFindReplaceController {
	NSSegmentedControl *_tabs;
	NSComboBox *_findCombo, *_replaceCombo, *_filterCombo, *_dirCombo;
	NSGridRow *_replaceRow, *_filterRow, *_dirRow;
	NSButton *_backward, *_wholeWord, *_matchCase, *_wrap, *_inSelection, *_bookmarkLine, *_purge;
	NSButton *_subfolders, *_hidden, *_projectCurrentDoc;
	NSButton *_modeNormal, *_modeExtended, *_modeRegex, *_dotNL;
	NSStackView *_buttons;
	NSTextField *_status;
	MppFindTab _tab;
	// Find in files job
	NSMutableArray<NSString *> *_fifQueue;
	NSInteger _fifSearched, _fifFiles, _fifHits;
	BOOL _fifReplace, _fifCancel;
	std::string _fifFind, _fifReplaceText;
	MppFindOptions _fifOpts;
	NSButton *_stopButton;
	// incremental search
	NSPanel *_incPanel;
	NSSearchField *_incField;
	NSButton *_incMatchCase, *_incHighlight;
	NSTextField *_incStatus;
	sptr_t _incStart;
}

@synthesize owner = _owner;   // NSWindowController already declares an "owner" property

- (instancetype)initWithOwner:(MppMainWindowController *)owner
{
	NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 700, 330)
	                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
	                                              backing:NSBackingStoreBuffered defer:YES];
	if ((self = [super initWithWindow:panel])) {
		_owner = owner;
		panel.title = @"Find";
		panel.floatingPanel = YES;
		panel.hidesOnDeactivate = YES;
		panel.becomesKeyOnlyIfNeeded = NO;
		panel.delegate = self;
		[panel setFrameAutosaveName:@"MppFindReplacePanel"];
		[self buildUI];
		[self showTab:MppFindTabFind activate:NO];
	}
	return self;
}

- (NSButton *)check:(NSString *)title key:(NSString *)key
{
	NSButton *b = [NSButton checkboxWithTitle:title target:self action:@selector(optionChanged:)];
	b.state = [MppDefaults() boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff;
	b.identifier = key;
	return b;
}

- (NSComboBox *)combo:(NSArray *)history
{
	NSComboBox *c = [[NSComboBox alloc] init];
	c.translatesAutoresizingMaskIntoConstraints = NO;
	c.completes = NO;
	c.numberOfVisibleItems = 15;
	[c addItemsWithObjectValues:history ?: @[]];
	[c.widthAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;
	return c;
}

- (void)buildUI
{
	NSView *cv = self.window.contentView;
	MppPrefs *p = [MppPrefs shared];
	NSUserDefaults *d = MppDefaults();
	[d registerDefaults:@{@"find.wrap": @YES, @"find.subfolders": @YES, @"find.purge": @NO}];

	_tabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Find", @"Replace", @"Find in Files", @"Mark"]
	                                          trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
	_tabs.translatesAutoresizingMaskIntoConstraints = NO;

	_findCombo = [self combo:p.findHistory];
	_replaceCombo = [self combo:p.replaceHistory];
	_filterCombo = [self combo:p.filterHistory.count ? p.filterHistory : @[@"*.*"]];
	_dirCombo = [self combo:p.dirHistory];
	if (!_filterCombo.stringValue.length)
		_filterCombo.stringValue = p.filterHistory.firstObject ?: @"*.*";
	_dirCombo.stringValue = p.dirHistory.firstObject ?: NSHomeDirectory();
	NSButton *browse = [NSButton buttonWithTitle:@"…" target:self action:@selector(browseDir:)];

	NSGridView *grid = [NSGridView gridViewWithViews:@[
		@[[NSTextField labelWithString:@"Find what:"], _findCombo, [NSGridCell emptyContentView]],
		@[[NSTextField labelWithString:@"Replace with:"], _replaceCombo, [NSGridCell emptyContentView]],
		@[[NSTextField labelWithString:@"Filters:"], _filterCombo, [NSGridCell emptyContentView]],
		@[[NSTextField labelWithString:@"Directory:"], _dirCombo, browse],
	]];
	grid.translatesAutoresizingMaskIntoConstraints = NO;
	grid.rowSpacing = 8;
	grid.columnSpacing = 8;
	[grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
	grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
	_replaceRow = [grid rowAtIndex:1];
	_filterRow = [grid rowAtIndex:2];
	_dirRow = [grid rowAtIndex:3];

	_backward = [self check:@"Backward direction" key:@"find.backward"];
	_wholeWord = [self check:@"Match whole word only" key:@"find.wholeWord"];
	_matchCase = [self check:@"Match case" key:@"find.matchCase"];
	_wrap = [self check:@"Wrap around" key:@"find.wrap"];
	_inSelection = [self check:@"In selection" key:@"find.inSelection"];
	_bookmarkLine = [self check:@"Bookmark line" key:@"find.bookmarkLine"];
	_purge = [self check:@"Purge for each search" key:@"find.purge"];
	_subfolders = [self check:@"In all sub-folders" key:@"find.subfolders"];
	_hidden = [self check:@"In hidden folders" key:@"find.hidden"];
	_projectCurrentDoc = [self check:@"Follow current doc." key:@"find.followDoc"];

	_modeNormal = [NSButton radioButtonWithTitle:@"Normal" target:self action:@selector(modeChanged:)];
	_modeExtended = [NSButton radioButtonWithTitle:@"Extended (\\n, \\r, \\t, \\0, \\x…)" target:self action:@selector(modeChanged:)];
	_modeRegex = [NSButton radioButtonWithTitle:@"Regular expression" target:self action:@selector(modeChanged:)];
	_dotNL = [self check:@". matches newline" key:@"find.dotNL"];
	const NSInteger mode = [d integerForKey:@"find.mode"];
	_modeNormal.state = mode == 0 ? NSControlStateValueOn : NSControlStateValueOff;
	_modeExtended.state = mode == 1 ? NSControlStateValueOn : NSControlStateValueOff;
	_modeRegex.state = mode == 2 ? NSControlStateValueOn : NSControlStateValueOff;
	_dotNL.enabled = mode == 2;

	NSTextField *modeTitle = [NSTextField labelWithString:@"Search Mode"];
	modeTitle.font = [NSFont boldSystemFontOfSize:NSFont.systemFontSize];
	NSStackView *regexRow = [NSStackView stackViewWithViews:@[_modeRegex, _dotNL]];
	regexRow.spacing = 12;
	NSStackView *modeBox = [NSStackView stackViewWithViews:@[modeTitle, _modeNormal, _modeExtended, regexRow]];
	modeBox.orientation = NSUserInterfaceLayoutOrientationVertical;
	modeBox.alignment = NSLayoutAttributeLeading;
	modeBox.spacing = 4;
	modeBox.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *opts = [NSStackView stackViewWithViews:@[_bookmarkLine, _purge, _backward, _wholeWord, _matchCase, _wrap,
	                                                      _subfolders, _hidden]];
	opts.orientation = NSUserInterfaceLayoutOrientationVertical;
	opts.alignment = NSLayoutAttributeLeading;
	opts.spacing = 4;
	opts.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView *lower = [NSStackView stackViewWithViews:@[opts, modeBox]];
	lower.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	lower.alignment = NSLayoutAttributeTop;
	lower.spacing = 20;
	lower.translatesAutoresizingMaskIntoConstraints = NO;

	_buttons = [[NSStackView alloc] init];
	_buttons.orientation = NSUserInterfaceLayoutOrientationVertical;
	_buttons.alignment = NSLayoutAttributeWidth;
	_buttons.spacing = 6;
	_buttons.translatesAutoresizingMaskIntoConstraints = NO;

	_status = [NSTextField labelWithString:@""];
	_status.translatesAutoresizingMaskIntoConstraints = NO;
	_status.lineBreakMode = NSLineBreakByTruncatingTail;

	for (NSView *v in @[_tabs, grid, lower, _inSelection, _buttons, _status])
		[cv addSubview:v];
	_inSelection.translatesAutoresizingMaskIntoConstraints = NO;

	[NSLayoutConstraint activateConstraints:@[
		[_tabs.topAnchor constraintEqualToAnchor:cv.topAnchor constant:10],
		[_tabs.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:14],
		[grid.topAnchor constraintEqualToAnchor:_tabs.bottomAnchor constant:14],
		[grid.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:14],
		[_buttons.topAnchor constraintEqualToAnchor:grid.topAnchor],
		[_buttons.leadingAnchor constraintEqualToAnchor:grid.trailingAnchor constant:14],
		[_buttons.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-14],
		[_buttons.widthAnchor constraintEqualToConstant:250],
		[_inSelection.topAnchor constraintEqualToAnchor:grid.bottomAnchor constant:8],
		[_inSelection.leadingAnchor constraintEqualToAnchor:grid.leadingAnchor constant:90],
		[lower.topAnchor constraintEqualToAnchor:_inSelection.bottomAnchor constant:10],
		[lower.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:14],
		[_status.topAnchor constraintGreaterThanOrEqualToAnchor:lower.bottomAnchor constant:10],
		[_status.topAnchor constraintGreaterThanOrEqualToAnchor:_buttons.bottomAnchor constant:10],
		[_status.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:14],
		[_status.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-14],
		[_status.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-10],
	]];
}

- (NSButton *)button:(NSString *)title action:(SEL)action
{
	NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
	b.bezelStyle = NSBezelStyleRounded;
	return b;
}

- (void)rebuildButtons
{
	for (NSView *v in [_buttons.arrangedSubviews copy])
		[v removeFromSuperview];
	NSArray *defs;
	switch (_tab) {
		case MppFindTabFind:
			defs = @[@[@"Find Next", @"findNextClicked:"], @[@"Count", @"countClicked:"],
			         @[@"Find All in All Opened Documents", @"findAllOpenedClicked:"],
			         @[@"Find All in Current Document", @"findAllCurrentClicked:"], @[@"Close", @"closeClicked:"]];
			break;
		case MppFindTabReplace:
			defs = @[@[@"Find Next", @"findNextClicked:"], @[@"Replace", @"replaceClicked:"],
			         @[@"Replace All", @"replaceAllClicked:"],
			         @[@"Replace All in All Opened Documents", @"replaceAllOpenedClicked:"], @[@"Close", @"closeClicked:"]];
			break;
		case MppFindTabFindInFiles:
			defs = @[@[@"Find All", @"findInFilesClicked:"], @[@"Replace in Files", @"replaceInFilesClicked:"],
			         @[@"Close", @"closeClicked:"]];
			break;
		case MppFindTabMark:
			defs = @[@[@"Mark All", @"markAllClicked:"], @[@"Clear all marks", @"clearMarksClicked:"],
			         @[@"Copy Marked Text", @"copyMarkedClicked:"], @[@"Close", @"closeClicked:"]];
			break;
	}
	for (NSArray *def in defs) {
		NSButton *b = [self button:def[0] action:NSSelectorFromString(def[1])];
		[_buttons addArrangedSubview:b];
		[b.widthAnchor constraintEqualToAnchor:_buttons.widthAnchor].active = YES;
	}
	NSButton *first = (NSButton *)_buttons.arrangedSubviews.firstObject;
	first.keyEquivalent = @"\r";
	_stopButton = nil;
}

- (void)showTab:(MppFindTab)tab activate:(BOOL)activate
{
	_tab = tab;
	_tabs.selectedSegment = tab;
	_replaceRow.hidden = !(tab == MppFindTabReplace || tab == MppFindTabFindInFiles);
	_filterRow.hidden = _dirRow.hidden = tab != MppFindTabFindInFiles;
	_bookmarkLine.hidden = _purge.hidden = tab != MppFindTabMark;
	_backward.hidden = tab == MppFindTabFindInFiles || tab == MppFindTabMark;
	_wrap.hidden = tab == MppFindTabFindInFiles || tab == MppFindTabMark;
	_subfolders.hidden = _hidden.hidden = tab != MppFindTabFindInFiles;
	_inSelection.hidden = tab == MppFindTabFindInFiles;
	self.window.title = @[@"Find", @"Replace", @"Find in Files", @"Mark"][(NSUInteger)tab];
	[self rebuildButtons];
	[self.window.contentView layoutSubtreeIfNeeded];
	NSSize fit = self.window.contentView.fittingSize;
	NSRect frame = self.window.frame;
	NSRect content = [self.window contentRectForFrameRect:frame];
	const CGFloat newHeight = fit.height;
	content.origin.y += content.size.height - newHeight;   // keep the top edge in place
	content.size = NSMakeSize(MAX(fit.width, 700), newHeight);
	[self.window setFrame:[self.window frameRectForContentRect:content] display:YES];
	if (activate) {
		if (!self.window.isVisible) {
			NSRect f = self.window.frame;
			NSRect mf = _owner.window.frame;
			if (![self.window setFrameUsingName:@"MppFindReplacePanel"])
				[self.window setFrameOrigin:NSMakePoint(NSMidX(mf) - f.size.width / 2, NSMidY(mf) - f.size.height / 2)];
		}
		[self.window makeKeyAndOrderFront:nil];
		[self.window makeFirstResponder:_findCombo];
		[_findCombo selectText:nil];
	}
	// "In selection" checkbox is useful when a multi-line selection exists
	const BOOL multiLine = [_owner sci:SCI_LINEFROMPOSITION w:(uptr_t)[_owner sci:SCI_GETSELECTIONSTART]] !=
	                       [_owner sci:SCI_LINEFROMPOSITION w:(uptr_t)[_owner sci:SCI_GETSELECTIONEND]];
	if (activate && multiLine && tab != MppFindTabFindInFiles)
		_inSelection.state = NSControlStateValueOn;
}

- (void)showTab:(MppFindTab)tab
{
	[self showTab:tab activate:YES];
}

- (void)tabChanged:(id)sender
{
	[self showTab:(MppFindTab)_tabs.selectedSegment activate:NO];
}

- (void)setFindText:(NSString *)text
{
	_findCombo.stringValue = text ?: @"";
}

- (NSString *)findText
{
	return _findCombo.stringValue;
}

- (void)setFindDirectory:(NSString *)dir
{
	if (dir.length)
		_dirCombo.stringValue = dir;
}

- (void)optionChanged:(NSButton *)b
{
	if (b.identifier)
		[MppDefaults() setBool:b.state == NSControlStateValueOn forKey:b.identifier];
}

- (void)modeChanged:(NSButton *)b
{
	const NSInteger mode = b == _modeRegex ? 2 : (b == _modeExtended ? 1 : 0);
	_modeNormal.state = mode == 0 ? NSControlStateValueOn : NSControlStateValueOff;
	_modeExtended.state = mode == 1 ? NSControlStateValueOn : NSControlStateValueOff;
	_modeRegex.state = mode == 2 ? NSControlStateValueOn : NSControlStateValueOff;
	_dotNL.enabled = mode == 2;
	[MppDefaults() setInteger:mode forKey:@"find.mode"];
}

- (void)browseDir:(id)sender
{
	NSOpenPanel *p = [NSOpenPanel openPanel];
	p.canChooseDirectories = YES;
	p.canChooseFiles = NO;
	p.directoryURL = [NSURL fileURLWithPath:_dirCombo.stringValue];
	if ([p runModal] == NSModalResponseOK)
		_dirCombo.stringValue = p.URL.path;
}

- (MppFindOptions)options
{
	MppFindOptions o;
	o.matchCase = _matchCase.state == NSControlStateValueOn;
	o.wholeWord = _wholeWord.state == NSControlStateValueOn;
	o.wrapAround = _wrap.state == NSControlStateValueOn;
	o.backward = _backward.state == NSControlStateValueOn;
	o.inSelection = _inSelection.state == NSControlStateValueOn && !_inSelection.hidden;
	o.dotMatchesNewline = _dotNL.state == NSControlStateValueOn;
	o.mode = _modeRegex.state == NSControlStateValueOn ? MppSearchRegex
	       : _modeExtended.state == NSControlStateValueOn ? MppSearchExtended : MppSearchNormal;
	o.bookmarkLine = _bookmarkLine.state == NSControlStateValueOn;
	o.purgeBeforeMark = _purge.state == NSControlStateValueOn;
	o.inSubfolders = _subfolders.state == NSControlStateValueOn;
	o.inHidden = _hidden.state == NSControlStateValueOn;
	return o;
}

// ---- status ----------------------------------------------------------------------------------

- (void)setStatus:(NSString *)msg kind:(int)kind   // 0 message, 1 not found, 2 end reached
{
	// System colours adapt to light/dark appearance of the panel (the theme colours target the editor)
	NSColor *colors[] = {NSColor.systemBlueColor, NSColor.systemRedColor, NSColor.systemGreenColor};
	_status.textColor = colors[kind];
	_status.stringValue = msg ?: @"";
	if (!self.window.isVisible && msg.length)
		[_owner setStatusMessage:msg];
}

- (void)regexError
{
	NSString *err = @(g_exceptionMessage.c_str());
	[self setStatus:[NSString stringWithFormat:@"Find: Invalid regular expression%@%@", err.length ? @" - " : @"", err] kind:1];
}

static void addHistory(NSComboBox *combo, NSString *value, NSString *key)
{
	if (!value.length)
		return;
	NSMutableArray *h = [[MppDefaults() stringArrayForKey:key] mutableCopy] ?: [NSMutableArray array];
	[h removeObject:value];
	[h insertObject:value atIndex:0];
	while (h.count > 30)
		[h removeLastObject];
	[MppDefaults() setObject:h forKey:key];
	[combo removeAllItems];
	[combo addItemsWithObjectValues:h];
	combo.stringValue = value;
}

- (void)saveHistory
{
	addHistory(_findCombo, _findCombo.stringValue, @"findHistory");
	if (!_replaceRow.hidden)
		addHistory(_replaceCombo, _replaceCombo.stringValue, @"replaceHistory");
	if (!_dirRow.hidden) {
		addHistory(_filterCombo, _filterCombo.stringValue, @"filterHistory");
		addHistory(_dirCombo, _dirCombo.stringValue, @"dirHistory");
	}
}

- (std::string)prepared:(NSString *)s options:(const MppFindOptions &)o
{
	std::string t = s.UTF8String ?: "";
	if (o.mode == MppSearchExtended)
		t = MppExpandExtended(t);
	return t;
}

// ---- core find --------------------------------------------------------------------------------

- (BOOL)findText:(const std::string &)text forward:(BOOL)forward options:(MppFindOptions)o showStatus:(BOOL)showStatus
{
	return [self findText:text forward:forward options:o showStatus:showStatus forReplace:NO];
}

- (BOOL)findText:(const std::string &)text forward:(BOOL)forward options:(MppFindOptions)o showStatus:(BOOL)showStatus forReplace:(BOOL)forReplace
{
	if (text.empty())
		return NO;
	ScintillaView *v = _owner.activeEditor;
	const sptr_t docLen = S(v, SCI_GETLENGTH);
	const sptr_t selStart = S(v, SCI_GETSELECTIONSTART), selEnd = S(v, SCI_GETSELECTIONEND);
	sptr_t start, end;
	if (forReplace) {
		start = selStart;
		end = docLen;
	} else if (forward) {
		start = selEnd;
		end = docLen;
	} else {
		start = selStart;
		end = 0;
	}
	int flags = MppSearchFlags(o) | SCFIND_REGEXP_SKIPCRLFASONE;
	flags |= forReplace ? (SCFIND_REGEXP_EMPTYMATCH_ALL | SCFIND_REGEXP_EMPTYMATCH_ALLOWATSTART) : SCFIND_REGEXP_EMPTYMATCH_ALL;
	if (S(v, SCI_GETCHARAT, (uptr_t)(start - 1)) == '\r' && S(v, SCI_GETCHARAT, (uptr_t)start) == '\n')
		flags = (flags & ~SCFIND_REGEXP_EMPTYMATCH_MASK) | SCFIND_REGEXP_EMPTYMATCH_NONE;
	S(v, SCI_SETSEARCHFLAGS, (uptr_t)flags);
	S(v, SCI_SETTARGETRANGE, (uptr_t)start, end);
	sptr_t pos = S(v, SCI_SEARCHINTARGET, text.size(), (sptr_t)text.data());
	int status = 0;
	if (pos == -2) {
		[self regexError];
		return NO;
	}
	if (pos == -1 && o.wrapAround) {
		if (forward || forReplace) {
			start = 0;
			end = docLen;
		} else {
			start = docLen;
			end = 0;
		}
		S(v, SCI_SETTARGETRANGE, (uptr_t)start, end);
		pos = S(v, SCI_SEARCHINTARGET, text.size(), (sptr_t)text.data());
		status = 2;
	}
	if (pos < 0) {
		if (showStatus) {
			NSString *what = [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding] ?: @"";
			[self setStatus:[NSString stringWithFormat:@"Find: Can't find the text \"%@\"", what] kind:1];
			NSBeep();
		}
		return NO;
	}
	const sptr_t tEnd = S(v, SCI_GETTARGETEND);
	[_owner selectRangeFrom:pos to:tEnd];
	if (showStatus) {
		if (status == 2)
			[self setStatus:forward ? @"Find: Found the 1st occurrence from the top. The end of the document has been reached."
			                        : @"Find: Found the 1st occurrence from the bottom. The beginning of the document has been reached."
			           kind:2];
		else
			[self setStatus:@"" kind:0];
	}
	return YES;
}

- (BOOL)findNext:(BOOL)forward
{
	MppFindOptions o = self.options;
	if (!_findCombo.stringValue.length) {
		[self showTab:MppFindTabFind];
		return NO;
	}
	const BOOL backward = o.backward;
	const BOOL fwd = backward ? !forward : forward;
	[_owner.macros recordFind:@{@"action": @"findNext", @"text": _findCombo.stringValue, @"matchCase": @(o.matchCase),
	                            @"wholeWord": @(o.wholeWord), @"mode": @(o.mode), @"wrap": @(o.wrapAround),
	                            @"dotNL": @(o.dotMatchesNewline), @"backward": @(!fwd)}];
	return [self findText:[self prepared:_findCombo.stringValue options:o] forward:fwd options:o showStatus:YES];
}

- (void)findNextClicked:(id)sender
{
	[self saveHistory];
	[self findNext:YES];
}

- (void)rangeForOptions:(const MppFindOptions &)o view:(ScintillaView *)v start:(sptr_t *)s end:(sptr_t *)e
{
	if (o.inSelection && !S(v, SCI_GETSELECTIONEMPTY)) {
		*s = S(v, SCI_GETSELECTIONSTART);
		*e = S(v, SCI_GETSELECTIONEND);
	} else {
		*s = 0;
		*e = S(v, SCI_GETLENGTH);
	}
}

- (void)countClicked:(id)sender
{
	[self saveHistory];
	MppFindOptions o = self.options;
	ScintillaView *v = _owner.activeEditor;
	sptr_t s, e;
	[self rangeForOptions:o view:v start:&s end:&e];
	ProcessResult r = processRange(v, OpCount, [self prepared:_findCombo.stringValue options:o], "", o, s, e);
	if (r.invalidRegex)
		[self regexError];
	else
		[self setStatus:[NSString stringWithFormat:@"Count: %d match%@%@", r.count, r.count == 1 ? @"" : @"es",
		                                           o.inSelection ? @" in selection" : @""] kind:0];
}

- (void)replaceClicked:(id)sender
{
	[self saveHistory];
	MppFindOptions o = self.options;
	ScintillaView *v = _owner.activeEditor;
	if (S(v, SCI_GETREADONLY)) {
		NSBeep();
		return;
	}
	const std::string find = [self prepared:_findCombo.stringValue options:o];
	const std::string repl = [self prepared:_replaceCombo.stringValue options:o];
	const sptr_t selStart = S(v, SCI_GETSELECTIONSTART), selEnd = S(v, SCI_GETSELECTIONEND);
	// Does the current selection match? Then replace it.
	if ([self findText:find forward:YES options:o showStatus:NO forReplace:YES] &&
	    S(v, SCI_GETSELECTIONSTART) == selStart && S(v, SCI_GETSELECTIONEND) == selEnd) {
		S(v, SCI_SETTARGETRANGE, (uptr_t)selStart, selEnd);
		sptr_t len;
		if (o.mode == MppSearchRegex) {
			// re-run the search on the target so that the regex substitution has the right groups
			S(v, SCI_SETSEARCHFLAGS, (uptr_t)(MppSearchFlags(o) | SCFIND_REGEXP_EMPTYMATCH_ALL | SCFIND_REGEXP_EMPTYMATCH_ALLOWATSTART));
			S(v, SCI_SEARCHINTARGET, find.size(), (sptr_t)find.data());
			len = S(v, SCI_REPLACETARGETRE, (uptr_t)-1, (sptr_t)repl.c_str());
		} else {
			len = S(v, SCI_REPLACETARGET, repl.size(), (sptr_t)repl.data());
		}
		const sptr_t newEnd = S(v, SCI_GETTARGETSTART) + len;
		S(v, SCI_SETSEL, (uptr_t)newEnd, newEnd);
		if (![self findText:find forward:!o.backward options:o showStatus:NO])
			[self setStatus:@"Replace: 1 occurrence was replaced. No more occurrences found." kind:2];
		else
			[self setStatus:@"Replace: 1 occurrence was replaced. The next occurrence found." kind:0];
	} else {
		S(v, SCI_SETSEL, (uptr_t)selStart, selEnd);
		[self findText:find forward:!o.backward options:o showStatus:YES];
	}
}

- (void)replaceAllClicked:(id)sender
{
	[self saveHistory];
	MppFindOptions o = self.options;
	ScintillaView *v = _owner.activeEditor;
	if (S(v, SCI_GETREADONLY)) {
		NSBeep();
		return;
	}
	sptr_t s, e;
	[self rangeForOptions:o view:v start:&s end:&e];
	ProcessResult r = processRange(v, OpReplaceAll, [self prepared:_findCombo.stringValue options:o],
	                               [self prepared:_replaceCombo.stringValue options:o], o, s, e);
	if (r.invalidRegex)
		[self regexError];
	else
		[self setStatus:[NSString stringWithFormat:@"Replace All: %d occurrence%@ %@ replaced%@", r.count, r.count == 1 ? @"" : @"s",
		                                           r.count == 1 ? @"was" : @"were", o.inSelection ? @" in selection" : @""]
		           kind:r.count ? 0 : 1];
}

// Run an operation over every opened document (scratch view for those not displayed)
- (int)processOpenedDocuments:(MppProcessOp)op hitsOut:(std::vector<std::pair<MppDocument *, std::vector<MppSearchHit>>> *)hitsOut
                         invalid:(BOOL *)invalid
{
	MppFindOptions o = self.options;
	o.inSelection = false;
	const std::string find = [self prepared:_findCombo.stringValue options:o];
	const std::string repl = [self prepared:_replaceCombo.stringValue options:o];
	int total = 0;
	MppDocumentManager *dm = MppDocumentManager.shared;
	for (MppDocument *doc in [_owner allDocuments]) {
		if (op == OpReplaceAll && (doc.userReadOnly || doc.fileReadOnly || doc.monitoring))
			continue;
		MppEditPane *pane = [_owner paneForDocument:doc];
		ScintillaView *v;
		BOOL scratch = NO;
		if (pane && pane.currentDocument == doc) {
			v = pane.editor;
		} else {
			v = [dm attachScratchViewTo:doc];
			scratch = YES;
		}
		ProcessResult r = processRange(v, op, find, repl, o, 0, S(v, SCI_GETLENGTH));
		if (scratch) {
			if (op == OpReplaceAll && r.count)
				doc.dirty = S(v, SCI_GETMODIFY) != 0;
			[dm detachScratchView];
		}
		if (r.invalidRegex) {
			*invalid = YES;
			return 0;
		}
		total += r.count;
		if (hitsOut && !r.hits.empty())
			hitsOut->emplace_back(doc, r.hits);
	}
	return total;
}

- (void)replaceAllOpenedClicked:(id)sender
{
	[self saveHistory];
	BOOL invalid = NO;
	int n = [self processOpenedDocuments:OpReplaceAll hitsOut:nullptr invalid:&invalid];
	if (invalid)
		[self regexError];
	else
		[self setStatus:[NSString stringWithFormat:@"Replace in Opened Files: %d occurrence%@ replaced", n, n == 1 ? @" was" : @"s were"]
		           kind:n ? 0 : 1];
}

- (NSString *)searchHeaderText
{
	return _findCombo.stringValue;
}

- (void)findAllCurrentClicked:(id)sender
{
	[self saveHistory];
	MppFindOptions o = self.options;
	ScintillaView *v = _owner.activeEditor;
	sptr_t s, e;
	[self rangeForOptions:o view:v start:&s end:&e];
	ProcessResult r = processRange(v, OpFindAll, [self prepared:_findCombo.stringValue options:o], "", o, s, e);
	if (r.invalidRegex) {
		[self regexError];
		return;
	}
	MppSearchResultsPanel *res = _owner.searchResults;
	[res beginSearch:[self searchHeaderText]];
	MppDocument *doc = _owner.currentDocument;
	if (!r.hits.empty())
		[res addFile:doc.filePath ?: doc.displayName hits:r.hits];
	[res finishSearchWithFileCount:r.hits.empty() ? 0 : 1 searched:1 inSelection:o.inSelection];
	[_owner showSearchResults:YES];
	[self setStatus:[NSString stringWithFormat:@"Find All: %d hit%@", r.count, r.count == 1 ? @"" : @"s"] kind:r.count ? 0 : 1];
}

- (void)findAllOpenedClicked:(id)sender
{
	[self saveHistory];
	BOOL invalid = NO;
	std::vector<std::pair<MppDocument *, std::vector<MppSearchHit>>> hits;
	int n = [self processOpenedDocuments:OpFindAll hitsOut:&hits invalid:&invalid];
	if (invalid) {
		[self regexError];
		return;
	}
	MppSearchResultsPanel *res = _owner.searchResults;
	[res beginSearch:[self searchHeaderText]];
	for (auto &h : hits)
		[res addFile:h.first.filePath ?: h.first.displayName hits:h.second];
	[res finishSearchWithFileCount:(NSInteger)hits.size() searched:(NSInteger)_owner.allDocuments.count inSelection:NO];
	[_owner showSearchResults:YES];
	[self setStatus:[NSString stringWithFormat:@"Find All in Opened Files: %d hit%@", n, n == 1 ? @"" : @"s"] kind:n ? 0 : 1];
}

// ---- Mark ----------------------------------------------------------------------------------

- (int)markAll:(const std::string &)text options:(MppFindOptions)o indicator:(int)indicator bookmark:(BOOL)bookmark
{
	ScintillaView *v = _owner.activeEditor;
	o.bookmarkLine = bookmark;
	sptr_t s, e;
	[self rangeForOptions:o view:v start:&s end:&e];
	if (indicator != MPP_INDIC_FOUND_STYLE) {
		S(v, SCI_SETINDICATORCURRENT, (uptr_t)indicator);
		S(v, SCI_INDICATORCLEARRANGE, 0, S(v, SCI_GETLENGTH));
	}
	ProcessResult r = processRange(v, OpMark, text, "", o, s, e, indicator);
	if (r.invalidRegex)
		[self regexError];
	return r.count;
}

- (void)clearMarks
{
	ScintillaView *v = _owner.activeEditor;
	S(v, SCI_SETINDICATORCURRENT, MPP_INDIC_FOUND_STYLE);
	S(v, SCI_INDICATORCLEARRANGE, 0, S(v, SCI_GETLENGTH));
	S(v, SCI_MARKERDELETEALL, MPP_MARK_BOOKMARK);
}

- (void)markAllClicked:(id)sender
{
	[self saveHistory];
	MppFindOptions o = self.options;
	if (o.purgeBeforeMark)
		[self clearMarks];
	int n = [self markAll:[self prepared:_findCombo.stringValue options:o] options:o indicator:MPP_INDIC_FOUND_STYLE bookmark:o.bookmarkLine];
	[self setStatus:[NSString stringWithFormat:@"Mark: %d match%@", n, n == 1 ? @"" : @"es"] kind:n ? 0 : 1];
}

- (void)clearMarksClicked:(id)sender
{
	[self clearMarks];
	[self setStatus:@"All marks cleared" kind:0];
}

- (void)copyMarkedClicked:(id)sender
{
	[_owner executeCommand:CMD_SEARCH_MARKEDTOCLIP];
	[self setStatus:@"Marked text copied to clipboard" kind:0];
}

- (void)closeClicked:(id)sender
{
	[self.window orderOut:nil];
	[_owner.window makeKeyAndOrderFront:nil];
}

- (void)cancelOperation:(id)sender
{
	[self closeClicked:sender];
}

// ---- Find in files -------------------------------------------------------------------------------

static bool matchWildcard(const char *pattern, const char *s)
{
	return fnmatch(pattern, s, FNM_CASEFOLD) == 0;
}

- (void)findInFilesClicked:(id)sender
{
	[self startFindInFiles:NO];
}

- (void)replaceInFilesClicked:(id)sender
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = [NSString stringWithFormat:@"Are you sure you want to replace all occurrences in:\n%@\nfor file type: %@",
	                 _dirCombo.stringValue, _filterCombo.stringValue];
	[a addButtonWithTitle:@"Replace"];
	[a addButtonWithTitle:@"Cancel"];
	if ([a runModal] != NSAlertFirstButtonReturn)
		return;
	[self startFindInFiles:YES];
}

- (void)startFindInFiles:(BOOL)replace
{
	if (_fifQueue)
		return;
	[self saveHistory];
	NSString *dir = _dirCombo.stringValue.stringByExpandingTildeInPath;
	BOOL isDir = NO;
	if (![NSFileManager.defaultManager fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
		[self setStatus:@"Find in Files: Invalid directory" kind:1];
		return;
	}
	if (!_findCombo.stringValue.length)
		return;
	_fifOpts = self.options;
	_fifOpts.inSelection = false;
	_fifFind = [self prepared:_findCombo.stringValue options:_fifOpts];
	_fifReplaceText = [self prepared:_replaceCombo.stringValue options:_fifOpts];
	_fifReplace = replace;
	_fifCancel = NO;
	_fifSearched = _fifFiles = _fifHits = 0;

	// Filters: "*.cpp *.h" with exclusions "!*.obj" and "!+\folder" / "!\folder"
	NSMutableArray *includes = [NSMutableArray array], *excludes = [NSMutableArray array], *excludeDirs = [NSMutableArray array];
	for (NSString *f in [_filterCombo.stringValue componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ;"]]) {
		if (!f.length)
			continue;
		if ([f hasPrefix:@"!+\\"] || [f hasPrefix:@"!+/"])
			[excludeDirs addObject:[f substringFromIndex:3]];
		else if ([f hasPrefix:@"!\\"] || [f hasPrefix:@"!/"])
			[excludeDirs addObject:[f substringFromIndex:2]];
		else if ([f hasPrefix:@"!"])
			[excludes addObject:[f substringFromIndex:1]];
		else
			[includes addObject:f];
	}
	if (!includes.count)
		[includes addObject:@"*"];

	NSMutableArray *files = [NSMutableArray array];
	NSDirectoryEnumerationOptions opts = 0;
	if (!_fifOpts.inSubfolders)
		opts |= NSDirectoryEnumerationSkipsSubdirectoryDescendants;
	if (!_fifOpts.inHidden)
		opts |= NSDirectoryEnumerationSkipsHiddenFiles;
	NSDirectoryEnumerator *en = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:dir]
	                                               includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey]
	                                                                  options:opts errorHandler:nil];
	for (NSURL *u in en) {
		NSNumber *isDirectory = nil;
		[u getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
		NSString *name = u.lastPathComponent;
		if (isDirectory.boolValue) {
			for (NSString *x in excludeDirs)
				if (matchWildcard(x.UTF8String, name.UTF8String))
					[en skipDescendants];
			continue;
		}
		BOOL ok = NO;
		for (NSString *inc in includes)
			if (matchWildcard(inc.UTF8String, name.UTF8String) || ([inc isEqualToString:@"*.*"]))
				ok = YES;
		for (NSString *exc in excludes)
			if (matchWildcard(exc.UTF8String, name.UTF8String))
				ok = NO;
		if (ok)
			[files addObject:u.path];
	}
	_fifQueue = files;
	[_owner.searchResults beginSearch:_findCombo.stringValue];
	[_owner showSearchResults:YES];
	_stopButton = [self button:@"Stop" action:@selector(stopFindInFiles:)];
	[_buttons addArrangedSubview:_stopButton];
	[self processFindInFilesChunk];
}

- (void)stopFindInFiles:(id)sender
{
	_fifCancel = YES;
}

- (void)processFindInFilesChunk
{
	MppDocumentManager *dm = MppDocumentManager.shared;
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.08];
	while (_fifQueue.count && !_fifCancel && [deadline timeIntervalSinceNow] > 0) {
		NSString *path = _fifQueue.firstObject;
		[_fifQueue removeObjectAtIndex:0];
		++_fifSearched;
		ProcessResult r;
		MppDocument *open = [dm documentForPath:path];
		if (open) {
			MppEditPane *pane = [_owner paneForDocument:open];
			ScintillaView *v = (pane && pane.currentDocument == open) ? pane.editor : [dm attachScratchViewTo:open];
			const MppProcessOp op = _fifReplace && !(open.userReadOnly || open.fileReadOnly) ? OpReplaceAll : OpFindAll;
			r = processRange(v, op, _fifFind, _fifReplaceText, _fifOpts, 0, S(v, SCI_GETLENGTH));
			if (op == OpReplaceAll && r.count)
				open.dirty = S(v, SCI_GETMODIFY) != 0;
			if (!(pane && pane.currentDocument == open))
				[dm detachScratchView];
		} else {
			NSData *raw = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
			if (!raw || raw.length > 200 * 1024 * 1024)
				continue;
			// skip binary files (NUL bytes in the first block) unless UTF-16 with BOM
			const unsigned char *b = (const unsigned char *)raw.bytes;
			const size_t probe = std::min<size_t>(raw.length, 8000);
			const bool bom16 = raw.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF));
			if (!bom16 && memchr(b, 0, probe))
				continue;
			std::string utf8;
			MppEncoding enc;
			MppDecode(raw, nullptr, true, utf8, enc);
			sptr_t sciDoc = [dm createSciDocumentWithText:utf8];
			ScintillaView *v = [dm attachScratchViewToSciDocument:sciDoc];
			r = processRange(v, _fifReplace ? OpReplaceAll : OpFindAll, _fifFind, _fifReplaceText, _fifOpts, 0, S(v, SCI_GETLENGTH));
			if (_fifReplace && r.count > 0) {
				const char *p = (const char *)S(v, SCI_GETCHARACTERPOINTER);
				NSData *out = MppEncode(p, (size_t)S(v, SCI_GETLENGTH), enc, true);
				[out writeToFile:path options:0 error:nil];
			}
			[dm detachScratchView];
			[dm releaseSciDocument:sciDoc];
		}
		if (r.invalidRegex) {
			[self regexError];
			_fifCancel = YES;
			break;
		}
		if (r.count) {
			++_fifFiles;
			_fifHits += r.count;
			if (!_fifReplace)
				[_owner.searchResults addFile:path hits:r.hits];
		}
	}
	[self setStatus:[NSString stringWithFormat:@"%@: %ld hit%@ in %ld file%@ (%ld searched, %lu remaining)",
	                 _fifReplace ? @"Replace in Files" : @"Find in Files", (long)_fifHits, _fifHits == 1 ? @"" : @"s",
	                 (long)_fifFiles, _fifFiles == 1 ? @"" : @"s", (long)_fifSearched, (unsigned long)_fifQueue.count]
	           kind:0];
	if (_fifQueue.count && !_fifCancel) {
		dispatch_async(dispatch_get_main_queue(), ^{ [self processFindInFilesChunk]; });
		return;
	}
	[_owner.searchResults finishSearchWithFileCount:_fifFiles searched:_fifSearched inSelection:NO];
	[_stopButton removeFromSuperview];
	_stopButton = nil;
	_fifQueue = nil;
	if (_fifReplace)
		[self setStatus:[NSString stringWithFormat:@"Replace in Files: %ld occurrence%@ replaced in %ld file%@",
		                 (long)_fifHits, _fifHits == 1 ? @" was" : @"s were", (long)_fifFiles, _fifFiles == 1 ? @"" : @"s"]
		           kind:0];
}

// ---- Incremental search ----------------------------------------------------------------------------

- (void)showIncrementalSearch
{
	if (!_incPanel) {
		_incPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 620, 40)
		                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
		                                         backing:NSBackingStoreBuffered defer:YES];
		_incPanel.title = @"Incremental Search";
		_incPanel.floatingPanel = YES;
		_incField = [[NSSearchField alloc] init];
		_incField.target = self;
		_incField.action = @selector(incChanged:);
		_incField.sendsSearchStringImmediately = YES;
		_incField.sendsWholeSearchString = NO;
		_incField.delegate = (id)self;
		NSButton *prev = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:@"Previous"]
		                                    target:self action:@selector(incPrev:)];
		NSButton *next = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"Next"]
		                                    target:self action:@selector(incNext:)];
		_incMatchCase = [NSButton checkboxWithTitle:@"Match case" target:self action:@selector(incChanged:)];
		_incHighlight = [NSButton checkboxWithTitle:@"Highlight all" target:self action:@selector(incChanged:)];
		_incHighlight.state = NSControlStateValueOn;
		_incStatus = [NSTextField labelWithString:@""];
		NSStackView *s = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"Find:"], _incField, prev, next,
		                                                   _incMatchCase, _incHighlight, _incStatus]];
		s.spacing = 8;
		s.edgeInsets = NSEdgeInsetsMake(8, 10, 8, 10);
		s.translatesAutoresizingMaskIntoConstraints = NO;
		[_incField.widthAnchor constraintEqualToConstant:220].active = YES;
		[_incPanel.contentView addSubview:s];
		[NSLayoutConstraint activateConstraints:@[
			[s.leadingAnchor constraintEqualToAnchor:_incPanel.contentView.leadingAnchor],
			[s.trailingAnchor constraintEqualToAnchor:_incPanel.contentView.trailingAnchor],
			[s.topAnchor constraintEqualToAnchor:_incPanel.contentView.topAnchor],
			[s.bottomAnchor constraintEqualToAnchor:_incPanel.contentView.bottomAnchor],
		]];
	}
	_incStart = [_owner sci:SCI_GETSELECTIONSTART];
	NSRect mf = _owner.window.frame;
	[_incPanel setFrameOrigin:NSMakePoint(NSMinX(mf) + 20, NSMinY(mf) + 40)];
	[_incPanel makeKeyAndOrderFront:nil];
	[_incPanel makeFirstResponder:_incField];
}

- (MppFindOptions)incOptions
{
	MppFindOptions o;
	o.matchCase = _incMatchCase.state == NSControlStateValueOn;
	o.wrapAround = true;
	return o;
}

- (void)incHighlight
{
	ScintillaView *v = _owner.activeEditor;
	S(v, SCI_SETINDICATORCURRENT, MPP_INDIC_FOUND_STYLE_INC);
	S(v, SCI_INDICATORCLEARRANGE, 0, S(v, SCI_GETLENGTH));
	if (_incHighlight.state != NSControlStateValueOn || !_incField.stringValue.length)
		return;
	processRange(v, OpMark, _incField.stringValue.UTF8String, "", [self incOptions], 0, S(v, SCI_GETLENGTH), MPP_INDIC_FOUND_STYLE_INC);
}

- (void)incChanged:(id)sender
{
	NSString *t = _incField.stringValue;
	[self incHighlight];
	if (!t.length) {
		_incStatus.stringValue = @"";
		return;
	}
	[_owner sci:SCI_SETSEL w:(uptr_t)_incStart l:_incStart];
	const BOOL ok = [self findText:t.UTF8String forward:YES options:[self incOptions] showStatus:NO];
	_incStatus.stringValue = ok ? @"" : @"Phrase not found";
	_incStatus.textColor = ok ? NSColor.labelColor : NSColor.systemRedColor;
}

- (void)incNext:(id)sender
{
	if (_incField.stringValue.length)
		[self findText:_incField.stringValue.UTF8String forward:YES options:[self incOptions] showStatus:NO];
	_incStart = [_owner sci:SCI_GETSELECTIONSTART];
}

- (void)incPrev:(id)sender
{
	if (_incField.stringValue.length)
		[self findText:_incField.stringValue.UTF8String forward:NO options:[self incOptions] showStatus:NO];
	_incStart = [_owner sci:SCI_GETSELECTIONSTART];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)sel
{
	if (control == _incField) {
		if (sel == @selector(insertNewline:)) {
			if (NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)
				[self incPrev:nil];
			else
				[self incNext:nil];
			return YES;
		}
		if (sel == @selector(cancelOperation:)) {
			[_incPanel orderOut:nil];
			ScintillaView *v = _owner.activeEditor;
			S(v, SCI_SETINDICATORCURRENT, MPP_INDIC_FOUND_STYLE_INC);
			S(v, SCI_INDICATORCLEARRANGE, 0, S(v, SCI_GETLENGTH));
			[_owner.window makeKeyAndOrderFront:nil];
			return YES;
		}
	}
	return NO;
}

@end
