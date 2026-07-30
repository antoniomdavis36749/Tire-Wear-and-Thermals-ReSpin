# BeamNG Repo publish checklist

Branch: `beamng-repo-publish`  
Working folder: `Tire-Wear-and-Thermals-ReSpin-main`  
Official packing docs: https://documentation.beamng.com/modding/mod-support/mod_packing/  
Guidelines: https://www.beamng.com/game/support/policies/modding-guidelines/

## Status legend

- `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` deferred / N/A

---

## A. Legal & credits (required)

- [x] Keep AGPL-3.0 (`license`)
- [x] Credit **lucky4luuk** (original) and **Zesty_Maple98** (Redux) — `CREDITS.md`, `NOTICE`, README, app authors, listing text
- [ ] Confirm you have permission / AGPL compliance to redistribute derivative (source link on listing)
- [ ] Decide listing author name (your BeamNG forum username) — fill into `mod_info` / repo form
- [ ] Link **your** GitHub source on the resource page (not only upstream Redux)

## B. What ships vs what stays private

Player zip should contain only runtime content. Dev tooling must not ship.

| Include in release zip | Exclude from release zip |
| --- | --- |
| `lua/` (except lap harness if removed below) | `tools/` |
| `ui/` | `.vscode/` |
| `scripts/luukstyrethermalsandwear/` | `.git/` |
| `license`, `CREDITS.md`, `NOTICE`, `README.md` | `tools/output/`, soft-sim dumps |
| `mod_info/` (cleaned for **new** resource) | Old Redux `resource_id` / foreign `username` leftovers |

- [x] Document exclude list (this file + packer)
- [x] Stop loading `tyreWestCoastLapTest` for players
- [ ] Decide: ship **Heavy** UI app (diagnostics) or keep Medium/Light only
- [x] Optional: omit `tyreWestCoastLapTest.lua` from release zip (packer excludes it; file remains in git for tools)

## C. Identity & metadata (new Repo resource)

Do **not** reuse Redux’s resource identity. This is a new listing derived from open source.

- [x] New title: `Tire Wear and Thermals ReSpin`
- [x] Short tagline with credits
- [x] Full description draft in `mod_info/TWTRS_RESPIN/info.json`
- [x] Version string `0.1.0` (no version in zip filename)
- [x] Zip name draft: `TireWearThermalsReSpin.zip` (add `_YourBeamNGUser` before upload if needed)
- [x] Removed Redux `resource_id` / `MXFQY32S5` / foreign owner fields / stale hashes
- [x] Local placeholder tagid `TWTRS_RESPIN` (Repo will assign official tag on upload)
- [ ] Confirm BeamNG forum username (currently set to GitHub-style `antoniomdavis36749` — change if different)
- [ ] Icon / preview images (≥2 screenshots for listing)
- [ ] Category confirmed on upload form
- [ ] Prefix: Alpha until balance is ready

## D. Technical readiness

- [ ] Game version: verify on current BeamNG (0.39+) clean profile
- [ ] No Lua load errors (`main function has more than 200 local variables`, missing modules)
- [ ] Vehicle spawn + thermals/wear/grip behave
- [ ] UI apps appear and stream data
- [ ] Brake duct sliders appear and save in `.pc`
- [ ] No dependency on companion draft mod
- [ ] Only **one** copy of this mod enabled (disable old `tyre-thermals-and-wear` unpacked folder)
- [ ] Hardcoded VFS paths: either remove arm-marker absolute unpacked path or make it optional/no-op for packaged installs

## E. Packing (zip)

Correct zip root = top-level game folders (`lua`, `ui`, `scripts`, …), **not** a parent `Tire-Wear-and-Thermals-ReSpin-main/` folder.

- [x] Use `tools/scripts/Pack-Release.ps1` (creates correctly nested zip)
- [ ] Open zip and confirm first entries are `lua/`, `ui/`, `scripts/`, …
- [ ] Install zip alone on a clean user folder / profile
- [ ] Clear cache if needed; check `BeamNG.log` for missing files

## F. Repo submission

- [ ] Upload zip via in-game Repository / website as **new resource** (not an update to Redux 29934)
- [ ] Fill title, description, images, tags
- [ ] Wait for moderator review (can take several working days)
- [ ] After approval: note resource URL; keep zip **filename stable** for future updates

## G. Post-publish maintenance

- [ ] Keep `main` for ongoing development; merge publish polish selectively
- [ ] Updates: same zip filename, bump version, changelog summary
- [ ] When changing physics: re-test clean zip install before each update

---

## Quick start (this branch)

1. Finish sections A–D locally and in-game.  
2. Run `tools/scripts/Pack-Release.ps1`.  
3. Verify zip layout, then test the zip alone.  
4. Submit as a **new** BeamNG Repo resource.
