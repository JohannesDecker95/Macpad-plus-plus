// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMenu.h"
#import "MppCommands.h"
#import "MppLanguages.h"
#import "MppEncoding.h"

NSString *const MppMenuRecent = @"recent";
NSString *const MppMenuMacros = @"macros";
NSString *const MppMenuRun = @"run";
NSString *const MppMenuUserLangs = @"userLangs";

static const NSEventModifierFlags CMD = NSEventModifierFlagCommand;
static const NSEventModifierFlags SHIFT = NSEventModifierFlagShift;
static const NSEventModifierFlags OPT = NSEventModifierFlagOption;
static const NSEventModifierFlags CTRL = NSEventModifierFlagControl;

static NSString *fkey(unichar k)
{
	return [NSString stringWithCharacters:&k length:1];
}

@implementation MppMenu

+ (NSMenuItem *)itemWithTitle:(NSString *)title command:(int)cmd key:(NSString *)key modifiers:(NSEventModifierFlags)mods
{
	NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:@selector(mppCommand:) keyEquivalent:key ?: @""];
	it.tag = cmd;
	if (key.length)
		it.keyEquivalentModifierMask = mods;
	return it;
}

static NSMenuItem *I(NSMenu *m, NSString *title, int cmd, NSString *key = @"", NSEventModifierFlags mods = CMD)
{
	NSMenuItem *it = [MppMenu itemWithTitle:title command:cmd key:key modifiers:mods];
	[m addItem:it];
	return it;
}

static NSMenuItem *STD(NSMenu *m, NSString *title, SEL action, NSString *key, NSEventModifierFlags mods)
{
	NSMenuItem *it = [m addItemWithTitle:title action:action keyEquivalent:key];
	if (key.length)
		it.keyEquivalentModifierMask = mods;
	return it;
}

static void SEP(NSMenu *m)
{
	[m addItem:[NSMenuItem separatorItem]];
}

static NSMenu *SUB(NSMenu *parent, NSString *title)
{
	NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
	NSMenu *m = [[NSMenu alloc] initWithTitle:title];
	it.submenu = m;
	[parent addItem:it];
	return m;
}

static NSMenu *TOP(NSMenu *bar, NSString *title)
{
	return SUB(bar, title);
}

+ (NSMenu *)languageMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Language"];
	I(m, @"None (Normal Text)", CMD_LANG_BASE + L_TEXT);
	SEP(m);
	NSString *currentLetter = nil;
	NSMenu *sub = nil;
	for (MppLangType t : [MppLanguages.shared menuLanguages]) {
		NSString *name = [MppLanguages menuNameForLang:t];
		NSString *letter = [name substringToIndex:1].uppercaseString;
		if (![letter isEqualToString:currentLetter]) {
			currentLetter = letter;
			sub = SUB(m, letter);
		}
		I(sub, name, CMD_LANG_BASE + t);
	}
	SEP(m);
	NSMenu *udl = SUB(m, @"User Defined Language");
	udl.identifier = MppMenuUserLangs;
	I(udl, @"Define your language…", CMD_LANG_DEFINE_UDL);
	I(udl, @"Import User Defined Language…", CMD_LANG_IMPORT_UDL);
	I(udl, @"Open User Defined Language Folder…", CMD_LANG_OPENUDLDIR);
	return m;
}

+ (NSMenu *)encodingMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Encoding"];
	I(m, @"ANSI", CMD_FORMAT_ANSI);
	I(m, @"UTF-8", CMD_FORMAT_AS_UTF_8);
	I(m, @"UTF-8-BOM", CMD_FORMAT_UTF_8);
	I(m, @"UTF-16 BE BOM", CMD_FORMAT_UTF_16BE);
	I(m, @"UTF-16 LE BOM", CMD_FORMAT_UTF_16LE);
	NSMenu *cs = SUB(m, @"Character Sets");
	NSString *group = nil;
	NSMenu *g = nil;
	const auto &charsets = MppCharsets();
	for (size_t i = 0; i < charsets.size(); ++i) {
		NSString *gn = @(charsets[i].group);
		if (![gn isEqualToString:group]) {
			group = gn;
			g = SUB(cs, gn);
		}
		I(g, @(charsets[i].name), CMD_FORMAT_CHARSET_BASE + (int)i);
	}
	SEP(m);
	I(m, @"Convert to ANSI", CMD_FORMAT_CONV2_ANSI);
	I(m, @"Convert to UTF-8", CMD_FORMAT_CONV2_AS_UTF_8);
	I(m, @"Convert to UTF-8-BOM", CMD_FORMAT_CONV2_UTF_8);
	I(m, @"Convert to UTF-16 BE BOM", CMD_FORMAT_CONV2_UTF_16BE);
	I(m, @"Convert to UTF-16 LE BOM", CMD_FORMAT_CONV2_UTF_16LE);
	return m;
}

