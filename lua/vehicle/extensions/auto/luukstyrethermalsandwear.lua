-- lua/vehicle/extensions/auto/luukstyrethermalsandwear.lua
-- Credits: lucky4luuk (original open-source mod), Zesty_Maple98 (Redux expansion).
-- This ReSpin builds on their AGPL-licensed work — see CREDITS.md / README.md.
local M = {}

-- Toggle real-time log prints to the BeamNG game console (open with ~ key)
local DEBUG_THERMALS = false

-- Safely wrap module loading in protected calls to prevent execution crashes if files are missing
local has_beamstate, beamstate_mod = pcall(require, "beamstate")
local has_tyre_data, tyre_data_mod = pcall(require, "tyredata")
local has_tyre_utils, tyre_utils_mod = pcall(require, "tyre_utils")
local has_fire, fire_mod = pcall(require, "fire")

-- Cleanly resolve module fallbacks using required locals or system pre-loaded globals to prevent shadowing bugs
local beamstate = (has_beamstate and beamstate_mod) or _G.beamstate
local tyre_data = (has_tyre_data and tyre_data_mod) or _G.tyreData
local tyre_utils = (has_tyre_utils and tyre_utils_mod) or _G.tyre_utils
local fire = (has_fire and fire_mod) or _G.fire

-- BeamNG spike-strip ground material ID (wheels.lua puncture path)
local SPIKE_STRIP_MATERIAL_ID = 32
-- sounds.lua scales slipEnergy ≈ *5e-6 for a 0..1 working range
local NATIVE_SLIP_ENERGY_SCALE = 0.000005
local NATIVE_SLIP_VEL_SCALE = 0.0125

-- Safe JSON fallback mapping
local jsonDecode = _G.jsonDecode or (json and json.decode) or function(str) return {} end
local deserialize = _G.deserialize or _G.unserialize or function(str) return nil end

-- Local math and vector aliases for hot path performance
local quat, vec3 = _G.quat, _G.vec3
local quatFromDir = _G.quatFromDir or (type(_G.quat) == "table" and _G.quat.fromDir) or nil
local sensors = _G.sensors -- Localized sensor registry to eliminate global hot path lookups

-- Robust local math aliases to eliminate global namespace lookups on hot path calls
local min, max, abs, sqrt, exp, cos, sin, deg, acos, asin, pi = math.min, math.max, math.abs, math.sqrt, math.exp, math.cos, math.sin, math.deg, math.acos, math.asin, math.pi

-- Safe fallback bindings if our utility module is missing
local lerp = (type(tyre_utils) == "table" and tyre_utils.lerp) or function(a, b, t) return a + (b - a) * t end
local sigmoid = (type(tyre_utils) == "table" and tyre_utils.sigmoid) or function(x, k) return 1 / (1 + (k or 10) ^ -x) end

-- Declare local tables instead of polluting the global namespace
local groundModels = {}
local groundModelsLut = {}

-- REALISTIC THERMAL CONSTANTS (BALANCED DEFAULT BASELINES)
local WORKING_TEMP = 85
local ENV_TEMP = 21
local TORQUE_ENERGY_MULTIPLIER = 0.25
local RUBBER_EMISSIVITY = 0.94
local STEFAN_BOLTZMANN = 5.670374e-8
local ASPHALT_CONDUCTIVITY = 1.35
local THERMAL_BOUNDARY_LAYER = 0.002
local CORE_REACTION_RATE = 0.08 -- Global carcass integration rate (was a dead per-profile knob)
-- 8-node thermal topology (Lua 1-based):
--   temp[1..3] skin L/C/R | temp[4..6] carcass L/C/R | temp[7] rim | temp[8] cavity air
-- Refinements (P0–P2): contact-patch heat fraction + free-belt cool bias; gated flex
-- warm-up into carcass; skin lateral conductance; dedicated airThermalInertia; cold-
-- biased dynamic skin/carcass grip blend. Packed table keeps CalcTyreWear upvalues safe.
local TEMP_NODE_COUNT = 8
local RIM_THERMAL_INERTIA = 1.35
local RIM_REACTION_RATE = 0.10
local RIM_CARCASS_CONDUCTANCE = 0.042
local RIM_AIR_CONDUCTANCE = 0.028
local CARCASS_LATERAL_CONDUCTANCE = 0.050
local THERMAL_TOPOLOGY = {
    -- P0-1: slip/work/torque heat deposits on patch-resident arc; free belt cools more
    patchFracMin = 0.09,       -- circumferential share floor (light load / lock)
    patchFracMax = 0.22,       -- raised from 0.20 to support high-downforce loads (3.5–5kN/wheel)
    patchFracRef = 0.140,      -- re-normalised reference so ceiling raise doesn't over-amplify normal loads
    freeBeltCoolMult = 1.32,   -- convection boost as freeFrac → 1
    -- P0-2: gated flex/hysteresis into carcass (cruise RR soft-cap still owns straights)
    flexWarmGain = 0.00095,    -- scale on load·ω·RR flex energy → carcass
    flexWarmLoad0 = 120,       -- load_kg gate start
    flexWarmLoad1 = 400,       -- load_kg gate full
    flexWarmSpeed0 = 2.0,      -- m/s freestream gate start
    flexWarmSpeed1 = 20.0,     -- m/s gate full
    flexWarmG0 = 0.28,         -- g deadband (aligns with cruise soft-cap intent)
    -- Excess propulsion: open drive heat on hard throttle (RWD track accel) without Belasco cruise cook
    -- Pass 2: cruiseNm 650→480, excessFullNm 1100→850, skin 0.021→0.030, hyst 1.1e-7→1.9e-7,
    --   flexExcess@gate>0.3; rears still cold on Scintilla.
    -- Pass 3 (aggressive; did not overshoot on drive-heat retest):
    --   cruiseNm 480→280, excessFullNm 850→520, skin 0.030→0.058 (>> brake 0.025),
    --   hystExcess 1.9e-7→5e-7, flexExcess↑ + gate 0.3→0.15, slip/work ×1.22@gate=1,
    --   cruise choke softens above half cruiseNm (idle/coast still ×0.15).
    -- Pass 4 (small ~10–20% bump; not another pass-3 jump):
    --   cruiseNm 280→250, skin 0.058→0.066, hystExcess 5e-7→6e-7,
    --   flexExcess 0.00048→0.00054 + gate 0.15→0.12, slip/work ×1.22→×1.28.
    drivePropCruiseNm = 250,   -- |prop| floor (Nm/wheel); below → excess gate shut (was 280)
    drivePropExcessFullNm = 520,  -- span above cruise to excessGate=1 (unchanged from pass 3)
    drivePropSkinCoef = 0.066, -- skin netTorque prop scale (was 0.058; brake stays 0.025)
    drivePropHystBase = 5e-8,  -- torque hysteresis at excessGate=0
    drivePropHystExcess = 6e-7, -- torque hysteresis at excessGate=1 (was 5e-7)
    drivePropFlexGateStart = 0.12, -- excessFlex begins above this gate (was 0.15)
    drivePropFlexExcess = 0.00054, -- carcass flex add when excessGate>FlexGateStart (was 0.00048)
    drivePropSlipWorkMult = 1.28, -- skin slip/work scale at excessGate=1 (1=off; driven via prop)
    -- Slick/race spectrum only: Pass 3/4 excess drive heat was tuned for sport_plus (Scintilla).
    -- GT4/RWD slicks overcooked driven rears while fronts stayed fine — scale excess only
    -- (sport_plus / street keep 1.0). Burnout slipVelBoost unchanged.
    -- Split: skin (slip/work + netTorque) vs carcass (hyst excess + flex excess + prop-linked RR).
    -- 0.55 skin was good but slightly hot; carcass still runaway → stronger carcass cut.
    drivePropSlickScale = 0.50,           -- skin excess gate (was 0.55)
    drivePropSlickCarcassScale = 0.30,    -- carcass excess/RR under prop (stronger than skin)
    -- Street/non-slick: high freestream damp on excess-prop carcass (prop-hold cruise cook).
    -- Slicks already use drivePropSlickCarcassScale; street kept 1.0 for Scintilla accel but
    -- |prop|≈aero hold opens the excess gate at ~180–300 mph with slip/g still cruise-choked.
    -- Ramp with safeAirspeed so moderate-V hard throttle still warms; full damp ~250 mph.
    drivePropStreetSpeed0 = 78.0,         -- m/s (~175 mph): street carcass damp begins
    drivePropStreetSpeed1 = 112.0,        -- m/s (~250 mph): full street carcass damp
    drivePropStreetCarcassScale = 0.28,   -- carcass excess/RR mult at Speed1 (≈ slick carcass)
    -- P1-1: skin L↔C↔R conductance (mirrors carcass); soft equalizer mostly retired
    skinLateralConductance = 0.042,
    skinEqualizerRetain = 0.05, -- leftover avg soft mix (was 0.20)
    -- P2: grip thermometer — more carcass when cold, skin-led in-window/hot
    gripBlendWarm = 0.18,      -- carcass share near/above opt
    gripBlendCold = 0.36,      -- carcass share when well below opt
    -- Fix A: gated |lastSlip| → longComp boost (burnout/lock smoke without cruise cook)
    -- Ramp is 0 below start (corner/cruise untouched); smoothstep to full by slipVelBoostFull.
    slipVelBoostStart = 8.0,   -- m/s |lastSlip| where boost begins
    slipVelBoostFull = 24.0,   -- m/s |lastSlip| at full boost (hard spin / lock slide)
    slipVelBoostMax = 9.0,     -- extra longComp mult at full (total = 1 + max*ramp)
    -- Toe speed-cap: soft-saturation Vref (m/s). Scrub = v*sin(toe) / (1+v/Vref).
    -- At v=Vref scrub is half the linear extrapolation; effect persists at mid-high speed
    -- without a hard cliff. Raised from implicit 45 m/s hard-cap to 70 m/s soft-sat.
    toeScrubVref = 70.0,       -- m/s; real toe scrub saturates ~highway speed, not motorway
    -- Pressure→grip bands: see pressurePerfectHalf / pressureNormal* / pressureMild* below
    -- Aero downforce thermal discount: aero load is included in wd.downForce but generates
    -- less internal tyre flex/hysteresis heat than equivalent static load. This scales the
    -- aero fraction of load_kg for heat paths ONLY; grip paths remain unaffected.
    -- 0.55 = aero-load contributes 55% as much heat per N as static mechanical load.
    -- aeroHeatSpeedStart/Full: m/s range over which aero discount ramps to full.
    -- aeroHeatMaxFrac: cap on the aero fraction of load assumed at maximum speed (0–1).
    aeroHeatScale     = 0.55,  -- aero thermal efficiency vs mechanical load (1.0 = no discount)
    aeroHeatSpeedStart = 15.0, -- m/s (~54 km/h): below this, no aero discount
    aeroHeatSpeedFull  = 52.0, -- m/s (~187 km/h): ramp fully saturated here (lowered from 56 for GT/aero cars)
    aeroHeatMaxFrac    = 0.48, -- max fraction of load_kg assumed as aero at full speed
    -- Thermal oddities (carcass>>skin / spawn fight / elevation noise):
    skinCoreConductanceScale = 1.85, -- raise skin↔carcass coupling (keeps relative compound ranking)
    skinCoreConductanceFloor = 0.070, -- floor so ultra-low compounds still equilibrate
    carcassCoolVelCoef = 0.28,       -- was hardcoded 0.18 on coreVelCool term
    carcassCoolStaticCoef = 0.20,    -- was hardcoded 0.12 on coreCool term
    hystSkinShare = 0.18,            -- fraction of RR/flex carcass work also deposited on skin
    -- Pressure→grip bands (ratio error = currentPSI/optimalPressure - 1). Absolute PSI target;
    -- stock BeamNG cold fills often sit at/above opt, then Gay-Lussac warm pushes further over —
    -- so the normal OVER band is wider than under. pressureSensitivity scales mild + outer only.
    pressurePerfectHalf = 0.04,      -- |offset| ≤ this → small grip bonus
    pressureNormalUnder = 0.14,      -- under-pressure still "normal" (mild)
    pressureNormalOver = 0.32,       -- over-pressure still "normal" (asymmetric for stock highs)
    pressurePerfectBonus = 0.020,    -- max +2% at exact opt
    pressureMildBase = 0.028,        -- mild penalty at normal-band edge (before sens)
    pressureMildSens = 0.022,        -- +sens contribution to mild edge (≈3.9% @ sens 0.5)
}
local topo = THERMAL_TOPOLOGY -- module-level alias; avoids one function local in CalcTyreWear

-- REALISM FEATURE FLAGS (safe defaults for BeamNG 0.35–0.38 compatibility)
local ENABLE_FORCE_FEEDBACK_FX = false -- Flat-spot / chatter / hop spindle forces (arcade); off by default
local FORCE_FEEDBACK_SCALE = 0.25      -- Used only when ENABLE_FORCE_FEEDBACK_FX is true
local ENABLE_BRAKE_BITE_HACK = false   -- Artificial post-brake long-grip boost
local MAX_DUCT_AIR_FACTOR = 1.45       -- Max tyre/brake cooling boost at 100% duct open
local DUCT_DEFAULT_PCT = 1             -- Tuning default: closed (stock cars have no ducts)
local SLICK_PREHEAT_BLEND = 0.25       -- Race slicks: mild blanket preheat toward optTemp
local STREET_PREHEAT_BLEND = 0.34      -- Street/garage soak (was 0.50; reduced to ease spawn cool fight)
local SKIN_PREHEAT_FRAC = 0.55         -- Skin starts cooler than carcass (blend*frac); carcass keeps soak
local SPAWN_CONV_GRACE_S = 14.0        -- Soften freestream convection for first N seconds after init
local ENV_SMOOTH_RATE = 0.40           -- 1/s toward raw env (was dt*2.0 ≈ tau 0.5s; now ~2.5s)
local ENV_MAX_DELTA_PER_SEC = 2.5      -- Clamp |dEnv/dt| so altitude/mailbox spikes don't yank skin
-- (telemetry locals moved into telem table below)
-- Lockup: full-ring slide heat is physically wrong and bricks post-release spin-up for seconds
local LOCKUP_OMEGA_THRESH = 1.0        -- rad/s — below this, treat as locking/locked
local LOCKUP_HEAT_FLOOR = 0.22         -- Keep some flat-spot heat; not full L/C/R cook
local LOCKUP_RECOVERY_LONG_GRIP = 0.62 -- Min longGrip when brake released & wheel still sliding near lock
local LOCKUP_RECOVERY_OMEGA = 8.0      -- Blend recovery floor out by this ω (rad/s)

-- UI streaming throttling (15 Hz): 20 Hz was chatty; 10 Hz felt choppy on canvas Simple/Heavy.
-- Single vehicle stream rate for all apps — 15 Hz is the usable compromise.
local sendTimer = 0
local SEND_INTERVAL = 1.0 / 15.0 -- ~0.0667 s = 15 Hz
-- Cached once in onInit: prefer queueStream alone (0.39+); else trigger. Avoid per-flush type() checks.
local hasQueueStream = false
local hasGuiTrigger = false

-- FIXED-TIMESTEP SIMULATION ACCUMULATOR (Locks GFX-rate physical integration to a constant 100Hz)
local gfxAccumulator = 0
local FIXED_DT = 0.01 -- 0.01 seconds = 100Hz stable time step
-- Grip/friction at half rate (50Hz): thermals stay smooth; friction API is heavier than ΔT
local GRIP_STEP_INTERVAL = 2
local gripStepCounter = 0

-- Hot-path scratch buffers (vehicle Lua is single-threaded; avoids per-step table alloc)
local scratchSkinSnap = { 0, 0, 0 }
local scratchCarcassSnap = { 0, 0, 0 }
local scratchCarcassWeights = { 0, 0, 0 }

--[[
  ========================================================================
  TIRE PROFILE SCHEMA (mods table) — 39 knobs + runtime descriptor
  Every profile table must include all of these; normalizeProfileMods()
  backfills any missing keys from DEFAULT_MODS.

  GRIP / COMPOUND
    adhesion            0–1  How strongly thermal grip follows the peak curve
                             (higher = more temp-sensitive sticky compound).
    gripMultiplier      Scale on total grip after thermal shaping (~0.6–1.2).
    longGripMult        Longitudinal (brake/accel) grip scale.
    latGripMult         Lateral (cornering) grip scale.
    loadSensitivity     Grip loss under overload vs static wheel load.
    pressureSensitivity Scales mild + outer pressure→grip penalties (band widths are
                             topology globals; higher = pickier compound).
    optimalPressure     Absolute hot PSI target for best patch (also UI hot target).
    casingCompliance    Sidewall flex 0–1 (camber window, pressure expand).
    waterDrainage       0–1 Wet aquaplane resistance (higher = better).
    wetGripScale        Extra wet-paved multiplier (after hydro model).
    dryGripScale        Extra dry/hard surface multiplier.
    camberSensitivity   Scales excess-camber grip penalty.
    bottomOutSensitivity Scales bump/bottom-out wear + grip hit.
    scrubSensitivity     Scales toe-scrub energy into slip heat.

  THERMAL TARGET / GRIP CURVE
    optimalTemp         °C compound peak (working_temp / green window center).
    tempPlateau         °C half-width of full-grip plateau around opt.
    coldWidth           °C Gaussian width below plateau (cold roll-off).
    hotWidth            °C Gaussian width above plateau (hot cliff).
    gripFloor           Minimum thermal multiplier at extreme temps (0–1).

  HEAT GENERATION
    slipHeatRate        Skin heat from sliding / slip energy.
    workHeatRate        Skin/carcass heat from cornering work + vertical.
    rollingRes          Rolling-resistance scale (hysteresis + torque heat).
    brakeGainRate       How strongly stock brake temps soak the rim node.
    scrubSensitivity    (see above) also feeds dynamic slip energy.

  COOLING / CONDUCTION
    staticCoolingRate   Still-air / natural convection baseline.
    airCoolingRate      Freestream convection on skin (× v^0.8).
    coreCoolRate        Carcass static cooling.
    coreVelCoolRate     Carcass velocity-linked cooling.
    skinCoreConductance Skin ↔ carcass lane conductance.
    airConductionRate   Cavity air ↔ carcass / rim coupling.
    trackConductivityMult  Asphalt (etc.) conduction scale into skin.

  THERMAL MASS / RESPONSE
    treadInertia        Skin thermal mass (higher = slower skin ΔT).
    carcassInertia      Carcass thermal mass.
    airThermalInertia   Cavity-air thermal mass (PSI lag dial; << carcass).
    thermalReactionRate Global rate multiplier on skin temp integration.

  TOPOLOGY KNOBS (module THERMAL_TOPOLOGY; not per-profile unless noted)
    patchFracMin/Max/Ref  Contact-patch circumferential share + heat normalize.
    freeBeltCoolMult      Free-belt convection bias on average skin.
    flexWarmGain (+gates) Gated flex energy into carcass (load/speed/g·slip).
    drivePropCruiseNm / ExcessFullNm / SkinCoef / Hyst* / Flex*
                          Excess-prop drive heat pass 4 (small bump on pass 3;
                          choke softens mid-prop; FlexExcess@FlexGateStart; SlipWorkMult).
    drivePropSlickScale   Skin excess-prop mult on slick/race only
                          (sport_plus keeps 1.0; default 0.50).
    drivePropSlickCarcassScale  Carcass excess/RR mult on slick/race only
                          (hyst/flex excess + prop-linked RR; default 0.30).
    drivePropStreetSpeed0/1 / StreetCarcassScale
                          Non-slick high-V carcass excess/RR damp (prop-hold cruise).
    skinLateralConductance  Skin L↔C↔R conductance.
    gripBlendWarm/Cold    Dynamic EffectiveTyreTemp carcass share.
    slipVelBoostStart/Full/Max  Gated |lastSlip| longComp boost (burnout/lock).
    pressurePerfectHalf / NormalUnder / NormalOver
                          Ratio bands for CalcPressureGripScales (asymmetric over).
    pressurePerfectBonus / MildBase / MildSens
                          Perfect-zone bonus + mild-edge penalty vs pressureSensitivity.

  WEAR / SURFACE DAMAGE
    wearRate            Base structural wear rate.
    coldWearMult        Wear multiplier when well below opt.
    hotWearMult         Wear multiplier when above opt.
    grainTempRatio      Graining starts below opt × this (e.g. 0.75).
    blisterTempRatio    Blistering starts above opt × this (e.g. 1.55).

  Runtime-only (not in DEFAULT_MODS tables):
    descriptor          UI label set by getInterpolatedProfile().
  ========================================================================
]]
-- PHYSICAL FALLBACK DEFAULTS (Used to protect custom modded profiles missing keys)
local DEFAULT_MODS = {
    adhesion = 0.45, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
    casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
    gripMultiplier = 1.00, longGripMult = 1.0, latGripMult = 1.0, loadSensitivity = 0.04,
    optimalPressure = 32, optimalTemp = 65, pressureSensitivity = 0.5, rollingRes = 0.8,
    staticCoolingRate = 0.08, slipHeatRate = 8.925, workHeatRate = 5.1, wearRate = 0.0005,
    treadInertia = 0.46, carcassInertia = 0.75, airThermalInertia = 0.22, thermalReactionRate = 1.35,
    tempPlateau = 15, coldWidth = 55, hotWidth = 55, gripFloor = 0.24,
    coldWearMult = 1.8, hotWearMult = 3.5, grainTempRatio = 0.75, blisterTempRatio = 1.55,
    waterDrainage = 0.8, wetGripScale = 1.0, dryGripScale = 1.0, trackConductivityMult = 1.0,
    camberSensitivity = 1.0, bottomOutSensitivity = 1.0, scrubSensitivity = 1.0
}

-- Baseline grip polynomial coeffs: grip = a + x*(b + x*(c + x*d)) with x = condition 0–1.
-- Order matters: more specific tags BEFORE shorter substrings (sport_plus before sport).
local DEFAULT_GRIP_COEFFS = {
    { "sport_plus", { 1.12, 0.22, -0.08 } },  -- Semi-slick / track day peak ~1.26
    { "soft_slick", { 1.42, 0.34, -0.12 } },
    { "medium_slick", { 1.38, 0.32, -0.12 } },
    { "hard_slick", { 1.34, 0.30, -0.11 } },
    { "slick", { 1.38, 0.32, -0.12 } },       -- Generic slick / race
    { "sport", { 1.02, 0.16, -0.06 } },       -- Performance street peak ~1.12
    { "drag", { 1.28, 0.28, -0.10 } },        -- Drag slick-ish long bias (longGripMult stacks)
    { "drift", { 0.88, 0.12, -0.05 } },       -- Intentionally lower peak
    { "rain", { 0.96, 0.14, -0.05 } },        -- Wet specialist; wetGripScale stacks
    { "rally", { 0.98, 0.14, -0.05 } },
    { "winter", { 0.90, 0.12, -0.04 } },
    { "paddle", { 0.70, 0.08, -0.02 } },
    { "donut", { 0.68, 0.08, -0.03 } },       -- Spare / space-saver
    { "mudterrain", { 0.76, 0.08, -0.02 } },
    { "allterrain", { 0.82, 0.10, -0.03 } },
    { "crawler", { 0.72, 0.06, -0.02 } },
    { "vintage", { 0.88, 0.11, -0.04 } },  -- Bias/classic radial peak ~0.95 (~91–96% of standard after gripMult)
    { "utility", { 0.84, 0.08, -0.02 } },
    { "truck", { 0.86, 0.08, -0.02 } },
    { "heavy", { 0.84, 0.08, -0.02 } },       -- heavy_duty / heavy_offroad
    { "standard", { 0.92, 0.12, -0.04 } },    -- Passenger
    { "utv", { 0.78, 0.08, -0.02 } },
}

local GRIP_COEFFS = _G.GRIP_COEFFS
if not GRIP_COEFFS or #GRIP_COEFFS == 0 then
    GRIP_COEFFS = DEFAULT_GRIP_COEFFS
end

-- STANDALONE OVERRIDES (With pre-calculated absolute physical rates and suspension sensitivities)
local STANDALONE_MODIFIERS = {
    drag = {
        adhesion = 0.58, airConductionRate = 0.018, airCoolingRate = 0.0175, brakeGainRate = 1.5,
        casingCompliance = 0.85, coreCoolRate = 0.021, coreVelCoolRate = 0.004, skinCoreConductance = 0.12,
        gripMultiplier = 1.18, longGripMult = 1.12, latGripMult = 0.92, loadSensitivity = 0.055,
        optimalPressure = 16, optimalTemp = 72, pressureSensitivity = 0.35, rollingRes = 1.55,
        staticCoolingRate = 0.08, slipHeatRate = 16.2, workHeatRate = 6.6, wearRate = 0.0018,
        treadInertia = 0.231, carcassInertia = 0.374, thermalReactionRate = 2.1, tempPlateau = 12,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 2.01,
        hotWearMult = 4.2, grainTempRatio = 0.78, blisterTempRatio = 1.48, waterDrainage = 0.1,
        wetGripScale = 0.72, dryGripScale = 1.08, trackConductivityMult = 1.15, camberSensitivity = 1.4,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.5
    },
    drift = {
        adhesion = 0.48, airConductionRate = 0.015, airCoolingRate = 0.0225, brakeGainRate = 1.2,
        casingCompliance = 0.4, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.094,
        gripMultiplier = 0.88, longGripMult = 0.95, latGripMult = 0.92, loadSensitivity = 0.05,
        optimalPressure = 26, optimalTemp = 75, pressureSensitivity = 0.35, rollingRes = 1.02,
        staticCoolingRate = 0.08, slipHeatRate = 10.0, workHeatRate = 3.6, wearRate = 0.002,
        treadInertia = 0.40, carcassInertia = 0.648, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 65, hotWidth = 65, gripFloor = 0.28, coldWearMult = 1.86,
        hotWearMult = 4.5, grainTempRatio = 0.78, blisterTempRatio = 1.80, waterDrainage = 0.4,
        wetGripScale = 0.95, dryGripScale = 1, trackConductivityMult = 1.15, camberSensitivity = 0.9,
        bottomOutSensitivity = 1, scrubSensitivity = 1.3
    },
    vintage = {
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.94, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.042,
        optimalPressure = 30, optimalTemp = 58, pressureSensitivity = 0.45, rollingRes = 0.78,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 7.2, wearRate = 0.0004,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1.4
    },
    crawler = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.85, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 9, optimalTemp = 48, pressureSensitivity = 0.18, rollingRes = 1.65,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.9, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 1,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    },
    paddle = {
        adhesion = 0.25, airConductionRate = 0.012, airCoolingRate = 0.0375, brakeGainRate = 0.45,
        casingCompliance = 0.8, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.04,
        gripMultiplier = 0.74, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.028,
        optimalPressure = 10, optimalTemp = 48, pressureSensitivity = 0.22, rollingRes = 1.95,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.6, wearRate = 0.0008,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.62,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    },
    truck = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.0325, brakeGainRate = 0.225,
        casingCompliance = 0.12, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.014,
        optimalPressure = 100, optimalTemp = 65, pressureSensitivity = 0.15, rollingRes = 0.65,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 2.7, wearRate = 0.00008,
        treadInertia = 1.89, carcassInertia = 3.06, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.832, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.8, scrubSensitivity = 1.2
    },
    truck_offroad = {
        adhesion = 0.32, airConductionRate = 0.009, airCoolingRate = 0.0375, brakeGainRate = 0.225,
        casingCompliance = 0.18, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.036,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 85, optimalTemp = 60, pressureSensitivity = 0.1, rollingRes = 0.9,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.00012,
        treadInertia = 2.016, carcassInertia = 3.264, thermalReactionRate = 1.25, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.848, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 1, camberSensitivity = 0.6,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1
    },
    heavy_duty = {
        adhesion = 0.38, airConductionRate = 0.0105, airCoolingRate = 0.03, brakeGainRate = 0.45,
        casingCompliance = 0.15, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.052,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 85, optimalTemp = 65, pressureSensitivity = 0.25, rollingRes = 0.8,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 1.008, carcassInertia = 1.632, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.75,
        wetGripScale = 1.038, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.7, scrubSensitivity = 1.2
    },
    light_truck_std = {
        adhesion = 0.42, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.6,
        casingCompliance = 0.35, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.028,
        optimalPressure = 38, optimalTemp = 62, pressureSensitivity = 0.35, rollingRes = 0.95,
        staticCoolingRate = 0.08, slipHeatRate = 8.4, workHeatRate = 4.8, wearRate = 0.0004,
        treadInertia = 0.504, carcassInertia = 0.816, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.8,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.9,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.1
    },
    light_truck_hd = {
        adhesion = 0.4, airConductionRate = 0.012, airCoolingRate = 0.02875, brakeGainRate = 0.525,
        casingCompliance = 0.25, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.06,
        gripMultiplier = 0.88, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 60, optimalTemp = 65, pressureSensitivity = 0.3, rollingRes = 0.85,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 4.2, wearRate = 0.00025,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 1.1, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 2.9, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1.1
    },
    winter = {
        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.86, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.035,
        optimalPressure = 32, optimalTemp = 38, pressureSensitivity = 0.35, rollingRes = 0.95,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 4.2, wearRate = 0.0008,
        treadInertia = 0.462, carcassInertia = 0.748, thermalReactionRate = 1.35, tempPlateau = 16,
        coldWidth = 42, hotWidth = 40, gripFloor = 0.28, coldWearMult = 1.8,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.1, dryGripScale = 0.9, trackConductivityMult = 1, camberSensitivity = 1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.2
    },
    donut = {
        adhesion = 0.3, airConductionRate = 0.0165, airCoolingRate = 0.03, brakeGainRate = 1.2,
        casingCompliance = 0.45, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.064,
        gripMultiplier = 0.68, longGripMult = 0.95, latGripMult = 0.88, loadSensitivity = 0.06,
        optimalPressure = 60, optimalTemp = 60, pressureSensitivity = 0.5, rollingRes = 0.6,
        staticCoolingRate = 0.08, slipHeatRate = 11.5, workHeatRate = 6.6, wearRate = 0.002,
        treadInertia = 0.252, carcassInertia = 0.408, thermalReactionRate = 1.5, tempPlateau = 14,
        coldWidth = 55, hotWidth = 55, gripFloor = 0.22, coldWearMult = 1.68,
        hotWearMult = 4.5, grainTempRatio = 0.75, blisterTempRatio = 1.58, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 1.2,
        bottomOutSensitivity = 1.5, scrubSensitivity = 1.3
    },
    rally = {
        adhesion = 0.45, airConductionRate = 0.015, airCoolingRate = 0.0275, brakeGainRate = 1.05,
        casingCompliance = 0.55, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.08,
        -- latGripMult: mild turn-in bite (clog still hits both axes via tyreGrip; loose bias does the rest)
        gripMultiplier = 0.96, longGripMult = 1, latGripMult = 1.06, loadSensitivity = 0.038,
        optimalPressure = 28, optimalTemp = 68, pressureSensitivity = 0.38, rollingRes = 1.12,
        staticCoolingRate = 0.08, slipHeatRate = 9.45, workHeatRate = 5.1, wearRate = 0.0006,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.65, tempPlateau = 16,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 1.83,
        hotWearMult = 3.04, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.75,
        wetGripScale = 1.038, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1
    },
    rain = {
        adhesion = 0.50, airConductionRate = 0.0165, airCoolingRate = 0.035, brakeGainRate = 1.35,
        casingCompliance = 0.5, coreCoolRate = 0.042, coreVelCoolRate = 0.0096, skinCoreConductance = 0.094,
        gripMultiplier = 0.90, longGripMult = 1.02, latGripMult = 1.05, loadSensitivity = 0.038,
        optimalPressure = 28, optimalTemp = 58, pressureSensitivity = 0.7, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 9.9, workHeatRate = 5.4, wearRate = 0.0008,
        treadInertia = 0.315, carcassInertia = 0.51, thermalReactionRate = 1.65, tempPlateau = 15,
        coldWidth = 62, hotWidth = 55, gripFloor = 0.28, coldWearMult = 1.92,
        hotWearMult = 3.12, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.22, dryGripScale = 0.92, trackConductivityMult = 1, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.4
    }
}

