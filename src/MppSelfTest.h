// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

@class MppMainWindowController;

#ifdef MPP_SELFTEST
// Runs the built-in self test and writes the results to logPath (see MppSelfTest.mm)
void MppRunSelfTest(MppMainWindowController *owner, NSString *logPath);
#endif
