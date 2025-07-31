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
Specify the media player to use (VLC, Potplayer, MPC-HC, MPV, Cosmic, Celluloid, or SMPlayer). Default is VLC if there is no default set in system for mp4.

.PARAMETER ATCVolume
Volume level for the ATC stream. Default is 65.

.PARAMETER LofiVolume
Volume level for the Lofi Girl stream. Default is 50.

.PARAMETER LofiSource
Specify a custom URL or file path for the Lofi audio/video source Defaults to the Lofi Girl Youtube stream if not provided.

.PARAMETER ICAO
Specify an airport by ICAO code. If multiple channels exist you will be prompted to select one unless -RandomATC is used to choose randomly.

.PARAMETER OpenRadar
Open the FlightAware radar page for the selected ICAO after displaying the welcome screen.

.NOTES
File Name      : lofiatc.ps1
Author         : github.com/RoMinjun
Prerequisite   : PowerShell V5.1 or later

.EXAMPLE
.\lofiatc.ps1 -IncludeWebcamIfAvailable -NoLofiMusic
This command runs the script, includes webcam video if available, and does not play Lofi music.

.EXAMPLE
.\lofiatc.ps1 -RandomATC -PlayLofiGirlVideo
This command runs the script, selects a random ATC stream, and plays the Lofi Girl video.

.EXAMPLE
.\lofiatc.ps1 -IncludeWebcamIfAvailable -UseFZF
This command runs the script, includes webcam video if available, and uses fzf for selecting ATC streams.

.EXAMPLE
.\lofiatc.ps1 -IncludeWebcamIfAvailable -UseFZF -Player Potplayer
This command runs the script, includes webcam video if available, uses fzf for selecting ATC streams, and uses Potplayer as the media player.

.EXAMPLE
.\lofiatc.ps1 -IncludeWebcamIfAvailable -UseFZF -Player VLC
This command runs the script, includes webcam video if available, uses fzf for selecting ATC streams, and uses VLC as the media player.

.EXAMPLE
.\lofiatc.ps1 -UseFavorite
This command lets you pick from the favorites list instead of browsing continents and countries.

.EXAMPLE
.\lofiatc.ps1 -LofiSource "C:\Path\To\Your\LofiAudio.mp3"
This command plays a local audio file instead of the default stream

.EXAMPLE
.\lofiatc.ps1 -LofiSource "http://youtube.com/watch?v=jfKfPfyJRdk"
This command plays a custom audio source from Youtube. Spotify streams wont work due to DRM restrictions.

.EXAMPLE
.\lofiatc.ps1 -OpenRadar
This command launches the FlightAware radar page for the selected airport.

.EXAMPLE
.\lofiatc.ps1 -ICAO RJTT
This command skips continent/country prompts and starts with Tokyo Haneda's channels.

.EXAMPLE
.\lofiatc.ps1 -ICAO RJTT -RandomATC
This command skips continent/country prompts and starts with Tokyo Haneda's channels, selecting a random channel.

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
    [ValidateSet("VLC", "MPV", "Potplayer", "MPC-HC", "Cosmic", "Celluloid", "SMPlayer")]
    [string]$Player,
    [int]$ATCVolume = 65,
    [int]$LofiVolume = 50,
    [string]$LofiSource = "https://www.youtube.com/watch?v=jfKfPfyJRdk",
    [string]$ICAO,
    [switch]$OpenRadar
)

# MP4 == Default app for all files
# Function to check the default application for .mp4
Function Get-DefaultAppForMP4 {
    try {
        # Query the UserChoice Registry Key for .mp4
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice"
        if (Test-Path $keyPath) {
            $key = Get-ItemProperty -Path $keyPath -ErrorAction Stop
            $progID = $key.ProgID
        } else {
            # Fallback to system default if UserChoice doesn't exist
            $keyPath = "HKCR:\.mp4"
            if (Test-Path $keyPath) {
                $progID = (Get-ItemProperty -Path $keyPath -ErrorAction Stop).'(default)'
            } else {
                return $null
            }
        }

        # Extract executable name if ProgID follows Applications format
        if ($progID -like "Applications\*") {
            return $progID -replace "Applications\\", ""
        } else {
            return $progID
        }
    } catch {
        return $null
    }
}

