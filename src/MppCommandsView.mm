// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMainWindowController.h"
#import "MppPaths.h"
#import "MppPrefs.h"
#import "MppStyler.h"
#import "MppEditing.h"
#import "MppAutoCompletion.h"
#import "MppPanels.h"
#import "MppMacro.h"
#import "MppSearchResults.h"
#include "Scintilla.h"

@implementation MppMainWindowController (View)

- (void)applyPrefsToEditors
{
	[[MppPrefs shared] notifyChanged];
}

- (void)foldLevel:(int)level expand:(BOOL)expand
{
	const sptr_t lines = [self sci:SCI_GETLINECOUNT];
	[self sci:SCI_COLOURISE w:0 l:-1];
	for (sptr_t l = 0; l < lines; ++l) {
		const sptr_t fl = [self sci:SCI_GETFOLDLEVEL w:(uptr_t)l];
		if (!(fl & SC_FOLDLEVELHEADERFLAG))
			continue;
		const int lev = (int)((fl & SC_FOLDLEVELNUMBERMASK) - SC_FOLDLEVELBASE);
		if (lev == level - 1)
			[self sci:SCI_FOLDLINE w:(uptr_t)l l:expand ? SC_FOLDACTION_EXPAND : SC_FOLDACTION_CONTRACT];
	}
}

- (void)foldCurrent:(BOOL)expand
{
	sptr_t line = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETCURRENTPOS]];
	if (!([self sci:SCI_GETFOLDLEVEL w:(uptr_t)line] & SC_FOLDLEVELHEADERFLAG))
		line = [self sci:SCI_GETFOLDPARENT w:(uptr_t)line];
	if (line < 0)
		return;
	[self sci:SCI_FOLDLINE w:(uptr_t)line l:expand ? SC_FOLDACTION_EXPAND : SC_FOLDACTION_CONTRACT];
	if (!expand)
		[self sci:SCI_GOTOLINE w:(uptr_t)line];
}

- (void)moveOrCloneToOtherView:(BOOL)clone
{
	MppDocument *doc = self.currentDocument;
	if (!doc)
		return;
	MppEditPane *src = self.activePane, *dst = self.otherPane;
	if ([dst indexOfDocument:doc] != NSNotFound) {
		[dst activateDocument:doc];
	} else {
		[dst addDocument:doc atIndex:-1 activate:YES];
		if (!clone)
			[src removeDocument:doc];
	}
	if (!clone && [dst indexOfDocument:doc] != NSNotFound && [src indexOfDocument:doc] != NSNotFound && src.documents.count > 0)
		[src removeDocument:doc];
	[self updatePaneVisibility];
	[self editPane:dst didActivateDocument:doc];
	[self.window makeFirstResponder:dst.editor.content];
}

- (void)switchTab:(int)cmd
{
	MppEditPane *pane = self.activePane;
	NSArray *docs = pane.documents;
	if (!docs.count)
		return;
	NSInteger cur = [pane indexOfDocument:self.currentDocument];
	NSInteger target = cur;
	switch (cmd) {
		case CMD_VIEW_TAB_START: target = 0; break;
		case CMD_VIEW_TAB_END: target = (NSInteger)docs.count - 1; break;
		case CMD_VIEW_TAB_NEXT: target = (cur + 1) % (NSInteger)docs.count; break;
		case CMD_VIEW_TAB_PREV: target = (cur - 1 + (NSInteger)docs.count) % (NSInteger)docs.count; break;
		default: target = cmd - CMD_VIEW_TAB1; break;
	}
	if (target >= 0 && target < (NSInteger)docs.count) {
		[pane activateDocument:docs[(NSUInteger)target]];
		[self.window makeFirstResponder:pane.editor.content];
	}
}

