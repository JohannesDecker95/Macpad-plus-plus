// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppMacro.h"
#import "MppMainWindowController.h"
#import "MppFindReplace.h"
#import "MppCommands.h"
#import "MppPaths.h"
#include "Scintilla.h"

@implementation MppMacroManager {
	NSMutableArray<NSDictionary *> *_current;
	NSMutableArray<NSDictionary *> *_recording;
	NSMutableArray<NSDictionary *> *_saved;
	BOOL _isRecording;
	BOOL _playing;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_current = [NSMutableArray array];
		NSArray *saved = [NSArray arrayWithContentsOfFile:[self savedPath]];
		_saved = saved ? [saved mutableCopy] : [NSMutableArray array];
	}
	return self;
}

- (NSString *)savedPath
{
	return [MppPaths.userDataDirectory stringByAppendingPathComponent:@"macros.plist"];
}

- (void)persist
{
	[_saved writeToFile:[self savedPath] atomically:YES];
}

- (BOOL)recording
{
	return _isRecording;
}

- (BOOL)hasRecordedMacro
{
	return _current.count > 0;
}

- (NSArray<NSDictionary *> *)savedMacros
{
	return _saved;
}

- (void)startRecording:(ScintillaView *)view
{
	if (_isRecording)
		return;
	_recording = [NSMutableArray array];
	_isRecording = YES;
	[view message:SCI_STARTRECORD];
	// record in every editor view so that switching views keeps recording
	MppMainWindowController *o = MppMainWindowController.shared;
	[o.mainPane sci:SCI_STARTRECORD];
	[o.subPane sci:SCI_STARTRECORD];
}

- (void)stopRecording:(ScintillaView *)view
{
	if (!_isRecording)
		return;
	MppMainWindowController *o = MppMainWindowController.shared;
	[o.mainPane sci:SCI_STOPRECORD];
	[o.subPane sci:SCI_STOPRECORD];
	_isRecording = NO;
	if (_recording.count)
		_current = _recording;
	_recording = nil;
}

static BOOL isStringMessage(unsigned int msg)
{
	return msg == SCI_REPLACESEL || msg == SCI_SEARCHNEXT || msg == SCI_SEARCHPREV || msg == SCI_INSERTTEXT ||
	       msg == SCI_ADDTEXT || msg == SCI_APPENDTEXT;
}

- (void)recordNotification:(SCNotification *)n
{
	if (!_isRecording || _playing)
		return;
	NSMutableDictionary *step = [@{@"type": @"sci", @"msg": @(n->message), @"w": @(n->wParam)} mutableCopy];
	if (isStringMessage(n->message) && n->lParam) {
		const char *s = (const char *)n->lParam;
		NSData *d;
		if (n->message == SCI_ADDTEXT || n->message == SCI_APPENDTEXT)
			d = [NSData dataWithBytes:s length:n->wParam];
		else
			d = [NSData dataWithBytes:s length:strlen(s)];
		step[@"s"] = d;
	} else {
		step[@"l"] = @(n->lParam);
	}
	[_recording addObject:step];
}

- (void)recordCommand:(int)cmd
{
	if (!_isRecording || _playing)
		return;
	[_recording addObject:@{@"type": @"cmd", @"cmd": @(cmd)}];
}

- (void)recordFind:(NSDictionary *)findStep
{
	if (!_isRecording || _playing)
		return;
	NSMutableDictionary *d = [findStep mutableCopy];
	d[@"type"] = @"find";
	[_recording addObject:d];
}

+ (BOOL)isRecordableCommand:(int)cmd
{
	if (cmd >= CMD_EDIT_UNDO && cmd <= CMD_EDIT_COPY_LINK) {
		switch (cmd) {
			case CMD_EDIT_CHANGESEARCHENGINE: case CMD_EDIT_COLUMNMODETIP: case CMD_EDIT_COLUMNMODE:
			case CMD_EDIT_CHAR_PANEL: case CMD_EDIT_CLIPBOARDHISTORY_PANEL: case CMD_EDIT_OPENSELECTEDFILE:
			case CMD_EDIT_REVEALSELECTEDFILE: case CMD_EDIT_SEARCHONINTERNET: case CMD_EDIT_AUTOCOMPLETE:
			case CMD_EDIT_AUTOCOMPLETE_CURRENTFILE: case CMD_EDIT_FUNCCALLTIP: case CMD_EDIT_AUTOCOMPLETE_PATH:
			case CMD_EDIT_TOGGLEREADONLY: case CMD_EDIT_SETREADONLYFORALLDOCS: case CMD_EDIT_CLEARREADONLYFORALLDOCS:
				return NO;
			default:
				return YES;
		}
	}
	if (cmd >= CMD_SEARCH_MARKALLEXT1 && cmd <= CMD_SEARCH_INVERSEMARKS)
		return YES;
	switch (cmd) {
		case CMD_SEARCH_FINDNEXT: case CMD_SEARCH_FINDPREV: case CMD_SEARCH_SETANDFINDNEXT:
		case CMD_SEARCH_SETANDFINDPREV: case CMD_SEARCH_VOLATILE_FINDNEXT: case CMD_SEARCH_VOLATILE_FINDPREV:
		case CMD_SEARCH_GOTOMATCHINGBRACE: case CMD_SEARCH_SELECTMATCHINGBRACES:
		case CMD_FILE_NEW: case CMD_FILE_SAVE: case CMD_FILE_CLOSE:
		case CMD_VIEW_TAB_NEXT: case CMD_VIEW_TAB_PREV:
			return YES;
		default:
			return NO;
	}
}