-- CONTINUOUS MECHANICAL TREAD SPECTRUM: Aligned perfectly with native JBeam values
local PROFILE_POINTS = {
    { tread = 0.30, profile = "sport_plus", mods = {
        -- v7: tiny mechanical μ bump after Scintilla Belasco v6 retest ("a bit more grip").
        -- gm+dry only; lat held 0.97 (not tippier); loadSens unchanged; ~+2% μ at treadCoef 0.4 blend.
        adhesion = 0.52, airConductionRate = 0.015, airCoolingRate = 0.029, brakeGainRate = 1.35,
        casingCompliance = 0.45, coreCoolRate = 0.038, coreVelCoolRate = 0.0095, skinCoreConductance = 0.088,
        gripMultiplier = 1.02, longGripMult = 1.0, latGripMult = 0.97, loadSensitivity = 0.078,
        optimalPressure = 31, optimalTemp = 76, pressureSensitivity = 0.75, rollingRes = 0.70,
        staticCoolingRate = 0.095, slipHeatRate = 8.2, workHeatRate = 3.8, wearRate = 0.0006,
        treadInertia = 0.441, carcassInertia = 0.714, thermalReactionRate = 1.3, tempPlateau = 14,
        coldWidth = 52, hotWidth = 50, gripFloor = 0.24, coldWearMult = 1.908,
        hotWearMult = 4.44, grainTempRatio = 0.78, blisterTempRatio = 1.50, waterDrainage = 0.58,
        wetGripScale = 0.995, dryGripScale = 1.02, trackConductivityMult = 1.15, camberSensitivity = 1.1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.15
    } },
    { tread = 0.50, profile = "sport", mods = {
        -- v6: medium mechanical μ bump (mirror sport_plus v6→v7 step; Kingsnake continuum ~0.50).
        -- gm+dry +0.02; lat held 1.0 (felt good); loadSens eased slightly; blend@0.4 still coherent.
        adhesion = 0.42, airConductionRate = 0.015, airCoolingRate = 0.024, brakeGainRate = 1.2,
        casingCompliance = 0.5, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.076,
        gripMultiplier = 1.00, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.036,
        optimalPressure = 33, optimalTemp = 66, pressureSensitivity = 0.55, rollingRes = 0.82,
        staticCoolingRate = 0.073, slipHeatRate = 9.2, workHeatRate = 5.3, wearRate = 0.00045,
        treadInertia = 0.483, carcassInertia = 0.782, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 74, hotWidth = 55, gripFloor = 0.34, coldWearMult = 1.83,
        hotWearMult = 2.98, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.72,
        wetGripScale = 1.03, dryGripScale = 1.02, trackConductivityMult = 1, camberSensitivity = 1,
        bottomOutSensitivity = 1, scrubSensitivity = 1.1
    } },
    { tread = 0.70, profile = "standard", mods = {
        adhesion = 0.4, airConductionRate = 0.0135, airCoolingRate = 0.0275, brakeGainRate = 0.9,
        casingCompliance = 0.6, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.068,
        gripMultiplier = 0.96, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.035,
        optimalPressure = 33, optimalTemp = 60, pressureSensitivity = 0.45, rollingRes = 0.82,
        staticCoolingRate = 0.08, slipHeatRate = 8.4, workHeatRate = 5.1, wearRate = 0.0005,
        treadInertia = 0.504, carcassInertia = 0.816, thermalReactionRate = 1.25, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 3, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.9,
        bottomOutSensitivity = 1, scrubSensitivity = 1
    } },
    { tread = 0.80, profile = "allterrain", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.0325, brakeGainRate = 0.45,
        casingCompliance = 0.75, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.056,
        gripMultiplier = 0.86, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.03,
        optimalPressure = 30, optimalTemp = 56, pressureSensitivity = 0.35, rollingRes = 1.18,
        staticCoolingRate = 0.08, slipHeatRate = 7.2, workHeatRate = 4.5, wearRate = 0.00025,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.05, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.9, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 0.7, scrubSensitivity = 0.9
    } },
    { tread = 0.90, profile = "mudterrain", mods = {
        adhesion = 0.32, airConductionRate = 0.0105, airCoolingRate = 0.0375, brakeGainRate = 0.3,
        casingCompliance = 0.8, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.04,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 26, optimalTemp = 52, pressureSensitivity = 0.28, rollingRes = 1.42,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.9, wearRate = 0.0002,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.95, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.88, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 1.00, profile = "crawler", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.85, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 9, optimalTemp = 48, pressureSensitivity = 0.18, rollingRes = 1.7,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3.3, wearRate = 0.00015,
        treadInertia = 0.672, carcassInertia = 1.088, thermalReactionRate = 0.9, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.86, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 1,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

-- CONTINUOUS SLICK COMPOUND SPECTRUM: Chemically Decoupled Racing Compounds (Only Soft, Medium, Hard)
local SLICK_SPECTRUM_POINTS = {
    { softness = 0.50, profile = "hard_slick", mods = {
        adhesion = 0.48, airConductionRate = 0.015, airCoolingRate = 0.018, brakeGainRate = 1.5,
        casingCompliance = 0.3, coreCoolRate = 0.035, coreVelCoolRate = 0.008, skinCoreConductance = 0.088,
        gripMultiplier = 0.96, longGripMult = 1, latGripMult = 0.74, loadSensitivity = 0.11,
        optimalPressure = 28, optimalTemp = 90, pressureSensitivity = 0.95, rollingRes = 0.98,
        staticCoolingRate = 0.072, slipHeatRate = 9.7, workHeatRate = 5.8, wearRate = 0.0005,
        treadInertia = 0.4536, carcassInertia = 0.7344, thermalReactionRate = 1.25, tempPlateau = 14,
        coldWidth = 48, hotWidth = 48, gripFloor = 0.20, coldWearMult = 1.86,
        hotWearMult = 4.4, grainTempRatio = 0.78, blisterTempRatio = 1.50, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 1.15, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.55
    } },
    { softness = 0.65, profile = "medium_slick", mods = {
        adhesion = 0.52, airConductionRate = 0.0165, airCoolingRate = 0.02, brakeGainRate = 1.5,
        casingCompliance = 0.25, coreCoolRate = 0.028, coreVelCoolRate = 0.0064, skinCoreConductance = 0.104,
        gripMultiplier = 1.02, longGripMult = 1, latGripMult = 0.72, loadSensitivity = 0.12,
        optimalPressure = 27, optimalTemp = 84, pressureSensitivity = 1.05, rollingRes = 1.02,
        staticCoolingRate = 0.076, slipHeatRate = 10.4, workHeatRate = 6.1, wearRate = 0.0008,
        treadInertia = 0.399, carcassInertia = 0.646, thermalReactionRate = 1.42, tempPlateau = 14,
        coldWidth = 46, hotWidth = 46, gripFloor = 0.20, coldWearMult = 1.95,
        hotWearMult = 4.52, grainTempRatio = 0.78, blisterTempRatio = 1.50, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 1.15, camberSensitivity = 1.45,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1.65
    } },
    { softness = 0.80, profile = "soft_slick", mods = {
        adhesion = 0.55, airConductionRate = 0.01725, airCoolingRate = 0.02, brakeGainRate = 1.5,
        casingCompliance = 0.22, coreCoolRate = 0.028, coreVelCoolRate = 0.0068, skinCoreConductance = 0.116,
        gripMultiplier = 1.08, longGripMult = 1, latGripMult = 0.70, loadSensitivity = 0.13,
        optimalPressure = 26, optimalTemp = 78, pressureSensitivity = 1.2, rollingRes = 1.08,
        staticCoolingRate = 0.082, slipHeatRate = 11.6, workHeatRate = 6.4, wearRate = 0.0013,
        treadInertia = 0.3444, carcassInertia = 0.5576, thermalReactionRate = 1.55, tempPlateau = 14,
        coldWidth = 44, hotWidth = 44, gripFloor = 0.18, coldWearMult = 1.992,
        hotWearMult = 4.72, grainTempRatio = 0.78, blisterTempRatio = 1.50, waterDrainage = 0,
        wetGripScale = 0.72, dryGripScale = 0.98, trackConductivityMult = 1.15, camberSensitivity = 1.55,
        bottomOutSensitivity = 1.2, scrubSensitivity = 1.75
    } }
}

-- CONTINUOUS LIGHT & MEDIUM DUTY SPECTRUM: Heavy Pickups, Vans, and Utility Cargo Rigs
local UTILITY_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_utility_utility", mods = {
        adhesion = 0.4, airConductionRate = 0.01275, airCoolingRate = 0.02875, brakeGainRate = 0.6,
        casingCompliance = 0.3, coreCoolRate = 0.0403, coreVelCoolRate = 0.0092, skinCoreConductance = 0.064,
        gripMultiplier = 0.9, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.022,
        optimalPressure = 44, optimalTemp = 60, pressureSensitivity = 0.32, rollingRes = 0.84,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 4.2, wearRate = 0.00032,
        treadInertia = 0.588, carcassInertia = 0.952, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.77,
        hotWearMult = 2.928, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.3, scrubSensitivity = 1.1
    } },
    { tread = 0.70, profile = "allterrain_utility_utility", mods = {
        adhesion = 0.36, airConductionRate = 0.012, airCoolingRate = 0.03125, brakeGainRate = 0.525,
        casingCompliance = 0.35, coreCoolRate = 0.0438, coreVelCoolRate = 0.0092, skinCoreConductance = 0.056,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 36, optimalTemp = 56, pressureSensitivity = 0.28, rollingRes = 1.08,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 3.9, wearRate = 0.00022,
        treadInertia = 0.63, carcassInertia = 1.02, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.74,
        hotWearMult = 2.888, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.1, scrubSensitivity = 1
    } },
    { tread = 0.85, profile = "mudterrain_utility_utility", mods = {
        adhesion = 0.32, airConductionRate = 0.01125, airCoolingRate = 0.03375, brakeGainRate = 0.45,
        casingCompliance = 0.4, coreCoolRate = 0.0473, coreVelCoolRate = 0.0108, skinCoreConductance = 0.048,
        gripMultiplier = 0.8, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.026,
        optimalPressure = 28, optimalTemp = 52, pressureSensitivity = 0.22, rollingRes = 1.35,
        staticCoolingRate = 0.08, slipHeatRate = 6.51, workHeatRate = 3.6, wearRate = 0.00018,
        treadInertia = 0.714, carcassInertia = 1.156, thermalReactionRate = 1.2, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.872, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1, scrubSensitivity = 0.9
    } },
    { tread = 0.95, profile = "logger_utility_utility", mods = {
        adhesion = 0.3, airConductionRate = 0.0105, airCoolingRate = 0.03625, brakeGainRate = 0.375,
        casingCompliance = 0.45, coreCoolRate = 0.0508, coreVelCoolRate = 0.0116, skinCoreConductance = 0.04,
        gripMultiplier = 0.76, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.03,
        optimalPressure = 24, optimalTemp = 50, pressureSensitivity = 0.18, rollingRes = 1.55,
        staticCoolingRate = 0.08, slipHeatRate = 6.09, workHeatRate = 3.3, wearRate = 0.00014,
        treadInertia = 0.798, carcassInertia = 1.292, thermalReactionRate = 1.15, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.856, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.9, scrubSensitivity = 0.8
    } }
}

-- CONTINUOUS HEAVY-DUTY COMMERCIAL SPECTRUM: Peterbilts, Volvos, and Heavy Long-Haul Semis
local COMMERCIAL_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "highway_steer_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.03125, brakeGainRate = 0.225,
        casingCompliance = 0.12, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.011,
        optimalPressure = 105, optimalTemp = 62, pressureSensitivity = 0.1, rollingRes = 0.62,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 2.4, wearRate = 0.00006,
        treadInertia = 1.764, carcassInertia = 2.856, thermalReactionRate = 1.15, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.824, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.8, scrubSensitivity = 1.2
    } },
    { tread = 0.60, profile = "highway_trailer_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.00825, airCoolingRate = 0.0325, brakeGainRate = 0.15,
        casingCompliance = 0.1, coreCoolRate = 0.056, coreVelCoolRate = 0.0128, skinCoreConductance = 0.036,
        gripMultiplier = 0.78, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.01,
        optimalPressure = 110, optimalTemp = 62, pressureSensitivity = 0.09, rollingRes = 0.58,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 2.16, wearRate = 0.00005,
        treadInertia = 2.184, carcassInertia = 3.536, thermalReactionRate = 1.1, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.82, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.85,
        wetGripScale = 1.062, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 1.9, scrubSensitivity = 1.2
    } },
    { tread = 0.70, profile = "traction_drive_truck", mods = {
        adhesion = 0.35, airConductionRate = 0.009, airCoolingRate = 0.0325, brakeGainRate = 0.225,
        casingCompliance = 0.15, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.04,
        gripMultiplier = 0.82, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.014,
        optimalPressure = 95, optimalTemp = 62, pressureSensitivity = 0.13, rollingRes = 0.75,
        staticCoolingRate = 0.08, slipHeatRate = 7.875, workHeatRate = 2.7, wearRate = 0.00008,
        treadInertia = 1.89, carcassInertia = 3.06, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 2.832, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.8,
        bottomOutSensitivity = 1.7, scrubSensitivity = 1.2
    } },
    { tread = 0.90, profile = "heavy_offroad_truck", mods = {
        adhesion = 0.3, airConductionRate = 0.009, airCoolingRate = 0.0375, brakeGainRate = 0.225,
        casingCompliance = 0.18, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.036,
        gripMultiplier = 0.72, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.018,
        optimalPressure = 80, optimalTemp = 56, pressureSensitivity = 0.09, rollingRes = 1.05,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.00012,
        treadInertia = 2.016, carcassInertia = 3.264, thermalReactionRate = 1.25, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 2.848, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.6,
        bottomOutSensitivity = 1.4, scrubSensitivity = 1.1
    } }
}

-- CONTINUOUS LIGHTWEIGHT SXS & UTV SPECTRUM: Hardpack, All-Terrain, and Deep Offroad Flotation Lugs
local ATV_UTV_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "hardpack_utv_utv", mods = {
        adhesion = 0.35, airConductionRate = 0.012, airCoolingRate = 0.0375, brakeGainRate = 0.45,
        casingCompliance = 0.8, coreCoolRate = 0.0455, coreVelCoolRate = 0.0104, skinCoreConductance = 0.04,
        gripMultiplier = 0.84, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.055,
        optimalPressure = 14, optimalTemp = 55, pressureSensitivity = 0.25, rollingRes = 1.1,
        staticCoolingRate = 0.08, slipHeatRate = 6.825, workHeatRate = 3.6, wearRate = 0.0025,
        treadInertia = 0.336, carcassInertia = 0.544, thermalReactionRate = 1.65, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.8, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.8,
        wetGripScale = 1.05, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.6, scrubSensitivity = 0.8
    } },
    { tread = 0.70, profile = "allterrain_utv_utv", mods = {
        adhesion = 0.3, airConductionRate = 0.01125, airCoolingRate = 0.04, brakeGainRate = 0.375,
        casingCompliance = 0.85, coreCoolRate = 0.049, coreVelCoolRate = 0.0112, skinCoreConductance = 0.036,
        gripMultiplier = 0.8, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.06,
        optimalPressure = 10, optimalTemp = 50, pressureSensitivity = 0.2, rollingRes = 1.25,
        staticCoolingRate = 0.08, slipHeatRate = 6.3, workHeatRate = 3.3, wearRate = 0.0018,
        treadInertia = 0.378, carcassInertia = 0.612, thermalReactionRate = 1.5, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.68,
        hotWearMult = 3.52, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.9,
        wetGripScale = 1.12, dryGripScale = 1, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.8
    } },
    { tread = 0.85, profile = "mud_utv_utv", mods = {
        adhesion = 0.28, airConductionRate = 0.0105, airCoolingRate = 0.0425, brakeGainRate = 0.3,
        casingCompliance = 0.9, coreCoolRate = 0.0525, coreVelCoolRate = 0.012, skinCoreConductance = 0.032,
        gripMultiplier = 0.76, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.065,
        optimalPressure = 7, optimalTemp = 48, pressureSensitivity = 0.15, rollingRes = 1.4,
        staticCoolingRate = 0.08, slipHeatRate = 5.775, workHeatRate = 3, wearRate = 0.0014,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.35, tempPlateau = 18,
        coldWidth = 58, hotWidth = 50, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 3.36, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.95,
        wetGripScale = 1.12, dryGripScale = 0.94, trackConductivityMult = 0.75, camberSensitivity = 0.4,
        bottomOutSensitivity = 0.5, scrubSensitivity = 0.7
    } }
}

-- CONTINUOUS RETRO SPECTRUM: Flexible Cross-Ply Bias overlays up to Classic Radial Belts
local VINTAGE_SPECTRUM_POINTS = {
    { tread = 0.50, profile = "vintage_biasply_vintage", mods = {
        adhesion = 0.28, airConductionRate = 0.0135, airCoolingRate = 0.02375, brakeGainRate = 0.6,
        casingCompliance = 0.65, coreCoolRate = 0.0385, coreVelCoolRate = 0.0088, skinCoreConductance = 0.08,
        gripMultiplier = 0.92, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.042,
        optimalPressure = 24, optimalTemp = 56, pressureSensitivity = 0.45, rollingRes = 0.78,
        staticCoolingRate = 0.08, slipHeatRate = 7.35, workHeatRate = 7.2, wearRate = 0.0004,
        treadInertia = 0.42, carcassInertia = 0.68, thermalReactionRate = 1.2, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.65,
        hotWearMult = 2.96, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.5,
        wetGripScale = 0.975, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.5,
        bottomOutSensitivity = 0.8, scrubSensitivity = 1.4
    } },
    { tread = 0.65, profile = "classic_radial_vintage", mods = {
        adhesion = 0.35, airConductionRate = 0.01425, airCoolingRate = 0.02625, brakeGainRate = 0.75,
        casingCompliance = 0.55, coreCoolRate = 0.0368, coreVelCoolRate = 0.0084, skinCoreConductance = 0.072,
        gripMultiplier = 0.97, longGripMult = 1, latGripMult = 1, loadSensitivity = 0.038,
        optimalPressure = 30, optimalTemp = 60, pressureSensitivity = 0.42, rollingRes = 0.86,
        staticCoolingRate = 0.08, slipHeatRate = 8.4, workHeatRate = 5.4, wearRate = 0.00055,
        treadInertia = 0.462, carcassInertia = 0.748, thermalReactionRate = 1.35, tempPlateau = 16,
        coldWidth = 58, hotWidth = 55, gripFloor = 0.26, coldWearMult = 1.71,
        hotWearMult = 3.02, grainTempRatio = 0.75, blisterTempRatio = 1.55, waterDrainage = 0.7,
        wetGripScale = 1.025, dryGripScale = 1, trackConductivityMult = 1, camberSensitivity = 0.7,
        bottomOutSensitivity = 0.9, scrubSensitivity = 1.2
    } }
}

-- Module-level variables
local tyreGripTable = {}
local tyreData = {}
local wheelCache = {}
local baseBrakeCoolings = {} -- Native brakeTypeSurfaceCoolingCoef snapshot per wheel
local vehicleMass = 1500
local wheelCount = 4 -- Dynamically calculated in initTyreData
local waterFilmDepth = 0 -- 0..1 global film from rain (no native BeamNG film API)
-- Telemetry state packed (frees ~10 main-chunk locals for Lua 200-cap)
local telem = {
    csvEnabled = false,    -- Optional CSV dump (user can enable)
    interval = 1.0,        -- Seconds between samples when enabled
    armMarker = "mods/unpacked/Tire-Wear-and-Thermals-ReSpin-main/tools/TELEMETRY_CSV_ARMED",
    timer = 0,
    path = nil,
    csvBuffer = {},
    csvBufCount = 0,
    headerReady = false,
    lastFlushClock = 0,
    flushWallSec = 45,
    flushMaxLines = 200,
    csvHeader = "wall,t,wheel,cond,o,m,i,carcL,carcC,carcR,rim,air,psi,grip,longGrip,latGrip,clog,grain,blister,marbles,cycles,stint,leak,film\n",
}
local brakeDuctSettings = { DUCT_DEFAULT_PCT, DUCT_DEFAULT_PCT } -- Front, Rear (1..100%)
local lastDuctMailbox = nil

-- Pack-air / wake thermals (single table: frees ~19 main-chunk locals for Lua 200-cap):
--  Pre-0.39: LuuksDraftingMod mailbox/setDraftWake -> convection cut + ambient rise
--  0.39+: native core_interAero owns drag (setWindAero). We INFER wake from
--    airspeed vs airflowspeed and only add pack-air ambient (no convection cut).
local draft = {
    coolingReduction = 0.28,   -- max forced-convection cut (legacy companion only)
    airTempCap = 5.0,          -- safety cap (C)
    staleSec = 1.5,            -- decay if companion stops publishing
    nativeAirTempMax = 4.0,    -- pack-air rise at full inferred wake (C)
    inferMinSpeed = 8.0,       -- m/s - ignore crawl / garage
    inferDeadband = 0.04,      -- ignore small ambient-tailwind noise (frac of speed)
    inferDeadbandMin = 0.8,    -- m/s absolute floor on deadband
    inferRefFrac = 0.45,       -- deficit / (speed*this) -> wake 1.0
    inferSmooth = 2.5,         -- 1/s toward inferred target
    wake = 0, side = 0, push = 0,
    airTempDelta = 0,
    coolingWake = 0,
    lastRxClock = 0,
    lastMailbox = nil,
    hasNativeInterAero = false, -- obj.setWindAero present (0.39+)
    inferredWake = 0,           -- 0..1 from airspeed - airflowspeed
    convectionMult = 1.0,       -- applied in CalcTyreWear (1 = no companion cut)
    airTempEffective = 0,       -- ambient bump after native coexistence scale
}

-- Rolling tracker parameters to evaluate level environment profile fluctuations
local rawEnvMin = 100
local rawEnvMax = -100

-- Track Environment State Cache (reused to prevent GC overhead)
local trackEnv = { timeOfDay = 0.5, cloudCover = 0.2 }
-- One track-surface sample per GFX frame (CalcTyreWear runs ~4×/frame; tod/cloud are slow)
local frameTrackTemp = 21

-- High Performance Pre-allocated GUI Data Structures (Reduces GC allocations to 0 per frame)
local guiStream = { data = {} }
local wheelIndexMap = {}

-- Local Cache states to prevent constant pattern matching / deserialization overhead
local cachedVehicleType = nil
-- BeamNG asphalt-rally configs often mount *_race tires (treadCoef 0) while gravel uses *_rally.
-- Cache whether the fitted vehicle has non-cosmetic rally hardware so race slicks aren't mislabeled.
local cachedRallyHardware = nil
local lastTrackEnvMailbox = nil
local lastEnvMailbox = nil

-- Forward declarations of local functions to ensure proper lexical scope and prevent global lookup errors
local sanitizeEnvTemp
local GetGroundModelData
local setGroundModels
local CalcBiasWeights
local CalcPressureGripScales
local ensureTempNodes
local TempRingsToAvgTemp
local TempCarcassToAvgTemp
local EffectiveTyreTemp
local getWheelJBeamData
local collectBaseWheelFactors
local getNativeBrakeTemps
local getFreestreamAirspeed
local updateWheelSuspension
local tempDistToWearMult
local getTrackTemp
local getTirePartName
local vehicleHasRallyHardware
local getVehicleType
local getInterpolatedProfile
local initTyreData
local CalcTyreWear
local getProfileBaselineGrip
local CalculateTyreGrip
local classifySurfaceGrip
local getSurfaceSanityScale
local fillSurfaceFlags
local resolveWheelSurface
local surfaceFlagsFromType
local applyProfileSurfaceBias
local initGuiStream
local update
local updateGFX
local prepareWheelFrame
local runFixedPhysicsSteps
local flushGuiStream
local writeTelemetryIfEnabled
local onInit
local onReset
local onSettingsChanged
local calculateWheelAlignment
local applySafeForce
local interpolateSpectrum
local copyMods
local normalizeProfileMods
local getProfileThermalGrip
local getBrakeDuctPercent
local ductPercentToFactors
local getVehicleAirspeedRef
local refreshDraftCompat
local updateInferredNativeWake
local setDraftWake
local decayDraftWake
local deflateTireCompat
local applyPressureLeakPa
local applyWheelFriction
local isSpareOrAccessoryTireName
local getTelemetryIo
local ensureTelemetryHeader
local clearTelemetryCsvBuffer
local flushTelemetryBuffer
local telemetryBufferNeedsFlush
local writeTelemetryArmMarker
local clearTelemetryArmMarker
local appendTelemetryResetMarker
local restoreTelemetryAfterReload
local onDeserialized
local onExtensionUnloaded