# Function to determine the appropriate player
Function Resolve-Player {
    param (
        [string]$explicitPlayer
    )

    if ($explicitPlayer) {
        # If the user specifies a player, use it
        return $explicitPlayer
    }

    if ($IsWindows) {
        # On Windows try to resolve from default app
        $defaultApp = Get-DefaultAppForMP4
        switch ($defaultApp) {
            "vlc.exe"       { return "VLC" }
            "mpv.exe"       { return "MPV" }
            "PotPlayerMini64.exe" { return "Potplayer" }
            "mpc-hc64.exe"  { return "MPC-HC" }
            default         { return "VLC" }
        }
    } else {
        # On non-Windows prefer mpv or other linux players. Cosmic-player is supported if found.
        if (Get-Command mpv -ErrorAction SilentlyContinue) { return "MPV" }
        if (Get-Command celluloid -ErrorAction SilentlyContinue) { return "Celluloid" }
        if (Get-Command smplayer -ErrorAction SilentlyContinue) { return "SMPlayer" }
        if (Get-Command vlc -ErrorAction SilentlyContinue) { return "VLC" }
        if (Get-Command cosmic-player -ErrorAction SilentlyContinue) { return "Cosmic" }
        return "MPV"
    }
}

# Function to check if the selected player is available
Function Test-Player {
    param (
        [string]$player
    )

    $command = switch ($player) {
        "VLC" { if ($IsWindows) { "vlc.exe" } else { "vlc" } }
        "MPV" { if ($IsWindows) { "mpv.com" } else { "mpv" } }
        "Potplayer" { "PotPlayerMini64.exe" }
        "MPC-HC" { "mpc-hc64.exe" }
        "Cosmic" { "cosmic-player" }
        "Celluloid" { "celluloid" }
        "SMPlayer" { "smplayer" }
    }

    $fullPath = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    if (-Not $fullPath) {
        Write-Error "$player is not installed or not available in PATH. Please install $player to proceed."
        exit
    }

    return $fullPath
}

# Function to load ATC sources from CSV
Function Import-ATCSources {
    param (
        [string]$csvPath
    )

    if (-Not (Test-Path $csvPath)) {
        Write-Error "The ATC sources CSV file ($csvPath) was not found. Please create it before running the script."
        exit
    }

    return Import-Csv -Path $csvPath
}

# Functions for managing favorites
Function Get-Favorites {
    param(
        [string]$path
    )

    if (Test-Path $path) {
        try {
            $data = Get-Content -Path $path -Raw | ConvertFrom-Json
            foreach ($f in $data) {
                if (-not $f.PSObject.Properties['Count']) { $f | Add-Member -Name Count -Value 1 -MemberType NoteProperty }
                if (-not $f.PSObject.Properties['LastUsed']) { $f | Add-Member -Name LastUsed -Value (Get-Date) -MemberType NoteProperty }
            }
            return $data
        } catch {
            return @()
        }
    } else {
        return @()
    }
}

Function Save-Favorites {
    param(
        [array]$favorites,
        [string]$path
    )

    $favorites | ConvertTo-Json | Set-Content -Path $path
}

Function Add-Favorite {
    param(
        [string]$path,
        [string]$ICAO,
        [string]$Channel,
        [int]$maxEntries = 10
    )

    $favorites = Get-Favorites -path $path
    $existing = $favorites | Where-Object { $_.ICAO -eq $ICAO -and $_.Channel -eq $Channel }
    if ($existing) {
        $existing.Count++
        $existing.LastUsed = Get-Date
        $favorites = $favorites | Where-Object { !(($_.ICAO -eq $ICAO) -and ($_.Channel -eq $Channel)) }
        $favorites = ,$existing + $favorites
    } else {
        $newEntry = [pscustomobject]@{
            ICAO     = $ICAO
            Channel  = $Channel
            Count    = 1
            LastUsed = Get-Date
        }
        $favorites = ,$newEntry + $favorites
    }
    $favorites = $favorites | Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='LastUsed';Descending=$true}
    if ($favorites.Count -gt $maxEntries) { $favorites = $favorites[0..($maxEntries-1)] }
    Save-Favorites -favorites $favorites -path $path
}

# Open FlightAware radar page for the given airport
Function Open-Radar {
    param(
        [string]$ICAO
    )

    $url = "https://beta.flightaware.com/live/airport/$ICAO"
    if ($IsWindows) {
        Start-Process $url
    } elseif ($IsMacOS) {
        & open $url
    } else {
        & xdg-open $url
    }
}

Function Select-FavoriteATC {
    param(
        [array]$favorites,
        [array]$atcSources,
        [switch]$UseFZF
    )

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
            StreamUrl  = $fav.Entry.'Stream URL'
            WebcamUrl  = $fav.Entry.'Webcam URL'
            AirportInfo = $fav.Entry
        }
    } else {
        return $null
    }
}


