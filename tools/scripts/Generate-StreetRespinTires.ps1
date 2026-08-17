#Requires -Version 5.1
# Gap-fill by native SKU that already exists on that wheel (stagger-safe).
# Sport Plus + Track Day: native sport_plus part/mesh when present, else native sport.
# Hard C2 / Medium C3: native race. Native Sport / Race / Standard are not replaced.
param(
    [string]$BeamNGRoot = 'C:\Program Files (x86)\Steam\steamapps\common\BeamNG.drive',
    [string]$ModRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $ModRoot) {
    $ModRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$zipPath = Join-Path $BeamNGRoot 'content\vehicles\common.zip'
if (-not (Test-Path $zipPath)) {
    throw "common.zip not found: $zipPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$outDir = Join-Path $ModRoot 'vehicles\common\tires_respin_street'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Get-ChildItem -LiteralPath $outDir -Filter '*_Respin_street.jbeam' -ErrorAction SilentlyContinue | Remove-Item -Force

$StreetCompounds = @(
    @{ Id = 'sport_plus'; Label = 'Sport Plus'; Tread = '0.30' },
    @{ Id = 'track_day';  Label = 'Track Day';  Tread = '0.18' }
)
$SlickCompounds = @(
    @{ Id = 'hard_slick';   Label = 'Hard Slick (C2)';   Tread = '0.00'; Softness = '0.50' },
    @{ Id = 'medium_slick'; Label = 'Medium Slick (C3)'; Tread = '0.00'; Softness = '0.65' }
)

function Get-MatchingBraceEnd {
    param([string]$Text, [int]$OpenIndex)
    $depth = 0
    $inStr = $false
    $esc = $false
    for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($inStr) {
            if ($esc) { $esc = $false; continue }
            if ($ch -eq '\') { $esc = $true; continue }
            if ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        if ($ch -eq '"') { $inStr = $true; continue }
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

function Get-QuotedStringEnd {
    param([string]$Text, [int]$OpenQuote)
    $esc = $false
    for ($i = $OpenQuote + 1; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($esc) { $esc = $false; continue }
        if ($ch -eq '\') { $esc = $true; continue }
        if ($ch -eq '"') { return $i }
    }
    return -1
}

function Get-JBeamPartBlocks([string]$Text) {
    $blocks = New-Object System.Collections.Generic.List[object]
    $matches = [regex]::Matches($Text, '"(tire_[FR]_[^"]+)"\s*:\s*\{')
    foreach ($m in $matches) {
        $id = $m.Groups[1].Value
        $braceStart = $Text.IndexOf('{', $m.Index + $m.Length - 1)
        $end = Get-MatchingBraceEnd -Text $Text -OpenIndex $braceStart
        if ($end -lt 0) { continue }
        $block = $Text.Substring($m.Index, $end - $m.Index + 1)
        $blocks.Add([pscustomobject]@{ Id = $id; Text = $block })
    }
    return $blocks
}

function Set-JBeamDisplayName {
    param([string]$Text, [string]$NameStr)
    $m = [regex]::Match($Text, '"name"\s*:')
    if (-not $m.Success) { return $Text }
    $i = $m.Index + $m.Length
    while ($i -lt $Text.Length -and [char]::IsWhiteSpace($Text[$i])) { $i++ }
    if ($i -ge $Text.Length) { return $Text }
    $end = -1
    if ($Text[$i] -eq '{') {
        $end = Get-MatchingBraceEnd -Text $Text -OpenIndex $i
    } elseif ($Text[$i] -eq '"') {
        $end = Get-QuotedStringEnd -Text $Text -OpenQuote $i
    }
    if ($end -lt 0) { return $Text }
    return $Text.Substring(0, $m.Index) + '"name":"' + $NameStr + '"' + $Text.Substring($end + 1)
}

function Convert-PartToRespin {
    param(
        [string]$Block,
        [string]$OldId,
        [hashtable]$Spec
    )
    $axle = if ($OldId -match '^tire_F_') { 'Front' } else { 'Rear' }
    $size = 'Tire'
    if ($OldId -match 'tire_[FR]_(\d+)_(\d+)_(\d+)') {
        $size = '{0}/{1}R{2}' -f $Matches[1], $Matches[2], $Matches[3]
    } elseif ($Block -match '"size"\s*:\s*"([^"]+)"') {
        $size = $Matches[1]
    }
    $newId = ($OldId -replace '_sport_plus$', '' -replace '_sport$', '' -replace '_race$', '') + '_Respin_' + $Spec.Id
    $text = $Block.Replace(('"' + $OldId + '"'), ('"' + $newId + '"'))
    $text = $text -replace '"authors"\s*:\s*"[^"]*"', '"authors":"BeamNG / ReSpin"'

    $nameStr = '{0} {1} {2} Tires Respin' -f $size, $Spec.Label, $axle
    $text = Set-JBeamDisplayName -Text $text -NameStr $nameStr

    if ($text -match '"treadCoef"\s*:') {
        $text = $text -replace '"treadCoef"\s*:\s*[0-9.]+', ('"treadCoef":' + $Spec.Tread)
    } else {
        $text = $text -replace '("softnessCoef"\s*:\s*[0-9.]+)', ('"treadCoef":' + $Spec.Tread + ",`r`n            " + '$1')
        if ($text -notmatch '"treadCoef"') {
            $text = $text -replace '("frictionCoef"\s*:\s*[0-9.]+)', ('"treadCoef":' + $Spec.Tread + ",`r`n            " + '$1')
        }
    }
    if ($Spec.ContainsKey('Softness') -and $Spec.Softness) {
        if ($text -match '"softnessCoef"\s*:') {
            $text = $text -replace '"softnessCoef"\s*:\s*[0-9.]+', ('"softnessCoef":' + $Spec.Softness)
        } else {
            $text = $text -replace '("treadCoef"\s*:\s*[0-9.]+)', ('$1,' + "`r`n            " + '"softnessCoef":' + $Spec.Softness)
        }
    }
    return $text
}

function Get-PartSizeKey([string]$Id) {
    return $Id -replace '_sport_plus$', '' -replace '_sport$', '' -replace '_race$', ''
}

function Test-SkipStreetFile([string]$FileName, [string]$Dir) {
    $blob = "$FileName $Dir"
    if ($blob -match 'offroad' -or $blob -match '3w') { return $true }
    if ($blob -match '10x6') { return $true }
    if ($FileName -match '(\d{2})x' -or $Dir -match '/(\d{2})x') {
        $rim = [int]$Matches[1]
        if ($rim -ge 22) { return $true }
    }
    return $false
}

function Get-StreetOutName([string]$FileName, [string]$Kind) {
    $axleTag = if ($FileName -match '_F_') { 'F' } elseif ($FileName -match '_R_') { 'R' } else { 'X' }
    $sizeTag = $FileName -replace '^tires_', '' -replace ('_' + $Kind + '\s*\.jbeam$'), ''
    $outName = "tires_{0}_Respin_street.jbeam" -f $sizeTag
    if ($axleTag -ne 'X' -and $outName -notmatch "tires_$axleTag") {
        $outName = "tires_{0}_{1}_Respin_street.jbeam" -f $axleTag, ($sizeTag -replace '^[FR]_', '')
    }
    return $outName
}

function Test-StreetJBeamFile([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path)
    $issues = New-Object System.Collections.Generic.List[string]
    $blocks = Get-JBeamPartBlocks $raw
    if ($blocks.Count -eq 0) {
        $issues.Add('no parts')
        return $issues
    }
    foreach ($b in $blocks) {
        if ($b.Text -notmatch '"slotType"') {
            $issues.Add("$($b.Id) missing slotType")
        }
        if ($b.Text -match '"name"\s*:\s*"[^"]+"\s*,\s*\}') {
            $issues.Add("$($b.Id) leftover braces after name")
        }
        if ($b.Id -notmatch '_Respin_(sport_plus|track_day|hard_slick|medium_slick)$') {
            $issues.Add("$($b.Id) unexpected part id")
        }
        if ($b.Id -match 'hard_slick' -and $b.Text -notmatch '"softnessCoef"\s*:\s*0\.50') {
            $issues.Add("$($b.Id) expected softnessCoef 0.50")
        }
        if ($b.Id -match 'medium_slick' -and $b.Text -notmatch '"softnessCoef"\s*:\s*0\.65') {
            $issues.Add("$($b.Id) expected softnessCoef 0.65")
        }
    }
    $rootKeys = [regex]::Matches($raw, '(?m)^"([^"]+)"\s*:')
    foreach ($k in $rootKeys) {
        $name = $k.Groups[1].Value
        if ($name -notmatch '^tire_') {
            $issues.Add("non-part root key: $name")
        }
    }
    return $issues
}

$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$files = 0
$partsOut = 0
try {
    $entries = @($zip.Entries)
    $byDir = @{}
    foreach ($e in $entries) {
        if ($e.FullName -notmatch 'vehicles/common/tires/.+\.jbeam$') { continue }
        if ($e.Name -match '3w') { continue }
        $dir = ($e.FullName -replace '\\', '/')
        $dir = $dir.Substring(0, $dir.LastIndexOf('/'))
        if (-not $byDir.ContainsKey($dir)) { $byDir[$dir] = [System.Collections.Generic.List[object]]::new() }
        $byDir[$dir].Add($e)
    }

    $bags = @{}
    foreach ($dir in ($byDir.Keys | Sort-Object)) {
        $group = $byDir[$dir]
        $sport = @($group | Where-Object { $_.Name -match '_sport\.jbeam$' })
        $race = @($group | Where-Object { $_.Name -match '_race' -and $_.Name -notmatch 'offroad_race' })

        foreach ($se in $sport) {
            if (Test-SkipStreetFile -FileName $se.Name -Dir $dir) { continue }
            $reader = [IO.StreamReader]::new($se.Open())
            $src = try { $reader.ReadToEnd() } finally { $reader.Close() }
            $blocks = Get-JBeamPartBlocks $src
            if ($blocks.Count -eq 0) { continue }
            $outName = Get-StreetOutName -FileName $se.Name -Kind 'sport'
            if (-not $bags.ContainsKey($outName)) {
                $bags[$outName] = [System.Collections.Generic.List[string]]::new()
            }
            $plusByKey = @{}
            $sportBlocks = New-Object System.Collections.Generic.List[object]
            foreach ($b in $blocks) {
                if ($b.Id -match 'offroad') { continue }
                if ($b.Id -match 'sport_plus') {
                    $plusByKey[(Get-PartSizeKey $b.Id)] = $b
                } elseif ($b.Id -match '_sport$') {
                    $sportBlocks.Add($b)
                }
            }
            $usedPlus = @{}
            foreach ($b in $sportBlocks) {
                $key = Get-PartSizeKey $b.Id
                $srcPart = $b
                if ($plusByKey.ContainsKey($key)) {
                    $srcPart = $plusByKey[$key]
                    $usedPlus[$key] = $true
                }
                foreach ($spec in $StreetCompounds) {
                    $bags[$outName].Add((Convert-PartToRespin -Block $srcPart.Text -OldId $srcPart.Id -Spec $spec))
                    $partsOut++
                }
            }
            foreach ($key in $plusByKey.Keys) {
                if ($usedPlus.ContainsKey($key)) { continue }
                $srcPart = $plusByKey[$key]
                foreach ($spec in $StreetCompounds) {
                    $bags[$outName].Add((Convert-PartToRespin -Block $srcPart.Text -OldId $srcPart.Id -Spec $spec))
                    $partsOut++
                }
            }
        }

        foreach ($re in $race) {
            if (Test-SkipStreetFile -FileName $re.Name -Dir $dir) { continue }
            $reader = [IO.StreamReader]::new($re.Open())
            $src = try { $reader.ReadToEnd() } finally { $reader.Close() }
            $blocks = Get-JBeamPartBlocks $src
            if ($blocks.Count -eq 0) { continue }
            $outName = Get-StreetOutName -FileName $re.Name -Kind 'race'
            if (-not $bags.ContainsKey($outName)) {
                $bags[$outName] = [System.Collections.Generic.List[string]]::new()
            }
            foreach ($b in $blocks) {
                if ($b.Id -match 'offroad') { continue }
                foreach ($spec in $SlickCompounds) {
                    $bags[$outName].Add((Convert-PartToRespin -Block $b.Text -OldId $b.Id -Spec $spec))
                    $partsOut++
                }
            }
        }
    }

    foreach ($outName in ($bags.Keys | Sort-Object)) {
        $emitted = $bags[$outName]
        if ($emitted.Count -eq 0) { continue }
        $outPath = Join-Path $outDir $outName
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('// ReSpin gap-fill: Sport Plus, Track Day, Hard C2, Medium C3.')
        [void]$sb.AppendLine('// Native Sport / Race / Standard are unchanged. Meshes stay in common.zip.')
        [void]$sb.AppendLine('{')
        [void]$sb.AppendLine(($emitted -join ",`r`n"))
        [void]$sb.AppendLine('}')
        [System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8NoBom)
        $files++
    }
} finally {
    $zip.Dispose()
}

$bad = 0
Get-ChildItem -LiteralPath $outDir -Filter '*_Respin_street.jbeam' | ForEach-Object {
    $issues = Test-StreetJBeamFile $_.FullName
    if ($issues.Count -gt 0) {
        $bad++
        Write-Output ("FAIL {0}: {1}" -f $_.Name, ($issues -join '; '))
    }
}
if ($bad -gt 0) {
    throw ("Street JBeam validation failed for {0} file(s)" -f $bad)
}

Write-Output ("Wrote {0} JBeam files, {1} parts → {2}" -f $files, $partsOut, $outDir)
