APP_NAME = ClaudeUsageBar
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: all clean install

all: $(APP_BUNDLE)

$(APP_BUNDLE): $(BINARY) Info.plist AppIcon.icns
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp AppIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@echo "Built $(APP_BUNDLE)"

$(BINARY): Sources/main.swift
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@swiftc -O -o $@ $< -framework Cocoa -framework ServiceManagement

install: $(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
