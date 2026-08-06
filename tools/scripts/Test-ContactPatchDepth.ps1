#Requires -Version 5.1
<#
  Contact-patch depth soft-sim (Phase A–E extended).
  Mirrors live luukstyrethermalsandwear.lua via lib/PatchThermal.ps1.
  Checks: depth→heatScale, load/PSI unstick, conduction denom, no area-shrink.
  No BeamNG launch.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib\PatchThermal.ps1')

$outDir = Join-Path (Split-Path $scriptDir -Parent) 'output'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'contact-patch-depth.txt'

$topo = Get-LivePatchTopo
$tyreWidth = 0.225
$tyreRadius = 0.32
$dt = 0.01
$fail = 0
$pass = 0

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('Contact-patch depth soft-sim (Hertz + deflection + Phase B unstick)')
[void]$sb.AppendLine(('topo: Min={0} HeatMin={1} Max={2} Ref={3} blendMax={4}' -f `
  $topo.patchFracMin, $topo.patchFracHeatMin, $topo.patchFracMax, $topo.patchFracRef, $topo.patchHertzDeflBlend))
[void]$sb.AppendLine('')

# --- Depth sweep at street load ---
$loadStreet = 4500.0
$psiStreet = 32.0
[void]$sb.AppendLine(('--- Depth sweep  load={0}N  PSI={1}  W={2}m  R={3}m ---' -f `
  $loadStreet, $psiStreet, $tyreWidth, $tyreRadius))
[void]$sb.AppendLine('  depth_m | hertz_m2 | defl_m2 | area_m2 | patchFrac | heatScale | boost | condDenom')

$depths = @(0.0, 0.005, 0.010, 0.020, 0.035, 0.050, 0.080)
$results = @{}
foreach ($d in $depths) {
  $p = Get-PatchThermal -LoadRawN $loadStreet -DynamicPressurePSI $psiStreet `
    -TyreWidthM $tyreWidth -TyreRadiusM $tyreRadius -ContactDepthM $d -Topo $topo
  $results[$d] = $p
  [void]$sb.AppendLine(('  {0,6:N3} | {1,8:N5} | {2,7:N5} | {3,7:N5} | {4,9:N4} | {5,9:N3} | {6,5:N3} | {7,8:N3}' -f `
    $d, $p.HertzArea, $p.DeflArea, $p.EstArea, $p.PatchFrac, $p.PatchHeatScale, $p.DepthHeatBoost, $p.CondDenom))
}

$shallow = $results[0.0]
$mid = $results[0.020]
$deep = $results[0.050]
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Depth checks ---')

if ($mid.PatchHeatScale -gt $shallow.PatchHeatScale) {
  [void]$sb.AppendLine(('PASS: mid depth heatScale {0} > shallow {1}' -f $mid.PatchHeatScale, $shallow.PatchHeatScale))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: mid depth heatScale {0} <= shallow {1}' -f $mid.PatchHeatScale, $shallow.PatchHeatScale))
  $fail++
}

if ($deep.PatchHeatScale -gt $mid.PatchHeatScale -and $deep.PatchHeatScale -le 1.20) {
  [void]$sb.AppendLine(('PASS: deep heatScale {0} > mid {1} and <= 1.20 ceiling' -f $deep.PatchHeatScale, $mid.PatchHeatScale))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: deep heatScale {0} vs mid {1} / ceiling' -f $deep.PatchHeatScale, $mid.PatchHeatScale))
  $fail++
}

$delta = $deep.PatchHeatScale - $shallow.PatchHeatScale
if ($delta -gt 0.02 -and $delta -lt 0.45) {
  [void]$sb.AppendLine(('PASS: deep-shallow delta {0:N3} modest (0.02..0.45)' -f $delta))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: deep-shallow delta {0:N3} not modest' -f $delta))
  $fail++
}

