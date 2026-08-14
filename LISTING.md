# BeamNG Repo listing (copy-paste)

Use this when creating the **new** Repository resource. Keep the zip filename stable across updates.

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
5. Optional (compatibility tires): install the separate [B]Compat Tires[/B] companion zip, plus [I]Scintilla GT3[/I] or [I]Pigniteon ETK Racing[/I] for meshes. Parts → tires → pick a name ending in [B]Respin[/B] (Scintilla also has Hard/Medium/Soft Slick). Author configs still default to upstream tires.

[HR][/HR]
[B]Requirements[/B]
• Current BeamNG.drive (developed/tested with 0.39-era builds)
• No required companion mods for core thermals/wear
• Optional Compat Tires zip is a [B]separate[/B] package (cannot ship inside the core zip — BeamNG would hide the UI apps)
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
Discussion (upstream Redux thread): [URL]https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/[/URL]
Original: [URL]https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/[/URL]
Redux: [URL]https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/[/URL]

[B]License[/B]
GNU Affero General Public License v3 — see the [I]license[/I] file in the package. Source must remain available for network-use derivatives under AGPL.
```

---

## Changelog (0.1.1 — calibration band)

- Soft C4 / Medium C3 / Hard C2 heat + wear locked (Belasco / WCU Track ~15°C protocol)
- FWD Soft-like driven-front damp locked (top of usable ~95–105)
- AWD Soft-like driven-front damp locked (FR usable; FL harsh/brake ceiling)
- Pitwall: stint km / odo km + heat-knob chips; capture-friendly contrast
- Respin GT3 Hard/Medium/Soft selectable SKUs documented for companions

---

## Screenshot plan (still needed)

Aim for **≥2** clear images on the listing:

1. **UI + car** — Crew or Classic app visible while driving (temps / wear readable)
2. **Tuning ducts** — Brakes category showing Front/Rear duct sliders
3. Optional: **before/after heat** — inner/center/outer rings after a hard lap
4. Optional: **Pitwall diagnostics** — engineer view with stint/odo + heat knobs

Keep the current `mod_info/TWTRS_RESPIN/icon.jpg` or replace with a cleaner square icon when you have one.

---

## Thumbnail / icon

`mod_info/TWTRS_RESPIN/icon.jpg` is an original ReSpin thumbnail (generated tyre/pit close-up, no team/sponsor logos).
`icon-redux-reference.jpg` is the old Redux-carried reference kept locally for comparison (do not ship if you prefer only the new icon — packer includes `icon.jpg` only via the mod_info folder copy; exclude the reference before packing if present).

## Credits note

- **lucky4luuk** — original work released as open source; cite authorship.
- **Zesty_Maple98** — Redux expansion; permission received for this ReSpin.

## Compatibility tires (optional companions — not ReSpin authors)

Mention on the listing when advertising the stop-gap parts; full inventory in `COMPAT_TIRES.md`.

- Scintilla GT3 Racing Parts — https://www.beamng.com/resources/scintilla-gt3-racing-parts.23027/
- Pigniteon ETK Racing — credit the pack author as on that Repo listing

Do not ship their meshes/textures inside either ReSpin zip. Compat tires are a **separate** Repo/local package from the same git tree (`vehicles/common/` + `mod_info/TWTRS_COMPAT/`).
