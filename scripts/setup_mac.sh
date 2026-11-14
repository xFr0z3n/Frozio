#!/usr/bin/env bash
# Checks the local macOS toolchain and links Xcode's iPhoneOS SDK into Theos (same as CI's
# "Link Xcode iPhoneOS SDK into Theos" step). Safe to re-run; run again after every Xcode update.
#
# The toolchain mirrors .github/workflows/build.yml. Homebrew doesn't support Intel Macs, so on
# this machine each tool is installed by hand into /usr/local/bin (docs/LAYOUT.md, "Local build").
set -uo pipefail
fail=0
need() { if command -v "$1" >/dev/null; then printf '  ok       %-13s %s\n' "$1" "$(command -v "$1")"
         else printf '  MISSING  %s (%s)\n' "$1" "$2"; fail=1; fi; }

echo "== tools"
need ldid         "github.com/ProcursusTeam/ldid releases"
need insert_dylib "Tyilo/insert_dylib at CI's INSERT_DYLIB_REF, built with clang"
need ipsw         "github.com/blacktop/ipsw releases"
need gh           "cli.github.com"
make --version | head -1 | grep -qE 'GNU Make [4-9]' \
    && echo "  ok       make          $(make --version | head -1)" \
    || { echo "  MISSING  GNU make >= 4 first on PATH (Theos needs it)"; fail=1; }

echo "== Theos"
if [ -n "${THEOS:-}" ] && [ -d "$THEOS/makefiles" ]; then
    echo "  ok       THEOS=$THEOS ($(git -C "$THEOS" rev-parse --short HEAD))"
else
    echo "  MISSING  THEOS (git clone --recursive theos/theos at CI's THEOS_REF)"; fail=1
fi

echo "== Xcode"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    echo "  MISSING  full Xcode (iPhoneOS/iPhoneSimulator SDKs, simctl)."
    echo "           Install it from the App Store, then: sudo xcode-select -s /Applications/Xcode.app"
    exit 1
fi
echo "  ok       $(xcodebuild -version | tr '\n' ' ')"
xcrun simctl help >/dev/null 2>&1 && echo "  ok       simctl" || { echo "  MISSING  simctl"; fail=1; }

if [ -n "${THEOS:-}" ] && [ -d "$THEOS/makefiles" ]; then
    SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    VER="$(xcrun --sdk iphoneos --show-sdk-version)"
    mkdir -p "$THEOS/sdks"
    rm -rf "$THEOS/sdks/iPhoneOS$VER.sdk"
    ln -s "$SDK" "$THEOS/sdks/iPhoneOS$VER.sdk"
    echo "  ok       linked iPhoneOS$VER.sdk into \$THEOS/sdks"
fi

exit $fail
