[CmdletBinding()]
param(
  [string]$InputCsvPath = "$(Join-Path (Split-Path -Parent $PSCommandPath) '..\atc_sources.csv')",
  [switch]$InPlace,
  [string]$OutputCsvPath,
  [switch]$Check
)

# --- Load CSV (no transforms) ---
if (-not (Test-Path $InputCsvPath)) {
  Write-Error "File not found: $InputCsvPath"
  exit 2
}
$rows = Import-Csv -Path $InputCsvPath
if (-not $rows) {
  Write-Error "No rows found in '$InputCsvPath'."
  exit 2
}

$expectedCols = @(
  'Continent', 'Country', 'City', 'State/Province', 'Airport Name',
  'ICAO', 'IATA', 'Channel Description', 'Stream URL', 'Webcam URL', 'NearbyICAOs'
)
$actualCols = @($rows[0].psobject.Properties.Name)
if (($actualCols.Count -ne $expectedCols.Count) -or
    (($actualCols -join ',') -cne ($expectedCols -join ','))) {
  Write-Error "Unexpected CSV schema in '$InputCsvPath'. Expected: $($expectedCols -join ',')"
  exit 2
}

$duplicateRows = @($rows | Group-Object {
  $row = $_
  ($expectedCols | ForEach-Object { [string]$row.PSObject.Properties[$_].Value }) -join [char]31
} | Where-Object { $_.Count -gt 1 })
if ($duplicateRows.Count -gt 0) {
  Write-Error "Found $($duplicateRows.Count) duplicate row group(s) in '$InputCsvPath'."
  exit 2
}

# Grab the filename for dynamic console logging
$fileName = Split-Path $InputCsvPath -Leaf

# Preserve original header order
$cols = $rows[0].psobject.Properties.Name

# Add stable index for full stability on ties
$script:idx = 0
$rows | ForEach-Object {
  $_ | Add-Member -NotePropertyName _idx -NotePropertyValue $script:idx -Force
  $script:idx++
}

# Canonical sort
$sorted = $rows | Sort-Object `
  @{ Expression = { ([string]$_.Continent).Trim() } ; Ascending = $true }, `
  @{ Expression = { ([string]$_.Country).Trim() } ; Ascending = $true }, `
  @{ Expression = { [string]::IsNullOrWhiteSpace($_.'State/Province') } }, `
  @{ Expression = { ([string]$_.'State/Province').Trim() } ; Ascending = $true }, `
  @{ Expression = { ([string]$_.City).Trim() } ; Ascending = $true }, `
  @{ Expression = { ([string]$_.ICAO).Trim().ToUpperInvariant() } ; Ascending = $true }, `
  @{ Expression = { ([string]$_.'Channel Description').Trim() } ; Ascending = $true }, `
  @{ Expression = { $_._idx } }

# Strip helper index
$rows   = $rows   | Select-Object $cols
$sorted = $sorted | Select-Object $cols

# Serialize both for comparison (no file touch)
function Serialize([object[]]$r) {
  $tmp = New-TemporaryFile
  try {
    $r | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
    Get-Content -Raw -Path $tmp -Encoding UTF8
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
}

$origText   = Serialize $rows
$sortedText = Serialize $sorted

if ($Check) {
  if ($origText -ceq $sortedText) {
    Write-Host "OK: $fileName is already sorted."
    exit 0
  } else {
    Write-Host "NEEDS SORT: $fileName would be changed by canonical sort."
    exit 1
  }
}

# Decide output
$outPath = if ($InPlace) {
  $InputCsvPath
} elseif ($OutputCsvPath) {
  $OutputCsvPath
} else {
  Join-Path (Split-Path -Parent $InputCsvPath) "$($fileName -replace '\.csv$','.sorted.csv')"
}

# Write sorted CSV
$sorted | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote sorted CSV: $outPath"
