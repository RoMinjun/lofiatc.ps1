param(
  [string]
  $flaresolverrUrl = "http://localhost:8191/v1"
)

$missingCsv        = ".\missing_from_metars.csv"
$atcSourcesCsv     = "..\atc_sources.csv"
$liveAtcSourcesCsv = "..\liveatc_sources.csv"

function Get-MetarFallbackValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Icao
    )

    $url = "https://metar-taf.com/metar/$Icao"

    $body = @{
        cmd        = "request.get"
        url        = $url
        maxTimeout = 60000
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $flaresolverrUrl `
            -ContentType "application/json" `
            -Body $body

        if ($response.status -ne "ok") {
            Write-Warning "FlareSolverr failed for $Icao with status '$($response.status)'"
            return $null
        }

        $html = $response.solution.response
        if ([string]::IsNullOrWhiteSpace($html)) {
            Write-Warning "No HTML returned for $Icao"
            return $null
        }

        $match = [regex]::Match(
            $html,
            '<a\b[^>]*\bid=["'']stationSelectButton["''][^>]*>(.*?)</a>',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if (-not $match.Success) {
            Write-Warning "stationSelectButton not found for $Icao"
            return $null
        }

        $value = $match.Groups[1].Value
        $value = [System.Text.RegularExpressions.Regex]::Replace($value, '<.*?>', '')
        $value = [System.Net.WebUtility]::HtmlDecode($value).Trim()

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Warning "Empty stationSelectButton value for $Icao"
            return $null
        }

        return $value
    }
    catch {
        Write-Warning "Request failed for $Icao : $($_.Exception.Message)"
        return $null
    }
}

function Append-NearbyIcaoFallback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$FallbackMap
    )

    if (-not (Test-Path $CsvPath)) {
        throw "CSV not found: $CsvPath"
    }

    $rows = Import-Csv $CsvPath

    foreach ($row in $rows) {
        $icao = $row.ICAO.Trim()

        if (-not $FallbackMap.ContainsKey($icao)) {
            continue
        }

        $fallback = $FallbackMap[$icao]
        if ([string]::IsNullOrWhiteSpace($fallback)) {
            continue
        }

        $existing = @()

        if (-not [string]::IsNullOrWhiteSpace($row.NearbyICAOs)) {
            $existing = $row.NearbyICAOs -split '\s*,\s*' | Where-Object { $_ -and $_.Trim() -ne "" }
        }

        if ($existing -contains $fallback) {
            continue
        }

        if ($existing.Count -eq 0) {
            $row.NearbyICAOs = $fallback
        }
        else {
            $row.NearbyICAOs = (($existing + $fallback) | Select-Object -Unique) -join ","
        }
    }

    $backupPath = "$CsvPath.bak"
    Copy-Item $CsvPath $backupPath -Force
    $rows | Export-Csv $CsvPath -NoTypeInformation
    Write-Host "Updated: $CsvPath"
    Write-Host "Backup:  $backupPath"
}

$missingRows = Import-Csv $missingCsv

$fallbackMap = @{}
$resolvedRows = foreach ($row in $missingRows) {
    if ($row.present_in_metars_csv -ne "False") {
        continue
    }

    $icao = $row.icao.Trim()
    $foundValue = Get-MetarFallbackValue -Icao $icao

    if ($foundValue) {
        $fallbackMap[$icao] = $foundValue
    }

    [pscustomobject]@{
        icao        = $icao
        found_value = $foundValue
        success     = [bool]$foundValue
    }
}

$resolvedRows | Export-Csv ".\missing_from_metars_resolved.csv" -NoTypeInformation

Append-NearbyIcaoFallback -CsvPath $atcSourcesCsv -FallbackMap $fallbackMap
Append-NearbyIcaoFallback -CsvPath $liveAtcSourcesCsv -FallbackMap $fallbackMap

$resolvedRows | Format-Table -AutoSize
Write-Host ""
Write-Host "Fallback map:"
$fallbackMap.GetEnumerator() | Sort-Object Name | Format-Table Name, Value -AutoSize
