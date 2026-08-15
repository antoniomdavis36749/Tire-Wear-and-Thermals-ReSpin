# Tire-Wear-and-Thermals-ReSpin

A variation / continuation of the open-source Tyre Wear and Thermals mods for BeamNG.drive.

## Credits

This project builds on the work of:

| Author | Role |
| --- | --- |
| **[lucky4luuk](https://www.beamng.com/members/lucky4luuk.53119/)** | Original mod author (open source; cite authorship) — [Luuk's Tyre Thermals and Wear](https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/) |
| **[Zesty_Maple98](https://www.beamng.com/members/zesty-maple98.393895/)** | Expanded / reworked the original — [Tyre Wear and Thermals Redux](https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/) (permission received for ReSpin) |

Source lineage remains AGPL-3.0 (see `license`). Thank you to both authors for releasing their work as open source.

### Related links

- ReSpin discussion: https://www.beamng.com/threads/tire-wear-and-thermals-respin-%E2%80%94-discussion-feedback-compat.111238/
- Redux / upstream discussion: https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/
- Redux source (upstream): https://github.com/ample-samples/tyre-thermals-and-wear

## Layout

BeamNG requires the runtime folders below; do not rename them.

| Path | Role |
| --- | --- |
| `lua/vehicle/extensions/auto/` | Main vehicle physics extension (auto-loaded) |
| `lua/vehicle/extensions/` | Helpers + short-name shim |
| `lua/ge/extensions/` | Game-engine extensions (ducts, HUD bridge, lap harness) |
| `lua/common/extensions/` | Shared utilities |
| `scripts/luukstyrethermalsandwear/` | Mod entry (`modscript.lua`) |
| `ui/modules/apps/` | In-game tyre HUD apps |
| `vehicles/common/` | Optional compatibility tire JBeams (`*_Respin`) — companion zip only; see `COMPAT_TIRES.md` |
| `mod_info/TWTRS_RESPIN/` | Core ReSpin resource metadata |
| `mod_info/TWTRS_COMPAT/` | Compat-tires companion metadata |
| `tools/` | Dev soft-sims, WC lap triggers, fixtures — not required to play |
| `.vscode/settings.json` | Editor Lua language-server config only |

See `tools/README.md` for soft-sim / telemetry workflow.  
Optional third-party tire stop-gaps: **`COMPAT_TIRES.md`**.

## Publishing

BeamNG Repo prep: polish on `testing/main`, merge to `main` for the public source link. See **`PUBLISH_CHECKLIST.md`**.

Build release zips (excludes `tools/` and the WC lap harness). Core never includes `vehicles/` (BeamNG would hide UI). Compat tires pack as a **second Repo resource** from the same git tree:

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'TireWearThermalsReSpin_YourName.zip'
# → core zip + TireWearThermalsReSpin_CompatTires.zip (when vehicles/ exists)
```

Repo listing copy-paste (core + Compat): **`LISTING.md`**.  
Compatibility tires inventory / packing: **`COMPAT_TIRES.md`**.

## Brake coupling (non-goals)

ReSpin reads native brake surface/core temps and soaks the tyre rim/carcass only. It does **not** replace native brake thermals, write `brakeTypeSurfaceCoolingCoef` for duct boost (restore-only), own torque fade / pad μ / ABS, or use arcade brake-bite grip hacks. Ducts affect tyre/rim air cooling and brake→rim soak — not native rotors.
