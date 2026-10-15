// Macpad++ for macOS - application entry point
// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import <Cocoa/Cocoa.h>
#import "MppMainWindowController.h"
#import "MppLanguages.h"
#import "MppPaths.h"
#import "MppPrefs.h"
#import "MppMenu.h"
#import "MppSelfTest.h"
#include "Scintilla.h"

@interface MppAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation MppAppDelegate {
	MppMainWindowController *_main;
	NSMutableArray<NSString *> *_pendingFiles;
	BOOL _launched;
	sptr_t _cmdLine, _cmdColumn;
	NSString *_cmdLang;
	BOOL _cmdReadOnly, _noSession;
	NSString *_selfTestLog;
}

- (void)parseCommandLine
{
	_cmdLine = -1;
	_cmdColumn = -1;
	NSArray *args = NSProcessInfo.processInfo.arguments;
	for (NSUInteger i = 1; i < args.count; ++i) {
		NSString *a = args[i];
		if ([a hasPrefix:@"-psn_"] || [a isEqualToString:@"-NSDocumentRevisionsDebugMode"]) {
			++i;   // skip value
			continue;
		}
		if ([a hasPrefix:@"-n"] && a.length > 2 && isdigit([a characterAtIndex:2]))
			_cmdLine = [a substringFromIndex:2].integerValue;
		else if ([a hasPrefix:@"-c"] && a.length > 2 && isdigit([a characterAtIndex:2]))
			_cmdColumn = [a substringFromIndex:2].integerValue;
		else if ([a hasPrefix:@"-l"] && a.length > 2)
			_cmdLang = [a substringFromIndex:2];
		else if ([a isEqualToString:@"-ro"])
			_cmdReadOnly = YES;
		else if ([a isEqualToString:@"-nosession"])
			_noSession = YES;
#ifdef MPP_SELFTEST
		else if ([a hasPrefix:@"-selftest="])
			_selfTestLog = [a substringFromIndex:10];
#endif
		else if ([a hasPrefix:@"-settingsDir="] && a.length > 13)
			[MppPaths setUserDataDirectory:[a substringFromIndex:13]];
		else if ([a hasPrefix:@"-"])
			continue;
		else {
			NSString *path = a;
			if (!path.isAbsolutePath)
				path = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent:path];
			[_pendingFiles addObject:path.stringByStandardizingPath];
		}
	}
}

- (void)applicationWillFinishLaunching:(NSNotification *)n
{
	_pendingFiles = [NSMutableArray array];
	[self parseCommandLine];
	[MppPrefs shared];
	[MppLanguages.shared loadFromDirectory:MppPaths.resourceDirectory];
	_main = [[MppMainWindowController alloc] init];
	NSApp.mainMenu = [MppMenu buildMainMenuWithDelegate:_main];
}

- (void)applyCommandLineToDocument:(MppDocument *)doc
{
	if (!doc)
		return;
	if (_cmdLang.length) {
		for (int i = 0; i < L_EXTERNAL; ++i)
			if ([_cmdLang caseInsensitiveCompare:@(g_mppLangNameInfo[i].langName)] == NSOrderedSame)
				[_main setLanguage:(MppLangType)i forDocument:doc];
	}
	if (_cmdReadOnly) {
		doc.userReadOnly = YES;
		[_main documentDisplayChanged:doc];
	}
	if (_cmdLine > 0) {
		const sptr_t line = _cmdLine - 1;
		[_main gotoLine:line];
		if (_cmdColumn > 0) {
			const sptr_t pos = [_main sci:SCI_FINDCOLUMN w:(uptr_t)line l:_cmdColumn - 1];
			[_main sci:SCI_GOTOPOS w:(uptr_t)pos];
		}
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
	if (!_noSession)
		[_main restoreSession];
	else
		[_main restoreSessionWithoutFiles];
	[_main showWindow:nil];
	[_main.window makeKeyAndOrderFront:nil];
	_launched = YES;
	if (_pendingFiles.count) {
		[_main openPaths:_pendingFiles];
		[self applyCommandLineToDocument:_main.currentDocument];
		[_pendingFiles removeAllObjects];
	}
#ifdef MPP_SELFTEST
	if (_selfTestLog) {
		// Runs in the background without taking the focus, then quits without touching any session
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
			MppRunSelfTest(self->_main, self->_selfTestLog);
			exit(0);
		});
		return;
	}
#endif
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls
{
	NSMutableArray *paths = [NSMutableArray array];
	for (NSURL *u in urls)
		if (u.isFileURL)
			[paths addObject:u.path];
	if (_launched)
		[_main openPaths:paths];
	else
		[_pendingFiles addObjectsFromArray:paths];
	[_main.window makeKeyAndOrderFront:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	return [_main prepareToQuit] ? NSTerminateNow : NSTerminateCancel;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag
{
	[_main.window makeKeyAndOrderFront:nil];
	return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app
{
	return YES;
}

// The app delegate is the last responder: route menu commands to the main window even when
// another window (Preferences, Find panel...) is key or the main window is not main yet
- (void)mppCommand:(id)sender
{
	[_main mppCommand:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	if (item.action == @selector(mppCommand:))
		return [_main validateMenuItem:item];
	return YES;
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
	NSMenu *m = [[NSMenu alloc] init];
	[m addItem:[MppMenu itemWithTitle:@"New Document" command:CMD_FILE_NEW key:@"" modifiers:0]];
	[m addItem:[MppMenu itemWithTitle:@"Open…" command:CMD_FILE_OPEN key:@"" modifiers:0]];
	for (NSMenuItem *it in m.itemArray)
		it.target = _main;
	return m;
}

@end

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSApplication *app = NSApplication.sharedApplication;
		static MppAppDelegate *delegate;
		delegate = [[MppAppDelegate alloc] init];
		app.delegate = delegate;
		app.activationPolicy = NSApplicationActivationPolicyRegular;
		[app run];
	}
	return 0;
}
