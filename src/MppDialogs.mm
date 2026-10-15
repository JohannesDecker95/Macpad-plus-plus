// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppDialogs.h"
#import "MppMainWindowController.h"
#import "MppMacro.h"
#import "MppPrefs.h"
#import "MppPaths.h"
#import "MppEditing.h"
#import "MppLanguages.h"
#include "Scintilla.h"
#include <sys/utsname.h>

// ---- small UI helpers ---------------------------------------------------------------

static NSTextField *label(NSString *s)
{
	NSTextField *t = [NSTextField labelWithString:s];
	return t;
}

static NSTextField *field(NSString *s, CGFloat width)
{
	NSTextField *t = [NSTextField textFieldWithString:s ?: @""];
	t.translatesAutoresizingMaskIntoConstraints = NO;
	[t.widthAnchor constraintEqualToConstant:width].active = YES;
	return t;
}

static NSButton *radio(NSString *title, id target, SEL action)
{
	NSButton *b = [NSButton radioButtonWithTitle:title target:target action:action];
	return b;
}

static NSView *stackV(NSArray<NSView *> *views, CGFloat spacing)
{
	NSStackView *s = [NSStackView stackViewWithViews:views];
	s.orientation = NSUserInterfaceLayoutOrientationVertical;
	s.alignment = NSLayoutAttributeLeading;
	s.spacing = spacing;
	s.translatesAutoresizingMaskIntoConstraints = NO;
	return s;
}

static NSView *stackH(NSArray<NSView *> *views, CGFloat spacing)
{
	NSStackView *s = [NSStackView stackViewWithViews:views];
	s.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	s.alignment = NSLayoutAttributeFirstBaseline;
	s.spacing = spacing;
	s.translatesAutoresizingMaskIntoConstraints = NO;
	return s;
}

// Wraps an auto-layout view in a frame-sized container (NSAlert accessory views need a frame)
static NSView *fitted(NSView *content)
{
	NSSize sz = content.fittingSize;
	NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, MAX(sz.width, 300), sz.height)];
	[box addSubview:content];
	[NSLayoutConstraint activateConstraints:@[
		[content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor],
		[content.topAnchor constraintEqualToAnchor:box.topAnchor],
	]];
	return box;
}

NSString *MppAskString(NSString *title, NSString *prompt, NSString *def)
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = title;
	a.informativeText = prompt ?: @"";
	[a addButtonWithTitle:@"OK"];
	[a addButtonWithTitle:@"Cancel"];
	NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
	f.stringValue = def ?: @"";
	a.accessoryView = f;
	a.window.initialFirstResponder = f;
	[a layout];
	[a.window makeFirstResponder:f];
	if ([a runModal] != NSAlertFirstButtonReturn)
		return nil;
	return f.stringValue;
}

@interface MppTextResultController : NSWindowController
@end
@implementation MppTextResultController
@end

void MppShowTextResult(NSString *title, NSString *text)
{
	NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
	                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
	                                          backing:NSBackingStoreBuffered defer:NO];
	p.title = title;
	NSScrollView *sv = [NSTextView scrollableTextView];
	sv.frame = p.contentView.bounds;
	sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	NSTextView *tv = sv.documentView;
	tv.font = [NSFont userFixedPitchFontOfSize:12];
	tv.string = text ?: @"";
	tv.editable = NO;
	[p.contentView addSubview:sv];
	static NSMutableArray *keep;
	if (!keep)
		keep = [NSMutableArray array];
	MppTextResultController *c = [[MppTextResultController alloc] initWithWindow:p];
	[keep addObject:c];
	[p center];
	[c showWindow:nil];
}

// ---- Go To ----------------------------------------------------------------------------

@interface MppRadioTarget : NSObject
@property (nonatomic, copy) void (^handler)(NSButton *);
@end
@implementation MppRadioTarget
- (void)changed:(NSButton *)b { if (_handler) _handler(b); }
@end

void MppShowGoToDialog(MppMainWindowController *o)
{
	const sptr_t curLine = [o sci:SCI_LINEFROMPOSITION w:(uptr_t)[o sci:SCI_GETCURRENTPOS]] + 1;
	const sptr_t lines = [o sci:SCI_GETLINECOUNT];
	const sptr_t curPos = [o sci:SCI_GETCURRENTPOS];
	const sptr_t len = [o sci:SCI_GETLENGTH];

	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Go To…";
	[a addButtonWithTitle:@"Go"];
	[a addButtonWithTitle:@"Cancel"];
	MppRadioTarget *t = [[MppRadioTarget alloc] init];
	NSButton *rLine = radio(@"Line", t, @selector(changed:));
	NSButton *rOffset = radio(@"Offset", t, @selector(changed:));
	rLine.state = NSControlStateValueOn;
	NSTextField *here = label([NSString stringWithFormat:@"You are here: %ld", (long)curLine]);
	NSTextField *maxL = label([NSString stringWithFormat:@"You can't go further than: %ld", (long)lines]);
	NSTextField *f = field(@"", 160);
	t.handler = ^(NSButton *b) {
		const BOOL line = (b == rLine);
		rLine.state = line ? NSControlStateValueOn : NSControlStateValueOff;
		rOffset.state = line ? NSControlStateValueOff : NSControlStateValueOn;
		here.stringValue = [NSString stringWithFormat:@"You are here: %ld", (long)(line ? curLine : curPos)];
		maxL.stringValue = [NSString stringWithFormat:@"You can't go further than: %ld", (long)(line ? lines : len)];
	};
	a.accessoryView = fitted(stackV(@[stackH(@[rLine, rOffset], 16), here, stackH(@[label(@"You want to go to:"), f], 8), maxL], 8));
	[a layout];
	[a.window makeFirstResponder:f];
	if ([a runModal] != NSAlertFirstButtonReturn)
		return;
	const long long v = f.stringValue.longLongValue;
	if (rLine.state == NSControlStateValueOn) {
		sptr_t line = (sptr_t)v - 1;
		line = std::max<sptr_t>(0, std::min(line, lines - 1));
		[o gotoLine:line];
	} else {
		sptr_t pos = std::max<sptr_t>(0, std::min<sptr_t>((sptr_t)v, len));
		[o sci:SCI_GOTOPOS w:(uptr_t)pos];
		[o.window makeFirstResponder:o.activeEditor.content];
	}
}

