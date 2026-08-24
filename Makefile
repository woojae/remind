BINARY   := remind
SOURCES  := $(wildcard Sources/*.swift)
PLIST    := Info.plist
BUILDDIR := .build
PREFIX   ?= $(HOME)/.local

SWIFTFLAGS := -O -parse-as-library -framework EventKit \
              -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST)

.PHONY: all build install uninstall clean run auth

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

clean:
	rm -rf $(BUILDDIR)
