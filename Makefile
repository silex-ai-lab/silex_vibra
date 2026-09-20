# vibra - SwiftPM-only build. Deliberately no .xcodeproj: this must build on a
# machine with Command Line Tools and no Xcode installed.

APP_NAME    := Vibra
BUNDLE_ID   := ai.silexlab.vibra
VERSION     := 0.1.0
CONFIG      := release
BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
BIN_SRC     := .build/$(CONFIG)/VibraApp

.PHONY: all build app run test clean fmt install uninstall probe restart

all: app

# --product VibraApp deliberately: a release build of the whole package would
# also try to compile the test target, whose `@testable import` requires
# -enable-testing and fails outside a debug build.
build:
	swift build -c $(CONFIG) --product VibraApp

# NOT `swift test`. On a machine without Xcode, SwiftPM builds the suite as an
# .xctest bundle it cannot execute: it prints "Build complete!", runs ZERO
# tests, and exits 0. A silent false green is worse than no tests, so the suite
# is an executable (see Sources/VibraTests/main.swift) and this target also
# asserts that a non-zero number of tests actually ran.
test:
	@mkdir -p $(BUILD_DIR); \
	  set -o pipefail; swift run VibraTests 2>&1 | tee $(BUILD_DIR)/test.log; \
	  status=$$?; \
	  if [ $$status -ne 0 ]; then echo "FAIL: test run exited $$status"; exit $$status; fi; \
	  if ! grep -qE 'Test run with [1-9][0-9]* tests' $(BUILD_DIR)/test.log; then \
	    echo "FAIL: no tests executed - refusing to report green"; exit 1; fi; \
	  if ! grep -q 'canaryTokenNeverLeaks' $(BUILD_DIR)/test.log; then \
	    echo "FAIL: security canary test did not run"; exit 1; fi; \
	  echo "OK: tests executed, canary present"

# Assemble a real .app by hand. LSUIElement=true keeps it out of the Dock and
# the app switcher - the status item is the whole UI.
app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(BUILD_DIR) $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BIN_SRC) $(CONTENTS)/MacOS/$(APP_NAME)
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleName</key><string>$(APP_NAME)</string>' \
	  '  <key>CFBundleDisplayName</key><string>$(APP_NAME)</string>' \
	  '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' \
	  '  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleShortVersionString</key><string>$(VERSION)</string>' \
	  '  <key>CFBundleVersion</key><string>$(VERSION)</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>14.0</string>' \
	  '  <key>LSUIElement</key><true/>' \
	  '  <key>NSHumanReadableCopyright</key><string>MIT</string>' \
	  '</dict></plist>' > $(CONTENTS)/Info.plist
	# Ad-hoc sign so the bundle has a stable identity. This is NOT a substitute
	# for Developer ID signing + notarization when distributing downloads.
	codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || \
	  echo "warning: ad-hoc codesign failed; notifications may not be delivered"
	@echo "built $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

# Run every adapter once and print a summary, then exit. Prints counts,
# project names and states - never message content.
probe: build
	@$(BIN_SRC) --probe

# Copy into /Applications so it survives `make clean` and behaves like a
# normal installed app. Quits any running copy first, otherwise the old
# binary keeps running against the new bundle.
install: app
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "installed /Applications/$(APP_NAME).app"
	@echo "launch it with: open -a $(APP_NAME)"

uninstall:
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@echo "removed /Applications/$(APP_NAME).app"

# Rebuild and relaunch the running copy - the usual edit/see-it loop.
restart: app
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	@open $(APP_BUNDLE)
	@echo "relaunched $(APP_NAME)"

clean:
	rm -rf .build $(BUILD_DIR)
