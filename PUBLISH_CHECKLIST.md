# BeamNG Repo publish checklist

Branches: **`testing/main`** (active polish) → merge to **`main`** (GitHub default / Repo source link)  
Working folder: `Tire-Wear-and-Thermals-ReSpin-main`  
Official packing docs: https://documentation.beamng.com/modding/mod-support/mod_packing/  
Guidelines: https://www.beamng.com/game/support/policies/modding-guidelines/

`beamng-repo-publish` is retired (stale ancestor; do not use).

## Status legend

- `[ ]` todo · `[~]` in progress · `[x]` done · `[-]` deferred / N/A

---

## Calibration band (0.1.1) — locked

Live Belasco / WCU Track ~15°C protocol (~4 laps / ~22 km). Soft compound knobs stay locked; layout damps are topology-only.

| Lock | Notes |
| --- | --- |
| Soft C4 heat + wear | `vel×0.85`, rolling **70**, settle ~62/73/80/90 vs opt 82 |
| Medium C3 heat + wear | `vel×0.60`, rolling **42/48**, Soft-like colder settle vs opt 84 |
| Hard C2 heat + wear | `vel×0.50`, rolling **50/55**, ~62/74/79/86 vs opt 90 |
| FWD Soft front damp | `0.58/0.48` — fronts ~97 top of usable |
| AWD Soft front damp | `0.45/0.38` — FR ~96; FL harsh/brake ceiling |

- [x] Soft / Medium / Hard ReSpin slick band locked
- [x] FWD Soft-like topology locked
- [x] AWD Soft-like front damp locked
- [x] Pitwall ships (engineer view + stint/odo + heat-knob chips)
- [x] Listing / `info.json` refreshed for 0.1.1

---

## A. Legal & credits (required)

- [x] Keep AGPL-3.0 (`license`)
- [x] Credit **lucky4luuk** (original, open source — cite authorship) and **Zesty_Maple98** (Redux) — `CREDITS.md`, `NOTICE`, README, app authors, listing text
- [x] Luuk: open-source release; authorship citation required (stated in listing)
- [x] Zesty_Maple98 official permission received (stated in listing)
- [x] Confirm BeamNG forum username: `antoniomdavis36749`
- [x] Link **your** GitHub source on the listing (`LISTING.md` / `info.json`)

## B. What ships vs what stays private

Player zip should contain only runtime content. Dev tooling must not ship.

| Include in **core** zip | Include in **compat** zip | Exclude from both |
| --- | --- | --- |
| `lua/` (no lap harness) | `vehicles/` (`*_Respin` JBeams only) | `tools/`, `.vscode/`, `.git/` |
| `ui/`, `scripts/` | `mod_info/TWTRS_COMPAT/` | Companion car meshes/textures |
| `mod_info/TWTRS_RESPIN/` | `COMPAT_TIRES.md`, `license`, `NOTICE`, `CREDITS.md` | `tools/output/`, soft-sim dumps |
| docs + `COMPAT_TIRES.md` pointer | — | Old Redux `resource_id` leftovers |

**Why two zips:** a package that contains `vehicles/` is mounted as vehicle-only — core UI/Lua never load. Same git repo; two artifacts from `Pack-Release.ps1`.

- [x] Document exclude list (this file + packer)
- [x] Stop loading `tyreWestCoastLapTest` for players
- [x] Ship **Pitwall** UI app (full engineer) alongside Driver / Classic / Crew
- [x] Optional: omit `tyreWestCoastLapTest.lua` from release zip (packer excludes it; file remains in git for tools)
- [x] Document compatibility tires (`COMPAT_TIRES.md`); companion zip + `TWTRS_COMPAT` metadata
- [x] Clean-zip smoke: core Apps visible when `vehicles/` is **not** in the core package
- [x] Smoke-test Respin Soft/Med/Hard on Scintilla GT3 (WCU Track 15°C) — band locked
- [ ] Smoke-test Pigniteon ETKC Respin parts before advertising that companion specifically (optional; Scintilla path confirmed)

## C. Identity & metadata (new Repo resource)

Do **not** reuse Redux’s resource identity. This is a new listing derived from open source.

