APP_NAME = ClaudeUsageBar
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")

.PHONY: all clean install

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(BINARY) Info.plist AppIcon.icns
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" $(APP_BUNDLE)/Contents/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) ($(VERSION))"

$(BINARY): Sources/main.swift
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@swiftc -O -o $@ $< -framework Cocoa -framework ServiceManagement

install: $(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
