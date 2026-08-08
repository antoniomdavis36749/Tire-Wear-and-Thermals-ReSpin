# BeamNG Repo listing (copy-paste)

Use this when creating the **new** Repository resource. Keep the zip filename stable across updates.

| Field | Value |
| --- | --- |
| **Title** | Tire Wear and Thermals ReSpin |
| **Tagline** | Open-source tyre thermals, wear & grip — ReSpin of Luuk + Zesty_Maple98 Redux |
| **Version** | 0.1.0 |
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
• Pressure, load, and surface effects on grip
• Brake cooling duct sliders (Tuning → Brakes; saved in .pc configs)
• UI apps: Driver / Classic / Crew (carcass + rim + stint fade) / Pitwall tyre telemetry
• Multiplayer-compatible vehicle extension
• BeamNG 0.39-aware pack-air / draft coexistence (no dependency on extra draft mods)

[HR][/HR]
[B]How to use[/B]
1. Install / enable the mod (disable any older thermals-and-wear unpack if present).
2. Spawn a vehicle.
3. Apps menu → add [B]Tyre Wear & Thermals[/B] (Driver, Classic, Crew, or Pitwall).
4. Optional: Tuning → Brakes → Front/Rear duct opening (1% = closed, 100% = fully open).

[HR][/HR]
[B]Requirements[/B]
• Current BeamNG.drive (developed/tested with 0.39-era builds)
• No required companion mods

[B]Known limitations (Alpha)[/B]
• Balance is still being refined across compounds and surfaces
• UI layout can be imperfect on vehicles with more than four wheels
• Pitwall app is a full-engineer diagnostics view (more data, denser UI)

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

## Screenshot plan (still needed)

Aim for **≥2** clear images on the listing:

1. **UI + car** — Crew or Classic app visible while driving (temps / wear readable)
2. **Tuning ducts** — Brakes category showing Front/Rear duct sliders
3. Optional: **before/after heat** — inner/center/outer rings after a hard lap
4. Optional: **Pitwall diagnostics** — if you ship that app

Keep the current `mod_info/TWTRS_RESPIN/icon.jpg` or replace with a cleaner square icon when you have one.

---

## Thumbnail / icon

`mod_info/TWTRS_RESPIN/icon.jpg` is an original ReSpin thumbnail (generated tyre/pit close-up, no team/sponsor logos).
`icon-redux-reference.jpg` is the old Redux-carried reference kept locally for comparison (do not ship if you prefer only the new icon — packer includes `icon.jpg` only via the mod_info folder copy; exclude the reference before packing if present).

## Credits note

- **lucky4luuk** — original work released as open source; cite authorship.
- **Zesty_Maple98** — Redux expansion; permission received for this ReSpin.
