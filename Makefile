# Frozio — Theos tweak for NaviMus (Arpeggi) 1.6.1, sideload-only.
# Layout follows FrozenMusic (Source/, layout/, control, <Tweak>.plist); see docs/LAYOUT.md for deviations.

# NaviMus's main binary is arm64-only (no arm64e slice) and MinimumOSVersion is 17.0
# (docs/DISCREPANCIES.md #10, #11), so the injected dylib matches both.
ARCHS = arm64
TARGET = iphone:clang:latest:17.0
INSTALL_TARGET_PROCESSES = Arpeggi
PACKAGE_VERSION = 0.3.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Frozio
$(TWEAK_NAME)_FILES = $(shell find Source \( -name '*.m' -o -name '*.x' -o -name '*.xm' -o -name '*.swift' \))
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wall -Werror -ISource -DFROZIO_VERSION=\"$(PACKAGE_VERSION)\"
$(TWEAK_NAME)_LIBRARIES = sqlite3 z
$(TWEAK_NAME)_FRAMEWORKS = Foundation UIKit QuartzCore CoreGraphics CoreText CoreImage UniformTypeIdentifiers MediaPlayer AVFoundation AVKit Metal MediaToolbox Accelerate Security CoreMotion
# No Logos hooks and no hooking runtime in Phase 1. The internal generator keeps any
# future %hook off CydiaSubstrate until a runtime is chosen; CI also fails if
# `otool -L` shows a substrate/ellekit dependency.
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

# FROZIO_DEBUG=1 compiles the os_log logger in; release builds compile it out.
ifeq ($(FROZIO_DEBUG),1)
$(TWEAK_NAME)_CFLAGS += -DFROZIO_DEBUG=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk
