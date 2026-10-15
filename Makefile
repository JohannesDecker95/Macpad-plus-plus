# Macpad++ for macOS - native Cocoa build
# Copyright (C)2026 Johannes Decker <lohnertspuckjoe@gmail.com>
#
#   make            build build/Macpad++.app (Release)
#   make DEBUG=1    debug build
#   make run        build and launch
#   make universal  build an arm64 + x86_64 binary
#   make dmg        package the app into a disk image
#   make clean

TP        := third_party
SCI       := $(TP)/scintilla
LEX       := $(TP)/lexilla
REGEX     := $(TP)/boostregex
UCD       := $(TP)/uchardet
DATA      := data
BUILD     := build
OBJDIR    := $(BUILD)/obj
APP       := $(BUILD)/Macpad++.app
EXE       := $(APP)/Contents/MacOS/Macpad++
RES       := $(APP)/Contents/Resources

ARCHS     ?= $(shell uname -m)
MIN_MACOS ?= 11.0
ARCHFLAGS := $(foreach a,$(ARCHS),-arch $(a))

CC        := clang
CXX       := clang++

ifeq ($(DEBUG),1)
  OPT := -O0 -g -DDEBUG
else
  OPT := -O2 -DNDEBUG
endif

COMMON    := $(ARCHFLAGS) -mmacosx-version-min=$(MIN_MACOS) $(OPT) -Wall -Wno-unknown-pragmas \
             -Wno-deprecated-declarations
INCLUDES  := -I$(SCI)/include -I$(SCI)/src -I$(SCI)/cocoa -I$(LEX)/include -I$(LEX)/lexlib \
             -I$(REGEX) -Ishim -Isrc -I$(UCD) -I$(TP)/markers
DEFINES   := -DSCI_OWNREGEX -DBOOST_REGEX_STANDALONE $(EXTRA_DEFINES)
CXXFLAGS  := $(COMMON) -std=c++17 $(DEFINES) $(INCLUDES)
OBJCXXFLAGS := $(COMMON) -std=c++17 -fobjc-arc $(DEFINES) $(INCLUDES)

LDFLAGS   := $(ARCHFLAGS) -mmacosx-version-min=$(MIN_MACOS) \
             -framework Cocoa -framework QuartzCore -framework UniformTypeIdentifiers