-- Dynamic Spectrum Interpolator Helper (0-Allocation In-Place Table Updates)
interpolateSpectrum = function(spectrum, searchKey, value, targetTable)
    local p1, p2
    value = tonumber(value) or 0
    if value ~= value then value = 0 end -- Safe NaN check
    
    -- Safety Check bounds immediately before search sequence
    if value < spectrum[1][searchKey] then
        p1 = spectrum[1]
        p2 = spectrum[2] or spectrum[1]
    elseif value > spectrum[#spectrum][searchKey] then
        p1 = spectrum[#spectrum - 1] or spectrum[1]
        p2 = spectrum[#spectrum]
    else
        for i = 1, #spectrum - 1 do
            if value >= spectrum[i][searchKey] and value <= spectrum[i + 1][searchKey] then
                p1 = spectrum[i]
                p2 = spectrum[i + 1]
                break
            end
        end
    end
    
    p1 = p1 or spectrum[1]
    p2 = p2 or spectrum[2] or spectrum[1]
    
    local diff = p2[searchKey] - p1[searchKey]
    local factor = 0
    if diff > 0 then
        -- Safe clamp factors to bounds (prevents extrapolation issues)
        factor = max(0, min(1, (value - p1[searchKey]) / diff))
    end
    
    -- Clear key space in targetTable to perform allocation-free updates
    for k in pairs(targetTable) do
        targetTable[k] = nil
    end
    
    -- Merge and interpolate metrics
    for k, v1 in pairs(p1.mods) do
        local v2 = p2.mods[k]
        targetTable[k] = v2 and lerp(v1, v2, factor) or v1
    end
    for k, v2 in pairs(p2.mods) do
        if targetTable[k] == nil then targetTable[k] = v2 end
    end
    
    return p1.profile, p2.profile, factor
end

-- Helper to safely clear and copy table values in-place without allocations
copyMods = function(src, target)
    local t = target or {}
    for k in pairs(t) do t[k] = nil end
    for k, v in pairs(src) do t[k] = v end
    return t
end

-- Migrates legacy profile keys and fills missing high-value knobs (keeps spectrum interpolation stable)
normalizeProfileMods = function(mods)
    if type(mods) ~= "table" then return mods end

    -- Merge dual conductance into single skinCoreConductance
    if mods.skinCoreConductance == nil then
        local a = mods.skinToCoreRate
        local b = mods.coreToSkinRate
        if a or b then
            mods.skinCoreConductance = ((a or b or 0.068) + (b or a or 0.068)) * 0.5
        else
            mods.skinCoreConductance = DEFAULT_MODS.skinCoreConductance
        end
    end
    mods.skinToCoreRate = nil
    mods.coreToSkinRate = nil
    mods.coreReactionRate = nil -- global CORE_REACTION_RATE

    -- Split thermalInertia into tread/carcass masses
    if mods.treadInertia == nil or mods.carcassInertia == nil then
        local ti = mods.thermalInertia or ((mods.treadInertia or DEFAULT_MODS.treadInertia) / 0.42)
        if mods.treadInertia == nil then mods.treadInertia = ti * 0.42 end
        if mods.carcassInertia == nil then mods.carcassInertia = ti * 0.68 end
    end
    mods.thermalInertia = nil

    -- Fill any missing new-schema keys from defaults (interpolated tables already have them)
    for k, v in pairs(DEFAULT_MODS) do
        if mods[k] == nil then mods[k] = v end
    end
    return mods
end

-- Plateau-Gaussian thermal grip from profile knobs (single source of truth with optimalTemp)
-- Cold side uses a softer exponent so street/sport compounds are not cliffed below ~40C.
getProfileThermalGrip = function(mods, temp, compliance, softness)
    temp = temp or 21
    compliance = compliance or 0.5
    softness = softness or 0.5
    local tOpt = mods.optimalTemp or DEFAULT_MODS.optimalTemp
    local plateau = (mods.tempPlateau or DEFAULT_MODS.tempPlateau) * (0.8 + 0.4 * softness)
    local wCold = (mods.coldWidth or DEFAULT_MODS.coldWidth) * (0.8 + 0.4 * softness) * (1.0 + (compliance - 0.5) * 0.15)
    local wHot = (mods.hotWidth or DEFAULT_MODS.hotWidth) * (0.8 + 0.4 * softness)
    local floor = mods.gripFloor or DEFAULT_MODS.gripFloor
    local diff = abs(temp - tOpt)
    local excess = max(0.0, diff - plateau)
    local width = (temp < tOpt) and wCold or wHot
    -- Cold: gentler roll-off (1.35); hot: keep sharper cliff (2.0) for overheat
    local power = (temp < tOpt) and 1.35 or 2.0
    local decay = exp(-((excess / max(1.0, width)) ^ power))
    return floor + (1.0 - floor) * decay
end

-- Cleanly filters ambient temperature. BeamNG native env is Kelvin; mailboxes are usually Celsius.
-- Never silently treat hot desert Celsius (e.g. 48C) as Fahrenheit.
sanitizeEnvTemp = function(rawTemp)
    if not rawTemp then return 21 end
    local temp = tonumber(rawTemp) or 21
    -- Kelvin from obj:getEnvTemperature or GE absolute scale
    if temp > 180 then
        temp = temp - 273.15
    end
    return max(-40, min(60, temp))
end

local DOESNT_EXIST_DATA = { name = "DOESNT EXIST", nameLower = "doesnt exist", staticFrictionCoefficient = 1, slidingFrictionCoefficient = 1 }

GetGroundModelData = function(id)
    if not id then return "DOESNT EXIST", DOESNT_EXIST_DATA end
    if groundModelsLut[id] then return groundModelsLut[id].name, groundModelsLut[id] end

    local materials = (particles and type(particles.getMaterialsParticlesTable) == "function") and particles.getMaterialsParticlesTable() or {}
    local matData = materials[id] or materials[id + 1] or {}
    local name = matData.name or "DOESNT EXIST"
    
    local rawData = groundModels[name] or { staticFrictionCoefficient = 1, slidingFrictionCoefficient = 1 }
    local data = {
        name = name,
        nameLower = string.lower(name),
        staticFrictionCoefficient = rawData.staticFrictionCoefficient or 1,
        slidingFrictionCoefficient = rawData.slidingFrictionCoefficient or 1,
        strength = rawData.strength,
        rough = rawData.roughnessCoefficient or rawData.rough,
        fluidDensity = rawData.fluidDensity,
        stribeckVelocity = rawData.stribeckVelocity or rawData.stribeckVel or 1,
        defaultDepth = rawData.defaultDepth or 0
    }
    
    groundModelsLut[id] = data
    return name, data
end

setGroundModels = function(data)
    groundModels = data or {}
    groundModelsLut = {} -- Invalidate LUT cache to force evaluation under the new environment
end

CalcBiasWeights = function(loadBias, pressureRatio)
    local dampedBias = loadBias * 0.40
    local weightLeft = max(0.15, -0.75 * dampedBias + 1)
    local weightRight = max(0.15, 0.75 * dampedBias + 1)
    
    local loadBiasSq = dampedBias * dampedBias
    local weightCenter = (loadBiasSq < 1e-5) and 1 or max(0, -1 / (1 + 5 / loadBiasSq) + 1)
    
    -- Under-inflation expands footprint to outer shoulders (concave structural collapsing)
    -- Over-inflation balloons tire centerline (crown bulging)
    if pressureRatio < 1.0 then
        local underInfFactor = (1.0 - pressureRatio) * 0.40
        weightLeft = weightLeft * (1.0 + underInfFactor)
        weightRight = weightRight * (1.0 + underInfFactor)
        weightCenter = weightCenter * max(0.3, 1.0 - underInfFactor * 1.5)
    elseif pressureRatio > 1.0 then
        local overInfFactor = min(1.0, pressureRatio - 1.0) * 0.30
        weightLeft = weightLeft * max(0.4, 1.0 - overInfFactor * 1.2)
        weightRight = weightRight * max(0.4, 1.0 - overInfFactor * 1.2)
        weightCenter = weightCenter * (1.0 + overInfFactor * 1.5)
    end
    
    local weightSum = weightLeft + weightCenter + weightRight
    if weightSum <= 0 then weightSum = 1 end
    return weightLeft / weightSum, weightCenter / weightSum, weightRight / weightSum
end

-- Three-band pressure→grip: perfect bonus, wide mild normal (asymmetric over), progressive outer.
-- pOffset = currentPSI/optimalPressure - 1. Returns longScale, latScale.
CalcPressureGripScales = function(pOffset, sensitivity, isLooseSurface)
    local sens = max(0.05, sensitivity or 0.5)
    if isLooseSurface then
        -- Loose: keep under-inflation flotation; over uses same banded outer as paved
        if pOffset < 0 then
            local progress = -pOffset
            local flotationGripBonus = 1.0 + 0.15 * sin(progress * pi)
            local latPressureScale = flotationGripBonus * max(0.70, 1.0 - 0.35 * (progress * progress))
            return flotationGripBonus, latPressureScale
        end
    end

    local tb = THERMAL_TOPOLOGY
    local perfectHalf = tb.pressurePerfectHalf or 0.04
    local normalUnder = tb.pressureNormalUnder or 0.14
    local normalOver = tb.pressureNormalOver or 0.32
    local perfectBonus = tb.pressurePerfectBonus or 0.020
    local mildMax = (tb.pressureMildBase or 0.028) + (tb.pressureMildSens or 0.022) * sens
    local ao = abs(pOffset)

    if ao <= perfectHalf then
        local t = 1.0 - ao / max(1e-6, perfectHalf)
        local s = 1.0 + perfectBonus * t * t
        return s, s
    end

    if pOffset < 0 then
        if pOffset >= -normalUnder then
            local t = (-pOffset - perfectHalf) / max(1e-6, normalUnder - perfectHalf)
            local lat = 1.0 - mildMax * t * 1.15
            local long = 1.0 - mildMax * t * 0.55
            return long, lat
        end
        local excess = -pOffset - normalUnder
        local edgeLat = 1.0 - mildMax * 1.15
        local edgeLong = 1.0 - mildMax * 0.55
        local den = 1.0 + sens * 1.5 * (excess * excess + 1.8 * excess * excess * excess)
        return max(0.30, edgeLong / den), max(0.15, edgeLat / den)
    end

    if pOffset <= normalOver then
        local t = (pOffset - perfectHalf) / max(1e-6, normalOver - perfectHalf)
        -- Soft ramp across the wide stock-friendly over band
        local pen = 1.0 - mildMax * (t ^ 1.15)
        return pen, pen
    end

    local excess = pOffset - normalOver
    local edge = 1.0 - mildMax
    local den = 1.0 + sens * 1.5 * (excess * excess + 2.4 * excess * excess * excess)
    local pen = max(0.35, edge / den)
    return pen, pen
end

-- Migrate legacy 5-node tables (skin×3, core, air) → 8-node in place
ensureTempNodes = function(temps, envTemp)
    envTemp = envTemp or ENV_TEMP
    if type(temps) ~= "table" then
        return { envTemp, envTemp, envTemp, envTemp, envTemp, envTemp, envTemp, envTemp }
    end
    if temps[8] ~= nil then
        for i = 1, TEMP_NODE_COUNT do
            temps[i] = temps[i] or envTemp
        end
        return temps
    end
    -- Legacy: [1..3]=skin, [4]=single carcass, [5]=air
    local core = temps[4] or envTemp
    local air = temps[5] or envTemp
    temps[1] = temps[1] or envTemp
    temps[2] = temps[2] or envTemp
    temps[3] = temps[3] or envTemp
    temps[4], temps[5], temps[6] = core, core, core
    temps[7] = core
    temps[8] = air
    return temps
end

TempRingsToAvgTemp = function(temps, loadBias, pressureRatio, localEnvTemp)
    local fallbackEnv = localEnvTemp or ENV_TEMP
    if not temps then return fallbackEnv end
    local wLeft, wCenter, wRight = CalcBiasWeights(loadBias, pressureRatio)
    return (temps[1] or fallbackEnv) * wLeft + (temps[2] or fallbackEnv) * wCenter + (temps[3] or fallbackEnv) * wRight
end

TempCarcassToAvgTemp = function(temps, loadBias, pressureRatio, localEnvTemp)
    local fallbackEnv = localEnvTemp or ENV_TEMP
    if not temps then return fallbackEnv end
    local wLeft, wCenter, wRight = CalcBiasWeights(loadBias, pressureRatio)
    return (temps[4] or fallbackEnv) * wLeft + (temps[5] or fallbackEnv) * wCenter + (temps[6] or fallbackEnv) * wRight
end

-- Skin-led grip thermometer with carcass lag; cold → more carcass weight (P2)
EffectiveTyreTemp = function(temps, loadBias, pressureRatio, localEnvTemp, mods)
    local skin = TempRingsToAvgTemp(temps, loadBias, pressureRatio, localEnvTemp)
    local carcass = TempCarcassToAvgTemp(temps, loadBias, pressureRatio, localEnvTemp)
    local topo = THERMAL_TOPOLOGY
    local blend = topo.gripBlendWarm
    if mods then
        local tOpt = mods.optimalTemp or WORKING_TEMP
        local coldW = max(15.0, mods.coldWidth or DEFAULT_MODS.coldWidth)
        -- 0 at/above opt, 1 when skin is ~0.65·coldWidth below opt
        local coldness = max(0.0, min(1.0, (tOpt - skin) / (coldW * 0.65)))
        coldness = coldness * coldness * (3.0 - 2.0 * coldness) -- smoothstep
        blend = lerp(topo.gripBlendWarm, topo.gripBlendCold, coldness)
    end
    return skin * (1.0 - blend) + carcass * blend
end

tempDistToWearMult = function(tempDist)
    return -1.8 / (1 + 0.01 * (tempDist * (tempDist or 1))) + 2.8
end

-- Track surface temperature: asphalt often runs well above air in sun (+20–35C typical)
getTrackTemp = function(envTemp, tod, cloudCover)
    tod = tod or 0.5
    if tod > 1.0 then tod = tod / 24.0 end
    
    local solarAngleFactor = max(0, cos((tod - 0.5) * 2 * pi))
    local cloudScale = max(0, min(1, cloudCover or 0.2))
    
    -- Sol-air style gain: up to ~32C above ambient under clear midday sun
    local solarGain = solarAngleFactor * (1.0 - cloudScale * 0.85) * 32.0
    
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    if isRaining or waterFilmDepth > 0.35 then
        -- Wet asphalt stays near ambient (evaporative cooling)
        return envTemp + solarGain * 0.15 - 1.5
    end
    
    local nightCooling = (1.0 - solarAngleFactor) * 6.0
    return envTemp + solarGain - nightCooling
end

-- Tuning-menu brake duct opening (1%=closed / stock, 100%=fully open)
-- Source priority: mailbox from GE createbrakeductsliders → v.data.variables → default
getBrakeDuctPercent = function(isFront)
    local idx = isFront and 1 or 2
    local key = isFront and "$WheelCoolingDuctFront" or "$WheelCoolingDuctRear"
    if v and v.data and type(v.data.variables) == "table" then
        local var = v.data.variables[key]
        if type(var) == "table" and var.val ~= nil then
            local n = tonumber(var.val)
            if n then return max(1, min(100, n)) end
        end
    end
    local fromMailbox = brakeDuctSettings[idx]
    if type(fromMailbox) == "number" then
        return max(1, min(100, fromMailbox))
    end
    return DUCT_DEFAULT_PCT
end

-- Maps duct % to cooling multipliers for tyre thermals (and native brake coef)
ductPercentToFactors = function(ductPct)
    local open = max(0, min(1, (ductPct - 1) / 99)) -- 1→0, 100→1
    local airFactor = lerp(1.0, MAX_DUCT_AIR_FACTOR, open)
    -- Open ducts reduce brake→tyre conduction soak slightly (more air over rotor)
    local conductionFactor = lerp(1.15, 0.85, open)
    return airFactor, conductionFactor, open
end

-- Raw pressureWheels / rotators JBeam row for this wheel
getWheelJBeamData = function(wd)
    if not wd or not v or not v.data or type(v.data.wheels) ~= "table" then return nil end
    local row = v.data.wheels[wd.cid]
    if type(row) == "table" then return row end
    if wd.wheelID ~= nil then
        row = v.data.wheels[wd.wheelID]
        if type(row) == "table" then return row end
    end
    return nil
end

-- One-shot cache of stock BeamNG tyre/brake construction factors
collectBaseWheelFactors = function(wd)
    local jb = getWheelJBeamData(wd) or {}
    local frictionCoef = tonumber(wd.frictionCoef) or tonumber(jb.frictionCoef) or 1.0
    local slidingFrictionCoef = tonumber(wd.slidingFrictionCoef) or tonumber(jb.slidingFrictionCoef) or frictionCoef
    local noLoadCoef = tonumber(wd.noLoadCoef) or tonumber(jb.noLoadCoef) or 1.0
    local fullLoadCoef = tonumber(wd.fullLoadCoef) or tonumber(jb.fullLoadCoef) or 1.0
    local loadSensSlope = tonumber(wd.loadSensitivitySlope) or tonumber(jb.loadSensitivitySlope) or 0.00015
    local dragCoef = tonumber(wd.dragCoef) or tonumber(jb.dragCoef) or 5.0
    local tireWidth = tonumber(wd.tireWidth) or tonumber(jb.tireWidth) or tonumber(wd.width) or 0.2
    local radius = tonumber(wd.radius) or tonumber(jb.radius) or 0.3
    local hubRadius = tonumber(wd.hubRadius) or tonumber(jb.hubRadius) or (radius * 0.65)

    -- Mass: prefer explicit tire/hub totals, else node weights × ray count estimate
    local rayCount = tonumber(wd.rayCount) or tonumber(jb.numRays) or 16
    local tireNodeW = tonumber(jb.nodeWeight) or tonumber(wd.nodeWeight)
    local hubNodeW = tonumber(jb.hubNodeWeight) or tonumber(wd.hubNodeWeight)
    local tireMass = tonumber(jb.tireWeight) or tonumber(wd.tireWeight)
    local hubMass = tonumber(jb.hubWeight) or tonumber(wd.hubWeight)
    if not tireMass and tireNodeW then tireMass = tireNodeW * max(8, rayCount) end
    if not hubMass and hubNodeW then hubMass = hubNodeW * max(8, rayCount) end
    tireMass = max(2.0, tireMass or 8.0)
    hubMass = max(2.0, hubMass or 6.0)

    -- Sidewall stiffness proxy → rolling resistance tendency (docs: higher spring → better RR / sharper peak)
    local sideSpring = tonumber(jb.tireSideBeamSpring) or tonumber(jb.hubSideBeamSpring) or tonumber(wd.tireSideBeamSpring) or 0
    local rrFromSidewall = 1.0
    if sideSpring > 0 then
        -- Normalize around a typical street sidewall (~2e5–6e5)
        rrFromSidewall = max(0.75, min(1.35, sideSpring / 400000))
    end

    local brakeMass = tonumber(wd.brakeMass) or tonumber(jb.brakeMass) or 8.0
    local brakeDiameter = tonumber(wd.brakeDiameter) or tonumber(jb.brakeDiameter) or 0.30
    local brakeVenting = tonumber(wd.brakeVentingCoef) or tonumber(jb.brakeVentingCoef) or 1.0
    local brakeCoolingArea = tonumber(wd.brakeCoolingArea)
    if not brakeCoolingArea then
        brakeCoolingArea = pi * brakeDiameter * brakeDiameter / 2 * 0.7
    end

    return {
        frictionCoef = frictionCoef,
        slidingFrictionCoef = slidingFrictionCoef,
        noLoadCoef = noLoadCoef,
        fullLoadCoef = fullLoadCoef,
        loadSensitivitySlope = loadSensSlope,
        dragCoef = dragCoef,
        tireMass = tireMass,
        hubMass = hubMass,
        tireWidth = tireWidth,
        radius = radius,
        hubRadius = hubRadius,
        rrFromSidewall = rrFromSidewall,
        brakeMass = max(1.0, brakeMass),
        brakeDiameter = max(0.15, brakeDiameter),
        brakeVentingCoef = max(0.2, brakeVenting),
        brakeCoolingArea = max(0.02, brakeCoolingArea),
        brakeType = tostring(wd.brakeType or jb.brakeType or "vented-disc"),
        rotorMaterial = tostring(wd.rotorMaterial or jb.rotorMaterial or "steel"),
        padMaterial = tostring(wd.padMaterial or jb.padMaterial or "basic"),
        enableBrakeThermals = not not (wd.enableBrakeThermals or jb.enableBrakeThermals)
    }
end

-- Native brake surface/core temps (wheels.lua → electrics.wheelThermals + live wd fields)
getNativeBrakeTemps = function(wd, envTemp)
    envTemp = envTemp or ENV_TEMP
    local surface, core = envTemp, envTemp
    if wd then
        if type(wd.brakeSurfaceTemperature) == "number" then surface = wd.brakeSurfaceTemperature end
        if type(wd.brakeCoreTemperature) == "number" then core = wd.brakeCoreTemperature end
        local name = wd.name
        if electrics and electrics.values and type(electrics.values.wheelThermals) == "table" and name then
            local wt = electrics.values.wheelThermals[name]
            if type(wt) == "table" then
                if type(wt.brakeSurfaceTemperature) == "number" then surface = wt.brakeSurfaceTemperature end
                if type(wt.brakeCoreTemperature) == "number" then core = wt.brakeCoreTemperature end
            end
        end
        -- Legacy fallbacks
        if surface == envTemp and type(wd.brakeThermal) == "table" and type(wd.brakeThermal.brakeTemp) == "number" then
            surface = wd.brakeThermal.brakeTemp
            core = surface
        end
    end
    return surface, core
end

getFreestreamAirspeed = function()
    local ev = electrics and electrics.values
    if not ev then return 0 end
    -- Brake thermals use airflowspeed; fall back to airspeed
    local a = tonumber(ev.airflowspeed) or tonumber(ev.airspeed) or 0
    return max(0, a)
end

getVehicleAirspeedRef = function()
    local ev = electrics and electrics.values
    if ev then
        local a = tonumber(ev.airspeed)
        if a and a > 0.5 then return a end
        local w = tonumber(ev.wheelspeed)
        if w and w > 0.5 then return w end
    end
    if obj and type(obj.getVelocity) == "function" then
        local vel = obj:getVelocity()
        if vel then
            local ok, len = pcall(function() return vel:length() end)
            if ok and type(len) == "number" then return max(0, len) end
        end
    end
    return 0
end

-- Recompute pack-air / convection vs native 0.39 interAero.
refreshDraftCompat = function()
    if draft.hasNativeInterAero then
        -- Drag/cooling freestream already handled by setWindAero → airflowspeed.
        draft.convectionMult = 1.0
        local fromInfer = draft.inferredWake * draft.nativeAirTempMax
        local fromCompanion = draft.airTempDelta
        draft.airTempEffective = max(0, min(draft.airTempCap, max(fromInfer, fromCompanion)))
    else
        draft.convectionMult = 1.0 - draft.coolingWake * draft.coolingReduction
        draft.airTempEffective = draft.airTempDelta
    end
end

-- Infer wake shelter from native aero: airflowspeed drops vs vehicle airspeed in a tow.
updateInferredNativeWake = function(dt)
    if not draft.hasNativeInterAero then
        draft.inferredWake = 0
        return
    end
    local spd = getVehicleAirspeedRef()
    local air = getFreestreamAirspeed()
    local target = 0
    if spd >= draft.inferMinSpeed then
        local deadband = max(draft.inferDeadbandMin, spd * draft.inferDeadband)
        local deficit = max(0, (spd - air) - deadband)
        local ref = max(1.0, spd * draft.inferRefFrac)
        target = max(0, min(1, deficit / ref))
    end
    local k = min(1.0, (dt or 0.05) * draft.inferSmooth)
    draft.inferredWake = draft.inferredWake + (target - draft.inferredWake) * k
    if draft.inferredWake < 0.008 and target < 0.008 then
        draft.inferredWake = 0
    end
end

-- Optional legacy companion (LuuksDraftingMod). On 0.39+, convection cut is ignored;
-- airTempDelta can still raise pack ambient if stronger than inference.
setDraftWake = function(wake, side, push, airTempDelta)
    draft.wake = max(0, min(1, tonumber(wake) or 0))
    draft.side = max(0, min(1, tonumber(side) or 0))
    draft.push = max(0, min(1, tonumber(push) or 0))
    draft.airTempDelta = max(0, min(draft.airTempCap, tonumber(airTempDelta) or 0))
    draft.coolingWake = max(draft.wake, draft.side * 0.7, draft.push * 0.25)
    draft.lastRxClock = os.clock()
    refreshDraftCompat()
end

decayDraftWake = function(dt)
    updateInferredNativeWake(dt)

    if draft.coolingWake <= 0 and draft.airTempDelta <= 0 then
        if not draft.hasNativeInterAero then
            draft.convectionMult = 1.0
            draft.airTempEffective = 0
        else
            refreshDraftCompat()
        end
        return
    end
    if (os.clock() - draft.lastRxClock) < draft.staleSec then
        refreshDraftCompat()
        return
    end
    local k = min(1.0, (dt or 0.05) * 3.0)
    draft.wake = draft.wake + (0 - draft.wake) * k
    draft.side = draft.side + (0 - draft.side) * k
    draft.push = draft.push + (0 - draft.push) * k
    draft.airTempDelta = draft.airTempDelta + (0 - draft.airTempDelta) * k
    draft.coolingWake = max(draft.wake, draft.side * 0.7, draft.push * 0.25)
    if draft.coolingWake < 0.001 then
        draft.wake, draft.side, draft.push, draft.coolingWake, draft.airTempDelta = 0, 0, 0, 0, 0
    end
    refreshDraftCompat()
end

-- Prefer wheels.deflateTire (0.39 surface) then beamstate fallback
deflateTireCompat = function(wheelID)
    if wheels and type(wheels.deflateTire) == "function" then
        wheels.deflateTire(wheelID)
        return true
    end
    if beamstate and type(beamstate.deflateTire) == "function" then
        beamstate.deflateTire(wheelID)
        return true
    end
    return false
end

--[[
  Wheel suspension state in vehicle-local frame (+Z up).
  Compression > 0 when the hub rises into the arch (bump).
  Ride height adapts slowly while settled so spawn pose / settling does not fake bottom-out.
  Damper velocity is d(hubZ)/dt — not hub−COM world velocity (that mixes yaw/pitch/roll).
]]
local susp = {  -- packed: frees 4 main-chunk locals
    velClamp = 10.0,
    softBumpM = 0.022,   -- start of bump stress (m of compression)
    hardBumpM = 0.065,   -- strong bottom-out region
    droopM = 0.035,      -- unloading / droop threshold
    rideAdapt = 0.55,    -- 1/s adaptive ride-height rate when settled
}

updateWheelSuspension = function(w, data, wd, dt, invQuat, upVector)
    w.suspensionVelocity = 0
    w.suspensionDeflection = 0
    w.suspCompression = 0
    w.suspStress = 0
    w.suspBump = 0
    w.suspDroop = 0

    if not wd or not obj or type(obj.getNodePosition) ~= "function" then return end
    if not wd.node1 then return end
    dt = max(1e-4, dt or 0.01)

    local pos1 = obj:getNodePosition(wd.node1)
    if not pos1 then return end
    local hx, hy, hz = pos1.x, pos1.y, pos1.z
    if wd.node2 then
        local pos2 = obj:getNodePosition(wd.node2)
        if pos2 then
            hx = (hx + pos2.x) * 0.5
            hy = (hy + pos2.y) * 0.5
            hz = (hz + pos2.z) * 0.5
        end
    end

    local hubLocalZ
    if invQuat and vec3 then
        hubLocalZ = (invQuat * vec3(hx, hy, hz)).z
    elseif upVector then
        -- Fallback: project hub offset onto vehicle up (node pos is vehicle-relative)
        hubLocalZ = hx * upVector.x + hy * upVector.y + hz * upVector.z
    else
        hubLocalZ = hz
    end

    local lastZ = w.suspHubZ
    w.suspHubZ = hubLocalZ

    -- Damper velocity from local hub Z derivative (stable vs body rotation)
    local suspVel = 0
    if lastZ ~= nil then
        suspVel = (hubLocalZ - lastZ) / dt
        if suspVel > susp.velClamp then suspVel = susp.velClamp
        elseif suspVel < -susp.velClamp then suspVel = -susp.velClamp end
    end
    -- Light smoothing
    local prevVel = w.suspensionVelocitySmoothed or suspVel
    suspVel = prevVel + (suspVel - prevVel) * min(1.0, dt * 25.0)
    w.suspensionVelocitySmoothed = suspVel
    w.suspensionVelocity = suspVel

    -- Adaptive ride height: only crawl toward hubZ when nearly settled and loaded
    local loadN = wd.downForce or 0
    local airborne = (not wd.contactMaterialID1 or wd.contactMaterialID1 == -1) or loadN <= 0
    local ride = data.rideHeightZ
    if ride == nil then
        ride = hubLocalZ
        data.rideHeightZ = ride
    elseif not airborne and abs(suspVel) < 0.12 and loadN > 200 then
        ride = ride + (hubLocalZ - ride) * min(1.0, dt * susp.rideAdapt)
        data.rideHeightZ = ride
    end

    -- +compression when hub rises above ride height (into the arch)
    local compression = hubLocalZ - ride
    w.suspCompression = compression
    w.suspensionDeflection = compression -- keep legacy field name (= bump positive)

    local bump = max(0, compression - susp.softBumpM)
    local droop = max(0, -compression - susp.droopM)
    w.suspBump = bump
    w.suspDroop = droop

    -- Stress: geometric bump + damper bump-stop (compression with downward body / upward wheel vel)
    -- suspVel > 0 ⇒ hub rising ⇒ bump stroke
    local bumpVel = max(0, suspVel)
    local hard = max(0, compression - susp.hardBumpM)
    local stress = bump * 12.0 + hard * 35.0 + bumpVel * bumpVel * 0.45
    -- Soft saturate so highway chatter cannot runaway
    stress = stress / (1.0 + stress * 0.35)
    w.suspStress = stress
end

-- Progressive pressure leak via BeamNG native pressure-group API (same path as wheels.lua puncture)
applyPressureLeakPa = function(wd, leakPaPerSec, dt)
    if not wd or leakPaPerSec <= 0 or not obj then return nil end
    if type(obj.getGroupPressure) ~= "function" or type(obj.setGroupPressure) ~= "function" then return nil end
    if not wd.pressureGroup or not v or not v.data or not v.data.pressureGroups then return nil end
    local pg = v.data.pressureGroups[wd.pressureGroup]
    if not pg then return nil end
    local ok, current = pcall(obj.getGroupPressure, obj, pg)
    if not ok or type(current) ~= "number" then return nil end
    -- Match BeamNG wheels.lua minimum before final deflate (~105 kPa absolute)
    local minPressure = 105000
    local newP = max(minPressure, current - leakPaPerSec * dt)
    pcall(obj.setGroupPressure, obj, pg, newP)
    return newP
end

-- Safe 8-arg friction API (BeamNG stage2 signature; ignore legacy 9th arg)
applyWheelFriction = function(wheel, longGrip, latGrip)
    if not wheel or type(wheel.setFrictionThermalSensitivity) ~= "function" then return end
    local mid = (longGrip + latGrip) * 0.5
    -- Disable native thermal curve; grip comes from this mod
    wheel:setFrictionThermalSensitivity(-300, 1e7, 1e-10, 1e-10, 10, longGrip, mid, latGrip)
end

-- Translates the wheel index position (e.g., "FL") to its actual active JBeam part name (Compatible with 0.35+)
-- Skips trunk/side spare parts — those contain "tire"/"spare" and were stealing classification from road tires.
isSpareOrAccessoryTireName = function(pLower)
    pLower = pLower or ""
    -- plain find: avoid pattern surprises; match common BeamNG spare slot/part names
    if string.find(pLower, "spare", 1, true) then return true end
    if string.find(pLower, "donut", 1, true) then return true end
    if string.find(pLower, "space_saver", 1, true) or string.find(pLower, "spacesaver", 1, true) then return true end
    if string.find(pLower, "temporary", 1, true) then return true end
    return false
end

getTirePartName = function(wheelName)
    local nameLower = string.lower(tostring(wheelName or ""))
    local isFront = string.match(nameLower, "^f")
    local isRear = string.match(nameLower, "^r")

    local function partNameFromEntry(k, v_part)
        if type(v_part) == "string" and v_part ~= "" then return v_part end
        if type(v_part) == "table" then
            local n = v_part.name or v_part.partName
            if type(n) == "string" and n ~= "" then return n end
        end
        if type(k) == "string" and k ~= "" then return k end
        return tostring(k)
    end

    local function scoreTirePart(partName)
        local pLower = string.lower(partName or "")
        if not string.find(pLower, "tire", 1, true) and not string.find(pLower, "tyre", 1, true) then
            return -1
        end
        if isSpareOrAccessoryTireName(pLower) then return -1 end

        local score = 10
        -- Axle-slot naming: tire_F_* = front, tire_R_* = rear (BeamNG common tires)
        local axleFront = string.find(pLower, "tire_f", 1, true) or string.find(pLower, "_f_", 1, true)
            or string.find(pLower, "front", 1, true)
        local axleRear = string.find(pLower, "tire_r", 1, true) or string.find(pLower, "_r_", 1, true)
            or string.find(pLower, "rear", 1, true)

        if isFront then
            if axleFront then score = score + 50
            elseif axleRear then score = score - 20 end
        elseif isRear then
            if axleRear then score = score + 50
            elseif axleFront then score = score - 20 end
        end

        -- Prefer compound tags over generic unnamed tires
        if string.find(pLower, "vintage", 1, true) or string.find(pLower, "bias", 1, true)
            or string.find(pLower, "whitewall", 1, true) or string.find(pLower, "sport", 1, true)
            or string.find(pLower, "standard", 1, true) or string.find(pLower, "slick", 1, true)
            or string.find(pLower, "race", 1, true) or string.find(pLower, "rally", 1, true)
            or string.find(pLower, "asphalt", 1, true) or string.find(pLower, "tarmac", 1, true)
            or string.find(pLower, "winter", 1, true) or string.find(pLower, "offroad", 1, true)
            or string.find(pLower, "drag", 1, true) or string.find(pLower, "drift", 1, true) then
            score = score + 15
        end
        return score
    end

    local activeParts = v and v.data and (v.data.activePartsData or v.data.activeParts)
    local bestName, bestScore = nil, -1
    if type(activeParts) == "table" then
        for k, v_part in pairs(activeParts) do
            local partName = partNameFromEntry(k, v_part)
            local sc = scoreTirePart(partName)
            if sc > bestScore then
                bestScore = sc
                bestName = partName
            end
        end
    end
    if bestName then return bestName end
    return wheelName
end

-- True when non-cosmetic rally hardware is fitted (coilovers, struts, skidplates, etc.).
-- Used to reclassify BeamNG asphalt-rally *_race mounts (UI type "Asphalt Rally") away from Slick.
vehicleHasRallyHardware = function()
    if cachedRallyHardware ~= nil then return cachedRallyHardware end
    local found = false
    local activeParts = v and v.data and (v.data.activePartsData or v.data.activeParts)
    if type(activeParts) == "table" then
        for k, v_part in pairs(activeParts) do
            local n = string.lower(tostring(
                (type(v_part) == "string" and v_part)
                or (type(v_part) == "table" and (v_part.name or v_part.partName))
                or k
                or ""
            ))
            if string.find(n, "rally", 1, true)
                and not string.find(n, "skin", 1, true)
                and not string.find(n, "paint", 1, true) then
                found = true
                break
            end
        end
    end
    cachedRallyHardware = found
    return found
end

local typeRetryCount = 0
getVehicleType = function()
    if cachedVehicleType then return cachedVehicleType end
    local vehType = "passenger_car"
    
    if v and type(v) == "table" and v.vehicleDirectory then
        local dirLower = string.lower(tostring(v.vehicleDirectory))
        if string.find(dirLower, "aurata") or string.find(dirLower, "utv") or string.find(dirLower, "atv") or string.find(dirLower, "sxs") then
            vehType = "utv"
        elseif string.find(dirLower, "md_series") or string.find(dirLower, "md%-series") or string.find(dirLower, "medium") or string.find(dirLower, "heavy_duty") or string.find(dirLower, "mt_series") or string.find(dirLower, "durham") or string.find(dirLower, "b_series") or string.find(dirLower, "b%-series") then
            vehType = "medium_duty"
        elseif string.find(dirLower, "semi") or string.find(dirLower, "t_series") or string.find(dirLower, "t%-series") or string.find(dirLower, "trailer") then
            vehType = "semi_truck"
        elseif string.find(dirLower, "pickup") or string.find(dirLower, "van") or string.find(dirLower, "roamer") then
            vehType = "light_truck"
        end
        cachedVehicleType = vehType -- Cache successfully resolved vehicle type
    elseif typeRetryCount > 10 then
        cachedVehicleType = "passenger_car" -- Freeze cache to passenger_car after 10 failed frames
    else
        typeRetryCount = typeRetryCount + 1
    end
    
    return cachedVehicleType or vehType
end

-- Hybrid Profile Resolving Engine (With Dynamic Dimensional Scaling & All Continuous Spectrums)
getInterpolatedProfile = function(treadCoef, softnessCoef, tireName, targetTable, radius, width, hubRadius)
    treadCoef, softnessCoef = treadCoef or 0.5, softnessCoef or 0.5
    local nameLower = string.lower(tostring(tireName or ""))
    local mods = targetTable or {}
    local rawProfile1, rawProfile2, interpFactor
    
    local r, w = max(0.1, radius or 0.3), max(0.1, width or 0.2)
    local hr = max(0.05, min(r - 0.01, hubRadius or (r * 0.65)))
    local sidewall = r - hr
    
    local vehType = getVehicleType()
    local isHeavyCommercialName = string.find(nameLower, "22.5") or string.find(nameLower, "19.5") or string.find(nameLower, "24.5") or string.find(nameLower, "steer") or string.find(nameLower, "drive") or string.find(nameLower, "semi")
    local isCommercialTire = (vehType == "semi_truck" or vehType == "medium_duty") or (radius and radius >= 0.44 and width and width >= 0.22) or (isHeavyCommercialName and radius and radius >= 0.40)
    local isUtilityTire = not isCommercialTire and ((vehType == "light_truck") or (radius and radius >= 0.36 and radius < 0.44))
    local isUTVTire = not isCommercialTire and not isUtilityTire and (vehType == "utv" or string.find(nameLower, "utv") or string.find(nameLower, "atv") or string.find(nameLower, "aurata") or string.find(nameLower, "sxs"))
    local isVintageTire = not isCommercialTire and not isUtilityTire and not isUTVTire and (string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") or string.find(nameLower, "classic_radial"))

    -- Name / vehicle cues for sealed-road rally rubber.
    -- Newer BeamNG parts use *_asphalt / tarmac; older asphalt-rally configs mount *_race
    -- (treadCoef 0, UI type "Asphalt Rally") on cars with rally coilovers/skidplates.
    local isAsphaltName = string.find(nameLower, "tarmac", 1, true)
        or (string.find(nameLower, "asphalt", 1, true) and not string.find(nameLower, "supersport", 1, true))
    local isGravelRallyName = string.find(nameLower, "rally", 1, true) and not isAsphaltName
    local isRaceLikeName = string.find(nameLower, "slick", 1, true) or string.find(nameLower, "race", 1, true) or treadCoef <= 0.12
    local isRallyAsphaltMount = isAsphaltName
        or (isRaceLikeName and not isGravelRallyName and not string.find(nameLower, "gravel", 1, true)
            and vehicleHasRallyHardware())

    -- 1. DETECT DETACHED OR STANDALONE SPECIFIC DESIGNS FIRST
    -- Vintage before spare: spare slots often contain "tire" and used to win incorrectly.
    if string.find(nameLower, "crawler") or string.find(nameLower, "beadlock") then rawProfile1, rawProfile2, interpFactor = "crawler", "crawler", 0; copyMods(STANDALONE_MODIFIERS.crawler, mods)
    elseif string.find(nameLower, "paddle") or string.find(nameLower, "sand") then rawProfile1, rawProfile2, interpFactor = "paddle", "paddle", 0; copyMods(STANDALONE_MODIFIERS.paddle, mods)
    elseif isGravelRallyName or isRallyAsphaltMount then rawProfile1, rawProfile2, interpFactor = "rally", "rally", 0; copyMods(STANDALONE_MODIFIERS.rally, mods)
    elseif string.find(nameLower, "winter") or string.find(nameLower, "snow") then rawProfile1, rawProfile2, interpFactor = "winter", "winter", 0; copyMods(STANDALONE_MODIFIERS.winter, mods)
    elseif string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") then rawProfile1, rawProfile2, interpFactor = "vintage", "vintage", 0; copyMods(STANDALONE_MODIFIERS.vintage, mods)
    elseif string.find(nameLower, "donut") or string.find(nameLower, "spare") then rawProfile1, rawProfile2, interpFactor = "donut", "donut", 0; copyMods(STANDALONE_MODIFIERS.donut, mods)
    elseif string.find(nameLower, "rain") or string.find(nameLower, "wet") or string.find(nameLower, "inter") then rawProfile1, rawProfile2, interpFactor = "rain", "rain", 0; copyMods(STANDALONE_MODIFIERS.rain, mods)
    elseif string.find(nameLower, "drag") then rawProfile1, rawProfile2, interpFactor = "drag", "drag", 0; copyMods(STANDALONE_MODIFIERS.drag, mods)
    elseif string.find(nameLower, "drift") then rawProfile1, rawProfile2, interpFactor = "drift", "drift", 0; copyMods(STANDALONE_MODIFIERS.drift, mods)
    elseif isRaceLikeName and not string.find(nameLower, "gravel", 1, true) then
        local sc = max(0.50, min(0.80, softnessCoef)) -- Simplified slicks range (Hard/Medium/Soft)
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(SLICK_SPECTRUM_POINTS, "softness", sc, mods)
    elseif isCommercialTire then
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(COMMERCIAL_SPECTRUM_POINTS, "tread", max(0.50, min(0.90, treadCoef)), mods)
    elseif isVintageTire then
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(VINTAGE_SPECTRUM_POINTS, "tread", max(0.50, min(0.65, treadCoef)), mods)
    elseif isUtilityTire then
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(UTILITY_SPECTRUM_POINTS, "tread", max(0.50, min(0.95, treadCoef)), mods)
    elseif isUTVTire then
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(ATV_UTV_SPECTRUM_POINTS, "tread", max(0.50, min(0.85, treadCoef)), mods)
    else
        -- Spectrum path updated to re-aligned discrete JBeam increments
        rawProfile1, rawProfile2, interpFactor = interpolateSpectrum(PROFILE_POINTS, "tread", max(0.30, min(1, treadCoef)), mods)
    end

    -- Ensure schema is current before dimensional scaling (legacy key migration + defaults)
    normalizeProfileMods(mods)

    -- DYNAMIC DIMENSIONAL SCALING SYSTEM (Intersects all compiled mods via realistic volumetric ratios)
    local REF_RADIUS, REF_WIDTH, REF_SIDEWALL = 0.315, 0.205, 0.112
    local ref_hr = REF_RADIUS - REF_SIDEWALL
    local ref_vol = pi * (REF_RADIUS^2 - ref_hr^2) * REF_WIDTH
    
    local current_vol = pi * (r^2 - hr^2) * w
    local volumeRatio = current_vol / max(1e-5, ref_vol)

    local widthRatio = w / REF_WIDTH
    local sidewallRatio = sidewall / REF_SIDEWALL

    -- Scale physical thermal mass, wear rate, and heat generation on volumetric curves
    local volScale = max(0.4, min(6.0, volumeRatio))
    if mods.treadInertia then mods.treadInertia = mods.treadInertia * volScale end
    if mods.carcassInertia then mods.carcassInertia = mods.carcassInertia * volScale end
    if mods.airThermalInertia then mods.airThermalInertia = mods.airThermalInertia * volScale end
    if mods.wearRate then mods.wearRate = mods.wearRate / max(0.4, min(4.0, volumeRatio)) end
    if mods.slipHeatRate then mods.slipHeatRate = mods.slipHeatRate / max(0.4, min(4.0, volumeRatio)) end
    if mods.workHeatRate then mods.workHeatRate = mods.workHeatRate * max(0.5, min(2.0, sidewallRatio)) end
    if mods.casingCompliance then mods.casingCompliance = mods.casingCompliance * max(0.3, min(1.8, sidewallRatio)) end

    local conductionScale = 1.0 / max(0.5, min(2.0, sidewallRatio))
    if mods.skinCoreConductance then mods.skinCoreConductance = mods.skinCoreConductance * conductionScale end
    if mods.airConductionRate then mods.airConductionRate = mods.airConductionRate * conductionScale end
    if mods.airCoolingRate then mods.airCoolingRate = mods.airCoolingRate * max(0.6, min(1.8, widthRatio)) end
    if mods.staticCoolingRate then mods.staticCoolingRate = mods.staticCoolingRate * max(0.6, min(1.8, widthRatio)) end

    -- Dynamic physical alignment scaling (thin tires are highly sensitive to roll/camber changes)
    if mods.camberSensitivity then mods.camberSensitivity = mods.camberSensitivity * max(0.5, min(2.5, REF_SIDEWALL / max(1e-5, sidewall))) end
    if mods.scrubSensitivity then mods.scrubSensitivity = mods.scrubSensitivity * max(0.6, min(1.8, w / REF_WIDTH)) end

    -- DYNAMIC DESCRIPTOR CLASSIFICATION ENGINE (Remaps strictly to standard base-game tire profiles) [BUGFIX]
    local descriptor = "Standard"
    if string.find(nameLower, "crawler") or string.find(nameLower, "beadlock") then 
        descriptor = "Crawler"
    elseif string.find(nameLower, "paddle") or string.find(nameLower, "sand") then 
        descriptor = "Paddle"
    elseif isRallyAsphaltMount then
        descriptor = "Rally Asphalt"
    elseif isGravelRallyName then
        descriptor = "Rally"
    elseif string.find(nameLower, "winter") or string.find(nameLower, "snow") then 
        descriptor = "Winter"
    elseif string.find(nameLower, "vintage") or string.find(nameLower, "biasply") or string.find(nameLower, "bias_ply") or string.find(nameLower, "whitewall") then 
        descriptor = "Vintage"
    elseif string.find(nameLower, "donut") or string.find(nameLower, "spare") then 
        descriptor = "Spare"
    elseif string.find(nameLower, "rain") or string.find(nameLower, "wet") or string.find(nameLower, "inter") then 
        descriptor = "Wet"
    elseif string.find(nameLower, "drag") then 
        descriptor = "Drag"
    elseif string.find(nameLower, "drift") then 
        descriptor = "Drift"
    elseif string.find(nameLower, "slick") or string.find(nameLower, "race") or treadCoef <= 0.15 then
        -- Explicit early sorting to identify base-game Slick / Race JBeams
        descriptor = "Slick"
    elseif isCommercialTire then
        descriptor = (treadCoef > 0.78) and "Mud-Terrain" or "Standard"
    elseif isVintageTire then
        descriptor = "Vintage"
    elseif isUtilityTire then
        if treadCoef <= 0.58 then
            descriptor = "Standard"
        elseif treadCoef <= 0.78 then
            descriptor = "All-Terrain"
        else
            descriptor = "Mud-Terrain"
        end
    elseif isUTVTire then
        if treadCoef <= 0.58 then
            descriptor = "Standard"
        elseif treadCoef <= 0.78 then
            descriptor = "All-Terrain"
        else
            descriptor = "Mud-Terrain"
        end
    else
        -- Passenger, sport, and sport plus definitions matching official JBeams
        if treadCoef <= 0.20 then
            descriptor = "Slick"
        elseif treadCoef <= 0.42 then
            descriptor = "Sport Plus"
        elseif treadCoef <= 0.58 then
            descriptor = "Sport"
        elseif treadCoef <= 0.72 then
            descriptor = "Standard"
        elseif treadCoef <= 0.85 then
            descriptor = "All-Terrain"
        elseif treadCoef <= 0.95 then
            descriptor = "Mud-Terrain"
        else
            descriptor = "Crawler"
        end
    end

    mods.descriptor = descriptor
    return rawProfile1, rawProfile2, interpFactor, mods
end

initTyreData = function()
    if not wheels or not wheels.wheelRotators then return end
    tyreData = {}
    cachedRallyHardware = nil -- re-probe on part reload / re-init
    
    -- Dynamically count active wheels to scale load-sensitivity curves for multi-axle trucks/duallys
    local count = 0
    for _ in pairs(wheels.wheelRotators) do
        count = count + 1
    end
    wheelCount = count > 0 and count or 4

    for i, wd in pairs(wheels.wheelRotators) do
        local wheelName = wd.name or "unknown"
        local tirePartName = getTirePartName(wheelName)
        local treadCoef, softnessCoef = wd.treadCoef or 0.5, wd.softnessCoef or 0.5
        local radius = wd.radius or 0.3
        local width = wd.tireWidth or wd.tyreWidth or wd.width or 0.2
        local hubRadius = wd.hubRadius or (radius * 0.65)
        
        -- Resolve and permanently cache the static profile configuration to save CPU cycles
        local initialMods = {}
        local p1, p2, factor, mods = getInterpolatedProfile(treadCoef, softnessCoef, tirePartName, initialMods, radius, width, hubRadius)
        local optTemp = mods and mods.optimalTemp or WORKING_TEMP
        
        -- Slicks: mild blanket preheat. Street: partial ambient→opt soak (sun/garage).
        -- Skin starts cooler than carcass so freestream doesn't fight a fully-soaked tread.
        local isRacingTire = string.find(p1 or "", "slick") or string.find(p2 or "", "slick")
        local preheatBlend = isRacingTire and SLICK_PREHEAT_BLEND or STREET_PREHEAT_BLEND
        local carcassStart = lerp(ENV_TEMP, optTemp, preheatBlend)
        local skinStart = lerp(ENV_TEMP, optTemp, preheatBlend * SKIN_PREHEAT_FRAC)
        local coldPSI = max(1.0, wd.pressure or 25.0)
        
        -- Axle side from wheel rotator name (FL/FR/RL/RR), not tire part (tire_R_* is rear axle compound)
        local wheelNameLower = string.lower(tostring(wheelName))
        local isFront = not not string.match(wheelNameLower, "^f")
        local baseFactors = collectBaseWheelFactors(wd)

        tyreData[i] = {
            working_temp = optTemp,
            temp = { skinStart, skinStart, skinStart, carcassStart, carcassStart, carcassStart, carcassStart, carcassStart },
            spawnAge = 0, -- seconds since init; drives SPAWN_CONV_GRACE_S
            condition = 100,
            zoneCondition = { 100, 100, 100 }, -- Outer / Middle / Inner wear (per-zone)
            flatSpot = 0,
            clog = 0, graining = 0, blistering = 0, marbles = 0,
            surfaceDamage = 0, -- Max of distinct damage modes (UI aggregate)
            heatCycles = 0, cycleHeated = false, coolTimer = 0,
            hotStintTime = 0, stintFade = 0,
            leakRatePa = 0, punctureSeverity = 0,
            lastGrip = 1, lastLongGrip = 1, lastLatGrip = 1,
            coldPressurePSI = coldPSI,
            targetHotPressurePSI = mods and mods.optimalPressure or coldPSI,
            rideHeightZ = nil, -- adaptive suspension baseline (set on first settled sample)
            isFront = isFront,
            profile1 = p1,
            profile2 = p2,
            -- Cached lowers for CalcTyreWear / grip hot paths (profiles are static after init)
            profile1Lower = string.lower(tostring(p1 or "")),
            profile2Lower = string.lower(tostring(p2 or "")),
            interpFactor = factor,
            interpolatedMods = initialMods,
            baseFactors = baseFactors,
            lastDriveHeatGate = 0
        }
    end
end

-- Translates 3D coordinates between the spindle nodes to calculate real camber & toe angles relative to GRAVITY
calculateWheelAlignment = function(i, wd)
    if not wd.node1 or not wd.node2 or not obj or not obj.getNodePosition then return 0, 0, 0, 0 end
    local pos1 = obj:getNodePosition(wd.node1)
    local pos2 = obj:getNodePosition(wd.node2)
    if not pos1 or not pos2 then return 0, 0, 0, 0 end
    
    local dx, dy, dz = pos1.x - pos2.x, pos1.y - pos2.y, pos1.z - pos2.z
    local dist = sqrt(dx*dx + dy*dy + dz*dz)
    if dist < 1e-5 then return 0, 0, 0, 0 end
    
    local lax, lay, laz = dx / dist, dy / dist, dz / dist
    
    -- Camber: Angle between the spindle axis and vehicle local vertical axis (Z)
    local camberRad = -asin(max(-0.999, min(0.999, laz)))
    local camberDeg = deg(camberRad)
    
    -- Toe: Angle between the spindle axis and vehicle local longitudinal axis (Y)
    local sideSign = pos1.x > 0 and 1 or -1
    local toeRad = math.atan2(lay * sideSign, abs(lax))
    local toeDeg = deg(toeRad)
    
    return camberDeg, toeDeg, camberRad, toeRad
end

-- FEATURE 2: Safe high-frequency force application helper (Clamps forces relative to individual node JBeam masses)
applySafeForce = function(node, fx, fy, fz)
    if not node or not obj or type(obj.applyForce) ~= "function" then return end
    -- Prevent NaN physics crashes immediately
    if fx ~= fx or fy ~= fy or fz ~= fz then return end
    
    -- Query the JBeam system for node physical weight
    local nodeMass = (type(obj.getNodeMass) == "function") and obj:getNodeMass(node) or 15
    if not nodeMass or nodeMass <= 0.1 then nodeMass = 15 end
    
    -- Enforce absolute limits relative to node mass (clamps physical acceleration up to ~30G)
    local maxForce = nodeMass * 300
    local fMag = sqrt(fx*fx + fy*fy + fz*fz)
    if fMag > maxForce then
        local scale = maxForce / fMag
        fx = fx * scale
        fy = fy * scale
        fz = fz * scale
    end
    
    obj:applyForce(node, fx, fy, fz)
end

-- CONSOLIDATED UNIFIED PARAMETER LOOKUP - ELIMINATES FRAGILE SIGNATURE OVERHEAD & LUA STACK COPIES
CalcTyreWear = function(wheelID, dt, localEnvTemp)
    local wd = wheels.wheelRotators[wheelID]
    local w = wheelCache[wheelID]
    local data = tyreData[wheelID]
    if not wd or not w or not data then return end

    localEnvTemp = localEnvTemp or ENV_TEMP
    dt = dt or 0.01
    data.temp = ensureTempNodes(data.temp, localEnvTemp)

    -- Read cached environmental dynamics (frameTrackTemp set once in updateGFX)
    local groundModel = w.groundModel or DOESNT_EXIST_DATA
    local trackTemp = frameTrackTemp
    local isAirborne = w.isAirborne
    
    local mods = data.interpolatedMods or DEFAULT_MODS

    -- DYNAMIC CLIMATE PROFILE ADAPTATION
    local baseEnv = 21.0
    local tempDiff = localEnvTemp - baseEnv
    
    -- Compound optimal temp is fixed; ambient only changes heat/cool rates
    local current_optimal_temp = max(35, mods.optimalTemp or WORKING_TEMP)
    
    -- Scale heat-generation and cooling with climate (not the grip peak)
    local heatAdaptationFactor = max(0.85, min(1.25, 1.0 - tempDiff * 0.008))
    local coolAdaptationFactor = max(0.75, min(1.30, 1.0 + tempDiff * 0.010))

    local wearRate = mods.wearRate or 0.0005
    local slipHeatRate = (mods.slipHeatRate or 8.925) * heatAdaptationFactor
    local workHeatRate = (mods.workHeatRate or 5.1) * heatAdaptationFactor
    local staticCoolingRate = (mods.staticCoolingRate or 0.08) * coolAdaptationFactor
    local airCoolingRate = (mods.airCoolingRate or 0.0275) * coolAdaptationFactor
    local skinCoreConductance = mods.skinCoreConductance or 0.068
    skinCoreConductance = max(topo.skinCoreConductanceFloor or 0.070,
        skinCoreConductance * (topo.skinCoreConductanceScale or 1.85))
    local coreVelCoolRate = (mods.coreVelCoolRate or 0.0088) * coolAdaptationFactor
    local coreCoolRate = (mods.coreCoolRate or 0.0385) * coolAdaptationFactor
    local brakeGainRate = mods.brakeGainRate or 0.9
    local airConductionRate = mods.airConductionRate or 0.0135
    local thermalReactionRate = mods.thermalReactionRate or 1.35
    local casing_compliance = mods.casingCompliance or 0.6
    local bottomOutSens = mods.bottomOutSensitivity or 1.0
    local trackConductivityMult = mods.trackConductivityMult or 1.0
    local coldWearMult = mods.coldWearMult or 1.8
    local hotWearMult = mods.hotWearMult or 3.5
    local grainTempRatio = mods.grainTempRatio or 0.75
    local blisterTempRatio = mods.blisterTempRatio or 1.55

    local rawJBeamTread = wd.treadCoef or 0.5
    local treadCoef = rawJBeamTread 
    
    local initialPressurePSI = max(1.0, wd.pressure or 25.0)

    -- Stock BeamNG construction + brake thermal factors
    local bf = data.baseFactors
    if not bf then
        bf = collectBaseWheelFactors(wd)
        data.baseFactors = bf
    end

    local brakeSurfaceTemp, brakeCoreTemp = getNativeBrakeTemps(wd, localEnvTemp)

    -- Tuning-menu brake ducts (default closed). Affects tyre air cooling + brake→carcass soak.
    local ductPct = getBrakeDuctPercent(data.isFront)
    local airCoolingDuctFactor, conductionDuctFactor, ductOpen = ductPercentToFactors(ductPct)
    -- Multiply with stock venting so race vented discs + open ducts stack correctly
    local ventingMult = max(0.35, min(2.0, bf.brakeVentingCoef or 1.0))
    airCoolingDuctFactor = airCoolingDuctFactor * lerp(1.0, ventingMult, 0.35)
    data.ductPercent = ductPct

    -- Apply to BeamNG native brake thermals (wheels.lua uses brakeTypeSurfaceCoolingCoef)
    if wd and baseBrakeCoolings[wheelID] == nil then
        baseBrakeCoolings[wheelID] = wd.brakeTypeSurfaceCoolingCoef or 1.0
    end
    if wd and baseBrakeCoolings[wheelID] then
        -- Closed = stock coef; fully open ≈ 2.2× stock venting (realistic race duct range)
        wd.brakeTypeSurfaceCoolingCoef = baseBrakeCoolings[wheelID] * lerp(1.0, 2.2, ductOpen) * ventingMult
    end
    
    local slipEnergy = isAirborne and 0 or (w.dynamicSlipEnergy or 0)
    local longSlipEnergy = isAirborne and 0 or (w.longSlipEnergy or 0)
    local sideSlipEnergy = isAirborne and 0 or (w.sideSlipEnergy or 0)
    local peakForce = isAirborne and 0 or (w.peakForce or 0)
    local contactDepth = isAirborne and 0 or (w.contactDepth or 0)
    local propulsionTorque = isAirborne and 0 or (wd.propulsionTorque or 0) * (wd.wheelDir or 1)
    local brakeTorque = isAirborne and 0 or (wd.brakeTorque or 0) * (wd.wheelDir or 1)
    local loadRaw = isAirborne and 0 or (wd.downForceRaw or wd.downForce or 0)
    if not isAirborne and (wd.downForce or 0) > 0 then
        -- Prefer smoothed downForce for stability when available
        loadRaw = wd.downForce or loadRaw
    end
    local angularVel = isAirborne and 0 or abs(wd.angularVelocity or 0)

    local tyreWidth = bf.tireWidth or wd.tireWidth or wd.tyreWidth or wd.width or 0.2
    local tyreRadius = (w.dynamicRadius and w.dynamicRadius > 0.05) and w.dynamicRadius or (bf.radius or wd.radius or 0.3)
    local airspeed = getFreestreamAirspeed()

    -- PHYSICAL AIRSPEED & ROTATIONAL HEADING COMBINATION MODEL (Forced Convection)
    local safeAirspeed = max(0, airspeed)
    -- Prefer freestream; rotation only adds mixing (avoid double-counting v≈ωr on cruise)
    local combinedAirspeed = safeAirspeed + angularVel * tyreRadius * 0.35
    local effectiveAirspeed = combinedAirspeed / (1.0 + combinedAirspeed / 220.0)

    -- Calculate horizontal G-force magnitude from actual BeamNG accelerometer vectors
    local gx = (sensors and (sensors.gx2 or sensors.gx) or 0) / 9.80665
    local gy = (sensors and (sensors.gy2 or sensors.gy) or 0) / 9.80665
    local g_mag = sqrt(gx * gx + gy * gy)

    local suspVel = w.suspensionVelocity or 0
    local underWater = w.underWater and true or false

    -- Yaw / sideslip cooling asymmetry (crossflow increases convection on the windward side)
    airCoolingDuctFactor = airCoolingDuctFactor * (1.0 + min(0.25, abs(gx) * 0.08 + abs(gy) * 0.05))
    if underWater then
        airCoolingDuctFactor = airCoolingDuctFactor * 1.55
        staticCoolingRate = staticCoolingRate * 1.8
    end

    -- Pack / slipstream convection: companion LuuksDraftingMod only when native
    -- 0.39 interAero is absent (draft.convectionMult precomputed in refreshDraftCompat).
    if draft.convectionMult < 1.0 then
        effectiveAirspeed = effectiveAirspeed * draft.convectionMult
        airCoolingDuctFactor = airCoolingDuctFactor * draft.convectionMult
    end

    -- Thermal mass from stock tire/hub node weights (not just geometry)
    local heatMassScale = max(0.55, min(2.4, (1 + ((tyreWidth / 0.2) * (tyreRadius / 0.3) - 1) * 0.45) * max(0.55, min(2.2, (bf.tireMass / 8.0) * 0.65 + (bf.hubMass / 6.0) * 0.35))))
    
    -- Convert raw vertical load from Newtons to kgf to match the non-linear curve's expected scaling.
    local load_kg = loadRaw / 9.81
    load_kg = ((400 + load_kg) * load_kg / (100 + load_kg) - 0.15 * load_kg)
    -- Align with stock noLoad/fullLoad friction curve (lighter load → slightly more heat per N work)
    local loadFrictionScale = 1.0
    if bf.noLoadCoef and bf.fullLoadCoef then
        loadFrictionScale = max(0.75, min(1.35, lerp(bf.noLoadCoef, bf.fullLoadCoef, min(1.0, max(0, loadRaw) * (bf.loadSensitivitySlope or 0.00015) * 8.0))))
        load_kg = load_kg * (0.85 + 0.15 * loadFrictionScale)
    end

    -- Thermal load: discount aero contribution. Aerodynamic downforce is included in
    -- wd.downForce but generates less tyre flex/hysteresis heat than static load because
    -- the pneumatic spring absorbs less deformation energy at high speed. The grip paths
    -- (CalculateTyreGrip) use the full loadRaw/loadN directly and are unaffected.
    local load_kg_thermal = load_kg
    do
        local aeroRamp = max(0.0, min(1.0, (safeAirspeed - topo.aeroHeatSpeedStart) / max(1.0, topo.aeroHeatSpeedFull - topo.aeroHeatSpeedStart)))
        if aeroRamp > 0.0 then
            load_kg_thermal = load_kg * (1.0 - aeroRamp * topo.aeroHeatMaxFrac * (1.0 - topo.aeroHeatScale))
        end
    end

    data.working_temp = current_optimal_temp

    local vehNotParked = (safeAirspeed < 1 and angularVel < 0.4) and 0 or 1
    local initialTempK = w.initialTempK or (localEnvTemp + 273.15)
    
    local currentTempK = (data.temp[8] or localEnvTemp) + 273.15
    -- Dynamic pressure rise from hard bump / bottom-out carcass volume loss
    local warmAbsolutePressurePSI = (initialPressurePSI + 14.696) * (1.0 + (currentTempK / initialTempK - 1.0) * (1.0 - casing_compliance)) * (1.0 + min(0.35, (w.suspStress or 0) * 0.08 * bottomOutSens))
    local dynamicPressurePSI = max(0.1, warmAbsolutePressurePSI - 14.696)
    
    local pressureRatio = max(0.01, dynamicPressurePSI / initialPressurePSI)
    local flexModifier = lerp(2.0, 0.5, max(0.01, min(1.0, pressureRatio)))
    local tyreWidthCoeff = (3.5 * tyreWidth) * 0.5 + 0.5

    -- Pass pressure ratio to warp edge load calculations dynamically based on inflation states
    local wLeft, wCenter, wRight = CalcBiasWeights(w.combinedBias, pressureRatio)

    -- Detect surfaces via shared classifier cache (must match CalculateTyreGrip)
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    local surfaceTypeHeat, sf = resolveWheelSurface(w, groundModel, isRaining) --luacheck: ignore surfaceTypeHeat
    local isLooseSurface = sf.loose
    local isIceSurface = sf.ice
    local isMudSurface = sf.mud
    local isSandSurface = sf.sand
    local isGravelSurface = sf.gravel
    local isSnowSurface = sf.snow
    local isDirtGrassSurface = sf.dirtGrass
    local isWetSurface = sf.wet
    local isDryPaved = sf.dryPaved
    local gmName = sf.gmName or (groundModel.nameLower or "")
    
    local avgWeightedTemp = TempRingsToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)
    local avgCarcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)
    
    local rollingResistance = (mods.rollingRes or 0.8) * (bf.rrFromSidewall or 1.0) * max(0.7, min(1.4, (bf.dragCoef or 5) / 5.0))
    -- topo = THERMAL_TOPOLOGY (module-level alias)
    -- Propulsion torque at steady cruise is mostly aero/RR balance — do not treat as slip work.
    -- Gate drive-torque heating by slip + lateral load so highway throttle does not cook the tread.
    local propAbs = abs(propulsionTorque)
    local driveHeatGate = min(1.0, (slipEnergy * 2.5) + (g_mag * 0.45) + (abs(brakeTorque) > 40 and 1.0 or 0))
    -- Straight-line cruise choke: idle/coast stay cold; Pass 3+ softens once |prop| > half cruiseNm
    -- so medium throttle can warm driven tires (overshoot OK). Very low prop still ×0.15.
    if slipEnergy < 0.06 and g_mag < 0.28 and abs(brakeTorque) < 40 then
        local halfCruise = topo.drivePropCruiseNm * 0.5
        driveHeatGate = driveHeatGate * (propAbs > halfCruise and (0.15 + 0.85 * max(0, min(1.0, (propAbs - halfCruise) / max(1.0, halfCruise)))) or 0.15)
    end
    -- Excess propulsion opens gate after cruise choke: hard throttle warms driven tires
    -- (Scintilla RWD track accel) while |prop|≤cruiseNm keeps Belasco highway soft.
    local excessPropGate = max(0, min(1.0, (propAbs - topo.drivePropCruiseNm) / max(1.0, topo.drivePropExcessFullNm)))
    -- Slick/race spectrum: damp Pass 3/4 excess only (sport_plus / non-slick keep full at low V).
    -- Split skin vs carcass — rears were still cooking carcass after skin-only 0.55 relief.
    local slickDriveScale = 1.0
    local slickCarcassScale = 1.0
    local p1Lower = data.profile1Lower or ""
    local p2Lower = data.profile2Lower or ""
    if string.find(p1Lower, "slick", 1, true) or string.find(p2Lower, "slick", 1, true) then
        slickDriveScale = topo.drivePropSlickScale or 0.50
        slickCarcassScale = topo.drivePropSlickCarcassScale or 0.30
    end
    -- Street/non-slick high-V: damp carcass excess when freestream opens prop-hold cook
    -- (soft-sim: 200→40C / 300→119C). Slicks already scaled; leave skin excess untouched.
    local streetCarcassScale = 1.0
    if slickCarcassScale >= 0.999 then
        local v0 = topo.drivePropStreetSpeed0 or 78.0
        local v1 = topo.drivePropStreetSpeed1 or 112.0
        local vRamp = max(0, min(1.0, (safeAirspeed - v0) / max(1.0, v1 - v0)))
        streetCarcassScale = 1.0 + ((topo.drivePropStreetCarcassScale or 0.28) - 1.0) * vRamp
    end
    local carcassPropScale = slickCarcassScale * streetCarcassScale
    local excessPropGateEff = excessPropGate * slickDriveScale
    local excessPropGateCarcass = excessPropGate * carcassPropScale
    local driveHeatGateSkin = max(driveHeatGate, excessPropGateEff)
    local driveHeatGateCarcass = max(driveHeatGate, excessPropGateCarcass)
    driveHeatGate = driveHeatGateSkin -- skin path + legacy readers
    data.lastDriveHeatGate = driveHeatGateSkin
    data.lastDriveHeatGateCarcass = driveHeatGateCarcass
    local netTorque = vehNotParked * abs(propulsionTorque * topo.drivePropSkinCoef * driveHeatGateSkin - brakeTorque * 0.025) * 0.075 * rollingResistance * flexModifier
    -- Pass 3+: boost slip/work skin heat with excess prop (driven tires only — undriven gate≈0)
    local tempDistWeighted = avgWeightedTemp / (data.working_temp > 0 and data.working_temp or 1)

    local estimatedContactArea = max(0.004, min(tyreWidth * 0.24, loadRaw / max(10000, dynamicPressurePSI * 6894.76)))
    -- Soft-surface sink reduces hard pavement conduction area
    if contactDepth and contactDepth > 0.02 then
        estimatedContactArea = estimatedContactArea * max(0.45, 1.0 - contactDepth * 1.5)
    end

    local current_working_temp = (data.working_temp and data.working_temp > 0) and data.working_temp or WORKING_TEMP

    local treadInertia = heatMassScale * (mods.treadInertia or DEFAULT_MODS.treadInertia) * max(0.7, min(1.5, bf.tireMass / 8.0))
    local carcassInertia = heatMassScale * (mods.carcassInertia or DEFAULT_MODS.carcassInertia) * max(0.7, min(1.6, (bf.tireMass * 0.55 + bf.hubMass * 0.2) / 6.0))
    local airInertia = heatMassScale * (mods.airThermalInertia or DEFAULT_MODS.airThermalInertia) * max(0.65, min(1.5, bf.tireMass / 8.0))
    local rimInertia = heatMassScale * RIM_THERMAL_INERTIA * max(0.6, min(2.5, bf.brakeMass / 8.0)) * max(0.75, min(1.4, bf.brakeDiameter / 0.30))
    local adjustedChangeRate = thermalReactionRate / max(0.05, treadInertia)
    local conductanceTreadScale = lerp(2.0, 1.0, treadCoef)
    local surfaceAreaScale = lerp(0.85, 1.15, treadCoef)
    local carcassRate = CORE_REACTION_RATE / max(0.05, carcassInertia)
    local rimRate = RIM_REACTION_RATE / max(0.05, rimInertia)

    -- P0-1: contact-patch fraction of circumference (skin nodes are belt averages)
    local patchFrac = topo.patchFracMin
    if not isAirborne and tyreWidth > 0.04 and tyreRadius > 0.05 then
        patchFrac = max(topo.patchFracMin, min(topo.patchFracMax, (estimatedContactArea / tyreWidth) / max(0.4, 2.0 * pi * tyreRadius)))
    end
    local patchHeatScale = max(0.40, min(1.20, patchFrac / max(0.05, topo.patchFracRef)))

    -- Stock friction multipliers shape heat generation
    local jbeamMu = max(0.4, min(1.8, bf.frictionCoef or 1.0))
    local jbeamSlideMu = max(0.35, min(1.8, bf.slidingFrictionCoef or jbeamMu))
    local peakWorkFactor = 1.0
    if peakForce and peakForce > 100 and loadRaw > 100 then
        -- Near peak force capacity → more hysteresis / scrub heat
        peakWorkFactor = max(0.85, min(1.35, peakForce / max(loadRaw, 1)))
    end

    -- Suspension damper / bump-stop heat into carcass (power ~ load·|v| + bump stress)
    local verticalCarcassHeat = 0
    if not isAirborne then
        verticalCarcassHeat = abs(suspVel) * (loadRaw / 1200) * 0.55
            + (w.suspBump or 0) * (loadRaw / 800) * 1.2
            + (w.suspStress or 0) * 1.8 * bottomOutSens
        if abs(suspVel) < 0.04 then
            verticalCarcassHeat = verticalCarcassHeat * 0.35 -- ignore micro-chatter
        end
    end

    -- CLIMATE PLAYABILITY ADAPTATION (reuses baseEnv/tempDiff from above)
    local climateScale = max(0.6, min(1.4, 1.0 + (tempDiff * 0.012)))

    -- Snapshot nodes before coupled updates (reuse scratch — no per-step alloc)
    local skinSnap = scratchSkinSnap
    skinSnap[1], skinSnap[2], skinSnap[3] = data.temp[1], data.temp[2], data.temp[3]
    local carcassSnap = scratchCarcassSnap
    carcassSnap[1], carcassSnap[2], carcassSnap[3] = data.temp[4], data.temp[5], data.temp[6]
    local rimSnap = data.temp[7] or localEnvTemp
    local airSnap = data.temp[8] or localEnvTemp

    -- Spawn convection grace: ease freestream fight against garage soak for ~SPAWN_CONV_GRACE_S
    data.spawnAge = (data.spawnAge or 0) + dt
    local spawnConvScale = 1.0
    if SPAWN_CONV_GRACE_S > 0 and data.spawnAge < SPAWN_CONV_GRACE_S then
        local u = max(0, min(1, data.spawnAge / SPAWN_CONV_GRACE_S))
        u = u * u * (3.0 - 2.0 * u) -- smoothstep
        spawnConvScale = lerp(0.35, 1.0, u)
    end

    -- Lateral carcass bias from side-slip (outer shoulder works harder in a slide)
    local sideBias = 0
    if (longSlipEnergy + sideSlipEnergy) > 1e-4 then
        sideBias = max(-0.35, min(0.35, (sideSlipEnergy - longSlipEnergy * 0.35) * 0.15 * (wd.wheelDir or 1)))
    end
    local wLeftB = max(0.08, wLeft * (1.0 - sideBias))
    local wRightB = max(0.08, wRight * (1.0 + sideBias))
    local wCenterB = max(0.08, wCenter)
    local carcassWeights = scratchCarcassWeights
    carcassWeights[1], carcassWeights[2], carcassWeights[3] = wLeftB / (wLeftB + wCenterB + wRightB), wCenterB / (wLeftB + wCenterB + wRightB), wRightB / (wLeftB + wCenterB + wRightB)

    for i = 1, 3 do
        local weight = carcassWeights[i]
        local loadCoeff = weight * load_kg_thermal
        -- Cornering work only — straight-line bump noise must not inflate skin heat
        local relative_work = max(0, g_mag - 0.22) * loadCoeff / 1000
        
        -- High-speed soft-saturation slide heat
        local slipEnergyHeat = slipEnergy / (1.0 + slipEnergy * 0.12)

        -- Rebalanced skin ring heating rates to prevent rapid thermal saturation
        local rawFrictionalGain = (slipEnergyHeat * 0.05 + netTorque * 0.002) * 3 * weight
        
        local surfaceMu = ((groundModel.staticFrictionCoefficient or 1) * 0.55 + (groundModel.slidingFrictionCoefficient or groundModel.staticFrictionCoefficient or 1) * 0.45) * jbeamMu
        local slideMuScale = max(0.5, min(1.6, jbeamSlideMu / max(0.2, jbeamMu)))

        -- West Coast hot-lap balance: ~+20% slip/work heat so ~4 laps approach opt without
        -- undoing highway RR soft-caps (those stay on carcass ω saturation below).
        rawFrictionalGain = rawFrictionalGain * (max(surfaceMu - 0.5, 0.1) * 2)
            + (((0.0078 * (slipEnergyHeat * slipEnergyHeat) * loadCoeff) * slipHeatRate * slideMuScale
                + 0.145 * relative_work * workHeatRate * peakWorkFactor / (1 + (slipEnergyHeat * slipEnergyHeat))) * surfaceMu / tyreWidthCoeff)
                
        rawFrictionalGain = rawFrictionalGain + ((verticalCarcassHeat * 0.005 * workHeatRate) / heatMassScale) * weight

        -- Surface sliding heat dampening (inline select)
        local frictionalGain = (rawFrictionalGain / heatMassScale) * ((tempDistWeighted > 1.1) and max(0.30, 1.0 - (tempDistWeighted - 1.1) * 0.6) or 1.0)
            * (isIceSurface and 0.20 or isSnowSurface and 0.25 or isMudSurface and 0.35 or isSandSurface and 0.45 or isDirtGrassSurface and 0.55 or isGravelSurface and 0.70 or isWetSurface and 0.85 or 1.0)

        -- Locked / locking wheel: sliding work is a circumferential flat, not whole-ring heating.
        -- Without this, 1–3s of ABS lock cooks skin → hot cliff → multi-second delay before roll resumes.
        if not isAirborne and angularVel < LOCKUP_OMEGA_THRESH and slipEnergy > 0.20 then
            frictionalGain = frictionalGain * lerp(LOCKUP_HEAT_FLOOR, 1.0, max(0, min(1, angularVel / LOCKUP_OMEGA_THRESH)))
        end
        -- P0-1: deposit slip/work/torque heat on patch-resident fraction (integrates with lockup floor)
        frictionalGain = frictionalGain * patchHeatScale * (1.0 + ((topo.drivePropSlipWorkMult or 1.0) - 1.0) * excessPropGateEff)

        local tempDelta = ((skinSnap[i] or localEnvTemp) - localEnvTemp)
        
        -- TURBULENT CONVECTION (v^0.8). 0.155 skin scale: cruise still mild; track retains more heat.
        -- Under sustained lateral load, convection is slightly reduced (patch/wake retention).
        local velCool = (effectiveAirspeed ^ 0.8) * airCoolingRate * 0.155 * airCoolingDuctFactor * surfaceAreaScale / (1.0 + min(0.18, max(0, g_mag - 0.20) * 0.22))
        local totalConvection = tempDelta * (staticCoolingRate * 0.04 + velCool) * climateScale * (1.0 + (1.0 - patchFrac) * (topo.freeBeltCoolMult - 1.0)) * spawnConvScale
        
        if tempDelta > 0 then
            totalConvection = totalConvection + tempDelta * climateScale * ((isWetSurface and 0.020 or 0) + ((isIceSurface or isSnowSurface) and 0.030 or 0))
        end

        local tempK_skin = (skinSnap[i] or localEnvTemp) + 273.15
        -- STEFAN-BOLTZMANN GREY-BODY RADIATION MODEL (Calibrated surface-area-to-mass scaling)
        local radiationCooling = (RUBBER_EMISSIVITY * STEFAN_BOLTZMANN * (tempK_skin^4 - (localEnvTemp + 273.15)^4)) * 0.0001

        local surfaceConduction = 0
        if not isAirborne then
            local surfaceConductivity = ASPHALT_CONDUCTIVITY * trackConductivityMult
            local surfaceTemp = trackTemp
            if isIceSurface then
                surfaceConductivity, surfaceTemp = 2.0 * trackConductivityMult, min(localEnvTemp, 0)
            elseif isSnowSurface then
                surfaceConductivity, surfaceTemp = 0.20 * trackConductivityMult, min(localEnvTemp, 0)
            elseif isMudSurface then
                surfaceConductivity, surfaceTemp = 0.45 * trackConductivityMult, localEnvTemp
            elseif isSandSurface then
                surfaceConductivity, surfaceTemp = 0.25 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.45
            elseif isGravelSurface or isDirtGrassSurface then
                surfaceConductivity, surfaceTemp = 0.55 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.55
            elseif isWetSurface then
                surfaceConductivity, surfaceTemp = 0.75 * trackConductivityMult, localEnvTemp + (trackTemp - localEnvTemp) * 0.35
            end
            -- Soft sink (contactDepth) or rough ground reduces clean asphalt conduction
            surfaceConduction = max(-25, min(110,
                (surfaceConductivity * estimatedContactArea * ((skinSnap[i] or localEnvTemp) - surfaceTemp) / THERMAL_BOUNDARY_LAYER)
                / (1 + slipEnergy * 0.1)
                * 0.003 / (1.0 + max(0, contactDepth or 0) * 4.0 + (tonumber(groundModel.rough) or 0) * 0.5)
            )) * weight
        end

        -- Skin ↔ matching carcass lane (L/C/R)
        local skinT = skinSnap[i] or localEnvTemp
        -- P1-1: real skin lateral conductance (mirrors carcass); soft avg equalizer mostly retired
        local skinLateral
        if i == 2 then
            skinLateral = (((skinSnap[1] or localEnvTemp) - skinT) + ((skinSnap[3] or localEnvTemp) - skinT)) * (topo.skinLateralConductance * 0.5)
        else
            skinLateral = ((skinSnap[2] or localEnvTemp) - skinT) * topo.skinLateralConductance
        end

        data.temp[i] = skinT + dt * (frictionalGain
            - (totalConvection + radiationCooling + surfaceConduction)
            + (avgWeightedTemp - skinT) * topo.skinEqualizerRetain
            + skinLateral
            + ((carcassSnap[i] or localEnvTemp) - skinT) * skinCoreConductance * conductanceTreadScale
        ) * adjustedChangeRate / tyreWidthCoeff
    end

    -- Soft-saturate ω so RR heat grows like real rolling power vs v^0.8 convection (ΔT rises slowly with speed)
    local angularVelHeat = abs(angularVel) / (1.0 + abs(angularVel) / 90.0)
    -- Cruise soft-cap: rolling hysteresis was cooking GT tires on Belasco straights
    local cruiseRRScale = 1.0
    if slipEnergy < 0.08 and g_mag < 0.35 and abs(brakeTorque) < 50 then
        cruiseRRScale = 0.48
    elseif slipEnergy < 0.15 and g_mag < 0.55 then
        cruiseRRScale = 0.72
    end
    -- Prop-linked RR damp: base load·ω RR opens under drive and was feeding carcass runaway
    -- (slick constant scale; street high-V scale). Blend toward carcassPropScale with excessPropGate.
    local propRrDamp = 1.0
    if carcassPropScale < 0.999 and excessPropGate > 1e-4 then
        propRrDamp = 1.0 + (carcassPropScale - 1.0) * excessPropGate
    end
    -- Scale hysteresis with carcass excess gate (base at cruise; full hystExcess when hard throttle).
    -- Skin uses excessPropGateEff; carcass hyst/flex use excessPropGateCarcass (slick / street high-V cut).
    local totalHysteresisHeat = (
        (load_kg_thermal * angularVelHeat * 0.0000028 * (0.45 * exp(-0.5 * (avgWeightedTemp / current_working_temp - 1)^2) + 0.15) * rollingResistance * cruiseRRScale * propRrDamp)
        + (verticalCarcassHeat * 0.01 * workHeatRate)
        + (propAbs * driveHeatGateCarcass * angularVelHeat * (topo.drivePropHystBase + (topo.drivePropHystExcess - topo.drivePropHystBase) * excessPropGateCarcass) * rollingResistance)
    ) / heatMassScale

    -- P0-2: gated flex warm-up into carcass (load × speed × g/slip). Does NOT bypass cruiseRRScale —
    -- straights keep workGate≈0 so Belasco GT-IV highway soak stays soft-capped.
    local flexWarmHeat = 0
    if not isAirborne and vehNotParked > 0 then
        local flexGate = max(0, min(1, (load_kg - topo.flexWarmLoad0) / max(1, topo.flexWarmLoad1 - topo.flexWarmLoad0)))
            * max(0, min(1, (safeAirspeed - topo.flexWarmSpeed0) / max(1, topo.flexWarmSpeed1 - topo.flexWarmSpeed0)))
            * max(0, min(1, max(0, g_mag - topo.flexWarmG0) / 0.70 + slipEnergy * 1.8))
        if flexGate > 1e-4 then
            local coldCoreBoost = (avgCarcassTemp < current_working_temp)
                and (1.0 + 0.35 * max(0, min(1, (current_working_temp - avgCarcassTemp) / max(20.0, mods.coldWidth or DEFAULT_MODS.coldWidth))))
                or 1.0
            flexWarmHeat = flexGate * topo.flexWarmGain * load_kg_thermal * angularVelHeat * rollingResistance * flexModifier * coldCoreBoost / heatMassScale
            -- Excess prop: damp base flex that co-fires with hard throttle / prop-hold (slick or street high-V)
            flexWarmHeat = flexWarmHeat * propRrDamp
        end
        -- Extra carcass flex on excess prop; carcass gate (slick / street high-V cut vs skin)
        if excessPropGateCarcass > (topo.drivePropFlexGateStart or 0.12) then
            flexWarmHeat = flexWarmHeat
                + ((excessPropGateCarcass - (topo.drivePropFlexGateStart or 0.12)) / max(1e-3, 1.0 - (topo.drivePropFlexGateStart or 0.12)))
                * topo.drivePropFlexExcess * load_kg_thermal * angularVelHeat * rollingResistance * flexModifier / heatMassScale
        end
    end

    local carcassCoolCoef = ((topo.carcassCoolVelCoef or 0.28) * coreVelCoolRate * (effectiveAirspeed ^ 0.8 * 0.20) * airCoolingDuctFactor
        + (topo.carcassCoolStaticCoef or 0.20) * coreCoolRate) * climateScale

    -- Share a slice of RR/flex work with skin so carcass doesn't runaway vs freestream-cooled tread
    local carcassWork = totalHysteresisHeat + flexWarmHeat
    local hystSkinShare = max(0, min(0.45, topo.hystSkinShare or 0.18))
    if hystSkinShare > 1e-6 and carcassWork > 0 then
        for i = 1, 3 do
            data.temp[i] = data.temp[i]
                + dt * carcassWork * hystSkinShare * carcassWeights[i] * adjustedChangeRate / tyreWidthCoeff
        end
    end
    local carcassWorkRemain = carcassWork * (1.0 - hystSkinShare)

    -- Carcass L/C/R: RR heat by load bias, skin coupling, rim soak, lateral diffusion, air
    for i = 1, 3 do
        local weight = carcassWeights[i]
        local carT = carcassSnap[i] or localEnvTemp
        local lateral
        if i == 2 then
            lateral = (((carcassSnap[1] or localEnvTemp) - carT) + ((carcassSnap[3] or localEnvTemp) - carT)) * (CARCASS_LATERAL_CONDUCTANCE * 0.5)
        else
            lateral = ((carcassSnap[2] or localEnvTemp) - carT) * CARCASS_LATERAL_CONDUCTANCE
        end
        data.temp[i + 3] = carT + (
            ((skinSnap[i] or localEnvTemp) - carT) * skinCoreConductance * conductanceTreadScale
            + (rimSnap - carT) * RIM_CARCASS_CONDUCTANCE * conductionDuctFactor
            + (airSnap - carT) * airConductionRate * 0.05
            + lateral
            + carcassWorkRemain * weight
            - (carT - localEnvTemp) * carcassCoolCoef
        ) * carcassRate * dt
    end

    avgCarcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias, pressureRatio, localEnvTemp)

    -- Rim / brake soak node: rotor heat enters here, then conducts into carcass + cavity air
    local brakeAreaScale = max(0.6, min(1.8, (bf.brakeCoolingArea or 0.1) / 0.12))
    local radiantToRim = 2.2e-11 * ((brakeSurfaceTemp+273.15)^4 - (rimSnap+273.15)^4) * brakeGainRate * conductionDuctFactor * brakeAreaScale
    local rimCarcassNet = (carcassWeights[1]*((carcassSnap[1] or localEnvTemp)-rimSnap) + carcassWeights[2]*((carcassSnap[2] or localEnvTemp)-rimSnap) + carcassWeights[3]*((carcassSnap[3] or localEnvTemp)-rimSnap)) * RIM_CARCASS_CONDUCTANCE * conductionDuctFactor
    -- Rotor material heat capacity proxy (steel default; carbon-ceramic holds less / cools differently)
    local rotorMat = string.lower(bf.rotorMaterial or "steel")
    local rotorCoolMult = (rotorMat == "aluminum" or rotorMat == "aluminium") and 1.15 or (string.find(rotorMat, "carbon") and 0.90 or 1.0)
    local rimCool = (rimSnap - localEnvTemp) * (0.22 * (effectiveAirspeed ^ 0.8 * 0.28) * airCoolingDuctFactor * rotorCoolMult + 0.08) * climateScale * brakeAreaScale

    -- Fire / hot-node soak (same helper BeamNG brake thermals use)
    local fireToRim = 0
    if fire and type(fire.getClosestHotNodeTempDistance) == "function" and wd.node1 then
        local okF, fireTemperature, fireDistance = pcall(fire.getClosestHotNodeTempDistance, wd.node1)
        if okF and type(fireTemperature) == "number" and type(fireDistance) == "number" then
            fireToRim = max((fireTemperature - rimSnap) * 0.04 * max(10 - fireDistance, 0), 0)
        end
    end

    data.temp[7] = rimSnap + (
        (0.012 * (brakeSurfaceTemp - rimSnap)) * brakeGainRate * conductionDuctFactor * brakeAreaScale
        + (0.004 * (brakeCoreTemp - rimSnap)) * brakeGainRate * conductionDuctFactor
        + radiantToRim + rimCarcassNet
        + (airSnap - rimSnap) * RIM_AIR_CONDUCTANCE
        + fireToRim - rimCool
    ) * rimRate * dt

    -- Cavity air: lags carcass + rim (pressure thermometer); dedicated airThermalInertia (P1-2)
    data.temp[8] = airSnap + (
        (avgCarcassTemp - airSnap) * airConductionRate * 4.0
        + ((data.temp[7] or localEnvTemp) - airSnap) * RIM_AIR_CONDUCTANCE * 2.0
        - (airSnap - localEnvTemp) * (airConductionRate * 0.08 * ((dynamicPressurePSI + 14.696) / 14.696) * (1.0 + abs(angularVel) * 0.006)) * climateScale
    ) * (1.0 / max(0.05, airInertia)) * dt

    -- HEAT CYCLES: compound hardens (more wear, less grip) — not reduced wear
    if not data.cycleHeated and avgWeightedTemp >= current_optimal_temp * 0.85 then
        data.cycleHeated = true
        data.coolTimer = 0
    elseif data.cycleHeated and avgWeightedTemp < (localEnvTemp + 15) then
        data.coolTimer = (data.coolTimer or 0) + dt
        if data.coolTimer > 45 then
            data.heatCycles = min(10, (data.heatCycles or 0) + 1)
            data.cycleHeated = false
            data.coolTimer = 0
        end
    else
        data.coolTimer = 0
    end

    -- Stint fade: time spent near/above optimal window
    if avgWeightedTemp >= current_optimal_temp * 0.90 then
        data.hotStintTime = (data.hotStintTime or 0) + dt
    elseif avgWeightedTemp < current_optimal_temp * 0.70 then
        data.hotStintTime = max(0, (data.hotStintTime or 0) - dt * 0.15)
    end
    -- ~0–12% grip loss over a long hot stint (~20 min at peak)
    data.stintFade = min(0.12, (data.hotStintTime or 0) / 10000)

    local cycleWearMultiplier = 1.0 + (data.heatCycles or 0) * 0.06 -- hardened compound wears faster
    
    local wear = 0
    local zoneWearDelta = { 0, 0, 0 }
    if not isAirborne then
        local tempWearPenalty = 1.0
        if tempDistWeighted > 1.0 then
            tempWearPenalty = lerp(1.0, hotWearMult, max(0.0, min(1.0, tempDistWeighted - 1.0)))
        elseif tempDistWeighted < 0.80 then
            tempWearPenalty = lerp(1.0, coldWearMult, max(0.0, min(1.0, (0.80 - tempDistWeighted) / 0.50)))
        end

        local slidingWear = 20.0 * ((loadRaw or max(100, vehicleMass)) / (max(100, vehicleMass) * 9.81) * slipEnergy * tempWearPenalty / tyreWidthCoeff)
        local surfaceWearScale = 1.0
        if isIceSurface then
            surfaceWearScale = lerp(0.25, 0.10, treadCoef)
        elseif isWetSurface then
            surfaceWearScale = 0.80
        elseif isLooseSurface then
            if isMudSurface or isSnowSurface or string.find(gmName, "grass") then
                surfaceWearScale = lerp(0.35, 0.15, treadCoef)
            elseif isGravelSurface then
                surfaceWearScale = lerp(1.15, 0.70, treadCoef)
            elseif isSandSurface then
                surfaceWearScale = lerp(1.00, 0.60, treadCoef)
            else
                surfaceWearScale = lerp(0.85, 0.50, treadCoef)
            end
        end
        
        wear = tempDistToWearMult(tempDistWeighted) * (slidingWear + (vehNotParked * abs(propulsionTorque * 0.008 - brakeTorque * 0.025) * 0.3 * TORQUE_ENERGY_MULTIPLIER) * 0.08 + angularVel * 0.0005) * (wearRate * cycleWearMultiplier / max(0.7, min(1.3, tyreWidth / 0.2))) * (1.0 + min(0.75, (w.suspStress or 0) * 0.35 * bottomOutSens)) * surfaceWearScale * dt

        -- Per-zone wear follows load bias weights (outer/middle/inner)
        zoneWearDelta[1] = wear * wLeft * 3
        zoneWearDelta[2] = wear * wCenter * 3
        zoneWearDelta[3] = wear * wRight * 3
    end

    if not data.zoneCondition then data.zoneCondition = { 100, 100, 100 } end
    for zi = 1, 3 do
        data.zoneCondition[zi] = max(0, min(100, (data.zoneCondition[zi] or 100) - (zoneWearDelta[zi] or 0)))
    end
    data.condition = max(0, min(100, (data.zoneCondition[1] + data.zoneCondition[2] + data.zoneCondition[3]) / 3))

    local scaleWearModifier = (mods.wearRate or 0.0005) * 2000
    
    -- Lockup flat spot: accumulates; heals extremely slowly (cosmetic smoothing only)
    if not isAirborne and (angularVel < 0.5) and (slipEnergy > 0.35) and (groundModel.staticFrictionCoefficient or 1.0) >= 0.85 then
        data.flatSpot = min(1.0, (data.flatSpot or 0) + (0.025 * scaleWearModifier * (slipEnergy / 0.35) * max(0.1, min(2.5, loadRaw / max(1, (vehicleMass * 9.81) / wheelCount)))) * dt)
    end
    if data.flatSpot and data.flatSpot > 0 and abs(angularVel) > 1.0 and loadRaw > 100 then
        -- Real flats barely heal; tiny decay only for numerical stability
        data.flatSpot = max(0, data.flatSpot - 0.00002 * dt)
    end

    -- DISTINCT surface modes: clog / grain / blister / marbles
    -- isDryPaved already from shared flags (includes hard_smooth)

    -- Dirt packing vs self-cleaning (tread-dependent)
    -- Rally blocks / open tread: slower pack + faster self-clean than street (clog still meaningful on mud)
    local clog = data.clog or 0
    local depthPack = min(1.5, max(0, contactDepth or 0) * 3.0)
    local p1Clog = data.profile1Lower or ""
    local p2Clog = data.profile2Lower or ""
    local isRallyClog = string.find(p1Clog, "rally", 1, true) or string.find(p2Clog, "rally", 1, true)
    if sf.mud or sf.dirtGrass or ((sf.sand or sf.gravel) and (isRaining or isWetSurface)) then
        local packRate = (0.35 + slipEnergy * 0.25 + depthPack) * max(0.05, 1.15 - rawJBeamTread) * (isMudSurface and 1.4 or 1.0)
        if isRallyClog then packRate = packRate * 0.55 end
        clog = clog + packRate * dt
    else
        local cleanBoost = (string.find(gmName, "sand") or string.find(gmName, "gravel")) and 2.5 or 1.0
        if isDryPaved then cleanBoost = cleanBoost * 1.3 end
        if isRallyClog then cleanBoost = cleanBoost * 1.45 end
        local selfClean = (0.015 + (angularVel * angularVel) * 0.000004 + slipEnergy * 0.02) * lerp(0.4, 2.5, rawJBeamTread) * cleanBoost
        clog = clog - selfClean * dt * max(0.35, 1.0 - depthPack * 0.4)
    end
    data.clog = max(0, min(1.0, clog))

    -- Graining: cold compound + lateral scrub on hard surfaces (not total slip alone).
    -- Threshold matches scaled native slip (~0.10), not the old 0.40 gate that rarely fired.
    local grain = data.graining or 0
    local grainColdLimit = current_working_temp * grainTempRatio
    local latGrainWork = max(sideSlipEnergy, slipEnergy * 0.55)
    local grainSlipThresh = 0.10
    local coldSeverity = 0
    if avgWeightedTemp < grainColdLimit then
        coldSeverity = min(1.6, (grainColdLimit - avgWeightedTemp) / max(10.0, grainColdLimit * 0.28))
    end
    if coldSeverity > 0 and latGrainWork > grainSlipThresh and not isAirborne and (isDryPaved or isWetSurface) then
        grain = grain + 0.00042 * scaleWearModifier * coldSeverity * min(2.8, latGrainWork / grainSlipThresh) * (isWetSurface and 0.55 or 1.0) * dt
    else
        local grainDecay = 0
        local warmFloor = current_working_temp * max(0.82, grainTempRatio + 0.06)
        if avgWeightedTemp >= warmFloor and avgWeightedTemp <= (current_working_temp * 1.15) and latGrainWork < (grainSlipThresh * 0.85) then
            grainDecay = 0.012 -- slow polish in the working window (old 0.04 erased grains too fast)
        end
        if not isAirborne and abs(angularVel) > 3.0 and latGrainWork < 0.08 then
            grainDecay = grainDecay + min(0.008, 0.00035 * abs(angularVel))
        end
        grain = grain - grainDecay * dt
    end
    data.graining = max(0, min(1.0, grain))

    -- Blistering: sustained overheat + aggressive slip only (does not heal).
    -- Old path used slip>0.15 with uncapped slip/0.15 scaling — mild hot corners blistered too fast.
    local blister = data.blistering or 0
    local blisterStart = current_working_temp * blisterTempRatio
    if avgWeightedTemp > blisterStart and slipEnergy > 0.32 and not isAirborne then
        blister = blister + 0.00028 * scaleWearModifier
            * min(2.0, (avgWeightedTemp - blisterStart) / max(12.0, current_working_temp * 0.18))
            * min(2.2, slipEnergy / 0.32) * dt
    end
    data.blistering = min(1.0, blister)

    -- Marbles / rubber pickup on hot dry asphalt under slip
    local marbles = data.marbles or 0
    if isDryPaved and not isWetSurface and avgWeightedTemp > current_optimal_temp * 0.95 and slipEnergy > 0.20 then
        marbles = marbles + (0.0004 * slipEnergy * scaleWearModifier) * dt
    elseif abs(angularVel) > 5 and slipEnergy < 0.12 then
        marbles = marbles - 0.008 * dt -- gradual clearing when rolling clean
    end
    data.marbles = max(0, min(1.0, marbles))

    data.surfaceDamage = max(data.clog or 0, data.graining or 0, data.blistering or 0, data.marbles or 0)

    -- Progressive puncture (BeamNG pressure-group leak), not instant deflate
    local leak = data.leakRatePa or 0
    if (data.blistering or 0) > 0.70 and avgWeightedTemp > current_optimal_temp * 1.30 then
        leak = max(leak, lerp(0, 22000, min(1, (data.blistering - 0.70) / 0.30))) -- Pa/s
    end
    if avgWeightedTemp > ((mods.optimalTemp or 65) >= 80 and 185 or 165) then
        leak = max(leak, 8000 + (avgWeightedTemp - 165) * 200)
    end
    if data.condition < 5 then
        leak = max(leak, 15000)
    end
    data.leakRatePa = leak
    if leak > 0 then
        local newAbs = applyPressureLeakPa(wd, leak, dt)
        if newAbs then
            data.punctureSeverity = min(1.0, (data.punctureSeverity or 0) + dt * 0.02)
            -- Finalize with native deflate only at BeamNG min pressure
            if newAbs <= 105500 then
                deflateTireCompat(wheelID)
            end
        elseif (data.blistering or 0) >= 0.95 and avgWeightedTemp > (data.working_temp * max(1.25, blisterTempRatio - 0.05)) then
            -- Fallback when pressure groups unavailable
            deflateTireCompat(wheelID)
        end
    end

    data.currentPressurePSI = dynamicPressurePSI
    -- Prefer live BeamNG pressure-group reading when leaking (matches native puncture path)
    if (data.leakRatePa or 0) > 0 and wd.pressureGroup and v and v.data and v.data.pressureGroups and obj and type(obj.getGroupPressure) == "function" then
        local pg = v.data.pressureGroups[wd.pressureGroup]
        if pg then
            local okP, absPa = pcall(obj.getGroupPressure, obj, pg)
            if okP and type(absPa) == "number" then
                data.currentPressurePSI = max(0.1, (absPa - 101325) / 6894.757)
            end
        end
    end
    data.currentFlatSpot = data.flatSpot or 0
    data.currentSurfaceDamage = data.surfaceDamage or 0
    data.currentClog = data.clog or 0
    data.currentGraining = data.graining or 0
    data.currentBlistering = data.blistering or 0
    data.currentMarbles = data.marbles or 0
end

-- COMPRESSED LOOKUP GRIP MATH: Scans pre-calculated static coefficient rows to avoid execution branches
-- profileLower: already string.lower'd (cached on tyreData); do not re-lower on the hot path.
getProfileBaselineGrip = function(profileLower, x)
    local p_lower = profileLower or ""
    local c = nil
    for i = 1, #GRIP_COEFFS do
        if string.find(p_lower, GRIP_COEFFS[i][1], 1, true) then
            c = GRIP_COEFFS[i][2]
            break
        end
    end
    c = c or { 0.85, 0.10, -0.05 } -- Default standard passenger fallback
    return c[1] + x * ((c[2] or 0) + x * ((c[3] or 0) + x * (c[4] or 0)))
end

classifySurfaceGrip = function(gmName)
    gmName = string.lower(gmName or "")

    -- Base-game keys / aliases first (art/groundmodels.json)
    if gmName == "frictionless" or gmName == "ice" then
        return "ice"
    end
    -- SLIPPERY is wet-asphalt class in BeamNG (collisiontype ASPHALT_WET), NOT ice
    if gmName == "slippery" or gmName == "asphalt_wet" or string.find(gmName, "asphalt_wet") then
        return "wet_paved"
    end
    if gmName == "snow" then
        return "snow"
    end
    if gmName == "mud" then
        return "mud"
    end
    if gmName == "gravel_wet" or string.find(gmName, "gravel_wet") or string.find(gmName, "gravel_riverbed") then
        return "gravel_wet"
    end
    if string.find(gmName, "gravel") or gmName == "dirt_loose" then
        return "gravel"
    end
    -- Dirt before sand so aliases like dirt_sandy stay dirt (not sand)
    if string.find(gmName, "grass") or string.find(gmName, "forest")
        or string.find(gmName, "leaves") or string.find(gmName, "branches")
        or string.find(gmName, "foliage") or string.find(gmName, "dirt") then
        return "dirt"
    end
    if gmName == "sand" or string.find(gmName, "beachsand") or string.find(gmName, "sandtrap")
        or (string.find(gmName, "sand") and not string.find(gmName, "dirt")) then
        return "sand"
    end
    if string.find(gmName, "rock") or string.find(gmName, "cobble") or string.find(gmName, "cliff")
        or string.find(gmName, "stone") then
        return "rock"
    end
    if string.find(gmName, "wet") or string.find(gmName, "puddle") then
        return "wet_paved"
    end
    if string.find(gmName, "asphalt") or string.find(gmName, "road") or string.find(gmName, "concrete")
        or string.find(gmName, "rumble") or string.find(gmName, "kickplate")
        or string.find(gmName, "spike") or string.find(gmName, "grid") then
        return "dry_paved"
    end
    -- Smooth hard props (bridges, ramps, barriers)
    if string.find(gmName, "metal") or string.find(gmName, "wood") or string.find(gmName, "plastic") then
        return "hard_smooth"
    end
    -- Non-drive / special
    if string.find(gmName, "void") or string.find(gmName, "soft_collision") or string.find(gmName, "shock_absorber") then
        return "generic"
    end
    return "generic"
end

getSurfaceSanityScale = function(surfaceType, treadCoef, drainage)
    treadCoef = max(0, min(1, treadCoef or 0.5))
    drainage = max(0, min(1, drainage or 0.5))

    if surfaceType == "dry_paved" then
        -- Low tread favors asphalt slightly; hard cap keeps high-G from tripping chassis
        -- Cap 1.15 ≈ peak logged ~1.34 @ Belasco gmμ~0.86 (was 1.49 @ cap 1.28)
        return lerp(1.04, 0.90, treadCoef), 1.15
    elseif surfaceType == "hard_smooth" then
        -- Kerbs/metal: keep below asphalt so curb strikes scrub instead of trip
        return lerp(0.96, 0.90, treadCoef), 1.10
    elseif surfaceType == "wet_paved" then
        -- Drainage/tread help in the wet, but never beat the same tire's dry-paved scale
        -- (MT/logger with wetGripScale were exceeding dry asphalt — illogical).
        local wet = lerp(0.82, 0.98, drainage) * lerp(0.94, 1.02, treadCoef)
        local dry = lerp(1.06, 0.90, treadCoef)
        return min(wet, dry * 0.92), 1.15
    elseif surfaceType == "gravel" then
        return lerp(0.55, 1.05, treadCoef), 1.00
    elseif surfaceType == "gravel_wet" then
        return lerp(0.48, 0.95, treadCoef), 0.88
    elseif surfaceType == "dirt" then
        return lerp(0.62, 1.02, treadCoef), 0.95
    elseif surfaceType == "mud" then
        return lerp(0.34, 1.08, treadCoef), 0.85
    elseif surfaceType == "sand" then
        return lerp(0.42, 1.04, treadCoef), 0.90
    elseif surfaceType == "snow" then
        return lerp(0.36, 1.00, treadCoef), 0.60
    elseif surfaceType == "ice" then
        -- Winter tread helps a little; slicks are awful
        return lerp(0.42, 0.78, treadCoef), 0.30
    elseif surfaceType == "rock" then
        return lerp(0.88, 1.05, treadCoef), 1.40
    end
    return 1.0, 1.30
end

-- Shared surface flags for wear/heat/grip (keeps CalcTyreWear and CalculateTyreGrip aligned)
-- Fills `out` in place — no allocation when caller reuses a table.
fillSurfaceFlags = function(out, surfaceType, gmName)
    out = out or {}
    out.ice = surfaceType == "ice"
    out.snow = surfaceType == "snow"
    out.mud = surfaceType == "mud"
    out.sand = surfaceType == "sand"
    out.gravel = surfaceType == "gravel" or surfaceType == "gravel_wet"
    out.dirtGrass = surfaceType == "dirt"
    out.wet = surfaceType == "wet_paved" or surfaceType == "gravel_wet"
    out.dryPaved = surfaceType == "dry_paved" or surfaceType == "hard_smooth"
    out.loose = surfaceType == "dirt" or surfaceType == "mud" or surfaceType == "gravel"
        or surfaceType == "gravel_wet" or surfaceType == "sand" or surfaceType == "snow"
    out.gmName = gmName or ""
    out.surfaceType = surfaceType
    return out
end

-- Cache classifySurfaceGrip + rain morph until contact material or rain state changes
resolveWheelSurface = function(w, groundModel, isRaining)
    local matId = w.contactMatId
    if matId == nil then matId = -2 end
    local raining = not not isRaining
    if w.surfCacheMatId == matId and w.surfCacheRaining == raining and w.surfaceType and w.surfaceFlags then
        return w.surfaceType, w.surfaceFlags
    end

    local gmName = (groundModel and groundModel.nameLower) or ""
    local surfaceType = classifySurfaceGrip(gmName)
    if raining then
        if surfaceType == "dry_paved" or surfaceType == "hard_smooth" or surfaceType == "rock" then
            surfaceType = "wet_paved"
        elseif surfaceType == "dirt" then
            surfaceType = "mud"
        elseif surfaceType == "gravel" then
            surfaceType = "gravel_wet"
        end
    end

    if not w.surfaceFlags then w.surfaceFlags = {} end
    fillSurfaceFlags(w.surfaceFlags, surfaceType, gmName)
    w.surfaceType = surfaceType
    w.surfCacheMatId = matId
    w.surfCacheRaining = raining
    return surfaceType, w.surfaceFlags
end

surfaceFlagsFromType = function(surfaceType, gmName)
    -- Legacy helper: prefer resolveWheelSurface in hot paths
    return fillSurfaceFlags({}, surfaceType, gmName)
end

-- Profile × surface grip bias (compound character on top of treadCoef sanity scale)
-- profile1/profile2 should already be lowercased (tyreData.profile1Lower / profile2Lower).
applyProfileSurfaceBias = function(tyreGrip, surfaceType, profile1, profile2)
    local p1 = profile1 or ""
    local p2 = profile2 or ""
    local function has(tag)
        return string.find(p1, tag, 1, true) or string.find(p2, tag, 1, true)
    end

    local isPaddle = has("paddle")
    local isWinter = has("winter")
    local isRally = has("rally")
    local isCrawler = has("crawler")
    local isMudTerrain = has("mudterrain") or has("mud_terrain")
    local isAllTerrain = has("allterrain") or has("all_terrain")
    local isSlick = has("slick")
    local isRain = (p1 == "rain" or p2 == "rain")
    local isDrift = has("drift")
    local isDrag = has("drag")
    -- Truck / commercial family (spectrum names: highway_*_truck, heavy_offroad_truck, logger_utility, etc.)
    local isTruckOffroad = has("offroad") or has("logger")
    local isTruckDrive = has("traction") and has("drive")
    local isTruckHighway = has("highway") or has("trailer") or (has("steer") and has("truck"))
    local isLightTruckHd = has("light_truck_hd") or has("heavy_duty")
    local isLightTruck = has("light_truck") and not isLightTruckHd

    if surfaceType == "sand" then
        if isPaddle then tyreGrip = tyreGrip * 1.35
        elseif isMudTerrain then tyreGrip = tyreGrip * 1.10
        elseif isAllTerrain or isCrawler then tyreGrip = tyreGrip * 1.06
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.08
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.90
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.88
        end
    elseif surfaceType == "mud" then
        if isPaddle then tyreGrip = tyreGrip * 1.25
        elseif isMudTerrain or isCrawler then tyreGrip = tyreGrip * 1.14
        elseif isRally or isAllTerrain then tyreGrip = tyreGrip * 1.08
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.12
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.06
        elseif isLightTruckHd or isLightTruck then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.88
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.82
        end
    elseif surfaceType == "rock" then
        if isCrawler then tyreGrip = tyreGrip * 1.18
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.14
        elseif isAllTerrain or isTruckDrive then tyreGrip = tyreGrip * 1.06
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.96
        elseif isPaddle then tyreGrip = tyreGrip * 0.80
        elseif isSlick then tyreGrip = tyreGrip * 0.94
        end
    elseif surfaceType == "gravel" or surfaceType == "dirt" then
        -- Rally: raised loose baseline (was 1.12) — asphalt path unchanged
        if isRally then tyreGrip = tyreGrip * 1.20
        elseif isAllTerrain then tyreGrip = tyreGrip * 1.10
        elseif isTruckOffroad then tyreGrip = tyreGrip * 1.10
        elseif isMudTerrain then tyreGrip = tyreGrip * 1.06
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.05
        elseif isLightTruckHd or isLightTruck then tyreGrip = tyreGrip * 1.04
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.94
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.90
        elseif isDrift then tyreGrip = tyreGrip * 0.95
        end
    elseif surfaceType == "gravel_wet" then
        if isRally then tyreGrip = tyreGrip * 1.14
        elseif isAllTerrain then tyreGrip = tyreGrip * 1.08
        elseif isMudTerrain or isCrawler or isTruckOffroad then tyreGrip = tyreGrip * 1.10
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.04
        elseif isRain then tyreGrip = tyreGrip * 1.06
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.90
        elseif isSlick then tyreGrip = tyreGrip * 0.85
        end
    elseif surfaceType == "snow" or surfaceType == "ice" then
        if isWinter then tyreGrip = tyreGrip * 1.22
        elseif isRain then tyreGrip = tyreGrip * 1.08
        elseif isAllTerrain or isTruckOffroad then tyreGrip = tyreGrip * 1.05
        elseif isTruckDrive then tyreGrip = tyreGrip * 1.03
        elseif isTruckHighway then tyreGrip = tyreGrip * 0.92
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.82
        end
    elseif surfaceType == "wet_paved" then
        if isRain then tyreGrip = tyreGrip * 1.06 -- stacks mildly with wetGripScale
        elseif isWinter then tyreGrip = tyreGrip * 1.04
        elseif isSlick or isDrag then tyreGrip = tyreGrip * 0.92 -- extra caution; wetGripScale already harsh
        end
    elseif surfaceType == "dry_paved" or surfaceType == "hard_smooth" then
        -- Slicks already get dryGripScale + surfaceCap; avoid stacking another asphalt bonus
        if isSlick or isDrag then tyreGrip = tyreGrip * 1.0
        elseif isMudTerrain or isCrawler or isTruckOffroad then tyreGrip = tyreGrip * 0.96
        elseif isPaddle then tyreGrip = tyreGrip * 0.90
        elseif isTruckHighway then tyreGrip = tyreGrip * 1.02
        end
    end
    return tyreGrip
end

-- CONSOLIDATED UNIFIED PARAMETER LOOKUP - HIGH PERFORMANCE ZERO-ALLOCATION PATH
CalculateTyreGrip = function(wheelID, localEnvTemp)
    local data = tyreData[wheelID]
    local w = wheelCache[wheelID]
    local wd = wheels.wheelRotators[wheelID]
    if not data or not w or not wd then return 0, 0, 1 end

    localEnvTemp = localEnvTemp or ENV_TEMP
    local mods = data.interpolatedMods or DEFAULT_MODS
    local rawJBeamTread = wd.treadCoef or 0.5
    local treadCoef = rawJBeamTread 
    local softnessCoef = wd.softnessCoef or 0.5
    local initialPressurePSI = max(1.0, wd.pressure or 25.0)
    local currentPSI = data.currentPressurePSI or initialPressurePSI
    
    local optP = max(1.0, mods.optimalPressure or 25.0)
    local pOffset = (currentPSI / optP) - 1.0
    local sensitivity = mods.pressureSensitivity or 0.5

    local avgTemp = EffectiveTyreTemp(data.temp, w.combinedBias, currentPSI / optP, localEnvTemp, mods)
    local cond = data.condition or 100
    local x = cond * 0.01
    
    local compliance = mods.casingCompliance or 0.5
    local camberSens = mods.camberSensitivity or 1.0
    local bottomOutSens = mods.bottomOutSensitivity or 1.0

    local profile1 = data.profile1
    local profile2 = data.profile2
    local profile1Lower = data.profile1Lower or ""
    local profile2Lower = data.profile2Lower or ""
    local interpFactor = data.interpFactor

    local baselineGrip1 = getProfileBaselineGrip(profile1Lower, x)
    local baselineGrip2 = getProfileBaselineGrip(profile2Lower, x)
    local tyreGrip = lerp(baselineGrip1, baselineGrip2, interpFactor)

    -- DYNAMIC SURFACE CLASSIFICATION (cached until contact material / rain changes)
    local groundModel = w.groundModel or DOESNT_EXIST_DATA
    local isRaining = electrics and electrics.values and type(electrics.values.rainState) == "number" and electrics.values.rainState > 0
    local surfaceType, flags = resolveWheelSurface(w, groundModel, isRaining)
    local isWetSurface = flags.wet
    local isLooseSurface = flags.loose
    local gmName = flags.gmName or (groundModel.nameLower or "")

    -- WEAR GRIP PENALTY
    local wearPenalty = 1.0
    if isLooseSurface then
        local minGripFactor = lerp(0.30, 0.55, 1.0 - treadCoef) 
        wearPenalty = lerp(minGripFactor, 1.0, x)
    else
        wearPenalty = lerp(0.75, 1.0, x)
    end
    tyreGrip = tyreGrip * wearPenalty

    -- Profile-owned thermal grip curve (ambient does not shift the compound peak)
    local thermalMultiplier = getProfileThermalGrip(mods, avgTemp, compliance, softnessCoef)

    -- Street: mild cold forgiveness. Race/slick/sport+: sharpen cold cliff (anti high-G trip on cold μ)
    local p1Cold = profile1Lower
    local p2Cold = profile2Lower
    local isRaceCold = string.find(p1Cold, "slick", 1, true) or string.find(p2Cold, "slick", 1, true)
        or string.find(p1Cold, "sport_plus", 1, true) or string.find(p2Cold, "sport_plus", 1, true)
    if thermalMultiplier < 1.0 then
        if isRaceCold then
            thermalMultiplier = max(0.42, thermalMultiplier ^ 1.12)
        else
            local thermalTolerance = lerp(1.18, 1.08, treadCoef)
            thermalMultiplier = max(0.50, thermalMultiplier ^ (1.0 / thermalTolerance))
        end
    end

    -- Mild adhesion shaping (old full square + high sport+ adhesion capped warm-up grip ~80–86%)
    local adhesionWeight = max(0.15, min(0.75, mods.adhesion or 0.45))
    local tTherm = max(0, thermalMultiplier)
    local shaped = tTherm * (0.62 + 0.38 * tTherm) -- between linear and quadratic
    local compoundThermalGrip = lerp(tTherm, shaped, adhesionWeight * 0.55)
    tyreGrip = tyreGrip * compoundThermalGrip * (mods.gripMultiplier or 1.0)

    -- Compound × surface character (AT/MT/winter/slick/etc.)
    tyreGrip = applyProfileSurfaceBias(tyreGrip, surfaceType, profile1Lower, profile2Lower)
    local longPressureScale, latPressureScale = CalcPressureGripScales(pOffset, sensitivity, isLooseSurface)

    -- Dynamically scales vertical tire load sensitivity by active wheelCount to handle trucks/duallys
    local staticLoad = (vehicleMass * 9.81) / wheelCount
    local loadSensitivityModifier = 1.0 / (1.0 + (mods.loadSensitivity or DEFAULT_MODS.loadSensitivity) * max(0, ((w.loadRaw or 0) / max(1, staticLoad)) - 1.0))
    -- Blend with stock JBeam noLoadCoef / fullLoadCoef curve
    local bf = data.baseFactors
    if bf and bf.noLoadCoef and bf.fullLoadCoef then
        local loadN = max(0, w.loadRaw or 0)
        local tLoad = min(1.0, loadN * (bf.loadSensitivitySlope or 0.00015) * 8.0)
        local jbeamLoadCoef = lerp(bf.noLoadCoef, bf.fullLoadCoef, tLoad)
        loadSensitivityModifier = loadSensitivityModifier * max(0.80, min(1.25, jbeamLoadCoef))
        -- Soft coupling to stock frictionCoef (do not double-count vs setFrictionThermalSensitivity)
        tyreGrip = tyreGrip * max(0.88, min(1.12, 0.55 + 0.45 * (bf.frictionCoef or 1.0)))
    end
    tyreGrip = tyreGrip * max(0.70, loadSensitivityModifier)

    -- Dynamic Wet & Hydroplaning Model (film depth from rain accumulation)
    if isWetSurface or waterFilmDepth > 0.05 then
        local drainage = mods.waterDrainage or 0.5
        local speedMPS = w.airspeed or 0
        local film = isWetSurface and max(waterFilmDepth, 0.35) or waterFilmDepth
        local widthHelp = max(0, min(8, ((wd.tireWidth or wd.tyreWidth or wd.width or 0.2) - 0.18) * 40))
        local thresholdSpeed = 10.0 + (drainage * 28.0) + max(-5.0, min(10.0, (currentPSI - 25.0) * 0.3)) + widthHelp - film * 8.0
        local exponent = max(-20.0, min(20.0, -0.16 * (speedMPS - thresholdSpeed)))
        local hydroplaneFactor = (speedMPS > 3.0) and (1.0 / (1.0 + exp(exponent))) or 0.0
        
        local baseWetPenalty = 0.14 * (1.0 - drainage) * (0.5 + film * 0.5)
        local dynamicPenalty = 0.55 * hydroplaneFactor * (1.0 - drainage * 0.40) * (0.4 + film * 0.6)
        -- Wet gravel: less classic hydroplane, more slurry — soften hydro term
        if surfaceType == "gravel_wet" then
            dynamicPenalty = dynamicPenalty * 0.55
            baseWetPenalty = baseWetPenalty * 0.70
        end
        tyreGrip = tyreGrip * (1.0 - min(0.78, baseWetPenalty + dynamicPenalty))
        tyreGrip = tyreGrip * (mods.wetGripScale or 1.0)
        -- Wet asphalt must not beat the same compound on dry asphalt (MT/logger wetGripScale overshoot)
        if surfaceType == "wet_paved" then
            local dryScale = select(1, getSurfaceSanityScale("dry_paved", treadCoef, drainage))
            local wetScale = select(1, getSurfaceSanityScale("wet_paved", treadCoef, drainage))
            local dryMod = mods.dryGripScale or 1.0
            local wetMod = mods.wetGripScale or 1.0
            local dryBias = 1.0
            local p1 = profile1Lower
            local p2 = profile2Lower
            if string.find(p1, "mudterrain", 1, true) or string.find(p2, "mudterrain", 1, true)
                or string.find(p1, "crawler", 1, true) or string.find(p2, "crawler", 1, true)
                or string.find(p1, "offroad", 1, true) or string.find(p2, "offroad", 1, true)
                or string.find(p1, "logger", 1, true) or string.find(p2, "logger", 1, true) then
                dryBias = 0.96
            elseif string.find(p1, "highway", 1, true) or string.find(p2, "highway", 1, true)
                or string.find(p1, "trailer", 1, true) or string.find(p2, "trailer", 1, true) then
                dryBias = 1.02
            end
            local ratioCap = (dryScale * dryMod * dryBias) / max(1e-3, wetScale * wetMod) * 0.98
            if ratioCap < 1.0 then
                tyreGrip = tyreGrip * ratioCap
            end
        end
    elseif surfaceType == "dry_paved" or surfaceType == "hard_smooth" then
        -- Pavement / smooth props only — do not apply dryGripScale on rock (offroad MT penalty was wrong there)
        tyreGrip = tyreGrip * (mods.dryGripScale or 1.0)
    end

    -- Distinct damage grip penalties
    -- Clog: street ~28% peak loss; rally open tread ~16% (still hurts, mud packs faster than dirt)
    if (data.currentClog or data.clog or 0) > 0.01 then
        local clogAmt = data.currentClog or data.clog
        local clogCoef = 0.28
        local p1c = profile1Lower
        local p2c = profile2Lower
        if string.find(p1c, "rally", 1, true) or string.find(p2c, "rally", 1, true) then
            clogCoef = 0.16
        end
        tyreGrip = tyreGrip * (1.0 - clogAmt * clogCoef * lerp(1.2, 0.6, treadCoef))
    end
    if (data.currentGraining or data.graining or 0) > 0.01 then
        tyreGrip = tyreGrip * (1.0 - (data.currentGraining or data.graining) * 0.22)
    end
    -- Ignore first ~8% blister (UI noise); then ramp to ~29% grip loss at full blister
    local blisterGrip = data.currentBlistering or data.blistering or 0
    if blisterGrip > 0.08 then
        tyreGrip = tyreGrip * (1.0 - (blisterGrip - 0.08) * 0.32)
    end
    if (data.currentMarbles or data.marbles or 0) > 0.01 then
        tyreGrip = tyreGrip * (1.0 - (data.currentMarbles or data.marbles) * 0.18)
    end
    if (data.heatCycles or 0) > 0 then
        tyreGrip = tyreGrip * (1.0 - min(0.15, data.heatCycles * 0.02)) -- hardened compound loses grip
    end
    if (data.stintFade or 0) > 0 then
        tyreGrip = tyreGrip * (1.0 - data.stintFade)
    end

    -- Camber penalty + mild camber thrust (grip bias, not spindle forces)
    local slideFactor = max(0, min(1, (w.slipEnergy or 0) / 0.50))
    local camberAbs = abs(w.camber or 0)
    local excessiveCamber = max(0, camberAbs - (2.5 + compliance * 3.5))
    local camberPenaltyFactor = 1.0 / (1.0 + excessiveCamber * excessiveCamber * (0.016 - compliance * 0.009) * camberSens)
    tyreGrip = tyreGrip * lerp(camberPenaltyFactor, 1.0, slideFactor)
    -- Camber thrust: small lateral preference when camber is working in the contact patch
    local camberThrust = max(0, min(0.06, camberAbs * 0.004 * (1.0 - slideFactor) * compliance))

    -- Unified suspension grip (single path — no stacked stress/vel/deflection penalties)
    -- Compression bump/bottom-out and droop unloading both reduce available patch load quality.
    local suspGripModifier = 1.0
    local bump = w.suspBump or 0
    local droop = w.suspDroop or 0
    local suspVel = w.suspensionVelocity or 0
    if bump > 0 then
        -- Soft bump: mild; hard bump (beyond SUSP_HARD band encoded in stress): stronger
        local hardFrac = min(1.0, bump / max(1e-3, susp.hardBumpM - susp.softBumpM))
        suspGripModifier = suspGripModifier * max(0.82, 1.0 - bump * 1.8 * bottomOutSens - hardFrac * 0.08 * bottomOutSens)
    end
    if droop > 0 then
        suspGripModifier = suspGripModifier * max(0.78, 1.0 - droop * 2.2)
    end
    -- Fast damper stroke: brief unload / scrub (extension = negative vel when hub dropping)
    if abs(suspVel) > 0.35 then
        suspGripModifier = suspGripModifier * max(0.88, 1.0 - (abs(suspVel) - 0.35) * 0.06)
    end
    tyreGrip = tyreGrip * suspGripModifier

    local surfaceScale, surfaceCap = getSurfaceSanityScale(surfaceType, treadCoef, mods.waterDrainage or 0.5)
    local gmStatic = max(0.0, groundModel.staticFrictionCoefficient or 1.0)
    local gmSliding = max(0.0, groundModel.slidingFrictionCoefficient or gmStatic)
    -- FRICTIONLESS / zero-μ pads: collapse grip instead of dividing by tiny μ (cap explosion)
    if gmStatic <= 0.01 and gmSliding <= 0.01 then
        tyreGrip = tyreGrip * 0.02
    else
        local gmMu = max(0.05, (gmStatic * 0.65) + (gmSliding * 0.35))
        local beamSurfaceReference = max(0.18, min(1.20, gmMu))
        tyreGrip = min(tyreGrip * surfaceScale, surfaceCap / beamSurfaceReference)
    end

    local activeFlatSpot = data.currentFlatSpot or 0
    -- Zone wear: outer/inner wear hurts lateral more; center hurts longitudinal more
    local zc = data.zoneCondition or { 100, 100, 100 }
    local zoneLatPen = 1.0 - ((100 - (zc[1] or 100)) + (100 - (zc[3] or 100))) * 0.0015
    local zoneLongPen = 1.0 - (100 - (zc[2] or 100)) * 0.0020
    local longGrip = tyreGrip * longPressureScale * (mods.longGripMult or 1.0) * max(0.55, zoneLongPen) * (1.0 - (activeFlatSpot * 0.08))
    local latGrip = tyreGrip * latPressureScale * (mods.latGripMult or 1.0) * max(0.55, zoneLatPen) * (1.0 + camberThrust) * (1.0 - (activeFlatSpot * 0.22))

    -- Tip-over protection: only after real load transfer (preserve turn-in bite)
    do
        local loadRatio = (w.loadRaw or 0) / max(1.0, staticLoad)
        if loadRatio > 1.32 then
            local overload = min(1.6, loadRatio - 1.32)
            latGrip = latGrip * max(0.72, 1.0 - overload * 0.22)
        end
    end

    -- Anti-trip ceiling: race compounds — softer than v3 so turn-in isn't dead
    do
        local p1r = profile1Lower
        local p2r = profile2Lower
        local isRaceLat = string.find(p1r, "slick", 1, true) or string.find(p2r, "slick", 1, true)
            or string.find(p1r, "sport_plus", 1, true) or string.find(p2r, "sport_plus", 1, true)
        if isRaceLat then
            local latCap = 1.12 -- sport_plus
            if string.find(p1r, "soft_slick", 1, true) or string.find(p2r, "soft_slick", 1, true) then
                latCap = 1.18
            elseif string.find(p1r, "medium_slick", 1, true) or string.find(p2r, "medium_slick", 1, true) then
                latCap = 1.16
            elseif string.find(p1r, "hard_slick", 1, true) or string.find(p2r, "hard_slick", 1, true) then
                latCap = 1.14
            end
            local tOptLat = mods.optimalTemp or DEFAULT_MODS.optimalTemp
            local coldFrac = max(0, min(1, (tOptLat - avgTemp) / max(20.0, tOptLat * 0.45)))
            local hotFrac = max(0, min(1, (avgTemp - tOptLat) / max(20.0, tOptLat * 0.40)))
            latCap = latCap * (1.0 - 0.18 * coldFrac - 0.12 * hotFrac)
            if latGrip > latCap then latGrip = latCap end
        end
    end

    -- Post-lockup spin-up assist: brakes off but wheel still nearly locked while sliding.
    -- Guarantees enough longitudinal μ for ground torque to accelerate the wheel (kills stuck-lock feel).
    do
        local brakeInput = 0
        if electrics and electrics.values and type(electrics.values.brake) == "number" then
            brakeInput = electrics.values.brake
        end
        local angVelGrip = abs(wd.angularVelocity or 0)
        local stillSliding = ((w.slipEnergy or 0) > 0.12) or (abs(wd.lastSlip or 0) > 2.0)
        if brakeInput < 0.08 and angVelGrip < LOCKUP_RECOVERY_OMEGA and stillSliding and not w.isAirborne then
            local need = lerp(LOCKUP_RECOVERY_LONG_GRIP, LOCKUP_RECOVERY_LONG_GRIP * 0.78,
                max(0, min(1, angVelGrip / LOCKUP_RECOVERY_OMEGA)))
            if longGrip < need then longGrip = need end
        end
    end

    -- Optional arcade brake-release bite (disabled by default)
    if ENABLE_BRAKE_BITE_HACK then
        local brakeInput = electrics and electrics.values and electrics.values.brake or 0
        local angularVel = abs(wd.angularVelocity or 0)
        local isSliding = w.slipEnergy and w.slipEnergy > 0.15
        if brakeInput < 0.05 and angularVel < 6.0 and isSliding and not w.isAirborne then
            longGrip = longGrip * 1.15
        end
    end

    tyreGripTable[wheelID] = tyreGrip
    return longGrip, latGrip, tyreGrip
end

initGuiStream = function()
    if not wheels or not wheels.wheelRotators then return end
    guiStream.data = {}
    guiStream.envTemp = ENV_TEMP
    guiStream.trackTemp = ENV_TEMP
    guiStream.rainState = 0
    guiStream.waterFilm = 0
    guiStream.totalDownforceN = 0
    guiStream.aeroFracPct = 0
    guiStream.streamHz = math.floor(1.0 / SEND_INTERVAL + 0.5)
    guiStream.elevationM = 0
    guiStream.timeOfDay = 0
    guiStream.cloudCover = 0
    guiStream.packWake = 0
    guiStream.packAirDelta = 0
    guiStream.envTempRange = 0
    wheelIndexMap = {}
    local idx = 1
    for i, wd in pairs(wheels.wheelRotators) do
        guiStream.data[idx] = {
            name = tostring(wd.name or "unknown"),
            temp = { ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP, ENV_TEMP },
            tempCategory = "Normal",
            working_temp = WORKING_TEMP, condition = 100, zoneCondition = { 100, 100, 100 },
            tyreGrip = 1, longGrip = 1, latGrip = 1, camber = 0, toe = 0, pressure = 25,
            initialPressure = 25, optimalPressure = 25, coldPressure = 25, targetHotPressure = 25,
            pressureRatio = 1, skinCarcassGap = 0, driveHeatGate = 0, driveHeatGateCarcass = 0,
            clog = 0, cycles = 0, graining = 0, blistering = 0, marbles = 0, flatspot = 0,
            surfaceDamage = 0, stintFade = 0, leak = 0, waterFilm = 0, ductPercent = 1,
            carcassAvg = ENV_TEMP, rimTemp = ENV_TEMP, airTemp = ENV_TEMP,
            brakeSurface = ENV_TEMP, brakeCore = ENV_TEMP, contactDepth = 0, underWater = false,
            -- Surface / contact diagnostics
            surfaceName = "unknown", surfaceType = "generic",
            muStatic = 1, muSlide = 1, rough = 0,
            loadN = 0, peakForce = 0, dynamicRadius = 0.3,
            slipEnergy = 0, longSlip = 0, sideSlip = 0,
            -- Suspension diagnostics
            suspCompressionMm = 0, suspVel = 0, suspStress = 0, suspBumpMm = 0, suspDroopMm = 0,
            airborne = false,
            profile = "standard", profile1 = "", profile2 = "", compoundClass = "standard",
            isBroken = false, isDetached = false
        }
        wheelIndexMap[i] = idx
        idx = idx + 1
    end
end

-- HIGH-FREQUENCY VEHICLE TICK (2000Hz)
update = function(dt)
    if not ENABLE_FORCE_FEEDBACK_FX then return end
    if not wheels or not wheels.wheelRotators or not next(wheelCache) or not next(tyreData) then return end

    local upDir, fwdDir = nil, nil
    local fxScale = FORCE_FEEDBACK_SCALE

    for i, wd in pairs(wheels.wheelRotators) do
        local w = wheelCache[i]
        local data = tyreData[i]
        if w and data and not w.isBroken and not w.isTireDeflated then
            local angularVelocity = wd.angularVelocity or 0
            w.rotationAngle = ((w.rotationAngle or 0) + angularVelocity * dt) % (2 * pi)

            local loadRawPhysics = wd.downForce or 0
            local realTimeSlip = wd.lastSlip or 0
            local slipPhysics = realTimeSlip * 0.05

            local activeFlatSpot = data.currentFlatSpot or 0
            if activeFlatSpot > 0.02 and abs(angularVelocity) > 2 and obj then
                if not upDir and obj.getDirectionVectorUp and obj.getDirectionVector then
                    upDir = obj:getDirectionVectorUp()
                    fwdDir = obj:getDirectionVector()
                end
                if upDir and fwdDir then
                    local cosAngle = max(0, cos(w.rotationAngle))
                    local impactFactor = (cosAngle * cosAngle * cosAngle * cosAngle) ^ 2
                    local forceMagnitude = loadRawPhysics * activeFlatSpot * impactFactor * min(abs(angularVelocity) / 30, 1.5) * fxScale
                    local fx = upDir.x * forceMagnitude + fwdDir.x * (-forceMagnitude * 0.25)
                    local fy = upDir.y * forceMagnitude + fwdDir.y * (-forceMagnitude * 0.25)
                    local fz = upDir.z * forceMagnitude + fwdDir.z * (-forceMagnitude * 0.25)
                    applySafeForce(wd.node1, fx, fy, fz)
                    applySafeForce(wd.node2, fx, fy, fz)
                end
            end

            if slipPhysics > 0.15 and not w.isAirborne and abs(angularVelocity) > 2 and obj and obj.getDirectionVector then
                fwdDir = fwdDir or obj:getDirectionVector()
                if fwdDir then
                    local compliance = (data.interpolatedMods and data.interpolatedMods.casingCompliance) or 0.6
                    w.chatterTime = ((w.chatterTime or 0) + dt * min(60, max(20, abs(angularVelocity) * 1.2)) * 2 * pi) % (2 * pi)
                    local mult = sin(w.chatterTime) * min(1.0, (slipPhysics - 0.15) / 0.4) * 18 * (1.5 - compliance) * fxScale
                    applySafeForce(wd.node1, fwdDir.x * mult, fwdDir.y * mult, fwdDir.z * mult)
                    applySafeForce(wd.node2, fwdDir.x * mult, fwdDir.y * mult, fwdDir.z * mult)
                end
            end
        end
    end
end

prepareWheelFrame = function(dt, localizedEnvTemp, invQuat, upVector, airspeed, g_mag, g_lat)
    for i, wd in pairs(wheels.wheelRotators) do
        if not wheelCache[i] then 
            wheelCache[i] = {
                initialTempK = localizedEnvTemp + 273.15,
                radius = wd.radius or 0.3
            } 
        end
        local w = wheelCache[i]
        local data = tyreData[i]
        
        if data then
            updateWheelSuspension(w, data, wd, dt, invQuat, upVector)

            local camberDeg, toeDeg, camberRad, toeRad = calculateWheelAlignment(i, wd)
            w.camber = camberDeg
            w.toe = toeDeg
            w.camberRad = camberRad
            w.toeRad = toeRad
            w.airspeed = airspeed

            -- Signed lateral G: g_lat (vehicle-right positive) * wheelDir maps lateral load
            -- onto each wheel's own outer shoulder ring. Under left corner (g_lat < 0), the
            -- right/outer wheel (wheelDir = -1) gets bias > 0 → rightRing ↑; left/inner wheel
            -- (wheelDir = 1) gets bias < 0 → leftRing ↑. Magnitude path (heat scale) still
            -- uses |g_mag| unchanged so total heat budget is not affected.
            local gLatBias = (g_lat or 0) * (wd.wheelDir or 1) * 0.28
            local combinedBias = (-w.camber * 0.12 * (wd.wheelDir or 1)) + gLatBias
            w.combinedBias = combinedBias

            local groundModelName, gm = GetGroundModelData(wd.contactMaterialID1)
            w.groundModel = gm

            local loadRaw = wd.downForce or 0
            local airborneState = (not wd.contactMaterialID1 or wd.contactMaterialID1 == -1) or (loadRaw <= 0)
            w.loadRaw, w.isAirborne = loadRaw, airborneState
            w.contactMatId = wd.contactMaterialID1 or -1
            w.isBroken = wd.isBroken or false
            w.isTireDeflated = wd.isTireDeflated or false
            w.dynamicRadius = wd.dynamicRadius or wd.radius or w.radius
            w.peakForce = wd.peakForce or 0
            w.contactDepth = wd.contactDepth or 0
            w.downForceRaw = wd.downForceRaw or loadRaw

            -- Invalidate surface cache when material changes (resolveWheelSurface also keys on this)
            if w.surfCacheMatId ~= w.contactMatId then
                w.surfaceType = nil
            end

            -- Immersion check (same path as stock brake underwater cooling)
            w.underWater = false
            if wd.node1 and obj and type(obj.inWater) == "function" then
                local okW, inW = pcall(obj.inWater, obj, wd.node1)
                w.underWater = okW and inW and true or false
            end

            -- Spike-strip material (ID 32) — sync progressive leak with stock puncture
            local mat1, mat2 = wd.contactMaterialID1, wd.contactMaterialID2
            if (mat1 == SPIKE_STRIP_MATERIAL_ID or mat2 == SPIKE_STRIP_MATERIAL_ID) and not w.isTireDeflated and not w.isBroken then
                data.leakRatePa = max(data.leakRatePa or 0, wd.punctureLeakRate or 20000)
                data.punctureSeverity = max(data.punctureSeverity or 0, 0.5)
            end

            local scrubSens = data.interpolatedMods and data.interpolatedMods.scrubSensitivity or 1.0
            local dynR = w.dynamicRadius or (wd.radius or 0.3)
            local surfaceSpeed = abs(wd.angularVelocity or 0) * dynR
            -- Toe scrub: soft-saturation v/(1+v/Vref) keeps effect proportional at low-mid speed
            -- and gently saturates above Vref rather than hard-capping. At v=Vref scrub is ~50%
            -- of linear extrapolation; real toe scrub saturates around highway speed.
            local toeScrubVref = THERMAL_TOPOLOGY.toeScrubVref or 70.0
            local toeScrubEnergy = (surfaceSpeed / (1.0 + surfaceSpeed / toeScrubVref)) * abs(sin(w.toeRad or 0)) * 0.025 * scrubSens

            -- Prefer BeamNG core slip energy (sounds.lua uses *5e-6); add explicit long/lat slip
            -- Fix A: high-|lastSlip| longComp boost so burnout/lock can smoke; cruise/corner stay flat.
            local gmStatic = gm.staticFrictionCoefficient or 1
            local nativeWork = (wd.slipEnergy or 0) * NATIVE_SLIP_ENERGY_SCALE
            local absLongSlip = abs(wd.lastSlip or 0)
            local longComp = absLongSlip * NATIVE_SLIP_VEL_SCALE * gmStatic
            local topoSlip = THERMAL_TOPOLOGY
            local boostStart = topoSlip.slipVelBoostStart or 8.0
            local boostFull = topoSlip.slipVelBoostFull or 24.0
            local boostMax = topoSlip.slipVelBoostMax or 9.0
            local boostSpan = max(1e-3, boostFull - boostStart)
            local boostRamp = max(0, min(1, (absLongSlip - boostStart) / boostSpan))
            boostRamp = boostRamp * boostRamp * (3.0 - 2.0 * boostRamp) -- smoothstep
            longComp = longComp * (1.0 + boostMax * boostRamp)
            local sideComp = abs(wd.lastSideSlip or 0) * NATIVE_SLIP_VEL_SCALE * gmStatic
            w.longSlipEnergy = longComp
            w.sideSlipEnergy = sideComp
            w.slipEnergy = max(nativeWork, longComp * 0.55 + sideComp * 0.45)
            local dynamicSlipEnergy = (w.slipEnergy + toeScrubEnergy) * (1.0 + abs(g_mag) * 0.15)
            -- Soft ground depth amplifies scrub/work slightly (paddling / ploughing)
            if (wd.contactDepth or 0) > 0.05 then
                dynamicSlipEnergy = dynamicSlipEnergy * (1.0 + min(0.6, wd.contactDepth))
            end
            w.dynamicSlipEnergy = dynamicSlipEnergy
        end
    end

end

runFixedPhysicsSteps = function(dt, localizedEnvTemp)
    gfxAccumulator = gfxAccumulator + dt
    if gfxAccumulator > 0.15 then gfxAccumulator = 0.15 end 
    
    while gfxAccumulator >= FIXED_DT do
        gfxAccumulator = gfxAccumulator - FIXED_DT
        gripStepCounter = gripStepCounter + 1
        local doGripStep = (gripStepCounter % GRIP_STEP_INTERVAL) == 0

        for i, wd in pairs(wheels.wheelRotators) do
            local wheel = (obj and obj.getWheel) and obj:getWheel(i) or nil
            local w = wheelCache[i]
            local data = tyreData[i]
            
            if wheel and w and data then
                -- Thermals / wear / pressure leak at 100Hz
                CalcTyreWear(i, FIXED_DT, localizedEnvTemp)

                local carcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias or 0, 1.0, localizedEnvTemp)
                local softFailTemp = (data.interpolatedMods and data.interpolatedMods.optimalTemp and data.interpolatedMods.optimalTemp >= 80) and 185 or 165
                if carcassTemp > softFailTemp and (data.leakRatePa or 0) < 5000 then
                    data.leakRatePa = max(data.leakRatePa or 0, 6000)
                end
                local cond = data.condition or 100
                if cond < 0.5 and (data.punctureSeverity or 0) > 0.8 then
                    deflateTireCompat(i)
                end

                -- Grip + BeamNG friction at 50Hz (every other fixed step)
                if doGripStep then
                    local longGrip, latGrip, grip = CalculateTyreGrip(i, localizedEnvTemp)
                    if longGrip ~= longGrip or latGrip ~= latGrip or longGrip <= 0.001 or latGrip <= 0.001 then
                        longGrip, latGrip, grip = 0.1, 0.1, 0.1
                    end
                    data.lastLongGrip, data.lastLatGrip, data.lastGrip = longGrip, latGrip, grip
                    tyreGripTable[i] = grip

                    if w.isTireDeflated or w.isBroken then
                        applyWheelFriction(wheel, 1.0, 1.0)
                    else
                        applyWheelFriction(wheel, longGrip, latGrip)
                    end
                end
            end
        end
    end
