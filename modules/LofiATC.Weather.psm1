# Functions dot-sourced by lofiatc.ps1. Keep script-scoped state in the entrypoint.
Function Get-METAR-TAF {
    param (
        [string]$ICAO,
        [string[]]$FallbackICAOs
    )

    $icaoList = @($ICAO)
    if ($FallbackICAOs) {
        $icaoList += $FallbackICAOs
    }

    $raw = $null
    $used = $ICAO
    $source = $null
    $sourceUrl = $null

    foreach ($code in $icaoList) {
        $url = "https://aviationweather.gov/api/data/metar?ids=$code"
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
            $raw = $response.Content.Trim()
            if ($raw -match "\b$code\b" -and $raw -match '\b\d{6}Z\b') {
                $used = $code; $source = 'NOAA'; $sourceUrl = 'https://aviationweather.gov'
                break
            }
            else {
                Write-Verbose ("NOAA METAR invalid for {0}: {1}" -f $code, $raw)
            }
        }
        catch {
            Write-Verbose ("NOAA METAR fetch failed for {0}: {1}" -f $code, $_) 
        }

        try {
            $vatsimUrl = "https://metar.vatsim.net/metar.php?id=$code"
            $response = Invoke-WebRequest -Uri $vatsimUrl -UseBasicParsing -Verbose:$false
            $raw = $response.Content.Trim()
            if ($raw -match "\b$code\b" -and $raw -match '\b\d{6}Z\b') {
                $used = $code; $source = 'VATSIM'; $sourceUrl = 'https://metar.vatsim.net'
                break
            }
            else {
                Write-Verbose ("VATSIM METAR invalid for {0}: {1}" -f $code, $raw)
            }
        }
        catch {
            Write-Verbose ("VATSIM METAR fetch failed for {0}: {1}" -f $code, $_)
        }
    }

    if (-not $raw) {
        Write-Error "Failed to fetch METAR/TAF data for $ICAO and fallbacks."
        return [pscustomobject]@{ Report = "METAR/TAF data unavailable."; ICAO = $ICAO; DistanceKm = $null; Source = $null; SourceUrl = $null }
    }

    $distance = if ($used -ne $ICAO) {
        $orig = Get-AirportInfo -ICAO $ICAO
        $alt = Get-AirportInfo -ICAO $used
        if ($orig -and $alt) {
            Get-DistanceKm -Lat1 $orig.lat -Lon1 $orig.lon -Lat2 $alt.lat -Lon2 $alt.lon
        }
        else {
            $null
        }
    }
    else {
        0
    }

    $distanceNm = if ($null -ne $distance) {
        ConvertTo-NauticalMiles -Kilometers $distance -Decimals 0 
    } 
    else {
        $null
    }

    return [pscustomobject]@{ 
        Report = $raw
        ICAO = $used
        DistanceKm = $distance
        DistanceNm = $distanceNm
        Source = $source
        SourceUrl = $sourceUrl 
    }
}

# Function to decode METAR string into a structured object
Function ConvertFrom-METAR {
    param (
        [string]$metar
    )

    $decoded = @{}

    if ($metar -match "(?<windDir>\d{3})(?<windSpeed>\d{2})(G(?<gustSpeed>\d{2}))?KT") {
        $decoded["Wind"] = if ($matches.gustSpeed) { 
            "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots, gusting to $([int]$matches.gustSpeed) knots" 
        }
        else {
            "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots"
        }
    }

    if ($metar -match "(?<visibility>9999)") {
        $decoded["Visibility"] = "10+ km (Unlimited)" 
    }
    elseif ($metar -match "\b(?<visibility>\d{4})\b") {
        $decoded["Visibility"] = "$([int]$matches.visibility / 1000) km"
    }
    elseif ($metar -match "(?<visibility>\d+SM)") {
        $decoded["Visibility"] = "$([math]::Round([double]($matches.visibility -replace 'SM','') * 1.60934, 3)) km"
    }
    else {
        $decoded["Visibility"] = "Unavailable"
    }

    if ($metar -match "VV(?<vv>\d{3})") {
        $decoded["Ceiling"] = "Vertical Visibility at $([int]$matches.vv * 100) ft"
    }
    elseif ($metar -match "(?<clouds>BKN|OVC|SCT|FEW)(?<ceiling>\d{3})") {
        $cloudType = switch ($matches.clouds) {
            "BKN" {
                "Broken"
            } 
            "OVC" {
                "Overcast"
            } 
            "SCT" {
                "Scattered"
            } 
            "FEW" {
                "Few"
            } 
            default { 
                $matches.clouds
            }
        }
        $decoded["Ceiling"] = "$cloudType at $([int]$matches.ceiling * 100) ft"
    }
    else {
        $decoded["Ceiling"] = "Unavailable"
    }

    if ($metar -match "(?<temp>-?\d{1,2})/(?<dew>-?\d{1,2}|M\d{1,2})") {
        $temperature = if ($matches.temp -eq "-00") {
            "0$([char]176)C"
        } 
        else {
            "$([int]$matches.temp)$([char]176)C"
        }

        $dewPoint = if ($matches.dew -eq "-00") {
            "0$([char]176)C"
        }
        elseif ($matches.dew -like "M*") {
            "-$([int]($matches.dew.Trim('M')))$([char]176)C"
        }
        else {
            "$([int]$matches.dew)$([char]176)C"
        }

        $decoded["Temperature"] = $temperature
        $decoded["DewPoint"] = $dewPoint
    }
    else {
        $decoded["Temperature"] = "Unavailable"; $decoded["DewPoint"] = "Unavailable"
    }

    if ($metar -match "Q(?<pressureHPA>\d{4})") {
        $decoded["Pressure"] = "$([int]$matches.pressureHPA) hPa"
    }
    elseif ($metar -match "A(?<pressureINHG>\d{4})") {
        $pressureHPA = [double]($matches.pressureINHG / 100) * 33.8639
        $decoded["Pressure"] = "$([math]::Round($pressureHPA, 1)) hPa"
    }
    else {
        $decoded["Pressure"] = "Unavailable"
    }

    return [PSCustomObject]$decoded
}

