# Dev tools

Helpers for soft-sims, West Coast lap telemetry, and profile transforms.

| Path | Purpose |
| --- | --- |
| `scripts/` | PowerShell / Python helpers |
| `fixtures/` | Race track / Belasco path inputs |
| `output/` | Generated CSV, status JSON, soft-sim dumps (gitignored) |

## West Coast lap / telemetry

Triggers live in `tools/` (VFS: `mods/unpacked/Tire-Wear-and-Thermals-ReSpin-main/tools`):

- `RUN_WC_MANUAL_TEL` — manual drive + CSV telemetry
- `RUN_WC_GT4_TEST` — auto AI Belasco test
- `STOP_WC_TEST` — abort
- `TELEMETRY_CSV_ARMED` — written by the vehicle extension when CSV is armed

Outputs go to `tools/output/` (`wc-*-lap-*.csv/json/txt`).

Vehicle CSV (armed only via `setTelemetryCsv` / West Coast runners; off by default) keeps the
legacy `wall..film` columns, then appends UI-stream fields: `profile,profile1,profile2,purpose,classifyReason,patchFrac,patchHeatScale,aeroLoadN,totalDownforceN,aeroFracPct,dutyMods,driveHeatGate,streetSlipScale,utilNudge`.
`dutyMods` / profile strings are CSV-quoted when they contain commas. Parsers that only use
legacy indices (e.g. `Summarize-WcTelemetry.ps1` cols 0–13) stay compatible.

Example runners: `scripts/Run-WestCoastManualTelemetry.ps1`, `Run-WestCoastGt4Laps.ps1`, etc.

### WCU Soft C4 mute-removal notes (live)

- **Compound for A/B:** ReSpin Soft Slick (C4) F+R — hold fixed across each mute family.
- **Phase 1 (done):** `drivePropSlickScale` / `drivePropSlickCarcassScale` → 1.0. Rears warm into/near opt 82; fronts lag (undriven + brake).
- **WCU right-turn bias:** Belasco / West Coast has many right turns in heavy-accel zones. On RWD that spikes **RL** skin/carcass vs **RR** (~+8–12°C typical). Treat RL≫RR as **track/load asymmetry**, not a Soft C4 bug — do not chase with global cool.
- **Phase 2 (cruise mutes):** `cruiseRrScaleFull` / `cruiseRrScalePartial` / `cruiseDriveChokeMin` → 1.0 (was 0.48 / 0.72 / 0.15). Soft C4 live A/B; watch Belasco highway straights for cook.
- **Soft C4:** airCool **locked 0.014**. slip/work raised to **14.0 / 7.8** (was 12.4 / 6.9). wearRate **0.00185** / hotWearMult **4.25**. Phase 1+2 unmute held. Protocol: **4 laps**.
- Path A patch math stays engineering calibration (not a balance mute).