- (void)showSummary
{
	MppDocument *doc = self.currentDocument;
	NSMutableString *s = [NSMutableString string];
	if (doc.filePath) {
		NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:doc.filePath error:nil];
		NSDateFormatter *f = [[NSDateFormatter alloc] init];
		f.dateStyle = NSDateFormatterMediumStyle;
		f.timeStyle = NSDateFormatterMediumStyle;
		[s appendFormat:@"Full file path: %@\n", doc.filePath];
		if (a) {
			[s appendFormat:@"Created: %@\n", [f stringFromDate:a[NSFileCreationDate]]];
			[s appendFormat:@"Modified: %@\n", [f stringFromDate:a[NSFileModificationDate]]];
		}
		[s appendString:@"\n"];
	}
	const sptr_t len = [self sci:SCI_GETLENGTH];
	const sptr_t chars = [self sci:SCI_COUNTCHARACTERS w:0 l:len];
	std::string text = [self textRangeFrom:0 to:len];
	size_t words = 0;
	bool inWord = false;
	for (unsigned char c : text) {
		const bool ws = c == ' ' || c == '\t' || c == '\r' || c == '\n';
		if (!ws && !inWord)
			++words;
		inWord = !ws;
	}
	sptr_t nonEmptyLines = 0;
	const sptr_t lines = [self sci:SCI_GETLINECOUNT];
	for (sptr_t l = 0; l < lines; ++l)
		if ([self sci:SCI_GETLINEINDENTPOSITION w:(uptr_t)l] < [self sci:SCI_GETLINEENDPOSITION w:(uptr_t)l])
			++nonEmptyLines;
	[s appendFormat:@"Characters (without line endings): %ld\n", (long)(chars - (lines - 1) * (doc.eolMode == SC_EOL_CRLF ? 2 : 1))];
	[s appendFormat:@"Words: %zu\n", words];
	[s appendFormat:@"Lines: %ld\n", (long)lines];
	[s appendFormat:@"Non-empty lines: %ld\n", (long)nonEmptyLines];
	[s appendFormat:@"Document length: %ld\n", (long)len];
	if (![self sci:SCI_GETSELECTIONEMPTY]) {
		const sptr_t ss = [self sci:SCI_GETSELECTIONSTART], se = [self sci:SCI_GETSELECTIONEND];
		[s appendFormat:@"\nSelected characters: %ld (%ld bytes) in %ld ranges\n",
		                (long)[self sci:SCI_COUNTCHARACTERS w:(uptr_t)ss l:se], (long)(se - ss), (long)[self sci:SCI_GETSELECTIONS]];
	}
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Summary";
	a.informativeText = s;
	[a runModal];
}

- (void)applyDistractionFree:(BOOL)on
{
	MppPrefs *p = [MppPrefs shared];
	static BOOL savedToolbar, savedStatus;
	if (on) {
		savedToolbar = p.showToolbar;
		savedStatus = p.showStatusBar;
		p.showToolbar = NO;
		p.showStatusBar = NO;
		if (!(self.window.styleMask & NSWindowStyleMaskFullScreen))
			[self.window toggleFullScreen:nil];
		const sptr_t width = self.activeEditor.bounds.size.width;
		const sptr_t margin = std::max<sptr_t>(0, (width - 900) / 2);
		[self sci:SCI_SETMARGINLEFT w:0 l:margin];
		[self sci:SCI_SETMARGINRIGHT w:0 l:margin];
	} else {
		p.showToolbar = savedToolbar;
		p.showStatusBar = savedStatus;
		if (self.window.styleMask & NSWindowStyleMaskFullScreen)
			[self.window toggleFullScreen:nil];
		[self sci:SCI_SETMARGINLEFT w:0 l:1];
		[self sci:SCI_SETMARGINRIGHT w:0 l:1];
	}
	[p notifyChanged];
}

