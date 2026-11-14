#!/usr/bin/env bash
# Rebuilds NaviMus's Assets.car with Frozio's icons as real asset-catalog icons (macOS CI only).
#
# Why: loose-PNG alternate icons fail on device with NSOSStatusErrorDomain -54; asset-catalog
# alternate icons are the path Apple supports (docs/FEATURES.md, "App icon").
#
# NaviMus 1.6.1's catalog (assetutil --info, CI run 43553883568) holds, besides its own icon:
#   AccentColor  sRGB (0.996078, 1, 1, 1) for Any and Dark
#   arpeggiLogo  1024x1024 PNG, universal 1x, template mode automatic
# Both are reproduced; the icon (AppIcon + AppIcon_Assets/*) is replaced by Frozio's.
#
#   rebuild_assets.sh <App.app> <repo root> <work dir>
# Exits non-zero WITHOUT touching the app if any step fails; CI then falls back to loose icons.
set -euo pipefail
APP="$1"; REPO="$2"; WORK="$3"
CAR="$APP/Assets.car"
rm -rf "$WORK"; mkdir -p "$WORK"
XC="$WORK/Assets.xcassets"; mkdir -p "$XC"

echo "== verify the source catalog is the one this script was written for"
xcrun --sdk iphoneos assetutil --info "$CAR" > "$WORK/before.json"
python3 - "$WORK/before.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
names = sorted({r.get("Name") for r in d[1:] if r.get("Name")})
app_assets = [n for n in names if n not in ("AppIcon",) and not n.startswith("AppIcon/") and not n.startswith("AppIcon_Assets/")]
print("non-icon assets:", app_assets)
if app_assets != ["AccentColor", "arpeggiLogo"]:
    sys.exit("catalog differs from NaviMus 1.6.1 (expected AccentColor + arpeggiLogo); not rebuilding")
PY

echo "== extract arpeggiLogo"
clang -fobjc-arc -framework Foundation -framework CoreGraphics -framework ImageIO \
  -o "$WORK/carextract" "$REPO/scripts/carextract.m"
mkdir -p "$XC/arpeggiLogo.imageset"
"$WORK/carextract" "$CAR" arpeggiLogo "$XC/arpeggiLogo.imageset/arpeggiLogo.png"
cat > "$XC/arpeggiLogo.imageset/Contents.json" <<'JSON'
{ "images" : [ { "filename" : "arpeggiLogo.png", "idiom" : "universal", "scale" : "1x" },
               { "idiom" : "universal", "scale" : "2x" }, { "idiom" : "universal", "scale" : "3x" } ],
  "info" : { "author" : "xcode", "version" : 1 } }
JSON

echo "== AccentColor"
mkdir -p "$XC/AccentColor.colorset"
cat > "$XC/AccentColor.colorset/Contents.json" <<'JSON'
{ "colors" : [
    { "color" : { "color-space" : "srgb", "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "1.000", "red" : "0.996" } }, "idiom" : "universal" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb", "components" : { "alpha" : "1.000", "blue" : "1.000", "green" : "1.000", "red" : "0.996" } }, "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 } }
JSON

echo "== Frozio icons"
for pair in "AppIcon:cyan" "AppIcon-White:white"; do
  name="${pair%%:*}"; look="${pair##*:}"
  mkdir -p "$XC/$name.appiconset"
  cp "$REPO/Resources/AppIcons/$look/appicon-$look-1024.png" "$XC/$name.appiconset/icon.png"
  cat > "$XC/$name.appiconset/Contents.json" <<'JSON'
{ "images" : [ { "filename" : "icon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 } }
JSON
done
echo '{ "info" : { "author" : "xcode", "version" : 1 } }' > "$XC/Contents.json"

echo "== actool"
mkdir -p "$WORK/out"
xcrun actool "$XC" --compile "$WORK/out" --platform iphoneos --minimum-deployment-target 17.0 \
  --target-device iphone --target-device ipad \
  --app-icon AppIcon --alternate-app-icon AppIcon-White --include-all-app-icons \
  --output-partial-info-plist "$WORK/partial.plist" --output-format human-readable-text
ls -la "$WORK/out"
plutil -p "$WORK/partial.plist"

echo "== verify the new catalog"
xcrun --sdk iphoneos assetutil --info "$WORK/out/Assets.car" > "$WORK/after.json"
python3 - "$WORK/after.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
names = {r.get("Name") for r in d[1:]}
need = {"AccentColor", "arpeggiLogo", "AppIcon", "AppIcon-White"}
missing = need - names
print("new catalog names:", sorted(n for n in names if n))
if missing: sys.exit(f"new catalog is missing {sorted(missing)}")
PY

echo "== install into the app"
cp "$WORK/out/Assets.car" "$CAR"
find "$WORK/out" -maxdepth 1 -name '*.png' -exec cp {} "$APP/" \;
python3 - "$APP/Info.plist" "$WORK/partial.plist" <<'PY'
import plistlib, sys
info_p, part_p = sys.argv[1], sys.argv[2]
info = plistlib.load(open(info_p, "rb"))
part = plistlib.load(open(part_p, "rb"))
for k in ("CFBundleIcons", "CFBundleIcons~ipad"):
    if k in part:
        info[k] = part[k]
        print("Info.plist", k, "<-", part[k])
plistlib.dump(info, open(info_p, "wb"), fmt=plistlib.FMT_BINARY)
PY
echo "asset catalog rebuilt"