// ---- Column editor ----------------------------------------------------------------------

static std::string formatNumber(long long n, int base, int width, int leading)
{
	std::string digits;
	unsigned long long u = n < 0 ? (unsigned long long)(-n) : (unsigned long long)n;
	do {
		const int d = (int)(u % (unsigned)base);
		digits.insert(digits.begin(), (char)(d < 10 ? '0' + d : 'A' + d - 10));
		u /= (unsigned)base;
	} while (u);
	if (n < 0)
		digits.insert(digits.begin(), '-');
	while ((int)digits.size() < width)
		digits.insert(digits.begin(), leading == 1 ? '0' : ' ');
	return digits;
}

void MppShowColumnEditor(MppMainWindowController *o)
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Column / Multi-Selection Editor";
	[a addButtonWithTitle:@"OK"];
	[a addButtonWithTitle:@"Cancel"];
	MppRadioTarget *t = [[MppRadioTarget alloc] init];
	NSButton *rText = radio(@"Text to Insert", t, @selector(changed:));
	NSButton *rNum = radio(@"Number to Insert", t, @selector(changed:));
	rText.state = NSControlStateValueOn;
	t.handler = ^(NSButton *b) {
		rText.state = b == rText ? NSControlStateValueOn : NSControlStateValueOff;
		rNum.state = b == rNum ? NSControlStateValueOn : NSControlStateValueOff;
	};
	NSTextField *text = field(@"", 300);
	NSTextField *initial = field(@"1", 80), *inc = field(@"1", 80), *rep = field(@"1", 80);
	NSPopUpButton *leading = [[NSPopUpButton alloc] init];
	[leading addItemsWithTitles:@[@"None", @"Zeros", @"Spaces"]];
	NSPopUpButton *format = [[NSPopUpButton alloc] init];
	[format addItemsWithTitles:@[@"Dec", @"Hex", @"Oct", @"Bin"]];
	a.accessoryView = fitted(stackV(@[rText, text, rNum,
	                                  stackH(@[label(@"Initial number:"), initial, label(@"Increase by:"), inc], 6),
	                                  stackH(@[label(@"Repeat:"), rep, label(@"Leading:"), leading], 6),
	                                  stackH(@[label(@"Format:"), format], 6)], 8));
	[a layout];
	[a.window makeFirstResponder:text];
	if ([a runModal] != NSAlertFirstButtonReturn)
		return;

	MppColumnInsert(o, rText.state == NSControlStateValueOn, text.stringValue, initial.stringValue.longLongValue,
	                inc.stringValue.longLongValue, rep.stringValue.longLongValue,
	                (int[]){10, 16, 8, 2}[format.indexOfSelectedItem], (int)leading.indexOfSelectedItem);
}

void MppColumnInsert(MppMainWindowController *o, BOOL isText, NSString *text, long long init, long long step,
                     long long repeat, int base, int lead)
{
	// Lines and column
	sptr_t l1, l2, col;
	if ([o sci:SCI_SELECTIONISRECTANGLE] || [o sci:SCI_GETSELECTIONS] > 1) {
		const sptr_t n = [o sci:SCI_GETSELECTIONS];
		l1 = LONG_MAX; l2 = 0; col = LONG_MAX;
		for (sptr_t i = 0; i < n; ++i) {
			const sptr_t s = [o sci:SCI_GETSELECTIONNSTART w:(uptr_t)i];
			const sptr_t line = [o sci:SCI_LINEFROMPOSITION w:(uptr_t)s];
			l1 = std::min(l1, line);
			l2 = std::max(l2, line);
			col = std::min(col, [o sci:SCI_GETCOLUMN w:(uptr_t)s] + [o sci:SCI_GETSELECTIONNSTARTVIRTUALSPACE w:(uptr_t)i]);
		}
	} else {
		const sptr_t pos = [o sci:SCI_GETCURRENTPOS];
		l1 = [o sci:SCI_LINEFROMPOSITION w:(uptr_t)pos];
		l2 = [o sci:SCI_GETLINECOUNT] - 1;
		col = [o sci:SCI_GETCOLUMN w:(uptr_t)pos];
	}
	repeat = std::max<long long>(1, repeat);
	int width = 0;
	if (!isText && lead != 0) {
		for (sptr_t i = 0; i <= l2 - l1; ++i)
			width = std::max(width, (int)formatNumber(init + step * (i / repeat), base, 0, 0).size());
	}
	[o sci:SCI_BEGINUNDOACTION];
	for (sptr_t line = l2; line >= l1; --line) {
		std::string ins = isText ? std::string(text.UTF8String ?: "")
		                         : formatNumber(init + step * ((line - l1) / repeat), base, width, lead);
		sptr_t pos = [o sci:SCI_FINDCOLUMN w:(uptr_t)line l:col];
		const sptr_t reached = [o sci:SCI_GETCOLUMN w:(uptr_t)pos];
		if (reached < col)
			ins = std::string((size_t)(col - reached), ' ') + ins;
		[o sci:SCI_INSERTTEXT w:(uptr_t)pos l:(sptr_t)ins.c_str()];
	}
	[o sci:SCI_ENDUNDOACTION];
}

