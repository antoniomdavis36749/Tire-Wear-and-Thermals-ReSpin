# BeamNG Repo listing (copy-paste)

**Two Repo resources** from the same git tree (required — `vehicles/` cannot ship inside core):

| Resource | Zip | Tag id (local) |
| --- | --- | --- |
| **Core** — thermals + UI | `TireWearThermalsReSpin_antoniomdavis36749.zip` | `TWTRS_RESPIN` |
| **Compat Tires** — second listing | `TireWearThermalsReSpin_CompatTires.zip` | `TWTRS_COMPAT` |

Keep each zip filename stable across updates. After both are approved, cross-link the two Repo URLs in each description.

---

## Core resource

| Field | Value |
| --- | --- |
| **Title** | Tire Wear and Thermals ReSpin |
| **Tagline** | Open-source tyre thermals, wear & grip — ReSpin of Luuk + Zesty_Maple98 Redux |
| **Version** | 0.1.1 |
| **Zip filename** | `TireWearThermalsReSpin_antoniomdavis36749.zip` (or `TireWearThermalsReSpin.zip`) |
| **Prefix** | Alpha |
| **Category** | Utility / Gameplay (confirm on upload form) |

---

## Description (BBCode)

```bbcode
[B]Tire Wear and Thermals ReSpin[/B]
Open-source tyre temperature, wear, and grip simulation for BeamNG.drive.

This is a [B]new[/B] resource (not an update to Redux). It continues the AGPL lineage of Luuk’s original mod and Zesty_Maple98’s Redux rework, with further thermals/wear tuning and BeamNG 0.39 compatibility work.

[HR][/HR]
[B]Credits[/B]
• [USER=53119]@lucky4luuk[/USER] — original [I]Tyre Thermals and Wear[/I] (open source; authorship cited)
• [USER=393895]@Zesty_Maple98[/USER] — [I]Tyre Wear and Thermals Redux[/I] expansion (permission received)

Full attribution is also in CREDITS.md / NOTICE inside the package.

[HR][/HR]
[B]Features[/B]
• Tyre thermals driven by slip, load, camber, brakes, and surface
• Wear that feeds back into grip over a stint
• Compound-aware behaviour (street → sport → race / slick spectrum)
• Locked ReSpin slick ladder (Hard C2 / Medium C3 / Soft C4) with Soft > Medium > Hard wear rates
• Layout-aware Soft drive heat (FWD / AWD fronts) — keeps Hot under abuse without rewriting compound knobs
• Pressure, load, and surface effects on grip
• Brake cooling duct sliders (Tuning → Brakes; saved in .pc configs)
• UI apps: Driver / Classic / Crew (carcass + rim + stint fade) / Pitwall tyre telemetry (ships; engineer view)
• Pitwall: stint/odo distance + live heat-knob chips for reload proof
• Multiplayer-compatible vehicle extension
• BeamNG 0.39-aware pack-air / draft coexistence (no dependency on extra draft mods)
• Optional [B]Respin[/B] selectable tire clones for a few popular GT3 packs whose author tires fight the green thermal window (meshes stay in those mods — see below)

[HR][/HR]
[B]How to use[/B]
1. Install / enable the mod (disable any older thermals-and-wear unpack if present).
2. Spawn a vehicle.
3. Apps menu → add [B]Tyre Wear & Thermals[/B] (Driver, Classic, Crew, or Pitwall).
4. Optional: Tuning → Brakes → Front/Rear duct opening (1% = closed, 100% = fully open).
5. Optional (compatibility tires): install the separate Repo resource [B]Tire Wear and Thermals ReSpin — Compat Tires[/B], plus [I]Scintilla GT3[/I] or [I]Pigniteon ETK Racing[/I] for meshes. Parts → tires → pick a name ending in [B]Respin[/B] (Scintilla also has Hard/Medium/Soft Slick). Author configs still default to upstream tires.

[HR][/HR]
[B]Requirements[/B]
• Current BeamNG.drive (developed/tested with 0.39-era builds)
• No required companion mods for core thermals/wear
• Optional [B]Compat Tires[/B] is a [B]second Repo resource[/B] (cannot ship inside this zip — BeamNG would hide the UI apps)
• Compatibility tires also need the matching car mod for meshes only (Scintilla GT3 Racing Parts / Pigniteon ETK Racing). ReSpin does not redistribute those meshes.

[B]Known limitations (Alpha)[/B]
• Street / utility / wet compounds still need broader surface A/B; race Soft/Med/Hard band is locked from live Track 15°C stints
• UI layout can be imperfect on vehicles with more than four wheels
• Pitwall is dense by design (engineer diagnostics)
• Some third-party race tires use unconventional friction; use the optional Respin clones or wait for upstream fixes
• AWD Soft can still spike one front under heavy brake soak — treated as a harsh-drive ceiling, not a compound miss

[HR][/HR]
[B]Links[/B]
Source: [URL]https://github.com/antoniomdavis36749/Tire-Wear-and-Thermals-ReSpin[/URL]
Discussion (ReSpin): [URL]https://www.beamng.com/threads/tire-wear-and-thermals-respin-%E2%80%94-discussion-feedback-compat.111238/[/URL]
Discussion (upstream Redux thread): [URL]https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/[/URL]
Original: [URL]https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/[/URL]
Redux: [URL]https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/[/URL]

[B]License[/B]
GNU Affero General Public License v3 — see the [I]license[/I] file in the package. Source must remain available for network-use derivatives under AGPL.
```

