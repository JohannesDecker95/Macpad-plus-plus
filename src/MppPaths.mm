// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

#import "MppPaths.h"

@implementation MppPaths

+ (NSString *)resourceDirectory
{
	return NSBundle.mainBundle.resourcePath;
}

static NSString *ensureDir(NSString *dir)
{
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return dir;
}

static NSString *s_userDataOverride;

+ (void)setUserDataDirectory:(NSString *)dir
{
	s_userDataOverride = dir.stringByExpandingTildeInPath.stringByStandardizingPath;
}

+ (NSString *)userDataDirectory
{
	if (s_userDataOverride)
		return ensureDir(s_userDataOverride);
	NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	return ensureDir([base stringByAppendingPathComponent:@"Macpad++"]);
}

+ (NSString *)backupDirectory
{
	return ensureDir([self.userDataDirectory stringByAppendingPathComponent:@"backup"]);
}

+ (NSString *)userFileOrBundled:(NSString *)name
{
	NSString *user = [self.userDataDirectory stringByAppendingPathComponent:name];
	if ([NSFileManager.defaultManager fileExistsAtPath:user])
		return user;
	return [self.resourceDirectory stringByAppendingPathComponent:name];
}

@end

NSString *MppDefaultsSuiteName(void)
{
	if (!s_userDataOverride)
		return nil;
	// One defaults domain per settings directory keeps its preferences apart from the normal ones
	return [NSString stringWithFormat:@"%@.settings-%08lx", NSBundle.mainBundle.bundleIdentifier ?: @"org.macpad-plus-plus.macos",
	                                  (unsigned long)(s_userDataOverride.hash & 0xffffffff)];
}

NSUserDefaults *MppDefaults(void)
{
	static NSUserDefaults *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		if (NSString *suite = MppDefaultsSuiteName())
			d = [[NSUserDefaults alloc] initWithSuiteName:suite];
		if (!d)
			d = NSUserDefaults.standardUserDefaults;
	});
	return d;
}
