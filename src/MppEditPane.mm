// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppEditPane.h"
#import "MppStyler.h"
#import "MppPrefs.h"
#import "MppUserLang.h"
#include "Scintilla.h"

@implementation MppEditPane {
	NSMutableArray<MppDocument *> *_docs;
	MppDocument *_current;
	sptr_t _initialDoc;
	sptr_t _fitScrollWidth;   // the width last set by ensureScrollWidth (not grown by Scintilla's tracking)
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_docs = [NSMutableArray array];

		_tabBar = [[MppTabBar alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, 28)];
		_tabBar.delegate = self;
		_tabBar.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_tabBar];

		_editor = [[MppScintillaView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - 28)];
		_editor.delegate = self;
		_editor.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:_editor];

		[NSLayoutConstraint activateConstraints:@[
			[_tabBar.topAnchor constraintEqualToAnchor:self.topAnchor],
			[_tabBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_tabBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_tabBar.heightAnchor constraintEqualToConstant:28],
			[_editor.topAnchor constraintEqualToAnchor:_tabBar.bottomAnchor],
			[_editor.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[_editor.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[_editor.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];

		[MppStyler initializeView:_editor];
		_initialDoc = [_editor message:SCI_GETDOCPOINTER];
		[_editor message:SCI_ADDREFDOCUMENT wParam:0 lParam:_initialDoc];
	}
	return self;
}

- (sptr_t)sci:(unsigned int)msg
{
	return [_editor message:msg wParam:0 lParam:0];
}

- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w
{
	return [_editor message:msg wParam:w lParam:0];
}

- (sptr_t)sci:(unsigned int)msg w:(uptr_t)w l:(sptr_t)l
{
	return [_editor message:msg wParam:w lParam:l];
}

- (NSArray<MppDocument *> *)documents
{
	return _docs;
}

- (MppDocument *)currentDocument
{
	return _current;
}

- (void)setActive:(BOOL)active
{
	_active = active;
	_tabBar.focused = active;
}

- (NSInteger)indexOfDocument:(MppDocument *)doc
{
	NSUInteger i = [_docs indexOfObjectIdenticalTo:doc];
	return i == NSNotFound ? NSNotFound : (NSInteger)i;
}

- (void)refreshTabs
{
	_tabBar.documents = _docs;
	_tabBar.selectedIndex = _current ? [self indexOfDocument:_current] : -1;
}

- (void)addDocument:(MppDocument *)doc atIndex:(NSInteger)index activate:(BOOL)activate
{
	if ([self indexOfDocument:doc] == NSNotFound) {
		if (index < 0 || index > (NSInteger)_docs.count)
			index = (NSInteger)_docs.count;
		[_docs insertObject:doc atIndex:(NSUInteger)index];
	}
	if (activate || !_current)
		[self activateDocument:doc];
	else
		[self refreshTabs];
}

- (void)saveCurrentPosition
{
	if (!_current || !_current.sciDocument)
		return;
	MppViewPosition &pos = [_current positionForView:_editor];
	const sptr_t displayed = [self sci:SCI_GETFIRSTVISIBLELINE];
	pos.firstVisibleDocLine = [self sci:SCI_DOCLINEFROMVISIBLE w:(uptr_t)displayed];
	pos.anchor = [self sci:SCI_GETANCHOR];
	pos.caret = [self sci:SCI_GETCURRENTPOS];
	pos.xOffset = [self sci:SCI_GETXOFFSET];
	pos.selMode = (int)[self sci:SCI_GETSELECTIONMODE];
	pos.foldedLines.clear();
	for (sptr_t line = [self sci:SCI_CONTRACTEDFOLDNEXT w:0]; line >= 0;
	     line = [self sci:SCI_CONTRACTEDFOLDNEXT w:(uptr_t)(line + 1)])
		pos.foldedLines.push_back(line);
	pos.valid = true;
}

- (void)restorePosition
{
	MppViewPosition &pos = [_current positionForView:_editor];
	if (!pos.valid) {
		[self sci:SCI_GOTOPOS w:0];
		return;
	}
	if (!pos.foldedLines.empty()) {
		const sptr_t last = pos.foldedLines.back();
		[self sci:SCI_COLOURISE w:0 l:[self sci:SCI_GETLINEENDPOSITION w:(uptr_t)last + 1]];
		for (sptr_t line : pos.foldedLines)
			if ([self sci:SCI_GETFOLDLEVEL w:(uptr_t)line] & SC_FOLDLEVELHEADERFLAG)
				[self sci:SCI_FOLDLINE w:(uptr_t)line l:SC_FOLDACTION_CONTRACT];
	}
	[self sci:SCI_SETSELECTIONMODE w:(uptr_t)pos.selMode];
	[self sci:SCI_SETANCHOR w:(uptr_t)pos.anchor];
	[self sci:SCI_SETCURRENTPOS w:(uptr_t)pos.caret];
	[self sci:SCI_CANCEL];
	const sptr_t visible = [self sci:SCI_VISIBLEFROMDOCLINE w:(uptr_t)pos.firstVisibleDocLine];
	[self sci:SCI_SETFIRSTVISIBLELINE w:(uptr_t)visible];
	[self sci:SCI_SETXOFFSET w:(uptr_t)pos.xOffset];
}

- (void)applyDocumentSettings
{
	[MppStyler defineDocType:_current.lang inView:_editor];
	if (_current.lang == L_USER)
		[MppUserLangManager.shared applyLanguage:_current.userLangName toView:_editor documentID:_current.docID];
	[MppStyler applyViewPreferences:_editor lang:_current.lang];
	[self sci:SCI_SETREADONLY w:(_current.userReadOnly || _current.fileReadOnly || _current.monitoring)];
}

// On Cocoa the document view is exactly "scroll width" wide, so keep it at least as wide as the
// visible area (Scintilla's width tracking then grows it for longer lines). While no line has grown
// it, it follows the visible area in both directions, e.g. when the vertical scroll bar appears.
- (void)ensureScrollWidth:(BOOL)reset
{
	const CGFloat visible = _editor.scrollView.contentView.bounds.size.width;
	if (visible <= 0)
		return;
	const sptr_t wanted = (sptr_t)visible;
	const sptr_t current = [self sci:SCI_GETSCROLLWIDTH];
	if (reset || current < wanted || (current == _fitScrollWidth && current != wanted)) {
		[self sci:SCI_SETSCROLLWIDTH w:(uptr_t)wanted];
		_fitScrollWidth = wanted;
	}
}

- (void)layout
{
	[super layout];
	[self ensureScrollWidth:NO];
}

- (void)activateDocument:(MppDocument *)doc
{
	if (!doc)
		return;
	if (doc != _current) {
		[self saveCurrentPosition];
		_current = doc;
		[self sci:SCI_SETDOCPOINTER w:0 l:doc.sciDocument];
		[self applyDocumentSettings];
		[self ensureScrollWidth:YES];
		[self restorePosition];
	}
	[self refreshTabs];
	[_delegate editPane:self didActivateDocument:doc];
}

- (void)restyleCurrentDocument
{
	if (!_current)
		return;
	[self applyDocumentSettings];
	[self ensureScrollWidth:NO];
	[self sci:SCI_COLOURISE w:0 l:-1];
	[_editor setNeedsDisplay:YES];
}

- (void)removeDocument:(MppDocument *)doc
{
	NSInteger idx = [self indexOfDocument:doc];
	if (idx == NSNotFound)
		return;
	if (doc == _current) {
		[self saveCurrentPosition];
		MppDocument *next = nil;
		if (_docs.count > 1)
			next = (idx + 1 < (NSInteger)_docs.count) ? _docs[(NSUInteger)idx + 1] : _docs[(NSUInteger)idx - 1];
		[_docs removeObjectAtIndex:(NSUInteger)idx];
		_current = nil;
		if (next) {
			[self activateDocument:next];
		} else {
			[self sci:SCI_SETDOCPOINTER w:0 l:_initialDoc];
			[self refreshTabs];
		}
	} else {
		[_docs removeObjectAtIndex:(NSUInteger)idx];
		[self refreshTabs];
	}
}

- (void)moveDocumentFromIndex:(NSInteger)from toIndex:(NSInteger)to
{
	if (from < 0 || from >= (NSInteger)_docs.count || to < 0 || to >= (NSInteger)_docs.count || from == to)
		return;
	MppDocument *d = _docs[(NSUInteger)from];
	[_docs removeObjectAtIndex:(NSUInteger)from];
	[_docs insertObject:d atIndex:(NSUInteger)to];
	[self refreshTabs];
}

// ---- MppTabBarDelegate --------------------------------------------------------

- (void)tabBar:(MppTabBar *)bar didSelectIndex:(NSInteger)index
{
	if (index >= 0 && index < (NSInteger)_docs.count)
		[self activateDocument:_docs[(NSUInteger)index]];
	[self.window makeFirstResponder:_editor.content];
}

- (void)tabBar:(MppTabBar *)bar closeIndex:(NSInteger)index
{
	if (index >= 0 && index < (NSInteger)_docs.count)
		[_delegate editPane:self requestCloseDocument:_docs[(NSUInteger)index]];
}

- (void)tabBar:(MppTabBar *)bar moveIndex:(NSInteger)from toIndex:(NSInteger)to
{
	[self moveDocumentFromIndex:from toIndex:to];
}

- (void)tabBar:(MppTabBar *)bar dropIndex:(NSInteger)index ontoBar:(MppTabBar *)target atIndex:(NSInteger)targetIndex
{
	NSView *v = target.superview;
	if ([v isKindOfClass:[MppEditPane class]] && index >= 0 && index < (NSInteger)_docs.count)
		[_delegate editPane:self moveDocument:_docs[(NSUInteger)index] toPane:(MppEditPane *)v atIndex:targetIndex];
}

- (NSMenu *)tabBar:(MppTabBar *)bar menuForIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_docs.count)
		return nil;
	return [_delegate editPane:self tabMenuForDocument:_docs[(NSUInteger)index]];
}

- (void)tabBarDoubleClickedEmptyArea:(MppTabBar *)bar
{
	[_delegate editPaneRequestsNewDocument:self];
}

// ---- Scintilla notifications ----------------------------------------------------

- (void)notification:(SCNotification *)n
{
	switch (n->nmhdr.code) {
		case SCN_SAVEPOINTLEFT:
			_current.dirty = YES;
			_current.backupDirty = YES;
			break;
		case SCN_SAVEPOINTREACHED:
			_current.dirty = NO;
			break;
		case SCN_MODIFIED:
			if (n->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) {
				_current.backupDirty = YES;
				if (n->linesAdded) {
					[MppStyler updateLineNumberWidth:_editor];
					[self ensureScrollWidth:NO];
				}
			}
			break;
		case SCN_ZOOM: {
			dispatch_async(dispatch_get_main_queue(), ^{ [self ensureScrollWidth:YES]; });
			break;
		}
		default:
			break;
	}
	[_delegate editPane:self notification:n];
}

@end
