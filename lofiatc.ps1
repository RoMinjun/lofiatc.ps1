<#
.SYNOPSIS
A PowerShell script to stream ATC audio, Lofi music, and optionally webcam video using VLC Media Player.

.DESCRIPTION
This script allows the user to select an ATC stream from a list of sources, optionally play Lofi music, and optionally include webcam video if available.

.PARAMETER IncludeWebcamIfAvailable
Include webcam video stream if available for the selected ATC source.

.PARAMETER NoLofiMusic
Do not play Lofi music.

.PARAMETER RandomATC
Select a random ATC stream from the list of sources. When combined with -ICAO,
choose a random channel for that airport.

.PARAMETER PlayLofiGirlVideo
Play the Lofi Girl video instead of just the audio.

.PARAMETER UseFZF
Use fzf for searching and filtering channels.

.PARAMETER UseBaseCSV
Force the script to load atc_sources.csv even if liveatc_sources.csv exists.

.PARAMETER UseFavorite
Load a previously saved favorite from favorites.json and skip continent/country selection. The file stores how often you play each stream and keeps the top entries.

.PARAMETER Player
Specify the media player to use (VLC, Potplayer, MPC-HC or MPV). Default is VLC if there is no default set in system for mp4.

.PARAMETER ATCVolume
Volume level for the ATC stream. Default is 65.

.PARAMETER LofiVolume
Volume level for the Lofi Girl stream. Default is 50.

.PARAMETER LofiSource
Specify a custom URL or file path for the Lofi audio/video source Defaults to the Lofi Girl Youtube stream if not provided.

.PARAMETER LofiGenre
Specify a Lofi genre preset. Valid options: Chillhop, Synthwave, Jazz, Ambient, DarkAmbient, Bossa, Asian, Medieval. This is overridden by -LofiSource.

.PARAMETER ICAO
Specify an airport by ICAO code. If multiple channels exist you will be prompted to select one unless -RandomATC is used to choose randomly.

.PARAMETER OpenRadar
Open the FlightAware radar page for the selected ICAO after displaying the welcome screen.

.PARAMETER SaveConfig
Save the parameters used for the current run to a configuration file.

.PARAMETER ConfigPath
Optional path for the saved configuration file. Defaults to a file named `config.json` beside the script.

.PARAMETER Nearby
Shows a list of nearby airports to your current device location (IP as fallback) 

.PARAMETER NearbyRadius
If specified, to be used in combination with -Nearby, to change the radius of nearby airports in kilometers

.PARAMETER ShowMap
Generates and opens an interactive HTML map in your browser showing all available ATC sources.
#>

[CmdletBinding()]
param (
    [switch]$IncludeWebcamIfAvailable,
    [switch]$NoLofiMusic,
    [switch]$RandomATC,
    [switch]$PlayLofiGirlVideo,
    [switch]$UseFZF,
    [switch]$UseBaseCSV,
    [switch]$UseFavorite,
    [ValidateSet("VLC", "MPV", "Potplayer", "MPC-HC")]
    [string]$Player,
    [int]$ATCVolume = 65,
    [int]$LofiVolume = 50,
    [string]$LofiSource = "https://youtu.be/jfKfPfyJRdk",
    [ValidateSet("Chillhop","Synthwave","Jazz","Ambient","DarkAmbient","Bossa","Asian","Medieval")]
    [string]$LofiGenre,
    [string]$ICAO,
    [switch]$LoadConfig,
    [switch]$SaveConfig,
    [string]$ConfigPath,
    [switch]$OpenRadar,
    [switch]$Nearby,
    [int]$NearbyRadius = 500,
    [switch]$ShowMap
)

$LofiGenres = @{
    "Chillhop"      = "https://youtu.be/jfKfPfyJRdk" # lofi girl original
    "Synthwave"     = "https://youtu.be/4xDzrJKXOOY" # Synthwave Boy (lofi girl)
    "Jazz"          = "https://youtu.be/HuFYqnbVbzY" # Lofi Girl Jazz
    "Ambient"       = "https://youtu.be/xORCbIptqcc" # Ambient lofi girl
    "Bossa"         = "https://youtu.be/Zq9-4INDsvY" # Bossa lofi girl
    "Asian"         = "https://youtu.be/Na0w3Mz46GA" # Asian lofi girl
    "Medieval"      = "https://youtu.be/IxPANmjPaek" # Medieval lofi girl
    "DarkAmbient"  = "https://youtu.be/S_MOd40zlYU" # Dark Ambient lofi girl
}

# Explicitly set OS variables at the script scope
$script:OnWindows = $env:OS -eq 'Windows_NT'

# Cache for airport database
$script:AirportData = $null

# Mapping of common IANA time zones to Windows IDs for PowerShell 5.1
$script:IanaToWindowsMap = @{
    "Etc/UTC"                        = "UTC"
    "Europe/London"                  = "GMT Standard Time"
    "Europe/Dublin"                  = "GMT Standard Time"
    "Europe/Amsterdam"               = "W. Europe Standard Time"
    "Europe/Paris"                   = "Romance Standard Time"
    "Europe/Berlin"                  = "W. Europe Standard Time"
    "Europe/Madrid"                  = "Romance Standard Time"
    "Europe/Brussels"                = "Romance Standard Time"
    "Europe/Rome"                    = "W. Europe Standard Time"
    "Europe/Vienna"                  = "W. Europe Standard Time"
    "Europe/Prague"                  = "Central Europe Standard Time"
    "Europe/Moscow"                  = "Russian Standard Time"
    "Europe/Athens"                  = "GTB Standard Time"
    "Europe/Bucharest"               = "GTB Standard Time"
    "Africa/Cairo"                   = "Egypt Standard Time"
    "Africa/Johannesburg"            = "South Africa Standard Time"
    "Asia/Jerusalem"                 = "Israel Standard Time"
    "Asia/Dubai"                     = "Arabian Standard Time"
    "Asia/Tehran"                    = "Iran Standard Time"
    "Asia/Riyadh"                    = "Arab Standard Time"
    "Asia/Karachi"                   = "Pakistan Standard Time"
    "Asia/Kolkata"                   = "India Standard Time"
    "Asia/Dhaka"                     = "Bangladesh Standard Time"
    "Asia/Bangkok"                   = "SE Asia Standard Time"
    "Asia/Singapore"                 = "Singapore Standard Time"
    "Asia/Hong_Kong"                 = "China Standard Time"
    "Asia/Shanghai"                  = "China Standard Time"
    "Asia/Taipei"                    = "Taipei Standard Time"
    "Asia/Tokyo"                     = "Tokyo Standard Time"
    "Asia/Seoul"                     = "Korea Standard Time"
    "Australia/Perth"                = "W. Australia Standard Time"
    "Australia/Adelaide"             = "Cen. Australia Standard Time"
    "Australia/Sydney"               = "AUS Eastern Standard Time"
    "Pacific/Auckland"               = "New Zealand Standard Time"
    "America/Halifax"                = "Atlantic Standard Time"
    "America/St_Johns"               = "Newfoundland Standard Time"
    "America/Argentina/Buenos_Aires" = "Argentina Standard Time"
    "America/Sao_Paulo"              = "E. South America Standard Time"
    "America/New_York"               = "Eastern Standard Time"
    "America/Chicago"                = "Central Standard Time"
    "America/Denver"                 = "Mountain Standard Time"
    "America/Phoenix"                = "US Mountain Standard Time"
    "America/Los_Angeles"            = "Pacific Standard Time"
    "America/Anchorage"              = "Alaskan Standard Time"
    "Pacific/Honolulu"               = "Hawaiian Standard Time"
}

