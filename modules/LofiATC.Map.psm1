# Functions dot-sourced by lofiatc.ps1. Keep script-scoped state in the entrypoint.
Function Invoke-MapChannelSelection {
    param(
        [hashtable]$Selection,
        [array]$AtcSources,
        [string]$Player,
        [int]$ATCVolume,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [string]$LofiMusicUrl,
        [int]$LofiVolume
    )

    if (-not $Selection -or -not $Selection.ICAO) {
        throw "Invalid map selection."
    }

    $icaoMatches = @($AtcSources | Where-Object { $_.ICAO -eq $Selection.ICAO })
    if ($icaoMatches.Count -eq 0) {
        throw "No ATC stream found for ICAO $($Selection.ICAO)."
    }

    if ($null -eq $Selection.ChannelIndex -or $Selection.ChannelIndex -lt 0 -or $Selection.ChannelIndex -ge $icaoMatches.Count) {
        throw "Invalid channel index returned from map for ICAO $($Selection.ICAO)."
    }

    $match = $icaoMatches[$Selection.ChannelIndex]

    $effectiveATCVolume = if ($null -ne $script:CurrentATCVolume) {
        [int]$script:CurrentATCVolume
    }
    else {
        [int]$ATCVolume
    }

    $effectiveLofiVolume = if ($null -ne $script:CurrentLofiVolume) {
        [int]$script:CurrentLofiVolume
    }
    else {
        [int]$LofiVolume
    }

    $script:CurrentATCVolume = $effectiveATCVolume
    $script:CurrentLofiVolume = $effectiveLofiVolume

    Stop-ManagedProcess -Process $script:CurrentATCProcess
    $script:CurrentATCProcess = $null

    Stop-ManagedProcess -Process $script:CurrentWebcamProcess
    $script:CurrentWebcamProcess = $null

    $script:CurrentATCProcess = Start-PlayerProcess `
        -Url $match.'Stream URL' `
        -Player $Player `
        -NoVideo `
        -BasicArgs `
        -Volume $effectiveATCVolume

    if ($IncludeWebcamIfAvailable -and -not [string]::IsNullOrWhiteSpace($match.'Webcam URL')) {
        $script:CurrentWebcamProcess = Start-PlayerProcess `
            -Url $match.'Webcam URL' `
            -Player $Player `
            -NoAudio `
            -BasicArgs
    }

    if (-not $NoLofiMusic) {
        $lofiAlive = Test-ManagedProcessAlive -Process $script:CurrentLofiProcess

        if (-not $lofiAlive) {
            $script:CurrentLofiProcess = if ($PlayLofiGirlVideo) {
                Start-PlayerProcess `
                    -Url $LofiMusicUrl `
                    -Player $Player `
                    -BasicArgs `
                    -Volume $effectiveLofiVolume
            }
            else {
                Start-PlayerProcess `
                    -Url $LofiMusicUrl `
                    -Player $Player `
                    -NoVideo `
                    -BasicArgs `
                    -Volume $effectiveLofiVolume
            }
        }
    }

    $script:CurrentMapSelection = $match

    return @{
        ICAO    = $match.ICAO
        Channel = $match.'Channel Description'
        Airport = $match.'Airport Name'
        Webcam  = [bool](-not [string]::IsNullOrWhiteSpace($match.'Webcam URL'))
        Lofi    = [bool](-not $NoLofiMusic)
    }
}

