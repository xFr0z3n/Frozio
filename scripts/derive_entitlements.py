#!/usr/bin/env python3
"""Derive signing entitlements for the re-signed NaviMus app.

Inputs: the app's ORIGINAL entitlements (plist, from `codesign -d --entitlements`) and the
decoded provisioning profile (plist, from `security cms -D`). Output: an entitlements plist
that only contains what the profile allows, with the original Team ID rewritten.

Rules (from docs/PHASE0_REPORT.md §2, "Re-signing risks"):
- application-identifier / team-identifier come from the new team + the app's bundle ID.
- Keys the profile doesn't grant are dropped and listed (e.g. CarPlay without Apple's grant).
- Team-prefixed string values (KVS identifier) are re-prefixed with the new team.
- aps-environment / get-task-allow take the profile's value.
- The bundle ID is never changed: if the profile's App ID can't cover it, fail (ask the user).
"""
import argparse, fnmatch, plistlib, sys

OLD_TEAM = "9QGVRRV7V8"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True)
    ap.add_argument("--profile", required=True)
    ap.add_argument("--bundle-id", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    orig = plistlib.load(open(a.original, "rb")) if a.original else {}
    prof = plistlib.load(open(a.profile, "rb"))
    pent = prof.get("Entitlements", {})
    team = (prof.get("TeamIdentifier") or [None])[0]
    if not team:
        sys.exit("profile has no TeamIdentifier")

    app_id_pattern = pent.get("application-identifier", "")
    want_app_id = f"{team}.{a.bundle_id}"
    if not fnmatch.fnmatchcase(want_app_id, app_id_pattern):
        sys.exit(f"profile App ID '{app_id_pattern}' does not cover '{want_app_id}'. "
                 "Frozio never changes the bundle ID on its own; use a profile for "
                 f"{a.bundle_id} (or a wildcard), or decide to change the bundle ID.")

    out = {"application-identifier": want_app_id, "com.apple.developer.team-identifier": team}
    dropped = []
    for k, v in orig.items():
        if k in ("application-identifier", "com.apple.developer.team-identifier"):
            continue
        if k not in pent:
            dropped.append(k)
            continue
        if isinstance(v, str):
            v = v.replace(OLD_TEAM, team)
        elif isinstance(v, list):
            v = [x.replace(OLD_TEAM, team) if isinstance(x, str) else x for x in v]
        if k in ("aps-environment",):
            v = pent[k]
        out[k] = v
    if "get-task-allow" in pent:
        out["get-task-allow"] = pent["get-task-allow"]

    plistlib.dump(out, open(a.out, "wb"))
    print("kept:   " + ", ".join(sorted(out)))
    print("dropped (not granted by profile): " + (", ".join(sorted(dropped)) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