# Function to check the default application for .mp4
Function Get-DefaultAppForMP4 {
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice"
        if (Test-Path $keyPath) {
            $key = Get-ItemProperty -Path $keyPath -ErrorAction Stop
            $progID = $key.ProgID
        }
        else {
            $keyPath = "HKCR:\.mp4"
            if (Test-Path $keyPath) {
                $progID = (Get-ItemProperty -Path $keyPath -ErrorAction Stop).'(default)'
            }
            else { return $null }
        }

        if ($progID -like "Applications\*") { return $progID -replace "Applications\\", "" }
        else { return $progID }
    }
    catch { return $null }
}

# Main function to get user's location
Function Get-CurrentCoordinates {
    Write-Verbose "Attempting to load System.Device assembly..."
    $location = $null
    $AssemblyLoaded = $false
    
    try {
        Add-Type -AssemblyName System.Device -ErrorAction Stop
        $AssemblyLoaded = $true
        Write-Verbose "Successfully loaded System.Device assembly."
    }
    catch {
        Write-Verbose "Could not load System.Device assembly (this is normal on PowerShell Core or non-Windows OS)."
    }

    if ($AssemblyLoaded) {
        Write-Verbose "Attempting to get device location..."
        try {
            $GeoWatcher = New-Object System.Device.Location.GeoCoordinateWatcher
            $GeoWatcher.Start()
            
            Write-Verbose "Waiting 1 second for device watcher to initialize..."
            Start-Sleep -Seconds 1
            
            $startTime = Get-Date
            $timeoutSeconds = 10 

            while ($GeoWatcher.Status -eq 'Initializing') {
                if ($GeoWatcher.Permission -eq 'Denied') { break }
                if (((Get-Date) - $startTime).TotalSeconds -ge $timeoutSeconds) { break }
                Start-Sleep -Milliseconds 100
            }

            if ($GeoWatcher.Permission -eq 'Denied') {
                Write-Warning 'Access Denied for device location.'
            } 
            elseif ($GeoWatcher.Status -eq 'Ready') {
                Write-Verbose "Device location acquired."
                $loc = $GeoWatcher.Position.Location
                
                $location = [pscustomobject]@{
                    Latitude  = $loc.Latitude
                    Longitude = $loc.Longitude
                    Source    = 'Device'
                }
            }
            elseif ($GeoWatcher.Status -eq 'Initializing') {
                 Write-Warning "Device location timed out after $($timeoutSeconds + 1) seconds."
                 $GeoWatcher.Stop()
            }
            else {
                 Write-Warning "Device location service failed. Status: $($GeoWatcher.Status)."
            }
        }
        catch { Write-Warning "An unexpected error occurred with the device location service. Error: $_" }
    }

    if (-not $location) {
        Write-Warning "Falling back to IP-based location."
        $location = Get-IPLocation 
    }
    
    return $location
}

# Helper function for IP-based fallback
Function Get-IPLocation {
    try {
        $uri = "http://ip-api.com/json/?fields=status,message,lat,lon,city,country"
        Write-Verbose "Attempting IP-based geolocation fallback..."
        $location = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 5
        
        if ($location.status -eq 'success' -and $location.lat -and $location.lon) {
            Write-Host "Using approximate location based on IP: $($location.city), $($location.country)." -ForegroundColor Yellow
            return [pscustomobject]@{
                Latitude  = $location.lat
                Longitude = $location.lon
                City      = $location.city
                Country   = $location.country
                Source    = 'IP' 
            }
        } else {
            Write-Verbose "IP-based geolocation failed: $($location.message)"
            return $null
        }
    }
    catch {
        Write-Error "Failed to get location from IP API. $_"
        return $null
    }
}

# Function to determine the appropriate player
Function Resolve-Player {
    param ([string]$explicitPlayer)

    if ($explicitPlayer) { return $explicitPlayer }

    if ($script:OnWindows) {
        $defaultApp = Get-DefaultAppForMP4
        switch ($defaultApp) {
            "vlc.exe" { return "VLC" }
            "mpv.exe" { return "MPV" }
            "PotPlayerMini64.exe" { return "Potplayer" }
            "mpc-hc64.exe" { return "MPC-HC" }
            default { return "VLC" }
        }
    }
    else {
        if (Get-Command mpv -ErrorAction SilentlyContinue) { return "MPV" }
        if (Get-Command vlc -ErrorAction SilentlyContinue) { return "VLC" }
        return "MPV"
    }
}

# Function to resolve links correctly
Function Resolve-StreamUrl {
    param([string]$url)

    $resolvedUrl = $url

    if ($url -match 'youtu(be)?\.com|youtu\.be') {
        try {
            if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
                $resolved = yt-dlp -g --no-warnings --skip-download -- $url 2>$null
            }
            elseif (Get-Command youtube-dl -ErrorAction SilentlyContinue) {
                $resolved = youtube-dl -g --no-warnings --skip-download -- $url 2>$null
            }
            if ($resolved) { $resolvedUrl = ($resolved -join '') }
        }
        catch { Write-Warning "Failed to resolve YouTube URL with yt-dlp/youtube-dl. Falling back to original URL." }
    }
    elseif ($url -match '\.pls(\?|$)') {
        try {
            if ($url -match ".*/(?<feed>[^\.]+)\.pls") {
                $feedName = $matches['feed']
                $resolvedUrl = "http://d.liveatc.net/$feedName"
            } else { Write-Warning "Could not parse feed name from the provided PLS URL. Falling back to original" }
        }
        catch { Write-Warning "Failed to resolve PLS URL. Falling back to original URL." }
    }
    elseif (($script:IsLinux -or $IsLinux) -and $url -match 'liveatc\.net') {
        try {
            $m3u = curl -sL -- $url
            $streamLine = $m3u -split "`n" | Where-Object { $_ -and ($_ -notmatch '^#') } | Select-Object -First 1
            if ($streamLine) { $resolvedUrl = $streamLine }
        }
        catch { Write-Warning "Failed to resolve LiveATC M3U. Falling back to original URL." }
    }

    return $resolvedUrl
}


# Function to check if the selected player is available
Function Test-Player {
    param ([string]$player)

    $command = switch ($player) {
        "VLC" { if ($script:OnWindows) { "vlc.exe" } else { "vlc" } }
        "MPV" { if ($script:OnWindows) { "mpv.com" } else { "mpv" } }
        "Potplayer" { "PotPlayerMini64.exe" }
        "MPC-HC" { "mpc-hc64.exe" }
    }

    $fullPath = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    if (-Not $fullPath) {
        Write-Error "$player is not installed or not available in PATH. Please install $player to proceed."
        exit
    }

    return $fullPath
}

Function Import-ATCSource {
    param ([string]$csvPath)
    if (-Not (Test-Path $csvPath)) {
        Write-Error "The ATC sources CSV file ($csvPath) was not found. Please create it before running the script."
        exit
    }
    return Import-Csv -Path $csvPath
}

Function Get-Favorite {
    param([string]$path)

    if (Test-Path $path) {
        try {
            $data = Get-Content -Path $path -Raw | ConvertFrom-Json
            foreach ($f in $data) {
                if (-not $f.PSObject.Properties['Count']) { $f | Add-Member -Name Count -Value 1 -MemberType NoteProperty }
                if (-not $f.PSObject.Properties['LastUsed']) { $f | Add-Member -Name LastUsed -Value (Get-Date) -MemberType NoteProperty }
            }
            return $data
        } catch { return @() }
    } else { return @() }
}

Function Save-Favorite {
    param([array]$favorites, [string]$path)
    $favorites | ConvertTo-Json | Set-Content -Path $path
}

Function Add-Favorite {
    param(
        [string]$path,
        [string]$ICAO,
        [string]$Channel,
        [int]$maxEntries = 10
    )

    $favorites = Get-Favorite -path $path
    $existing = $favorites | Where-Object { $_.ICAO -eq $ICAO -and $_.Channel -eq $Channel }
    if ($existing) {
        $existing.Count++
        $existing.LastUsed = Get-Date
        $favorites = $favorites | Where-Object { !(($_.ICAO -eq $ICAO) -and ($_.Channel -eq $Channel)) }
        $favorites = , $existing + $favorites
    } else {
        $newEntry = [pscustomobject]@{
            ICAO     = $ICAO
            Channel  = $Channel
            Count    = 1
            LastUsed = Get-Date
        }
        $favorites = , $newEntry + $favorites
    }
    $favorites = $favorites | Sort-Object -Property @{Expression = 'Count'; Descending = $true }, @{Expression = 'LastUsed'; Descending = $true }
    if ($favorites.Count -gt $maxEntries) { $favorites = $favorites[0..($maxEntries - 1)] }
    Save-Favorite -favorites $favorites -path $path
}