---

## Compat Tires resource (second listing)

| Field | Value |
| --- | --- |
| **Title** | Tire Wear and Thermals ReSpin — Compat Tires |
| **Tagline** | Optional Respin-selectable GT3 tire JBeams (meshes stay in companion car mods) |
| **Version** | 0.1.1 |
| **Zip filename** | `TireWearThermalsReSpin_CompatTires.zip` |
| **Prefix** | Alpha |
| **Category** | Vehicles / Parts (confirm on upload form) |
| **Requires** | Core ReSpin Repo resource + Scintilla GT3 and/or Pigniteon ETK Racing for meshes |

### Description (BBCode)

```bbcode
[B]Tire Wear and Thermals ReSpin — Compat Tires[/B]

Optional [B]second Repo resource[/B] for the core [I]Tire Wear and Thermals ReSpin[/I] mod. Ships [B]JBeam-only[/B] selectable [I]*_Respin[/I] tire clones so popular third-party GT3 packs can sit in a ReSpin-friendly thermal window.

This is [B]not[/B] a standalone thermals mod — install [B]core ReSpin[/B] first.

[HR][/HR]
[B]Install[/B]
1. Install / enable [B]Tire Wear and Thermals ReSpin[/B] (core — thermals + UI apps).
2. Install / enable [B]this[/B] Compat Tires resource.
3. Install the matching car mod for meshes (Scintilla GT3 Racing Parts and/or Pigniteon ETK Racing).
4. Parts → tires → pick a name ending in [B]Respin[/B] (Scintilla also has Hard/Medium/Soft Slick).

[HR][/HR]
[B]Why a separate Repo listing?[/B]
BeamNG mounts vehicle-classified packages at [I]vehicles/[/I] only. Compat tires must not live inside the core ReSpin zip or the Apps / Lua never mount.

[HR][/HR]
[B]Includes[/B]
• Scintilla GT3 Respin tires (default Soft + Hard/Medium/Soft Slick SKUs)
• Pigniteon ETKC Grip-All GT3 Respin tires
• Stock-like friction / softness for ReSpin thermal windows — author tire files unchanged

[HR][/HR]
[B]Legal[/B]
• Does [B]not[/B] redistribute companion meshes, textures, or sounds.
• Upstream car/tire authors are optional companions — not ReSpin contributors.
• Scintilla GT3 Racing Parts — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/
• Pigniteon ETK Racing — credit per that pack’s Repo listing
• AGPL-3.0 — same lineage as core ReSpin. Source: [URL]https://github.com/antoniomdavis36749/Tire-Wear-and-Thermals-ReSpin[/URL]
• Discussion / feedback & compat suggestions: [URL]https://www.beamng.com/threads/tire-wear-and-thermals-respin-%E2%80%94-discussion-feedback-compat.111238/[/URL]
```

Gallery for this listing: `mod_info/TWTRS_COMPAT/images/listing_hero.jpg` (icon: `icon.jpg`).

