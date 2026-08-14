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
- **FWD Soft-like topology LOCKED:** Before damp FR/FL ~**106 / ~120** Hot vs opt **82**. After: FR ~**97** Normal (top of usable ~**95–105**); F≫R kept; Hot still possible under abuse. Scales: `drivePropFwdSoftScale` **0.58** / carcass **0.48** / softnessMin **0.72**. Soft compound knobs untouched. RWD Soft Phase1 unmute stays. Duty: `fwd_soft_drive_damp`. **Do not nudge.**
- **WCU right-turn bias:** Belasco / West Coast has many right turns in heavy-accel zones. On RWD that spikes **RL** skin/carcass vs **RR** (~+8–12°C typical). Treat RL≫RR as **track/load asymmetry**, not a Soft C4 bug — do not chase with global cool.
- **Phase 2 (cruise mutes):** `cruiseRrScaleFull` / `cruiseRrScalePartial` / `cruiseDriveChokeMin` → 1.0 (was 0.48 / 0.72 / 0.15). Soft C4 live A/B; watch Belasco highway straights for cook.
- **Soft C4 wear locked:** rollingWearCoef **70** (4-lap ~95.7–96.6% / ~3.5–4% drop; path live). airCool **0.014**. Protocol: **4 laps**.
- **Soft C4 heat ACCEPTED (locked):** Track **15°C** settle ~**62 / 73 / 80 / 90** vs opt **82**. Loaded Turn 1 FR ~**70** then dumps on the straight. RL harsh-drive cook (~90–100 carcass) is a ceiling, not a bug. F<R on high-DF RWD is realistic — do **not** chase FR to 82 with global heat. No workHeatRate polish. Live knobs: `skinVelCoolScale` **0.85**, `workHeatG0` **0.04**, `staticCoolingRate` **0.060**, `trackConductivityMult` **0.75**, Path A6 floor **0.70**, Phase1+2 unmute. **Do not nudge Soft C4 heat/wear.**
- **Medium C3 (next):** ReSpin Medium Slick F+R. Opt **~84** (not 82). Baseline knobs — do **not** copy Soft velCool 0.85 / workHeatG0 0.04. Same Track **15°C** if comparing shape to Soft. **Protocol: 4 laps first** (same as Soft — 8 laps did not move the Soft plateau). After the 4-lap Pitwall: if FR/RL still climbing, one 8-lap confirm; if the Soft-like F<R pattern is already there, stop at 4 and judge. Capture straight settle + loaded Turn 1. Judge vs Soft shape (FR cold, RR near opt, RL cook ceiling), not “all four at 84.”
- **Medium C3 WEAR+HEAT LOCKED:** Soft-like settle ~**59 / 70s / ~80 / ~83** vs opt **84** (Track 15°C). Live knobs: `skinVelCoolScale` **0.60**, `workHeatG0` **0.04**, `airCool` **0.014**, `staticCoolingRate` **0.060**, `trackConductivityMult` **0.75**, slip/work **15/8.6** (mid **15.5/8.9**), `rollingWearCoef` **42/48**. Soft 0.80 locked. **Do not nudge Medium.**
- **Hard C2 WEAR+HEAT LOCKED (#2):** Soft-like settle ~**62 / 74 / 79 / 86** vs opt **90**; wear ~**0.9–1.4%** @~22 km. Knobs: `skinVelCoolScale` **0.50**, `workHeatG0` **0.04**, slip/work **13.5/7.8** (mid **14/8.1**), `rollingWearCoef` **50/55**. Soft+Medium locked. **Do not nudge Hard.**
- **Wear ladder (locked):** Soft **70** ≈4% → Medium **42/48** → Hard **50/55**.
- **Pitwall reload proof:** Heavy app header shows **Stint km** (mod trip, resets on vehicle reload) + **Odo km** (vehicle electrics when available). Per-wheel **Heat knobs** row: air / vel× / g0 / slip/work / trk — confirms live profile after respawn (Hard → vel×**0.50**, Medium → **0.60**, Soft → **0.85**). Re-add Pitwall app after UI edits.
- **AWD Soft edge case (baseline):** Soft `vel×0.85` + duty `awd_prop_gate`. Settle FR/FL ~**101 / ~115** Hot vs opt **82**; RR/RL ~**81 / ~96**. Rears OK; fronts like pre-damp FWD Soft (FWD Soft damp does not run on `awd` layout). Soft compound lock stands.
- **AWD Soft-like front damp #1 (partial):** FR ~**88** Normal; FL ~**112** Hot (barely moved). Scales **0.58/0.48**.
- **AWD Soft-like front damp LOCKED (#2):** FR ~**96** Normal (top of usable); FL ~**109** Hot (brake soak ~620°C + harsh ceiling — do not chase). Scales: `drivePropAwdSoftScale` **0.45** / carcass **0.38**. Soft/FWD Soft/compound locks untouched. Duty: `awd_soft_front_damp`. **Do not nudge.**
- **Path A6 (heat pin — failed live):** Soft C4 4-lap still ~**58/69/72/76** vs opt **82** after `patchFracRef` 0.043 / heat floor 0.70 / `patchFracHeatMin` 0.026. Path A not the live pin (or already ≥0.70). Keep A6 values; do not stack more Path A for Soft.
- **Skin retention #1 (too mild):** `trackConductivityMult` **1.15→0.88**, `skinCoreConductance` **0.116→0.130**. Clean Track **15°C** short stint still ~**58/70/74/83** vs opt **82**; FR pegged ×0.70. Path A6 live; do not stack more Path A.
- **Skin retention #2 (failed live):** `trackConductivityMult` **0.88→0.75**. Clean Track ~15°C still FR **~58**; FL/RR/RL shape unchanged. Track conduction is not the front-window lever here.
- **Static cool cut (failed live):** `staticCoolingRate` **0.076→0.060**. FR still ~55–60 @ Track 15°C — static is `×0.04` vs on-track **velCool**.
- **Skin velCool 0.70 (live):** Track 15°C ~**64/76/83/94** vs opt **82**. RR in window; **RL cook** (avg 94 / carcass ~102) — keep that as a harsh-drive ceiling, not the cruise settle. FR still Cold; wear ~96–99%.
- **Middle ground + turn-in:** `skinVelCoolScale` **0.85**. Soft `workHeatG0` **0.10** was still a trickle (work ∝ g−G0, then ×0.70 patch). Next: `workHeatG0` **0.10→0.04**. Held: velCool 0.85, airCool **0.014**, wear **70**. **Respawn**. Judge FR/FL on a sweeper; RL still allowed to cook if abused.
