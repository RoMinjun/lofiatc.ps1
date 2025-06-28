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
Select a random ATC stream from the list of sources.

.PARAMETER PlayLofiGirlVideo
Play the Lofi Girl video instead of just the audio.

.PARAMETER UseFZF
Use fzf for searching and filtering channels.

.PARAMETER Player
Specify the media player to use (VLC, Potplayer, MPC-HC or MPV). Default is VLC if there is no default set in system for mp4.

.PARAMETER ATCVolume
Volume level for the ATC stream. Default is 65.

.PARAMETER LofiVolume
Volume level for the Lofi Girl stream. Default is 50.

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

#>

[CmdletBinding()]
param (
    [switch]$IncludeWebcamIfAvailable,
    [switch]$NoLofiMusic,
    [switch]$RandomATC,
    [switch]$PlayLofiGirlVideo,
    [switch]$UseFZF,
    [ValidateSet("VLC", "MPV", "Potplayer", "MPC-HC")]
    [string]$Player,
    [int]$ATCVolume = 65,
    [int]$LofiVolume = 50
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
    } else {
        # If no player is specified, check the system default for .mp4
        $defaultApp = Get-DefaultAppForMP4

        # Match default app to known players
        switch ($defaultApp) {
            "vlc.exe"       { return "VLC" }
            "mpv.exe"       { return "MPV" }
            "PotPlayerMini64.exe" { return "Potplayer" }
            "mpc-hc64.exe"  { return "MPC-HC" }
            default         { return "VLC" }  # Fallback to VLC if no match is found
        }
    }
}