Function Open-Radar {
    param([string]$ICAO)

    $url = "https://beta.flightaware.com/live/airport/$ICAO"
    if ($script:OnWindows) { Start-Process $url }
    elseif ($IsMacOS) { & open $url }
    else { & xdg-open $url }
}

Function Select-FavoriteATC {
    param([array]$favorites, [array]$atcSources, [switch]$UseFZF)

    $favEntries = foreach ($fav in $favorites) {
        $entry = $atcSources | Where-Object { $_.ICAO -eq $fav.ICAO -and $_.'Channel Description' -eq $fav.Channel } | Select-Object -First 1
        if ($entry) {
            [pscustomobject]@{
                Display = "[{0}] {1} - {2} ({3})" -f $entry.ICAO, $entry.'Airport Name', $entry.'Channel Description', $fav.Count
                Entry   = $entry
            }
        }
    }

    if (-not $favEntries -or $favEntries.Count -eq 0) { return $null }
    $labels = $favEntries.Display
    $sel = if ($UseFZF) { Select-ItemFZF -prompt 'Select a favorite' -items $labels } else { Select-Item -prompt 'Select a favorite:' -items $labels }
    if ($sel) {
        $fav = $favEntries | Where-Object { $_.Display -eq $sel }
        return @{
            StreamUrl   = $fav.Entry.'Stream URL'
            WebcamUrl   = $fav.Entry.'Webcam URL'
            AirportInfo = $fav.Entry
        }
    } else { return $null }
}

Function Select-Item {
    param ([string]$prompt, [array]$items, [switch]$AllowBack)

    while ($true) {
        Clear-Host
        Write-Host $prompt -ForegroundColor Yellow
        $i = 1
        foreach ($item in $items) { Write-Host "$i. $item"; $i++ }
        if ($AllowBack) { Write-Host "0. Go Back" }

        $userChoice = Read-Host "Enter the number of your choice"
        if ($AllowBack -and $userChoice -eq '0') { return $null }

        if ($userChoice -match '^\d+$') {
            $index = [int]$userChoice - 1
            if ($index -ge 0 -and $index -lt $items.Count) { return $items[$index].Trim() }
        }

        Write-Error "Error: Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}

Function Select-ItemFZF {
    param ([string]$prompt, [array]$items)
    $selectedItem = $items | fzf --prompt "$prompt> " --exact
    if ($selectedItem) { return $selectedItem.Trim() }
    else { Write-Host "No selection made. Exiting script." -ForegroundColor Yellow; exit }
}

Function Select-ATCStream {
    param ([array]$atcSources, [string]$continent, [string]$country, [string]$state)

    while ($true) {
        Clear-Host
        $choices = $atcSources | Where-Object {
            $_.Continent.Trim().ToLower() -eq $continent.Trim().ToLower() -and
            $_.Country.Trim().ToLower() -eq $country.Trim().ToLower() -and
            (
                -not $state -or (
                    -not [string]::IsNullOrWhiteSpace($_.'State/Province') -and
                    $_.'State/Province'.Trim().ToLower() -eq $state.Trim().ToLower()
                )
            )
        }

        if ($choices.Count -eq 0) { Write-Error "No ATC streams available for the selected country."; return $null }

        $airports = $choices | Group-Object -Property City, 'Airport Name' | ForEach-Object {
            $city = $_.Group[0].City
            $airportName = $_.Group[0].'Airport Name'
            $hasWebcam = $_.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.'Webcam URL') } | Measure-Object
            $webcamIndicator = if ($hasWebcam.Count -gt 0) { "[Webcam available]" } else { "" }
            "[{0}] {1} {2}" -f $city, $airportName, $webcamIndicator
        } | Sort-Object

        $airportSel = Select-Item -prompt "Select an airport from ${country}:" -items $airports -AllowBack
        if ($null -eq $airportSel) { return $null }

        $airportChoices = $choices | Where-Object {
            "[{0}] {1}" -f $_.City, $_.'Airport Name' -eq ($airportSel -replace '\s\[Webcam available\]', '')
        }

        while ($true) {
            if ($airportChoices.Count -gt 1) {
                $airportNameForPrompt = ($airportSel -replace '\s\[Webcam available\]', '')
                $channels = $airportChoices | ForEach-Object {
                    $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
                    "{0}{1}" -f $_.'Channel Description', $webcamIndicator
                } | Sort-Object -Unique
                $chanSel = Select-Item -prompt "Select a channel for ${airportNameForPrompt}:" -items $channels -AllowBack
                if ($null -eq $chanSel) { break }
                $chanClean = $chanSel -replace '\s\[Webcam available\]', ''
                $selected = $airportChoices | Where-Object { $_.'Channel Description' -eq $chanClean }
            } else { $selected = $airportChoices[0] }

            if ($selected) {
                return @{
                    StreamUrl   = $selected.'Stream URL'
                    WebcamUrl   = $selected.'Webcam URL'
                    AirportInfo = $selected
                }
            }
        }
    }
}

Function Select-ATCStreamFZF {
    param ([array]$atcSources)

    Clear-Host
    $choices = $atcSources | ForEach-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
        $state = $_.'State/Province'
        $location = if (-not [string]::IsNullOrWhiteSpace($state)) { "{0}, {1}, {2}" -f $_.City, $state, $_.'Country' }
                    else { "{0}, {1}" -f $_.City, $_.'Country' }
        "[{0}] {1} ({2}/{3}) | {4}{5}" -f $location, $_.'Airport Name', $_.'ICAO', $_.'IATA', $_.'Channel Description', $webcamInfo
    }

    $selectedChoice = Select-ItemFZF -prompt "Select an ATC stream" -items $choices

    $selectedStream = $atcSources | Where-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
        $state = $_.'State/Province'
        $location = if (-not [string]::IsNullOrWhiteSpace($state)) { "{0}, {1}, {2}" -f $_.City, $state, $_.'Country' }
                    else { "{0}, {1}" -f $_.City, $_.'Country' }
        $formattedEntry = "[{0}] {1} ({2}/{3}) | {4}{5}" -f $location, $_.'Airport Name', $_.'ICAO', $_.'IATA', $_.'Channel Description', $webcamInfo
        $formattedEntry -eq $selectedChoice
    }

    if ($selectedStream) {
        return @{
            StreamUrl   = $selectedStream.'Stream URL'
            WebcamUrl   = $selectedStream.'Webcam URL'
            AirportInfo = $selectedStream
        }
    } else { Write-Error "No matching ATC stream found."; exit }
}

Function Get-RandomATCStream {
    param ([array]$atcSources)
    $randomIndex = Get-Random -Minimum 0 -Maximum $atcSources.Count
    $selectedStream = $atcSources[$randomIndex]
    return @{
        StreamUrl   = $selectedStream.'Stream URL'
        WebcamUrl   = $selectedStream.'Webcam URL'
        AirportInfo = $selectedStream
    }
}

Function Get-DistanceKm {
    param ([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2)
    $rad = [math]::PI / 180
    $dLat = ($Lat2 - $Lat1) * $rad
    $dLon = ($Lon2 - $Lon1) * $rad
    $a = [math]::Pow([math]::Sin($dLat / 2), 2) + [math]::Cos($Lat1 * $rad) * [math]::Cos($Lat2 * $rad) * [math]::Pow([math]::Sin($dLon / 2), 2)
    $c = 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))
    return [math]::Round(6371 * $c)
}

