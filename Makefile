APP_NAME = Deckle
BUNDLE   = dist/$(APP_NAME).app
INSTALL  = /Applications/$(APP_NAME).app
VERSION  = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)

# UNIVERSAL=1 builds a fat arm64+x86_64 binary (used by release CI).
ifdef UNIVERSAL
SWIFT_FLAGS = --arch arm64 --arch x86_64
BINARY      = .build/apple/Products/Release/$(APP_NAME)
else
SWIFT_FLAGS =
BINARY      = .build/release/$(APP_NAME)
endif

.PHONY: build app run install dmg clean

build:
	swift build -c release $(SWIFT_FLAGS)

build/AppIcon.icns: scripts/GenerateIcon.swift
	mkdir -p build
	swift scripts/GenerateIcon.swift build

app: build build/AppIcon.icns
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	cp Support/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp build/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(BUNDLE)
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

install: app
	-killall $(APP_NAME) 2>/dev/null
	rm -rf $(INSTALL)
	cp -R $(BUNDLE) $(INSTALL)
	touch $(INSTALL)
	open $(INSTALL)
	@echo "Installed and launched $(INSTALL)"

dmg: app
	rm -rf dist/dmg dist/$(APP_NAME)-$(VERSION).dmg
	mkdir -p dist/dmg
	cp -R $(BUNDLE) dist/dmg/
	ln -s /Applications dist/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder dist/dmg -ov -format UDZO dist/$(APP_NAME)-$(VERSION).dmg
	rm -rf dist/dmg
	@echo "Built dist/$(APP_NAME)-$(VERSION).dmg"

clean:
	rm -rf .build build dist
