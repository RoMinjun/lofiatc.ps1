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

#>

param (
    [switch]$IncludeWebcamIfAvailable,
    [switch]$NoLofiMusic,
    [switch]$RandomATC,
    [switch]$PlayLofiGirlVideo,
    [switch]$UseFZF
)

# Function to check if VLC is available
Function Test-VLC {
    if (-Not (Get-Command "vlc.exe" -ErrorAction SilentlyContinue)) {
        Write-Error "VLC is not installed or not available in PATH. Please install VLC Media Player to proceed."
        exit
    }
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
    $url = "https://metar-taf.com/$ICAO"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        $metarDescription = if ($response.Content -match '<meta name="description" content="([^"]+)">') {
            $matches[1]
        }

        # Extract the METAR string before the first period
        if ($metarDescription) {
            $rawMETAR = $metarDescription -split "\.", 2
            return $rawMETAR[0].Trim()
        } else {
            return "METAR/TAF data unavailable."
        }
    } catch {
        Write-Error "Failed to fetch METAR/TAF data for $ICAO."
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
            "$([int]$matches.windDir)° at $([int]$matches.windSpeed) knots, gusting to $([int]$matches.gustSpeed) knots"
        } else {
            "$([int]$matches.windDir)° at $([int]$matches.windSpeed) knots"
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
            "0°C" 
        } else { 
            "$([int]$matches.temp)°C" 
        }

        # Remove leading zeros for dew point
        $dewPoint = if ($matches.dew -eq "-00") { 
            "0°C" 
        } elseif ($matches.dew -like "M*") {
            "-$([int]($matches.dew.Trim('M')))°C"
        } else {
            "$([int]$matches.dew)°C"
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

# Function to fetch airport date/time
Function Get-AirportDateTime {
    param (
        [string]$ICAO
    )
    $url = "https://metar-taf.com/$ICAO"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        $dateAndTime = if ($response.Content -match '<div class="d-flex align-items-center m-auto text-nowrap px-3">\s*<span class="[^"]+">([^<]+)</span>\s*([^<]+)\s*</div>') {
            ($matches[1].Trim() + " " + $matches[2].Trim())
        }
        return $dateAndTime
    } catch {
        Write-Error "Date and time not found for $ICAO."
        return "Date/time data unavailable"
    }
}

# Function to fetch airport sunrise/sunset times
Function Get-AirportSunriseSunset {
    param (
        [string]$ICAO
    )
    $url = "https://metar-taf.com/$ICAO"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        $htmlContent = $response.Content

        # Extract Sunrise
        $sunrise = "Sunrise not found"
        if ($htmlContent -match '<small><b>Sunrise<\/b><br>\s*(\d{2}:\d{2})') {
            $sunrise = $matches[1]
        }

        # Extract Sunset
        $sunset = "Sunset not found"
        if ($htmlContent -match '<small><b>Sunset<\/b><br>\s*(\d{2}:\d{2})') {
            $sunset = $matches[1]
        }

        # Return result
        return @{
            Sunrise = $sunrise
            Sunset = $sunset
        }
    } catch {
        Write-Error "Failed to fetch data for $ICAO. Exception: $_"
        return @{
            Sunrise = "Data unavailable"
            Sunset = "Data unavailable"
        }
    }
}

# Function to fetch METAR last updated time
Function Get-METAR-LastUpdatedTime {
    param (
        [string]$ICAO
    )
    $url = "https://metar-taf.com/$ICAO"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        $htmlContent = $response.Content

        # Extract the "Last Updated" time from the correct div and span structure
        $lastUpdated = "Last updated time not found"
        if ($htmlContent -match '<div[^>]*class="rounded-right d-flex align-items-center py-1 py-lg-2 px-3 bg-darkblue border-left text-white">\s*<span[^>]*></span>\s*(?<lastUpdatedTime>[^<]+)') {
            $lastUpdated = $matches['lastUpdatedTime'].Trim()
        }

        return $lastUpdated
    } catch {
        Write-Error "Failed to fetch the last updated time for $ICAO. Exception: $_"
        return "Last updated time unavailable."
    }
}