// ---- Find characters in range ---------------------------------------------------------------

void MppShowFindCharsInRange(MppMainWindowController *o)
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Find Characters in Range";
	[a addButtonWithTitle:@"Find Next"];
	[a addButtonWithTitle:@"Find Previous"];
	[a addButtonWithTitle:@"Close"];
	MppRadioTarget *t = [[MppRadioTarget alloc] init];
	NSButton *r1 = radio(@"Non-ASCII Characters (128-255 and above)", t, @selector(changed:));
	NSButton *r2 = radio(@"ASCII Characters (0-127)", t, @selector(changed:));
	NSButton *r3 = radio(@"My Range:", t, @selector(changed:));
	r1.state = NSControlStateValueOn;
	t.handler = ^(NSButton *b) {
		for (NSButton *x in @[r1, r2, r3])
			x.state = x == b ? NSControlStateValueOn : NSControlStateValueOff;
	};
	NSTextField *from = field(@"0", 70), *to = field(@"255", 70);
	NSButton *wrap = [NSButton checkboxWithTitle:@"Wrap around" target:nil action:nil];
	wrap.state = NSControlStateValueOn;
	a.accessoryView = fitted(stackV(@[r1, r2, stackH(@[r3, from, label(@"-"), to], 6), wrap], 8));
	NSModalResponse r = [a runModal];
	if (r == NSAlertThirdButtonReturn)
		return;
	long lo, hi;
	if (r1.state == NSControlStateValueOn) { lo = 128; hi = 0x10FFFF; }
	else if (r2.state == NSControlStateValueOn) { lo = 0; hi = 127; }
	else { lo = from.stringValue.integerValue; hi = to.stringValue.integerValue; }
	if (!MppFindCharsInRange(o, lo, hi, r == NSAlertFirstButtonReturn, wrap.state == NSControlStateValueOn)) {
		NSBeep();
		[o setStatusMessage:@"Find Characters in Range: not found"];
	}
}

BOOL MppFindCharsInRange(MppMainWindowController *o, long lo, long hi, BOOL forward, BOOL wrap)
{
	const sptr_t len = [o sci:SCI_GETLENGTH];
	auto codeAt = [&](sptr_t p, sptr_t *next) -> long {
		const unsigned char c = (unsigned char)[o sci:SCI_GETCHARAT w:(uptr_t)p];
		const sptr_t after = [o sci:SCI_POSITIONAFTER w:(uptr_t)p];
		*next = after > p ? after : p + 1;
		if (c < 0x80)
			return c;
		std::string s = MppGetRange(o.activeEditor, p, *next);
		NSString *ns = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
		if (!ns.length)
			return c;
		UTF32Char u = 0;
		[ns getBytes:&u maxLength:4 usedLength:nullptr encoding:NSUTF32LittleEndianStringEncoding options:0
		       range:NSMakeRange(0, ns.length) remainingRange:nullptr];
		return (long)u;
	};
	auto search = [&](sptr_t start, sptr_t end) -> sptr_t {
		if (forward) {
			sptr_t p = start;
			while (p < end) {
				sptr_t next;
				const long c = codeAt(p, &next);
				if (c >= lo && c <= hi)
					return p;
				p = next;
			}
		} else {
			sptr_t p = start;
			while (p > end) {
				const sptr_t prev = [o sci:SCI_POSITIONBEFORE w:(uptr_t)p];
				sptr_t next;
				const long c = codeAt(prev, &next);
				if (c >= lo && c <= hi)
					return prev;
				p = prev;
			}
		}
		return -1;
	};
	sptr_t found = forward ? search([o sci:SCI_GETSELECTIONEND], len) : search([o sci:SCI_GETSELECTIONSTART], 0);
	if (found < 0 && wrap)
		found = forward ? search(0, len) : search(len, 0);
	if (found < 0)
		return NO;
	[o selectRangeFrom:found to:[o sci:SCI_POSITIONAFTER w:(uptr_t)found]];
	return YES;
}

// ---- Windows dialog ---------------------------------------------------------------------------