+ (NSMenu *)eolMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"EOL Conversion"];
	I(m, @"Windows (CR LF)", CMD_FORMAT_TODOS);
	I(m, @"Unix (LF)", CMD_FORMAT_TOUNIX);
	I(m, @"Macintosh (CR)", CMD_FORMAT_TOMAC);
	return m;
}

+ (NSMenu *)buildMainMenuWithDelegate:(id<NSMenuDelegate>)delegate
{
	NSMenu *bar = [[NSMenu alloc] initWithTitle:@"Main"];

	// ---- Application menu --------------------------------------------------
	NSMenu *app = TOP(bar, @"Macpad++");
	I(app, @"About Macpad++", CMD_HELP_ABOUT, @"");
	SEP(app);
	I(app, @"Preferences…", CMD_SETTING_PREFERENCE, @",");
	SEP(app);
	NSMenuItem *services = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
	services.submenu = [[NSMenu alloc] initWithTitle:@"Services"];
	NSApp.servicesMenu = services.submenu;
	[app addItem:services];
	SEP(app);
	[app addItemWithTitle:@"Hide Macpad++" action:@selector(hide:) keyEquivalent:@"h"];
	NSMenuItem *hideOthers = [app addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	hideOthers.keyEquivalentModifierMask = CMD | OPT;
	[app addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
	SEP(app);
	[app addItemWithTitle:@"Quit Macpad++" action:@selector(terminate:) keyEquivalent:@"q"];

	// ---- File --------------------------------------------------------------
	NSMenu *file = TOP(bar, @"File");
	I(file, @"New", CMD_FILE_NEW, @"n");
	I(file, @"Open…", CMD_FILE_OPEN, @"o");
	NSMenu *containing = SUB(file, @"Open Containing Folder");
	I(containing, @"Finder", CMD_FILE_REVEAL_IN_FINDER);
	I(containing, @"Terminal", CMD_FILE_OPEN_TERMINAL);
	I(containing, @"Folder as Workspace", CMD_FILE_CONTAININGFOLDER_AS_WORKSPACE);
	I(file, @"Open in Default Viewer", CMD_FILE_OPEN_DEFAULT_VIEWER);
	I(file, @"Open Folder as Workspace…", CMD_FILE_OPEN_FOLDER_AS_WORKSPACE);
	I(file, @"Reload from Disk", CMD_FILE_RELOAD);
	I(file, @"Save", CMD_FILE_SAVE, @"s");
	I(file, @"Save As…", CMD_FILE_SAVEAS, @"s", CMD | SHIFT);
	I(file, @"Save a Copy As…", CMD_FILE_SAVECOPYAS);
	I(file, @"Save All", CMD_FILE_SAVEALL, @"s", CMD | OPT);
	I(file, @"Rename…", CMD_FILE_RENAME);
	I(file, @"Close", CMD_FILE_CLOSE, @"w");
	I(file, @"Close All", CMD_FILE_CLOSEALL, @"w", CMD | SHIFT);
	NSMenu *closeMulti = SUB(file, @"Close Multiple Documents");
	I(closeMulti, @"Close All but Active Document", CMD_FILE_CLOSEALL_BUT_CURRENT);
	I(closeMulti, @"Close All to the Left", CMD_FILE_CLOSEALL_TOLEFT);
	I(closeMulti, @"Close All to the Right", CMD_FILE_CLOSEALL_TORIGHT);
	I(closeMulti, @"Close All Unchanged", CMD_FILE_CLOSEALL_UNCHANGED);
	I(file, @"Move to Trash", CMD_FILE_DELETE);
	SEP(file);
	I(file, @"Load Session…", CMD_FILE_LOADSESSION);
	I(file, @"Save Session…", CMD_FILE_SAVESESSION);
	SEP(file);
	I(file, @"Print…", CMD_FILE_PRINT, @"p");
	SEP(file);
	I(file, @"Restore Recent Closed File", CMD_FILE_RESTORE_LAST_CLOSED, @"t", CMD | SHIFT);
	NSMenu *recent = SUB(file, @"Recent Files");
	recent.identifier = MppMenuRecent;
	recent.delegate = delegate;

	// ---- Edit --------------------------------------------------------------
	NSMenu *edit = TOP(bar, @"Edit");
	// Standard selectors so that these also work in text fields of panels and dialogs
	STD(edit, @"Undo", @selector(undo:), @"z", CMD);
	STD(edit, @"Redo", @selector(redo:), @"z", CMD | SHIFT);
	SEP(edit);
	STD(edit, @"Cut", @selector(cut:), @"x", CMD);
	STD(edit, @"Copy", @selector(copy:), @"c", CMD);
	STD(edit, @"Paste", @selector(paste:), @"v", CMD);
	STD(edit, @"Delete", @selector(delete:), @"", 0);
	STD(edit, @"Select All", @selector(selectAll:), @"a", CMD);
	I(edit, @"Begin/End Select", CMD_EDIT_BEGINENDSELECT);
	I(edit, @"Begin/End Select in Column Mode", CMD_EDIT_BEGINENDSELECT_COLUMN);
	SEP(edit);
	NSMenu *ins = SUB(edit, @"Insert");
	I(ins, @"Date Time (short)", CMD_EDIT_INSERT_DATETIME_SHORT);
	I(ins, @"Date Time (long)", CMD_EDIT_INSERT_DATETIME_LONG);
	I(ins, @"Date Time (customized)", CMD_EDIT_INSERT_DATETIME_CUSTOM);
	NSMenu *clip = SUB(edit, @"Copy to Clipboard");
	I(clip, @"Copy Current Full File Path", CMD_EDIT_FULLPATHTOCLIP);
	I(clip, @"Copy Current Filename", CMD_EDIT_FILENAMETOCLIP);
	I(clip, @"Copy Current Dir. Path", CMD_EDIT_CURRENTDIRTOCLIP);
	SEP(clip);
	I(clip, @"Copy All Filenames", CMD_EDIT_COPY_ALL_NAMES);
	I(clip, @"Copy All File Paths", CMD_EDIT_COPY_ALL_PATHS);
	NSMenu *indent = SUB(edit, @"Indent");
	I(indent, @"Increase Line Indent", CMD_EDIT_INS_TAB, @"]");
	I(indent, @"Decrease Line Indent", CMD_EDIT_RMV_TAB, @"[");
	NSMenu *cvcase = SUB(edit, @"Convert Case to");
	I(cvcase, @"UPPERCASE", CMD_EDIT_UPPERCASE, @"u", CMD | SHIFT);
	I(cvcase, @"lowercase", CMD_EDIT_LOWERCASE, @"u");
	I(cvcase, @"Proper Case", CMD_EDIT_PROPERCASE_FORCE, @"u", CMD | OPT);
	I(cvcase, @"Proper Case (blend)", CMD_EDIT_PROPERCASE_BLEND);
	I(cvcase, @"Sentence case", CMD_EDIT_SENTENCECASE_FORCE, @"u", CMD | OPT | CTRL);
	I(cvcase, @"Sentence case (blend)", CMD_EDIT_SENTENCECASE_BLEND);
	I(cvcase, @"iNVERT cASE", CMD_EDIT_INVERTCASE, @"u", CMD | CTRL);
	I(cvcase, @"ranDOm CasE", CMD_EDIT_RANDOMCASE);
	NSMenu *lines = SUB(edit, @"Line Operations");
	I(lines, @"Duplicate Current Line", CMD_EDIT_DUP_LINE, @"d");
	I(lines, @"Delete Current Line", CMD_EDIT_DELETE_LINE, @"k", CMD | SHIFT);
	I(lines, @"Remove Duplicate Lines", CMD_EDIT_REMOVE_ANY_DUP_LINES);
	I(lines, @"Remove Consecutive Duplicate Lines", CMD_EDIT_REMOVE_CONSECUTIVE_DUP_LINES);
	I(lines, @"Split Lines", CMD_EDIT_SPLIT_LINES, @"i");
	I(lines, @"Join Lines", CMD_EDIT_JOIN_LINES, @"j");
	I(lines, @"Move Up Current Line", CMD_EDIT_LINE_UP, fkey(NSUpArrowFunctionKey), CTRL | SHIFT);
	I(lines, @"Move Down Current Line", CMD_EDIT_LINE_DOWN, fkey(NSDownArrowFunctionKey), CTRL | SHIFT);
	I(lines, @"Remove Empty Lines", CMD_EDIT_REMOVEEMPTYLINES);
	I(lines, @"Remove Empty Lines (Containing Blank characters)", CMD_EDIT_REMOVEEMPTYLINESWITHBLANK);
	I(lines, @"Insert Blank Line Above Current", CMD_EDIT_BLANKLINEABOVECURRENT, @"\r", CMD | OPT);
	I(lines, @"Insert Blank Line Below Current", CMD_EDIT_BLANKLINEBELOWCURRENT, @"\r", CMD | OPT | SHIFT);
	SEP(lines);
	I(lines, @"Reverse Line Order", CMD_EDIT_SORT_REVERSE);
	I(lines, @"Randomize Line Order", CMD_EDIT_SORT_RANDOM);
	SEP(lines);
	I(lines, @"Sort Lines Lexicographically Ascending", CMD_EDIT_SORT_LEX_ASC);
	I(lines, @"Sort Lines Lex. Ascending Ignoring Case", CMD_EDIT_SORT_LEX_CI_ASC);
	I(lines, @"Sort Lines In Locale Order Ascending", CMD_EDIT_SORT_LOCALE_ASC);
	I(lines, @"Sort Lines As Integers Ascending", CMD_EDIT_SORT_INT_ASC);
	I(lines, @"Sort Lines As Decimals (Comma) Ascending", CMD_EDIT_SORT_DECCOMMA_ASC);
	I(lines, @"Sort Lines As Decimals (Dot) Ascending", CMD_EDIT_SORT_DECDOT_ASC);
	I(lines, @"Sort Lines By Length Ascending", CMD_EDIT_SORT_LEN_ASC);
	SEP(lines);
	I(lines, @"Sort Lines Lexicographically Descending", CMD_EDIT_SORT_LEX_DESC);
	I(lines, @"Sort Lines Lex. Descending Ignoring Case", CMD_EDIT_SORT_LEX_CI_DESC);
	I(lines, @"Sort Lines In Locale Order Descending", CMD_EDIT_SORT_LOCALE_DESC);
	I(lines, @"Sort Lines As Integers Descending", CMD_EDIT_SORT_INT_DESC);
	I(lines, @"Sort Lines As Decimals (Comma) Descending", CMD_EDIT_SORT_DECCOMMA_DESC);
	I(lines, @"Sort Lines As Decimals (Dot) Descending", CMD_EDIT_SORT_DECDOT_DESC);
	I(lines, @"Sort Lines By Length Descending", CMD_EDIT_SORT_LEN_DESC);
	NSMenu *comment = SUB(edit, @"Comment/Uncomment");
	I(comment, @"Toggle Single Line Comment", CMD_EDIT_BLOCK_COMMENT, @"/");
	I(comment, @"Single Line Comment", CMD_EDIT_BLOCK_COMMENT_SET, @"k", CMD | CTRL);
	I(comment, @"Single Line Uncomment", CMD_EDIT_BLOCK_UNCOMMENT, @"k", CMD | CTRL | SHIFT);
	I(comment, @"Block Comment", CMD_EDIT_STREAM_COMMENT, @"/", CMD | SHIFT);
	I(comment, @"Block Uncomment", CMD_EDIT_STREAM_UNCOMMENT, @"/", CMD | SHIFT | OPT);
	NSMenu *ac = SUB(edit, @"Auto-Completion");
	I(ac, @"Function Completion", CMD_EDIT_AUTOCOMPLETE, @" ", CTRL);
	I(ac, @"Word Completion", CMD_EDIT_AUTOCOMPLETE_CURRENTFILE, @"\r", CTRL);
	I(ac, @"Function Parameters Hint", CMD_EDIT_FUNCCALLTIP, @" ", CTRL | SHIFT);
	I(ac, @"Path Completion", CMD_EDIT_AUTOCOMPLETE_PATH, @" ", CTRL | OPT);
	NSMenuItem *eolItem = [[NSMenuItem alloc] initWithTitle:@"EOL Conversion" action:nil keyEquivalent:@""];
	eolItem.submenu = [self eolMenu];
	[edit addItem:eolItem];
	NSMenu *blank = SUB(edit, @"Blank Operations");
	I(blank, @"Trim Trailing Space", CMD_EDIT_TRIMTRAILING);
	I(blank, @"Trim Leading Space", CMD_EDIT_TRIMLINEHEAD);
	I(blank, @"Trim Leading and Trailing Space", CMD_EDIT_TRIM_BOTH);
	I(blank, @"EOL to Space", CMD_EDIT_EOL2WS);
	I(blank, @"Trim both and EOL to Space", CMD_EDIT_TRIMALL);
	SEP(blank);
	I(blank, @"TAB to Space", CMD_EDIT_TAB2SW);
	I(blank, @"Space to TAB (All)", CMD_EDIT_SW2TAB_ALL);
	I(blank, @"Space to TAB (Leading)", CMD_EDIT_SW2TAB_LEADING);
	NSMenu *paste = SUB(edit, @"Paste Special");
	I(paste, @"Paste HTML Content", CMD_EDIT_PASTE_AS_HTML);
	I(paste, @"Paste RTF Content", CMD_EDIT_PASTE_AS_RTF);
	NSMenu *onsel = SUB(edit, @"On Selection");
	I(onsel, @"Open File", CMD_EDIT_OPENSELECTEDFILE);
	I(onsel, @"Reveal File in Finder", CMD_EDIT_REVEALSELECTEDFILE);
	SEP(onsel);
	I(onsel, @"Redact Selection █", CMD_EDIT_REDACT_SELECTION);
	SEP(onsel);
	I(onsel, @"Search on Internet", CMD_EDIT_SEARCHONINTERNET);
	I(onsel, @"Change Search Engine…", CMD_EDIT_CHANGESEARCHENGINE);
	SEP(edit);
	NSMenu *msa = SUB(edit, @"Multi-select All");
	I(msa, @"Ignore Case & Whole Word", CMD_EDIT_MULTISELECTALL);
	I(msa, @"Match Case Only", CMD_EDIT_MULTISELECTALLMATCHCASE);
	I(msa, @"Match Whole Word Only", CMD_EDIT_MULTISELECTALLWHOLEWORD);
	I(msa, @"Match Case & Whole Word", CMD_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD);
	NSMenu *msn = SUB(edit, @"Multi-select Next");
	I(msn, @"Ignore Case & Whole Word", CMD_EDIT_MULTISELECTNEXT);
	I(msn, @"Match Case Only", CMD_EDIT_MULTISELECTNEXTMATCHCASE);
	I(msn, @"Match Whole Word Only", CMD_EDIT_MULTISELECTNEXTWHOLEWORD);
	I(msn, @"Match Case & Whole Word", CMD_EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD, @"d", CMD | OPT);
	I(edit, @"Undo the Latest Added Multi-Select", CMD_EDIT_MULTISELECTUNDO);
	I(edit, @"Skip Current & Go to Next Multi-select", CMD_EDIT_MULTISELECTSKIP);
	SEP(edit);
	I(edit, @"Column Mode…", CMD_EDIT_COLUMNMODETIP);
	I(edit, @"Column Editor…", CMD_EDIT_COLUMNMODE, @"c", CMD | OPT);
	I(edit, @"Character Panel", CMD_EDIT_CHAR_PANEL);
	I(edit, @"Clipboard History", CMD_EDIT_CLIPBOARDHISTORY_PANEL);
	SEP(edit);
	NSMenu *ro = SUB(edit, @"Read-Only in Macpad++");
	I(ro, @"Read-Only on Current Document", CMD_EDIT_TOGGLEREADONLY);
	I(ro, @"Read-Only for All Documents", CMD_EDIT_SETREADONLYFORALLDOCS);
	I(ro, @"Clear Read-Only for All Documents", CMD_EDIT_CLEARREADONLYFORALLDOCS);
	SEP(edit);
	NSMenuItem *emoji = [edit addItemWithTitle:@"Emoji & Symbols" action:@selector(orderFrontCharacterPalette:) keyEquivalent:@" "];
	emoji.keyEquivalentModifierMask = CMD | CTRL;

	// ---- Search ------------------------------------------------------------
	NSMenu *search = TOP(bar, @"Search");
	I(search, @"Find…", CMD_SEARCH_FIND, @"f");
	I(search, @"Find in Files…", CMD_SEARCH_FINDINFILES, @"f", CMD | SHIFT);
	I(search, @"Find Next", CMD_SEARCH_FINDNEXT, @"g");
	I(search, @"Find Previous", CMD_SEARCH_FINDPREV, @"g", CMD | SHIFT);
	I(search, @"Select and Find Next", CMD_SEARCH_SETANDFINDNEXT, fkey(NSF3FunctionKey), CMD);
	I(search, @"Select and Find Previous", CMD_SEARCH_SETANDFINDPREV, fkey(NSF3FunctionKey), CMD | SHIFT);
	I(search, @"Find (Volatile) Next", CMD_SEARCH_VOLATILE_FINDNEXT, fkey(NSF3FunctionKey), CMD | OPT);
	I(search, @"Find (Volatile) Previous", CMD_SEARCH_VOLATILE_FINDPREV, fkey(NSF3FunctionKey), CMD | OPT | SHIFT);
	I(search, @"Replace…", CMD_SEARCH_REPLACE, @"f", CMD | OPT);
	I(search, @"Incremental Search", CMD_SEARCH_FINDINCREMENT, @"i", CMD | OPT);
	I(search, @"Search Results Window", CMD_SEARCH_FOCUS_ON_FOUND_RESULTS, fkey(NSF7FunctionKey), 0);
	I(search, @"Next Search Result", CMD_SEARCH_GOTONEXTFOUND, fkey(NSF4FunctionKey), 0);
	I(search, @"Previous Search Result", CMD_SEARCH_GOTOPREVFOUND, fkey(NSF4FunctionKey), SHIFT);
	I(search, @"Go to…", CMD_SEARCH_GOTOLINE, @"l");
	I(search, @"Go to Matching Brace", CMD_SEARCH_GOTOMATCHINGBRACE, @"b");
	I(search, @"Select All In-between {} [] or ()", CMD_SEARCH_SELECTMATCHINGBRACES, @"b", CMD | OPT);
	I(search, @"Mark…", CMD_SEARCH_MARK, @"m", CMD | OPT);
	SEP(search);
	NSMenu *ch = SUB(search, @"Change History");
	I(ch, @"Go to Next Change", CMD_SEARCH_CHANGED_NEXT);
	I(ch, @"Go to Previous Change", CMD_SEARCH_CHANGED_PREV);
	I(ch, @"Clear Change History", CMD_SEARCH_CLEAR_CHANGE_HISTORY);
	SEP(search);
	NSArray *ord = @[@"1st", @"2nd", @"3rd", @"4th", @"5th"];
	NSMenu *styleAll = SUB(search, @"Style All Occurrences of Token");
	for (int i = 0; i < 5; ++i)
		I(styleAll, [NSString stringWithFormat:@"Using %@ Style", ord[i]], CMD_SEARCH_MARKALLEXT1 + i);
	NSMenu *styleOne = SUB(search, @"Style One Token");
	for (int i = 0; i < 5; ++i)
		I(styleOne, [NSString stringWithFormat:@"Using %@ Style", ord[i]], CMD_SEARCH_MARKONEEXT1 + i);
	NSMenu *clearStyle = SUB(search, @"Clear Style");
	for (int i = 0; i < 5; ++i)
		I(clearStyle, [NSString stringWithFormat:@"Clear %@ Style", ord[i]], CMD_SEARCH_UNMARKALLEXT1 + i);
	I(clearStyle, @"Clear all Styles", CMD_SEARCH_CLEARALLMARKS);
	NSMenu *jumpUp = SUB(search, @"Jump Up");
	for (int i = 0; i < 5; ++i)
		I(jumpUp, [NSString stringWithFormat:@"%@ Style", ord[i]], CMD_SEARCH_GOPREVMARKER1 + i);
	I(jumpUp, @"Find Mark Style", CMD_SEARCH_GOPREVMARKER_DEF);
	NSMenu *jumpDown = SUB(search, @"Jump Down");
	for (int i = 0; i < 5; ++i)
		I(jumpDown, [NSString stringWithFormat:@"%@ Style", ord[i]], CMD_SEARCH_GONEXTMARKER1 + i);
	I(jumpDown, @"Find Mark Style", CMD_SEARCH_GONEXTMARKER_DEF);
	NSMenu *copyStyled = SUB(search, @"Copy Styled Text");
	for (int i = 0; i < 5; ++i)
		I(copyStyled, [NSString stringWithFormat:@"%@ Style", ord[i]], CMD_SEARCH_STYLE1TOCLIP + i);
	I(copyStyled, @"All Styles", CMD_SEARCH_ALLSTYLESTOCLIP);
	I(copyStyled, @"Find Mark Style", CMD_SEARCH_MARKEDTOCLIP);
	SEP(search);
	NSMenu *bm = SUB(search, @"Bookmark");
	I(bm, @"Toggle Bookmark", CMD_SEARCH_TOGGLE_BOOKMARK, fkey(NSF2FunctionKey), CMD);
	I(bm, @"Next Bookmark", CMD_SEARCH_NEXT_BOOKMARK, fkey(NSF2FunctionKey), 0);
	I(bm, @"Previous Bookmark", CMD_SEARCH_PREV_BOOKMARK, fkey(NSF2FunctionKey), SHIFT);
	I(bm, @"Clear All Bookmarks", CMD_SEARCH_CLEAR_BOOKMARKS);
	I(bm, @"Cut Bookmarked Lines", CMD_SEARCH_CUTMARKEDLINES);
	I(bm, @"Copy Bookmarked Lines", CMD_SEARCH_COPYMARKEDLINES);
	I(bm, @"Paste to (Replace) Bookmarked Lines", CMD_SEARCH_PASTEMARKEDLINES);
	I(bm, @"Remove Bookmarked Lines", CMD_SEARCH_DELETEMARKEDLINES);
	I(bm, @"Remove Non-Bookmarked Lines", CMD_SEARCH_DELETEUNMARKEDLINES);
	I(bm, @"Inverse Bookmark", CMD_SEARCH_INVERSEMARKS);
	SEP(search);
	I(search, @"Find Characters in Range…", CMD_SEARCH_FINDCHARINRANGE);

	// ---- View --------------------------------------------------------------
	NSMenu *view = TOP(bar, @"View");
	I(view, @"Always on Top", CMD_VIEW_ALWAYSONTOP);
	I(view, @"Toggle Full Screen Mode", CMD_VIEW_FULLSCREENTOGGLE, @"f", CMD | CTRL);
	I(view, @"Post-It", CMD_VIEW_POSTIT);
	I(view, @"Distraction Free Mode", CMD_VIEW_DISTRACTIONFREE);
	SEP(view);
	NSMenu *viewIn = SUB(view, @"View Current File in");
	I(viewIn, @"Safari", CMD_VIEW_IN_SAFARI);
	I(viewIn, @"Chrome", CMD_VIEW_IN_CHROME);
	I(viewIn, @"Firefox", CMD_VIEW_IN_FIREFOX);
	I(viewIn, @"Edge", CMD_VIEW_IN_EDGE);
	SEP(view);
	NSMenu *sym = SUB(view, @"Show Symbol");
	I(sym, @"Show Space and Tab", CMD_VIEW_TAB_SPACE);
	I(sym, @"Show End of Line", CMD_VIEW_EOL);
	I(sym, @"Show Non-Printing Characters", CMD_VIEW_NPC);
	I(sym, @"Show All Characters", CMD_VIEW_ALL_CHARACTERS);
	SEP(sym);
	I(sym, @"Show Indent Guide", CMD_VIEW_INDENT_GUIDE);
	I(sym, @"Show Wrap Symbol", CMD_VIEW_WRAP_SYMBOL);
	NSMenu *zoom = SUB(view, @"Zoom");
	I(zoom, @"Zoom In", CMD_VIEW_ZOOMIN, @"=");
	I(zoom, @"Zoom Out", CMD_VIEW_ZOOMOUT, @"-");
	I(zoom, @"Restore Default Zoom", CMD_VIEW_ZOOMRESTORE, @"0");
	I(zoom, @"Synchronize Across Views", CMD_VIEW_ZOOM_SYNC);
	NSMenu *mv = SUB(view, @"Move/Clone Current Document");
	I(mv, @"Move to Other View", CMD_VIEW_GOTO_ANOTHER_VIEW);
	I(mv, @"Clone to Other View", CMD_VIEW_CLONE_TO_ANOTHER_VIEW);
	NSMenu *tab = SUB(view, @"Tab");
	for (int i = 0; i < 9; ++i)
		I(tab, [NSString stringWithFormat:@"%@ Tab", @[@"1st", @"2nd", @"3rd", @"4th", @"5th", @"6th", @"7th", @"8th", @"9th"][i]],
		  CMD_VIEW_TAB1 + i, [NSString stringWithFormat:@"%d", i + 1]);
	SEP(tab);
	I(tab, @"First Tab", CMD_VIEW_TAB_START);
	I(tab, @"Last Tab", CMD_VIEW_TAB_END);
	I(tab, @"Next Tab", CMD_VIEW_TAB_NEXT, @"\t", CTRL);
	I(tab, @"Previous Tab", CMD_VIEW_TAB_PREV, @"\t", CTRL | SHIFT);
	SEP(tab);
	I(tab, @"Move to Start", CMD_VIEW_GOTO_START);
	I(tab, @"Move to End", CMD_VIEW_GOTO_END);
	I(tab, @"Move Tab Forward", CMD_VIEW_TAB_MOVEFORWARD, fkey(NSPageDownFunctionKey), CTRL | SHIFT);
	I(tab, @"Move Tab Backward", CMD_VIEW_TAB_MOVEBACKWARD, fkey(NSPageUpFunctionKey), CTRL | SHIFT);
	SEP(tab);
	for (int i = 0; i < 5; ++i)
		I(tab, [NSString stringWithFormat:@"Apply Color %d", i + 1], CMD_VIEW_TAB_COLOUR_1 + i);
	I(tab, @"Remove Color", CMD_VIEW_TAB_COLOUR_NONE);
	SEP(view);
	I(view, @"Word Wrap", CMD_VIEW_WRAP);
	I(view, @"Focus on Another View", CMD_VIEW_SWITCHTO_OTHER_VIEW, fkey(NSF8FunctionKey), 0);
	I(view, @"Hide Lines", CMD_VIEW_HIDELINES);
	SEP(view);
	I(view, @"Fold All", CMD_VIEW_FOLDALL, @"0", CMD | OPT);
	I(view, @"Unfold All", CMD_VIEW_UNFOLDALL, @"0", CMD | OPT | SHIFT);
	I(view, @"Fold Current Level", CMD_VIEW_FOLD_CURRENT, @"[", CMD | OPT);
	I(view, @"Unfold Current Level", CMD_VIEW_UNFOLD_CURRENT, @"]", CMD | OPT);
	NSMenu *foldLevel = SUB(view, @"Fold Level");
	NSMenu *unfoldLevel = SUB(view, @"Unfold Level");
	for (int i = 0; i < 8; ++i) {
		I(foldLevel, [NSString stringWithFormat:@"%d", i + 1], CMD_VIEW_FOLD_1 + i, [NSString stringWithFormat:@"%d", i + 1], CMD | OPT);
		I(unfoldLevel, [NSString stringWithFormat:@"%d", i + 1], CMD_VIEW_UNFOLD_1 + i, [NSString stringWithFormat:@"%d", i + 1], CMD | OPT | SHIFT);
	}
	SEP(view);
	I(view, @"Summary…", CMD_VIEW_SUMMARY);
	SEP(view);
	I(view, @"Folder as Workspace", CMD_VIEW_FILEBROWSER);
	I(view, @"Document Map", CMD_VIEW_DOC_MAP);
	I(view, @"Document List", CMD_VIEW_DOCLIST);
	I(view, @"Function List", CMD_VIEW_FUNC_LIST);
	SEP(view);
	I(view, @"Synchronize Vertical Scrolling", CMD_VIEW_SYNSCROLLV);
	I(view, @"Synchronize Horizontal Scrolling", CMD_VIEW_SYNSCROLLH);
	SEP(view);
	I(view, @"Monitoring (tail -f)", CMD_VIEW_MONITORING);
	SEP(view);
	I(view, @"Show Toolbar", CMD_VIEW_TOOLBAR, @"t", CMD | OPT);
	I(view, @"Show Status Bar", CMD_VIEW_STATUSBAR);
	I(view, @"Show Line Numbers", CMD_VIEW_LINENUMBER);
	I(view, @"Show Bookmark Margin", CMD_VIEW_BOOKMARK_MARGIN);
	I(view, @"Show Change History", CMD_VIEW_CHANGE_HISTORY_MARGIN);

	// ---- Encoding / Language -------------------------------------------------
	NSMenuItem *encItem = [[NSMenuItem alloc] initWithTitle:@"Encoding" action:nil keyEquivalent:@""];
	encItem.submenu = [self encodingMenu];
	[bar addItem:encItem];

	NSMenuItem *langItem = [[NSMenuItem alloc] initWithTitle:@"Language" action:nil keyEquivalent:@""];
	langItem.submenu = [self languageMenu];
	[bar addItem:langItem];
	for (NSMenuItem *it in langItem.submenu.itemArray)
		if ([it.submenu.identifier isEqualToString:MppMenuUserLangs])
			it.submenu.delegate = delegate;

	// ---- Settings ------------------------------------------------------------
	NSMenu *settings = TOP(bar, @"Settings");
	I(settings, @"Preferences…", CMD_SETTING_PREFERENCE);
	I(settings, @"Style Configurator…", CMD_SETTING_STYLE_CONFIG);
	I(settings, @"Shortcut List…", CMD_SETTING_SHORTCUT_MAPPER);
	SEP(settings);
	NSMenu *imp = SUB(settings, @"Import");
	I(imp, @"Import Style Theme(s)…", CMD_SETTING_IMPORT_THEMES);
	I(imp, @"Import User Defined Language…", CMD_LANG_IMPORT_UDL);
	I(settings, @"Open Settings Folder…", CMD_SETTING_OPEN_SETTINGS_DIR);

	// ---- Tools ---------------------------------------------------------------
	NSMenu *tools = TOP(bar, @"Tools");
	struct { NSString *name; int base; } hashes[] = {
		{@"MD5", CMD_TOOL_MD5_GENERATE}, {@"SHA-1", CMD_TOOL_SHA1_GENERATE},
		{@"SHA-256", CMD_TOOL_SHA256_GENERATE}, {@"SHA-512", CMD_TOOL_SHA512_GENERATE}};
	for (auto &h : hashes) {
		NSMenu *hm = SUB(tools, h.name);
		I(hm, @"Generate…", h.base);
		I(hm, @"Generate from Files…", h.base + 1);
		I(hm, @"Generate from Selection into Clipboard", h.base + 2);
	}

	// ---- Macro ---------------------------------------------------------------
	NSMenu *macro = TOP(bar, @"Macro");
	macro.identifier = MppMenuMacros;
	macro.delegate = delegate;
	I(macro, @"Start Recording", CMD_MACRO_START_RECORDING, @"r", CMD | SHIFT);
	I(macro, @"Stop Recording", CMD_MACRO_STOP_RECORDING);
	I(macro, @"Playback", CMD_MACRO_PLAYBACK, @"p", CMD | SHIFT);
	I(macro, @"Save Current Recorded Macro…", CMD_MACRO_SAVE_CURRENT);
	I(macro, @"Run a Macro Multiple Times…", CMD_MACRO_RUN_MULTI);
	I(macro, @"Manage Saved Macros…", CMD_MACRO_MANAGE);

	// ---- Run -----------------------------------------------------------------
	NSMenu *run = TOP(bar, @"Run");
	run.identifier = MppMenuRun;
	run.delegate = delegate;
	I(run, @"Run…", CMD_RUN_EXECUTE, fkey(NSF5FunctionKey), 0);
	I(run, @"Manage Saved Commands…", CMD_RUN_MANAGE);

	// ---- Plugins -------------------------------------------------------------
	NSMenu *plugins = TOP(bar, @"Plugins");
	I(plugins, @"About Plugins on macOS…", CMD_HELP_PLUGINS_INFO);

	// ---- Window --------------------------------------------------------------
	NSMenu *window = TOP(bar, @"Window");
	NSMenu *sortBy = SUB(window, @"Sort By");
	I(sortBy, @"Name A to Z", CMD_WINDOW_SORT_FN_ASC);
	I(sortBy, @"Name Z to A", CMD_WINDOW_SORT_FN_DSC);
	I(sortBy, @"Path A to Z", CMD_WINDOW_SORT_FP_ASC);
	I(sortBy, @"Path Z to A", CMD_WINDOW_SORT_FP_DSC);
	I(sortBy, @"Type A to Z", CMD_WINDOW_SORT_FT_ASC);
	I(sortBy, @"Type Z to A", CMD_WINDOW_SORT_FT_DSC);
	I(sortBy, @"Content Length Ascending", CMD_WINDOW_SORT_FS_ASC);
	I(sortBy, @"Content Length Descending", CMD_WINDOW_SORT_FS_DSC);
	I(window, @"Windows…", CMD_WINDOW_WINDOWS);
	SEP(window);
	[window addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
	[window addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
	SEP(window);
	[window addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
	NSApp.windowsMenu = window;

	// ---- Help ----------------------------------------------------------------
	NSMenu *help = TOP(bar, @"Help");
	I(help, @"Command Line Arguments…", CMD_HELP_CMDLINE);
	SEP(help);
	I(help, @"Debug Info…", CMD_HELP_DEBUGINFO);
	I(help, @"About Macpad++", CMD_HELP_ABOUT);
	NSApp.helpMenu = help;

	return bar;
}

@end