end

flushGuiStream = function(localizedEnvTemp)
        local totalLoadN = 0
        local topo = THERMAL_TOPOLOGY
        local airspeed = getFreestreamAirspeed()
        local aeroSpeedRange = max(1.0, topo.aeroHeatSpeedFull - topo.aeroHeatSpeedStart)
        local aeroRamp = max(0.0, min(1.0, (airspeed - topo.aeroHeatSpeedStart) / aeroSpeedRange))
        local aeroFracEst = aeroRamp * topo.aeroHeatMaxFrac

        for i, wd in pairs(wheels.wheelRotators) do
            local w = wheelCache[i]
            local data = tyreData[i]
            local idx = wheelIndexMap[i]
            if w and data and idx and guiStream.data[idx] then
                local entry = guiStream.data[idx]
                local rawLoad = w.loadRaw or wd.downForce or 0
                totalLoadN = totalLoadN + rawLoad
                entry.aeroLoadN = math.floor(rawLoad * aeroFracEst)
                local interpolatedMods = data.interpolatedMods
                local initialPressurePSI = wd.pressure or 25
                local cond = data.condition or 100
                local grip = data.lastGrip or tyreGripTable[i] or 1
                local longGrip = data.lastLongGrip or grip
                local latGrip = data.lastLatGrip or grip
                local carcassTemp = TempCarcassToAvgTemp(data.temp, w.combinedBias or 0, 1.0, localizedEnvTemp)

                entry.isBroken = w.isBroken
                entry.isDetached = w.isBroken
                entry.condition = (w.isBroken) and -1 or cond
                if not entry.zoneCondition then entry.zoneCondition = { cond, cond, cond } end
                local zc = data.zoneCondition or entry.zoneCondition
                entry.zoneCondition[1], entry.zoneCondition[2], entry.zoneCondition[3] = zc[1] or cond, zc[2] or cond, zc[3] or cond
                entry.tyreGrip = (w.isBroken) and 0 or grip
                entry.longGrip = (w.isBroken) and 0 or longGrip
                entry.latGrip = (w.isBroken) and 0 or latGrip
                entry.camber = (w.isBroken) and 0 or ((w.camber or 0) * (wd.wheelDir or 1))
                entry.toe = (w.isBroken) and 0 or math.floor((w.toe or 0) * 100) / 100
                entry.pressure = (w.isBroken or w.isTireDeflated) and 0 or (math.floor((data.currentPressurePSI or initialPressurePSI) * 10) / 10)
                entry.initialPressure = data.coldPressurePSI or initialPressurePSI
                entry.coldPressure = data.coldPressurePSI or initialPressurePSI
                entry.optimalPressure = interpolatedMods and interpolatedMods.optimalPressure or 25
                entry.targetHotPressure = data.targetHotPressurePSI or entry.optimalPressure
                entry.flatspot = (w.isBroken) and 0 or math.floor((data.currentFlatSpot or 0) * 100)
                entry.profile = (w.isBroken) and "none" or (interpolatedMods and interpolatedMods.descriptor or ((data.interpFactor > 0.5) and data.profile2 or data.profile1))
                entry.profile1 = data.profile1 or ""
                entry.profile2 = data.profile2 or ""
                entry.compoundClass = interpolatedMods and interpolatedMods.descriptor or entry.profile
                entry.cycles = data.heatCycles or 0
                entry.stintFade = math.floor((data.stintFade or 0) * 1000) / 10
                entry.leak = math.floor((data.punctureSeverity or 0) * 100)
                entry.waterFilm = math.floor(waterFilmDepth * 100)
                entry.ductPercent = data.ductPercent or getBrakeDuctPercent(data.isFront)
                entry.driveHeatGate = math.floor((data.lastDriveHeatGate or 0) * 1000) / 1000
                entry.driveHeatGateCarcass = math.floor((data.lastDriveHeatGateCarcass or 0) * 1000) / 1000

                entry.clog = (w.isBroken) and 0 or math.floor((data.currentClog or data.clog or 0) * 100)
                entry.graining = (w.isBroken) and 0 or math.floor((data.currentGraining or data.graining or 0) * 100)
                entry.blistering = (w.isBroken) and 0 or math.floor((data.currentBlistering or data.blistering or 0) * 100)
                entry.marbles = (w.isBroken) and 0 or math.floor((data.currentMarbles or data.marbles or 0) * 100)
                entry.surfaceDamage = (w.isBroken) and 0 or math.floor((data.currentSurfaceDamage or 0) * 100)

                local gm = w.groundModel or DOESNT_EXIST_DATA
                entry.surfaceName = gm.name or "unknown"
                entry.surfaceType = w.surfaceType or classifySurfaceGrip(gm.nameLower or gm.name or "")
                entry.muStatic = math.floor((gm.staticFrictionCoefficient or 1) * 1000) / 1000
                entry.muSlide = math.floor((gm.slidingFrictionCoefficient or entry.muStatic) * 1000) / 1000
                entry.rough = math.floor((tonumber(gm.rough) or 0) * 1000) / 1000
                entry.loadN = math.floor(w.loadRaw or wd.downForce or 0)
                entry.peakForce = math.floor(w.peakForce or 0)
                entry.dynamicRadius = math.floor(((w.dynamicRadius or wd.radius or 0.3) * 1000) + 0.5) / 1000
                entry.slipEnergy = math.floor((w.dynamicSlipEnergy or w.slipEnergy or 0) * 1000) / 1000
                entry.longSlip = math.floor((w.longSlipEnergy or 0) * 1000) / 1000
                entry.sideSlip = math.floor((w.sideSlipEnergy or 0) * 1000) / 1000
                entry.airborne = not not w.isAirborne

                entry.suspCompressionMm = math.floor((w.suspCompression or 0) * 1000)
                entry.suspVel = math.floor((w.suspensionVelocity or 0) * 1000) / 1000
                entry.suspStress = math.floor((w.suspStress or 0) * 1000) / 1000
                entry.suspBumpMm = math.floor((w.suspBump or 0) * 1000)
                entry.suspDroopMm = math.floor((w.suspDroop or 0) * 1000)

                if not entry.temp then entry.temp = { 0, 0, 0, 0, 0, 0, 0, 0 } end
                if data.temp and not w.isBroken then
                    data.temp = ensureTempNodes(data.temp, localizedEnvTemp)
                    for ti = 1, TEMP_NODE_COUNT do
                        entry.temp[ti] = math.floor((data.temp[ti] or localizedEnvTemp) * 10) / 10
                    end
                    entry.carcassAvg = math.floor(carcassTemp * 10) / 10
                    entry.rimTemp = math.floor((data.temp[7] or localizedEnvTemp) * 10) / 10
                    entry.airTemp = math.floor((data.temp[8] or localizedEnvTemp) * 10) / 10
                    local bSurf, bCore = getNativeBrakeTemps(wd, localizedEnvTemp)
                    entry.brakeSurface = math.floor(bSurf * 10) / 10
                    entry.brakeCore = math.floor(bCore * 10) / 10
                    entry.contactDepth = math.floor((w.contactDepth or 0) * 1000) / 1000
                    entry.underWater = not not w.underWater
                    entry.working_temp = math.floor(data.working_temp * 10) / 10
                else
                    for ti = 1, TEMP_NODE_COUNT do
                        entry.temp[ti] = localizedEnvTemp
                    end
                    entry.carcassAvg, entry.rimTemp, entry.airTemp = localizedEnvTemp, localizedEnvTemp, localizedEnvTemp
                    entry.brakeSurface, entry.brakeCore = localizedEnvTemp, localizedEnvTemp
                    entry.contactDepth, entry.underWater = 0, false
                    entry.working_temp = WORKING_TEMP
                end

                local optTemp = data.working_temp or WORKING_TEMP
                local avgT = EffectiveTyreTemp(data.temp, w.combinedBias, entry.pressure / (interpolatedMods and interpolatedMods.optimalPressure or 25), localizedEnvTemp, interpolatedMods)
                local tempRatio = avgT / (optTemp > 0 and optTemp or 1)
                if tempRatio < 0.80 then
                    entry.tempCategory = "Cold"
                elseif tempRatio > 1.20 then
                    entry.tempCategory = "Hot"
                else
                    entry.tempCategory = "Normal"
                end
                entry.avgTemp = math.floor(avgT * 10) / 10
                local hotTgt = max(1.0, entry.targetHotPressure or entry.optimalPressure or 25)
                entry.pressureRatio = math.floor((entry.pressure / hotTgt) * 1000) / 1000
                local skinAvg = ((entry.temp[1] or 0) + (entry.temp[2] or 0) + (entry.temp[3] or 0)) / 3.0
                entry.skinCarcassGap = math.floor((skinAvg - (entry.carcassAvg or skinAvg)) * 10) / 10
            end
        end

        -- Estimated total aerodynamic downforce across all wheels (N)
        guiStream.totalDownforceN = math.floor(totalLoadN * aeroFracEst)
        guiStream.aeroFracPct = math.floor(aeroFracEst * 100)

