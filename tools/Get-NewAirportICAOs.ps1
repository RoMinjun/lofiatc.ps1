<#
.SYNOPSIS
Prints a fetchtest command for autocomplete ICAOs missing from the base CSV.
.EXAMPLE
./tools/Get-NewAirportICAOs.ps1
.EXAMPLE
./tools/Get-NewAirportICAOs.ps1 -CsvPath ./atc_sources.csv
#>
[CmdletBinding()]
param(
    [string]$CsvPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'atc_sources.csv')
)

$rows = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
if ($rows.Count -eq 0 -or $rows[0].PSObject.Properties.Name -notcontains 'ICAO') {
    throw "CSV must contain airport rows and an ICAO column: $CsvPath"
}

$baseICAOs = @{}
foreach ($row in $rows) {
    $icao = ([string]$row.ICAO).Trim().ToUpperInvariant()
    if ($icao) { $baseICAOs[$icao] = $true }
}

# Collect every response before emitting results so a failed request cannot
# produce a seemingly complete list.
$remoteICAOs = foreach ($letterCode in 97..122) {
    $letter = [string][char]$letterCode
    $url = "https://www.lofiatc.com/autocomplete/$letter"
    Write-Verbose "Fetching $url"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 30 -ErrorAction Stop
    if ($null -eq $response -or $response.PSObject.Properties.Name -notcontains 'codes') {
        throw "Autocomplete response has no codes property: $url"
    }
    foreach ($code in $response.codes) {
        $icao = ([string]$code).Trim().ToUpperInvariant()
        if ($icao -match '^[A-Z]{4}$' -and $icao -like "$letter*") {
            $icao
        }
    }
}

$missingICAOs = @($remoteICAOs | Sort-Object -Unique | Where-Object { -not $baseICAOs.ContainsKey($_) })
if ($missingICAOs.Count -gt 0) {
    './fetchtest.ps1 -ICAO ' + ($missingICAOs -join ' ')
}
else {
    Write-Host 'No new ICAOs found.'
}