# Function to handle various playback actions from the interactive map, such as stopping the ATC stream, stopping all media, restarting the current stream, or selecting a random stream
Function Invoke-MapPlaybackAction {
    param(
        [string]$Action,
        [array]$AtcSources,
        [string]$Player,
        [int]$ATCVolume,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [string]$LofiMusicUrl,
        [int]$LofiVolume,
        [string]$Target,
        [int]$Volume = -1,
        [string]$ICAO,
        [int]$ChannelIndex = -1,
        [string]$FavoritesPath
    )

    switch ($Action.ToLowerInvariant()) {
        'stop-atc' {
            Stop-ManagedProcess -Process $script:CurrentATCProcess
            Stop-ManagedProcess -Process $script:CurrentWebcamProcess

            $script:CurrentATCProcess = $null
            $script:CurrentWebcamProcess = $null

            return @{
                ok      = $true
                stopped = $true
                message = 'ATC and webcam playback stopped.'
            }
        }

        'stop-lofi' {
            Stop-ManagedProcess -Process $script:CurrentLofiProcess

            $script:CurrentLofiProcess = $null

            return @{
                ok      = $true
                message = 'Lofi playback stopped.'
                lofi    = $false
            }
        }

        'set-volume' {
            if ($Volume -lt 0 -or $Volume -gt 100) {
                throw 'Volume must be between 0 and 100.'
            }

            $targetName = if ($Target) {
                $Target.ToLowerInvariant()
            }
            else {
                ''
            }

            switch ($targetName) {
                'atc' {
                    $script:CurrentATCVolume = $Volume

                    if (-not $script:CurrentMapSelection) {
                        return @{
                            ok        = $true
                            message   = "ATC volume set to $Volume% for the next channel."
                            atcVolume = $Volume
                        }
                    }

                    $current = $script:CurrentMapSelection

                    Stop-ManagedProcess -Process $script:CurrentATCProcess
                    $script:CurrentATCProcess = $null

                    $script:CurrentATCProcess = Start-PlayerProcess `
                        -Url $current.'Stream URL' `
                        -Player $Player `
                        -NoVideo `
                        -BasicArgs `
                        -Volume $script:CurrentATCVolume

                    return @{
                        ok        = $true
                        message   = "ATC volume set to $Volume%."
                        atcVolume = $Volume
                    }
                }

                'lofi' {
                    $script:CurrentLofiVolume = $Volume

                    if ($NoLofiMusic) {
                        return @{
                            ok         = $true
                            message    = "Lofi is disabled. Lofi volume saved as $Volume% for later."
                            lofi       = $false
                            lofiVolume = $Volume
                        }
                    }

                    $lofiAlive = Test-ManagedProcessAlive -Process $script:CurrentLofiProcess

                    if (-not $lofiAlive -and -not $script:CurrentMapSelection) {
                        return @{
                            ok         = $true
                            message    = "Lofi volume set to $Volume% for the next channel."
                            lofiVolume = $Volume
                        }
                    }

                    Stop-ManagedProcess -Process $script:CurrentLofiProcess
                    $script:CurrentLofiProcess = $null

                    $script:CurrentLofiProcess = if ($PlayLofiGirlVideo) {
                        Start-PlayerProcess `
                            -Url $LofiMusicUrl `
                            -Player $Player `
                            -BasicArgs `
                            -Volume $script:CurrentLofiVolume
                    }
                    else {
                        Start-PlayerProcess `
                            -Url $LofiMusicUrl `
                            -Player $Player `
                            -NoVideo `
                            -BasicArgs `
                            -Volume $script:CurrentLofiVolume
                    }

                    return @{
                        ok         = $true
                        message    = "Lofi volume set to $Volume%."
                        lofi       = $true
                        lofiVolume = $Volume
                    }
                }

                default {
                    throw 'Volume target must be atc or lofi.'
                }
            }
        }

        'favorite-toggle' {
            if ([string]::IsNullOrWhiteSpace($FavoritesPath)) {
                throw 'Favorites path is not available.'
            }

            if ([string]::IsNullOrWhiteSpace($ICAO)) {
                throw 'ICAO is required to update favorites.'
            }

            if ($ChannelIndex -lt 0) {
                throw 'Channel index is required to update favorites.'
            }

            $icaoMatches = @($AtcSources | Where-Object { $_.ICAO -eq $ICAO })

            if ($icaoMatches.Count -eq 0) {
                throw "No ATC stream found for ICAO $ICAO."
            }

            if ($ChannelIndex -ge $icaoMatches.Count) {
                throw "Invalid channel index for ICAO $ICAO."
            }

            $match = $icaoMatches[$ChannelIndex]
            $channel = [string]$match.'Channel Description'

            $favorites = @(Get-Favorite -path $FavoritesPath)
            $existing = $favorites | Where-Object {
                $_.ICAO -eq $ICAO -and $_.Channel -eq $channel
            } | Select-Object -First 1

            if ($existing) {
                Remove-Favorite `
                    -path $FavoritesPath `
                    -ICAO $ICAO `
                    -Channel $channel | Out-Null

                return @{
                    ok        = $true
                    favorited = $false
                    icao      = $ICAO
                    channel   = $channel
                    message   = "Removed favorite: $ICAO — $channel"
                }
            }

            Add-Favorite `
                -path $FavoritesPath `
                -ICAO $ICAO `
                -Channel $channel `
                -maxEntries 10

            return @{
                ok        = $true
                favorited = $true
                icao      = $ICAO
                channel   = $channel
                message   = "Added favorite: $ICAO — $channel"
            }
        }

        'airport-favorite-toggle' {
            if ([string]::IsNullOrWhiteSpace($FavoritesPath)) {
                throw 'Favorites path is not available.'
            }

            if ([string]::IsNullOrWhiteSpace($ICAO)) {
                throw 'ICAO is required to update airport favorites.'
            }

            $airportFavoriteChannel = '__AIRPORT__'

            $airportMatches = @($AtcSources | Where-Object { $_.ICAO -eq $ICAO })

            if ($airportMatches.Count -eq 0) {
                throw "No ATC streams found for ICAO $ICAO."
            }

            $airportName = [string]$airportMatches[0].'Airport Name'

            $favorites = @(Get-Favorite -path $FavoritesPath)
            $existing = $favorites | Where-Object {
                $_.ICAO -eq $ICAO -and $_.Channel -eq $airportFavoriteChannel
            } | Select-Object -First 1

            if ($existing) {
                Remove-Favorite `
                    -path $FavoritesPath `
                    -ICAO $ICAO `
                    -Channel $airportFavoriteChannel | Out-Null

                return @{
                    ok        = $true
                    favorited = $false
                    icao      = $ICAO
                    airport   = $airportName
                    message   = "Removed airport favorite: $ICAO — $airportName"
                }
            }

            Add-Favorite `
                -path $FavoritesPath `
                -ICAO $ICAO `
                -Channel $airportFavoriteChannel `
                -maxEntries 10

            return @{
                ok        = $true
                favorited = $true
                icao      = $ICAO
                airport   = $airportName
                message   = "Added airport favorite: $ICAO — $airportName"
            }
        }

        'stop-all' {
            Stop-ManagedProcess -Process $script:CurrentATCProcess
            Stop-ManagedProcess -Process $script:CurrentWebcamProcess
            Stop-ManagedProcess -Process $script:CurrentLofiProcess

            $script:CurrentATCProcess = $null
            $script:CurrentWebcamProcess = $null
            $script:CurrentLofiProcess = $null
            $script:CurrentMapSelection = $null

            return @{
                ok      = $true
                stopped = $true
                message = 'All playback stopped.'
            }
        }

        'restart' {
            if (-not $script:CurrentMapSelection) {
                throw 'No channel is currently selected.'
            }

            $current = $script:CurrentMapSelection
            $icaoMatches = @($AtcSources | Where-Object { $_.ICAO -eq $current.ICAO })

            $channelIndex = -1
            for ($i = 0; $i -lt $icaoMatches.Count; $i++) {
                if (
                    $icaoMatches[$i].'Channel Description' -eq $current.'Channel Description' -and
                    $icaoMatches[$i].'Stream URL' -eq $current.'Stream URL'
                ) {
                    $channelIndex = $i
                    break
                }
            }

            if ($channelIndex -lt 0) {
                throw 'Could not find the current channel in the source list.'
            }

            Stop-ManagedProcess -Process $script:CurrentLofiProcess
            $script:CurrentLofiProcess = $null

            $started = Invoke-MapChannelSelection `
                -Selection @{ ICAO = $current.ICAO; ChannelIndex = $channelIndex } `
                -AtcSources $AtcSources `
                -Player $Player `
                -ATCVolume $ATCVolume `
                -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
                -NoLofiMusic:$NoLofiMusic `
                -PlayLofiGirlVideo:$PlayLofiGirlVideo `
                -LofiMusicUrl $LofiMusicUrl `
                -LofiVolume $LofiVolume

            return @{
                ok      = $true
                message = "Restarted $($started.ICAO) — $($started.Channel)"
                icao    = $started.ICAO
                channel = $started.Channel
                airport = $started.Airport
                webcam  = $started.Webcam
                lofi    = $started.Lofi
            }
        }

        'random' {
            $randomMatch = $AtcSources | Get-Random
            $icaoMatches = @($AtcSources | Where-Object { $_.ICAO -eq $randomMatch.ICAO })

            $channelIndex = -1
            for ($i = 0; $i -lt $icaoMatches.Count; $i++) {
                if (
                    $icaoMatches[$i].'Channel Description' -eq $randomMatch.'Channel Description' -and
                    $icaoMatches[$i].'Stream URL' -eq $randomMatch.'Stream URL'
                ) {
                    $channelIndex = $i
                    break
                }
            }

            if ($channelIndex -lt 0) {
                throw 'Could not select a random channel.'
            }

            $started = Invoke-MapChannelSelection `
                -Selection @{ ICAO = $randomMatch.ICAO; ChannelIndex = $channelIndex } `
                -AtcSources $AtcSources `
                -Player $Player `
                -ATCVolume $ATCVolume `
                -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
                -NoLofiMusic:$NoLofiMusic `
                -PlayLofiGirlVideo:$PlayLofiGirlVideo `
                -LofiMusicUrl $LofiMusicUrl `
                -LofiVolume $LofiVolume

            return @{
                ok      = $true
                message = "Random channel: $($started.ICAO) — $($started.Channel)"
                icao    = $started.ICAO
                channel = $started.Channel
                airport = $started.Airport
                webcam  = $started.Webcam
                lofi    = $started.Lofi
            }
        }

        default {
            throw "Unsupported map playback action: $Action"
        }
    }
}