end


getTelemetryIo = function()
    local okIo, ioLib = pcall(function() return io end)
    if okIo and ioLib and type(ioLib.open) == "function" then
        return ioLib
    end
    return nil
end

-- Write header once per path; skip open/read/check on every sample.
ensureTelemetryHeader = function(ioLib, path)
    if telem.headerReady or not ioLib or not path then return end
    local exists = false
    local rf = ioLib.open(path, "r")
    if rf then
        local first = rf:read(1)
        exists = first ~= nil
        rf:close()
    end
    if exists then
        telem.headerReady = true
        return
    end
    local hdr = ioLib.open(path, "w")
    if hdr then
        hdr:write(telem.csvHeader)
        hdr:close()
        telem.headerReady = true
    end
end

clearTelemetryCsvBuffer = function()
    for i = 1, telem.csvBufCount do
        telem.csvBuffer[i] = nil
    end
    telem.csvBufCount = 0
end

-- Batch-append buffered lines in one open/write/close. Safe to call often (no-op if empty).
flushTelemetryBuffer = function(ioLib)
    ioLib = ioLib or getTelemetryIo()
    if not ioLib or not telem.path then
        telem.lastFlushClock = os.clock()
        return
    end
    if telem.csvBufCount <= 0 then
        telem.lastFlushClock = os.clock()
        return
    end
    ensureTelemetryHeader(ioLib, telem.path)
    local f = ioLib.open(telem.path, "a")
    if f then
        f:write(table.concat(telem.csvBuffer, "", 1, telem.csvBufCount))
        f:close()
    end
    clearTelemetryCsvBuffer()
    telem.lastFlushClock = os.clock()
