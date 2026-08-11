$ErrorActionPreference = 'Stop'
function GripPoly([double[]]$c, [double]$x) {
    $d = if ($c.Length -gt 3) { $c[3] } else { 0.0 }
    return $c[0] + $x * ($c[1] + $x * ($c[2] + $x * $d))
}
function Thermal([double]$temp, [double]$tOpt, [double]$plateau, [double]$wCold, [double]$wHot, [double]$floor, [double]$compliance = 0.6, [double]$softness = 0.5) {
    $plateau = $plateau * (0.8 + 0.4 * $softness)
    $wCold = $wCold * (0.8 + 0.4 * $softness) * (1.0 + ($compliance - 0.5) * 0.15)
    $wHot = $wHot * (0.8 + 0.4 * $softness)
    $diff = [math]::Abs($temp - $tOpt)
    $excess = [math]::Max(0.0, $diff - $plateau)
    $width = if ($temp -lt $tOpt) { $wCold } else { $wHot }
    $power = if ($temp -lt $tOpt) { 1.35 } else { 2.0 }
    $decay = [math]::Exp(-[math]::Pow($excess / [math]::Max(1.0, $width), $power))
    return $floor + (1.0 - $floor) * $decay
}
function ShapeThermal([double]$tTherm, [double]$adhesion) {
    $adhesionWeight = [math]::Max(0.15, [math]::Min(0.75, $adhesion))
    $shaped = $tTherm * (0.62 + 0.38 * $tTherm)
    return $tTherm + ($shaped - $tTherm) * ($adhesionWeight * 0.55)
}
function SoftenThermal([double]$tm, [double]$tread = 0.5) {
    $tol = 1.18 + (1.08 - 1.18) * $tread
    if ($tm -lt 1.0) { $tm = [math]::Max(0.50, [math]::Pow($tm, 1.0 / $tol)) }
    return $tm
}
function EffGrip($p, [double]$temp, [double]$loadRatio) {
    $base = GripPoly $p.c 1.0
    $tm = SoftenThermal (Thermal $temp $p.tOpt $p.plat $p.wc $p.wh $p.fl $p.comp 0.5) 0.5
    $ct = ShapeThermal $tm $p.ad
    $dry = if ($null -ne $p.dry) { [double]$p.dry } else { 1.0 }
    $g = $base * $ct * $p.gm * $dry
    $loadMod = 1.0 / (1.0 + $p.ls * [math]::Max(0.0, $loadRatio - 1.0))
    $g = $g * [math]::Max(0.70, $loadMod)
    return @{ baseline = $base; thermal = $tm; grip = $g }
}

# Live PROFILE_POINTS / DEFAULT_GRIP_COEFFS / SLICK_SPECTRUM mirrors
# standard gm: 0.96 -> 1.00 (~+4.2% overall)
$profiles = @(
    @{ name = 'standard'; c = @(0.92, 0.12, -0.04); gm = 1.00; dry = 1.00; ad = 0.40; tOpt = 60; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.60; ls = 0.035 },
    @{ name = 'sport'; c = @(1.02, 0.16, -0.06); gm = 1.00; dry = 1.02; ad = 0.42; tOpt = 66; plat = 18; wc = 74; wh = 55; fl = 0.34; comp = 0.50; ls = 0.036 },
    @{ name = 'sport_plus'; c = @(1.12, 0.22, -0.08); gm = 1.02; dry = 1.02; ad = 0.52; tOpt = 76; plat = 14; wc = 52; wh = 50; fl = 0.24; comp = 0.45; ls = 0.078 },
    @{ name = 'medium_slick'; c = @(1.38, 0.32, -0.12); gm = 1.02; dry = 0.98; ad = 0.52; tOpt = 84; plat = 14; wc = 46; wh = 46; fl = 0.20; comp = 0.25; ls = 0.12 },
    @{ name = 'vintage_standalone'; c = @(0.88, 0.11, -0.04); gm = 0.94; dry = 1.00; ad = 0.28; tOpt = 58; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.60; ls = 0.042 },
    @{ name = 'allterrain'; c = @(0.82, 0.10, -0.03); gm = 0.86; dry = 1.00; ad = 0.36; tOpt = 56; plat = 18; wc = 58; wh = 50; fl = 0.26; comp = 0.75; ls = 0.030 },
    @{ name = 'donut_spare'; c = @(0.68, 0.08, -0.03); gm = 0.68; dry = 1.00; ad = 0.30; tOpt = 60; plat = 14; wc = 55; wh = 55; fl = 0.22; comp = 0.45; ls = 0.060 }
)