Function ConvertTo-NauticalMiles {
    param([double]$Kilometers, [int]$Decimals = 0)
    if ($null -eq $Kilometers) { return $null }
    $nm = $Kilometers / 1.852
    return [math]::Round($nm, $Decimals)
}

Function Get-METAR-TAF {
    param ([string]$ICAO, [string[]]$FallbackICAOs)

    $icaoList = @($ICAO)
    if ($FallbackICAOs) { $icaoList += $FallbackICAOs }

    $raw = $null; $used = $ICAO; $source = $null; $sourceUrl = $null

    foreach ($code in $icaoList) {
        $url = "https://aviationweather.gov/api/data/metar?ids=$code"
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
            $raw = $response.Content.Trim()
            if ($raw -match "\b$code\b" -and $raw -match '\b\d{6}Z\b') {
                $used = $code; $source = 'NOAA'; $sourceUrl = 'https://aviationweather.gov'
                break
            } else { Write-Verbose ("NOAA METAR invalid for {0}: {1}" -f $code, $raw) }
        } catch { Write-Verbose ("NOAA METAR fetch failed for {0}: {1}" -f $code, $_) }

        try {
            $vatsimUrl = "https://metar.vatsim.net/metar.php?id=$code"
            $response = Invoke-WebRequest -Uri $vatsimUrl -UseBasicParsing -Verbose:$false
            $raw = $response.Content.Trim()
            if ($raw -match "\b$code\b" -and $raw -match '\b\d{6}Z\b') {
                $used = $code; $source = 'VATSIM'; $sourceUrl = 'https://metar.vatsim.net'
                break
            } else { Write-Verbose ("VATSIM METAR invalid for {0}: {1}" -f $code, $raw) }
        } catch { Write-Verbose ("VATSIM METAR fetch failed for {0}: {1}" -f $code, $_) }
    }
    
    if (-not $raw) {
        Write-Error "Failed to fetch METAR/TAF data for $ICAO and fallbacks."
        return [pscustomobject]@{ Report = "METAR/TAF data unavailable."; ICAO = $ICAO; DistanceKm = $null; Source = $null; SourceUrl = $null }
    }

    $distance = if ($used -ne $ICAO) {
        $orig = Get-AirportInfo -ICAO $ICAO
        $alt = Get-AirportInfo -ICAO $used
        if ($orig -and $alt) { Get-DistanceKm -Lat1 $orig.lat -Lon1 $orig.lon -Lat2 $alt.lat -Lon2 $alt.lon } else { $null }
    } else { 0 }

    $distanceNm = if ($null -ne $distance) { ConvertTo-NauticalMiles -Kilometers $distance -Decimals 0 } else { $null }

    return [pscustomobject]@{ Report = $raw; ICAO = $used; DistanceKm = $distance; DistanceNm = $distanceNm; Source = $source; SourceUrl = $sourceUrl }
}

Function ConvertFrom-METAR {
    param ([string]$metar)
    $decoded = @{}

    if ($metar -match "(?<windDir>\d{3})(?<windSpeed>\d{2})(G(?<gustSpeed>\d{2}))?KT") {
        $decoded["Wind"] = if ($matches.gustSpeed) { "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots, gusting to $([int]$matches.gustSpeed) knots" }
        else { "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots" }
    }

    if ($metar -match "(?<visibility>9999)") { $decoded["Visibility"] = "10+ km (Unlimited)" }
    elseif ($metar -match "\b(?<visibility>\d{4})\b") { $decoded["Visibility"] = "$([int]$matches.visibility / 1000) km" }
    elseif ($metar -match "(?<visibility>\d+SM)") { $decoded["Visibility"] = "$([math]::Round([double]($matches.visibility -replace 'SM','') * 1.60934, 3)) km" }
    else { $decoded["Visibility"] = "Unavailable" }

    if ($metar -match "VV(?<vv>\d{3})") { $decoded["Ceiling"] = "Vertical Visibility at $([int]$matches.vv * 100) ft" }
    elseif ($metar -match "(?<clouds>BKN|OVC|SCT|FEW)(?<ceiling>\d{3})") {
        $cloudType = switch ($matches.clouds) {
            "BKN" { "Broken" } "OVC" { "Overcast" } "SCT" { "Scattered" } "FEW" { "Few" } default { $matches.clouds }
        }
        $decoded["Ceiling"] = "$cloudType at $([int]$matches.ceiling * 100) ft"
    } else { $decoded["Ceiling"] = "Unavailable" }

    if ($metar -match "(?<temp>-?\d{1,2})/(?<dew>-?\d{1,2}|M\d{1,2})") {
        $temperature = if ($matches.temp -eq "-00") { "0$([char]176)C" } else { "$([int]$matches.temp)$([char]176)C" }
        $dewPoint = if ($matches.dew -eq "-00") { "0$([char]176)C" } elseif ($matches.dew -like "M*") { "-$([int]($matches.dew.Trim('M')))$([char]176)C" } else { "$([int]$matches.dew)$([char]176)C" }
        $decoded["Temperature"] = $temperature
        $decoded["DewPoint"] = $dewPoint
    } else {
        $decoded["Temperature"] = "Unavailable"; $decoded["DewPoint"] = "Unavailable"
    }

    if ($metar -match "Q(?<pressureHPA>\d{4})") { $decoded["Pressure"] = "$([int]$matches.pressureHPA) hPa" }
    elseif ($metar -match "A(?<pressureINHG>\d{4})") {
        $pressureHPA = [double]($matches.pressureINHG / 100) * 33.8639
        $decoded["Pressure"] = "$([math]::Round($pressureHPA, 1)) hPa"
    } else { $decoded["Pressure"] = "Unavailable" }

    return [PSCustomObject]$decoded
}

Function ConvertTo-TimeZoneInfo {
    param([string]$IanaId)
    try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($IanaId) }
    catch {
        if ($script:IanaToWindowsMap.ContainsKey($IanaId)) { return [System.TimeZoneInfo]::FindSystemTimeZoneById($script:IanaToWindowsMap[$IanaId]) }
        else { throw "Timezone ID '$IanaId' not recognized" }
    }
}

Function Get-AirportInfo {
    param([string]$ICAO)
    if (-not $script:AirportData) {
        try { $script:AirportData = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/rominjun/Airports/master/airports.json' -Method Get }
        catch { Write-Error "Failed to load airport database. Exception: $_"; return $null }
    }
    $info = $script:AirportData.$ICAO
    if (-not $info) { Write-Error "Airport info not found for $ICAO." }
    return $info
}

Function Get-AirportDateTime {
    param ([string]$ICAO)
    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        if (-not $airportInfo -or -not $airportInfo.tz) { throw "Timezone not found" }
        $tzInfo = ConvertTo-TimeZoneInfo -IanaId $airportInfo.tz
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tzInfo)
        return "$($local.ToString('dd MMMM yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)) LT"
    } catch { Write-Error "Date and time not found for $ICAO. Exception: $_"; return "Date/time data unavailable" }
}

Function Get-AirportSunriseSunset {
    param ([string]$ICAO)
    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        $lat = $airportInfo.lat; $lon = $airportInfo.lon; $tz = $airportInfo.tz
        if (-not ($lat -and $lon -and $tz)) { throw "Missing data" }
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
    } catch { Write-Error "Failed to fetch data for $ICAO. Exception: $_"; return @{ Sunrise = "Data unavailable"; Sunset = "Data unavailable" } }
}