end

telemetryBufferNeedsFlush = function()
    if telem.csvBufCount <= 0 then return false end
    if telem.csvBufCount >= telem.flushMaxLines then return true end
    local now = os.clock()
    if telem.lastFlushClock <= 0 then
        telem.lastFlushClock = now
        return false
    end
    return (now - telem.lastFlushClock) >= telem.flushWallSec
end

writeTelemetryArmMarker = function(path)
    local ioLib = getTelemetryIo()
    if not ioLib or not path then return end
    local f = ioLib.open(telem.armMarker, "w")
    if f then
        f:write(tostring(path) .. "\n")
        f:close()
    end
end

clearTelemetryArmMarker = function()
    pcall(function()
        os.remove(telem.armMarker)
    end)
end

-- Flush pending samples first so #RESET stays chronologically after them.
appendTelemetryResetMarker = function(ioLib, path, reason)
    ioLib = ioLib or getTelemetryIo()
    if not ioLib or not path then return end
    flushTelemetryBuffer(ioLib)
    ensureTelemetryHeader(ioLib, path)
    local f = ioLib.open(path, "a")
    if f then
        f:write(string.format("#RESET,%.3f,%s\n", os.clock(), tostring(reason or "reset")))
        f:close()
    end
    telem.lastFlushClock = os.clock()
