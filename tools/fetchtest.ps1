# Function to fetch ATC sources from liveatc.net
Function Get-LiveATCSources {
    param (
        [string]$url = "https://www.liveatc.net/search/?icao=EHAM"
    )
    try {
        # Extract the ICAO from the URL (e.g. "KJFK")
        $icaoFromUrl = $url -replace ".*icao=([^&]+).*", '$1'
        Write-Host "Using ICAO: $icaoFromUrl from URL"

        # Fetch the HTML content
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
        $htmlContent = $response.Content

        Write-Host "Fetched HTML content for ATC sources."

        # Parse the HTML to extract ATC sources
        $atcSources = @()
        $currentFeedName = ""

        # Split by <tr> tags so every table row is processed
        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()
            Write-Host "Processing ATC row: $row"

            if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<feedName>[^<]+)</strong>') {
                $currentFeedName = $matches['feedName'].Trim()
            }
            elseif ($row -match '<td[^>]*>\s*<a href="(?<url>[^"]+\.pls)"') {
                $atcSources += [PSCustomObject]@{
                    City    = ""
                    Airport = $icaoFromUrl  # Set dynamically from the URL
                    Channel = $currentFeedName
                    URL     = "https://www.liveatc.net" + $matches['url'].Trim()
                }
            }
        }
        return $atcSources
    }
    catch {
        Write-Error "Failed to fetch ATC sources. Exception: $_"
        return @()
    }
}

# Function to fetch airport details from liveatc.net
Function Get-AirportDetails {
    param (
        [string]$url = "https://www.liveatc.net/search/?icao=EHAM"
    )
    try {
        # Fetch the HTML content
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
        $htmlContent = $response.Content

        Write-Host "Fetched HTML content for airport details:"
        Write-Host $htmlContent

        $airportDetails = @()

        # Initialize variables for the expected rows:
        $icao = ""
        $iata = ""
        $airportName = ""
        $city = ""
        $province = ""
        $country = ""
        $continent = ""

        # Split the entire HTML content by <tr> tags
        $htmlContent -split '<tr>' | ForEach-Object {
            $row = $_.Trim()
            Write-Host "Processing details row: $row"

            # Row 1: ICAO, IATA, and Airport Name
            if ($row -match '<td[^>]*>\s*<strong>ICAO:\s*</strong>(?<icao>[^<]+)\s*<strong>&nbsp;&nbsp;IATA:\s*</strong>(?<iata>[^<]+)\s*&nbsp;&nbsp;<strong>Airport:</strong>\s*(?<airport>[^<]+)') {
                $icao = $matches['icao'].Trim()
                $iata = $matches['iata'].Trim()
                $airportName = $matches['airport'].Trim()
                Write-Host "Extracted ICAO: $icao, IATA: $iata, Airport: $airportName"
            }
            # Row 2: City and optional State/Province (if present)
            elseif ($row -match '<td[^>]*>\s*<strong>City:\s*</strong>\s*(?<city>[^<]+)(?:\s*<strong>&nbsp;&nbsp;State/Province:</strong>\s*(?<province>[^<]+))?') {
                $city = $matches['city'].Trim()
                if ($matches['province']) {
                    $province = $matches['province'].Trim()
                }
                else {
                    $province = ""
                }
                Write-Host "Extracted City: $city, Province: $province"
            }
            # Row 3: Country and Continent
            elseif ($row -match '<td[^>]*>\s*<strong>Country:\s*</strong>\s*(?<country>[^<]+)\s*<strong>&nbsp;&nbsp;Continent:</strong>\s*(?<continent>[^<]+)') {
                $country = $matches['country'].Trim()
                $continent = $matches['continent'].Trim()
                Write-Host "Extracted Country: $country, Continent: $continent"
            }
        }

        # Create a single airport details object if we have the required data
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
        Write-Error "Failed to fetch airport details. Exception: $_"
        return @()
    }
}

# Function to save combined data to a CSV file with the preferred column order
Function Save-CombinedDataToCSV {
    param (
        [array]$atcSources,
        [array]$airportDetails,
        [string]$csvPath = "liveatc_sources.csv"
    )
    try {
        $combinedData = @()
        foreach ($atcSource in $atcSources) {
            # Match the airport detail by ICAO
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
                }
            }
        }
        $combinedData | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "Combined data saved to $csvPath"
    }
    catch {
        Write-Error "Failed to save combined data to CSV. Exception: $_"
    }
}

# Fetch ATC sources and airport details, then save the combined data to CSV
$atcSources = Get-LiveATCSources
$airportDetails = Get-AirportDetails

if ($atcSources.Count -gt 0 -and $airportDetails.Count -gt 0) {
    Save-CombinedDataToCSV -atcSources $atcSources -airportDetails $airportDetails
}
else {
    Write-Host "No ATC sources or airport details found."
}
