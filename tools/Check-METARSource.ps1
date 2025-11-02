param(
    [string]$MetarsGzUrl = "https://aviationweather.gov/data/cache/metars.cache.csv.gz",
    [string]$AtcSourcesCsv = "../atc_sources.csv",
    [string]$CachedGz = "metars.cache.csv.gz",
    [string]$ExtractedCsv = "metars.cache.csv",
    [string]$OutReportCsv = "missing_from_metars.csv",
    [string]$AtcIcaoColumn = "",
    [switch]$ForceRefresh
)

$ScriptRoot = if ($PSScriptRoot) { 
    $PSScriptRoot 
} 
else { 
    Split-Path -Parent $MyInvocation.MyCommand.Path 
}

function Resolve-Here([string]$p) { 
    if ([IO.Path]::IsPathRooted($p)) { 
        $p 
    } 
    else { 
        Join-Path $ScriptRoot $p 
    }
}

$AtcSourcesCsvPath = Resolve-Here $AtcSourcesCsv
$CachedGzPath = Resolve-Here $CachedGz
$ExtractedCsvPath = Resolve-Here $ExtractedCsv
$OutReportPath = Resolve-Here $OutReportCsv

Write-Host "Script root: $ScriptRoot"
Write-Host "ATC Sources CSV path: $AtcSourcesCsvPath"
Write-Host "METAR gzip path: $CachedGzPath"
Write-Host "METAR CSV (extracted): $ExtractedCsvPath"
Write-Host "Output report (missing): $OutReportPath"

if (-not (Test-Path -LiteralPath $AtcSourcesCsvPath)) {
    throw "ATC Sources CSV not found: $AtcSourcesCsvPath"
}

try { 
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
}
catch {
    Write-Host "Failed to set TLS 1.2 security protocol. $_"
}

if ($ForceRefresh -or -not (Test-Path -LiteralPath $CachedGzPath)) {
    Write-Host "Downloading METAR gzip from $MetarsGzUrl ..."
    try {
        Invoke-WebRequest -Uri $MetarsGzUrl -OutFile $CachedGzPath -UseBasicParsing -ErrorAction Stop
    }
    catch {
        throw "Download failed from $MetarsGzUrl. $_"
    }
}
else {
    Write-Host "Reusing existing gzip: $CachedGzPath (use -ForceRefresh to re-download)"
}

if (-not (Test-Path -LiteralPath $CachedGzPath)) {
    throw "Expected download file not found at: $CachedGzPath"
}

Write-Host "Decompressing gzip..."
$in = $null; $gz = $null; $out = $null
try {
    $in = [IO.File]::OpenRead($CachedGzPath)
    $gz = New-Object IO.Compression.GzipStream($in, [IO.Compression.CompressionMode]::Decompress)
    $out = [IO.File]::Create($ExtractedCsvPath)
    $gz.CopyTo($out)
    Write-Host "Decompressed to $ExtractedCsvPath"
}
catch {
    throw "Failed to decompress '$CachedGzPath' -> '$ExtractedCsvPath'. $_"
}
finally {
    if ($out) { $out.Dispose() }
    if ($gz) { $gz.Dispose() }
    if ($in) { $in.Dispose() }
}

if (-not (Test-Path -LiteralPath $ExtractedCsvPath)) {
    throw "Extracted CSV not found at $ExtractedCsvPath"
}

$metarLines = Get-Content -LiteralPath $ExtractedCsvPath -ErrorAction Stop
$headerMatch = $metarLines | Select-String -Pattern '^raw_text,station_id,' | Select-Object -First 1
$headerLineNum = $headerMatch.LineNumber
if (-not $headerLineNum) { 
    throw "Couldn't locate METAR header (expected to start with 'raw_text,station_id,')." 
}

$metarIds = $metarLines[$headerLineNum..($metarLines.Count - 1)] |
Where-Object { $_ -and $_.Trim() -ne "" } |
ForEach-Object {
    if ($_ -match ',([A-Z0-9]{4}),\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z,') {
        $matches[1].ToUpperInvariant()
    }
} |
Where-Object { $_ } |
Sort-Object -Unique

Write-Host ("METAR station_id count: {0}" -f $metarIds.Count)

$metarSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
foreach ($m in $metarIds) { 
    [void]$metarSet.Add($m)
}

$atcRaw = Get-Content -LiteralPath $AtcSourcesCsvPath -ErrorAction Stop
if (-not $atcRaw -or $atcRaw.Count -eq 0) { 
    throw "ATC Sources CSV is empty: $AtcSourcesCsvPath"
}

$atcObjs = ($atcRaw -join [Environment]::NewLine) | ConvertFrom-Csv
if (-not $atcObjs) { 
    throw "Failed to parse ATC Sources CSV at $AtcSourcesCsvPath." 
}

