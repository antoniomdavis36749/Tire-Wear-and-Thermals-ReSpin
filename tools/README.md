# Dev tools

Helpers for soft-sims, West Coast lap telemetry, and profile transforms.

| Path | Purpose |
| --- | --- |
| `scripts/` | PowerShell / Python helpers |
| `fixtures/` | Race track / Belasco path inputs |
| `output/` | Generated CSV, status JSON, soft-sim dumps (gitignored) |

## West Coast lap / telemetry

Triggers live in `tools/` (VFS: `mods/unpacked/tyre-thermals-and-wear/tools`):

- `RUN_WC_MANUAL_TEL` — manual drive + CSV telemetry
- `RUN_WC_GT4_TEST` — auto AI Belasco test
- `STOP_WC_TEST` — abort
- `TELEMETRY_CSV_ARMED` — written by the vehicle extension when CSV is armed

Outputs go to `tools/output/` (`wc-*-lap-*.csv/json/txt`).

Example runners: `scripts/Run-WestCoastManualTelemetry.ps1`, `Run-WestCoastGt4Laps.ps1`, etc.
