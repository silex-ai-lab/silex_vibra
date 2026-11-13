# Vibra - SwiftPM-only build. Deliberately no .xcodeproj: this must build on a
# machine with Command Line Tools and no Xcode installed.

APP_NAME    := Vibra
BUNDLE_ID   := ai.silexlab.vibra
VERSION := 0.4.2
CONFIG      := release
BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
DMG         := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

# Empty (the default) builds the host arch where SwiftPM puts it.
# ARCHS="arm64 x86_64" builds each arch into its own scratch path and lipos
# them together, for a DMG that runs natively on both.
ARCHS ?=
ifeq ($(strip $(ARCHS)),)
BIN_SRC := .build/$(CONFIG)/VibraApp
else
BIN_SRC := .build/universal/VibraApp
endif

# HARDENED=1 signs for distribution: hardened runtime plus the entitlements
# file. It does not imply an identity - the dry run is hardened and ad hoc.
HARDENED ?=

# --timestamp only under HARDENED with a real identity: ad hoc has no
# timestamp to request and codesign rejects the flag there. Outside HARDENED
# signing behaves exactly as before, for the tap formula's `make app`.
SIGN_IDENTITY_TRIMMED := $(strip $(SIGN_IDENTITY))
SIGN_TIMESTAMP := $(if $(SIGN_IDENTITY_TRIMMED),$(if $(filter -,$(SIGN_IDENTITY_TRIMMED)),,--timestamp),)
DIST_SIGN_FLAGS := $(if $(strip $(HARDENED)),--options runtime --entitlements packaging/Vibra.entitlements $(SIGN_TIMESTAMP),)

.PHONY: all build app dmg run test clean fmt install uninstall probe bench restart query

all: app

# --product VibraApp deliberately: a release build of the whole package would
# also try to compile the test target, whose `@testable import` requires
# -enable-testing and fails outside a debug build.
#
# Per arch: a separate scratch path, because one scratch dir cannot hold two
# targets' modules at once. Each slice's binary is asked for with
# --show-bin-path instead of assumed, since the layout is SwiftPM's.
build:
ifeq ($(strip $(ARCHS)),)
	swift build -c $(CONFIG) --product VibraApp
else
	@set -e; slices=''; \
	  for arch in $(ARCHS); do \
	    triple=$$arch-apple-macosx14.0; \
	    swift build -c $(CONFIG) --product VibraApp --triple $$triple --scratch-path .build/$$arch; \
	    slice=$$(swift build -c $(CONFIG) --product VibraApp --triple $$triple --scratch-path .build/$$arch --show-bin-path)/VibraApp; \
	    slices="$$slices $$slice"; \
	  done; \
	  mkdir -p .build/universal; \
	  lipo -create $$slices -output $(BIN_SRC); \
	  lipo -archs $(BIN_SRC)
endif

# Opt-in SwiftPM build backend for the test run, e.g. `make test
# SWIFT_BUILD_SYSTEM=native`. Unset, `swift run` keeps its default. On Swift
# 6.4 Command Line Tools with no Xcode, the default swiftbuild backend fails to
# load the Swift Testing macro plugin ("plugin for module 'TestingMacros' not
# found"), even on a commit that builds fine with `native`.
SWIFT_BUILD_SYSTEM ?=
TEST_BUILD_FLAGS := $(if $(SWIFT_BUILD_SYSTEM),--build-system $(SWIFT_BUILD_SYSTEM),)

# Each privacy canary is checked by its exact Swift Testing line, so a renamed
# or deleted canary fails the run instead of being matched by a substring.
CANARIES := canaryTokenNeverLeaks perfPrivacySentinelsNeverLeak evidenceSentinelsNeverLeak incidentSentinelsNeverLeak