# Function to select an item from a list
Function Select-Item {
    param (
        [string]$prompt,
        [array]$items,
        [switch]$AllowBack
    )

    while ($true) {
        Clear-Host
        Write-Host $prompt -ForegroundColor Yellow
        $i = 1
        foreach ($item in $items) {
            Write-Host "$i. $item"
            $i++
        }
        if ($AllowBack) { Write-Host "0. Go Back" }

        $userChoice = Read-Host "Enter the number of your choice"
        if ($AllowBack -and $userChoice -eq '0') { return $null }

        if ($userChoice -match '^\d+$') {
            $index = [int]$userChoice - 1
            if ($index -ge 0 -and $index -lt $items.Count) {
                return $items[$index].Trim()
            }
        }

        Write-Host "Error: Invalid selection." -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}

# Function to select an item using fzf
Function Select-ItemFZF {
    param (
        [string]$prompt,
        [array]$items
    )

    $selectedItem = $items | fzf --prompt "$prompt> " --exact
    if ($selectedItem) {
        return $selectedItem.Trim()
    } else {
        Write-Host "No selection made. Exiting script." -ForegroundColor Yellow
        exit
    }
}

# Function to select an ATC stream
Function Select-ATCStream {
    param (
        [array]$atcSources,
        [string]$continent,
        [string]$country
    )

    while ($true) {
        Clear-Host
        # Filter ATC sources by selected continent and country
        $choices = $atcSources | Where-Object {
            $_.Continent.Trim().ToLower() -eq $continent.Trim().ToLower() -and
            $_.Country.Trim().ToLower() -eq $country.Trim().ToLower()
        }

        if ($choices.Count -eq 0) {
            Write-Error "No ATC streams available for the selected country."
            return $null
        }

        # Group by city and airport name, and check if any channel for that airport has a webcam
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
            } else {
                $selected = $airportChoices[0]
            }

            if ($selected) {
                return @{
                    StreamUrl = $selected.'Stream URL'
                    WebcamUrl = $selected.'Webcam URL'
                    AirportInfo = $selected
                }
            }
        }
    }
}

# Function to select an ATC stream using fzf
Function Select-ATCStreamFZF {
    param (
        [array]$atcSources
    )

    Clear-Host

    # Combine relevant information for fzf selection
    $choices = $atcSources | ForEach-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) {
            " [Webcam available]"
        } else {
            ""
        }

        "[{0}, {1}] {2} ({4}/{5}) | {3}{6}" -f $_.City, $_.'Country', $_.'Airport Name', $_.'Channel Description', $_.'ICAO', $_.'IATA', $webcamInfo
    }

    $selectedChoice = Select-ItemFZF -prompt "Select an ATC stream" -items $choices

    $selectedStream = $atcSources | Where-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) {
            " [Webcam available]"
        } else {
            ""
        }

        $formattedEntry = "[{0}, {1}] {2} ({4}/{5}) | {3}{6}" -f $_.City, $_.'Country', $_.'Airport Name', $_.'Channel Description', $_.'ICAO', $_.'IATA', $webcamInfo
        $formattedEntry -eq $selectedChoice
    }

    if ($selectedStream) {
        return @{
            StreamUrl = $selectedStream.'Stream URL'
            WebcamUrl = $selectedStream.'Webcam URL'
            AirportInfo = $selectedStream
        }
    } else {
        Write-Error "No matching ATC stream found."
        exit
    }
}

# Function to get a random ATC stream
Function Get-RandomATCStream {
    param (
        [array]$atcSources
    )

    # Select a random ATC stream from the list
    $randomIndex = Get-Random -Minimum 0 -Maximum $atcSources.Count
    $selectedStream = $atcSources[$randomIndex]
    return @{
        StreamUrl = $selectedStream.'Stream URL'
        WebcamUrl = $selectedStream.'Webcam URL'
        AirportInfo = $selectedStream
    }
}

# Function to fetch METAR/TAF data
Function Get-METAR-TAF {
    param (
        [string]$ICAO
    )
    $url = "https://metar.vatsim.net/metar.php?id=$ICAO"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
        $raw = $response.Content.Trim()
        if ($raw) {
            return $raw
        } else {
            return "METAR/TAF data unavailable."
        }
    } catch {
        Write-Error "Failed to fetch METAR/TAF data for $ICAO. Exception: $_"
        return "METAR/TAF data unavailable."
    }
}

