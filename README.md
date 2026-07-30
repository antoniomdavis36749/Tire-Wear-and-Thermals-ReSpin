# Tire-Wear-and-Thermals-ReSpin

A variation / continuation of the open-source Tyre Wear and Thermals mods for BeamNG.drive.

## Credits

This project builds on the work of:

| Author | Role |
| --- | --- |
| **[lucky4luuk](https://www.beamng.com/members/lucky4luuk.53119/)** | Original mod author — [Luuk's Tyre Thermals and Wear](https://www.beamng.com/resources/luuks-tyre-thermals-and-wear-mod.26947/) |
| **[Zesty_Maple98](https://www.beamng.com/members/zesty-maple98.393895/)** | Expanded / reworked the original — [Tyre Wear and Thermals Redux](https://www.beamng.com/resources/tyre-wear-and-thermals-redux.29934/) |

Source lineage remains AGPL-3.0 (see `license`). Thank you to both authors for releasing their work as open source.

### Related links

- Redux / discussion: https://www.beamng.com/threads/tyre-wear-and-thermals-mod-discussion.97035/
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
| `mod_info/` | BeamNG resource metadata |
| `tools/` | Dev soft-sims, WC lap triggers, fixtures — not required to play |
| `.vscode/settings.json` | Editor Lua language-server config only |

See `tools/README.md` for soft-sim / telemetry workflow.

## Publishing

BeamNG Repo prep lives on branch `beamng-repo-publish`. See **`PUBLISH_CHECKLIST.md`**.

Build a correctly nested release zip (excludes `tools/` and the WC lap harness):

```powershell
.\tools\scripts\Pack-Release.ps1 -ZipName 'TireWearThermalsReSpin_YourName.zip'
```

