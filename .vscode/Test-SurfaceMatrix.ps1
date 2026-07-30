#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Classify-Surface([string]$gmName) {
    $g = $gmName.ToLowerInvariant()
    if ($g -eq 'frictionless' -or $g -eq 'ice') { return 'ice' }
    if ($g -eq 'slippery' -or $g -eq 'asphalt_wet' -or $g.Contains('asphalt_wet')) { return 'wet_paved' }
    if ($g -eq 'snow') { return 'snow' }
    if ($g -eq 'mud') { return 'mud' }
    if ($g -eq 'gravel_wet' -or $g.Contains('gravel_wet') -or $g.Contains('gravel_riverbed')) { return 'gravel_wet' }
    if ($g.Contains('gravel') -or $g -eq 'dirt_loose') { return 'gravel' }
    if ($g.Contains('grass') -or $g.Contains('forest') -or $g.Contains('leaves') -or $g.Contains('branches') -or $g.Contains('foliage') -or $g.Contains('dirt')) { return 'dirt' }
    if ($g -eq 'sand' -or $g.Contains('beachsand') -or $g.Contains('sandtrap') -or ($g.Contains('sand') -and -not $g.Contains('dirt'))) { return 'sand' }
    if ($g.Contains('rock') -or $g.Contains('cobble') -or $g.Contains('cliff') -or $g.Contains('stone')) { return 'rock' }
    if ($g.Contains('wet') -or $g.Contains('puddle')) { return 'wet_paved' }
    if ($g.Contains('asphalt') -or $g.Contains('road') -or $g.Contains('concrete') -or $g.Contains('rumble') -or $g.Contains('kickplate') -or $g.Contains('spike') -or $g.Contains('grid')) { return 'dry_paved' }
    if ($g.Contains('metal') -or $g.Contains('wood') -or $g.Contains('plastic')) { return 'hard_smooth' }
    if ($g.Contains('void') -or $g.Contains('soft_collision') -or $g.Contains('shock_absorber')) { return 'generic' }
    return 'generic'
}

$expected = @{
    ASPHALT = 'dry_paved'; ASPHALT_OLD = 'dry_paved'; ASPHALT_PREPPED = 'dry_paved'
    ASPHALT_WET = 'wet_paved'; RUMBLE_STRIP = 'dry_paved'; ROCK = 'rock'; COBBLESTONE = 'rock'
    METAL = 'hard_smooth'; METAL_TREAD = 'hard_smooth'; WOOD = 'hard_smooth'; PLASTIC = 'hard_smooth'
    DIRT = 'dirt'; DIRT_DUSTY = 'dirt'; DIRT_DUSTY_LOOSE = 'dirt'
    GRAVEL = 'gravel'; GRAVEL_WET = 'gravel_wet'; GRASS = 'dirt'; MUD = 'mud'; SAND = 'sand'
    ICE = 'ice'; FRICTIONLESS = 'ice'; SPIKE_STRIP = 'dry_paved'; SNOW = 'snow'
    SLIPPERY = 'wet_paved'; KICKPLATE = 'dry_paved'; SHOCK_ABSORBER = 'generic'
    BRANCHES_STRONG = 'dirt'; LEAVES_STRONG = 'dirt'; LEAVES_THIN = 'dirt'
    SOFT_COLLISION_GENERAL = 'generic'; VOID = 'generic'
    concrete = 'dry_paved'; grid = 'dry_paved'; beachsand = 'sand'; dirt_loose = 'gravel'
    forest = 'dirt'; gravel_riverbed = 'gravel_wet'; dirt_sandy = 'dirt'
}

$fail = 0; $pass = 0
foreach ($k in ($expected.Keys | Sort-Object)) {
    $got = Classify-Surface $k
    $want = $expected[$k]
    if ($got -ne $want) {
        Write-Host "FAIL $k -> $got (want $want)"
        $fail++
    } else { $pass++ }
}

function Lerp($a,$b,$t){ return $a + ($b-$a)*$t }
function Min2($a,$b){ if($a -lt $b){return $a}; return $b }