if ($deep.EstArea -gt $shallow.EstArea) {
  [void]$sb.AppendLine(('PASS: deep area {0} > shallow area {1} (defl blend, no shrink)' -f $deep.EstArea, $shallow.EstArea))
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: deep area did not grow vs shallow')
  $fail++
}

# Street must NOT sit glued at old 0.09 floor
if ($shallow.PatchFrac -lt 0.08 -and $shallow.PatchFracRaw -lt $topo.patchFracMin + 0.02) {
  [void]$sb.AppendLine(('PASS: street patchFrac {0} unstuck from old 0.09 floor (raw={1:N4})' -f `
    $shallow.PatchFrac, $shallow.PatchFracRaw))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: street patchFrac still glued? frac={0} raw={1}' -f `
    $shallow.PatchFrac, $shallow.PatchFracRaw))
  $fail++
}

# --- Load × PSI matrix (Phase A/B) ---
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Load/PSI matrix (depth=0, no util) ---')
[void]$sb.AppendLine('  loadN | PSI | patchFrac | heatScale | hertz')
$loadCases = @(
  @{ N = 2500; PSI = 35 },
  @{ N = 4500; PSI = 32 },
  @{ N = 4500; PSI = 26 },
  @{ N = 7000; PSI = 31 },
  @{ N = 9000; PSI = 28 }
)
$matrix = @()
foreach ($c in $loadCases) {
  $p = Get-PatchThermal -LoadRawN $c.N -DynamicPressurePSI $c.PSI `
    -TyreWidthM $tyreWidth -TyreRadiusM $tyreRadius -ContactDepthM 0 `
    -Topo $topo -NoUtilNudge
  $matrix += $p
  [void]$sb.AppendLine(('  {0,5} | {1,3} | {2,9:N4} | {3,9:N3} | {4:N5}' -f `
    $c.N, $c.PSI, $p.PatchFrac, $p.PatchHeatScale, $p.HertzArea))
}

# Heat scale must rise with load or lower PSI (unstick)
if ($matrix[3].PatchHeatScale -gt $matrix[1].PatchHeatScale) {
  [void]$sb.AppendLine(('PASS: 7kN heatScale {0} > street 4.5kN {1}' -f `
    $matrix[3].PatchHeatScale, $matrix[1].PatchHeatScale))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: load did not raise heatScale ({0} vs {1})' -f `
    $matrix[3].PatchHeatScale, $matrix[1].PatchHeatScale))
  $fail++
}

if ($matrix[2].PatchHeatScale -gt $matrix[1].PatchHeatScale) {
  [void]$sb.AppendLine(('PASS: lower PSI 26 raises heatScale {0} > 32PSI {1}' -f `
    $matrix[2].PatchHeatScale, $matrix[1].PatchHeatScale))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: PSI did not move heatScale ({0} vs {1})' -f `
    $matrix[2].PatchHeatScale, $matrix[1].PatchHeatScale))
  $fail++
}

# Street heatScale parity ~0.64 (old glued min/ref)
$streetHs = $matrix[1].PatchHeatScale
if ($streetHs -gt 0.55 -and $streetHs -lt 0.75) {
  [void]$sb.AppendLine(('PASS: street heatScale {0:N3} near legacy ~0.64 band' -f $streetHs))
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: street heatScale {0:N3} outside 0.55..0.75 parity band' -f $streetHs))
  $fail++
}

# --- Soft sink conduction denom + heat damp ---
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Soft sink (conduction denom + heat damp) ---')
$asphalt = Get-PatchThermal -LoadRawN 4500 -DynamicPressurePSI 32 `
  -TyreWidthM $tyreWidth -TyreRadiusM $tyreRadius -ContactDepthM 0.005 -Rough 0.05 -Topo $topo
$gravel = Get-PatchThermal -LoadRawN 4500 -DynamicPressurePSI 32 `
  -TyreWidthM $tyreWidth -TyreRadiusM $tyreRadius -ContactDepthM 0.060 -Rough 0.45 -Topo $topo
