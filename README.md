# Macpad++

Macpad++ is a clone of Notepad++ for the Mac. It runs natively on Apple silicon (arm64) Macs
with macOS 11 Big Sur or later. No emulation, Wine or Rosetta is involved.

It is built from Scintilla's Cocoa backend, all of Lexilla
(including the `user`, `searchResult` and `objc` lexers), a Boost.Regex search engine and
uchardet, plus an Objective-C++/AppKit front end in `src/`.

This project is self-contained and has no external dependencies.

## Allowing Macpad++ to run (macOS 15 Sequoia and later)

Macpad++ is not signed with an Apple Developer ID and not notarized by Apple. A copy you built
and installed on the same Mac starts normally. A copy that reached the Mac by download, AirDrop,
e-mail, a USB drive or a cloud drive is blocked by Gatekeeper on its first launch. Allow it once:

1. Copy `Macpad++.app` into the *Applications* folder and double-click it. macOS shows
   *"Macpad++" Not Opened*. Click **Done**.
2. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
   It shows *"Macpad++" was blocked to protect your Mac.* Click **Open Anyway**.
3. Confirm with your password or Touch ID, then click **Open Anyway** in the dialog that follows.

Macpad++ now starts, and it opens normally from then on. The **Open Anyway** button stays
available for about an hour after the blocked launch. If it is missing, double-click the app
again and go back to step 2.

Alternatively, remove the download marker in Terminal (this has the same effect):

    xattr -dr com.apple.quarantine /Applications/Macpad++.app

## Layout

    src/                    the macOS application (Objective-C++ / AppKit)
    shim/                   minimal windows.h stand-in needed to compile Lexilla's LexUser.cxx
    resources/Info.plist    bundle metadata
    tools/make_icon.sh      builds AppIcon.icns from data/icons/Macpad++_logo.jpeg (via make_icon.swift)
    data/                   langs/stylers models, themes,
                            APIs, functionList, preinstalled user defined languages, logo
    third_party/scintilla   Scintilla (include, src, cocoa)
    third_party/lexilla     Lexilla (include, lexlib, lexers, src/Lexilla.cxx)
    third_party/boostregex  Boost.Regex search engine for Scintilla
    third_party/uchardet    encoding detection
    third_party/markers/rgba_icons.h   margin marker icons

## Build

    make            # -> build/Macpad++.app
    make run        # build and launch
    make universal  # arm64 + x86_64
    make dmg        # disk image
    make selftest   # build a test copy and run the built-in self test (see below)

Run these commands in the project's root folder (the one containing the `Makefile`).
Requires Xcode command line tools (clang). No other dependencies.

## Where to find the built application

| Command          | Result                                     |
|------------------|--------------------------------------------|
| `make`           | `build/Macpad++.app` (for the architecture of the Mac it is built on; arm64 on Apple silicon) |
| `make universal` | `build-universal/Macpad++.app` (Apple silicon and Intel) |
| `make dmg`       | `build/Macpad++.dmg` (disk image of `build/Macpad++.app`) |

To install, drag `Macpad++.app` into the *Applications* folder (or copy it with
`cp -R build/Macpad++.app /Applications/`). The app is self-contained, so the project folder is
not needed afterwards. Your settings and files are stored outside the app (see *Data files*) and
survive replacing it with a newer build.

## Data files
In `data/`: `langs.model.xml`, `stylers.model.xml`, all `themes/`, `APIs/` (auto-completion),
`functionList/` (Function List parsers), user-defined-language XML files.

Your own files live in `~/Library/Application Support/Macpad++`: themes, userDefineLangs,
functionList and APIs overrides, edited `langs.xml`/`stylers.xml`, the session (`session.plist`),
backups (`backup/`) and macros (`macros.plist`). Preferences are stored by macOS in
`~/Library/Preferences/org.macpad-plus-plus.macos.plist`. The preinstalled Markdown user defined
languages ship with the app; the light or dark variant is picked to match the theme.

User defined languages are created and edited in *Language > User Defined Language > Define your
language…*. Changes apply to open documents immediately and are saved in the UDL 2.1
format. UDL, theme and API files with any XML root element are read.

## Command line

    Macpad++.app/Contents/MacOS/Macpad++ [options] [files]

    -n<line> -c<column>   go to a line / column
    -l<language>          set the language (e.g. -lpython)
    -ro                   open read-only
    -nosession            do not restore the previous session
    -settingsDir=<dir>    keep session, backups and user files in <dir> (preferences are kept
                          in a separate defaults domain for that directory)

## Self test
`make selftest` builds a separate copy (`build-selftest/`, compiled with `-DMPP_SELFTEST`) and
runs it with a throw-away settings directory. It drives Mark, incremental search, the column
editor, Find Characters in Range, hashes, Run, printing (to PDF), scroll bar layout, user defined
languages and the language editor inside the app, without keyboard input, and prints PASS/FAIL per check. The
regular build contains none of this code.

## Not ported
Windows plugins (DLLs) and localization files.

## License
Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>

GPL v3 (see `LICENSE`). The bundled libraries keep their own licenses: Scintilla and Lexilla
(`third_party/scintilla/License.txt`, `third_party/lexilla/License.txt`), Boost (Boost Software
License, stated in the headers under `third_party/boostregex/boost`) and uchardet (MPL 1.1 /
GPL 2.0 / LGPL 2.1, stated in the headers under `third_party/uchardet`).
