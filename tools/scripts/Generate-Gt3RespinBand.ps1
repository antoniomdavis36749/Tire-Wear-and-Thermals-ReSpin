# Generate Hard / Medium / Soft GT3 Respin tire SKUs from the stop-gap templates.
# Softness values land on distinct SLICK_SPECTRUM anchors after remapSlickSoftness:
#   Soft   softnessCoef=1.00 -> remap 0.80 -> soft_slick
#   Medium softnessCoef=0.65 -> remap 0.65 -> medium_slick
#   Hard   softnessCoef=0.50 -> remap 0.50 -> hard_slick
# Friction stays at stock race norms (1.0).

param(
    [string]$ModRoot = 'C:\Users\anton\AppData\Local\BeamNG\BeamNG.drive\current\mods\unpacked\Tire-Wear-and-Thermals-ReSpin-main'
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$common = Join-Path $ModRoot 'vehicles\common'

$Band = @(
    @{
        Id       = 'soft_slick'
        Label    = 'Soft Slick (C4)'
        Softness = '1.00'
        Pressure = '26.0'
        Friction = '1.0'
        ValueAdd = 0
        Comment  = 'soft=1.00 -> remap 0.80 -> soft_slick (stock race soft end)'
    },
    @{
        Id       = 'medium_slick'
        Label    = 'Medium Slick (C3)'
        Softness = '0.65'
        Pressure = '27.0'
        Friction = '1.0'
        ValueAdd = -10
        Comment  = 'soft=0.65 -> medium_slick'
    },
    @{
        Id       = 'hard_slick'
        Label    = 'Hard Slick (C2)'
        Softness = '0.50'
        Pressure = '28.0'
        Friction = '1.0'
        ValueAdd = -20
        Comment  = 'soft=0.50 -> hard_slick'
    }
)

function Convert-RespinBandText {
    param(
        [string]$Text,
        [hashtable]$Spec,
        [ValidateSet('F', 'R')]$Axle
    )

    $idSuffix = $Spec.Id
    $label = $Spec.Label
    $soft = $Spec.Softness
    $psi = $Spec.Pressure
    $fric = $Spec.Friction
    $valueAdd = [int]$Spec.ValueAdd

    $text = [regex]::Replace($Text, '"(tire_[FR]_[^"]+_gt3_Respin)"\s*:\s*\{', {
            param($m)
            '"' + $m.Groups[1].Value + '_' + $idSuffix + '": {'
        })

    $text = [regex]::Replace($text, '"name"\s*:\s*"([^"]+?) Respin"', {
            param($m)
            '"name":"' + $m.Groups[1].Value + ' Respin ' + $label + '"'
        })

    $text = $text -replace '"authors"\s*:\s*"[^"]*"', '"authors":"yborella / ReSpin spectrum band"'

    $text = [regex]::Replace($text, '("value"\s*:\s*)(\d+)', {
            param($m)
            $m.Groups[1].Value + ([int]$m.Groups[2].Value + $valueAdd)
        })

    $pressVar = if ($Axle -eq 'F') { '\$tirepressure_F' } else { '\$tirepressure_R' }
    $text = [regex]::Replace(
        $text,
        "(\[`"$pressVar`",\s*`"range`",\s*`"psi`",\s*`"Wheels`",\s*)([0-9.]+)",
        ('${1}' + $psi)
    )

    $text = $text -replace '// ReSpin-compatible friction \(stock race norms; soft slick classify\)',
    ("// ReSpin band: " + $Spec.Comment)
    $text = $text -replace '"frictionCoef"\s*:\s*[0-9.]+', ('"frictionCoef":' + $fric)
    $text = $text -replace '"slidingFrictionCoef"\s*:\s*[0-9.]+', ('"slidingFrictionCoef":' + $fric)
    $text = $text -replace '"softnessCoef"\s*:\s*[0-9.]+', ('"softnessCoef":' + $soft)

    $header = "// ReSpin GT3 spectrum band - $label. Requires scintilla_gt3 for meshes. Softness set for remapSlickSoftness -> $($Spec.Id)."
    if ($text -match '(?s)^//[^\r\n]*\r?\n//[^\r\n]*\r?\n') {
        $text = $text -replace '(?s)^//[^\r\n]*\r?\n//[^\r\n]*\r?\n', ($header + "`r`n")
    }

    return $text
}

$generated = 0
foreach ($axle in @('F', 'R')) {
    $srcPath = Join-Path $common ("tires_{0}_gt3_Respin.jbeam" -f $axle)
    if (-not (Test-Path $srcPath)) {
        throw "Missing template: $srcPath"
    }
    $srcText = [System.IO.File]::ReadAllText($srcPath)

    foreach ($spec in $Band) {
        $outName = "tires_{0}_gt3_Respin_{1}.jbeam" -f $axle, $spec.Id
        $outPath = Join-Path $common $outName
        $converted = Convert-RespinBandText -Text $srcText -Spec $spec -Axle $axle
        [System.IO.File]::WriteAllText($outPath, $converted, $utf8NoBom)
        $generated++
        Write-Output "Wrote $outName"
    }
}

Write-Output ""
Write-Output "Generated $generated JBeam files (3 compounds x F/R)."
Write-Output "Part selector: ... Respin Soft/Medium/Hard Slick."
Write-Output "Original tires_*_gt3_Respin.jbeam left as soft-end stop-gap (soft=1)."
Write-Output "Classify: Soft->soft_slick, Medium->medium_slick, Hard->hard_slick."
