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
    $g = $base * $ct * $p.gm
    $loadMod = 1.0 / (1.0 + $p.ls * [math]::Max(0.0, $loadRatio - 1.0))
    $g = $g * [math]::Max(0.70, $loadMod)
    return @{ baseline = $base; thermal = $tm; grip = $g }
}

$profiles = @(
    @{ name = 'standard'; c = @(0.92, 0.12, -0.04); gm = 0.96; ad = 0.40; tOpt = 60; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.60; ls = 0.035 },
    @{ name = 'sport'; c = @(1.02, 0.16, -0.06); gm = 1.00; ad = 0.42; tOpt = 66; plat = 16; wc = 62; wh = 55; fl = 0.28; comp = 0.50; ls = 0.036 },
    @{ name = 'vintage_standalone'; c = @(0.74, 0.10, -0.05); gm = 0.82; ad = 0.28; tOpt = 58; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.60; ls = 0.065 },
    @{ name = 'vintage_biasply'; c = @(0.74, 0.10, -0.05); gm = 0.80; ad = 0.28; tOpt = 56; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.65; ls = 0.065 },
    @{ name = 'classic_radial'; c = @(0.74, 0.10, -0.05); gm = 0.88; ad = 0.35; tOpt = 60; plat = 16; wc = 58; wh = 55; fl = 0.26; comp = 0.55; ls = 0.050 },
    @{ name = 'allterrain'; c = @(0.82, 0.10, -0.03); gm = 0.86; ad = 0.36; tOpt = 56; plat = 18; wc = 58; wh = 50; fl = 0.26; comp = 0.75; ls = 0.030 },
    @{ name = 'donut_spare'; c = @(0.68, 0.08, -0.03); gm = 0.74; ad = 0.25; tOpt = 48; plat = 18; wc = 58; wh = 50; fl = 0.26; comp = 0.80; ls = 0.028 }
)

$out = New-Object System.Collections.Generic.List[string]
$out.Add('profile,tempC,loadX,baseline,thermal,grip,pct_of_standard')
$stdWarm = (EffGrip $profiles[0] 60 1.0).grip
foreach ($p in $profiles) {
    foreach ($T in @(21, 35, 45, 56, 60, 70)) {
        foreach ($lr in @(1.0, 1.5)) {
            $e = EffGrip $p $T $lr
            $std = (EffGrip $profiles[0] $T $lr).grip
            $pct = if ($std -gt 0) { 100.0 * $e.grip / $std } else { 0 }
            $out.Add(('{0},{1},{2:n1},{3:n3},{4:n3},{5:n3},{6:n1}' -f $p.name, $T, $lr, $e.baseline, $e.thermal, $e.grip, $pct)
        }
    }
}
$out.Add('')
$out.Add('SUMMARY_WARM_1.0x_load_vs_standard_at_60C')
foreach ($p in $profiles) {
    $e = EffGrip $p 60 1.0
    $pct = 100.0 * $e.grip / $stdWarm
    $out.Add(('{0}: grip={1:n3} ({2:n0}% of standard {3:n3})' -f $p.name, $e.grip, $pct, $stdWarm)
}
$out.Add('')
$out.Add('SUMMARY_SPAWN_35C_1.0x')
foreach ($p in $profiles) {
    $e = EffGrip $p 35 1.0
    $std = (EffGrip $profiles[0] 35 1.0).grip
    $out.Add(('{0}: grip={1:n3} ({2:n0}% of standard)' -f $p.name, $e.grip, (100.0 * $e.grip / $std))
}
$path = Join-Path $PSScriptRoot 'vintage-grip-results.csv'
$out | Set-Content -LiteralPath $path -Encoding UTF8
Write-Output "Wrote $path"
$out | Select-Object -Last 20