---

## Changelog (0.1.1 — calibration band)

- Soft C4 / Medium C3 / Hard C2 heat + wear locked (Belasco / WCU Track ~15°C protocol)
- FWD Soft-like driven-front damp locked (top of usable ~95–105)
- AWD Soft-like driven-front damp locked (FR usable; FL harsh/brake ceiling)
- Pitwall: stint km / odo km + heat-knob chips; capture-friendly contrast
- Respin GT3 Hard/Medium/Soft selectable SKUs documented for companions

---

## Screenshot / gallery plan (Repo page)

Yes — BeamNG Repo listings support **multiple images** with **captions/descriptions** on the resource page (upload gallery + optional notes in the description BBCode).

### Locked heroes (use these)

| Image | Resource | Caption / description (paste on upload) |
| --- | --- | --- |
| `mod_info/TWTRS_RESPIN/images/listing_hero.jpg` (icon: `icon.jpg`) | **Core** ReSpin | **ReSpin** — Tire wear, thermals & grip for BeamNG.drive. Open-source continuation of Luuk + Redux. |
| `mod_info/TWTRS_RESPIN/images/ui_four_apps.jpg` | **Core** ReSpin | **Four UI tiers in one shot** — Pitwall (full engineer), Crew (carcass + stint fade), Driver (quick read), and Classic (compact I/C/O temps). Pick the density you need. |
| `mod_info/TWTRS_RESPIN/images/ducts.jpg` | **Core** ReSpin | **Brake cooling ducts** — Tuning → Brakes → Front/Rear Cooling Ducts (1% = closed, 100% = open). Saved with the vehicle `.pc`. |
| `mod_info/TWTRS_COMPAT/images/listing_hero.jpg` (icon: `icon.jpg`) | **Compat Tires** companion | **ReSpin Tires** — Optional selectable `*_Respin` GT3 tire JBeams (meshes stay in the car mods). Install beside core ReSpin. |
| `mod_info/TWTRS_RESPIN/images/tire_thermal_map.jpg` (draft) | **Core** ReSpin (optional 4th gallery) | **Tire thermal map** — Inner / center / outer tread + surface, carcass, and rim-soak callouts (same Hirochi / ring language as the hero). |

Masters (do not restyle without unlock): `tools/listing/locked/respin-core-hero.jpg`, `respin-compat-hero.jpg`, `respin-ui-four-apps.jpg`, `respin-ducts.jpg`. Draft (not locked): `tools/listing/drafts/respin-tire-thermal-map.jpg`.

### Gallery captions — the four apps (from `ui_four_apps.jpg`)

Use as one image with this description, or split into bullets in the listing body:

1. **Pitwall** (left) — Full engineer telemetry: environment, per-tire tread/grip/PSI, surface vs carcass heat, brakes/rim soak, test channels.
2. **Crew** (top right) — Four-corner crew view with tread, grip, PSI, temp state, and surface heat maps.
3. **Driver** (middle right) — Streamlined driver HUD: condition, grip, pressure, heat bars.
4. **Classic** (bottom right) — Compact inner/center/outer temperature blocks per axle.

Exposure on the source capture was pulled down for listing readability; UI panels were kept intact.

Gallery order tip: hero → `ui_four_apps` → `ducts`.

---

## Thumbnail / icon

Locked poster icons replace the older tyre/pit thumbnail:

- Core: `mod_info/TWTRS_RESPIN/icon.jpg`
- Compat: `mod_info/TWTRS_COMPAT/icon.jpg`

`icon-redux-reference.jpg` (if present locally) is archive-only — do not ship.

## Credits note

- **lucky4luuk** — original work released as open source; cite authorship.
- **Zesty_Maple98** — Redux expansion; permission received for this ReSpin.

## Compatibility tires (optional companions — not ReSpin authors)

Mention on the listing when advertising the stop-gap parts; full inventory in `COMPAT_TIRES.md`.

- Scintilla GT3 Racing Parts — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/
- Pigniteon ETK Racing — credit the pack author as on that Repo listing

Do not ship their meshes/textures inside either ReSpin zip. Compat tires are a **second BeamNG Repo resource** from the same git tree (`vehicles/common/` + `mod_info/TWTRS_COMPAT/`).