- [x] New title: `Tire Wear and Thermals ReSpin`
- [x] Polished tagline + BBCode description (`LISTING.md`, `mod_info/TWTRS_RESPIN/info.json`)
- [x] Version string `0.1.1` (no version in zip filename)
- [x] Zip name draft: `TireWearThermalsReSpin.zip` (add `_YourBeamNGUser` before upload if needed)
- [x] Removed Redux `resource_id` / `MXFQY32S5` / foreign owner fields / stale hashes
- [x] Local placeholder tagid `TWTRS_RESPIN` (Repo will assign official tag on upload)
- [x] BeamNG forum username confirmed: `antoniomdavis36749`
- [x] Icon / preview images — locked heroes + four-UI gallery + ducts
- [ ] Category confirmed on upload form
- [x] Prefix: Alpha (street/wet still open; race Soft/Med/Hard band locked)

## D. Technical readiness

- [x] Game version: verify on current BeamNG (0.39+) clean profile / current install
- [x] No Lua load errors (`main function has more than 200 local variables`, missing modules) — local-cap work landed earlier
- [x] Vehicle spawn + thermals/wear/grip behave (RWD Soft/Med/Hard + FWD/AWD Soft edge cases)
- [x] UI apps appear and stream data (Pitwall stint/odo + heat knobs verified live)
- [x] Brake duct sliders appear and save in `.pc` (user tech check 2026-08-14)
- [x] No dependency on companion draft mod (user tech check 2026-08-14)
- [x] Only **one** copy of this mod enabled (user tech check 2026-08-14)
- [x] Hardcoded VFS paths: reviewed / no-op for packaged installs (user tech check 2026-08-14)

## E. Packing (zips)

Correct zip root = top-level game folders, **not** a parent `Tire-Wear-and-Thermals-ReSpin-main/` folder. Forward-slash zip paths required (packer uses Python zipfile).

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'TireWearThermalsReSpin_antoniomdavis36749.zip'
```

- [x] Use `tools/scripts/Pack-Release.ps1` (POSIX paths; core without `vehicles/`; auto companion zip)
- [x] Core zip roots: `lua/`, `ui/`, `scripts/`, `mod_info/TWTRS_RESPIN/` — **no** `vehicles/`
- [x] Compat zip roots: `vehicles/`, `mod_info/TWTRS_COMPAT/` — JBeams only, no meshes
- [x] Install **core + compat** → Apps still appear; Respin tires selectable (Scintilla confirmed 2026-08-14)
- [x] No missing meshes on Respin tire swap; HUD classifies Soft/Med/Hard correctly
- [x] Confirm compat zip has **no** third-party meshes — only `vehicles/common/*_Respin*.jbeam`
- [x] Tag / commit both artifacts from the same git revision before Repo upload (packed from 7735a6e / main merge)
- [ ] Optional: Pigniteon ETKC Respin parts smoke before advertising that companion specifically

## F. Repo submission (two resources)

Upload **both** as **new** resources (not updates to Redux 29934). Same git revision for both zips.

### F1. Core — Tire Wear and Thermals ReSpin

- [ ] Upload `TireWearThermalsReSpin_antoniomdavis36749.zip`
- [ ] Paste core BBCode from `LISTING.md`; gallery: hero → `ui_four_apps` → `ducts`
- [ ] Category confirmed on form
- [ ] After approval: note core resource URL; keep zip filename stable

### F2. Compat Tires — second listing

- [x] Decision: Compat is a **second Repo resource** (not bundled / not “later only”)
- [ ] Upload `TireWearThermalsReSpin_CompatTires.zip`
- [ ] Paste Compat BBCode from `LISTING.md`; gallery: Compat hero
- [ ] Category confirmed on form (Vehicles/Parts likely)
- [ ] After approval: note Compat URL; cross-link core ↔ Compat in both descriptions
- [ ] Optional: Pigniteon ETKC smoke before advertising that companion in Compat listing

## G. Post-publish maintenance

- [ ] Keep `main` for ongoing development; merge publish polish selectively
- [ ] Updates: same zip filenames, bump version on **both** resources when JBeams or thermals change together
- [ ] When changing physics: re-test clean zip install before each update

---

## Quick start (this branch)

1. Finish sections A–D locally and in-game.  
2. Run `tools/scripts/Pack-Release.ps1` (emits core + Compat zips).  
3. Verify both zip layouts.  
4. Submit **two** new BeamNG Repo resources (core, then Compat).