end

restoreTelemetryAfterReload = function(reason)
    local ioLib = getTelemetryIo()
    if not ioLib then return end
    local mf = ioLib.open(telem.armMarker, "r")
    if not mf then return end
    local path = mf:read("*l")
    mf:close()
    if not path or #path < 3 then return end
    telem.path = path
    telem.headerReady = false
    telem.csvEnabled = true
    ensureTelemetryHeader(ioLib, path)
    appendTelemetryResetMarker(ioLib, path, reason or "vehicle_reload")
end

writeTelemetryIfEnabled = function(dt)
    -- Optional CSV telemetry (disabled by default). Samples go to an in-memory buffer;
    -- disk I/O only on flush (safety timer / line cap / disable / reset / explicit).
    if not telem.csvEnabled then return end
    telem.timer = telem.timer + dt
    if telem.timer < telem.interval then
        if telemetryBufferNeedsFlush() then
            flushTelemetryBuffer()
        end
        return
    end
    telem.timer = 0
    if not telem.path then
        telem.path = "tyre_thermals_telemetry.csv"
    end
    -- Ensure header once while armed (not every sample).
    if not telem.headerReady then
        local ioLib = getTelemetryIo()
        if ioLib then
            ensureTelemetryHeader(ioLib, telem.path)
        end
    end
    local tNow = (electrics and electrics.values and electrics.values.timer) or 0
    local wall = os.clock()
    for wheelID, data in pairs(tyreData) do
        data.temp = ensureTempNodes(data.temp, ENV_TEMP)
        local grip = data.lastGrip or tyreGripTable[wheelID] or 0
        local longG = data.lastLongGrip or grip
        local latG = data.lastLatGrip or grip
        telem.csvBufCount = telem.csvBufCount + 1
        telem.csvBuffer[telem.csvBufCount] = string.format(
            "%.3f,%.2f,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.2f,%.2f,%.2f,%.2f,%d,%.2f,%.2f,%.2f\n",
            wall, tNow, tostring(wheelID), data.condition or 0,
            data.temp[1] or 0, data.temp[2] or 0, data.temp[3] or 0,
            data.temp[4] or 0, data.temp[5] or 0, data.temp[6] or 0,
            data.temp[7] or 0, data.temp[8] or 0,
            data.currentPressurePSI or 0, grip, longG, latG,
            data.clog or 0, data.graining or 0, data.blistering or 0, data.marbles or 0,
            data.heatCycles or 0, data.stintFade or 0, data.punctureSeverity or 0, waterFilmDepth)
    end
    if telemetryBufferNeedsFlush() then
        flushTelemetryBuffer()
    end
