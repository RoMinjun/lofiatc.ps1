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
    }
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
} else {
    $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
    Write-Host "Selected continent: $selectedContinent" -ForegroundColor Green

    $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items (@($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique))
    Write-Host "Selected country: $selectedCountry" -ForegroundColor Green

    $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Write-Host "Selected ATC stream: $selectedATCUrl" -ForegroundColor Green
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