# Decoding METAR message
Function ConvertFrom-METAR {
    param (
        [string]$metar
    )

    # Initialize a hashtable for the decoded values
    $decoded = @{}

    # Match wind information, including gusts
    if ($metar -match "(?<windDir>\d{3})(?<windSpeed>\d{2})(G(?<gustSpeed>\d{2}))?KT") {
        $decoded["Wind"] = if ($matches.gustSpeed) {
            "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots, gusting to $([int]$matches.gustSpeed) knots"
        } else {
            "$([int]$matches.windDir)$([char]176) at $([int]$matches.windSpeed) knots"
        }
    }

    # Match visibility
    if ($metar -match "(?<visibility>9999)") {
        $decoded["Visibility"] = "10+ km (Unlimited)"
    } elseif ($metar -match "\b(?<visibility>\d{4})\b") {
        $decoded["Visibility"] = "$([int]$matches.visibility / 1000) km"
    } elseif ($metar -match "(?<visibility>\d+SM)") {
        $decoded["Visibility"] = "$([math]::Round([double]($matches.visibility -replace 'SM','') * 1.60934, 3)) km"
    } else {
        $decoded["Visibility"] = "Unavailable"
    }

    # Match cloud coverage and ceiling, including vertical visibility
    if ($metar -match "VV(?<vv>\d{3})") {
        $decoded["Ceiling"] = "Vertical Visibility at $([int]$matches.vv * 100) ft"
    } elseif ($metar -match "(?<clouds>BKN|OVC|SCT|FEW)(?<ceiling>\d{3})") {
        $cloudType = switch ($matches.clouds) {
            "BKN" { "Broken" }
            "OVC" { "Overcast" }
            "SCT" { "Scattered" }
            "FEW" { "Few" }
            default { $matches.clouds }
        }
        $decoded["Ceiling"] = "$cloudType at $([int]$matches.ceiling * 100) ft"
    } else {
        $decoded["Ceiling"] = "Unavailable"
    }
    # Match temperature and dew point
    if ($metar -match "(?<temp>-?\d{1,2})/(?<dew>-?\d{1,2}|M\d{1,2})") {
        # Remove leading zeros for temperature
        $temperature = if ($matches.temp -eq "-00") { 
            "0$([char]176)C" 
        } else { 
            "$([int]$matches.temp)$([char]176)C" 
        }

        # Remove leading zeros for dew point
        $dewPoint = if ($matches.dew -eq "-00") { 
            "0$([char]176)C" 
        } elseif ($matches.dew -like "M*") {
            "-$([int]($matches.dew.Trim('M')))$([char]176)C"
        } else {
            "$([int]$matches.dew)$([char]176)C"
        }

        $decoded["Temperature"] = $temperature
        $decoded["DewPoint"] = $dewPoint
    } else {
        $decoded["Temperature"] = "Unavailable"
        $decoded["DewPoint"] = "Unavailable"
    }

    # Match pressure in hPa (e.g., Q1023) or inHg (e.g., A2996)
    if ($metar -match "Q(?<pressureHPA>\d{4})") {
        $decoded["Pressure"] = "$([int]$matches.pressureHPA) hPa"
    } elseif ($metar -match "A(?<pressureINHG>\d{4})") {
        $pressureHPA = [double]($matches.pressureINHG / 100) * 33.8639
        $decoded["Pressure"] = "$([math]::Round($pressureHPA, 1)) hPa"
    } else {
        $decoded["Pressure"] = "Unavailable"
    }

    # Return as a custom object
    return [PSCustomObject]$decoded
}


# Cache for airport database
$global:AirportData = $null

# Mapping of common IANA time zones to Windows IDs for PowerShell 5.1
$global:IanaToWindowsMap = @{
    "Etc/UTC"             = "UTC"
    "Europe/London"       = "GMT Standard Time"
    "Europe/Dublin"       = "GMT Standard Time"
    "Europe/Amsterdam"    = "W. Europe Standard Time"
    "Europe/Paris"        = "Romance Standard Time"
    "Europe/Berlin"       = "W. Europe Standard Time"
    "Europe/Madrid"       = "Romance Standard Time"
    "Europe/Brussels"     = "Romance Standard Time"
    "Europe/Rome"         = "W. Europe Standard Time"
    "Europe/Vienna"       = "W. Europe Standard Time"
    "Europe/Prague"       = "Central Europe Standard Time"
    "Europe/Moscow"       = "Russian Standard Time"
    "Europe/Athens"       = "GTB Standard Time"
    "Europe/Bucharest"    = "GTB Standard Time"
    "Africa/Cairo"        = "Egypt Standard Time"
    "Africa/Johannesburg" = "South Africa Standard Time"
    "Asia/Jerusalem"      = "Israel Standard Time"
    "Asia/Dubai"          = "Arabian Standard Time"
    "Asia/Tehran"         = "Iran Standard Time"
    "Asia/Riyadh"         = "Arab Standard Time"
    "Asia/Karachi"        = "Pakistan Standard Time"
    "Asia/Kolkata"        = "India Standard Time"
    "Asia/Dhaka"          = "Bangladesh Standard Time"
    "Asia/Bangkok"        = "SE Asia Standard Time"
    "Asia/Singapore"      = "Singapore Standard Time"
    "Asia/Hong_Kong"      = "China Standard Time"
    "Asia/Shanghai"       = "China Standard Time"
    "Asia/Taipei"         = "Taipei Standard Time"
    "Asia/Tokyo"          = "Tokyo Standard Time"
    "Asia/Seoul"          = "Korea Standard Time"
    "Australia/Perth"     = "W. Australia Standard Time"
    "Australia/Adelaide"  = "Cen. Australia Standard Time"
    "Australia/Sydney"    = "AUS Eastern Standard Time"
    "Pacific/Auckland"    = "New Zealand Standard Time"
    "America/Halifax"     = "Atlantic Standard Time"
    "America/St_Johns"    = "Newfoundland Standard Time"
    "America/Argentina/Buenos_Aires" = "Argentina Standard Time"
    "America/Sao_Paulo"   = "E. South America Standard Time"
    "America/New_York"    = "Eastern Standard Time"
    "America/Chicago"     = "Central Standard Time"
    "America/Denver"      = "Mountain Standard Time"
    "America/Phoenix"     = "US Mountain Standard Time"
    "America/Los_Angeles" = "Pacific Standard Time"
    "America/Anchorage"   = "Alaskan Standard Time"
    "Pacific/Honolulu"    = "Hawaiian Standard Time"
}