# Function to display welcome message
Function Write-Welcome {
    param (
        [object]$airportInfo
    )

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

    # Display welcome message
    Write-Output "`n✈️ Welcome to $($airportInfo.'Airport Name'):"
    Write-Output "    📍 City:        $($airportInfo.City)"
    Write-Output "    🌍 Country:     $($airportInfo.Country)"
    Write-Output "    🛫 ICAO/IATA:   $($airportInfo.'ICAO')/$($airportInfo.'IATA')`n"

    Write-Output "🕒 Current Date/Time:"
    Write-Output "    $airportDateTime`n"

    Write-Output "🌦️ Weather Information:"
    Write-Output "    🌬️ Wind:        $($decodedMetar.Wind)"
    Write-Output "    👁️ Visibility:  $($decodedMetar.Visibility)"
    Write-Output "    ☁️ Ceiling:     $($decodedMetar.Ceiling)"
    Write-Output "    🌡️ Temperature: $($decodedMetar.Temperature)"
    Write-Output "    💧 Dew Point:   $($decodedMetar.DewPoint)"
    Write-Output "    📏 Pressure:    $($decodedMetar.Pressure)"
    Write-Output "    📝 Raw METAR:   $metar`n"

    # Display sunrise and sunset information if available
    if ($sunTimes) {
        Write-Output "🌅 Sunrise/Sunset Times:"
        Write-Output "    🌅 Sunrise: $($sunTimes.Sunrise)"
        Write-Output "    🌄 Sunset:  $($sunTimes.Sunset)`n"
    }

    Write-Output "📡 Air Traffic Control:"
    Write-Output "    🗣️ Channel: $($airportInfo.'Channel Description')"
    Write-Output "    🎧 Stream:  $($airportInfo.'Stream URL')`n"

    # Include webcam information if available
    if (-not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
        Write-Output "🎥 Webcam:"
        Write-Output "    $($airportInfo.'Webcam URL')`n"
    }

    # Display METAR source and last updated time
    Write-Output "🔗 Data Source: METAR and TAF data retrieved from https://metar-taf.com/$($airportInfo.'ICAO')"
    Write-Output "    ⏰ Last Updated: $lastUpdatedTime ago`n"
}

# Function to start VLC with a given URL
Function Start-VLC {
    param (
        [string]$url,
        [switch]$noVideo,
        [switch]$noAudio
    )

    $vlcArgs = "`"$url`""
    if ($noVideo) {
        $vlcArgs += " --no-video"
    }
    if ($noAudio) {
        $vlcArgs += " --no-audio"
    }

    Start-Process vlc -ArgumentList $vlcArgs -NoNewWindow
}

# check if vlc is installed in PATH
Test-VLC

$lofiMusicUrl = "https://www.youtube.com/watch?v=jfKfPfyJRdk"
$csvPath = "atc_sources.csv"
$atcSources = Import-ATCSources -csvPath $csvPath

if ($RandomATC) {
    $selectedATC = Get-RandomATCStream -atcSources $atcSources
    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Welcome -airportInfo $selectedATC.AirportInfo
} else {
    if ($UseFZF) {
        $selectedATC = Select-ATCStreamFZF -atcSources $atcSources
    } else {
        $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
        Write-Host "Selected continent: $selectedContinent" -ForegroundColor Green

        $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items (@($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique))
        Write-Host "Selected country: $selectedCountry" -ForegroundColor Green

        $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
    }
    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Welcome -airportInfo $selectedATC.AirportInfo
}

# Starting the ATC audio stream
Start-VLC -url $selectedATCUrl -noVideo

# starting the lofi music if not disabled
if (-not $NoLofiMusic) {
    if ($PlayLofiGirlVideo) {
        Start-VLC -url $lofiMusicUrl
    } else {
        Start-VLC -url $lofiMusicUrl -noVideo
    }
}

# Starting the webcam stream if available
if ($IncludeWebcamIfAvailable -and $selectedWebcamUrl) {
    Start-VLC -url $selectedWebcamUrl -noAudio
}