@interface MppWindowsDialog : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) MppMainWindowController *owner;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSPanel *panel;
@end

@implementation MppWindowsDialog

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)_owner.allDocuments.count;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	MppDocument *d = _owner.allDocuments[(NSUInteger)row];
	if ([col.identifier isEqualToString:@"name"])
		return [NSString stringWithFormat:@"%@%@", d.displayName, d.dirty ? @"*" : @""];
	if ([col.identifier isEqualToString:@"path"])
		return d.filePath.stringByDeletingLastPathComponent ?: @"";
	if ([col.identifier isEqualToString:@"type"])
		return [MppLanguages shortNameForLang:d.lang];
	sptr_t len = [MppDocumentManager.shared scratchMessage:SCI_GETLENGTH doc:d wParam:0 lParam:0];
	return [NSByteCountFormatter stringFromByteCount:len countStyle:NSByteCountFormatterCountStyleFile];
}

- (NSArray<MppDocument *> *)selectedDocs
{
	NSMutableArray *a = [NSMutableArray array];
	NSArray *all = _owner.allDocuments;
	[_table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
		if (i < all.count)
			[a addObject:all[i]];
	}];
	return a;
}

- (void)activate:(id)sender
{
	MppDocument *d = [self selectedDocs].firstObject;
	if (d)
		[_owner activateDocument:d];
	[NSApp stopModal];
}

- (void)save:(id)sender
{
	for (MppDocument *d in [self selectedDocs])
		[_owner saveDocument:d];
	[_table reloadData];
}

- (void)closeDocs:(id)sender
{
	[_owner closeDocuments:[self selectedDocs]];
	[_table reloadData];
}

- (void)done:(id)sender
{
	[NSApp stopModal];
}

@end

void MppShowWindowsDialog(MppMainWindowController *o)
{
	MppWindowsDialog *d = [[MppWindowsDialog alloc] init];
	d.owner = o;
	NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 720, 400)
	                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
	                                          backing:NSBackingStoreBuffered defer:NO];
	p.title = @"Windows";
	d.panel = p;
	NSTableView *t = [[NSTableView alloc] init];
	t.allowsMultipleSelection = YES;
	t.usesAlternatingRowBackgroundColors = YES;
	for (NSArray *c in @[@[@"name", @"Name", @200], @[@"path", @"Path", @300], @[@"type", @"Type", @90], @[@"size", @"Size", @80]]) {
		NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
		col.title = c[1];
		col.width = [c[2] doubleValue];
		[t addTableColumn:col];
	}
	t.dataSource = d;
	t.delegate = d;
	t.target = d;
	t.doubleAction = @selector(activate:);
	d.table = t;
	NSScrollView *sv = [[NSScrollView alloc] init];
	sv.documentView = t;
	sv.hasVerticalScroller = YES;
	sv.translatesAutoresizingMaskIntoConstraints = NO;
	NSButton *bAct = [NSButton buttonWithTitle:@"Activate" target:d action:@selector(activate:)];
	NSButton *bSave = [NSButton buttonWithTitle:@"Save" target:d action:@selector(save:)];
	NSButton *bClose = [NSButton buttonWithTitle:@"Close Window(s)" target:d action:@selector(closeDocs:)];
	NSButton *bOK = [NSButton buttonWithTitle:@"OK" target:d action:@selector(done:)];
	bOK.keyEquivalent = @"\r";
	NSView *buttons = stackH(@[bAct, bSave, bClose, bOK], 8);
	[p.contentView addSubview:sv];
	[p.contentView addSubview:buttons];
	NSView *cv = p.contentView;
	[NSLayoutConstraint activateConstraints:@[
		[sv.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
		[sv.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
		[sv.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[buttons.topAnchor constraintEqualToAnchor:sv.bottomAnchor constant:12],
		[buttons.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[buttons.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
	]];
	NSInteger cur = (NSInteger)[o.allDocuments indexOfObject:o.currentDocument];
	if (cur != NSNotFound)
		[t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)cur] byExtendingSelection:NO];
	[p center];
	[NSApp runModalForWindow:p];
	[p orderOut:nil];
}

// ---- Hash dialog ------------------------------------------------------------------------------

@interface MppHashDialog : NSWindowController <NSTextViewDelegate>
@property (nonatomic) int algo;
@property (nonatomic, strong) NSTextView *input, *output;
@property (nonatomic, strong) NSButton *perLine;
@end

@implementation MppHashDialog

- (void)update
{
	NSString *text = _input.string;
	NSMutableArray *out = [NSMutableArray array];
	if (_perLine.state == NSControlStateValueOn) {
		for (NSString *l in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet])
			[out addObject:l.length ? MppHashData([l dataUsingEncoding:NSUTF8StringEncoding], _algo) : @""];
	} else if (text.length) {
		[out addObject:MppHashData([text dataUsingEncoding:NSUTF8StringEncoding], _algo)];
	}
	_output.string = [out componentsJoinedByString:@"\n"];
}

- (void)textDidChange:(NSNotification *)n { [self update]; }
- (void)toggled:(id)sender { [self update]; }
- (void)copyResult:(id)sender
{
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:_output.string forType:NSPasteboardTypeString];
}