# Function to check if the selected player is available
Function Test-Player {
    param (
        [string]$player
    )

    $command = switch ($player) {
        "VLC" { "vlc.exe" }
        "MPV" { "mpv.com" }
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

# Function to select an item from a list
Function Select-Item {
    param (
        [string]$prompt,
        [array]$items
    )

    Clear-Host
    Write-Host $prompt -ForegroundColor Yellow
    $i = 1
    foreach ($item in $items) {
        Write-Host "$i. $item"
        $i++ 
    }

    $userChoice = Read-Host "Enter the number of your choice"
    if ($userChoice -match "^\d+$") {
        $index = [int]$userChoice - 1
        if ($index -ge 0 -and $index -lt $items.Count) {
            return $items[$index].Trim()
        } else {
            Write-Host "Error: Selected number is out of range." -ForegroundColor Red
        }
    } else {
        Write-Host "Error: Invalid input. Please enter a number." -ForegroundColor Red
    }

    Write-Error "Invalid selection. Please restart the script and try again."
    exit
}

# Function to select an item using fzf
Function Select-ItemFZF {
    param (
        [string]$prompt,
        [array]$items
    )

    $selectedItem = $items | fzf --prompt "$prompt> " --ignore-case --exact
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

    Clear-Host
    # Filter ATC sources by selected continent and country
    $choices = $atcSources | Where-Object {
        $_.Continent.Trim().ToLower() -eq $continent.Trim().ToLower() -and
        $_.Country.Trim().ToLower() -eq $country.Trim().ToLower()
    }

    if ($choices.Count -eq 0) {
        Write-Error "No ATC streams available for the selected country."
        exit
    }

    # Dynamic prompt for airport selection
    Write-Host "Select an airport from ${country}:" -ForegroundColor Yellow

    # Group by city and airport name, and check if any channel for that airport has a webcam
    $airports = $choices | Group-Object -Property City, 'Airport Name' | ForEach-Object {
        # Extract city and airport name
        $city = $_.Group[0].City
        $airportName = $_.Group[0].'Airport Name'

        # Check if any channel under this airport has a webcam
        $hasWebcam = $_.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.'Webcam URL') } | Measure-Object
        $webcamIndicator = if ($hasWebcam.Count -gt 0) { "[Webcam available]" } else { "" }

        # Return formatted airport entry
        "[{0}] {1} {2}" -f $city, $airportName, $webcamIndicator
    } | Sort-Object

    # Let the user select an airport
    $selectedAirport = Select-Item -prompt "Select an airport from ${country}:" -items $airports

    # Filter choices by selected airport
    $airportChoices = $choices | Where-Object {
        "[{0}] {1}" -f $_.City, $_.'Airport Name' -eq ($selectedAirport -replace '\s\[Webcam available\]', '') # Remove the [Webcam available] text for matching
    }

    if ($airportChoices.Count -gt 1) {
        # Extract airport name for dynamic channel selection prompt
        $airportNameForPrompt = ($selectedAirport -replace '\s\[Webcam available\]', '')

        # Dynamic prompt for channel selection
        Write-Host "Select a channel for ${airportNameForPrompt}:" -ForegroundColor Yellow

        # Get unique channel descriptions for the selected airport, with webcam indicators
        $channels = $airportChoices | ForEach-Object {
            $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) {
                " [Webcam available]"
            } else {
                ""
            }
            "{0}{1}" -f $_.'Channel Description', $webcamIndicator
        } | Sort-Object -Unique

        # Let the user select a channel
        $selectedChannel = Select-Item -prompt "Select a channel for ${airportNameForPrompt}:" -items $channels
        # Remove the [Webcam available] indicator from the selected channel for matching
        $selectedChannelClean = $selectedChannel -replace '\s\[Webcam available\]', ''

        # Filter choices by selected channel
        $selectedStream = $airportChoices | Where-Object { $_.'Channel Description' -eq $selectedChannelClean }
    } else {
        $selectedStream = $airportChoices[0]
    }

    return @{
        StreamUrl = $selectedStream.'Stream URL'
        WebcamUrl = $selectedStream.'Webcam URL'
        AirportInfo = $selectedStream
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
        # Add webcam availability only if Webcam URL is present
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) {
            " [Webcam available]"
        } else {
            ""
        }

        "[{0}, {1}] {2} ({4}/{5}) | {3}{6}" -f $_.City, $_.'Country', $_.'Airport Name', $_.'Channel Description', $_.'ICAO', $_.'IATA', $webcamInfo
    }

    # Use fzf for user selection
    $selectedChoice = Select-ItemFZF -prompt "Select an ATC stream" -items $choices

    $selectedStream = $atcSources | Where-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) {
            " [Webcam available]" 
        } else {
            "" 
        }

        # Match based on the formatted fzf entry
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
        [object]$airportInfo
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
    $header = "$airplane Welcome to $($airportInfo.'Airport Name')"
    $border = '═' * $header.Length
    Write-Host "`n$border" -ForegroundColor Yellow
    Write-Host $header -ForegroundColor Yellow
    Write-Host $border -ForegroundColor Yellow
    Write-Host ""        
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

    # Include webcam information if available
    if (-not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
        Write-Output "$camera Webcam:"
        Write-Output "    $($airportInfo.'Webcam URL')`n"
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
            $vlcArgs += " --volume=$volume"
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
    }

    $playerPath = Test-Player -player $player
    Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow
}

# Determine the player to use
$Player = Resolve-Player -explicitPlayer $Player

# Check if the selected player is installed
Test-Player -player $Player | Out-Null

$lofiMusicUrl = "https://www.youtube.com/watch?v=jfKfPfyJRdk"
$csvPath = "atc_sources.csv"
$atcSources = Import-ATCSources -csvPath $csvPath

if ($RandomATC) {
    $selectedATC = Get-RandomATCStream -atcSources $atcSources
    $selectedATCUrl = $selectedATC.StreamUrl    
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Welcome -airportInfo $selectedATC.AirportInfo

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
} else {
    if ($UseFZF) {
        $selectedATC = Select-ATCStreamFZF -atcSources $atcSources
    } else {
        $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)

        $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items (@($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique))

        $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
    }
    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Welcome -airportInfo $selectedATC.AirportInfo

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