# Function to calculate the age of a METAR report in minutes based on the timestamp in the METAR string, returning null if the timestamp is missing or invalid
Function Get-METARAgeMinutes {
    param(
        [string]$Metar
    )

    if ([string]::IsNullOrWhiteSpace($Metar)) {
        return $null
    }

    if ($Metar -notmatch '\b(?<ts>\d{6})Z\b') {
        return $null
    }

    try {
        $ts = $matches.ts
        $day = [int]$ts.Substring(0, 2)
        $hour = [int]$ts.Substring(2, 2)
        $min = [int]$ts.Substring(4, 2)

        $now = [datetime]::UtcNow
        $year = $now.Year
        $month = $now.Month

        if ($day -gt $now.Day) {
            $prev = $now.AddMonths(-1)
            $year = $prev.Year
            $month = $prev.Month
        }

        $obs = New-Object DateTime($year, $month, $day, $hour, $min, 0, [System.DateTimeKind]::Utc)
        $age = $now - $obs

        if ($age.TotalMinutes -lt 0) {
            return $null
        }

        return [int][math]::Floor($age.TotalMinutes)
    }
    catch {
        return $null
    }
}

# Function to convert an IANA timezone ID to a .NET TimeZoneInfo object, with fallback mapping for common timezones
Function ConvertTo-TimeZoneInfo {
    param(
        [string]$IanaId
    )

    try {
        return [System.TimeZoneInfo]::FindSystemTimeZoneById($IanaId)
    }
    catch {
        if ($script:IanaToWindowsMap.ContainsKey($IanaId)) {
            return [System.TimeZoneInfo]::FindSystemTimeZoneById($script:IanaToWindowsMap[$IanaId])
        }
        else {
            throw "Timezone ID '$IanaId' not recognized"
        }
    }
}

# Function to fetch airport information from a cached dataset, loading it from a remote source if not already loaded, and return the info for a given ICAO code
Function Get-AirportInfo {
    param(
        [string]$ICAO
    )

    if (-not $script:AirportData) {
        try {
            $script:AirportData = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/rominjun/Airports/master/airports.json' -Method Get
        }
        catch {
            Write-Error "Failed to load airport database. Exception: $_"; return $null
        }
    }
    $info = $script:AirportData.$ICAO
    if (-not $info) {
        Write-Error "Airport info not found for $ICAO."
    }

    return $info
}

# Function to get the local date and time at an airport based on its ICAO code, using the airport's timezone information and handling errors gracefully
Function Get-AirportDateTime {
    param ([string]$ICAO)
    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        if (-not $airportInfo -or -not $airportInfo.tz) {
            throw "Timezone not found"
        }
        $tzInfo = ConvertTo-TimeZoneInfo -IanaId $airportInfo.tz
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tzInfo)
        return "$($local.ToString('dd MMMM yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)) LT"
    }
    catch {
        Write-Error "Date and time not found for $ICAO. Exception: $_"; return "Date/time data unavailable"
    }
}

