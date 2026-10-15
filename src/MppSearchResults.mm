// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppSearchResults.h"
#import "MppMainWindowController.h"
#import "MppStyler.h"
#import "MppEditing.h"
#import "MppLanguages.h"
#include "Scintilla.h"
#include "SciLexer.h"

namespace {
struct ResultLine {
	NSInteger pathIndex = -1;        // -1: header line
	sptr_t lineNumber = 0;
	sptr_t matchStart = 0, matchEnd = 0;   // relative to the line start in the source document
};
}

@implementation MppSearchResultsPanel {
	MppScintillaView *_view;
	std::vector<SearchResultMarkingLine> _markings;
	SearchResultMarkings _markStruct;
	std::vector<ResultLine> _lines;
	NSMutableArray<NSString *> *_paths;
	NSString *_currentWhat;
	sptr_t _insertPos;
	sptr_t _insertLine;
	NSInteger _totalHits;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_paths = [NSMutableArray array];
		_markStruct._length = 0;
		_markStruct._markings = nullptr;

		NSTextField *title = [NSTextField labelWithString:@"Search results"];
		title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
		NSButton *close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"]
		                                     target:self action:@selector(closeClicked:)];
		close.bordered = NO;
		NSStackView *header = [NSStackView stackViewWithViews:@[title, [[NSView alloc] init], close]];
		header.edgeInsets = NSEdgeInsetsMake(2, 8, 2, 6);
		header.translatesAutoresizingMaskIntoConstraints = NO;
		[header.arrangedSubviews[1] setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

		_view = [[MppScintillaView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - 22)];
		_view.translatesAutoresizingMaskIntoConstraints = NO;
		_view.delegate = self;
		__weak MppSearchResultsPanel *weakSelf = self;
		_view.contextMenuProvider = ^NSMenu *(MppScintillaView *v) { return [weakSelf contextMenu]; };
		_view.keyDownHandler = ^BOOL(MppScintillaView *v, NSEvent *e) {
			if (e.keyCode == 36 || e.keyCode == 76) {   // Return / Enter
				[weakSelf openLine:[v message:SCI_LINEFROMPOSITION wParam:(uptr_t)[v message:SCI_GETCURRENTPOS]]];
				return YES;
			}
			if (e.keyCode == 53) {   // Escape
				[weakSelf closeClicked:nil];
				return YES;
			}
			return NO;
		};
		[self addSubview:header];
		[self addSubview:_view];
		[NSLayoutConstraint activateConstraints:@[
			[header.topAnchor constraintEqualToAnchor:self.topAnchor],
			[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[header.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[header.heightAnchor constraintEqualToConstant:22],
			[_view.topAnchor constraintEqualToAnchor:header.bottomAnchor],
			[_view.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_view.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_view.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
		[self applyTheme];
	}
	return self;
}

- (MppScintillaView *)resultView
{
	return _view;
}

- (sptr_t)sci:(unsigned int)m w:(uptr_t)w l:(sptr_t)l
{
	return [_view message:m wParam:w lParam:l];
}

- (void)updateMarkingsProperty
{
	_markStruct._length = (intptr_t)_markings.size();
	_markStruct._markings = _markings.empty() ? nullptr : _markings.data();
	char buf[64];
	snprintf(buf, sizeof buf, "%p", (void *)&_markStruct);
	[self sci:SCI_SETPROPERTY w:(uptr_t)"@MarkingsStruct" l:(sptr_t)buf];
}

- (void)applyTheme
{
	[MppStyler setupSearchResultView:_view];
	[self sci:SCI_SETPROPERTY w:(uptr_t)"fold" l:(sptr_t)"1"];
	[self sci:SCI_SETPROPERTY w:(uptr_t)"fold.compact" l:(sptr_t)"0"];
	[self updateMarkingsProperty];
	[self sci:SCI_SETCARETLINEVISIBLEALWAYS w:1 l:0];
	// The finder uses its own "Current line background colour" (style 6 of the searchResult lexer)
	if (const MppLexerStyler *ls = [MppLanguages.shared theme]->lexer("searchResult"))
		if (const MppStyle *cur = ls->findByID(SCE_SEARCHRESULT_CURRENT_LINE))
			[self sci:SCI_SETELEMENTCOLOUR w:SC_ELEMENT_CARET_LINE_BACK l:(sptr_t)(cur->bgColor | 0xFF000000)];
	[self sci:SCI_COLOURISE w:0 l:-1];
}

- (void)closeClicked:(id)sender
{
	if (_onClose)
		_onClose();
}

- (void)insertText:(const std::string &)text markings:(const std::vector<SearchResultMarkingLine> &)marks
             lines:(const std::vector<ResultLine> &)lines
{
	[self sci:SCI_SETREADONLY w:0 l:0];
	_markings.insert(_markings.begin() + _insertLine, marks.begin(), marks.end());
	_lines.insert(_lines.begin() + _insertLine, lines.begin(), lines.end());
	[self updateMarkingsProperty];
	[self sci:SCI_INSERTTEXT w:(uptr_t)_insertPos l:(sptr_t)text.c_str()];
	_insertPos += (sptr_t)text.size();
	_insertLine += (sptr_t)marks.size();
	[self sci:SCI_SETREADONLY w:1 l:0];
	[self sci:SCI_COLOURISE w:0 l:_insertPos];
}

- (void)beginSearch:(NSString *)what
{
	_currentWhat = [what copy];
	_totalHits = 0;
	_insertPos = 0;
	_insertLine = 0;
	NSString *oneLine = [[what stringByReplacingOccurrencesOfString:@"\r" withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	std::string header = std::string("Search \"") + oneLine.UTF8String + "\"\n";
	[self insertText:header markings:{SearchResultMarkingLine()} lines:{ResultLine()}];
	[self sci:SCI_GOTOPOS w:0 l:0];
}

- (void)addFile:(NSString *)path hits:(const std::vector<MppSearchHit> &)hits
{
	if (hits.empty())
		return;
	[_paths addObject:path];
	const NSInteger pathIndex = (NSInteger)_paths.count - 1;
	size_t nHits = 0;
	sptr_t maxLine = 0;
	for (const auto &h : hits) {
		nHits += h.ranges.size();
		maxLine = std::max(maxLine, h.lineNumber + 1);
	}
	_totalHits += (NSInteger)nHits;
	int width = 1;
	for (sptr_t n = maxLine; n >= 10; n /= 10)
		++width;

	std::string text = std::string("  ") + path.UTF8String + " (" + std::to_string(nHits) + (nHits == 1 ? " hit)\n" : " hits)\n");
	std::vector<SearchResultMarkingLine> marks{SearchResultMarkingLine()};
	std::vector<ResultLine> lines{ResultLine()};
	for (const auto &h : hits) {
		char prefix[64];
		snprintf(prefix, sizeof prefix, "\tLine %*ld: ", width, (long)(h.lineNumber + 1));
		const sptr_t prefixLen = (sptr_t)strlen(prefix);
		std::string lineText = h.lineText;
		for (char &c : lineText)
			if (c == '\r' || c == '\n')
				c = ' ';
		text += prefix;
		text += lineText;
		text += "\n";
		SearchResultMarkingLine ml;
		for (auto &r : h.ranges) {
			const sptr_t s = std::min<sptr_t>(r.first, (sptr_t)lineText.size());
			const sptr_t e = std::min<sptr_t>(r.second, (sptr_t)lineText.size());
			ml._segmentPostions.emplace_back(prefixLen + s, prefixLen + e);
		}
		marks.push_back(ml);
		ResultLine rl;
		rl.pathIndex = pathIndex;
		rl.lineNumber = h.lineNumber;
		rl.matchStart = h.ranges.empty() ? 0 : h.ranges[0].first;
		rl.matchEnd = h.ranges.empty() ? 0 : h.ranges[0].second;
		lines.push_back(rl);
	}
	[self insertText:text markings:marks lines:lines];
}

- (void)finishSearchWithFileCount:(NSInteger)files searched:(NSInteger)searched inSelection:(BOOL)sel
{
	NSString *what = [[_currentWhat stringByReplacingOccurrencesOfString:@"\r" withString:@""] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	NSString *unit = sel ? @"selection" : @"file";
	NSString *info = [NSString stringWithFormat:@"Search \"%@\" (%ld %@ in %ld %@%@ of %ld searched)", what, (long)_totalHits,
	                  _totalHits == 1 ? @"hit" : @"hits", (long)files, unit, files == 1 ? @"" : @"s", (long)searched];
	std::string s = info.UTF8String;
	[self sci:SCI_SETREADONLY w:0 l:0];
	[self sci:SCI_SETTARGETRANGE w:0 l:[self sci:SCI_GETLINEENDPOSITION w:0 l:0]];
	[self sci:SCI_REPLACETARGET w:s.size() l:(sptr_t)s.c_str()];
	[self sci:SCI_SETREADONLY w:1 l:0];
	_insertPos = [self sci:SCI_POSITIONFROMLINE w:(uptr_t)_insertLine l:0];
	[self sci:SCI_COLOURISE w:0 l:-1];
	// Fold the older searches, keep the new one open
	const sptr_t n = [self sci:SCI_GETLINECOUNT w:0 l:0];
	for (sptr_t l = 0; l < n; ++l) {
		const sptr_t lev = [self sci:SCI_GETFOLDLEVEL w:(uptr_t)l l:0];
		if ((lev & SC_FOLDLEVELHEADERFLAG) && (lev & SC_FOLDLEVELNUMBERMASK) == SC_FOLDLEVELBASE)
			[self sci:SCI_FOLDLINE w:(uptr_t)l l:(l == 0 ? SC_FOLDACTION_EXPAND : SC_FOLDACTION_CONTRACT)];
	}
	[self sci:SCI_GOTOPOS w:0 l:0];
	[self sci:SCI_SETFIRSTVISIBLELINE w:0 l:0];
}

- (void)clearAll
{
	[self sci:SCI_SETREADONLY w:0 l:0];
	[self sci:SCI_CLEARALL w:0 l:0];
	[self sci:SCI_SETREADONLY w:1 l:0];
	_markings.clear();
	_lines.clear();
	[_paths removeAllObjects];
	_insertPos = _insertLine = 0;
	[self updateMarkingsProperty];
}

- (void)openLine:(sptr_t)line
{
	if (line < 0 || line >= (sptr_t)_lines.size())
		return;
	const ResultLine &rl = _lines[(size_t)line];
	if (rl.pathIndex < 0) {
		// header: toggle folding
		[self sci:SCI_TOGGLEFOLD w:(uptr_t)line l:0];
		return;
	}
	NSString *path = _paths[(NSUInteger)rl.pathIndex];
	MppMainWindowController *o = _owner;
	MppDocument *doc = nil;
	for (MppDocument *d in o.allDocuments)
		if ([d.filePath isEqualToString:path] || (!d.filePath && [d.displayName isEqualToString:path]))
			doc = d;
	if (doc)
		[o activateDocument:doc];
	else
		doc = [o openPath:path];
	if (!doc)
		return;
	const sptr_t lineStart = [o sci:SCI_POSITIONFROMLINE w:(uptr_t)rl.lineNumber];
	[o selectRangeFrom:lineStart + rl.matchStart to:lineStart + rl.matchEnd];
	[o.window makeFirstResponder:o.activeEditor.content];
	// keep the result line highlighted
	[self sci:SCI_GOTOLINE w:(uptr_t)line l:0];
}

- (void)gotoResult:(BOOL)forward
{
	if (_lines.empty())
		return;
	sptr_t cur = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS w:0 l:0] l:0];
	const sptr_t n = (sptr_t)_lines.size();
	for (sptr_t i = 1; i <= n; ++i) {
		const sptr_t l = forward ? (cur + i) % n : (cur - i + n) % n;
		if (_lines[(size_t)l].pathIndex >= 0) {
			[self sci:SCI_ENSUREVISIBLE w:(uptr_t)l l:0];
			[self sci:SCI_GOTOLINE w:(uptr_t)l l:0];
			[self openLine:l];
			return;
		}
	}
}

- (void)notification:(SCNotification *)n
{
	if (n->nmhdr.code == SCN_DOUBLECLICK) {
		[self openLine:n->line];
	} else if (n->nmhdr.code == SCN_MARGINCLICK) {
		const sptr_t line = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)n->position l:0];
		[self sci:SCI_TOGGLEFOLD w:(uptr_t)line l:0];
	}
}

- (NSMenu *)contextMenu
{
	NSMenu *m = [[NSMenu alloc] init];
	[m addItemWithTitle:@"Fold All" action:@selector(foldAll:) keyEquivalent:@""].target = self;
	[m addItemWithTitle:@"Unfold All" action:@selector(unfoldAll:) keyEquivalent:@""].target = self;
	[m addItem:NSMenuItem.separatorItem];
	[m addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
	[m addItemWithTitle:@"Copy Selected Pathnames" action:@selector(copyPaths:) keyEquivalent:@""].target = self;
	[m addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@""];
	[m addItemWithTitle:@"Clear All" action:@selector(clearAllAction:) keyEquivalent:@""].target = self;
	[m addItem:NSMenuItem.separatorItem];
	[m addItemWithTitle:@"Open All" action:@selector(openAll:) keyEquivalent:@""].target = self;
	[m addItem:NSMenuItem.separatorItem];
	[m addItemWithTitle:@"Close" action:@selector(closeClicked:) keyEquivalent:@""].target = self;
	return m;
}

- (void)foldAll:(id)s { [self sci:SCI_FOLDALL w:SC_FOLDACTION_CONTRACT l:0]; }
- (void)unfoldAll:(id)s { [self sci:SCI_FOLDALL w:SC_FOLDACTION_EXPAND l:0]; }
- (void)clearAllAction:(id)s { [self clearAll]; }

- (void)copyPaths:(id)sender
{
	const sptr_t l1 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETSELECTIONSTART w:0 l:0] l:0];
	const sptr_t l2 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETSELECTIONEND w:0 l:0] l:0];
	NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
	for (sptr_t l = l1; l <= l2 && l < (sptr_t)_lines.size(); ++l)
		if (_lines[(size_t)l].pathIndex >= 0)
			[set addObject:_paths[(NSUInteger)_lines[(size_t)l].pathIndex]];
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:[set.array componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

- (void)openAll:(id)sender
{
	NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
	for (const auto &l : _lines)
		if (l.pathIndex >= 0)
			[set addObject:_paths[(NSUInteger)l.pathIndex]];
	for (NSString *p in set)
		if ([NSFileManager.defaultManager fileExistsAtPath:p])
			[_owner openPath:p];
}

@end
