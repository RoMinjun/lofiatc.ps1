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
  @{ Expression = { ($_.Continent        ?? '').Trim() } ; Ascending = $true }, `
  @{ Expression = { ($_.Country          ?? '').Trim() } ; Ascending = $true }, `
  @{ Expression = { [string]::IsNullOrWhiteSpace($_.'State/Province') } }, `
  @{ Expression = { ($_. 'State/Province'?? '').Trim() } ; Ascending = $true }, `
  @{ Expression = { ($_.City             ?? '').Trim() } ; Ascending = $true }, `
  @{ Expression = { ($_.ICAO             ?? '').Trim().ToUpper() } ; Ascending = $true }, `
  @{ Expression = { ($_. 'Channel Description' ?? '').Trim() } ; Ascending = $true }, `
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
    Write-Host "OK: atc_sources.csv is already sorted."
    exit 0
  } else {
    Write-Host "NEEDS SORT: atc_sources.csv would be changed by canonical sort."
    exit 1
  }
}

# Decide output
$outPath = if ($InPlace) {
  $InputCsvPath
} elseif ($OutputCsvPath) {
  $OutputCsvPath
} else {
  Join-Path (Split-Path -Parent $InputCsvPath) 'atc_sources.sorted.csv'
}

# Write sorted CSV
$sorted | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote sorted CSV: $outPath"

