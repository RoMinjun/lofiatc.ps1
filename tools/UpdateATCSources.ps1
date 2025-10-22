# UpdateATCSources.ps1
param(
  [switch]$SortOnly,
  [switch]$InPlace,
  [string]$InputCsvPath,      # optional override
  [string]$OutputCsvPath      # optional override
)

# --- Helpers ---------------------------------------------------------------

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
  $Rows | Select-Object $cols | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
  Write-Host "`nWrote: $Path"
}

# --- Paths ----------------------------------------------------------------

$scriptDir = Get-ScriptRoot
$inputCsv  = if ($InputCsvPath) { Resolve-Path $InputCsvPath -ErrorAction Stop }
            else { Resolve-Path (Join-Path $scriptDir '..\atc_sources.csv') -ErrorAction Stop }
$csvDir    = Split-Path -Parent $inputCsv

# Default output for fetch-mode (legacy behavior)
$defaultFetchOut = Join-Path $csvDir 'liveatc_sources.csv'

# --- SortOnly short-circuit -----------------------------------------------

if ($SortOnly) {
  $rows = Import-Csv $inputCsv
  $sorted = Sort-AtcRows -Rows $rows
  $outPath = if ($InPlace) { $inputCsv } elseif ($OutputCsvPath) { $OutputCsvPath } else { $defaultFetchOut }
  Write-AtcCsv -Rows $sorted -Path $outPath
  return
}

# --- Fetch mode (original behavior), then sort ----------------------------

# Function to fetch ATC sources from liveatc.net
Function Get-LiveATCSources {
  param (
    [string]$Url = "https://www.liveatc.net/search/?icao=EHAM"
  )
  try {
    # Extract ICAO from the URL
    $icaoFromUrl = $Url -replace ".*icao=([^&]+).*", '$1'

    # Fetch HTML
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $htmlContent = $response.Content

    # Parse for .pls links
    $atcSources = @()
    $currentFeedName = ""
    $htmlContent -split '<tr>' | ForEach-Object {
      $row = $_.Trim()
      if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feedName>[^<]+)</strong>') {
        $currentFeedName = $matches['feedName'].Trim()
      }
      elseif ($row -match '<a href="(?<url>[^"]+\.pls)"') {
        $atcSources += [PSCustomObject]@{
          ICAO    = $icaoFromUrl
          Channel = $currentFeedName
          URL     = "https://www.liveatc.net" + $matches['url'].Trim()
        }
      }
    }
    return $atcSources
  }
  catch {
    Write-Error "Error fetching $($Url): $_"
    return @()
  }
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

# Fetch once per distinct ICAO
$icaoCache = @{}
$origRows |
  Select-Object -Expand ICAO -Unique |
  ForEach-Object {
    Write-Host "Fetching channels for $_…"
    $icaoCache[$_] = Get-LiveATCSources -Url "https://www.liveatc.net/search/?icao=$_"
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