# Helper to convert IANA timezone to a TimeZoneInfo object
Function ConvertTo-TimeZoneInfo {
    param(
        [string]$IanaId
    )
    try {
        return [System.TimeZoneInfo]::FindSystemTimeZoneById($IanaId)
    } catch {
        if ($global:IanaToWindowsMap.ContainsKey($IanaId)) {
            return [System.TimeZoneInfo]::FindSystemTimeZoneById($global:IanaToWindowsMap[$IanaId])
        } else {
            throw "Timezone ID '$IanaId' not recognized"
        }
    }
}

# Retrieve airport information from a public dataset
Function Get-AirportInfo {
    param(
        [string]$ICAO
    )
    if (-not $global:AirportData) {
        try {
            $global:AirportData = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/mwgg/Airports/master/airports.json' -Method Get
        } catch {
            Write-Error "Failed to load airport database. Exception: $_"
            return $null
        }
    }
    $info = $global:AirportData.$ICAO
    if (-not $info) {
        Write-Error "Airport info not found for $ICAO."
    }
    return $info
}

# Function to fetch airport date/time
Function Get-AirportDateTime {
    param (
        [string]$ICAO
    )
    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        if (-not $airportInfo -or -not $airportInfo.tz) { throw "Timezone not found" }
        $tzInfo = ConvertTo-TimeZoneInfo -IanaId $airportInfo.tz
        $local = [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tzInfo)
        $formatted = $local.ToString('dd MMMM yyyy HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        return "$formatted LT"
    } catch {
        Write-Error "Date and time not found for $ICAO. Exception: $_"
        return "Date/time data unavailable"
    }
}

# Function to fetch airport sunrise/sunset times
Function Get-AirportSunriseSunset {
    param (
        [string]$ICAO
    )
    try {
        $airportInfo = Get-AirportInfo -ICAO $ICAO
        $lat = $airportInfo.lat
        $lon = $airportInfo.lon
        $tz  = $airportInfo.tz
        if (-not ($lat -and $lon -and $tz)) { throw "Missing data" }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $tzInfo = ConvertTo-TimeZoneInfo -IanaId $tz

        # Request data already adjusted to the airport's timezone
        $uri = "https://api.sunrise-sunset.org/json?lat=$lat&lng=$lon&formatted=0&tzid=$tz"
        $sunInfo = Invoke-RestMethod -Uri $uri -Method Get
        $sunriseRaw = $sunInfo.results.sunrise
        $sunsetRaw  = $sunInfo.results.sunset

        # Parse the returned timestamps
        $sunriseOffset = [datetimeoffset]::Parse($sunriseRaw, [cultureinfo]::InvariantCulture)
        $sunsetOffset  = [datetimeoffset]::Parse($sunsetRaw,  [cultureinfo]::InvariantCulture)

        # Convert explicitly to the airport timezone in case the API omits it
        $sunrise = [System.TimeZoneInfo]::ConvertTime($sunriseOffset, $tzInfo).ToString('HH:mm')
        $sunset  = [System.TimeZoneInfo]::ConvertTime($sunsetOffset,  $tzInfo).ToString('HH:mm')
        return @{
            Sunrise = $sunrise
            Sunset  = $sunset
        }
    } catch {
        Write-Error "Failed to fetch data for $ICAO. Exception: $_"
        return @{
            Sunrise = "Data unavailable"
            Sunset  = "Data unavailable"
        }
    }
}