# Function to get the sunrise and sunset times for an airport based on its ICAO code, using the airport's geographic coordinates and timezone information
Function Get-AirportSunriseSunset {
    param (
        [string]$ICAO
    )

    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        $lat = $airportInfo.lat; $lon = $airportInfo.lon; $tz = $airportInfo.tz
        if (-not ($lat -and $lon -and $tz)) {
            throw "Missing data"
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tzInfo = ConvertTo-TimeZoneInfo -IanaId $tz

        $uri = "https://api.sunrise-sunset.org/json?lat=$lat&lng=$lon&formatted=0&tzid=$tz"
        $sunInfo = Invoke-RestMethod -Uri $uri -Method Get
        $sunriseOffset = [datetimeoffset]::Parse($sunInfo.results.sunrise, [cultureinfo]::InvariantCulture)
        $sunsetOffset = [datetimeoffset]::Parse($sunInfo.results.sunset, [cultureinfo]::InvariantCulture)

        return @{
            Sunrise = [System.TimeZoneInfo]::ConvertTime($sunriseOffset, $tzInfo).ToString('HH:mm')
            Sunset  = [System.TimeZoneInfo]::ConvertTime($sunsetOffset, $tzInfo).ToString('HH:mm')
        }
    }
    catch { Write-Error "Failed to fetch data for $ICAO. Exception: $_"; return @{ Sunrise = "Data unavailable"; Sunset = "Data unavailable" } }
}

# Function to determine how long ago the METAR report was updated based on the timestamp in the METAR string, handling time zone and date rollovers correctly
Function Get-METAR-LastUpdatedTime {
    param (
        [string]$ICAO,
        [string[]]$FallbackICAOs
    )
    try {
        $metarInfo = Get-METAR-TAF -ICAO $ICAO -FallbackICAOs $FallbackICAOs
        if ($metarInfo.Report -match '\b(?<ts>\d{6})Z\b') {
            $ts = $matches.ts
            $day = [int]$ts.Substring(0, 2); $hour = [int]$ts.Substring(2, 2); $min = [int]$ts.Substring(4, 2)
            $now = (Get-Date).ToUniversalTime()
            $year = $now.Year; $month = $now.Month

            if ($day -gt $now.Day) {
                $prev = $now.AddMonths(-1)
                $year = $prev.Year
                $month = $prev.Month
            }

            $obs = New-Object DateTime($year, $month, $day, $hour, $min, 0, [System.DateTimeKind]::Utc)
            $diff = $now - $obs
            if ($diff.TotalHours -ge 1) {
                return "{0:N0} hours" -f [math]::Floor($diff.TotalHours)
            }
            else {
                return "{0:N0} minutes" -f [math]::Floor($diff.TotalMinutes)
            }
        }
        else {
            throw 'Time code not found'
        }
    }
    catch {
        Write-Error "Failed to fetch the last updated time for $ICAO. Exception: $_"
        return "Last updated time unavailable."
    }
}