- (BOOL)handleViewCommand:(int)cmd
{
	MppPrefs *p = [MppPrefs shared];
	MppDocument *doc = self.currentDocument;

	if (cmd >= CMD_VIEW_TAB1 && cmd <= CMD_VIEW_TAB_PREV) {
		[self switchTab:cmd];
		return YES;
	}
	if (cmd >= CMD_VIEW_FOLD_1 && cmd <= CMD_VIEW_FOLD_8) {
		[self foldLevel:cmd - CMD_VIEW_FOLD_1 + 1 expand:NO];
		return YES;
	}
	if (cmd >= CMD_VIEW_UNFOLD_1 && cmd <= CMD_VIEW_UNFOLD_8) {
		[self foldLevel:cmd - CMD_VIEW_UNFOLD_1 + 1 expand:YES];
		return YES;
	}
	if (cmd >= CMD_VIEW_TAB_COLOUR_1 && cmd <= CMD_VIEW_TAB_COLOUR_NONE) {
		doc.tabColor = (cmd == CMD_VIEW_TAB_COLOUR_NONE) ? -1 : cmd - CMD_VIEW_TAB_COLOUR_1;
		[doc notifyChanged];
		return YES;
	}

	switch (cmd) {
		case CMD_VIEW_ALWAYSONTOP: p.alwaysOnTop = !p.alwaysOnTop; [p notifyChanged]; return YES;
		case CMD_VIEW_FULLSCREENTOGGLE: [self.window toggleFullScreen:nil]; return YES;
		case CMD_VIEW_POSTIT: {
			// Post-it: a small floating window without toolbar and status bar
			static BOOL postIt = NO, savedToolbar = YES, savedStatus = YES;
			postIt = !postIt;
			if (postIt) {
				savedToolbar = p.showToolbar;
				savedStatus = p.showStatusBar;
				p.showToolbar = NO;
				p.showStatusBar = NO;
			} else {
				p.showToolbar = savedToolbar;
				p.showStatusBar = savedStatus;
			}
			[p notifyChanged];
			self.window.level = (postIt || p.alwaysOnTop) ? NSFloatingWindowLevel : NSNormalWindowLevel;
			return YES;
		}
		case CMD_VIEW_DISTRACTIONFREE:
			self.distractionFree = !self.distractionFree;
			[self applyDistractionFree:self.distractionFree];
			return YES;
		case CMD_VIEW_IN_SAFARI: case CMD_VIEW_IN_CHROME: case CMD_VIEW_IN_FIREFOX: case CMD_VIEW_IN_EDGE: {
			if (!doc.filePath)
				return YES;
			NSString *bid = cmd == CMD_VIEW_IN_SAFARI ? @"com.apple.Safari" : cmd == CMD_VIEW_IN_CHROME ? @"com.google.Chrome"
			              : cmd == CMD_VIEW_IN_FIREFOX ? @"org.mozilla.firefox" : @"com.microsoft.edgemac";
			NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:bid];
			if (!app) {
				NSAlert *a = [[NSAlert alloc] init];
				a.messageText = @"This browser is not installed.";
				[a runModal];
				return YES;
			}
			[NSWorkspace.sharedWorkspace openURLs:@[[NSURL fileURLWithPath:doc.filePath]] withApplicationAtURL:app
			                        configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
			return YES;
		}
		case CMD_VIEW_TAB_SPACE: p.showWhitespace = !p.showWhitespace; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_EOL: p.showEOL = !p.showEOL; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_NPC: p.showNonPrinting = !p.showNonPrinting; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_ALL_CHARACTERS: {
			const BOOL on = !(p.showWhitespace && p.showEOL);
			p.showWhitespace = on;
			p.showEOL = on;
			[self applyPrefsToEditors];
			return YES;
		}
		case CMD_VIEW_INDENT_GUIDE: p.showIndentGuides = !p.showIndentGuides; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_WRAP_SYMBOL: p.showWrapSymbol = !p.showWrapSymbol; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_WRAP: p.wordWrap = !p.wordWrap; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_TOOLBAR: p.showToolbar = !p.showToolbar; [p notifyChanged]; return YES;
		case CMD_VIEW_STATUSBAR: p.showStatusBar = !p.showStatusBar; [p notifyChanged]; return YES;
		case CMD_VIEW_LINENUMBER: p.showLineNumbers = !p.showLineNumbers; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_BOOKMARK_MARGIN: p.showBookmarkMargin = !p.showBookmarkMargin; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_CHANGE_HISTORY_MARGIN: p.showChangeHistory = !p.showChangeHistory; [self applyPrefsToEditors]; return YES;
		case CMD_VIEW_ZOOMIN:
		case CMD_VIEW_ZOOMOUT:
		case CMD_VIEW_ZOOMRESTORE: {
			const unsigned int msg = cmd == CMD_VIEW_ZOOMIN ? SCI_ZOOMIN : (cmd == CMD_VIEW_ZOOMOUT ? SCI_ZOOMOUT : SCI_SETZOOM);
			[self.activePane sci:msg w:0];
			if ([MppDefaults() boolForKey:@"zoomSync"])
				[self.otherPane sci:SCI_SETZOOM w:(uptr_t)[self.activePane sci:SCI_GETZOOM]];
			return YES;
		}
		case CMD_VIEW_ZOOM_SYNC: {
			const BOOL on = ![MppDefaults() boolForKey:@"zoomSync"];
			[MppDefaults() setBool:on forKey:@"zoomSync"];
			if (on)
				[self.otherPane sci:SCI_SETZOOM w:(uptr_t)[self.activePane sci:SCI_GETZOOM]];
			return YES;
		}
		case CMD_VIEW_GOTO_ANOTHER_VIEW: [self moveOrCloneToOtherView:NO]; return YES;
		case CMD_VIEW_CLONE_TO_ANOTHER_VIEW: [self moveOrCloneToOtherView:YES]; return YES;
		case CMD_VIEW_GOTO_START:
		case CMD_VIEW_GOTO_END:
		case CMD_VIEW_TAB_MOVEFORWARD:
		case CMD_VIEW_TAB_MOVEBACKWARD: {
			MppEditPane *pane = self.activePane;
			const NSInteger cur = [pane indexOfDocument:doc];
			const NSInteger n = (NSInteger)pane.documents.count;
			NSInteger to = cmd == CMD_VIEW_GOTO_START ? 0 : cmd == CMD_VIEW_GOTO_END ? n - 1
			             : cmd == CMD_VIEW_TAB_MOVEFORWARD ? std::min(cur + 1, n - 1) : std::max<NSInteger>(cur - 1, 0);
			[pane moveDocumentFromIndex:cur toIndex:to];
			return YES;
		}
		case CMD_VIEW_SWITCHTO_OTHER_VIEW: {
			MppEditPane *o = self.otherPane;
			if (o.documents.count) {
				[self.window makeFirstResponder:o.editor.content];
				[self editPane:o didActivateDocument:o.currentDocument];
			}
			return YES;
		}
		case CMD_VIEW_HIDELINES: {
			const sptr_t l1 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETSELECTIONSTART]];
			const sptr_t l2 = [self sci:SCI_LINEFROMPOSITION w:(uptr_t)[self sci:SCI_GETSELECTIONEND]];
			if (l1 == 0 && l2 == [self sci:SCI_GETLINECOUNT] - 1)
				return YES;
			const sptr_t first = l1;
			[self sci:SCI_HIDELINES w:(uptr_t)first l:l2];
			if (first > 0)
				[self sci:SCI_MARKERADD w:(uptr_t)(first - 1) l:MPP_MARK_HIDELINESBEGIN];
			if (l2 + 1 < [self sci:SCI_GETLINECOUNT])
				[self sci:SCI_MARKERADD w:(uptr_t)(l2 + 1) l:MPP_MARK_HIDELINESEND];
			return YES;
		}
		case CMD_VIEW_FOLDALL:
			[self sci:SCI_COLOURISE w:0 l:-1];
			[self sci:SCI_FOLDALL w:SC_FOLDACTION_CONTRACT | SC_FOLDACTION_CONTRACT_EVERY_LEVEL];
			return YES;
		case CMD_VIEW_UNFOLDALL:
			[self sci:SCI_FOLDALL w:SC_FOLDACTION_EXPAND | SC_FOLDACTION_CONTRACT_EVERY_LEVEL];
			// also unhide hidden lines
			[self sci:SCI_SHOWLINES w:0 l:[self sci:SCI_GETLINECOUNT] - 1];
			[self sci:SCI_MARKERDELETEALL w:MPP_MARK_HIDELINESBEGIN];
			[self sci:SCI_MARKERDELETEALL w:MPP_MARK_HIDELINESEND];
			return YES;
		case CMD_VIEW_FOLD_CURRENT: [self foldCurrent:NO]; return YES;
		case CMD_VIEW_UNFOLD_CURRENT: [self foldCurrent:YES]; return YES;
		case CMD_VIEW_SUMMARY: [self showSummary]; return YES;
		case CMD_VIEW_FILEBROWSER: [self toggleFolderAsWorkspace]; return YES;
		case CMD_VIEW_DOC_MAP: [self toggleDocumentMap]; return YES;
		case CMD_VIEW_DOCLIST: [self toggleDocumentList]; return YES;
		case CMD_VIEW_FUNC_LIST: [self toggleFunctionList]; return YES;
		case CMD_VIEW_SYNSCROLLV: self.syncVerticalScroll = !self.syncVerticalScroll; return YES;
		case CMD_VIEW_SYNSCROLLH: self.syncHorizontalScroll = !self.syncHorizontalScroll; return YES;
		case CMD_VIEW_MONITORING:
			if (!doc.filePath)
				return YES;
			if (!doc.monitoring && doc.dirty) {
				NSAlert *a = [[NSAlert alloc] init];
				a.messageText = @"The document is modified. Save it before monitoring?";
				[a addButtonWithTitle:@"Save"];
				[a addButtonWithTitle:@"Cancel"];
				if ([a runModal] != NSAlertFirstButtonReturn || ![self saveDocument:doc])
					return YES;
			}
			doc.monitoring = !doc.monitoring;
			[self documentDisplayChanged:doc];
			[doc notifyChanged];
			if (doc.monitoring)
				[self sci:SCI_DOCUMENTEND];
			return YES;
		default:
			return NO;
	}
}

