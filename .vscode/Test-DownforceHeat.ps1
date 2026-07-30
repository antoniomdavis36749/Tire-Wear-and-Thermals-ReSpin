<#
.SYNOPSIS
    Soft-sim sweep: downforce heat aggressiveness analysis + tuning record.
    Validates the aeroHeatScale discount applied in luukstyrethermalsandwear.lua.

.DESCRIPTION
    Analyses the effective load_kg_thermal multiplier across speed / downforce levels,
    verifies the reduction is conservative (still thermally meaningful) and produces a
    before/after delta table.
#>

# ============================================================
# CONSTANTS (must match THERMAL_TOPOLOGY in the Lua file)
# ============================================================
$AERO_HEAT_SCALE      = 0.55    # aero portion efficiency vs mechanical load
$AERO_SPEED_START_MS  = 15.0    # m/s  (~54 km/h)
$AERO_SPEED_FULL_MS   = 56.0    # m/s  (~202 km/h)
$AERO_MAX_FRAC        = 0.48    # max fraction of load assumed aero at full speed

# load_kg non-linear curve (mirrors Lua)
function Get-LoadKg([double]$loadN) {
    $lkg = $loadN / 9.81
    $lkg = ((400 + $lkg) * $lkg / (100 + $lkg)) - 0.15 * $lkg
    return $lkg
}

# aero ramp at a given airspeed
function Get-AeroRamp([double]$speedMs) {
    $range = [Math]::Max(1.0, $AERO_SPEED_FULL_MS - $AERO_SPEED_START_MS)
    $ramp  = [Math]::Max(0.0, [Math]::Min(1.0, ($speedMs - $AERO_SPEED_START_MS) / $range))
    return $ramp
}

# thermal load fraction
function Get-ThermalLoadFrac([double]$speedMs) {
    $ramp    = Get-AeroRamp $speedMs
    $frac    = $ramp * $AERO_MAX_FRAC
    $thermal = 1.0 - $frac * (1.0 - $AERO_HEAT_SCALE)
    return $thermal
}

# ============================================================
# SWEEP TABLE: speed vs thermal load fraction
# ============================================================
Write-Host ""
Write-Host "=== AERO HEAT DISCOUNT: speed sweep ===" -ForegroundColor Cyan
Write-Host ("  {0,-18} {1,-12} {2,-14} {3,-14} {4,-12}" -f "Speed","AeroRamp","AeroFrac","ThermalFrac","Discount%")
Write-Host ("-" * 72)

foreach ($kmh in @(0, 50, 80, 100, 130, 160, 200, 250, 300)) {
    $ms      = $kmh / 3.6
    $ramp    = Get-AeroRamp $ms
    $frac    = $ramp * $AERO_MAX_FRAC
    $tFrac   = Get-ThermalLoadFrac $ms
    $disc    = (1 - $tFrac) * 100
    Write-Host ("  {0,-8} km/h ({1:F1} m/s)   ramp={2:F3}  aeroFrac={3:F3}  thermal={4:F3}  -{5:F1}%" -f $kmh, $ms, $ramp, $frac, $tFrac, $disc)
}

# ============================================================
# SOFT-SIM: before/after delta for Scintilla GT at 200 km/h
#   Assumptions:
#     - Static corner load:  ~3100 N  (1250 kg car / 4 wheels * 9.81)
#     - Aero rear corner:    ~520 N   (est. ~2000 N total rear aero @ 200 km/h)
#     - Total rear loadRaw:  ~3620 N
# ============================================================
Write-Host ""
Write-Host "=== SOFT-SIM: Scintilla GT rear corner at 200 km/h ===" -ForegroundColor Cyan

$staticLoad  = 3100   # N
$aeroExtra   = 520    # N estimated rear-corner aero addition @ 200 km/h
$totalLoad   = $staticLoad + $aeroExtra
$speedKmh    = 200
$speedMs     = $speedKmh / 3.6

