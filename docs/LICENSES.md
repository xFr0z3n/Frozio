# LICENSES

Frozio is licensed under **GPL-3.0** (`LICENSE`), as decided in Phase 0 (the user approved GPL so GPL code can be reused).

## Code reuse policy

| Source | Licence | May Frozio copy code? |
|---|---|---|
| taurus (`github.com/xFr0z3n/taurus`) | GPL-3.0 (taurus/README.md: "no code under PolyForm Strict License 1.0.0 is distributed") | **Yes**, with attribution |
| spoti.pw **≤ v0.21.1** | GPL-3.0 (spoti.pw/README.md:119-121) | **Yes**, with attribution, taken from those tagged releases |
| spoti.pw **after v0.21.1** (current `main`, v0.50+) | PolyForm Strict 1.0.0 | **No.** Values and behaviour are recorded in `DESIGN_TOKENS.md` / `FEATURE_MATRIX.md`; no source is copied |
| amperfy | GPL-3.0 | **Yes**, with `// Adapted from amperfy/<path>:<lines> (GPL-3.0)` |
| FrozenMusic | GPL-3.0 | Structure and CI shape only |
| `pngs/patch-ipa-icon.py` (xFr0z3n) | the user's own | Adapted into `scripts/patch_icons.py` |

Every borrowed file or block carries a header comment `// Adapted from <repo>/<path>:<lines> (<licence>)`, and gets a row below.

## Borrowed code

| Frozio file | Origin | Licence |
|---|---|---|
| `scripts/patch_icons.py` | `pngs/patch-ipa-icon.py` | user-owned |

## Build-time tools (not shipped)

| Tool | Pin | Licence |
|---|---|---|
| Theos | `theos/theos@344ee59` | GPL-3.0 |
| insert_dylib | `Tyilo/insert_dylib@eb72781` | MIT |
