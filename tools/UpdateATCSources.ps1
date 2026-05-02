param(
  [switch]$SortOnly,
  [switch]$InPlace,
  [string]$InputCsvPath,
  [string]$OutputCsvPath,
  [string]$FailedLogPath = "failed_liveatc_fetches.log"
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

  $Rows | Sort-Object `
    @{ Expression = { ($_.Continent        ?? '').Trim() } }, `
    @{ Expression = { ($_.Country          ?? '').Trim() } }, `
    @{ Expression = { [string]::IsNullOrWhiteSpace($_.'State/Province') } }, `
    @{ Expression = { ($_.'State/Province' ?? '').Trim() } }, `
    @{ Expression = { ($_.City             ?? '').Trim() } }, `
    @{ Expression = { ($_.ICAO             ?? '').Trim().ToUpper() } }, `
    @{ Expression = { ($_.'Channel Description' ?? '').Trim() } }
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

function Write-FailedFetchLog {
  param(
    [Parameter(Mandatory)][string]$Icao,
    [Parameter()][object]$Status,
    [Parameter(Mandatory)][string]$Reason,
    [Parameter(Mandatory)][string]$Url
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $statusText = if ($null -ne $Status -and "$Status" -ne "") { "$Status" } else { "UNKNOWN" }
  $line = "[$timestamp] ICAO=$Icao | HTTP=$statusText | URL=$Url | Reason=$Reason"

  try {
    Add-Content -Path $FailedLogPath -Value $line
  }
  catch {
    Write-Warning "Could not write failed fetch log to '$FailedLogPath'. Exception: $($_.Exception.Message)"
  }
}

function Test-FlareSolverrConnection {
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

function Get-HtmlViaFlareSolverr {
  param(
    [Parameter(Mandatory)][string]$TargetUrl,
    [Parameter(Mandatory)][string]$Icao
  )

  $flareSolverrUrl = "http://localhost:8191/v1"

  $payload = @{
    cmd        = "request.get"
    url        = $TargetUrl
    maxTimeout = 60000
  } | ConvertTo-Json -Depth 2

  try {
    Write-Host "Asking FlareSolverr to fetch [$Icao]: $TargetUrl"

    $response = Invoke-RestMethod `
      -Uri $flareSolverrUrl `
      -Method Post `
      -Body $payload `
      -ContentType "application/json" `
      -TimeoutSec 120 `
      -ErrorAction Stop

    $statusCode = $response.solution.status

    if ($statusCode -ne 200) {
      $reason = "LiveATC search page returned HTTP $statusCode instead of 200 OK. Existing rows for this ICAO will be preserved."
      Write-Warning "[$Icao] $reason"
      Write-FailedFetchLog -Icao $Icao -Status $statusCode -Reason $reason -Url $TargetUrl

      return [PSCustomObject]@{
        Success = $false
        Html    = $null
      }
    }

    if ($response.solution.response) {
      return [PSCustomObject]@{
        Success = $true
        Html    = $response.solution.response
      }
    }

    $reason = "LiveATC search page returned 200 OK, but FlareSolverr returned no HTML. Existing rows for this ICAO will be preserved."
    Write-Warning "[$Icao] $reason"
    Write-FailedFetchLog -Icao $Icao -Status 200 -Reason $reason -Url $TargetUrl

    return [PSCustomObject]@{
      Success = $false
      Html    = $null
    }
  }
  catch {
    $reason = "FlareSolverr request failed. Existing rows for this ICAO will be preserved. Exception: $($_.Exception.Message)"
    Write-Warning "[$Icao] $reason"
    Write-FailedFetchLog -Icao $Icao -Status $null -Reason $reason -Url $TargetUrl

    return [PSCustomObject]@{
      Success = $false
      Html    = $null
    }
  }
}

function Parse-LiveATCSources {
  param (
    [Parameter(Mandatory)][string]$HtmlContent,
    [Parameter(Mandatory)][string]$Icao
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

$inputCsv = if ($InputCsvPath) {
  Resolve-Path $InputCsvPath -ErrorAction Stop
}
else {
  Resolve-Path (Join-Path $scriptDir '..\atc_sources.csv') -ErrorAction Stop
}

$csvDir = Split-Path -Parent $inputCsv

$defaultFetchOut = Join-Path $csvDir 'liveatc_sources.csv'

if ($SortOnly) {
  $rows = Import-Csv $inputCsv
  $sorted = Sort-AtcRows -Rows $rows
  $outPath = if ($InPlace) { $inputCsv } elseif ($OutputCsvPath) { $OutputCsvPath } else { $defaultFetchOut }
  Write-AtcCsv -Rows $sorted -Path $outPath
  return
}

if (-not (Test-FlareSolverrConnection)) {
  Write-Warning "FlareSolverr is not running or unreachable at http://localhost:8191/."
  Write-Warning "Please ensure the FlareSolverr background process is active."
  exit 1
}

$origRows = Import-Csv $inputCsv

$webcamLookup = @{}

foreach ($row in $origRows) {
  $key = "{0}||{1}" -f $row.ICAO, $row.'Channel Description'

  if (-not $webcamLookup.ContainsKey($key) -and $row.'Webcam URL') {
    $webcamLookup[$key] = $row.'Webcam URL'
  }
}

$icaoCache = @{}

$origRows |
  Select-Object -ExpandProperty ICAO -Unique |
  Where-Object { [string]::IsNullOrWhiteSpace($_) -eq $false } |
  ForEach-Object {
    $icao = $_.Trim().ToUpper()
    Write-Host "Processing channels for $icao..."

    $url = "https://www.liveatc.net/search/?icao=$icao"
    $fetchResult = Get-HtmlViaFlareSolverr -TargetUrl $url -Icao $icao

    if ($fetchResult.Success -eq $true) {
      $parsedSources = @(Parse-LiveATCSources -HtmlContent $fetchResult.Html -Icao $icao)

      if ($parsedSources.Count -eq 0) {
        Write-Host "[$icao] 200 OK, but no channels found. Existing rows for this ICAO will be removed from output." -ForegroundColor Yellow
      }

      $icaoCache[$icao] = $parsedSources
    }
    else {
      Write-Warning "[$icao] Fetch failed. Existing rows for this ICAO will be preserved."
      $icaoCache[$icao] = $null
    }
  }

$allResults = foreach ($icao in $icaoCache.Keys) {
  $meta = $origRows | Where-Object { ($_.ICAO ?? '').Trim().ToUpper() -eq $icao } | Select-Object -First 1

  if ($null -eq $icaoCache[$icao]) {
    $origRows | Where-Object { ($_.ICAO ?? '').Trim().ToUpper() -eq $icao }
    continue
  }

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

$sorted = Sort-AtcRows -Rows $allResults

$outPath = if ($OutputCsvPath) { $OutputCsvPath } else { $defaultFetchOut }

Write-AtcCsv -Rows $sorted -Path $outPath
