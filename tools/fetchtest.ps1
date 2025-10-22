param(
    [Parameter(Mandatory = $true)]
    [string[]]$ICAO,
    [string]$OutCsv = "fetched_sources.csv"
)

# Normalize ICAO input: split on commas/whitespace, trim, uppercase, unique
$icaoList =
    $ICAO
    | ForEach-Object { ($_ -split '[,\s]+') }
    | Where-Object { $_ -and $_.Trim() -ne '' }
    | ForEach-Object { $_.Trim().ToUpper() }
    | Select-Object -Unique

if (-not $icaoList -or $icaoList.Count -eq 0) {
    Write-Error "No valid ICAO codes provided."
    exit 1
}

# Function to fetch ATC sources from liveatc.net for a single ICAO
Function Get-LiveATCSources {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Icao
    )
    $url = "https://www.liveatc.net/search/?icao=$Icao"
    try {
        Write-Host "Fetching ATC sources for $Icao ($url)..."
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
        $htmlContent = $response.Content

        $atcSources = @()
        $currentFeedName = ""

        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()

            if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feedName>[^<]+)</strong>') {
                $currentFeedName = $matches['feedName'].Trim()
            }
            elseif ($row -match '<td[^>]*>\s*<a href="(?<url>[^"]+\.pls)"') {
                $atcSources += [PSCustomObject]@{
                    City    = ""
                    Airport = $Icao
                    Channel = $currentFeedName
                    URL     = "https://www.liveatc.net" + $matches['url'].Trim()
                }
            }
        }
        return $atcSources
    }
    catch {
        Write-Error "[$Icao] Failed to fetch ATC sources. Exception: $_"
        return @()
    }
}

# Function to fetch airport details from liveatc.net for a single ICAO
Function Get-AirportDetails {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Icao
    )
    $url = "https://www.liveatc.net/search/?icao=$Icao"
    try {
        Write-Host "Fetching airport details for $Icao ($url)..."
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
        $htmlContent = $response.Content

        $airportDetails = @()

        $icao = ""
        $iata = ""
        $airportName = ""
        $city = ""
        $province = ""
        $country = ""
        $continent = ""

        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()

            if ($row -match '<td[^>]*>\s*<strong>ICAO:\s*</strong>(?<icao>[^<]+)\s*<strong>&nbsp;&nbsp;IATA:\s*</strong>(?<iata>[^<]+)\s*&nbsp;&nbsp;<strong>Airport:</strong>\s*(?<airport>[^<]+)') {
                $icao = $matches['icao'].Trim()
                $iata = $matches['iata'].Trim()
                $airportName = $matches['airport'].Trim()
            }
            elseif ($row -match '<td[^>]*>\s*<strong>City:\s*</strong>\s*(?<city>[^<]+)(?:\s*<strong>&nbsp;&nbsp;State/Province:</strong>\s*(?<province>[^<]+))?') {
                $city = $matches['city'].Trim()
                $province = if ($matches['province']) { $matches['province'].Trim() } else { "" }
            }
            elseif ($row -match '<td[^>]*>\s*<strong>Country:\s*</strong>\s*(?<country>[^<]+)\s*<strong>&nbsp;&nbsp;Continent:</strong>\s*(?<continent>[^<]+)') {
                $country = $matches['country'].Trim()
                $continent = $matches['continent'].Trim()
            }
        }

        if ($icao -and $iata -and $airportName) {
            $airportDetails += [PSCustomObject]@{
                ICAO      = $icao
                IATA      = $iata
                Airport   = $airportName
                City      = $city
                Province  = $province
                Country   = $country
                Continent = $continent
            }
        }
        return $airportDetails
    }
    catch {
        Write-Error "[$Icao] Failed to fetch airport details. Exception: $_"
        return @()
    }
}

# Function to save combined data to a CSV file with the preferred column order
Function Save-CombinedDataToCSV {
    param (
        [array]$atcSources,
        [array]$airportDetails,
        [string]$csvPath = "fetched_sources.csv"
    )
    try {
        $combinedData = @()
        foreach ($atcSource in $atcSources) {
            $airportDetail = $airportDetails | Where-Object { $_.ICAO -eq $atcSource.Airport }
            if ($airportDetail) {
                $combinedData += [PSCustomObject][ordered]@{
                    Continent             = $airportDetail.Continent
                    Country               = $airportDetail.Country
                    City                  = $airportDetail.City
                    Province              = $airportDetail.Province
                    'Airport Name'        = $airportDetail.Airport
                    ICAO                  = $airportDetail.ICAO
                    IATA                  = $airportDetail.IATA
                    'Channel Description' = $atcSource.Channel
                    'Stream URL'          = $atcSource.URL
                    'Webcam URL'          = ""
                    'NearbyICAOs'         = ""
                }
            }
            else {
                $combinedData += [PSCustomObject][ordered]@{
                    Continent             = ""
                    Country               = ""
                    City                  = ""
                    Province              = ""
                    'Airport Name'        = $atcSource.Airport
                    ICAO                  = ""
                    IATA                  = ""
                    'Channel Description' = $atcSource.Channel
                    'Stream URL'          = $atcSource.URL
                    'Webcam URL'          = ""
                    'NearbyICAOs'         = ""
                }
            }
        }

        if ($combinedData.Count -gt 0) {
            $combinedData | Export-Csv -Path $csvPath -NoTypeInformation
            Write-Host "Combined data saved to $csvPath"
        }
        else {
            Write-Host "No data to write."
        }
    }
    catch {
        Write-Error "Failed to save combined data to CSV. Exception: $_"
    }
}

$allAtcSources   = @()
$allAirportInfos = @()

foreach ($code in $icaoList) {
    $sources = Get-LiveATCSources -Icao $code
    $details = Get-AirportDetails -Icao $code

    if ($sources) { $allAtcSources += $sources }
    if ($details) { $allAirportInfos += $details }
}

if ($allAtcSources.Count -gt 0) {
    Save-CombinedDataToCSV -atcSources $allAtcSources -airportDetails $allAirportInfos -csvPath $OutCsv
} else {
    Write-Host "No ATC sources found for the requested ICAO code(s): $($icaoList -join ', ')"
}
