# Compatibility tires (stop-gap)

Optional **selectable** tyre parts shipped with ReSpin so popular third-party race mods can sit in a ReSpin-friendly thermal window **without editing those mods**.

Meshes and materials stay in the **upstream vehicle mods**. ReSpin only ships JBeam clones with stock-like friction / `softnessCoef` so classification and heat rates behave like BeamNG race rubber.

## Why they exist

Some GT3-style mods ship custom tires with unconventional friction (notably `softnessCoef: 0`, elevated `frictionCoef`, and `fullLoadCoef > 1`). ReSpin remaps `softnessCoef: 0` to the **hard slick** band (~90 °C optimal) and scales heat/grip from μ / load curves — so those author tires are hard to keep in the green window.

Until upstream authors adopt stock-compatible values, these `…_Respin` parts are a player-facing workaround.

## Requirements

| Companion mod | Repo / local name | Required for |
| --- | --- | --- |
| Scintilla GT3 Racing Parts | `scintilla_gt3` (Exchy / MXD7VGO9K) | Scintilla Corsa S GT3 Respin tires (meshes under that mod) |
| Pigniteon ETK Racing | `pigniteon_etk_racing` | ETKC Grip-All GT3 Respin tires (meshes under `vehicles/etkc/tires_gt3/`) |

Enable **both** ReSpin and the companion. Configs still mount author tires by default — swap in Parts → Wheels/Tires.

## Files (ship in release zip)

All under `vehicles/common/`:

| File | Vehicle / family |
| --- | --- |
| `tires_F_gt3_Respin.jbeam` | Scintilla GT3 — default soft-slick Respin |
| `tires_R_gt3_Respin.jbeam` | Scintilla GT3 — default soft-slick Respin |
| `tires_F_gt3_Respin_hard_slick.jbeam` | Scintilla GT3 — Hard Slick (C2) |
| `tires_R_gt3_Respin_hard_slick.jbeam` | Scintilla GT3 — Hard Slick (C2) |
| `tires_F_gt3_Respin_medium_slick.jbeam` | Scintilla GT3 — Medium Slick (C3) |
| `tires_R_gt3_Respin_medium_slick.jbeam` | Scintilla GT3 — Medium Slick (C3) |
| `tires_F_gt3_Respin_soft_slick.jbeam` | Scintilla GT3 — Soft Slick (C4) |
| `tires_R_gt3_Respin_soft_slick.jbeam` | Scintilla GT3 — Soft Slick (C4) |
| `tires_F_etkc_gt3_Respin.jbeam` | Pigniteon ETKC GT3 |
| `tires_R_etkc_gt3_Respin.jbeam` | Pigniteon ETKC GT3 |

## Part catalogue

### Scintilla GT3 (slots `tire_F/R_18x12`, `tire_F/R_18x13`)

Author sizes use motorsport OD naming (`325/660`, `325/680`, `325/705`). Balanced/Endurance configs typically use **680 F / 705 R**.

| Part name suffix | UI name ends with | `softnessCoef` | ReSpin band (approx. opt °C) |
| --- | --- | --- | --- |
| `_Respin` | `… Respin` | `1` | Soft slick (~82 °C) |
| `_Respin_hard_slick` | `… Respin Hard Slick (C2)` | `0.50` | Hard slick (~90 °C) |
| `_Respin_medium_slick` | `… Respin Medium Slick (C3)` | `0.65` | Medium slick (~84 °C) |
| `_Respin_soft_slick` | `… Respin Soft Slick (C4)` | `1.00` | Soft slick (~82 °C) |

Examples:

- `tire_F_325_680_18_gt3_Respin`
- `tire_R_325_705_18_gt3_Respin_medium_slick`

### Pigniteon ETKC GT3 (slots `tire_F/R_18x11`)

| Part name | UI name | Notes |
| --- | --- | --- |
| `tire_F_295_30_18_gt3_Respin` | `295/30R18 Grip-All GT3 Front Tires Respin` | Optional size |
| `tire_F_295_35_18_gt3_Respin` | `295/35R18 Grip-All GT3 Front Tires Respin` | Used by stock GT3 `.pc` configs |
| `tire_R_295_30_18_gt3_Respin` | `295/30R18 Grip-All GT3 Rear Tires Respin` | Optional size |
| `tire_R_295_35_18_gt3_Respin` | `295/35R18 Grip-All GT3 Rear Tires Respin` | Used by stock GT3 `.pc` configs |

Default Respin friction target (all of the above except compound variants only change softness):

- `frictionCoef` / `slidingFrictionCoef` = `1.0`
- `noLoadCoef` ≈ `1.85`, `fullLoadCoef` ≈ `0.80`, `loadSensitivitySlope` ≈ `0.00022`
- `stribeckExponent` ≈ `1.75`, `stribeckVelMult` ≈ `2.5`
- `treadCoef` = `0` (slick / race-like)
- Carcass beams / radius / width / meshes copied from upstream

## Player instructions (listing-ready)

1. Install ReSpin **and** the companion car mod.
2. Spawn the GT3 config.
3. Vehicle config → Parts → tires → choose a name ending in **Respin** (and optional Hard/Medium/Soft Slick for Scintilla).
4. Save a personal `.pc` if you want it sticky.

## Legal / attribution (publish)

- Do **not** redistribute companion meshes, textures, or sounds inside the ReSpin zip.
- Credit upstream tire/car authors as **optional companions**, not ReSpin contributors:
  - Scintilla GT3 Racing Parts — Exchy / Turbo49 / Cyborella (et al.) — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/
  - Pigniteon ETK Racing — pack author as on the Repo listing for that zip
- These parts are a **compatibility shim**. Prefer upstream fixes; remove or slim this pack when authors ship stock-compatible tires.
- Naming: keep author size/branding text, append **`Respin`** (and compound label) so parts are distinguishable in the selector.

## Maintainer notes

- Prefer unique filenames under `vehicles/common/` (`*_Respin.jbeam`) — never overwrite upstream paths.
- Part IDs must stay unique (`*_Respin`, `*_Respin_hard_slick`, …).
- After adding a new companion: update this file, `CREDITS.md`, `LISTING.md`, and confirm `Pack-Release.ps1` includes `vehicles/`.
- Smoke-test: spawn car → select Respin tire → no missing-mesh errors → HUD shows soft/medium/hard slick as expected → green window reachable on a short hotlap.
- Author mods must remain **unmodified** in player installs; only ReSpin ships the clones.

## Changelog seed (for Repo updates)

```text
Compatibility tires: optional Respin-selectable clones for Scintilla GT3 and Pigniteon ETKC GT3
(requires those mods for meshes). Stock-like friction/softness for ReSpin thermal windows;
author tire files unchanged.
```