- (void)playSteps:(NSArray<NSDictionary *> *)steps on:(MppMainWindowController *)owner
{
	for (NSDictionary *step in steps) {
		NSString *type = step[@"type"];
		if ([type isEqualToString:@"sci"]) {
			const unsigned int msg = [step[@"msg"] unsignedIntValue];
			const uptr_t w = [step[@"w"] unsignedLongValue];
			if (NSData *d = step[@"s"]) {
				std::string s((const char *)d.bytes, d.length);
				[owner sci:msg w:(msg == SCI_ADDTEXT || msg == SCI_APPENDTEXT) ? s.size() : w l:(sptr_t)s.c_str()];
			} else {
				[owner sci:msg w:w l:[step[@"l"] longValue]];
			}
		} else if ([type isEqualToString:@"cmd"]) {
			[owner executeCommand:[step[@"cmd"] intValue]];
		} else if ([type isEqualToString:@"find"]) {
			MppFindOptions o;
			o.matchCase = [step[@"matchCase"] boolValue];
			o.wholeWord = [step[@"wholeWord"] boolValue];
			o.mode = (MppSearchMode)[step[@"mode"] integerValue];
			o.wrapAround = [step[@"wrap"] boolValue];
			o.dotMatchesNewline = [step[@"dotNL"] boolValue];
			NSString *text = step[@"text"];
			NSString *action = step[@"action"];
			if ([action isEqualToString:@"findNext"])
				[owner.findReplace findText:text.UTF8String forward:![step[@"backward"] boolValue] options:o showStatus:NO];
		}
	}
}

- (void)playSteps:(NSArray<NSDictionary *> *)steps on:(MppMainWindowController *)owner times:(NSInteger)times untilEnd:(BOOL)untilEnd
{
	if (!steps.count || _isRecording)
		return;
	_playing = YES;
	[owner sci:SCI_BEGINUNDOACTION];
	if (untilEnd) {
		for (NSInteger i = 0; i < 1000000; ++i) {
			const sptr_t posBefore = [owner sci:SCI_GETCURRENTPOS];
			const sptr_t lenBefore = [owner sci:SCI_GETLENGTH];
			const sptr_t lineBefore = [owner sci:SCI_LINEFROMPOSITION w:(uptr_t)posBefore];
			[self playSteps:steps on:owner];
			const sptr_t posAfter = [owner sci:SCI_GETCURRENTPOS];
			const sptr_t lenAfter = [owner sci:SCI_GETLENGTH];
			if (posAfter >= lenAfter)
				break;
			if (posAfter == posBefore && lenAfter == lenBefore)
				break;
			if ([owner sci:SCI_LINEFROMPOSITION w:(uptr_t)posAfter] < lineBefore)
				break;
		}
	} else {
		for (NSInteger i = 0; i < times; ++i)
			[self playSteps:steps on:owner];
	}
	[owner sci:SCI_ENDUNDOACTION];
	_playing = NO;
}

- (void)playCurrentOn:(MppMainWindowController *)owner times:(NSInteger)times untilEnd:(BOOL)untilEnd
{
	[self playSteps:_current on:owner times:times untilEnd:untilEnd];
}

- (void)playSaved:(NSInteger)index on:(MppMainWindowController *)owner
{
	if (index < 0 || index >= (NSInteger)_saved.count)
		return;
	[self playSteps:_saved[(NSUInteger)index][@"steps"] on:owner times:1 untilEnd:NO];
}

- (BOOL)saveCurrentAs:(NSString *)name
{
	if (!_current.count || !name.length)
		return NO;
	[_saved addObject:@{@"name": name, @"steps": [_current copy]}];
	[self persist];
	return YES;
}

- (void)deleteSaved:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_saved.count)
		return;
	[_saved removeObjectAtIndex:(NSUInteger)index];
	[self persist];
}

- (void)renameSaved:(NSInteger)index to:(NSString *)name
{
	if (index < 0 || index >= (NSInteger)_saved.count || !name.length)
		return;
	NSMutableDictionary *d = [_saved[(NSUInteger)index] mutableCopy];
	d[@"name"] = name;
	_saved[(NSUInteger)index] = d;
	[self persist];
}

- (NSArray *)stepsOfSaved:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)_saved.count)
		return @[];
	return _saved[(NSUInteger)index][@"steps"];
}

- (void)setCurrentSteps:(NSArray *)steps
{
	_current = [steps mutableCopy];
}

@end
