# FrozioHarness: builds Frozio's sources into a Simulator app (see main.m for why).
#
#   make -C Harness          build build/FrozioHarness.app
#   make -C Harness run      build, boot $(DEVICE) if needed, install, launch on Frozio settings
#   make -C Harness shot     screenshot of the booted Simulator into build/shot.png
#   make -C Harness log      stream Frozio's os_log lines from the Simulator
#
# Needs full Xcode (iPhoneSimulator SDK + simctl). Builds for the host's arch: x86_64 on this Mac.

REPO    := $(abspath ..)
BUILD   := build
APP     := $(BUILD)/FrozioHarness.app
ARCH    ?= $(shell uname -m)
DEVICE  ?= iPhone 17 Pro
SDK     := $(shell xcrun --sdk iphonesimulator --show-sdk-path)
VERSION := $(shell sed -n 's/^PACKAGE_VERSION = //p' $(REPO)/Makefile)

# Every Frozio source except Frozio.m: no constructor, no version gate, no NaviMus hooks.
SOURCES := main.m $(filter-out $(REPO)/Source/Frozio.m,$(shell find $(REPO)/Source -name '*.m'))
HEADERS := $(shell find $(REPO)/Source -name '*.h')
SWIFT   := NaviMusStandIn.swift $(shell find $(REPO)/Source -name '*.swift')

OBJDIR  := $(BUILD)/obj
# swiftc by path: on this Mac `xcrun -f swiftc` dies in xcodebuild (bus error) while the toolchain is fine.
SWIFTC  ?= $(shell xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
TARGET  := $(ARCH)-apple-ios17.0-simulator

CFLAGS := -target $(ARCH)-apple-ios17.0-simulator -isysroot $(SDK) -fobjc-arc -fmodules -g -O0 \
          -Wall -Werror -I$(REPO)/Source -DFROZIO_VERSION=\"$(VERSION)\" -DFROZIO_DEBUG=1 -DFROZIO_HARNESS=1
FRAMEWORKS := -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics \
              -framework CoreText -framework CoreImage -framework UniformTypeIdentifiers -framework MediaPlayer -framework AVFoundation -framework AVKit -framework Metal -framework MediaToolbox -framework Accelerate -framework Security -framework SwiftUI -framework AppIntents -lsqlite3 -lz

.PHONY: all run shot log clean

all: $(APP)/FrozioHarness

# Frozio's Objective-C is compiled to objects, then linked by swiftc with the SwiftUI stand-in.
$(APP)/FrozioHarness: $(SOURCES) $(HEADERS) $(SWIFT) Info.plist Makefile
	@mkdir -p $(APP)/Frozio.bundle $(OBJDIR)
	cd $(OBJDIR) && xcrun --sdk iphonesimulator clang $(CFLAGS) -c $(abspath $(SOURCES))
	$(SWIFTC) -target $(TARGET) -sdk $(SDK) -g -Onone -parse-as-library -module-name FrozioHarness $(SWIFT) $(OBJDIR)/*.o $(FRAMEWORKS) -o $@
	cp Info.plist $(APP)/Info.plist
	cp "$(REPO)/layout/Library/Application Support/Frozio.bundle/"* $(APP)/Frozio.bundle/
	codesign --force --sign - --timestamp=none $(APP)

run: all
	@xcrun simctl boot "$(DEVICE)" 2>/dev/null || true
	@open -a Simulator
	xcrun simctl install booted $(APP)
	xcrun simctl launch --terminate-running-process booted com.frozio.harness -FZHarnessOpenSettings YES

shot:
	xcrun simctl io booted screenshot $(BUILD)/shot.png

log:
	xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "com.frozio.tweak"'

clean:
	rm -rf $(BUILD)
