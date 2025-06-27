# Fetches the latest list of airports from liveatc.net and refreshes
# atc_sources.csv with any new or updated streams.
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot '..' 'atc_sources.csv')
)

Function Get-AllLiveATCAirports {
    Function Parse-AirportsJson {
        param([string]$Content)
        try {
            $match = [regex]::Match($Content, '(?s)airports[^=]*=\s*(?<json>\[[^;]+\])')
            if ($match.Success) {
                $data = $match.Groups['json'].Value | ConvertFrom-Json
                return $data | Select-Object -ExpandProperty icao -Unique | Where-Object { $_ }
            }
        } catch {}
        return $null
    }

    try {
        $page = Invoke-WebRequest -Uri 'https://www.liveatc.net/search/' -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Referer'='https://www.liveatc.net/' }

        $pattern = @'
<script[^>]+src=["'](?<p>[^"']*airports[^"']*\.js[^"']*)
'@
        $scriptUrls = [regex]::Matches($page.Content, $pattern) | ForEach-Object {
            $u = $_.Groups['p'].Value
            if ($u -notmatch '^https?://') { "https://www.liveatc.net$u" } else { $u }
        }

        foreach ($url in $scriptUrls) {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Referer'='https://www.liveatc.net/search/' }
            $codes = Parse-AirportsJson -Content $resp.Content
            if ($codes) { return $codes }
        }

        $inlineCodes = Parse-AirportsJson -Content $page.Content
        if ($inlineCodes) { return $inlineCodes }
    } catch {
        # ignore network errors and continue
    }

    $fallbackUrls = @(
        'https://www.liveatc.net/cache/airports.js',
        'https://www.liveatc.net/search/airports.js',
        'https://www.liveatc.net/assets/js/airports.js'
    )
    foreach ($url in $fallbackUrls) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Referer'='https://www.liveatc.net/' }
            $codes = Parse-AirportsJson -Content $resp.Content
            if ($codes) { return $codes }
        } catch {}
    }

    Write-Error 'Failed to fetch airport list'
    return @()
}

Function Get-LiveATCSources {
    param([string]$ICAO)
    try {
        $url = "https://www.liveatc.net/search/?icao=$ICAO"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $htmlContent = $response.Content
        $sources = @()
        $current = ""
        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()
            if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feed>[^<]+)</strong>') {
                $current = $matches['feed'].Trim()
            } elseif ($row -match '<td[^>]*>\s*<a href="(?<url>[^"]+\.pls)"') {
                $sources += [PSCustomObject]@{
                    Channel = $current
                    URL     = "https://www.liveatc.net" + $matches['url'].Trim()
                }
            }
        }
        return $sources
    } catch {
        Write-Error "Failed to fetch sources for ${ICAO}: $_"
        return @()
    }
}

Function Get-AirportDetails {
    param([string]$ICAO)
    try {
        $url = "https://www.liveatc.net/search/?icao=$ICAO"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $htmlContent = $response.Content
        $icao=""; $iata=""; $airport=""; $city=""; $prov=""; $country=""; $cont=""
        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()
            if ($row -match '<td[^>]*>\s*<strong>ICAO:\s*</strong>(?<icao>[^<]+)\s*<strong>&nbsp;&nbsp;IATA:\s*</strong>(?<iata>[^<]+)\s*&nbsp;&nbsp;<strong>Airport:</strong>\s*(?<airport>[^<]+)') {
                $icao = $matches['icao'].Trim()
                $iata = $matches['iata'].Trim()
                $airport = $matches['airport'].Trim()
            } elseif ($row -match '<td[^>]*>\s*<strong>City:\s*</strong>\s*(?<city>[^<]+)(?:\s*<strong>&nbsp;&nbsp;State/Province:</strong>\s*(?<prov>[^<]+))?') {
                $city = $matches['city'].Trim()
                if ($matches['prov']) { $prov = $matches['prov'].Trim() }
            } elseif ($row -match '<td[^>]*>\s*<strong>Country:\s*</strong>\s*(?<country>[^<]+)\s*<strong>&nbsp;&nbsp;Continent:</strong>\s*(?<cont>[^<]+)') {
                $country = $matches['country'].Trim()
                $cont = $matches['cont'].Trim()
            }
        }
        if ($icao) {
            return [PSCustomObject]@{
                ICAO=$icao; IATA=$iata; Airport=$airport; City=$city; Province=$prov; Country=$country; Continent=$cont
            }
        }
        return $null
    } catch {
        Write-Error "Failed to fetch airport details for ${ICAO}: $_"
        return $null
    }
}

Function Update-LiveATCSources {
    param(
        [string]$Path,
        [string[]]$ICAOs
    )
    $existing = @()
    if (Test-Path $Path) {
        $existing = Import-Csv $Path
    }
    $map = @{}
    foreach ($row in $existing) {
        $key = "$($row.ICAO)|$($row.'Channel Description')"
        $map[$key] = $row
    }
    if (-not $ICAOs) {
        $ICAOs = $existing | Select-Object -ExpandProperty ICAO -Unique
    }
    foreach ($icao in $ICAOs) {
        Write-Host "Updating $icao..." -ForegroundColor Cyan
        $sources = Get-LiveATCSources -ICAO $icao
        $details = Get-AirportDetails -ICAO $icao
        foreach ($s in $sources) {
            $row = [PSCustomObject]@{
                Continent=$details.Continent
                Country=$details.Country
                City=$details.City
                'State/Province'=$details.Province
                'Airport Name'=$details.Airport
                ICAO=$details.ICAO
                IATA=$details.IATA
                'Channel Description'=$s.Channel
                'Stream URL'=$s.URL
                'Webcam URL'=""
            }
            $key = "$icao|$($s.Channel)"
            if ($map.ContainsKey($key)) {
                $map[$key].'Stream URL' = $s.URL
            } else {
                $map[$key] = $row
            }
        }
    }
    $map.Values | Sort-Object ICAO,'Channel Description' | Export-Csv -Path $Path -NoTypeInformation
}

$icaoList = Get-AllLiveATCAirports
if ($icaoList.Count -eq 0) {
    Write-Warning 'No ICAO codes retrieved; using existing CSV entries.'
}
Update-LiveATCSources -Path $CsvPath -ICAOs $icaoList