# ---- sources --------------------------------------------------------------
SCI_SRC   := $(wildcard $(SCI)/src/*.cxx) $(REGEX)/BoostRegExSearch.cxx \
             $(REGEX)/UTF8DocumentIterator.cxx
SCI_MM    := $(SCI)/cocoa/ScintillaCocoa.mm $(SCI)/cocoa/ScintillaView.mm \
             $(SCI)/cocoa/PlatCocoa.mm $(SCI)/cocoa/InfoBar.mm
LEX_SRC   := $(wildcard $(LEX)/lexlib/*.cxx) $(wildcard $(LEX)/lexers/*.cxx) $(LEX)/src/Lexilla.cxx
UCD_SRC   := $(wildcard $(UCD)/*.cpp)
APP_MM    := $(wildcard src/*.mm)
APP_CPP   := $(wildcard src/*.cpp)

obj = $(addprefix $(OBJDIR)/$(1)/,$(addsuffix .o,$(basename $(notdir $(2)))))

SCI_OBJ   := $(call obj,scintilla,$(SCI_SRC)) $(call obj,scintilla,$(SCI_MM))
LEX_OBJ   := $(call obj,lexilla,$(LEX_SRC))
UCD_OBJ   := $(call obj,uchardet,$(UCD_SRC))
APP_OBJ   := $(call obj,app,$(APP_MM)) $(call obj,app,$(APP_CPP))
ALL_OBJ   := $(SCI_OBJ) $(LEX_OBJ) $(UCD_OBJ) $(APP_OBJ)

vpath %.cxx $(SCI)/src $(REGEX) $(LEX)/lexlib $(LEX)/lexers $(LEX)/src
vpath %.mm  $(SCI)/cocoa src
vpath %.cpp $(UCD) src

.PHONY: all app run clean universal dmg resources selftest

all: app

app: $(EXE) resources
	@codesign --force --deep --sign - "$(APP)" >/dev/null 2>&1 || true
	@echo "Built $(APP)"

$(EXE): $(ALL_OBJ)
	@mkdir -p $(dir $@)
	@echo "  LD   $@"
	@$(CXX) $(LDFLAGS) -o $@ $^

$(OBJDIR)/scintilla/%.o: %.cxx
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJDIR)/scintilla/%.o: %.mm
	@mkdir -p $(dir $@)
	@echo "  OBJC $<"
	@$(CXX) $(OBJCXXFLAGS) -c $< -o $@

$(OBJDIR)/lexilla/%.o: %.cxx
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(CXXFLAGS) -Wno-unused -Wno-sign-compare -c $< -o $@

$(OBJDIR)/uchardet/%.o: %.cpp
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(CXXFLAGS) -w -c $< -o $@

$(OBJDIR)/app/%.o: src/%.mm $(wildcard src/*.h)
	@mkdir -p $(dir $@)
	@echo "  OBJC $<"
	@$(CXX) $(OBJCXXFLAGS) -c $< -o $@

$(OBJDIR)/app/%.o: src/%.cpp $(wildcard src/*.h)
	@mkdir -p $(dir $@)
	@echo "  CXX  $<"
	@$(CXX) $(CXXFLAGS) -c $< -o $@

# ---- bundle resources -----------------------------------------------------
resources: $(EXE)
	@mkdir -p "$(RES)/themes" "$(RES)/APIs" "$(RES)/functionList"
	@cp resources/Info.plist "$(APP)/Contents/Info.plist"
	@cp $(DATA)/langs.model.xml "$(RES)/langs.xml"
	@cp $(DATA)/stylers.model.xml "$(RES)/stylers.xml"
	@cp $(DATA)/themes/*.xml "$(RES)/themes/"
	@cp $(DATA)/APIs/*.xml "$(RES)/APIs/"
	@cp $(DATA)/functionList/*.xml "$(RES)/functionList/"
	@mkdir -p "$(RES)/userDefineLangs" && cp $(DATA)/userDefineLangs/*.xml "$(RES)/userDefineLangs/"
	@for img in mac_cursor_busy mac_cursor_flipped info_bar_bg; do \
		tiffutil -cathidpicheck $(SCI)/cocoa/res/$$img.png $(SCI)/cocoa/res/$$img@2x.png -out "$(RES)/$$img.tiff" >/dev/null 2>&1; \
	done
	@if [ ! -f $(BUILD)/AppIcon.icns ]; then ./tools/make_icon.sh "$(DATA)/icons/Macpad++_logo.jpeg" $(BUILD); fi
	@cp $(BUILD)/AppIcon.icns "$(RES)/AppIcon.icns" 2>/dev/null || true
	@cp LICENSE "$(RES)/LICENSE.txt"

run: app
	open "$(APP)"

# Builds a separate copy with the self test compiled in and runs it with a throw-away settings directory
SELFTEST_DIR := $(BUILD)/selftest-data
selftest:
	$(MAKE) BUILD=build-selftest EXTRA_DEFINES=-DMPP_SELFTEST app
	@rm -rf $(SELFTEST_DIR) && mkdir -p $(SELFTEST_DIR) && cp src/MppPaths.h $(SELFTEST_DIR)/launch.h
	@build-selftest/Macpad++.app/Contents/MacOS/Macpad++ -nosession -settingsDir=$(abspath $(SELFTEST_DIR)) \
		-selftest=$(abspath $(SELFTEST_DIR))/selftest.log $(abspath $(SELFTEST_DIR))/launch.h >/dev/null 2>&1; \
	cat $(SELFTEST_DIR)/selftest.log; grep -q "^0 failure" $(SELFTEST_DIR)/selftest.log

universal:
	$(MAKE) ARCHS="arm64 x86_64" BUILD=build-universal

dmg: app
	@rm -f $(BUILD)/Macpad++.dmg
	hdiutil create -volname "Macpad++" -srcfolder "$(APP)" -ov -format UDZO $(BUILD)/Macpad++.dmg

clean:
	rm -rf $(BUILD) build-universal build-selftest