@end

void MppShowHashDialog(int algo)
{
	static NSMutableArray *keep;
	if (!keep)
		keep = [NSMutableArray array];
	NSArray *names = @[@"MD5", @"SHA-1", @"SHA-256", @"SHA-512"];
	NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 420)
	                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
	                                          backing:NSBackingStoreBuffered defer:NO];
	p.title = [NSString stringWithFormat:@"Generate %@ digest", names[(NSUInteger)algo]];
	MppHashDialog *c = [[MppHashDialog alloc] initWithWindow:p];
	c.algo = algo;
	NSScrollView *in = [NSTextView scrollableTextView], *out = [NSTextView scrollableTextView];
	c.input = in.documentView;
	c.output = out.documentView;
	c.input.font = c.output.font = [NSFont userFixedPitchFontOfSize:12];
	c.input.delegate = c;
	c.output.editable = NO;
	c.perLine = [NSButton checkboxWithTitle:@"Treat each line as a separate string" target:c action:@selector(toggled:)];
	NSButton *copy = [NSButton buttonWithTitle:@"Copy to Clipboard" target:c action:@selector(copyResult:)];
	for (NSView *v in @[in, out, c.perLine, copy]) {
		v.translatesAutoresizingMaskIntoConstraints = NO;
		[p.contentView addSubview:v];
	}
	NSView *cv = p.contentView;
	[NSLayoutConstraint activateConstraints:@[
		[in.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
		[in.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
		[in.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[in.heightAnchor constraintEqualToAnchor:out.heightAnchor],
		[c.perLine.topAnchor constraintEqualToAnchor:in.bottomAnchor constant:8],
		[c.perLine.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
		[out.topAnchor constraintEqualToAnchor:c.perLine.bottomAnchor constant:8],
		[out.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
		[out.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[copy.topAnchor constraintEqualToAnchor:out.bottomAnchor constant:8],
		[copy.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
		[copy.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
	]];
	[keep addObject:c];
	[p center];
	[c showWindow:nil];
	[p makeFirstResponder:c.input];
}

// ---- Shortcut list ----------------------------------------------------------------------------

@interface MppShortcutList : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
@property (nonatomic, strong) NSArray<NSArray *> *all, *shown;
@property (nonatomic, strong) NSTableView *table;
@end

@implementation MppShortcutList

static NSString *shortcutString(NSMenuItem *it)
{
	if (!it.keyEquivalent.length)
		return nil;
	NSMutableString *s = [NSMutableString string];
	NSEventModifierFlags m = it.keyEquivalentModifierMask;
	if (m & NSEventModifierFlagControl) [s appendString:@"⌃"];
	if (m & NSEventModifierFlagOption) [s appendString:@"⌥"];
	if (m & NSEventModifierFlagShift) [s appendString:@"⇧"];
	if (m & NSEventModifierFlagCommand) [s appendString:@"⌘"];
	unichar c = [it.keyEquivalent characterAtIndex:0];
	NSString *k;
	switch (c) {
		case NSF1FunctionKey ... NSF35FunctionKey: k = [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1]; break;
		case NSUpArrowFunctionKey: k = @"↑"; break;
		case NSDownArrowFunctionKey: k = @"↓"; break;
		case NSPageUpFunctionKey: k = @"PgUp"; break;
		case NSPageDownFunctionKey: k = @"PgDn"; break;
		case '\r': k = @"↩"; break;
		case '\t': k = @"⇥"; break;
		case ' ': k = @"Space"; break;
		default: k = it.keyEquivalent.uppercaseString; break;
	}
	[s appendString:k];
	return s;
}

static void collect(NSMenu *m, NSString *path, NSMutableArray *out)
{
	for (NSMenuItem *it in m.itemArray) {
		if (it.isSeparatorItem)
			continue;
		NSString *p = path.length ? [NSString stringWithFormat:@"%@ › %@", path, it.title] : it.title;
		if (it.submenu)
			collect(it.submenu, p, out);
		else if (NSString *sc = shortcutString(it))
			[out addObject:@[p, sc]];
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_shown.count; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row
{
	return _shown[(NSUInteger)row][[col.identifier isEqualToString:@"cmd"] ? 0 : 1];
}
- (void)controlTextDidChange:(NSNotification *)n
{
	NSString *q = [(NSSearchField *)n.object stringValue];
	if (!q.length) {
		_shown = _all;
	} else {
		NSMutableArray *a = [NSMutableArray array];
		for (NSArray *r in _all)
			if ([r[0] localizedCaseInsensitiveContainsString:q] || [r[1] localizedCaseInsensitiveContainsString:q])
				[a addObject:r];
		_shown = a;
	}
	[_table reloadData];
}

@end

void MppShowShortcutList(NSMenu *mainMenu)
{
	static MppShortcutList *c;
	if (!c) {
		NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 520)
		                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
		                                          backing:NSBackingStoreBuffered defer:NO];
		p.title = @"Shortcut List";
		c = [[MppShortcutList alloc] initWithWindow:p];
		NSMutableArray *all = [NSMutableArray array];
		collect(mainMenu, @"", all);
		c.all = c.shown = all;
		NSSearchField *search = [[NSSearchField alloc] init];
		search.delegate = c;
		search.placeholderString = @"Filter";
		NSTableView *t = [[NSTableView alloc] init];
		for (NSArray *col in @[@[@"cmd", @"Command", @430], @[@"key", @"Shortcut", @150]]) {
			NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col[0]];
			tc.title = col[1];
			tc.width = [col[2] doubleValue];
			[t addTableColumn:tc];
		}
		t.dataSource = c;
		t.delegate = c;
		t.usesAlternatingRowBackgroundColors = YES;
		c.table = t;
		NSScrollView *sv = [[NSScrollView alloc] init];
		sv.documentView = t;
		sv.hasVerticalScroller = YES;
		NSTextField *note = [NSTextField wrappingLabelWithString:
		    @"Shortcuts can be customized in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts (use the exact menu item title)."];
		note.textColor = NSColor.secondaryLabelColor;
		for (NSView *v in @[search, sv, note]) {
			v.translatesAutoresizingMaskIntoConstraints = NO;
			[p.contentView addSubview:v];
		}
		NSView *cv = p.contentView;
		[NSLayoutConstraint activateConstraints:@[
			[search.topAnchor constraintEqualToAnchor:cv.topAnchor constant:12],
			[search.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
			[search.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
			[sv.topAnchor constraintEqualToAnchor:search.bottomAnchor constant:8],
			[sv.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
			[sv.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
			[note.topAnchor constraintEqualToAnchor:sv.bottomAnchor constant:8],
			[note.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:12],
			[note.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-12],
			[note.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-12],
		]];
		[p center];
	}
	[c showWindow:nil];
}

// ---- About / help / debug ---------------------------------------------------------------------

static NSString *versionString(void)
{
	return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
}

void MppShowAbout(void)
{
	NSString *credits = @"Native macOS text editor built with Cocoa, Scintilla and Lexilla.\n\n"
	                    @"Macpad++ is free software: you can redistribute it and/or modify it under the terms of the "
	                    @"GNU General Public License as published by the Free Software Foundation, either version 3 "
	                    @"of the License, or (at your option) any later version.\n\n"
	                    @"Scintilla & Lexilla © Neil Hodgson. Boost.Regex © Boost authors. uchardet © Mozilla.";
	NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
	ps.alignment = NSTextAlignmentCenter;
	NSAttributedString *c = [[NSAttributedString alloc] initWithString:credits attributes:@{
		NSFontAttributeName: [NSFont systemFontOfSize:11],
		NSForegroundColorAttributeName: NSColor.labelColor,
		NSParagraphStyleAttributeName: ps}];
	[NSApp orderFrontStandardAboutPanelWithOptions:@{
		NSAboutPanelOptionApplicationName: @"Macpad++",
		NSAboutPanelOptionApplicationVersion: [NSString stringWithFormat:@"v%@ (macOS)", versionString()],
		NSAboutPanelOptionCredits: c,
	}];
}

void MppShowCommandLineHelp(void)
{
	NSString *t =
	    @"Usage:\n\n"
	    @"open -a Macpad++ [file1 file2 ...]\n"
	    @"Macpad++.app/Contents/MacOS/Macpad++ [options] [file1 file2 ...]\n\n"
	    @"Options:\n"
	    @"  -n<line>       Scroll to the given line number in the opened file\n"
	    @"  -c<column>     Scroll to the given column\n"
	    @"  -l<language>   Set the language of the opened file (e.g. -lpython)\n"
	    @"  -multiInst     Kept for compatibility; Macpad++ for macOS runs as a single instance\n"
	    @"  -nosession     Do not restore the previous session\n"
	    @"  -ro            Open files read-only\n"
	    @"  -settingsDir=<dir>  Keep session, backups and user files in <dir> instead of\n"
	    @"                 ~/Library/Application Support/Macpad++\n";
	MppShowTextResult(@"Command Line Arguments", t);
}

void MppShowDebugInfo(void)
{
	struct utsname u;
	uname(&u);
	NSMutableString *s = [NSMutableString string];
	[s appendFormat:@"Macpad++ v%@ (macOS native)\n", versionString()];
	[s appendFormat:@"Build time: %s - %s\n", __DATE__, __TIME__];
	[s appendFormat:@"Path: %@\n", NSBundle.mainBundle.bundlePath];
	[s appendFormat:@"Settings folder: %@\n", MppPaths.userDataDirectory];
	[s appendFormat:@"OS: %@ (%s)\n", NSProcessInfo.processInfo.operatingSystemVersionString, u.machine];
	[s appendFormat:@"Theme: %@\n", [MppLanguages.shared currentThemeName]];
	[s appendFormat:@"Editor font: %@ %ld\n", [MppPrefs shared].macFontName, (long)[MppPrefs shared].macFontSize];
	[s appendString:@"Scintilla: 5.x (Cocoa), Lexilla 5.x, Boost.Regex (bundled)\n"];
	MppShowTextResult(@"Debug Info", s);
}

// ---- Run --------------------------------------------------------------------------------------

static NSString *const kRunCommands = @"runCommands";
static NSString *const kRunHistory = @"runHistory";

NSArray<NSDictionary *> *MppSavedRunCommands(void)
{
	return [MppDefaults() arrayForKey:kRunCommands] ?: @[];
}

static NSString *expandVariables(MppMainWindowController *o, NSString *cmd)
{
	MppDocument *d = o.currentDocument;
	NSString *path = d.filePath ?: @"";
	std::string word = [o currentWordOrSelection];
	const sptr_t pos = [o sci:SCI_GETCURRENTPOS];
	NSDictionary *vars = @{
		@"$(FULL_CURRENT_PATH)": path,
		@"$(CURRENT_DIRECTORY)": path.stringByDeletingLastPathComponent ?: @"",
		@"$(FILE_NAME)": d.displayName ?: @"",
		@"$(NAME_PART)": d.displayName.stringByDeletingPathExtension ?: @"",
		@"$(EXT_PART)": d.displayName.pathExtension.length ? [@"." stringByAppendingString:d.displayName.pathExtension] : @"",
		@"$(CURRENT_WORD)": [[NSString alloc] initWithBytes:word.data() length:word.size() encoding:NSUTF8StringEncoding] ?: @"",
		@"$(CURRENT_LINE)": [NSString stringWithFormat:@"%ld", (long)[o sci:SCI_LINEFROMPOSITION w:(uptr_t)pos] + 1],
		@"$(CURRENT_COLUMN)": [NSString stringWithFormat:@"%ld", (long)[o sci:SCI_GETCOLUMN w:(uptr_t)pos] + 1],
		@"$(MPP_DIRECTORY)": NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent,
		@"$(MPP_FULL_FILE_PATH)": NSBundle.mainBundle.executablePath,
		@"$(SETTINGS_DIR)": MppPaths.userDataDirectory,
	};
	NSMutableString *s = [cmd mutableCopy];
	for (NSString *k in vars)
		[s replaceOccurrencesOfString:k withString:vars[k] options:0 range:NSMakeRange(0, s.length)];
	// $(SYS.VAR) environment variables
	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\$\\(SYS\\.([A-Za-z0-9_]+)\\)" options:0 error:nil];
	NSArray *matches = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
	for (NSTextCheckingResult *m in matches.reverseObjectEnumerator) {
		NSString *name = [s substringWithRange:[m rangeAtIndex:1]];
		[s replaceCharactersInRange:m.range withString:NSProcessInfo.processInfo.environment[name] ?: @""];
	}
	return s;
}

void MppRunCommandLine(MppMainWindowController *o, NSString *command)
{
	NSString *expanded = expandVariables(o, command);
	NSTask *task = [[NSTask alloc] init];
	task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
	task.arguments = @[@"-c", expanded];
	if (o.currentDocument.filePath)
		task.currentDirectoryURL = [NSURL fileURLWithPath:o.currentDocument.filePath.stringByDeletingLastPathComponent];
	NSError *err = nil;
	if (![task launchAndReturnError:&err]) {
		[[NSAlert alertWithError:err] runModal];
		return;
	}
	[o setStatusMessage:[NSString stringWithFormat:@"Run: %@", expanded]];
}

void MppShowRunDialog(MppMainWindowController *o)
{
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Run…";
	a.informativeText = @"The program to run (shell command). Variables: $(FULL_CURRENT_PATH), $(CURRENT_DIRECTORY), "
	                    @"$(FILE_NAME), $(NAME_PART), $(EXT_PART), $(CURRENT_WORD), $(CURRENT_LINE), $(CURRENT_COLUMN), $(SYS.VAR)";
	[a addButtonWithTitle:@"Run"];
	[a addButtonWithTitle:@"Save…"];
	[a addButtonWithTitle:@"Cancel"];
	NSComboBox *combo = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 440, 26)];
	NSArray *hist = [MppDefaults() stringArrayForKey:kRunHistory] ?: @[@"open \"$(FULL_CURRENT_PATH)\""];
	[combo addItemsWithObjectValues:hist];
	combo.stringValue = hist.firstObject ?: @"";
	a.accessoryView = combo;
	[a layout];
	[a.window makeFirstResponder:combo];
	NSModalResponse r = [a runModal];
	NSString *cmd = combo.stringValue;
	if (r == NSAlertThirdButtonReturn || !cmd.length)
		return;
	NSMutableArray *h = [hist mutableCopy];
	[h removeObject:cmd];
	[h insertObject:cmd atIndex:0];
	while (h.count > 20)
		[h removeLastObject];
	[MppDefaults() setObject:h forKey:kRunHistory];
	if (r == NSAlertSecondButtonReturn) {
		NSString *name = MppAskString(@"Save Command", @"Name (shown in the Run menu):", @"");
		if (name.length) {
			NSMutableArray *cmds = [MppSavedRunCommands() mutableCopy];
			[cmds addObject:@{@"name": name, @"command": cmd}];
			[MppDefaults() setObject:cmds forKey:kRunCommands];
		}
		return;
	}
	MppRunCommandLine(o, cmd);
}

// Generic list manager (rename / delete) used for saved macros and run commands
@interface MppListManager : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *names;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, copy) void (^onDelete)(NSInteger index);
@property (nonatomic, copy) void (^onRename)(NSInteger index, NSString *name);
@end

@implementation MppListManager
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_names.count; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row { return _names[(NSUInteger)row]; }
- (void)tableView:(NSTableView *)tv setObjectValue:(id)obj forTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
	NSString *n = [obj description];
	if (!n.length)
		return;
	_names[(NSUInteger)row] = n;
	if (_onRename)
		_onRename(row, n);
}
- (void)deleteSelected:(id)sender
{
	NSInteger row = _table.selectedRow;
	if (row < 0)
		return;
	[_names removeObjectAtIndex:(NSUInteger)row];
	if (_onDelete)
		_onDelete(row);
	[_table reloadData];
}
@end

static void showListManager(NSString *title, NSArray<NSString *> *names, void (^del)(NSInteger), void (^ren)(NSInteger, NSString *))
{
	MppListManager *m = [[MppListManager alloc] init];
	m.names = [names mutableCopy];
	m.onDelete = del;
	m.onRename = ren;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = title;
	a.informativeText = @"Double-click a name to rename it.";
	[a addButtonWithTitle:@"Done"];
	NSTableView *t = [[NSTableView alloc] init];
	NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	c.title = @"Name";
	c.width = 320;
	c.editable = YES;
	[t addTableColumn:c];
	t.dataSource = m;
	t.delegate = m;
	m.table = t;
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 30, 360, 200)];
	sv.documentView = t;
	sv.hasVerticalScroller = YES;
	NSButton *del2 = [NSButton buttonWithTitle:@"Delete" target:m action:@selector(deleteSelected:)];
	del2.frame = NSMakeRect(0, 0, 90, 26);
	NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 232)];
	[box addSubview:sv];
	[box addSubview:del2];
	a.accessoryView = box;
	[a runModal];
}

void MppShowManageRunCommands(MppMainWindowController *o)
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSDictionary *d in MppSavedRunCommands())
		[names addObject:d[@"name"] ?: @""];
	showListManager(@"Saved Commands", names, ^(NSInteger i) {
		NSMutableArray *cmds = [MppSavedRunCommands() mutableCopy];
		if (i < (NSInteger)cmds.count)
			[cmds removeObjectAtIndex:(NSUInteger)i];
		[MppDefaults() setObject:cmds forKey:kRunCommands];
	}, ^(NSInteger i, NSString *name) {
		NSMutableArray *cmds = [MppSavedRunCommands() mutableCopy];
		if (i < (NSInteger)cmds.count) {
			NSMutableDictionary *d = [cmds[(NSUInteger)i] mutableCopy];
			d[@"name"] = name;
			cmds[(NSUInteger)i] = d;
		}
		[MppDefaults() setObject:cmds forKey:kRunCommands];
	});
}

