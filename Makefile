APP_NAME = ClaudeUsageBar
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

.PHONY: all clean install

all: $(APP_BUNDLE)

$(APP_BUNDLE): Sources/main.swift Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@swiftc -O -o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) Sources/main.swift \
		-framework Cocoa -framework ServiceManagement
	@cp Info.plist $(APP_BUNDLE)/Contents/
	@echo "Built $(APP_BUNDLE)"

install: $(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