Function Get-METAR-LastUpdatedTime {
    param ([string]$ICAO, [string[]]$FallbackICAOs)
    try {
        $metarInfo = Get-METAR-TAF -ICAO $ICAO -FallbackICAOs $FallbackICAOs
        if ($metarInfo.Report -match '\b(?<ts>\d{6})Z\b') {
            $ts = $matches.ts
            $day = [int]$ts.Substring(0, 2); $hour = [int]$ts.Substring(2, 2); $min = [int]$ts.Substring(4, 2)
            $now = (Get-Date).ToUniversalTime()
            $year = $now.Year; $month = $now.Month
            if ($day -gt $now.Day) { $prev = $now.AddMonths(-1); $year = $prev.Year; $month = $prev.Month }
            $obs = New-Object DateTime($year, $month, $day, $hour, $min, 0, [System.DateTimeKind]::Utc)
            $diff = $now - $obs
            if ($diff.TotalHours -ge 1) { return "{0:N0} hours" -f [math]::Floor($diff.TotalHours) }
            else { return "{0:N0} minutes" -f [math]::Floor($diff.TotalMinutes) }
        } else { throw 'Time code not found' }
    } catch { Write-Error "Failed to fetch the last updated time for $ICAO. Exception: $_"; return "Last updated time unavailable." }
}

Function Write-Welcome {
    param ([object]$airportInfo, [switch]$OpenRadar)

    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [Console]::OutputEncoding = $utf8; $OutputEncoding = $utf8
    } catch { Write-Verbose "[$($MyInvocation.MyCommand.Name)] $($_.Exception.Message)"; return }

    function Get-Emoji { param([int]$CodePoint, [switch]$VS16) $s = [System.Char]::ConvertFromUtf32($CodePoint); if ($VS16) { $s += [char]0xFE0F }; return $s }
    
    $airplane = Get-Emoji 0x2708 -VS16; $location = Get-Emoji 0x1F4CD; $earth = Get-Emoji 0x1F30D; $departure = Get-Emoji 0x1F6EB; $clock = Get-Emoji 0x23F0
    $weather = Get-Emoji 0x1F326 -VS16; $wind = Get-Emoji 0x1F32C -VS16; $eye = Get-Emoji 0x1F441 -VS16; $cloud = Get-Emoji 0x2601 -VS16; $thermometer = Get-Emoji 0x1F321 -VS16
    $droplet = Get-Emoji 0x1F4A7; $barometer = Get-Emoji 0x1F4CF; $note = Get-Emoji 0x1F4DD; $sunrise = Get-Emoji 0x1F305; $sunset = Get-Emoji 0x1F304
    $antenna = Get-Emoji 0x1F4E1; $mic = Get-Emoji 0x1F5E3 -VS16; $headphones = Get-Emoji 0x1F3A7; $camera = Get-Emoji 0x1F3A5; $link = Get-Emoji 0x1F517
    $hourglass = Get-Emoji 0x23F3; $radar = Get-Emoji 0x1F4E1

    $fallbacks = if ($airportInfo.NearbyICAOs) { $airportInfo.NearbyICAOs -split ';' } else { @() }
    $metarInfo = Get-METAR-TAF -ICAO $airportInfo.ICAO -FallbackICAOs $Fallbacks
    $decodedMetar = ConvertFrom-METAR -metar $metarInfo.Report
    $airportDateTime = Get-AirportDateTime -ICAO $airportInfo.ICAO
    $sunTimes = Get-AirportSunriseSunset -ICAO $airportInfo.ICAO
    $lastUpdatedTime = Get-METAR-LastUpdatedTime -ICAO $airportInfo.ICAO -FallbackICAOs $fallbacks

    Write-Output "$airplane Welcome to $($airportInfo.'Airport Name')"
    Write-Output "    $location City:        $($airportInfo.City)"
    Write-Output "    $earth Country:     $($airportInfo.Country)"
    Write-Output "    $departure ICAO/IATA:   $($airportInfo.ICAO)/$($airportInfo.IATA)`n"
    Write-Output "$clock Current Date/Time:`n    $airportDateTime`n"
    Write-Output "$weather Weather Information:"
    Write-Output "    $wind Wind:        $($decodedMetar.Wind)"
    Write-Output "    $eye Visibility:  $($decodedMetar.Visibility)"
    Write-Output "    $cloud Ceiling:     $($decodedMetar.Ceiling)"
    Write-Output "    $thermometer Temperature: $($decodedMetar.Temperature)"
    Write-Output "    $droplet Dew Point:   $($decodedMetar.DewPoint)"
    Write-Output "    $barometer Pressure:    $($decodedMetar.Pressure)"
    Write-Output "    $note Raw METAR:   $($metarInfo.Report)`n"

    if ($sunTimes) {
        Write-Output "$sunrise Sunrise/Sunset Times:"
        Write-Output "    $sunrise Sunrise: $($sunTimes.Sunrise)"
        Write-Output "    $sunset Sunset:  $($sunTimes.Sunset)`n"
    }

    Write-Output "$antenna Air Traffic Control:"
    Write-Output "    $mic Channel: $($airportInfo.'Channel Description')"
    Write-Output "    $headphones Stream:  $($airportInfo.'Stream URL')`n"

    if ($OpenRadar -or -not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
        Write-Output "$link External Links:"
        if ($OpenRadar) { Write-Output "    $radar Radar:  https://beta.flightaware.com/live/airport/$($airportInfo.ICAO)" }
        if (-not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) { Write-Output "    $camera Webcam: $($airportInfo.'Webcam URL')" }
        Write-Output ""
    }

    $sourceName = if ($metarInfo.Source) { $metarInfo.Source } else { 'Unknown source' }
    $sourceUrl = if ($metarInfo.SourceUrl) { " ($($metarInfo.SourceUrl))" } else { '' }
    Write-Output "$link Data Source: METAR data retrieved from $sourceName$sourceUrl"
    
    if ($metarInfo.ICAO -ne $airportInfo.ICAO -and $metarInfo.DistanceKm) {
        $distNmText = if ($metarInfo.DistanceNm) { "/$($metarInfo.DistanceNm)nm" } else { "" }
        Write-Output "    $radar Using fallback METAR from $($metarInfo.ICAO) ($($metarInfo.DistanceKm)km$distNmText away)"
    }
    Write-Output "    $hourglass Last Updated: $lastUpdatedTime ago`n"
}

Function Get-VLCVolumeArg {
    param ([int]$volume, [switch]$NoAudio)
    if ($script:OnWindows) {
        $vlcConfigPath = Join-Path $env:APPDATA "vlc\vlcrc"; $module = $null
        if (Test-Path $vlcConfigPath) {
            try {
                $line = Get-Content -Path $vlcConfigPath | Where-Object { $_ -match '^\s*aout\s*=' -and $_ -notmatch '^\s*#' } | Select-Object -First 1
                if ($line) { $module = ($line -split "=")[1].Trim().ToLower() }
            } catch { Write-Error ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message); return }
        }
        $v = [math]::Round([double]$volume / 100, 2)
        switch -Regex ($module) {
            'mmdevice|wasapi' { return "--aout=wasapi --mmdevice-volume=$v" }
            'waveout' { return "--aout=waveout --waveout-volume=$v" }
            default { return "--aout=directx --directx-volume=$v" }
        }
    } else {
        $pct = [math]::Max(0, [math]::Min(100, $volume))
        $vlcVol = if ($NoAudio) { 0 } else { [int][math]::Round($pct * 2.56) }
        return [PSCustomObject]@{ Mode = 'RCStdin'; Prepend = ' --intf qt --extraintf rc --rc-fake-tty --verbose=-1 --quiet'; Value = $vlcVol }
    }
}