// ---- Macros -------------------------------------------------------------------------------------

void MppShowRunMacroMultiple(MppMainWindowController *o)
{
	MppMacroManager *m = o.macros;
	NSAlert *a = [[NSAlert alloc] init];
	a.messageText = @"Run a Macro Multiple Times";
	[a addButtonWithTitle:@"Run"];
	[a addButtonWithTitle:@"Cancel"];
	NSPopUpButton *which = [[NSPopUpButton alloc] init];
	if (m.hasRecordedMacro)
		[which addItemWithTitle:@"Current recorded macro"];
	for (NSDictionary *d in m.savedMacros)
		[which addItemWithTitle:d[@"name"]];
	MppRadioTarget *t = [[MppRadioTarget alloc] init];
	NSButton *rTimes = radio(@"Run", t, @selector(changed:));
	NSButton *rEnd = radio(@"Run until the end of file", t, @selector(changed:));
	rTimes.state = NSControlStateValueOn;
	t.handler = ^(NSButton *b) {
		rTimes.state = b == rTimes ? NSControlStateValueOn : NSControlStateValueOff;
		rEnd.state = b == rEnd ? NSControlStateValueOn : NSControlStateValueOff;
	};
	NSTextField *times = field(@"1", 60);
	a.accessoryView = fitted(stackV(@[stackH(@[label(@"Macro to run:"), which], 8),
	                                  stackH(@[rTimes, times, label(@"times")], 6), rEnd], 8));
	if ([a runModal] != NSAlertFirstButtonReturn || which.numberOfItems == 0)
		return;
	NSInteger idx = which.indexOfSelectedItem - (m.hasRecordedMacro ? 1 : 0);
	const BOOL untilEnd = rEnd.state == NSControlStateValueOn;
	if (idx >= 0)
		[m playSteps:[m stepsOfSaved:idx] on:o times:MAX(times.integerValue, 1) untilEnd:untilEnd];
	else
		[m playCurrentOn:o times:MAX(times.integerValue, 1) untilEnd:untilEnd];
}

void MppShowManageMacros(MppMainWindowController *o)
{
	MppMacroManager *m = o.macros;
	NSMutableArray *names = [NSMutableArray array];
	for (NSDictionary *d in m.savedMacros)
		[names addObject:d[@"name"] ?: @""];
	showListManager(@"Saved Macros", names, ^(NSInteger i) { [m deleteSaved:i]; },
	                ^(NSInteger i, NSString *name) { [m renameSaved:i to:name]; });
}
