#!/usr/bin/env python3
"""Install Frozio's app icons into an unpacked NaviMus .app (run before signing).

Adapted from pngs/patch-ipa-icon.py (xFr0z3n). Changes: works on an extracted .app,
and also registers the white set as an alternate icon so Frozio settings can switch
to it with -[UIApplication setAlternateIconName:@"White" ...].

Why loose PNGs: Arpeggi ships Assets.car and sets CFBundleIconName, so iOS reads the icon
out of the compiled catalog. Rebuilding Assets.car needs actool, so we drop CFBundleIconName
and let iOS fall back to CFBundleIconFiles (primary) / CFBundleAlternateIcons (alternate).
"""
import argparse, pathlib, plistlib, shutil, sys

PRIMARY = {  # bundle filename -> source filename in the icon-set folder
    "AppIcon60x60@2x.png": "AppIcon60x60@2x.png",
    "AppIcon60x60@3x.png": "AppIcon60x60@3x.png",
    "AppIcon76x76@2x.png": "AppIcon76x76@2x.png",
    "AppIcon76x76@2x~ipad.png": "AppIcon76x76@2x.png",
}
ALT_NAME = "White"
ALT_PREFIX = "FrozioWhite"
ALT = {
    f"{ALT_PREFIX}60x60@2x.png": "AppIcon60x60@2x.png",
    f"{ALT_PREFIX}60x60@3x.png": "AppIcon60x60@3x.png",
    f"{ALT_PREFIX}76x76@2x~ipad.png": "AppIcon76x76@2x.png",
}


def copy_set(app: pathlib.Path, src: pathlib.Path, mapping: dict) -> None:
    for dst, s in mapping.items():
        p = src / s
        if not p.is_file():
            sys.exit(f"missing icon {p}")
        shutil.copyfile(p, app / dst)
        print(f"  wrote {dst}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, type=pathlib.Path)
    ap.add_argument("--primary", required=True, type=pathlib.Path)
    ap.add_argument("--alternate", required=True, type=pathlib.Path)
    a = ap.parse_args()

    copy_set(a.app, a.primary, PRIMARY)
    copy_set(a.app, a.alternate, ALT)

    plist_path = a.app / "Info.plist"
    info = plistlib.loads(plist_path.read_bytes())
    for key, stems, alt_stems in (
        ("CFBundleIcons", ["AppIcon60x60"], [f"{ALT_PREFIX}60x60"]),
        ("CFBundleIcons~ipad", ["AppIcon60x60", "AppIcon76x76"], [f"{ALT_PREFIX}60x60", f"{ALT_PREFIX}76x76"]),
    ):
        block = info.get(key)
        if not isinstance(block, dict):
            block = {}
        primary = block.get("CFBundlePrimaryIcon", {})
        if primary.pop("CFBundleIconName", None) is not None:
            print(f"  plist: {key}.CFBundlePrimaryIcon.CFBundleIconName removed")
        files = list(primary.get("CFBundleIconFiles", []))
        for s in stems:
            if s not in files:
                files.append(s)
        primary["CFBundleIconFiles"] = files
        block["CFBundlePrimaryIcon"] = primary
        alts = block.get("CFBundleAlternateIcons", {})
        alts[ALT_NAME] = {"CFBundleIconFiles": alt_stems, "UIPrerenderedIcon": False}
        block["CFBundleAlternateIcons"] = alts
        info[key] = block
        print(f"  plist: {key} alternate '{ALT_NAME}' -> {alt_stems}")

    plist_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
    return 0


if __name__ == "__main__":
    sys.exit(main())