end

updateGFX = function(dt)
    if not wheels or not wheels.wheelRotators then return end
    if not next(wheelIndexMap) then initGuiStream() end
    if not next(tyreData) then initTyreData() end

    -- Prefer GE mailbox when present (even if unchanged this frame). Previously we only
    -- marked envReceived on mailbox *change*, so native getEnvTemperature ran every frame
    -- between 2 Hz GE ticks and fought altitude/mailbox steps → noisy ΔT + wasted work.
    local envFromMailbox = false
    if obj and obj.getLastMailbox then
        local env = obj:getLastMailbox("tyreWearMailboxEnvTemp")
        if env then
            envFromMailbox = true
            if env ~= lastEnvMailbox then
                lastEnvMailbox = env
                local rawEnv = sanitizeEnvTemp(env)
                local blended = ENV_TEMP + (rawEnv - ENV_TEMP) * min(1.0, dt * ENV_SMOOTH_RATE)
                local maxStep = ENV_MAX_DELTA_PER_SEC * dt
                local delta = blended - ENV_TEMP
                if delta > maxStep then delta = maxStep elseif delta < -maxStep then delta = -maxStep end
                ENV_TEMP = ENV_TEMP + delta
                if rawEnv < rawEnvMin then rawEnvMin = rawEnv end
                if rawEnv > rawEnvMax then rawEnvMax = rawEnv end
            end
        end

        local trackEnvMailbox = obj:getLastMailbox("tyreWearMailboxTrackEnv")
        if trackEnvMailbox and trackEnvMailbox ~= lastTrackEnvMailbox then
            lastTrackEnvMailbox = trackEnvMailbox
            local ok, decoded = pcall(deserialize, trackEnvMailbox)
            if not ok or type(decoded) ~= "table" then ok, decoded = pcall(jsonDecode, trackEnvMailbox) end
            if ok and type(decoded) == "table" then
                trackEnv.timeOfDay = decoded.timeOfDay or trackEnv.timeOfDay
                trackEnv.cloudCover = decoded.cloudCover or trackEnv.cloudCover
            end
        end

        -- Front/Rear duct % from Tuning menu (GE createbrakeductsliders)
        local ductMailbox = obj:getLastMailbox("tyreWearMailboxDuct")
        if ductMailbox and ductMailbox ~= lastDuctMailbox then
            lastDuctMailbox = ductMailbox
            local ok, decoded = pcall(deserialize, ductMailbox)
            if not ok or type(decoded) ~= "table" then ok, decoded = pcall(jsonDecode, ductMailbox) end
            if ok and type(decoded) == "table" then
                brakeDuctSettings[1] = tonumber(decoded[1]) or brakeDuctSettings[1]
                brakeDuctSettings[2] = tonumber(decoded[2]) or brakeDuctSettings[2]
            end
        end

        -- Per-vehicle draft wake from LuuksDraftingMod (soft companion; no-op if absent)
        local draftMailbox = obj:getLastMailbox("tyreWearMailboxDraft")
        if draftMailbox and draftMailbox ~= draft.lastMailbox then
            draft.lastMailbox = draftMailbox
            local ok, decoded = pcall(deserialize, draftMailbox)
            if not ok or type(decoded) ~= "table" then ok, decoded = pcall(jsonDecode, draftMailbox) end
            if ok and type(decoded) == "table" then
                local myId = (obj.getID and obj:getID()) or objectId
                local mine = decoded[myId] or decoded[tostring(myId)]
                if type(mine) == "table" then
                    setDraftWake(mine.wake, mine.side, mine.push, mine.airTempDelta)
                end
            end
        end
    end

    decayDraftWake(dt)

    if not envFromMailbox and obj and type(obj.getEnvTemperature) == "function" then
        local nativeKelvin = obj:getEnvTemperature()
        if nativeKelvin and nativeKelvin > 0 then
            local nativeCelsius = nativeKelvin - 273.15
            local rawEnv = sanitizeEnvTemp(nativeCelsius)
            local blended = ENV_TEMP + (rawEnv - ENV_TEMP) * min(1.0, dt * ENV_SMOOTH_RATE)
            local maxStep = ENV_MAX_DELTA_PER_SEC * dt
            local delta = blended - ENV_TEMP
            if delta > maxStep then delta = maxStep elseif delta < -maxStep then delta = -maxStep end
            ENV_TEMP = ENV_TEMP + delta
            if rawEnv < rawEnvMin then rawEnvMin = rawEnv end
            if rawEnv > rawEnvMax then rawEnvMax = rawEnv end
        end
    end

    local localizedEnvTemp = ENV_TEMP
    -- Mild diurnal only as last-resort when env feed is completely flat (not a fake weather system)
    local envTempRange = rawEnvMax - rawEnvMin
    if envTempRange < 0.5 and (not envFromMailbox) then
        local rad = (trackEnv.timeOfDay - 0.16) * 2 * pi
        localizedEnvTemp = ENV_TEMP + 2.0 * -cos(rad)
    end

    -- Pack air: hotter ambient in a wake (inferred on 0.39+; companion on older builds)
    if draft.airTempEffective > 0 then
        localizedEnvTemp = localizedEnvTemp + draft.airTempEffective
    end

    -- Water film accumulation from rainState (0..1); decays when dry
    local rainState = 0
    if electrics and electrics.values and type(electrics.values.rainState) == "number" then
        rainState = max(0, min(1, electrics.values.rainState))
    end
    if rainState > 0 then
        waterFilmDepth = min(1.0, waterFilmDepth + rainState * dt * 0.15)
    else
        waterFilmDepth = max(0, waterFilmDepth - dt * 0.04)
    end
    -- Immersed wheels dump water onto the contact patch
    for _, wc in pairs(wheelCache) do
        if wc and wc.underWater then
            waterFilmDepth = min(1.0, waterFilmDepth + dt * 0.35)
            break
        end
    end

    -- Sample track surface once per GFX frame (physics + UI share this)
    frameTrackTemp = getTrackTemp(localizedEnvTemp, trackEnv.timeOfDay, trackEnv.cloudCover)
    
    local upVector = (obj and obj.getDirectionVectorUp) and obj:getDirectionVectorUp() or nil
    local frontVector = (obj and obj.getDirectionVector) and obj:getDirectionVector() or nil
    local invQuat = nil
    if upVector and frontVector and quatFromDir then
        local ok, q = pcall(quatFromDir, vec3(frontVector), vec3(upVector))
        if ok and q then invQuat = q:inversed() end
    end

    local airspeed = getFreestreamAirspeed()

    local gx_gfx = (sensors and (sensors.gx2 or sensors.gx) or 0) / 9.80665
    local gy_gfx = (sensors and (sensors.gy2 or sensors.gy) or 0) / 9.80665
    local g_mag = sqrt(gx_gfx * gx_gfx + gy_gfx * gy_gfx)

    prepareWheelFrame(dt, localizedEnvTemp, invQuat, upVector, airspeed, g_mag, gy_gfx)

    runFixedPhysicsSteps(dt, localizedEnvTemp)
    
    if DEBUG_THERMALS then
        local logParts = {}
        for wheelID, data in pairs(tyreData) do
            local avg = TempRingsToAvgTemp(data.temp, 0, 1.0, localizedEnvTemp)
            local carc = TempCarcassToAvgTemp(data.temp, 0, 1.0, localizedEnvTemp)
            local wName = wheelCache[wheelID] and wheelCache[wheelID].name or tostring(wheelID)
            table.insert(logParts, string.format("%s: Skin=%.1f Carc=%.1f Rim=%.1f Air=%.1f (Opt=%.1f)", wName, avg, carc, data.temp[7] or 0, data.temp[8] or 0, data.working_temp or 0))
        end
        print("TYRE_DEBUG: " .. table.concat(logParts, " | "))
    end

    sendTimer = sendTimer + dt
    if sendTimer >= SEND_INTERVAL then
        sendTimer = 0
        -- Global env snapshot only when flushing HUD (was every GFX frame)
        guiStream.envTemp = math.floor(localizedEnvTemp * 10) / 10
        guiStream.trackTemp = math.floor(frameTrackTemp * 10) / 10
        guiStream.rainState = math.floor((rainState or 0) * 100)
        guiStream.waterFilm = math.floor(waterFilmDepth * 100)
        guiStream.packWake = math.floor(max(draft.inferredWake, draft.coolingWake) * 100)
        guiStream.packAirDelta = math.floor(draft.airTempEffective * 10) / 10
        guiStream.streamHz = math.floor(1.0 / SEND_INTERVAL + 0.5)
        guiStream.timeOfDay = math.floor((trackEnv.timeOfDay or 0) * 1000) / 1000
        guiStream.cloudCover = math.floor((trackEnv.cloudCover or 0) * 100)
        guiStream.envTempRange = math.floor((rawEnvMax - rawEnvMin) * 10) / 10
        if obj and type(obj.getPosition) == "function" then
            local pos = obj:getPosition()
            if pos and pos.z then
                guiStream.elevationM = math.floor(pos.z * 10) / 10
            end
        end
        flushGuiStream(localizedEnvTemp)

        -- 0.39+: queueStream feeds StreamsManager / streamsUpdate. Prefer it alone so apps
        -- do not process the same payload twice (queueStream + trigger). Older builds keep trigger.
        -- Presence cached in onInit (hasQueueStream / hasGuiTrigger).
        if hasQueueStream then
            pcall(guihooks.queueStream, "TyreWearThermals", guiStream)
        elseif hasGuiTrigger then
            pcall(guihooks.trigger, "TyreWearThermals", guiStream)
        end
    end

    writeTelemetryIfEnabled(dt)
end

onInit = function()
    local t0 = (os and os.clock and os.clock()) or 0
    local ok, err = pcall(function()
        print("luukstyrethermalsandwear vehicle extension onInit")
        -- BeamNG 0.39+: native inter-vehicle aero authority (do NOT call setWindAero)
        draft.hasNativeInterAero = obj and type(obj.setWindAero) == "function"
        -- Cache GUI publish path once (hot flush must not re-type-check every tick)
        hasQueueStream = guihooks and type(guihooks.queueStream) == "function"
        hasGuiTrigger = guihooks and type(guihooks.trigger) == "function"
        local weight = 1500
        if type(tyre_utils) == "table" and type(tyre_utils.getVehWeight) == "function" then
            local ok_w, w = pcall(tyre_utils.getVehWeight)
            if ok_w and type(w) == "number" and w > 0 then weight = w end
        elseif v and v.data and v.data.nodes then
            local sum = 0
            for _, n in pairs(v.data.nodes) do
                if type(n) == "table" and type(n.nodeWeight) == "number" then sum = sum + n.nodeWeight end
            end
            if sum > 0 then weight = sum end
        end
        
        if weight < 100 then
            weight = weight * 1000
        end
        vehicleMass = weight

        if not next(groundModels) then
            local targetID = objectId or (obj and obj.getID and obj:getID()) or 0
            if obj and type(obj.queueGameEngineLua) == "function" then
                obj:queueGameEngineLua("if luukstyrethermalsandwear then luukstyrethermalsandwear.getGroundModels(" .. tostring(targetID) .. ") end")
            end
        end

        lastTrackEnvMailbox = nil
        lastEnvMailbox = nil
        cachedVehicleType = nil
        cachedRallyHardware = nil
        typeRetryCount = 0
        rawEnvMin = 100
        rawEnvMax = -100
        groundModelsLut = {}
        wheelCache = {}
        gfxAccumulator = 0
        waterFilmDepth = 0
        -- Keep / restore CSV arm across reset so stint data is never truncated
        telem.timer = 0
        brakeDuctSettings = { DUCT_DEFAULT_PCT, DUCT_DEFAULT_PCT }
        lastDuctMailbox = nil
        draft.lastMailbox = nil
        draft.wake, draft.side, draft.push = 0, 0, 0
        draft.airTempDelta, draft.coolingWake = 0, 0
        draft.lastRxClock = 0
        draft.inferredWake = 0
        draft.convectionMult, draft.airTempEffective = 1.0, 0
        baseBrakeCoolings = {}

        initTyreData()
        initGuiStream()
        -- Soft reset keeps locals; full vehicle reload re-runs module — restore from arm marker
        if not telem.csvEnabled then
            restoreTelemetryAfterReload("onInit")
        elseif telem.csvEnabled and telem.path then
            -- Flush any pending samples before #RESET so stint data is never lost
            appendTelemetryResetMarker(nil, telem.path, "onReset")
        end
    end)
    if not ok then
        print("luukstyrethermalsandwear onInit handled exception: " .. tostring(err))
    end
    local t1 = (os and os.clock and os.clock()) or t0
    local ms = (t1 - t0) * 1000
    if ms > 50 then
        local msg = string.format(
            "onInit took %.1f ms (nativeInterAero=%s). 0.39 may warn on slow extension loads.",
            ms, tostring(draft.hasNativeInterAero))
        if type(log) == "function" then
            log("W", "luukstyrethermalsandwear", msg)
        else
            print("W|luukstyrethermalsandwear|" .. msg)
        end
    elseif DEBUG_THERMALS then
        print(string.format("luukstyrethermalsandwear onInit %.1f ms nativeInterAero=%s", ms, tostring(draft.hasNativeInterAero)))
    end
end

onReset = function()
    onInit()
end

-- Vehicle deserialize / hard reload: flush if somehow still buffered, then restore arm.
onDeserialized = function(_data)
    flushTelemetryBuffer()
    if not telem.csvEnabled then
        restoreTelemetryAfterReload("onDeserialized")
    elseif telem.csvEnabled and telem.path then
        appendTelemetryResetMarker(nil, telem.path, "onDeserialized")
    end
end

-- 0.39 prefers onExtensionUnloaded over deprecated onUnload
onExtensionUnloaded = function()
    flushTelemetryBuffer()
    draft.wake, draft.side, draft.push = 0, 0, 0
    draft.airTempDelta, draft.coolingWake = 0, 0
    draft.inferredWake = 0
    draft.convectionMult, draft.airTempEffective = 1.0, 0
    draft.lastMailbox = nil
end

onSettingsChanged = function()
end

M.onSettingsChanged = onSettingsChanged
M.onInit = onInit
M.onReset = onReset
M.onDeserialized = onDeserialized
M.onExtensionUnloaded = onExtensionUnloaded
M.update = update
M.updateGFX = updateGFX
M.setGroundModels = setGroundModels
M.setDraftWake = setDraftWake
M.hasNativeInterAero = function() return draft.hasNativeInterAero end
M.getInferredWake = function() return draft.inferredWake end
M.setForceFeedbackFX = function(enabled) ENABLE_FORCE_FEEDBACK_FX = not not enabled end
M.setBrakeBiteHack = function(enabled) ENABLE_BRAKE_BITE_HACK = not not enabled end
M.flushTelemetryCsv = function()
    flushTelemetryBuffer()
end
M.setTelemetryCsv = function(enabled, path, intervalSec)
        local wasEnabled = telem.csvEnabled
        local prevPath = telem.path
        telem.csvEnabled = not not enabled
        if path and type(path) == "string" and #path > 0 then
            if telem.path and telem.path ~= path and telem.csvBufCount > 0 then
                -- Path change: flush old file before switching
                flushTelemetryBuffer()
            end
            if telem.path ~= path then
                telem.headerReady = false
            end
            telem.path = path
        end
        if type(intervalSec) == "number" and intervalSec > 0 then
            telem.interval = max(0.25, min(10.0, intervalSec))
        end
        if not telem.csvEnabled then
            -- Disarm: flush so no samples are stranded in RAM
            flushTelemetryBuffer()
            telem.timer = 0
            clearTelemetryArmMarker()
            return
        end
        if telem.path then
            writeTelemetryArmMarker(telem.path)
        end
        -- Header once on arm (or path change); not every sample / heartbeat re-arm
        if (not wasEnabled) or (prevPath ~= telem.path) or (not telem.headerReady) then
            local ioLib = getTelemetryIo()
            if ioLib and telem.path then
                ensureTelemetryHeader(ioLib, telem.path)
            end
        end
        if telem.lastFlushClock <= 0 then
            telem.lastFlushClock = os.clock()
        end
    end

return M
