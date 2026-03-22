param(
    # ValueFromRemainingArguments allows you to pass space-separated codes easily
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$ICAO,

    [Parameter()]
    [string]$OutCsv = "fetched_sources.csv"
)

# Normalize ICAO input: split on commas/whitespace, trim, uppercase, unique
$icaoList =
    $ICAO | ForEach-Object { ($_ -split '[,\s]+') } |
    Where-Object { $_ -and $_.Trim() -ne '' } |
    ForEach-Object { $_.Trim().ToUpper() } |
    Select-Object -Unique

if (-not $icaoList -or $icaoList.Count -eq 0) {
    Write-Error "No valid ICAO codes provided."
    exit 1
}

# --- NEW: Function to check if FlareSolverr is alive ---
Function Test-FlareSolverrConnection {
    $baseUrl = "http://localhost:8191/"
    try {
        Write-Host "Checking connection to FlareSolverr..." -NoNewline
        $response = Invoke-RestMethod -Uri $baseUrl -Method Get -TimeoutSec 5 -ErrorAction Stop
        
        # FlareSolverr usually returns a JSON with a 'msg' property saying it's ready
        if ($response.msg -match "FlareSolverr") {
            Write-Host " OK! (Version: $($response.version))" -ForegroundColor Green
            return $true
        }
        
        Write-Host " Failed! Unexpected response." -ForegroundColor Red
        return $false
    }
    catch {
        Write-Host " Failed!" -ForegroundColor Red
        return $false
    }
}

# Function to request HTML through FlareSolverr
Function Get-HtmlViaFlareSolverr {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl
    )
    
    $flareSolverrUrl = "http://localhost:8191/v1"
    
    $payload = @{
        cmd = "request.get"
        url = $TargetUrl
        maxTimeout = 60000
    } | ConvertTo-Json -Depth 2

    try {
        Write-Host "Asking FlareSolverr to fetch: $TargetUrl"
        $response = Invoke-RestMethod -Uri $flareSolverrUrl `
                                      -Method Post `
                                      -Body $payload `
                                      -ContentType "application/json" `
                                      -TimeoutSec 120

        if ($response.solution.response) {
            return $response.solution.response
        } else {
            Write-Error "FlareSolverr returned a response, but no HTML was found."
            return $null
        }
    }
    catch {
        Write-Error "Failed to fetch via FlareSolverr. Exception: $_"
        return $null
    }
}

# Function to parse ATC sources from raw HTML
Function Parse-LiveATCSources {
    param(
        [Parameter(Mandatory = $true)][string]$HtmlContent,
        [Parameter(Mandatory = $true)][string]$Icao
    )
    try {
        $atcSources = @()
        $currentFeedName = ""

        $HtmlContent -split '<tr>' | ForEach-Object {
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
        Write-Error "[$Icao] Failed to parse ATC sources. Exception: $_"
        return @()
    }
}

# Function to parse airport details from raw HTML
Function Parse-AirportDetails {
    param(
        [Parameter(Mandatory = $true)][string]$HtmlContent
    )
    try {
        $airportDetails = @()
        $icao = ""; $iata = ""; $airportName = ""; $city = ""
        $province = ""; $country = ""; $continent = ""

        $HtmlContent -split '<tr>' | ForEach-Object {
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
        Write-Error "Failed to parse airport details. Exception: $_"
        return @()
    }
}

# Function to save combined data to a CSV file
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


# Run the health check before proceeding
if (-not (Test-FlareSolverrConnection)) {
    Write-Warning "FlareSolverr is not running or unreachable at http://localhost:8191/."
    Write-Warning "Please ensure the FlareSolverr Docker container or background process is active."
    exit 1
}

$allAtcSources   = @()
$allAirportInfos = @()

foreach ($code in $icaoList) {
    $url = "https://www.liveatc.net/search/?icao=$code"
    
    # Fetch HTML once via FlareSolverr
    $rawHtml = Get-HtmlViaFlareSolverr -TargetUrl $url
    
    if ($null -ne $rawHtml) {
        # Parse the single payload for both datasets
        $sources = Parse-LiveATCSources -HtmlContent $rawHtml -Icao $code
        $details = Parse-AirportDetails -HtmlContent $rawHtml
        
        if ($sources) { $allAtcSources += $sources }
        if ($details) { $allAirportInfos += $details }
    }
}

if ($allAtcSources.Count -gt 0) {
    Save-CombinedDataToCSV -atcSources $allAtcSources -airportDetails $allAirportInfos -csvPath $OutCsv
} else {
    Write-Host "No ATC sources found for the requested ICAO code(s): $($icaoList -join ', ')"
}