# Function to fetch METAR last updated time
Function Get-METAR-LastUpdatedTime {
    param (
        [string]$ICAO
    )
    try {
        $metar = Get-METAR-TAF -ICAO $ICAO
        if ($metar -match '\b(?<ts>\d{6})Z\b') {
            $ts = $matches.ts
            $day = [int]$ts.Substring(0,2)
            $hour = [int]$ts.Substring(2,2)
            $min = [int]$ts.Substring(4,2)
            $now = (Get-Date).ToUniversalTime()
            $year = $now.Year
            $month = $now.Month
            if ($day -gt $now.Day) {
                $prev = $now.AddMonths(-1)
                $year = $prev.Year
                $month = $prev.Month
            }
            $obs = New-Object DateTime($year,$month,$day,$hour,$min,0,[System.DateTimeKind]::Utc)
            $diff = $now - $obs
            if ($diff.TotalHours -ge 1) {
                return "{0:N0} hours" -f [math]::Floor($diff.TotalHours)
            } else {
                return "{0:N0} minutes" -f [math]::Floor($diff.TotalMinutes)
            }
        } else {
            throw 'Time code not found'
        }
    } catch {
        Write-Error "Failed to fetch the last updated time for $ICAO. Exception: $_"
        return "Last updated time unavailable."
    }
}

Function Write-Welcome {
    param (
        [object]$airportInfo,
        [switch]$OpenRadar
    )

    # Check PowerShell version
    $isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7

    # Unicode Symbols (Use blank strings for PowerShell 5.1)
    $airplane       = if ($isPowerShell7) { "`u{2708}`u{FE0F}" } else { "" }
    $location       = if ($isPowerShell7) { "`u{1F4CD}" } else { "" }
    $earth          = if ($isPowerShell7) { "`u{1F30D}" } else { "" }
    $departure      = if ($isPowerShell7) { "`u{1F6EB}" } else { "" }
    $clock          = if ($isPowerShell7) { "`u{23F0}" } else { "" }
    $weather        = if ($isPowerShell7) { "`u{1F326}`u{FE0F}" } else { "" }
    $wind           = if ($isPowerShell7) { "`u{1F32C}`u{FE0F}" } else { "" }
    $eye            = if ($isPowerShell7) { "`u{1F441}`u{FE0F}" } else { "" }
    $cloud          = if ($isPowerShell7) { "`u{2601}`u{FE0F}" } else { "" }
    $thermometer    = if ($isPowerShell7) { "`u{1F321}`u{FE0F}" } else { "" }
    $droplet        = if ($isPowerShell7) { "`u{1F4A7}" } else { "" }
    $barometer      = if ($isPowerShell7) { "`u{1F4CF}" } else { "" }
    $note           = if ($isPowerShell7) { "`u{1F4DD}" } else { "" }
    $sunrise        = if ($isPowerShell7) { "`u{1F305}" } else { "" }
    $sunset         = if ($isPowerShell7) { "`u{1F304}" } else { "" }
    $antenna        = if ($isPowerShell7) { "`u{1F4E1}" } else { "" }
    $mic            = if ($isPowerShell7) { "`u{1F5E3}`u{FE0F}" } else { "" }
    $headphones     = if ($isPowerShell7) { "`u{1F3A7}" } else { "" }
    $camera         = if ($isPowerShell7) { "`u{1F3A5}" } else { "" }
    $link           = if ($isPowerShell7) { "`u{1F517}" } else { "" }
    $hourglass      = if ($isPowerShell7) { "`u{23F3}" } else { "" }
    $radar          = if ($isPowerShell7) { "`u{1F4E1}" } else { "" }

    # Fetch raw METAR
    $metar = Get-METAR-TAF -ICAO $airportInfo.ICAO

    # Decode METAR into structured data
    $decodedMetar = ConvertFrom-METAR -metar $metar

    # Fetch current airport date/time
    $airportDateTime = Get-AirportDateTime -ICAO $airportInfo.ICAO

    # Fetch sunrise and sunset times
    $sunTimes = Get-AirportSunriseSunset -ICAO $airportInfo.ICAO

    # Fetch METAR last updated time
    $lastUpdatedTime = Get-METAR-LastUpdatedTime -ICAO $airportInfo.ICAO

    # Display welcome message with a simple border
    Write-Output "$airplane Welcome to $($airportInfo.'Airport Name')"
    Write-Output "    $location City:        $($airportInfo.City)"
    Write-Output "    $earth Country:     $($airportInfo.Country)"
    Write-Output "    $departure ICAO/IATA:   $($airportInfo.ICAO)/$($airportInfo.IATA)`n"

    Write-Output "$clock Current Date/Time:"
    Write-Output "    $airportDateTime`n"

    Write-Output "$weather Weather Information:"
    Write-Output "    $wind Wind:        $($decodedMetar.Wind)"
    Write-Output "    $eye Visibility:  $($decodedMetar.Visibility)"
    Write-Output "    $cloud Ceiling:     $($decodedMetar.Ceiling)"
    Write-Output "    $thermometer Temperature: $($decodedMetar.Temperature)"
    Write-Output "    $droplet Dew Point:   $($decodedMetar.DewPoint)"
    Write-Output "    $barometer Pressure:    $($decodedMetar.Pressure)"
    Write-Output "    $note Raw METAR:   $metar`n"

    # Display sunrise and sunset information if available
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
        if ($OpenRadar) {
            $radarUrl = "https://beta.flightaware.com/live/airport/$($airportInfo.ICAO)"
            Write-Output "    $radar Radar:  $radarUrl"
        }
        # Include webcam information if available
        if (-not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
            Write-Output "    $camera Webcam: $($airportInfo.'Webcam URL')"
        }
        Write-Output ""
    }

    # Display METAR source and last updated time
    Write-Output "$link Data Source: METAR data retrieved from https://metar.vatsim.net for $($airportInfo.ICAO)"
    Write-Output "    $hourglass Last Updated: $lastUpdatedTime ago`n"
}