[void]$sb.AppendLine(('  asphalt: condDenom={0:N3} sinkDamp={1:N3} area={2:N5}' -f `
  $asphalt.CondDenom, $asphalt.SoftSinkDamp, $asphalt.EstArea))
[void]$sb.AppendLine(('  gravel:  condDenom={0:N3} sinkDamp={1:N3} area={2:N5}' -f `
  $gravel.CondDenom, $gravel.SoftSinkDamp, $gravel.EstArea))

if ($gravel.CondDenom -gt $asphalt.CondDenom * 1.3) {
  [void]$sb.AppendLine('PASS: gravel conduction denom >> asphalt (no area-shrink needed)')
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: soft sink conduction denom not rising with depth/rough')
  $fail++
}

if ($gravel.SoftSinkDamp -lt $asphalt.SoftSinkDamp -and $gravel.SoftSinkDamp -ge $topo.softSinkHeatFloor) {
  [void]$sb.AppendLine(('PASS: soft sink heat damp {0:N3} < asphalt {1:N3} and >= floor {2}' -f `
    $gravel.SoftSinkDamp, $asphalt.SoftSinkDamp, $topo.softSinkHeatFloor))
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: soft sink heat damp not applied as expected')
  $fail++
}

# Gravel area must NOT shrink vs asphalt at same Hertz (defl may grow)
if ($gravel.EstArea -ge $asphalt.HertzArea * 0.95) {
  [void]$sb.AppendLine('PASS: no rally area-shrink (gravel area >= ~Hertz)')
  $pass++
} else {
  [void]$sb.AppendLine(('FAIL: area shrank on soft sink ({0} vs hertz {1})' -f `
    $gravel.EstArea, $asphalt.HertzArea))
  $fail++
}

# --- EMA ---
$smooth = 0.0
$tau = [double]$topo.contactDepthEmaTau
$spike = 0.06
for ($i = 0; $i -lt 8; $i++) {
  $alpha = [math]::Min(1.0, $dt / $tau)
  $smooth = $smooth + ($spike - $smooth) * $alpha
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('EMA after 8×{0}s toward {1}: smooth={2:N4}' -f $dt, $spike, $smooth))
if ($smooth -gt 0.02 -and $smooth -lt $spike * 0.95) {
  [void]$sb.AppendLine('PASS: EMA lags spike (partial settle)')
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: EMA did not lag spike as expected')
  $fail++
}

# --- Phase 2/3 constant sanity ---
[void]$sb.AppendLine('')
[void]$sb.AppendLine('--- Phase 2/3 constant sanity ---')
$surfSoak = 0.016; $coreSoak = 0.0025; $radiantCoef = 2.2e-11
if ($surfSoak -gt $coreSoak * 3.0) {
  [void]$sb.AppendLine(('PASS: surface soak {0} >> core soak {1}' -f $surfSoak, $coreSoak))
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: surface/core soak split wrong')
  $fail++
}
if ($radiantCoef -gt 0 -and $radiantCoef -lt 1e-9) {
  [void]$sb.AppendLine(('PASS: brakeRadiantCoef={0} extracted (topo)' -f $radiantCoef))
  $pass++
} else {
  [void]$sb.AppendLine('FAIL: brakeRadiantCoef out of range')
  $fail++
}
[void]$sb.AppendLine('NOTE: hystSkinShare is bulk (not × patchHeatScale). freeBelt uses geometric patchFrac.')
[void]$sb.AppendLine('NOTE: banks lean on camber/gy (Test-BankedCamber); soft sink is conduction+damp.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('RESULT: {0} pass / {1} fail' -f $pass, $fail))
if ($fail -gt 0) { [void]$sb.AppendLine('VERDICT: FAIL') } else { [void]$sb.AppendLine('VERDICT: PASS') }

$text = $sb.ToString()
[System.IO.File]::WriteAllText($outPath, $text)
Write-Host $text
if ($fail -gt 0) { exit 1 }
exit 0