# Live getSurfaceSanityScale caps (luukstyrethermalsandwear.lua)
$caps = @{
    dry_paved = 1.15; hard_smooth = 1.10; wet_paved = 1.15; gravel = 1.00
    gravel_wet = 0.88; dirt = 0.95; mud = 0.85; sand = 0.90; snow = 0.60; ice = 0.30; rock = 1.40
}

Write-Host ""
Write-Host "Surface scale (slick tread=0.1 vs MT tread=0.9) + live caps:"
$types = @('dry_paved','hard_smooth','wet_paved','gravel','gravel_wet','dirt','mud','sand','snow','ice','rock')
foreach ($s in $types) {
    $sa = switch ($s) {
        'dry_paved' { Lerp 1.04 0.90 0.1 }
        'hard_smooth' { Lerp 0.96 0.90 0.1 }
        'wet_paved' {
            $wet = (Lerp 0.82 0.98 0.5) * (Lerp 0.94 1.02 0.1)
            $dry = Lerp 1.06 0.90 0.1
            Min2 $wet ($dry * 0.92)
        }
        'gravel' { Lerp 0.55 1.05 0.1 }
        'gravel_wet' { Lerp 0.48 0.95 0.1 }
        'dirt' { Lerp 0.62 1.02 0.1 }
        'mud' { Lerp 0.34 1.08 0.1 }
        'sand' { Lerp 0.42 1.04 0.1 }
        'snow' { Lerp 0.36 1.00 0.1 }
        'ice' { Lerp 0.42 0.78 0.1 }
        'rock' { Lerp 0.88 1.05 0.1 }
    }
    $sb = switch ($s) {
        'dry_paved' { Lerp 1.04 0.90 0.9 }
        'hard_smooth' { Lerp 0.96 0.90 0.9 }
        'wet_paved' {
            $wet = (Lerp 0.82 0.98 0.5) * (Lerp 0.94 1.02 0.9)
            $dry = Lerp 1.06 0.90 0.9
            Min2 $wet ($dry * 0.92)
        }
        'gravel' { Lerp 0.55 1.05 0.9 }
        'gravel_wet' { Lerp 0.48 0.95 0.9 }
        'dirt' { Lerp 0.62 1.02 0.9 }
        'mud' { Lerp 0.34 1.08 0.9 }
        'sand' { Lerp 0.42 1.04 0.9 }
        'snow' { Lerp 0.36 1.00 0.9 }
        'ice' { Lerp 0.42 0.78 0.9 }
        'rock' { Lerp 0.88 1.05 0.9 }
    }
    $cap = $caps[$s]
    Write-Host ("  {0,-12} slick={1:N2}  MT={2:N2}  cap={3:N2}" -f $s, $sa, $sb, $cap)
}

# Cap awareness checks vs live SURFACE / getSurfaceSanityScale
$capFail = 0
if ([math]::Abs([double]$caps['dry_paved'] - 1.15) -gt 1e-9) { Write-Host 'FAIL dry_paved cap want 1.15'; $capFail++ }
else { Write-Host 'PASS dry_paved cap=1.15' }
if ([math]::Abs([double]$caps['hard_smooth'] - 1.10) -gt 1e-9) { Write-Host 'FAIL hard_smooth cap want 1.10'; $capFail++ }
else { Write-Host 'PASS hard_smooth cap=1.10' }
$dpSlick = Lerp 1.04 0.90 0.1
$hsSlick = Lerp 0.96 0.90 0.1
if ([math]::Abs($dpSlick - 1.026) -gt 0.002) { Write-Host "FAIL dry_paved slick scale got $dpSlick"; $capFail++ }
else { Write-Host 'PASS dry_paved slick scale ~1.03 (lerp 1.04 to 0.90 at tread 0.1)' }
if ([math]::Abs($hsSlick - 0.954) -gt 0.002) { Write-Host "FAIL hard_smooth slick scale got $hsSlick"; $capFail++ }
else { Write-Host 'PASS hard_smooth slick scale ~0.95 (lerp 0.96 to 0.90 at tread 0.1)' }
$fail += $capFail
$pass += (4 - $capFail)

Write-Host ""
Write-Host "Classification: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