# Work out which column contains the ICAO code
$chosen = $null
if ($AtcIcaoColumn) {
    if (-not ($atcObjs | Get-Member -Name $AtcIcaoColumn -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
        throw "Column '$AtcIcaoColumn' not found in ATC Sources CSV."
    }
    $chosen = $AtcIcaoColumn
}
else {
    $candidates = @('icao', 'ICAO', 'icao_code', 'station_id', 'code', 'airport', 'Airport', 'AirportICAO', 'airport_icao')
    foreach ($c in $candidates) {
        if ($atcObjs | Get-Member -Name $c -MemberType NoteProperty -ErrorAction SilentlyContinue) { 
            $chosen = $c; 
            break 
        }
    }
    if (-not $chosen) {
        $props = $atcObjs[0].PSObject.Properties.Name
        $best = $null; $bestScore = -1
        foreach ($p in $props) {
            $valsTry = $atcObjs | Select-Object -ExpandProperty $p
            $score = ($valsTry | Where-Object { $_ -and $_ -match '^[A-Za-z0-9]{4}$' }).Count
            if ($score -gt $bestScore) { $bestScore = $score; $best = $p }
        }
        if (-not $best) { 
            throw "Couldn't auto-detect an ICAO column in ATC Sources CSV. Use -AtcIcaoColumn." 
        }
        $chosen = $best
    }
    Write-Host "Detected ICAO column: '$chosen'"
}

# Collect alternate messages instead of printing immediately
$alternateMessages = @()
$rowsToCheck = $atcObjs
if ($atcObjs | Get-Member -Name 'NearbyICAOs' -MemberType NoteProperty -ErrorAction SilentlyContinue) {
    $withNearby = $atcObjs |
    Where-Object { 
        $_.NearbyICAOs -and 
        -not [string]::IsNullOrWhiteSpace($_.NearbyICAOs) 
    } | Group-Object -Property $chosen

    foreach ($group in $withNearby) {
        $icao = ($group.Name -as [string]).Trim().ToUpper()
        $altVal = ($group.Group[0].NearbyICAOs -as [string]).Trim().ToUpper()
        if ($icao -and $altVal) {
            $alternateMessages += "$icao has configured alternate: $altVal"
        }
    }

    # Remove these rows from further checks
    $rowsToCheck = $atcObjs | Where-Object { 
        -not $_.NearbyICAOs `
        -or [string]::IsNullOrWhiteSpace($_.NearbyICAOs) 
    }
}

# Pull ICAOs only from the filtered rows
$atcIcaos = $rowsToCheck |
Select-Object -ExpandProperty $chosen |
Where-Object { $_ -and $_ -ne "" } |
ForEach-Object { $_.ToString().Trim().ToUpperInvariant() } |
Sort-Object -Unique

Write-Host ("ATC Sources ICAO count: {0}" -f $atcIcaos.Count)

function Get-VatsimMetar {
    param([Parameter(Mandatory)][string]$Icao)
    $url = "https://metar.vatsim.net/metar.php?id=$Icao"
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $text = $resp.Content.Trim()
        if ($text -and ($text -notmatch '^\s*No\s+METAR\b')) {
            return $text
        }
    }
    catch {
        Write-Warning "$Icao -> fallback request failed: $($_.Exception.Message)"
    }
    return $null
}

$recoveredCount = 0
$missing = foreach ($icao in $atcIcaos) {
    if (-not $metarSet.Contains($icao)) {
        $fallback = Get-VatsimMetar -Icao $icao
        if ($fallback) {
            $recoveredCount++
            Write-Host "$icao found via fallback."
            continue
        }
        [PSCustomObject]@{
            icao                  = $icao
            present_in_metars_csv = $false
        }
    }
}

# Now print alternate messages AFTER fallback results
foreach ($msg in $alternateMessages) {
    Write-Host $msg
}

if ($missing) {
    $missing | Sort-Object icao | Export-Csv -LiteralPath $OutReportPath -NoTypeInformation -Encoding UTF8
    Write-Warning ("{0} ICAO(s) from ATC Sources are NOT present in METARs (after fallback). Report: {1}" -f $missing.Count, (Resolve-Path $OutReportPath))
    if ($recoveredCount -gt 0) { 
        Write-Host ("Recovered via fallback: {0}" -f $recoveredCount) 
    }
    exit 1
}
else {
    Write-Host "All ICAOs resolved by primary METARs or fallback source."
    if ($recoveredCount -gt 0) { 
        Write-Host ("Recovered via fallback: {0}" -f $recoveredCount) 
    }
    exit 0
}