# Function to get a list of nearby airports within a specified radius
Function Remove-StaleATCMapFiles {
    param(
        [int]$MaxAgeHours = 24
    )

    $tempDir = [System.IO.Path]::GetTempPath()
    $cutoff = (Get-Date).AddHours(-$MaxAgeHours)

    try {
        Get-ChildItem -Path $tempDir -Filter 'lofiatc_map_*.html' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                }
                catch {
                    Write-Verbose "Could not remove stale temp map file: $($_.FullName)"
                }
            }
    }
    catch {
        Write-Verbose "Failed to scan temp directory for stale map files. $_"
    }
}

# Function to generate and display an interactive ATC map based on the provided sources
# user location, and preferences, and handle the selection of an ATC stream from the map
Function Select-ATCMap {
    param (
        [array]$AtcSources,
        [array]$Favorites,
        [string]$CsvPath,
        [object]$UserLocation,
        [int]$Radius,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoWeather,
        [switch]$Dark,
        [switch]$KeepOpen,
        [string]$Player,
        [int]$ATCVolume,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [string]$LofiMusicUrl,
        [int]$LofiVolume,
        [switch]$StartRandom,
        [string]$FavoritesPath
    )

    Write-Host "Generating interactive tactical map..." -ForegroundColor Cyan
    Remove-StaleATCMapFiles -MaxAgeHours 24

    if (-not $script:AirportData) {
        Get-AirportInfo -ICAO "KLAX" | Out-Null
    }

    $server = Start-ATCMapServer
    $port = $server.Port
    $listener = $server.Listener
    $mapControlToken = New-MapControlToken
    $lazyWeather = -not $NoWeather
    $weatherData = @{
        WeatherMap      = @{}
        IcaoToFallbacks = @{}
    }

    $jsArray = ConvertTo-MapMarkers `
        -AtcSources $AtcSources `
        -Favorites $Favorites `
        -WeatherMap $weatherData.WeatherMap `
        -IcaoToFallbacks $weatherData.IcaoToFallbacks `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
        -NoWeather:($NoWeather -or $lazyWeather) `
        -EnableFavoriteActions:$KeepOpen

    $csvName = Split-Path $CsvPath -Leaf
    $htmlContent = New-ATCMapHtml `
        -JsArray $jsArray `
        -CsvName $csvName `
        -UserLocation $UserLocation `
        -Radius $Radius `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
        -NoWeather:$NoWeather `
        -Dark:$Dark `
        -Port $port `
        -KeepOpen:$KeepOpen `
        -StartRandom:$StartRandom `
        -ATCVolume $ATCVolume `
        -LofiVolume $LofiVolume `
        -MapControlToken $mapControlToken `
        -LazyWeather:$lazyWeather

    $tempMapFile = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_map_{0}.html" -f ([guid]::NewGuid().ToString('N')))

    Set-Content -Path $tempMapFile -Value $htmlContent -Encoding UTF8

    if ($script:OnWindows) {
        Start-Process $tempMapFile
    }
    elseif ($IsMacOS) {
        & open $tempMapFile
    }
    else {
        & xdg-open $tempMapFile
    }

    if ($KeepOpen) {
        Start-PersistentATCMapSession `
            -Listener $listener `
            -AtcSources $AtcSources `
            -Player $Player `
            -ATCVolume $ATCVolume `
            -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
            -NoLofiMusic:$NoLofiMusic `
            -PlayLofiGirlVideo:$PlayLofiGirlVideo `
            -LofiMusicUrl $LofiMusicUrl `
            -LofiVolume $LofiVolume `
            -FavoritesPath $FavoritesPath `
            -Favorites $Favorites `
            -MapControlToken $mapControlToken

        return $null
    }

    return Select-ATCFromMap `
        -Listener $listener `
        -TimeoutSeconds 300 `
        -MapControlToken $mapControlToken `
        -AtcSources $AtcSources `
        -Favorites $Favorites `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable
}

