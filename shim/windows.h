// Minimal <windows.h> stand-in for building LexUser.cxx on macOS.
// Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
// LexUser.cxx only needs _itoa from the Win32 CRT.
#pragma once

#include <cstdio>

inline char *_itoa(int value, char *buffer, int radix)
{
	if (radix == 16)
		std::snprintf(buffer, 16, "%x", value);
	else
		std::snprintf(buffer, 16, "%d", value);
	return buffer;
}