// ---- Notifications from the editors -------------------------------------------------

- (void)handleUpdateUI:(SCNotification *)n pane:(MppEditPane *)pane
{
	MppScintillaView *v = pane.editor;
	MppDocument *doc = pane.currentDocument;
	if (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)) {
		MppBraceMatch(v);
		MppXmlTagMatch(v, doc.lang);
	}
	if (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL | SC_UPDATE_CONTENT))
		MppSmartHighlight(v, NO);
	if (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_CONTENT | SC_UPDATE_SELECTION))
		MppHighlightURLs(v);
	if (pane == self.activePane) {
		if (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT))
			[self updateStatusBar];
		MppDocumentMapPanel *map = self.documentMapPanel;
		if (map && (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL | SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)))
			[map syncWithEditor];
	}
	// Synchronized scrolling between the two views
	if (pane == self.activePane && (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL)) &&
	    (self.syncVerticalScroll || self.syncHorizontalScroll) && !self.otherPane.hidden) {
		static sptr_t lastFirst = -1, lastX = -1;
		static __weak MppEditPane *lastPane = nil;
		const sptr_t first = [pane sci:SCI_GETFIRSTVISIBLELINE];
		const sptr_t x = [pane sci:SCI_GETXOFFSET];
		if (lastPane == pane && lastFirst >= 0) {
			MppEditPane *o = self.otherPane;
			if (self.syncVerticalScroll && first != lastFirst)
				[o sci:SCI_LINESCROLL w:0 l:first - lastFirst];
			if (self.syncHorizontalScroll && x != lastX)
				[o sci:SCI_SETXOFFSET w:(uptr_t)std::max<sptr_t>(0, [o sci:SCI_GETXOFFSET] + (x - lastX))];
		}
		lastPane = pane;
		lastFirst = first;
		lastX = x;
	}
}

- (void)handleCharAdded:(SCNotification *)n pane:(MppEditPane *)pane
{
	MppScintillaView *v = pane.editor;
	MppDocument *doc = pane.currentDocument;
	const int ch = n->ch;
	MppMaintainIndentation(v, ch, doc.lang);
	MppAutoCloseChar(v, ch, doc.lang);
	if (!self.macros.recording)
		[MppAutoCompletion charAdded:ch view:v lang:doc.lang];
}

@end