# Resolves the external HTML template used by New-ATCMapHtml.
Function Get-ATCMapHtmlTemplatePath {
    $scriptRoot = if ($PSScriptRoot) {
        $PSScriptRoot
    }
    else {
        (Get-Location).Path
    }

    $templatePath = Join-Path $scriptRoot 'templates\atc-map.html'

    if (-not (Test-Path -Path $templatePath -PathType Leaf)) {
        throw "Map HTML template not found: $templatePath"
    }

    return $templatePath
}

# Converts a string to be safely embedded in JavaScript code by escaping special characters.
Function ConvertTo-JsSafeString {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ($Value -replace '\\', '\\\\' `
                   -replace "'", "\\'" `
                   -replace '"', '\"' `
                   -replace "`r", '' `
                   -replace "`n", ' '
    )
}

# Converts a string to be safely embedded in HTML content by encoding special characters.
Function ConvertTo-HtmlSafeString {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode($Value)
}

# Generates an unguessable token used to bind browser map controls to the current local session.
Function New-MapControlToken {
    $bytes = [byte[]]::new(32)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

Function Test-MapControlToken {
    param(
        [string]$ExpectedToken,
        [string]$ProvidedToken
    )

    return (
        -not [string]::IsNullOrWhiteSpace($ExpectedToken) -and
        -not [string]::IsNullOrWhiteSpace($ProvidedToken) -and
        $ProvidedToken -eq $ExpectedToken
    )
}

# Fetches METAR data for all ICAOs in the provided sources, including fallbacks, and returns a map of ICAO to weather data and a map of ICAOs to their fallback lists.
Function ConvertTo-MapMarkers {
    param(
        [array]$AtcSources,
        [array]$Favorites,
        [hashtable]$WeatherMap,
        [hashtable]$IcaoToFallbacks,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoWeather,
        [switch]$EnableFavoriteActions
    )

    $mapData = @()
    $groupedSources = $AtcSources | Group-Object ICAO
    $defaultFcat = if ($NoWeather) {
        'NONE'
    } 
    else {
        'UNK'
    }

    foreach ($group in $groupedSources) {
        $icaoCode = $group.Name
        $airportInfo = $script:AirportData.$icaoCode

        if (-not $airportInfo -or $null -eq $airportInfo.lat -or $null -eq $airportInfo.lon) {
            continue
        }

        $hasWebcamGlobal = $false
        $channelLinks = @()

        $airportFavoriteChannel = '__AIRPORT__'
        $icaoJs = ConvertTo-JsSafeString $icaoCode

        $isAirportFavorite = @(
            $Favorites | Where-Object {
                $_.ICAO -eq $icaoCode -and $_.Channel -eq $airportFavoriteChannel
            }
        ).Count -gt 0

        $airportFavText = if ($isAirportFavorite) {
            '★ Remove airport favorite'
        }
        else {
            '☆ Add airport favorite'
        }

        $airportFavClass = if ($isAirportFavorite) {
            'airport-favorite-link active'
        }
        else {
            'airport-favorite-link'
        }

        $airportFavState = if ($isAirportFavorite) {
            'true'
        }
        else {
            'false'
        }

        $airportFavoriteLink = if ($EnableFavoriteActions) {
            "<div class=`"airport-favorite-row`"><a href=`"javascript:void(0)`" onclick=`"toggleAirportFavorite('$icaoJs', this)`" class=`"$airportFavClass`" data-favorited=`"$airportFavState`">$airportFavText</a></div>"
        }
        else {
            ""
        }

        for ($i = 0; $i -lt $group.Group.Count; $i++) {
            $ch = $group.Group[$i]

            $camIcon = ""
            if (-not [string]::IsNullOrWhiteSpace($ch.'Webcam URL') -and $IncludeWebcamIfAvailable) {
                $camIcon = " 📷"
                $hasWebcamGlobal = $true
            }

            $descHtml = ConvertTo-HtmlSafeString $ch.'Channel Description'
            $channelName = [string]$ch.'Channel Description'

            $isChannelFavorite = @(
                $Favorites | Where-Object {
                    $_.ICAO -eq $icaoCode -and $_.Channel -eq $channelName
                }
            ).Count -gt 0

            $favText = if ($isChannelFavorite) {
                '★ Remove favorite'
            }
            else {
                '☆ Add favorite'
            }

            $favClass = if ($isChannelFavorite) {
                'favorite-link active'
            }
            else {
                'favorite-link'
            }

            $favState = if ($isChannelFavorite) {
                'true'
            }
            else {
                'false'
            }

            $favoriteLink = if ($EnableFavoriteActions) {
                " <span class=`"channel-separator`">·</span> <a href=`"javascript:void(0)`" onclick=`"toggleFavorite('$icaoJs', $i, this)`" class=`"$favClass`" data-favorited=`"$favState`">$favText</a>"
            }
            else {
                ""
            }

            $channelLinks += "&bull; <a href=`"javascript:void(0)`" onclick=`"playChannel('$icaoJs', $i)`" class=`"channel-link`">$descHtml</a>$camIcon$favoriteLink"

        }

        $favCount = ($Favorites | Where-Object { $_.ICAO -eq $icaoCode } | Measure-Object -Property Count -Sum).Sum
        if ($null -eq $favCount) {
            $favCount = 0
        }

        $wx = $null
        if ($WeatherMap.ContainsKey($icaoCode)) {
            $wx = $WeatherMap[$icaoCode]
        }
        elseif ($IcaoToFallbacks.ContainsKey($icaoCode)) {
            $bestFb = $null
            $minDist = [int]::MaxValue

            foreach ($fb in $IcaoToFallbacks[$icaoCode]) {
                if ($WeatherMap.ContainsKey($fb)) {
                    $fbInfo = $script:AirportData.$fb
                    $dist = 0

                    if ($airportInfo -and $fbInfo) {
                        $dist = Get-DistanceKm -Lat1 $airportInfo.lat -Lon1 $airportInfo.lon -Lat2 $fbInfo.lat -Lon2 $fbInfo.lon
                    }

                    if ($dist -lt $minDist) {
                        $minDist = $dist
                        $bestFb = $fb
                    }
                }
            }

            if ($bestFb) {
                $wxObj = $WeatherMap[$bestFb]
                $wx = @{
                    fcat   = $wxObj.fcat
                    wdir   = $wxObj.wdir
                    wspd   = $wxObj.wspd
                    rawOb  = "[Fallback $bestFb - $($minDist)km] $($wxObj.rawOb)"
                    ageMin = $wxObj.ageMin
                    source = $wxObj.source
                    wxIcao = $bestFb
                }
            }
        }

        if (-not $wx) {
            $wx = @{
                fcat = $defaultFcat
                wdir = 'null'
                wspd = 0
                rawOb = 'Weather Skipped or Unavailable'
                ageMin = $null
                source = 'Unavailable'
                wxIcao = $icaoCode
            }
        }

        $rawDir = $wx.wdir
        $wdir = if ($rawDir -match '^\d+$') {
            [int]$rawDir
        }
        else {
            $null
        }

        $rawSpd = $wx.wspd
        $wspd = if ($rawSpd -match '^\d+$') {
            [int]$rawSpd
        }
        else {
            0
        }

        $mapData += [pscustomobject]@{
            lat      = [double]$airportInfo.lat
            lon      = [double]$airportInfo.lon
            icao     = [string]$icaoCode
            name     = [string]$group.Group[0].'Airport Name'
            city     = [string]$group.Group[0].City
            country  = [string]$group.Group[0].Country
            desc     = [string]($channelLinks -join "<br/>")
            isFav    = [bool]($favCount -gt 0)
            isAirportFav   = [bool]$isAirportFavorite
            airportFavHtml = [string]$airportFavoriteLink
            favCount = [int]$favCount
            hasCam   = [bool]$hasWebcamGlobal
            fcat     = [string]$wx.fcat
            wdir     = $wdir
            wspd     = [int]$wspd
            rawOb    = [string]$wx.rawOb
            wxAgeMin = if ($null -ne $wx.ageMin) { [int]$wx.ageMin } else { $null }
            wxSource = [string]$wx.source
            wxIcao   = [string]$wx.wxIcao
        }
    }

    return ($mapData | ConvertTo-Json -Depth 5 -Compress)
}

# Generates the HTML content for the ATC map, embedding the provided JavaScript array of markers, user location, and other settings, 
# then saves it to a temporary file and opens it in the default web browser. 
# It also listens for channel selection events from the map and returns the selected ICAO and channel description.
Function New-ATCMapHtml {
    param(
        [string]$JsArray,
        [string]$CsvName,
        [object]$UserLocation,
        [int]$Radius,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoWeather,
        [switch]$Dark,
        [int]$Port,
        [switch]$KeepOpen,
        [switch]$StartRandom,
        [int]$ATCVolume,
        [int]$LofiVolume,
        [string]$MapControlToken = '',
        [switch]$LazyWeather
    )

    $userLat = if ($UserLocation) {
        $UserLocation.Latitude
    } 
    else {
        'null'
    }

    $userLon = if ($UserLocation) {
        $UserLocation.Longitude
    }
    else {
        'null'
    }
    $userRad = if ($UserLocation -and $Radius) {
        $Radius * 1000
    }
    else {
        0
    }

    $weatherLegendItems = if (-not $NoWeather) {
@"
        <label class="legend-item" title="Visual Flight Rules: Good visibility (>5 miles) and clear skies (>3,000ft ceiling). Pilots can fly by sight."><input type="checkbox" class="filter-cb" value="vfr" checked> <span class="legend-color color-vfr"></span> VFR (Clear)</label>
        <label class="legend-item" title="Marginal VFR: Fair visibility (3-5 miles) or medium ceiling (1,000-3,000ft)."><input type="checkbox" class="filter-cb" value="mvfr" checked> <span class="legend-color color-mvfr"></span> MVFR</label>
        <label class="legend-item" title="Instrument Flight Rules: Poor visibility (<3 miles) or low ceiling (<1,000ft). Flights must rely on instruments."><input type="checkbox" class="filter-cb" value="ifr" checked> <span class="legend-color color-ifr"></span> IFR/LIFR</label>
        <label class="legend-item" title="Weather data currently unavailable."><input type="checkbox" class="filter-cb" value="unk" checked> <span class="legend-color color-unk"></span> Offline/Unknown</label>
"@
    }
    else {
        '<label class="legend-item" title="Standard active ATC stream."><input type="checkbox" class="filter-cb" value="none" checked> <span class="legend-color color-blue"></span> Active ATC</label>'
    }

    $windToggle = if (-not $NoWeather) {
        '<label class="legend-item" title="Toggle live wind direction arrows."><input type="checkbox" id="toggle-wind" checked> Wind Arrows</label>'
    }
    else {
        ""
    }

    $webcamLegendItem = if ($IncludeWebcamIfAvailable) {
        '<label class="legend-item" title="This ATC feed includes a live webcam link."><input type="checkbox" class="filter-cb" value="cam" checked> <span class="legend-color color-purple"></span> Has Webcam</label>'
    }
    else {
        ""
    }

    $locationLegendItem = if ($UserLocation) {
        '<div class="legend-item" title="Your current device or IP-based location." style="cursor:help; padding-left: 22px;"><span class="legend-color color-green"></span> Your Location</div>'
    }
    else {
        ""
    }

    $darkModeClass = if ($Dark) {
        ' class="dark-mode"'
    }
    else {
        ''
    }

    $darkModeChecked = if ($Dark) {
        'checked'
    } 
    else {
        ''
    
    }
    $isDarkJs = if ($Dark) {
        'true'
    }
    else {
        'false'
    }

    $keepOpenJs = if ($KeepOpen) {
        'true'
    }
    else {
        'false'
    }

    $startRandomJs = if ($KeepOpen -and $StartRandom) {
        'true'
    }
    else {
        'false'
    }

    $lazyWeatherJs = if ($LazyWeather) {
        'true'
    }
    else {
        'false'
    }

    $mapControlTokenJs = ConvertTo-JsSafeString $MapControlToken

    $favoriteLegendItem = '<label class="legend-item" title="Streams you play often."><input type="checkbox" class="filter-cb" value="fav" checked> <span class="legend-color color-fav"></span> Favorites</label>'

    $nearbyControls = if ($UserLocation) {
@"
        <div class="legend-section-title" style="margin-top:10px;">Nearby</div>
        <label class="legend-item" title="Only show airports within the selected radius.">
            <input type="checkbox" id="toggle-nearby-only"> Nearby only
        </label>
        <label class="legend-item" title="Adjust nearby airport radius.">
            Radius: <span id="nearby-radius-label">$Radius km</span>
        </label>
        <input type="range" id="nearby-radius" min="50" max="3000" step="50" value="$Radius">
"@
    }
    else {
        ""
    }

    $playbackControls = if ($KeepOpen) {
@"
        <div class="np-actions">
            <button type="button" id="np-restart" class="np-btn">Restart</button>
            <button type="button" id="np-random" class="np-btn">Random</button>
            <button type="button" id="np-stop-atc" class="np-btn">Stop ATC</button>
            <button type="button" id="np-stop-lofi" class="np-btn">Stop Lofi</button>
            <button type="button" id="np-stop-all" class="np-btn danger">Stop All</button>
        </div>

        <div class="np-volume-panel">
            <label class="np-volume-row" title="Restarts the current ATC stream when released.">
                <span>ATC</span>
                <input type="range" id="np-atc-volume" min="0" max="100" step="1" value="$ATCVolume">
                <span id="np-atc-volume-value" class="np-volume-value">$ATCVolume%</span>
            </label>

            <label class="np-volume-row" title="Restarts the lofi stream when released.">
                <span>Lofi</span>
                <input type="range" id="np-lofi-volume" min="0" max="100" step="1" value="$LofiVolume">
                <span id="np-lofi-volume-value" class="np-volume-value">$LofiVolume%</span>
            </label>
        </div>
"@
    }
    else {
        ""
    }

    $templatePath = Get-ATCMapHtmlTemplatePath
    $template = [System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)

    $templateValues = [ordered]@{
        '{{DARK_MODE_CLASS}}'       = $darkModeClass
        '{{CSV_NAME}}'              = $CsvName
        '{{WEATHER_LEGEND_ITEMS}}'  = $weatherLegendItems
        '{{WEBCAM_LEGEND_ITEM}}'    = $webcamLegendItem
        '{{FAVORITE_LEGEND_ITEM}}'  = $favoriteLegendItem
        '{{LOCATION_LEGEND_ITEM}}'  = $locationLegendItem
        '{{NEARBY_CONTROLS}}'       = $nearbyControls
        '{{WIND_TOGGLE}}'           = $windToggle
        '{{DARK_MODE_CHECKED}}'     = $darkModeChecked
        '{{PLAYBACK_CONTROLS}}'     = $playbackControls
        '{{MARKERS_JSON}}'          = $JsArray
        '{{MAP_CONTROL_TOKEN_JS}}'  = $mapControlTokenJs
        '{{PORT}}'                  = [string]$Port
        '{{KEEP_OPEN_JS}}'          = $keepOpenJs
        '{{IS_DARK_JS}}'            = $isDarkJs
        '{{LAZY_WEATHER_JS}}'       = $lazyWeatherJs
        '{{USER_LAT}}'              = [string]$userLat
        '{{USER_LON}}'              = [string]$userLon
        '{{USER_RADIUS_METERS}}'    = [string]$userRad
        '{{START_RANDOM_JS}}'       = $startRandomJs
    }

    foreach ($placeholder in $templateValues.Keys) {
        $template = $template.Replace($placeholder, $templateValues[$placeholder])
    }

    return $template
}

Function Start-ATCMapServer {
    param(
        [int]$StartPort = 49152,
        [int]$MaxRetries = 10
    )

    $port = $StartPort
    $listener = New-Object System.Net.HttpListener

    while ($MaxRetries -gt 0) {
        try {
            $listener.Prefixes.Clear()
            $listener.Prefixes.Add("http://127.0.0.1:$port/")
            $listener.Start()

            return @{
                Listener = $listener
                Port     = $port
            }
        }
        catch {
            $port++
            $MaxRetries--
        }
    }

    throw "Could not start local web server. Port is blocked."
}


# Listens for incoming HTTP requests from the ATC map, waiting for a user to click on a channel.
# It returns the selected ICAO code and channel description as a hashtable. The function also handles timeout
# and optional cancellation via 'Q' key press when an interactive console is available.
Function Select-ATCFromMap {
    param(
        [System.Net.HttpListener]$Listener,
        [int]$TimeoutSeconds = 300,
        [string]$MapControlToken = '',
        [array]$AtcSources,
        [array]$Favorites,
        [switch]$IncludeWebcamIfAvailable
    )

    $canPollConsole = Test-InteractiveConsoleAvailable

    Write-Host "`nMap opened in your browser! Click a channel on the map to start streaming." -ForegroundColor Green
    if ($canPollConsole) {
        Write-Host "Waiting for selection... (Press 'Q' in this window to cancel and use the terminal)" -ForegroundColor Yellow
    }
    else {
        Write-Host "Waiting for selection... (Console cancellation unavailable in this host/session)" -ForegroundColor Yellow
    }

    $selection = $null
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    try {
        while ((Get-Date) -lt $deadline) {
            $contextTask = $Listener.BeginGetContext($null, $null)

            while (-not $contextTask.IsCompleted) {
                Start-Sleep -Milliseconds 100

                if ((Get-Date) -ge $deadline) {
                    throw "Timed out waiting for a map selection after $TimeoutSeconds seconds."
                }

                if ($canPollConsole -and (Test-ConsoleKeyAvailable)) {
                    $key = Read-ConsoleKey -Intercept
                    if ($key.Key.ToString() -eq 'Q') {
                        throw [System.OperationCanceledException]::new("Map selection cancelled.")
                    }
                }
            }

            try {
                $context = $Listener.EndGetContext($contextTask)
                $req = $context.Request
                $res = $context.Response

                if (
                    -not [string]::IsNullOrWhiteSpace($MapControlToken) -and
                    -not (Test-MapControlToken -ExpectedToken $MapControlToken -ProvidedToken $req.QueryString["token"])
                ) {
                    $res.StatusCode = 403
                    $res.OutputStream.Close()
                    continue
                }

                if ($req.QueryString["action"] -eq 'weather') {
                    $payload = New-MapWeatherPayload `
                        -AtcSources $AtcSources `
                        -Favorites $Favorites `
                        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable
                    $json = $payload | ConvertTo-Json -Depth 8 -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

                    $res.StatusCode = 200
                    $res.ContentType = 'application/json; charset=utf-8'
                    $res.ContentEncoding = [System.Text.Encoding]::UTF8
                    $res.ContentLength64 = $buffer.Length
                    $res.Headers['Cache-Control'] = 'no-store'
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    $res.OutputStream.Close()
                    continue
                }

                if ($null -ne $req.QueryString["icao"]) {
                    $channelIndexRaw = $req.QueryString["channelIndex"]
                    $channelIndex = $null

                    if ($null -ne $channelIndexRaw -and $channelIndexRaw -match '^\d+$') {
                        $channelIndex = [int]$channelIndexRaw
                    }

                    $selection = @{
                        ICAO         = $req.QueryString["icao"]
                        ChannelIndex = $channelIndex
                    }

                    $res.StatusCode = 200
                    $res.OutputStream.Close()

                    Write-Host "`nSelection received from map: $($selection.ICAO)" -ForegroundColor Green
                    return $selection
                }
            }
            catch {}
        }

        throw "Timed out waiting for a map selection after $TimeoutSeconds seconds."
    }
    finally {
        Start-Sleep -Milliseconds 250
        $Listener.Stop()
        $Listener.Close()
    }
}

# Function to start a persistent session that continues to listen for map channel selections 
# until the user cancels (via 'Q' key or closing the window). Each time a selection is made
# it invokes the channel selection logic and updates the currently playing ATC stream accordingly.
Function Start-PersistentATCMapSession {
    param(
        [System.Net.HttpListener]$Listener,
        [array]$AtcSources,
        [string]$Player,
        [int]$ATCVolume,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [string]$LofiMusicUrl,
        [int]$LofiVolume,
        [string]$FavoritesPath,
        [array]$Favorites,
        [string]$MapControlToken
    )

    $canPollConsole = Test-InteractiveConsoleAvailable

    $script:CurrentATCVolume = [int]$ATCVolume
    $script:CurrentLofiVolume = [int]$LofiVolume

    Write-Host "`nMap opened in your browser! Click channels to switch ATC live." -ForegroundColor Green
    if ($canPollConsole) {
        Write-Host "Persistent map mode active. Press 'Q' in this window to quit." -ForegroundColor Yellow
    }
    else {
        Write-Host "Persistent map mode active. Close this PowerShell window to stop." -ForegroundColor Yellow
    }

    try {
        while ($true) {
            $contextTask = $Listener.BeginGetContext($null, $null)

            while (-not $contextTask.IsCompleted) {
                Start-Sleep -Milliseconds 100

                if ($canPollConsole -and (Test-ConsoleKeyAvailable)) {
                    $key = Read-ConsoleKey -Intercept
                    if ($key.Key.ToString() -eq 'Q') {
                        throw [System.OperationCanceledException]::new("Persistent map session cancelled.")
                    }
                }
            }

            try {
                $context = $Listener.EndGetContext($contextTask)
                $req = $context.Request
                $res = $context.Response

                $payload = @{
                    ok      = $true
                    message = "Ready"
                }
                $statusCode = 200

                if (-not (Test-MapControlToken -ExpectedToken $MapControlToken -ProvidedToken $req.QueryString["token"])) {
                    $statusCode = 403
                    $payload = @{
                        ok      = $false
                        message = "Unauthorized map control request."
                    }
                }
                elseif ($req.QueryString["action"] -eq 'weather') {
                    $payload = New-MapWeatherPayload `
                        -AtcSources $AtcSources `
                        -Favorites $Favorites `
                        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable
                }
                elseif ($null -ne $req.QueryString["action"]) {
                    try {
                        $volumeValue = -1

                        if ($null -ne $req.QueryString["volume"] -and $req.QueryString["volume"] -match '^\d+$') {
                            $volumeValue = [int]$req.QueryString["volume"]
                        }

                        $actionChannelIndex = -1

                        if ($null -ne $req.QueryString["channelIndex"] -and $req.QueryString["channelIndex"] -match '^\d+$') {
                            $actionChannelIndex = [int]$req.QueryString["channelIndex"]
                        }

                        $payload = Invoke-MapPlaybackAction `
                            -Action $req.QueryString["action"] `
                            -AtcSources $AtcSources `
                            -Player $Player `
                            -ATCVolume $ATCVolume `
                            -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
                            -NoLofiMusic:$NoLofiMusic `
                            -PlayLofiGirlVideo:$PlayLofiGirlVideo `
                            -LofiMusicUrl $LofiMusicUrl `
                            -LofiVolume $LofiVolume `
                            -Target $req.QueryString["target"] `
                            -Volume $volumeValue `
                            -ICAO $req.QueryString["icao"] `
                            -ChannelIndex $actionChannelIndex `
                            -FavoritesPath $FavoritesPath

                        Write-Host $payload.message -ForegroundColor Green
                    }
                    catch {
                        $payload = @{
                            ok      = $false
                            message = $_.Exception.Message
                        }

                        Write-Warning $_.Exception.Message
                    }
                }
                elseif ($null -ne $req.QueryString["icao"]) {
                    $channelIndexRaw = $req.QueryString["channelIndex"]
                    $channelIndex = $null

                    if ($null -ne $channelIndexRaw -and $channelIndexRaw -match '^\d+$') {
                        $channelIndex = [int]$channelIndexRaw
                    }

                    $selection = @{
                        ICAO         = $req.QueryString["icao"]
                        ChannelIndex = $channelIndex
                    }

                    try {
                        $started = Invoke-MapChannelSelection `
                            -Selection $selection `
                            -AtcSources $AtcSources `
                            -Player $Player `
                            -ATCVolume $ATCVolume `
                            -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
                            -NoLofiMusic:$NoLofiMusic `
                            -PlayLofiGirlVideo:$PlayLofiGirlVideo `
                            -LofiMusicUrl $LofiMusicUrl `
                            -LofiVolume $LofiVolume

                        $payload = @{
                            ok      = $true
                            message = "Now monitoring $($started.ICAO) — $($started.Channel)"
                            icao    = $started.ICAO
                            channel = $started.Channel
                            airport = $started.Airport
                            webcam  = $started.Webcam
                            lofi    = $started.Lofi
                        }

                        Write-Host "Switched to $($started.ICAO) — $($started.Channel)" -ForegroundColor Green
                    }
                    catch {
                        $payload = @{
                            ok      = $false
                            message = $_.Exception.Message
                        }

                        Write-Warning $_.Exception.Message
                    }
                }

                $json = $payload | ConvertTo-Json -Depth 8 -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

                $res.StatusCode = $statusCode
                $res.ContentType = 'application/json; charset=utf-8'
                $res.ContentEncoding = [System.Text.Encoding]::UTF8
                $res.ContentLength64 = $buffer.Length

                $res.Headers['Access-Control-Allow-Origin'] = 'null'
                $res.Headers['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
                $res.Headers['Access-Control-Allow-Headers'] = '*'
                $res.Headers['Cache-Control'] = 'no-store'

                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.OutputStream.Close()
            }
            catch {
                Write-Verbose "Listener request handling error: $_"
            }
        }
    }
    finally {
        Stop-ManagedProcess -Process $script:CurrentATCProcess
        Stop-ManagedProcess -Process $script:CurrentWebcamProcess
        Stop-ManagedProcess -Process $script:CurrentLofiProcess

        try { $Listener.Stop() } catch {}
        try { $Listener.Close() } catch {}
    }
}
