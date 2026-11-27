#!/bin/zsh
# Re-sign a Frozio IPA with the local device cert and install it on the iPhone over USB.
#
#   scripts/device-install.sh                 # newest asset of the 'frozio-build' draft release
#   scripts/device-install.sh path/to/x.ipa   # a local IPA
#
# Signing material never lives in the repo:
#   - identity: keychain "frozio-signing" (Apple Distribution cert)
#   - profile:  ~/Library/Application Support/FrozioSigning/device.mobileprovision
# Env overrides: FZ_DEVICE (devicectl id), FZ_IDENTITY (cert SHA-1), FZ_KEYCHAIN_PW.
set -euo pipefail

REPO=xFr0z3n/Frozio
DEVICE="${FZ_DEVICE:-00008110-001128601A33801E}"
KEYCHAIN=frozio-signing.keychain
PROFILE="$HOME/Library/Application Support/FrozioSigning/device.mobileprovision"
WORK="${TMPDIR:-/tmp}/frozio-device"

rm -rf "$WORK"; mkdir -p "$WORK"

if [ $# -ge 1 ]; then
  IPA="$1"
else
  gh release download frozio-build -R "$REPO" -p '*.ipa' -D "$WORK" --clobber
  IPA="$(ls "$WORK"/*.ipa | head -n1)"
fi
echo "IPA: $IPA"

[ -f "$PROFILE" ] || { echo "missing profile: $PROFILE" >&2; exit 1; }
security unlock-keychain -p "${FZ_KEYCHAIN_PW:-frozio-local}" "$KEYCHAIN"
IDENTITY="${FZ_IDENTITY:-$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR==1{print $2}')}"
[ -n "$IDENTITY" ] || { echo "no valid identity in $KEYCHAIN" >&2; exit 1; }

security cms -D -i "$PROFILE" > "$WORK/profile.plist"
EXP="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$WORK/profile.plist")"
echo "profile expires: $EXP"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$WORK/profile.plist" > "$WORK/ent.plist"

unzip -q "$IPA" -d "$WORK/x"
APP="$(ls -d "$WORK"/x/Payload/*.app | head -n1)"
cp "$PROFILE" "$APP/embedded.mobileprovision"
rm -rf "$APP/_CodeSignature"

# Inner code first (dylibs, frameworks, plug-ins), then the app.
find "$APP" -depth \( -name '*.dylib' -o -name '*.framework' -o -name '*.appex' \) -print0 |
  while IFS= read -r -d '' f; do
    codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --generate-entitlement-der "$f" >/dev/null
  done
codesign -f -s "$IDENTITY" --keychain "$KEYCHAIN" --entitlements "$WORK/ent.plist" --generate-entitlement-der "$APP"
codesign --verify --deep --strict "$APP"

xcrun devicectl device install app --device "$DEVICE" "$APP"
BID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
if [ "${FZ_NO_LAUNCH:-0}" != 1 ]; then
  # Debug builds open the scripts/fzr control port when launched with the token.
  "$(dirname "$0")/fzr" launch || xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BID" || true
fi
echo "installed $BID"
