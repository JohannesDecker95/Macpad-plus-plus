// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, MppStatusField) {
	MppStatusDocType = 0,
	MppStatusDocSize,
	MppStatusCursorPos,
	MppStatusEOL,
	MppStatusEncoding,
	MppStatusTypingMode,
	MppStatusFieldCount
};

// Status bar: doc type | length/lines | Ln/Col/Pos | EOL | encoding | INS/OVR
@interface MppStatusBar : NSView
@property (nonatomic, copy) NSMenu *(^menuProvider)(MppStatusField field);
- (void)setText:(NSString *)text forField:(MppStatusField)field;
@end
