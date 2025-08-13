# Function to fetch ATC sources from liveatc.net
Function Get-LiveATCSources {
    param (
        [string]$Url = "https://www.liveatc.net/search/?icao=EHAM"
    )
    try {
        # Extract ICAO from the URL
        $icaoFromUrl = $Url -replace ".*icao=([^&]+).*", '$1'

        # Fetch HTML
        $response    = Invoke-WebRequest -Uri $Url -UseBasicParsing
        $htmlContent = $response.Content

        # Parse for .pls links
        $atcSources      = @()
        $currentFeedName = ""
        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()
            if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feedName>[^<]+)</strong>') {
                $currentFeedName = $matches['feedName'].Trim()
            }
            elseif ($row -match '<a href="(?<url>[^"]+\.pls)"') {
                $atcSources += [PSCustomObject]@{
                    ICAO    = $icaoFromUrl
                    Channel = $currentFeedName
                    URL     = "https://www.liveatc.net" + $matches['url'].Trim()
                }
            }
        }

        return $atcSources
    }
    catch {
        Write-Error "Error fetching $($Url): $_"
        return @()
    }
}

# Figure out where the input CSV actually lives
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputCsv  = Join-Path $scriptDir '..\atc_sources.csv' | Resolve-Path -ErrorAction Stop
$csvDir    = Split-Path -Parent $inputCsv

# **Changed output filename here:**
$outputCsv = Join-Path $csvDir 'liveatc_sources.csv'

# Load input
$origRows = Import-Csv $inputCsv

# Build a lookup of Webcam URLs by ICAO+Channel
$webcamLookup = @{}
foreach ($row in $origRows) {
    $key = "{0}||{1}" -f $row.ICAO, $row.'Channel Description'
    if (-not $webcamLookup.ContainsKey($key) -and $row.'Webcam URL') {
        $webcamLookup[$key] = $row.'Webcam URL'
    }
}

# Fetch once per distinct ICAO
$icaoCache = @{}
$origRows |
  Select-Object -Expand ICAO -Unique |
  ForEach-Object {
    Write-Host "Fetching channels for $_…"
    $icaoCache[$_] = Get-LiveATCSources -Url "https://www.liveatc.net/search/?icao=$_"
  }

# Build output: one row per fetched source
$allResults = foreach ($icao in $icaoCache.Keys) {
    $meta = $origRows | Where-Object ICAO -eq $icao | Select-Object -First 1

    foreach ($src in $icaoCache[$icao]) {
        $key    = "{0}||{1}" -f $icao, $src.Channel
        $webcam = if ($webcamLookup.ContainsKey($key)) { $webcamLookup[$key] } else { "" }

        [PSCustomObject][ordered]@{
            Continent             = $meta.'Continent'
            Country               = $meta.'Country'
            City                  = $meta.'City'
            'State/Province'      = $meta.'State/Province'
            'Airport Name'        = $meta.'Airport Name'
            ICAO                  = $icao
            IATA                  = $meta.'IATA'
            'Channel Description' = $src.Channel
            'Stream URL'          = $src.URL
            'Webcam URL'          = $webcam
        }
    }
}

# Sort by Continent then ICAO, then export next to the atc_sources.csv
$allResults |
  Sort-Object Continent, ICAO |
  Export-Csv -Path $outputCsv -NoTypeInformation

Write-Host "`n New sources written to csv: $outputCsv"