# Function to start the media player with a given URL
Function Start-Player {
    param (
        [string]$url,
        [string]$player,
        [switch]$noVideo,
        [switch]$noAudio,
        [switch]$basicArgs,
        [int]$volume = 100
    )

    $playerArgs = switch ($player) {
        "VLC" {
            $vlcArgs = "`"$url`"" 
            if ($noVideo) { $vlcArgs += " --no-video" }
            if ($noAudio) { $vlcArgs += " --no-audio" }
            if ($IsWindows) {
                $vlcArgs += " --volume=$volume"
            } else {
                $vlcArgs += " --gain $($volume / 100) --demux=rawaud --quiet"
            }
            $vlcArgs
        }
        "MPV" {
            $mpvArgs = "`"$url`""
            if ($noVideo) { $mpvArgs += " --no-video" }
            if ($noAudio) { $mpvArgs += " --no-audio" }
            if ($basicArgs) { $mpvArgs += " --force-window=immediate --cache=yes --cache-pause=no --really-quiet" }
            $mpvArgs += " --volume=$volume"
            $mpvArgs
        }
        "Celluloid" {
            $cellArgs = "`"$url`""
            if ($noVideo) { $cellArgs += " --no-video" }
            if ($noAudio) { $cellArgs += " --no-audio" }
            if ($basicArgs) { $cellArgs += " --force-window=immediate --cache=yes --cache-pause=no --really-quiet" }
            $cellArgs += " --volume=$volume"
            $cellArgs
        }
        "SMPlayer" {
            $smArgs = "`"$url`""
            if ($noVideo) { $smArgs += " --no-video" }
            if ($noAudio) { $smArgs += " --no-audio" }
            if ($basicArgs) { $smArgs += " --really-quiet" }
            $smArgs += " --volume=$volume"
            $smArgs
        }
        "Potplayer" {
            $potplayerArgs = "`"$url`""
            if ($noVideo) { $potplayerArgs += "" } # Not possible with potplayer
            if ($noAudio) { $potplayerArgs += " /volume=0" }
            if ($basicArgs) { $potplayerArgs += " /new" }
            $potplayerArgs += " /volume=$volume"
            $potplayerArgs
        }
        "MPC-HC" {
            $mpchcArgs = "`"$url`""
            if ($noVideo) { $mpchcArgs += "" } # Not possible with MPC-HC
            if ($noAudio) { $mpchcArgs += " /mute" }
            if ($basicArgs) { $mpchcArgs += " /new" }
            $mpchcArgs += " /volume $volume"
            $mpchcArgs
        }
        "Cosmic" {
            $resolvedUrl = $url
            if ($url -match 'youtu(be)?\.com|youtu\.be') {
                try {
                    $resolvedUrl = (yt-dlp -f best -g $url) -join ''
                } catch {
                    Write-Warning "Failed to resolve YouTube URL with yt-dlp."
                }
            } elseif ($url -match '\.pls(\?|$)') {
                try {
                    $content = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
                    $fileLine = ($content -split "`n" | Where-Object { $_ -match '^File1=' } | Select-Object -First 1)
                    if ($fileLine) { $resolvedUrl = $fileLine -replace '^File1=', '' }
                } catch {
                    Write-Warning "Failed to resolve PLS URL: $url"
                }
            }
            # Cosmic Player does not currently offer flags to mute audio or
            # disable video. We simply pass the resolved URL and suppress the
            # player's own output using shell redirection to /dev/null.
            "`"$resolvedUrl`""
        }
    }

    $playerPath = Test-Player -player $player
    if ($player -eq "Cosmic") {
        # Use a shell to discard Cosmic Player output, mimicking
        # `cosmic-player <url> >/dev/null 2>&1`
        $shellCmd = "cosmic-player $playerArgs >/dev/null 2>&1"
        Start-Process -FilePath "/bin/sh" -ArgumentList "-c", $shellCmd -NoNewWindow
    } else {
        Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow
    }
}

# Determine the player to use
$Player = Resolve-Player -explicitPlayer $Player

# Check if the selected player is installed
Test-Player -player $Player | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseCsv = Join-Path $scriptDir 'atc_sources.csv'
$liveCsv = Join-Path $scriptDir 'liveatc_sources.csv'
$favoritesJson = Join-Path $scriptDir 'favorites.json'
$maxFavorites = 10

if (-not $UseBaseCSV -and (Test-Path $liveCsv)) {
    Write-Host "Using live sources CSV: $liveCsv"
    $csvPath = $liveCsv
} else {
    Write-Host "Using base sources CSV: $baseCsv"
    $csvPath = $baseCsv
}


$lofiMusicUrl = $LofiSource
$atcSources = Import-ATCSources -csvPath $csvPath
$favorites = Get-Favorites -path $favoritesJson

$selectedATC = $null
if ($ICAO) {
    $icaoMatches = $atcSources | Where-Object { $_.ICAO -eq $ICAO }
    if (-not $icaoMatches) {
        Write-Error "No ATC stream found for ICAO $ICAO"
        exit
    }

    if ($icaoMatches.Count -eq 1 -or $RandomATC) {
        $match = if ($RandomATC -and $icaoMatches.Count -gt 1) { Get-Random -InputObject $icaoMatches } else { $icaoMatches[0] }
    } else {
        $channels = $icaoMatches | ForEach-Object {
            $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
            "{0}{1}" -f $_.'Channel Description', $webcamIndicator
        } | Sort-Object -Unique
        $chanSel = if ($UseFZF) {
            Select-ItemFZF -prompt "Select a channel for ${ICAO}" -items $channels
        } else {
            Select-Item -prompt "Select a channel for ${ICAO}:" -items $channels
        }
        $chanClean = $chanSel -replace '\s\[Webcam available\]', ''
        $match = $icaoMatches | Where-Object { $_.'Channel Description' -eq $chanClean } | Select-Object -First 1
    }

    $selectedATC = @{
        StreamUrl   = $match.'Stream URL'
        WebcamUrl   = $match.'Webcam URL'
        AirportInfo = $match
    }
}

if (-not $selectedATC) {
    if ($RandomATC) {
        $selectedATC = Get-RandomATCStream -atcSources $atcSources
    } else {
        if ($UseFavorite) {
            $selectedATC = Select-FavoriteATC -favorites $favorites -atcSources $atcSources -UseFZF:$UseFZF
        }
        if (-not $selectedATC) {
            if ($UseFZF) {
                $selectedATC = Select-ATCStreamFZF -atcSources $atcSources
            } else {
                while (-not $selectedATC) {
                    $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
                    do {
                        $countries = @($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique)
                        $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items $countries -AllowBack
                        if ($null -eq $selectedCountry) { $selectedContinent = $null; break }
                        $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
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
Add-Favorite -path $favoritesJson -ICAO $selectedATC.AirportInfo.ICAO -Channel $selectedATC.AirportInfo.'Channel Description' -maxEntries $maxFavorites
if ($OpenRadar) { Open-Radar -ICAO $selectedATC.AirportInfo.ICAO }

# Output player info after the welcome message
if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Player"]) {
    Write-Verbose "Player selected by user: $Player"
} else {
    Write-Verbose "Default player selected: $Player"
}

if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) {
    Write-Verbose "Opening ATC stream: $selectedATCUrl"
    if ($selectedWebcamUrl) {
        Write-Verbose "Opening webcam stream: $selectedWebcamUrl"
    }
}

# Starting the ATC audio stream
Start-Player -url $selectedATCUrl -player $Player -noVideo -basicArgs -volume $ATCVolume

# Starting the Lofi music if not disabled
if (-not $NoLofiMusic) {
    if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) {
        Write-Verbose "Opening Lofi Girl stream: $lofiMusicUrl"
    }
    if ($PlayLofiGirlVideo) {
        Start-Player -url $lofiMusicUrl -player $Player -basicArgs -volume $LofiVolume
    } else {
        Start-Player -url $lofiMusicUrl -player $Player -noVideo -basicArgs -volume $LofiVolume
    }
}

# Starting the webcam stream if available
if ($IncludeWebcamIfAvailable -and $selectedWebcamUrl) {
    Start-Player -url $selectedWebcamUrl -player $Player -noAudio -basicArgs
}