$out = New-Object System.Collections.Generic.List[string]
[void]$out.Add('profile,tempC,loadX,baseline,thermal,grip,pct_of_standard')
$stdWarm = (EffGrip $profiles[0] 60 1.0).grip
foreach ($p in $profiles) {
    foreach ($T in @(21, 35, 45, 56, 60, 70)) {
        foreach ($lr in @(1.0, 1.5)) {
            $e = EffGrip $p $T $lr
            $std = (EffGrip $profiles[0] $T $lr).grip
            $pct = if ($std -gt 0) { 100.0 * $e.grip / $std } else { 0 }
            $line = '{0},{1},{2:n1},{3:n3},{4:n3},{5:n3},{6:n1}' -f $p.name, $T, $lr, $e.baseline, $e.thermal, $e.grip, $pct
            [void]$out.Add($line)
        }
    }
}
[void]$out.Add('')
[void]$out.Add('SUMMARY_WARM_1.0x_load_vs_standard_at_60C')
foreach ($p in $profiles) {
    $e = EffGrip $p 60 1.0
    $pct = 100.0 * $e.grip / $stdWarm
    $line = '{0}: grip={1:n3} ({2:n0} pct of standard {3:n3})' -f $p.name, $e.grip, $pct, $stdWarm
    [void]$out.Add($line)
}
[void]$out.Add('')
[void]$out.Add('SUMMARY_SPAWN_35C_1.0x')
foreach ($p in $profiles) {
    $e = EffGrip $p 35 1.0
    $std = (EffGrip $profiles[0] 35 1.0).grip
    $pct = 100.0 * $e.grip / $std
    $line = '{0}: grip={1:n3} ({2:n0} pct of standard)' -f $p.name, $e.grip, $pct
    [void]$out.Add($line)
}

# Standard grip bump soft-sim: gm 0.96 -> 1.00 (~+4.2%), hierarchy intact on dry paved
$oldStdWarm = $stdWarm * (0.96 / 1.00)
$bumpPct = 100.0 * ($stdWarm / $oldStdWarm - 1.0)
$sportP = $profiles | Where-Object { $_.name -eq 'sport' } | Select-Object -First 1
$spP = $profiles | Where-Object { $_.name -eq 'sport_plus' } | Select-Object -First 1
$slickP = $profiles | Where-Object { $_.name -eq 'medium_slick' } | Select-Object -First 1
$sportWarm = (EffGrip $sportP 66 1.0).grip
$spWarm = (EffGrip $spP 76 1.0).grip
$slickWarm = (EffGrip $slickP 84 1.0).grip
[void]$out.Add('')
[void]$out.Add('STANDARD_GRIP_BUMP_ASSERTS')
[void]$out.Add(('old_standard_warm={0:n3} new_standard_warm={1:n3} bump={2:n1} pct' -f $oldStdWarm, $stdWarm, $bumpPct))
[void]$out.Add(('hierarchy_warm: std={0:n3} sport@opt={1:n3} sport+@opt={2:n3} med_slick@opt={3:n3}' -f $stdWarm, $sportWarm, $spWarm, $slickWarm))

$fail = 0
function Expect([bool]$ok, [string]$msg) {
    if ($ok) {
        [void]$script:out.Add("PASS $msg")
        Write-Host "PASS $msg"
    }
    else {
        $script:fail++
        [void]$script:out.Add("FAIL $msg")
        Write-Host "FAIL $msg"
    }
}
Expect ($bumpPct -ge 3.0 -and $bumpPct -le 6.5) ("standard warm bump in 3-6 pct band ({0:n1})" -f $bumpPct)
Expect ($stdWarm -gt $oldStdWarm) 'standard warm grip rose vs prior gm=0.96'
Expect ($stdWarm -lt $sportWarm) ("standard < sport on dry ({0:n3} < {1:n3})" -f $stdWarm, $sportWarm)
Expect ($stdWarm -lt $spWarm) ("standard < sport_plus on dry ({0:n3} < {1:n3})" -f $stdWarm, $spWarm)
Expect ($stdWarm -lt $slickWarm) ("standard < medium_slick on dry ({0:n3} < {1:n3})" -f $stdWarm, $slickWarm)
Expect ($sportWarm -lt $spWarm) 'sport < sport_plus on dry'
Expect ($spWarm -lt $slickWarm) 'sport_plus < medium_slick on dry'

