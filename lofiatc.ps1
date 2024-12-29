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

#>

param (
    [switch]$IncludeWebcamIfAvailable,
    [switch]$NoLofiMusic,
    [switch]$RandomATC,
    [switch]$PlayLofiGirlVideo
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

# Function to select an ATC stream
Function Select-ATCStream {
    param (
        [array]$atcSources,
        [string]$continent,
        [string]$country
    )

    Clear-Host
    # Filter ATC sources by selected continent and country
    $choices = $atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $continent.Trim().ToLower() -and $_.Country.Trim().ToLower() -eq $country.Trim().ToLower() }

    if ($choices.Count -eq 0) {
        Write-Error "No ATC streams available for the selected country."
        exit
    }

    Write-Host "Select an airport from ${country}:" -ForegroundColor Yellow
    # Get unique city and airport name combinations
    $airports = $choices | Select-Object @{Name="CityAirport";Expression={ "[{0}] {1}" -f $_.City, $_.'Airport Name' }} | Sort-Object -Property CityAirport -Unique
    $selectedAirport = Select-Item -prompt "Select an airport:" -items $airports.CityAirport
    # Filter choices by selected airport
    $airportChoices = $choices | Where-Object { "[{0}] {1}" -f $_.City, $_.'Airport Name' -eq $selectedAirport }

    if ($airportChoices.Count -gt 1) {
        Write-Host "Select a category for ${selectedAirport}:" -ForegroundColor Yellow
        # Get unique categories for the selected airport
        $categories = $airportChoices | Select-Object -ExpandProperty 'Channel Description' | Sort-Object -Property 'Channel Description' -Unique
        $selectedCategory = Select-Item -prompt "Select a category:" -items $categories
        # Filter choices by selected category
        $selectedStream = $airportChoices | Where-Object { $_.'Channel Description' -eq $selectedCategory }
    } else {
        $selectedStream = $airportChoices[0]
    }

    return @{
        StreamUrl = $selectedStream.'Stream URL'
        WebcamUrl = $selectedStream.'Webcam URL'
        AirportInfo = $selectedStream
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

# Function to fetch METAR and TAF data from the web
# Function Get-METAR-TAF {
#     param (
#         [string]$ICAO
#     )
#     $url = "https://metar-taf.com/$ICAO"
#     try {
#         $response = Invoke-WebRequest -Uri $url -UseBasicParsing
#         $metarDescription = if ($response.Content -match '<meta name="description" content="([^"]+)">') {
#             $matches[1]
#         }
#         return $metarDescription
#     } catch {
#         Write-Error "Failed to fetch METAR/TAF data for $ICAO."
#         return "METAR/TAF data unavailable."
#     }
# }
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
Function Decode-METAR {
    param (
        [string]$metar
    )

    # Initialize a hashtable for the decoded values
    $decoded = @{}

    # Match wind information, including gusts
    if ($metar -match "(?<windDir>\d{3})(?<windSpeed>\d{2})(G(?<gustSpeed>\d{2}))?KT") {
        $decoded["Wind"] = if ($matches.gustSpeed) {
            "$($matches.windDir)° at $($matches.windSpeed) knots, gusting to $($matches.gustSpeed) knots"
        } else {
            "$($matches.windDir)° at $($matches.windSpeed) knots"
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
        $decoded["Temperature"] = if ($matches.temp -eq "-00") { "0°C" } else { "$($matches.temp)°C" }
        $decoded["DewPoint"] = if ($matches.dew -eq "-00") { "0°C" } elseif ($matches.dew -like "M*") {
            "-" + ($matches.dew.Trim('M')) + "°C"
        } else {
            "$($matches.dew)°C"
        }
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


Function Get-AiportDateTime {
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

# Function to display welcome message
Function Display-Welcome {
    param (
        [object]$airportInfo
    )

    # Fetch raw METAR
    $metar = Get-METAR-TAF -ICAO $airportInfo.ICAO

    # Decode METAR into structured data
    $decodedMetar = Decode-METAR -metar $metar

    # Fetch current airport date/time
    $airportDateTime = Get-AiportDateTime -ICAO $airportInfo.ICAO

    # Display welcome message
    Write-Output "`nWelcome to $($airportInfo.'Airport Name')!"
    Write-Output "City: $($airportInfo.City), Country: $($airportInfo.Country)"
    Write-Output "ICAO: $($airportInfo.'ICAO')`n"

    # Display raw and decoded METAR
    Write-Output "Weather Info:"
    Write-Output "Wind: $($decodedMetar.Wind)"
    Write-Output "Visibility: $($decodedMetar.Visibility)"
    Write-Output "Ceiling: $($decodedMetar.Ceiling)"
    Write-Output "Temperature: $($decodedMetar.Temperature) | Dew Point: $($decodedMetar.DewPoint)"
    Write-Output "Pressure: $($decodedMetar.Pressure)"
    Write-Output "Raw: $metar`n"

    Write-Output "Channel: $($airportInfo.'Channel Description')"
    Write-Output "Current Date/Time: $airportDateTime"
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
    Write-Host "Selected random ATC stream: $selectedATCUrl" -ForegroundColor Green
    Display-Welcome -airportInfo $selectedATC.AirportInfo
} else {
    $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
    Write-Host "Selected continent: $selectedContinent" -ForegroundColor Green

    $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items (@($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique))
    Write-Host "Selected country: $selectedCountry" -ForegroundColor Green

    $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Host "Selected ATC stream: $selectedATCUrl" -ForegroundColor Green
    Display-Welcome -airportInfo $selectedATC.AirportInfo
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
