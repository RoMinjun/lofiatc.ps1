param(
  [switch]$SortOnly,
  [switch]$InPlace,
  [string]$InputCsvPath,
  [string]$OutputCsvPath
)

function Get-ScriptRoot {
  if ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
  else { Split-Path -Parent $MyInvocation.MyCommand.Path }
}

function Get-ColumnOrder {
  @(
    'Continent','Country','City','State/Province','Airport Name',
    'ICAO','IATA','Channel Description','Stream URL','Webcam URL','NearbyICAOs'
  )
}

function Sort-AtcRows {
  param([Parameter(Mandatory)][array]$Rows)

  # deterministic, case-insensitive; empty State/Province sorted LAST
  $Rows | Sort-Object `
    @{ Expression = { ($_.Continent        ?? '').Trim() } }, `
    @{ Expression = { ($_.Country          ?? '').Trim() } }, `
    @{ Expression = { [string]::IsNullOrWhiteSpace($_.'State/Province') } }, `
    @{ Expression = { ($_. 'State/Province'?? '').Trim() } }, `
    @{ Expression = { ($_.City             ?? '').Trim() } }, `
    @{ Expression = { ($_.ICAO             ?? '').Trim().ToUpper() } }, `
    @{ Expression = { ($_. 'Channel Description' ?? '').Trim() } }
}

function Write-AtcCsv {
  param(
    [Parameter(Mandatory)][array]$Rows,
    [Parameter(Mandatory)][string]$Path
  )
  $cols = Get-ColumnOrder
  $Rows | Select-Object $cols -Unique | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
  Write-Host "`nWrote: $Path"
}

# Test proxy connection
Function Test-FlareSolverrConnection {
    $baseUrl = "http://localhost:8191/"
    try {
        Write-Host "Checking connection to FlareSolverr..." -NoNewline
        $response = Invoke-RestMethod -Uri $baseUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
        
        if ($response.msg -match "FlareSolverr") {
            Write-Host " OK! (Version: $($response.version))" -ForegroundColor Green
            return $true
        }
        
        Write-Host " Failed! Unexpected response." -ForegroundColor Red
        return $false
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        return $false
    }
}

Function Get-HtmlViaFlareSolverr {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl
    )
    
    $flareSolverrUrl = "http://localhost:8191/v1"
    
    $payload = @{
        cmd = "request.get"
        url = $TargetUrl
        maxTimeout = 60000
    } | ConvertTo-Json -Depth 2

    try {
        Write-Host "Asking FlareSolverr to fetch: $TargetUrl"
        $response = Invoke-RestMethod -Uri $flareSolverrUrl `
                                      -Method Post `
                                      -Body $payload `
                                      -ContentType "application/json" `
                                      -TimeoutSec 120

        if ($response.solution.response) {
            return $response.solution.response
        } else {
            Write-Error "FlareSolverr returned a response, but no HTML was found."
            return $null
        }
    }
    catch {
        Write-Error "Failed to fetch via FlareSolverr. Exception: $_"
        return $null
    }
}

Function Parse-LiveATCSources {
  param (
    [Parameter(Mandatory = $true)][string]$HtmlContent,
    [Parameter(Mandatory = $true)][string]$Icao
  )
  try {
    $atcSources = @()
    $currentFeedName = ""
    
    $HtmlContent -split '<tr>' | ForEach-Object {
      $row = $_.Trim()
      if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feedName>[^<]+)</strong>') {
        $currentFeedName = $matches['feedName'].Trim()
      }
      elseif ($row -match '<a href="(?<url>[^"]+\.pls)"') {
        $atcSources += [PSCustomObject]@{
          ICAO    = $Icao
          Channel = $currentFeedName
          URL     = "https://www.liveatc.net" + $matches['url'].Trim()
        }
      }
    }
    return $atcSources
  }
  catch {
    Write-Error "[$Icao] Failed to parse ATC sources. Exception: $_"
    return @()
  }
}

$scriptDir = Get-ScriptRoot
$inputCsv  = if ($InputCsvPath) { Resolve-Path $InputCsvPath -ErrorAction Stop }
             else { Resolve-Path (Join-Path $scriptDir '..\atc_sources.csv') -ErrorAction Stop }
$csvDir    = Split-Path -Parent $inputCsv

# Default output for fetch-mode
$defaultFetchOut = Join-Path $csvDir 'liveatc_sources.csv'

if ($SortOnly) {
  $rows = Import-Csv $inputCsv
  $sorted = Sort-AtcRows -Rows $rows
  $outPath = if ($InPlace) { $inputCsv } elseif ($OutputCsvPath) { $OutputCsvPath } else { $defaultFetchOut }
  Write-AtcCsv -Rows $sorted -Path $outPath
  return
}

# Run the health check before proceeding with network operations
if (-not (Test-FlareSolverrConnection)) {
    Write-Warning "FlareSolverr is not running or unreachable at http://localhost:8191/."
    Write-Warning "Please ensure the FlareSolverr background process is active."
    exit 1
}

# Figure out input rows
$origRows = Import-Csv $inputCsv

# Build a lookup of Webcam URLs by ICAO+Channel
$webcamLookup = @{}
foreach ($row in $origRows) {
  $key = "{0}||{1}" -f $row.ICAO, $row.'Channel Description'
  if (-not $webcamLookup.ContainsKey($key) -and $row.'Webcam URL') {
    $webcamLookup[$key] = $row.'Webcam URL'
  }
}

# Fetch once per distinct ICAO using FlareSolverr
$icaoCache = @{}
$origRows |
  Select-Object -ExpandProperty ICAO -Unique |
  Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false } |
  ForEach-Object {
    $icao = $_
    Write-Host "Processing channels for $icao…"
    
    $url = "https://www.liveatc.net/search/?icao=$icao"
    $rawHtml = Get-HtmlViaFlareSolverr -TargetUrl $url
    
    if ($null -ne $rawHtml) {
        $icaoCache[$icao] = Parse-LiveATCSources -HtmlContent $rawHtml -Icao $icao
    } else {
        $icaoCache[$icao] = @()
    }
  }

# Build output: one row per fetched source
$allResults = foreach ($icao in $icaoCache.Keys) {
  $meta = $origRows | Where-Object ICAO -eq $icao | Select-Object -First 1

  foreach ($src in $icaoCache[$icao]) {
    $key = "{0}||{1}" -f $icao, $src.Channel
    $webcam = if ($webcamLookup.ContainsKey($key)) { $webcamLookup[$key] } else { "" }

    [PSCustomObject][ordered]@{
      Continent             = $meta.'Continent'
      Country               = $meta.'Country'
      City                  = $meta.'City'
      'State/Province'      = $meta.'State/Province'
      'Airport Name'        = $meta.'Airport Name'
      ICAO                  = $icao
      IATA                  = $meta.'IATA'
      'Channel Description' = $src.Channel
      'Stream URL'          = $src.URL
      'Webcam URL'          = $webcam
      'NearbyICAOs'         = $meta.NearbyICAOs
    }
  }
}

# Sort with the new deterministic key
$sorted = Sort-AtcRows -Rows $allResults

# Choose output path
$outPath = if ($OutputCsvPath) { $OutputCsvPath } else { $defaultFetchOut }

# Write CSV in canonical column order
Write-AtcCsv -Rows $sorted -Path $outPath
