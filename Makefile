BINARY   := remind
SOURCES  := $(wildcard Sources/*.swift)
PLIST    := Info.plist
BUILDDIR := .build
PREFIX   ?= $(HOME)/.local

SWIFTFLAGS := -O -parse-as-library -framework EventKit \
              -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST)

# --- macOS app -------------------------------------------------------------
APP        := Remind
APPDIR     := $(BUILDDIR)/$(APP).app
APPBIN     := $(APPDIR)/Contents/MacOS/$(APP)
APPPLIST   := App/Info.plist
APPSOURCES := $(wildcard App/*.swift) Sources/Store.swift Sources/DateParse.swift
APPSOURCES := $(filter-out App/mkicon.swift,$(APPSOURCES))
FONTS      := $(wildcard App/Fonts/*.ttf)
ICONSET    := $(BUILDDIR)/AppIcon.iconset
ICNS       := $(BUILDDIR)/AppIcon.icns
ARCH       := $(shell uname -m)
APPFLAGS   := -O -parse-as-library -target $(ARCH)-apple-macosx14.0 \
              -framework SwiftUI -framework AppKit -framework EventKit \
              -framework UserNotifications -framework ServiceManagement
APPINSTALL ?= $(HOME)/Applications

.PHONY: all build install uninstall clean run auth app run-app install-app uninstall-app icon

all: build

build: $(BUILDDIR)/$(BINARY)

# EventKit refuses to run without a usage description, so the Info.plist is
# linked into the binary. TCC keys on the code signature, so we ad-hoc sign
# every build to keep a granted permission from resetting.
$(BUILDDIR)/$(BINARY): $(SOURCES) $(PLIST)
	@mkdir -p $(BUILDDIR)
	swiftc $(SWIFTFLAGS) $(SOURCES) -o $@
	@codesign --sign - --force --preserve-metadata=entitlements $@ 2>/dev/null || codesign --sign - --force $@

install: build
	@mkdir -p $(PREFIX)/bin
	install -m 0755 $(BUILDDIR)/$(BINARY) $(PREFIX)/bin/$(BINARY)
	@echo "installed $(PREFIX)/bin/$(BINARY)"
	@echo "run '$(BINARY) auth' in your terminal to grant Reminders access"

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

auth: build
	$(BUILDDIR)/$(BINARY) auth

run: build
	$(BUILDDIR)/$(BINARY) $(ARGS)

# --- app targets -----------------------------------------------------------

app: $(APPBIN)

icon: $(ICNS)

$(ICNS): App/mkicon.swift
	@mkdir -p $(BUILDDIR)
	rm -rf $(ICONSET)
	swift App/mkicon.swift $(ICONSET)
	iconutil --convert icns --output $@ $(ICONSET)

# UserNotifications and TCC both need a real .app bundle with a bundle id, so
# the binary is wrapped and ad-hoc signed as a bundle.
# Fonts go in Resources/Fonts; Info.plist's ATSApplicationFontsPath registers
# them for the app at launch.
$(APPBIN): $(APPSOURCES) $(APPPLIST) $(ICNS) $(FONTS)
	@mkdir -p $(APPDIR)/Contents/MacOS $(APPDIR)/Contents/Resources/Fonts
	swiftc $(APPFLAGS) $(APPSOURCES) -o $@
	cp $(APPPLIST) $(APPDIR)/Contents/Info.plist
	cp $(ICNS) $(APPDIR)/Contents/Resources/AppIcon.icns
	cp $(FONTS) $(APPDIR)/Contents/Resources/Fonts/
	printf 'APPL????' > $(APPDIR)/Contents/PkgInfo
	codesign --sign - --force --deep $(APPDIR)
	@echo "built $(APPDIR)"

run-app: app
	-pkill -x $(APP) 2>/dev/null; sleep 0.5
	open $(APPDIR)

install-app: app
	@mkdir -p $(APPINSTALL)
	rm -rf $(APPINSTALL)/$(APP).app
	cp -R $(APPDIR) $(APPINSTALL)/$(APP).app
	@echo "installed $(APPINSTALL)/$(APP).app"

uninstall-app:
	rm -rf $(APPINSTALL)/$(APP).app

clean:
	rm -rf $(BUILDDIR)