Function Start-Player {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param ([string]$url, [string]$player, [switch]$noVideo, [switch]$noAudio, [switch]$basicArgs, [int]$volume = 100)

    $url = Resolve-StreamUrl $url
    if (-not $PSCmdlet.ShouldProcess("$player -> $url", 'Start media player')) { return }

    $playerArgs = switch ($player) {
        "VLC" {
            $vlcArgs = "`"$url`""; if ($noVideo) { $vlcArgs += " --no-video" }
            if ($script:OnWindows) {
                $vol = if ($noAudio) { 0 } else { $volume }
                $vlcArgs += " $(Get-VLCVolumeArg -volume $vol -NoAudio:$noAudio) --no-volume-save --quiet"
                $vlcArgs
            } else {
                if ($noAudio) { $vlcArgs += " --no-audio" }
                $vlcArgs += " --quiet"; $volSetting = Get-VLCVolumeArg -volume $volume -NoAudio:$noAudio
                $playerPath = Test-Player -player "VLC"
                $psi = New-Object Diagnostics.ProcessStartInfo
                $psi.FileName = $playerPath; $psi.Arguments = "$($volSetting.Prepend) $vlcArgs"
                $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
                $proc = [Diagnostics.Process]::Start($psi)
                $proc.StandardInput.WriteLine("volume $($volSetting.Value)")
                return
            }
        }   
        "MPV" {
            $mpvArgs = "`"$url`""; if ($noVideo) { $mpvArgs += " --no-video" }; if ($noAudio) { $mpvArgs += " --no-audio" }
            if ($basicArgs) { $mpvArgs += " --force-window=immediate --cache=yes --cache-pause=no --terminal=no" }
            $mpvArgs += " --volume=$volume"; $mpvArgs
        }
        "Potplayer" {
            $potplayerArgs = "`"$url`""; if ($noAudio) { $potplayerArgs += " /volume=0" }
            if ($basicArgs) { $potplayerArgs += " /new" }; $potplayerArgs += " /volume=$volume"; $potplayerArgs
        }
        "MPC-HC" {
            $mpchcArgs = "`"$url`""; if ($noAudio) { $mpchcArgs += " /mute" }
            if ($basicArgs) { $mpchcArgs += " /new" }; $mpchcArgs += " /volume $volume"; $mpchcArgs
        }
    }

    $playerPath = Test-Player -player $player
    if ($IsLinux) { Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow -RedirectStandardError '/dev/null' *> $null | Out-Null }
    else { Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow *> $null | Out-Null }
}

Function Get-NearbyAirports {
    param ([object]$UserLocation, [array]$AtcSources, [int]$Radius)
    
    if (-not $script:AirportData) { Get-AirportInfo -ICAO "KLAX" | Out-Null }
    $allAirports = $script:AirportData.PSObject.Properties | ForEach-Object { $_.Value }

    $nearbyList = foreach ($airport in $allAirports) {
        if ($AtcSources.ICAO -contains $airport.icao) {
            [pscustomobject]@{
                ICAO     = $airport.icao
                Name     = $airport.name
                City     = $airport.city
                Country  = $airport.country
                Distance = (Get-DistanceKm -Lat1 $UserLocation.Latitude -Lon1 $UserLocation.Longitude -Lat2 $airport.lat -Lon2 $airport.lon)
            }
        }
    }
    return $nearbyList | Where-Object { $_.Distance -lt $Radius } | Sort-Object Distance | Select-Object -First 50
}

