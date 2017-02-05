.PHONY: release

ifndef BUILDDIR
    BUILDDIR := $(shell mktemp -d "$(TMPDIR)/MASShortcut.XXXXXX")
endif

release:
	xcodebuild -scheme MASShortcut -configuration Release -derivedDataPath "$(BUILDDIR)" build
	open "$(BUILDDIR)/Build/Products/Release"

