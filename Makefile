APP_NAME = Deckle
BUNDLE   = dist/$(APP_NAME).app
BINARY   = .build/release/$(APP_NAME)
INSTALL  = /Applications/$(APP_NAME).app

.PHONY: build app run install clean

build:
	swift build -c release

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

clean:
	rm -rf .build build dist