Function Select-ATCMap {
    param (
        [array]$AtcSources, 
        [array]$Favorites, 
        [string]$CsvPath, 
        [object]$UserLocation, 
        [int]$Radius,
        [switch]$IncludeWebcamIfAvailable
    )
    
    Write-Host "Generating interactive tactical map..." -ForegroundColor Cyan
    if (-not $script:AirportData) { Get-AirportInfo -ICAO "KLAX" | Out-Null }
    
    # --- START LOCAL SERVER FIRST TO LOCK IN A PORT ---
    $port = 49152
    $listener = New-Object System.Net.HttpListener
    $maxRetries = 10
    
    while ($maxRetries -gt 0) {
        try {
            $listener.Prefixes.Clear()
            $listener.Prefixes.Add("http://127.0.0.1:$port/")
            $listener.Start()
            break
        } catch {
            $port++
            $maxRetries--
        }
    }
    
    if (-not $listener.IsListening) {
        Write-Warning "Could not start local web server. Port is blocked."
        return $null
    }

    $mapData = @()
    $groupedSources = $AtcSources | Group-Object ICAO
    $favIcaos = $Favorites | Select-Object -ExpandProperty ICAO -Unique
    
    foreach ($group in $groupedSources) {
        $icaoCode = $group.Name
        $airportInfo = $script:AirportData.$icaoCode
        
        if ($airportInfo -and $null -ne $airportInfo.lat -and $null -ne $airportInfo.lon) {
            $airportName = $group.Group[0].'Airport Name'
            $hasWebcamGlobal = $false
            
            $channelLinks = @()
            foreach ($ch in $group.Group) {
                $desc = $ch.'Channel Description'
                $stream = $ch.'Stream URL'
                $cam = $ch.'Webcam URL'
                
                if ($stream -match ".*/(?<feed>[^\.]+)\.pls") { $stream = "http://d.liveatc.net/$($matches['feed'])" }
                
                $camIcon = ""
                # Only show webcam icon if the source has one AND the user passed the flag
                if (-not [string]::IsNullOrWhiteSpace($cam) -and $IncludeWebcamIfAvailable) { 
                    $camIcon = " 📷"
                    $hasWebcamGlobal = $true 
                }
                
                # Link triggers the JS function to send data back to PowerShell
                $channelLinks += "&bull; <a href=`"javascript:void(0)`" onclick=`"playChannel('$icaoCode', '$desc')`" style=`"color: #a2a2bd; text-decoration: none; transition: 0.2s;`" onmouseover=`"this.style.color='#fff'`" onmouseout=`"this.style.color='#a2a2bd'`">$desc</a>$camIcon"
            }
            
            $favCount = ($Favorites | Where-Object { $_.ICAO -eq $icaoCode } | Measure-Object -Property Count -Sum).Sum
            if ($null -eq $favCount) { $favCount = 0 }
            
            $isFav = if ($favCount -gt 0) { 'true' } else { 'false' }
            $hasCam = if ($hasWebcamGlobal) { 'true' } else { 'false' }
            
            $title = "$icaoCode - $airportName" -replace "'","\'" -replace '"','\"'
            $descHtml = ($channelLinks -join "<br/>") -replace "'","\'" -replace '"','\"'
            
            $mapData += "{ lat: $($airportInfo.lat), lon: $($airportInfo.lon), title: '$title', desc: '$descHtml', isFav: $isFav, favCount: $favCount, hasCam: $hasCam }"
        }
    }
    
    $jsArray = "[`n" + ($mapData -join ",`n") + "`n]"
    $userLat = if ($UserLocation) { $UserLocation.Latitude } else { 'null' }
    $userLon = if ($UserLocation) { $UserLocation.Longitude } else { 'null' }
    $userRad = if ($UserLocation -and $Radius) { $Radius * 1000 } else { 0 }
    
    $csvName = Split-Path $CsvPath -Leaf
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>LofiATC Global Radar</title>
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <script src="https://unpkg.com/@joergdietrich/leaflet.terminator"></script>
    <style>
        body, html { margin: 0; padding: 0; height: 100%; font-family: 'Segoe UI', sans-serif; background-color: #0b0f19; }
        #map { height: 100%; width: 100%; z-index: 1; }
        
        #brand-overlay { position: absolute; top: 20px; right: 20px; z-index: 1000; background: rgba(11, 15, 25, 0.85); color: #fff; padding: 15px 25px; border-radius: 8px; border-left: 5px solid #e94560; box-shadow: 0 4px 6px rgba(0,0,0,0.3); pointer-events: none; backdrop-filter: blur(4px); }
        #brand-overlay h1 { margin: 0 0 5px 0; font-size: 26px; font-weight: 800; letter-spacing: 1px; }
        #brand-overlay h1 span { color: #e94560; }
        #brand-overlay p { margin: 0; font-size: 13px; color: #a2a2bd; }
        #brand-overlay .sub-text { font-size: 11px; opacity: 0.6; margin-top: 3px; font-style: italic; }
        
        #legend-overlay { position: absolute; bottom: 20px; right: 20px; z-index: 1000; background: rgba(11, 15, 25, 0.85); color: #a2a2bd; padding: 12px 18px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.3); pointer-events: none; backdrop-filter: blur(4px); font-size: 13px; }
        .legend-item { display: flex; align-items: center; margin-bottom: 8px; }
        .legend-item:last-child { margin-bottom: 0; }
        .legend-color { width: 14px; height: 14px; border-radius: 50%; margin-right: 10px; box-shadow: 0 0 3px rgba(0,0,0,0.8); }
        
        .color-blue { background-color: #2A81CB; }
        .color-purple { background-color: #9b59b6; }
        .color-red { background-color: #e94560; }
        .color-green { background-color: #00ff00; }
        
        .leaflet-popup-content-wrapper { background: rgba(22, 33, 62, 0.95); color: #fff; border-radius: 6px; box-shadow: 0 0 10px rgba(0,0,0,0.5); backdrop-filter: blur(3px); }
        .leaflet-popup-tip { background: rgba(22, 33, 62, 0.95); }
        .leaflet-popup-content b { font-size: 14px; display: block; margin-bottom: 8px; color: #e94560; border-bottom: 1px solid #333; padding-bottom: 4px;}
        .fav-star { color: #f39c12; }
    </style>
</head>
<body>
    <div id="brand-overlay">
        <h1>Lofi<span>ATC</span></h1>
        <p>Active LiveATC Sources</p>
        <p class="sub-text">Loaded from: $csvName</p>
    </div>
    
    <div id="legend-overlay">
        <div class="legend-item"><span class="legend-color color-blue"></span> Active ATC</div>
        <div class="legend-item"><span class="legend-color color-purple"></span> Has Webcam</div>
        <div class="legend-item"><span class="legend-color color-red"></span> Favorite (Heatmap)</div>
        <div class="legend-item"><span class="legend-color color-green"></span> Your Location</div>
    </div>

    <div id="map"></div>
    
    <script>
        // Send choice back to PowerShell dynamically using the active Port
        function playChannel(icao, desc) {
            window.location.href = 'http://127.0.0.1:$port/?icao=' + encodeURIComponent(icao) + '&desc=' + encodeURIComponent(desc);
        }

        var map = L.map('map').setView([20, 0], 2);
        
        L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
            maxZoom: 18, attribution: '&copy; OpenStreetMap &copy; CARTO'
        }).addTo(map);

        L.terminator({ fillOpacity: 0.35, color: '#000', interactive: false }).addTo(map);

        fetch('https://api.rainviewer.com/public/weather-maps.json')
            .then(res => res.json())
            .then(data => {
                var latest = data.radar.past[data.radar.past.length - 1].path;
                L.tileLayer(data.host + latest + '/256/{z}/{x}/{y}/2/1_1.png', {
                    opacity: 0.6, 
                    zIndex: 10,
                    maxNativeZoom: 12, // RainViewer max zoom is 12. This tells Leaflet to stretch those tiles when zooming closer.
                    maxZoom: 18
                }).addTo(map);
            }).catch(e => console.log('Weather radar unavailable.'));

        var markers = $jsArray;
        
        markers.forEach(function(m) {
            var baseRadius = 5;
            var mColor = "#2A81CB"; 
            
            if (m.isFav) {
                mColor = "#e94560"; 
                baseRadius = Math.min(5 + (m.favCount * 1.5), 18); 
            } else if (m.hasCam) {
                mColor = "#9b59b6"; 
            }

            var favStar = m.isFav ? "<span class='fav-star'>★ </span>" : "";
            
            L.circleMarker([m.lat, m.lon], {
                radius: baseRadius, color: mColor, fillColor: mColor, fillOpacity: 0.7, weight: 2
            }).addTo(map).bindPopup("<b>" + favStar + m.title + "</b>" + m.desc);
        });

        var uLat = $userLat;
        var uLon = $userLon;
        var uRad = $userRad;

        if (uLat !== null && uLon !== null) {
            L.circleMarker([uLat, uLon], {
                radius: 6, color: '#00ff00', fillColor: '#00ff00', fillOpacity: 1, weight: 2, interactive: false
            }).addTo(map).bindPopup("<b>📍 Your Location</b>");
            
            L.circle([uLat, uLon], {
                radius: uRad, color: '#00ff00', weight: 1, fillOpacity: 0.05, dashArray: '5, 5', interactive: false
            }).addTo(map);
            
            map.setView([uLat, uLon], 6); 
        }
    </script>
</body>
</html>
"@
    
    $tempMapFile = Join-Path $env:TEMP "lofiatc_map.html"
    Set-Content -Path $tempMapFile -Value $htmlContent -Encoding UTF8
    
    if ($script:OnWindows) { Start-Process $tempMapFile } 
    elseif ($IsMacOS) { & open $tempMapFile } 
    else { & xdg-open $tempMapFile }
    
    Write-Host "`nMap opened in your browser! Click a channel on the map to start streaming." -ForegroundColor Green
    Write-Host "Waiting for selection... (Press 'Q' in this window to cancel and use the terminal)" -ForegroundColor Yellow
    
    $selection = $null
    
    try {
        while ($true) {
            # Start listening for a request
            $contextTask = $listener.BeginGetContext($null, $null)
            
            # Loop ensures the terminal doesn't freeze so the user can cancel if needed
            while (-not $contextTask.IsCompleted) {
                Start-Sleep -Milliseconds 100
                if ([console]::KeyAvailable) {
                    $key = [console]::ReadKey($true)
                    if ($key.Key.ToString() -eq 'Q') {
                        Write-Host "`nMap selection cancelled." -ForegroundColor Red
                        return $null
                    }
                }
            }
            
            $context = $listener.EndGetContext($contextTask)
            $req = $context.Request
            $res = $context.Response
            
            # CRITICAL FIX: Only process requests that actually contain our ICAO parameter!
            if ($null -ne $req.QueryString["icao"]) {
                $selection = @{
                    ICAO = $req.QueryString["icao"]
                    Channel = $req.QueryString["desc"]
                }
                
                # Send a success screen back to the browser so the user knows it worked
                $responseHtml = "<html><body style='background:#0b0f19;color:#fff;text-align:center;font-family:sans-serif;padding-top:20vh;'><h1>Starting LofiATC...</h1><p style='color:#a2a2bd'>You can close this tab now.</p><script>setTimeout(function(){window.close();}, 3000);</script></body></html>"
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseHtml)
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.OutputStream.Close()
                
                Write-Host "`nSelection received from map: $($selection.ICAO)" -ForegroundColor Green
                break # Exit the loop, we got our selection
            } else {
                # Ignore background browser requests (like favicon.ico)
                $res.StatusCode = 200
                $res.OutputStream.Close()
            }
        }
    }
    finally {
        # Give the browser a split second to receive the success page before killing the server
        Start-Sleep -Milliseconds 250 
        $listener.Stop()
        $listener.Close()
    }
    
    return $selection
}


$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($LoadConfig) {
    if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'config.json' }
    if (Test-Path $ConfigPath) {
        $config = Get-Content -Path $ConfigPath | ConvertFrom-Json
        foreach ($prop in $config.PSObject.Properties) {
            $name = $prop.Name
            if ($name -in @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'SaveConfig', 'LoadConfig', 'ConfigPath')) { continue }
            if (-not $PSBoundParameters.ContainsKey($name)) { Set-Variable -Name $name -Value $prop.Value -Scope Local }
        }
        Write-Information "Loaded config from $ConfigPath"
    } else { Write-Warning "Config file not found at $ConfigPath" }
}

$Player = Resolve-Player -explicitPlayer $Player

if ($SaveConfig) {
    if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'config.json' }
    $paramNames = (Get-Command $MyInvocation.MyCommand.Path).Parameters.Keys
    $config = @{}
    foreach ($name in $paramNames) {
        if ($name -notin @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'SaveConfig', 'LoadConfig', 'ConfigPath')) {
            $value = Get-Variable -Name $name -ValueOnly
            if ($value -is [System.Management.Automation.SwitchParameter]) { $value = [bool]$value }
            $config[$name] = $value
        }
    }
    $config | ConvertTo-Json | Set-Content -Path $ConfigPath
    Write-Information "Saved config to $ConfigPath"
}

Test-Player -player $Player | Out-Null

$baseCsv = Join-Path $scriptDir 'atc_sources.csv'
$liveCsv = Join-Path $scriptDir 'liveatc_sources.csv'
$favoritesJson = Join-Path $scriptDir 'favorites.json'
$maxFavorites = 10

if (-not $UseBaseCSV -and (Test-Path $liveCsv)) {
    Write-Information "Using live sources CSV: $liveCsv"; $csvPath = $liveCsv
} else {
    Write-Information "Using base sources CSV: $baseCsv"; $csvPath = $baseCsv
}

if ($LofiGenre -and (-not $PSBoundParameters.ContainsKey('LofiSource'))) { $lofiMusicUrl = $LofiGenres[$LofiGenre] }
else { $lofiMusicUrl = $LofiSource }

$atcSources = Import-ATCSource -csvPath $csvPath
$favorites = Get-Favorite -path $favoritesJson
$currentUserLocation = $null

if ($Nearby) {
    if ($ICAO) { Write-Host "-Nearby switch detected, ignoring -ICAO $ICAO." -ForegroundColor Yellow; $ICAO = $null }
    
    $currentUserLocation = Get-CurrentCoordinates
    if (-not $currentUserLocation) {
        Write-Error "Could not determine your location. Please select manually."
    } else {
        $locationLabel = if ($currentUserLocation.Source -eq 'Device') { "your current device location" } else { "$($currentUserLocation.City), $($currentUserLocation.Country)" }
        Write-Host "Finding airports near $locationLabel..." -ForegroundColor Green
        
        $sortedAirports = Get-NearbyAirports -UserLocation $currentUserLocation -AtcSources $atcSources -Radius $NearbyRadius
        
        # If ShowMap is NOT active, prompt the user immediately
        if (-not $ShowMap) {
            if ($sortedAirports.Count -eq 0) {
                Write-Error "No LiveATC streams found near your location."
            } else {
                $choices = $sortedAirports | ForEach-Object { "[{0}] {1}, {2} ({3}km away)" -f $_.ICAO, $_.Name, $_.City, ([math]::Round($_.Distance)) }
                $prompt = "Select a nearby airport:"
                $selectedChoice = if ($UseFZF) { Select-ItemFZF -prompt $prompt -items $choices } else { Select-Item -prompt $prompt -items $choices }
                if ($selectedChoice -match "^\[(?<icao>\w{4})\]") { $ICAO = $matches.icao } 
                else { Write-Error "Invalid selection. Exiting."; exit }
            }
        }
    }
}

$mapSelectedChannel = $null

if ($ShowMap) {
    # Pass the IncludeWebcam flag into the map function
    $mapSelection = Select-ATCMap -AtcSources $atcSources -Favorites $favorites -CsvPath $csvPath -UserLocation $currentUserLocation -Radius $NearbyRadius -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable
    
    # If the user clicked a channel on the map, skip the terminal menus!
    if ($mapSelection -and $mapSelection.ICAO) {
        $ICAO = $mapSelection.ICAO
        $mapSelectedChannel = $mapSelection.Channel
    }
}

$selectedATC = $null
if ($ICAO) {
    $icaoMatches = $atcSources | Where-Object { $_.ICAO -eq $ICAO }
    if (-not $icaoMatches) { Write-Error "No ATC stream found for ICAO $ICAO"; exit }

    # If the user selected a specific channel via the map, use it immediately
    if ($mapSelectedChannel) {
        $match = $icaoMatches | Where-Object { $_.'Channel Description' -eq $mapSelectedChannel } | Select-Object -First 1
    }
    elseif ($icaoMatches.Count -eq 1 -or $RandomATC) {
        $match = if ($RandomATC -and $icaoMatches.Count -gt 1) { Get-Random -InputObject $icaoMatches } else { $icaoMatches[0] }
    } else {
        $channels = $icaoMatches | ForEach-Object {
            $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL') -and $IncludeWebcamIfAvailable) { " [Webcam available]" } else { "" }
            "{0}{1}" -f $_.'Channel Description', $webcamIndicator
        } | Sort-Object -Unique
        
        $chanSel = if ($UseFZF) { Select-ItemFZF -prompt "Select a channel for ${ICAO}" -items $channels }
                   else { Select-Item -prompt "Select a channel for ${ICAO}:" -items $channels }
        
        $chanClean = $chanSel -replace '\s\[Webcam available\]', ''
        $match = $icaoMatches | Where-Object { $_.'Channel Description' -eq $chanClean } | Select-Object -First 1
    }

    $selectedATC = @{ StreamUrl = $match.'Stream URL'; WebcamUrl = $match.'Webcam URL'; AirportInfo = $match }
}

if (-not $selectedATC) {
    if ($RandomATC) { $selectedATC = Get-RandomATCStream -atcSources $atcSources }
    else {
        if ($UseFavorite) { $selectedATC = Select-FavoriteATC -favorites $favorites -atcSources $atcSources -UseFZF:$UseFZF }
        if (-not $selectedATC) {
            if ($UseFZF) { $selectedATC = Select-ATCStreamFZF -atcSources $atcSources }
            else {
                while (-not $selectedATC) {
                    $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
                    do {
                        $countries = @($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique)
                        $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items $countries -AllowBack
                        if ($null -eq $selectedCountry) { $selectedContinent = $null; break }
                        $states = @($atcSources | Where-Object {
                                $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() -and
                                $_.Country.Trim().ToLower() -eq $selectedCountry.Trim().ToLower() -and
                                -not [string]::IsNullOrWhiteSpace($_.'State/Province')
                            } | Select-Object -ExpandProperty 'State/Province' | Sort-Object -Unique)

                        if ($states.Count -gt 0) {
                            do {
                                $selectedState = Select-Item -prompt "Select a state or province from ${selectedCountry}:" -items $states -AllowBack
                                if ($null -eq $selectedState) { $selectedCountry = $null; break }
                                $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry -state $selectedState
                            } while (-not $selectedATC -and $selectedCountry)
                            if (-not $selectedCountry) { continue }
                        } else {
                            $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
                        }
                    } while (-not $selectedATC)
                }
            }
        }
    }
}

$selectedATCUrl = $selectedATC.StreamUrl
$selectedWebcamUrl = $selectedATC.WebcamUrl
Clear-Host
Write-Welcome -airportInfo $selectedATC.AirportInfo -OpenRadar:$OpenRadar
if (-not $RandomATC) { Add-Favorite -path $favoritesJson -ICAO $selectedATC.AirportInfo.ICAO -Channel $selectedATC.AirportInfo.'Channel Description' -maxEntries $maxFavorites }
if ($OpenRadar) { Open-Radar -ICAO $selectedATC.AirportInfo.ICAO }

if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Player"]) { Write-Verbose "Player selected by user: $Player" }
else { Write-Verbose "Default player selected: $Player" }

if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) {
    Write-Verbose "Opening ATC stream: $selectedATCUrl"
    if ($selectedWebcamUrl) { Write-Verbose "Opening webcam stream: $selectedWebcamUrl" }
}

Start-Player -url $selectedATCUrl -player $Player -noVideo -basicArgs -volume $ATCVolume

if (-not $NoLofiMusic) {
    if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) { Write-Verbose "Opening Lofi Girl stream: $lofiMusicUrl" }
    if ($PlayLofiGirlVideo) { Start-Player -url $lofiMusicUrl -player $Player -basicArgs -volume $LofiVolume }
    else { Start-Player -url $lofiMusicUrl -player $Player -noVideo -basicArgs -volume $LofiVolume }
}

if ($IncludeWebcamIfAvailable -and $selectedWebcamUrl) { Start-Player -url $selectedWebcamUrl -player $Player -noAudio -basicArgs }