$load_kg_base = Get-LoadKg $staticLoad
$load_kg_full = Get-LoadKg $totalLoad
$thermalFrac  = Get-ThermalLoadFrac $speedMs
$load_kg_thermal = $load_kg_full * $thermalFrac

Write-Host ("  Static load:           {0,6} N  → load_kg = {1:F1}" -f $staticLoad, $load_kg_base)
Write-Host ("  Static+aero load:      {0,6} N  → load_kg = {1:F1}" -f $totalLoad,  $load_kg_full)
Write-Host ("  Thermal load (scaled): {0,6} N  → load_kg_thermal = {1:F1}  (×{2:F3})" -f $totalLoad, $load_kg_thermal, $thermalFrac)
Write-Host ""

$rawRatio      = $load_kg_full / $load_kg_base
$thermalRatio  = $load_kg_thermal / $load_kg_base
$rawDeltaPct   = ($rawRatio - 1) * 100
$thermalDeltaPct = ($thermalRatio - 1) * 100

Write-Host ("  BEFORE (no discount): aero adds {0:F1}% more heat generation" -f $rawDeltaPct) -ForegroundColor Yellow
Write-Host ("  AFTER  (discounted):  aero adds {0:F1}% more heat generation" -f $thermalDeltaPct) -ForegroundColor Green
Write-Host ""
Write-Host ("  Reduction in aero thermal impact: {0:F1} percentage points" -f ($rawDeltaPct - $thermalDeltaPct)) -ForegroundColor Cyan

# ============================================================
# VERDICT
# ============================================================
Write-Host ""
Write-Host "=== VERDICT ===" -ForegroundColor Cyan
$verdict = if ($rawDeltaPct -gt 12) { "Too aggressive (pre-fix)" } else { "OK" }
Write-Host ("  Pre-fix aero heat delta: {0:F1}%  → {1}" -f $rawDeltaPct, $verdict) -ForegroundColor ($rawDeltaPct -gt 12 ? "Red" : "Green")
$verdict2 = if ($thermalDeltaPct -ge 3 -and $thermalDeltaPct -le 10) { "GOOD (still meaningful)" } else { "CHECK" }
Write-Host ("  Post-fix aero heat delta: {0:F1}%  → {1}" -f $thermalDeltaPct, $verdict2) -ForegroundColor ($verdict2 -eq "GOOD (still meaningful)" ? "Green" : "Yellow")

# ============================================================
# PARAMETERS CHANGED
# ============================================================
Write-Host ""
Write-Host "=== CHANGES TO luukstyrethermalsandwear.lua ===" -ForegroundColor Cyan
Write-Host "  THERMAL_TOPOLOGY additions:"
Write-Host "    aeroHeatScale      = 0.55  (aero load thermal efficiency; was effectively 1.0)"
Write-Host "    aeroHeatSpeedStart = 15.0  m/s  (~54 km/h)"
Write-Host "    aeroHeatSpeedFull  = 56.0  m/s  (~200 km/h)"
Write-Host "    aeroHeatMaxFrac    = 0.48  (max aero fraction of total load at peak speed)"
Write-Host ""
Write-Host "  New variable in CalcTyreThermals():"
Write-Host "    load_kg_thermal = load_kg * (1 - aeroFrac * (1 - aeroHeatScale))"
Write-Host "    Replaces load_kg in: loadCoeff (skin), loadRrHeat, flexWarmHeat, flexExcess"
Write-Host "    Does NOT change: loadRaw/loadN (grip), flexWarmLoad gate (onset behavior)"
Write-Host ""
Write-Host "  GUI stream additions:"
Write-Host "    guiStream.totalDownforceN  – estimated total aero downforce (N) all wheels"
Write-Host "    guiStream.aeroFracPct      – speed-based aero fraction %"
Write-Host "    entry.aeroLoadN            – per-wheel estimated aero load (N)"
Write-Host ""
Write-Host "Done." -ForegroundColor Green