# NOT `swift test`. On a machine without Xcode, SwiftPM builds the suite as an
# .xctest bundle it cannot execute: it prints "Build complete!", runs ZERO
# tests, and exits 0. A silent false green is worse than no tests, so the suite
# is an executable (see Sources/VibraTests/main.swift) and this target also
# asserts that a non-zero number of tests actually ran.
test:
	@mkdir -p $(BUILD_DIR); \
	  set -o pipefail; swift run $(TEST_BUILD_FLAGS) VibraTests 2>&1 | tee $(BUILD_DIR)/test.log; \
	  status=$$?; \
	  if [ $$status -ne 0 ]; then echo "FAIL: test run exited $$status"; exit $$status; fi; \
	  if ! grep -qE 'Test run with [1-9][0-9]* tests' $(BUILD_DIR)/test.log; then \
	    echo "FAIL: no tests executed - refusing to report green"; exit 1; fi; \
	  for canary in $(CANARIES); do \
	    if ! grep -qF "Test $$canary() passed" $(BUILD_DIR)/test.log; then \
	      echo "FAIL: canary $$canary did not pass"; exit 1; fi; \
	  done; \
	  echo "OK: tests executed, canaries passed: $(CANARIES)"

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
	  '  <key>NSHumanReadableCopyright</key><string>Apache-2.0</string>' \
	  '  <key>NSAppleEventsUsageDescription</key>' \
	  '  <string>Vibra asks your terminal which tab owns a session'"'"'s tty, so clicking a session can focus it.</string>' \
	  '</dict></plist>' > $(CONTENTS)/Info.plist
	# Signing identity. SIGN_IDENTITY unset means ad-hoc, which is what a fresh
	# clone gets and what CI should use.
	#
	# Ad-hoc has no stable identity, so macOS pins every TCC grant to the exact
	# code hash: measured on 2026-09-21, the Automation grant's csreq was
	# literally `fade0c00...` followed by the cdhash. Any rebuild that changes a
	# byte of the binary invalidates it, and reverting the source does NOT
	# restore the old hash -- a release build is not byte-reproducible once the
	# build cache has been disturbed. In practice that means re-approving
	# "Vibra wants to control iTerm" after most rebuilds.
	#
	# Signing with a stable certificate instead makes the designated requirement
	# name that certificate, so the grant survives rebuilds. It does not need an
	# Apple account -- a self-signed code-signing certificate in your login
	# keychain is enough. See "Stable signing for development" in the README.
	#
	#   make install SIGN_IDENTITY="vibra local signing"
	#
	# This is NOT a substitute for Developer ID signing + notarization when
	# distributing downloads.
	#
	# Signing failure is fatal, and its stderr is not hidden. An unsigned or
	# wrongly-signed bundle still launches, so a swallowed error here does not
	# look like a build problem at all -- it looks like notifications and
	# terminal jump-back being mysteriously broken, days later. That is not
	# hypothetical: on 2026-09-21 a `make install SIGN_IDENTITY=...` was denied
	# keychain access, the `2>/dev/null ||` ate it, the build reported success,
	# and the bundle was quietly ad-hoc.
	@codesign --force --deep $(DIST_SIGN_FLAGS) --sign $(if $(SIGN_IDENTITY),"$(SIGN_IDENTITY)",-) $(APP_BUNDLE) || { \
	  echo "error: codesign failed. The bundle would run but could not hold any"; \
	  echo "       permission: no notifications, no terminal jump-back."; \
	  $(if $(SIGN_IDENTITY),echo "       Check that SIGN_IDENTITY=$(SIGN_IDENTITY) names a code-signing"; \
	  echo "       identity: security find-identity -p codesigning";,:;) \
	  exit 1; }
	# Verify what was actually produced, not just that codesign exited 0. Asking
	# for an identity and silently getting ad-hoc is the failure that hides best.
	@if codesign -dvvv $(APP_BUNDLE) 2>&1 | grep -q "Signature=adhoc"; then \
	  if [ -n "$(SIGN_IDENTITY)" ]; then \
	    echo "error: asked to sign with $(SIGN_IDENTITY) but the bundle is ad-hoc."; \
	    echo "       codesign fell back instead of failing. TCC grants would be"; \
	    echo "       pinned to the code hash and lost on the next rebuild."; \
	    exit 1; \
	  fi; \
	  echo "signed ad-hoc (TCC grants will not survive a rebuild; see SIGN_IDENTITY above)"; \
	else \
	  echo "signed with $(SIGN_IDENTITY)"; \
	fi
	@echo "built $(APP_BUNDLE)"

# Packaging only. No prerequisite, so it can never rebuild the bundle under a
# check that already verified it: whatever is on disk is what ships.
dmg:
	@if [ ! -d $(APP_BUNDLE) ]; then \
	  echo "error: $(APP_BUNDLE) is missing."; \
	  echo "       make dmg only packages an existing bundle; run 'make app' first."; \
	  exit 1; \
	fi
	@rm -rf $(BUILD_DIR)/dmg-root $(DMG)
	@mkdir -p $(BUILD_DIR)/dmg-root
	@cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg-root/
	@ln -s /Applications $(BUILD_DIR)/dmg-root/Applications
	@hdiutil create -quiet -volname "$(APP_NAME)" -srcfolder $(BUILD_DIR)/dmg-root -format UDZO -ov $(DMG)
	@rm -rf $(BUILD_DIR)/dmg-root
	@if [ -n "$(SIGN_TIMESTAMP)" ]; then \
	  codesign --force --timestamp --sign "$(SIGN_IDENTITY)" $(DMG) || { \
	    echo "error: codesign failed on $(DMG)"; exit 1; }; \
	  echo "signed $(DMG)"; \
	else \
	  echo "wrote $(DMG) unsigned (SIGN_IDENTITY is not a real identity)"; \
	fi

run: app
	open $(APP_BUNDLE)

# Run every adapter once and print a summary, then exit. Prints counts,
# project names and states - never message content.
probe: build
	@$(BIN_SRC) --probe

# The menu's live sessions as JSON, for scripts and agents. Reads the same
# ai.silexlab.vibra settings as the installed app. Never message content.
query: build
	@$(BIN_SRC) --query

# Phase 0 acceptance check: a refresh where nothing changed must read 0 bytes.
bench: build
	@$(BIN_SRC) --bench

# Copy into /Applications so it survives `make clean` and behaves like a
# normal installed app. Quits any running copy first, otherwise the old
# binary keeps running against the new bundle.
# Removes the build copy once it is installed. Two bundles with the same id
# means LaunchServices picks one, and it does not have to pick the installed
# one -- on 2026-09-21 a permission check was run against the build copy
# without anyone noticing, and read as "the permission does not work". The two
# copies also have different code hashes, so they do not even share TCC grants.
# `make probe` rebuilds in seconds; the ambiguity is not worth it.
install: app
	@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) /Applications/
	@rm -rf $(APP_BUNDLE)
	@echo "installed /Applications/$(APP_NAME).app"
	@echo "launch it by full path, not by name:"
	@echo "  open /Applications/$(APP_NAME).app"

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