# Function to display a welcome message with airport information
Function Get-MapWeatherData {
    param(
        [array]$AtcSources,
        [switch]$NoWeather,
        [switch]$UseVatsimFallback
    )

    $weatherMap = @{}
    $icaoToFallbacks = @{}
    $stats = [ordered]@{
        NoaaStations  = 0
        VatsimStations = 0
        NoaaMs        = 0
        VatsimMs      = 0
        NoaaRequests  = 0
        VatsimRequests = 0
    }

    if ($NoWeather) {
        return @{
            WeatherMap      = $weatherMap
            IcaoToFallbacks = $icaoToFallbacks
            Stats           = [pscustomobject]$stats
        }
    }

    Write-Host "Fetching live weather & wind data..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {}

    $allIcaosToFetch = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($src in $AtcSources) {
        $allIcaosToFetch.Add($src.ICAO) | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($src.NearbyICAOs)) {
            $fbs = $src.NearbyICAOs -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $icaoToFallbacks[$src.ICAO] = $fbs
            foreach ($fb in $fbs) {
                $allIcaosToFetch.Add($fb) | Out-Null
            }
        }
    }

    $icaoArray = @($allIcaosToFetch)

    $chunkSize = 100

    for ($i = 0; $i -lt $icaoArray.Count; $i += $chunkSize) {
        $chunkEnd = [math]::Min($i + ($chunkSize - 1), $icaoArray.Count - 1)
        $chunk = $icaoArray[$i..$chunkEnd] -join ','

        try {
            $noaaTimer = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $stats.NoaaRequests++
                $wxData = Invoke-RestMethod -Uri "https://aviationweather.gov/api/data/metar?ids=$chunk&format=json" -Method Get -TimeoutSec 12
            }
            finally {
                $noaaTimer.Stop()
                $stats.NoaaMs += [int]$noaaTimer.ElapsedMilliseconds
            }

            foreach ($item in $wxData) {
                if ($item.icaoId) {
                    $rawOb = if ($item.rawOb) { [string]$item.rawOb } else { "METAR Unavailable" }

                    $weatherMap[$item.icaoId] = @{
                        fcat = if ($item.fltcat) { $item.fltcat } else { "UNK" }
                        wdir = if ($null -ne $item.wdir) { $item.wdir } else { "null" }
                        wspd = if ($null -ne $item.wspd) { $item.wspd } else { 0 }
                        rawOb  = ConvertTo-JsSafeString $rawOb
                        ageMin = Get-METARAgeMinutes -Metar $rawOb
                        source = 'NOAA'
                        wxIcao = [string]$item.icaoId
                    }

                    $stats.NoaaStations++
                }
            }
        }
        catch {
            Write-Verbose "NOAA fetch failed for chunk: $_"
        }
    }

    $missingPrimaries = $AtcSources.ICAO | Sort-Object -Unique | Where-Object {
        -not $weatherMap.ContainsKey($_)
    }

    if ($UseVatsimFallback -and $missingPrimaries.Count -gt 0) {
        Write-Host "Fetching VATSIM alternative METARs for $($missingPrimaries.Count) stations..." -ForegroundColor DarkCyan

        foreach ($mIcao in $missingPrimaries) {
            try {
                $vatsimTimer = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $stats.VatsimRequests++
                    $vRes = Invoke-WebRequest -Uri "https://metar.vatsim.net/metar.php?id=$mIcao" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
                    $vRaw = if ($null -ne $vRes -and $vRes.PSObject.Properties['Content']) {
                        [string]$vRes.Content
                    }
                    else {
                        [string]$vRes
                    }

                    $vRaw = $vRaw.Trim()
                }
                finally {
                    $vatsimTimer.Stop()
                    $stats.VatsimMs += [int]$vatsimTimer.ElapsedMilliseconds
                }

                if (-not [string]::IsNullOrWhiteSpace($vRaw) -and $vRaw -match "\b$([regex]::Escape($mIcao))\b") {
                    $fcat = "VFR"
                    if ($vRaw -match "\bM?1/4SM|\bM?1/2SM|\bM?3/4SM") {
                        $fcat = "LIFR"
                    }
                    elseif ($vRaw -match "\b[1-2]SM|\b1 1/2SM|\b2 1/2SM") {
                        $fcat = "IFR"
                    }
                    elseif ($vRaw -match "\b[3-5]SM") {
                        $fcat = "MVFR"
                    }

                    if ($vRaw -match "(BKN|OVC|VV)(00[0-4])") {
                        $fcat = "LIFR"
                    }
                    elseif ($vRaw -match "(BKN|OVC|VV)(00[5-9])") {
                        if ($fcat -ne "LIFR") {
                            $fcat = "IFR"
                        }
                    }
                    elseif ($vRaw -match "(BKN|OVC|VV)(0[1-2]\d|030)") {
                        if ($fcat -notin @("LIFR", "IFR")) {
                            $fcat = "MVFR"
                        }
                    }

                    $wdir = "null"
                    $wspd = 0

                    if ($vRaw -match "(?<wdir>\d{3}|VRB)(?<wspd>\d{2,3})(G\d{2,3})?KT") {
                        if ($matches.wdir -match "\d{3}") {
                            $wdir = [int]$matches.wdir
                        }
                        $wspd = [int]$matches.wspd
                    }

                    $weatherMap[$mIcao] = @{
                        fcat   = $fcat
                        wdir   = $wdir
                        wspd   = $wspd
                        rawOb  = "[VATSIM] " + (ConvertTo-JsSafeString $vRaw)
                        ageMin = Get-METARAgeMinutes -Metar $vRaw
                        source = 'VATSIM'
                        wxIcao = $mIcao
                    }

                    $stats.VatsimStations++
                }
            }
            catch {}
        }
    }

    if ($weatherMap.Count -eq 0) {
        Write-Warning "Could not connect to weather services. Map will default to Offline/Unknown colors."
    }

    return @{
        WeatherMap      = $weatherMap
        IcaoToFallbacks = $icaoToFallbacks
        Stats           = [pscustomobject]$stats
    }
}

Function New-MapWeatherPayload {
    param(
        [array]$AtcSources,
        [array]$Favorites,
        [switch]$IncludeWebcamIfAvailable
    )

    $weatherData = Get-MapWeatherData -AtcSources $AtcSources -UseVatsimFallback
    $markersJson = ConvertTo-MapMarkers `
        -AtcSources $AtcSources `
        -Favorites $Favorites `
        -WeatherMap $weatherData.WeatherMap `
        -IcaoToFallbacks $weatherData.IcaoToFallbacks `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable

    $stats = if ($weatherData.Stats) {
        $weatherData.Stats
    }
    else {
        [pscustomobject]@{
            NoaaStations   = 0
            VatsimStations = 0
            NoaaMs         = 0
            VatsimMs       = 0
            NoaaRequests   = 0
            VatsimRequests = 0
        }
    }

    return @{
        ok      = $true
        message = "Weather stations loaded: $($stats.NoaaStations) NOAA, $($stats.VatsimStations) VATSIM."
        stats   = $stats
        markers = @($markersJson | ConvertFrom-Json)
    }
}