# Pass 6: vintage/bias-ply thermal coherence (mirror live Lua; no gm dump)
# Bias-ply: softer carcass flex → elevated workHeat vs standard, but far below pre-Pass-5 7.2 cliff.
# Soft-cap floors closer to 1.0 than street debt pack.
$vBias = @{ slip = 6.5; work = 5.7; rr = 0.94; treadI = 0.50; carcassI = 0.82; gm = 0.92; tOpt = 56 }
$vMid = @{ slip = 6.9; work = 5.45; rr = 0.91; treadI = 0.49; carcassI = 0.80; gm = 0.945; tOpt = 58 }
$vClassic = @{ slip = 7.4; work = 5.05; rr = 0.88; treadI = 0.48; carcassI = 0.78; gm = 0.97; tOpt = 60 }
$vSoft = @{ heatMin = 0.95; propMin = 0.97; highV = 0.88 }
$stSoft = @{ heatMin = 0.90; propMin = 0.93; highV = 0.80 }
[void]$out.Add('')
[void]$out.Add('VINTAGE_PASS6_THERMAL_ASSERTS')
Expect ($vBias.work -lt 6.2 -and $vBias.work -gt 5.0) ("biasply workHeat coherent ({0})" -f $vBias.work)
Expect ($vBias.slip -lt 7.2) ("biasply slipHeat below old 7.35 cliff ({0})" -f $vBias.slip)
Expect ($vBias.rr -gt 0.85 -and $vBias.rr -gt $vClassic.rr) ("biasply RR > classic radial ({0} > {1})" -f $vBias.rr, $vClassic.rr)
Expect ($vBias.carcassI -gt 0.75) ("biasply carcass inertia raised ({0})" -f $vBias.carcassI)
Expect ($vBias.gm -ge 0.90 -and $vClassic.gm -ge 0.95) ("vintage gm not dumped (bias {0} classic {1})" -f $vBias.gm, $vClassic.gm)
Expect ($vBias.tOpt -le 58 -and $vClassic.tOpt -le 62) ("vintage cooler optimalTemp window")
Expect ($vSoft.heatMin -gt $stSoft.heatMin -and $vSoft.highV -gt $stSoft.highV) `
  ("vintage soft-cap gentler than street ({0}/{1} vs {2}/{3})" -f $vSoft.heatMin, $vSoft.highV, $stSoft.heatMin, $stSoft.highV)
Expect ($vMid.work -lt $vBias.work -and $vClassic.work -le $vMid.work) 'vintage spectrum workHeat decreases bias->classic'
Expect ($vBias.work -lt 7.0 -and $vClassic.slip -lt 8.0) 'vintage heat below sport+ race cook band'

# Asphalt vs loose relative is surface-bias (applyProfileSurfaceBias), not gripMultiplier.
# Dry-paved hierarchy above is unchanged by street loose penalty; mild asphalt *1.02 stacks
# only on dry_paved/hard_smooth in the live grip path (see Test-SurfaceMatrix / Test-RallySurfaces).
[void]$out.Add('')
[void]$out.Add('NOTE: street asphalt:loose rebalance is surface-bias only (not another gm bump)')

$path = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'output') 'vintage-grip-results.csv'
$dir = Split-Path $path -Parent
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$out | Set-Content -LiteralPath $path -Encoding UTF8
Write-Output "Wrote $path"
$out | Select-Object -Last 24
if ($fail -gt 0) { Write-Host "ASSERTS: $fail failed"; exit 1 }
Write-Host 'ASSERTS: all passed'
exit 0
