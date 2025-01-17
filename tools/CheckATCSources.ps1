param (
    [switch]$Failed
)

# Path to the local CSV file
$csvPath = "..\atc_sources.csv"

# Check if the CSV file exists
if (-Not (Test-Path -Path $csvPath)) {
    Write-Host "CSV file not found: $csvPath" -ForegroundColor Red
    exit
}

# Load the CSV file
try {
    Write-Host "Loading CSV file..." -ForegroundColor Yellow
    $csvData = Import-Csv -Path $csvPath
    Write-Host "CSV file successfully loaded." -ForegroundColor Green
} catch {
    Write-Host "Error loading the CSV file. Please check the file path: $csvPath" -ForegroundColor Red
    exit
}

# Check the 'Stream URL' and 'Webcam URL' columns
Write-Host "Checking links in the CSV file..." -ForegroundColor Yellow
$results = @()

foreach ($row in $csvData) {
    # Initialize variables
    $streamUrl = $null
    $webcamUrl = $null
    $streamStatus = "N/A"
    $webcamStatus = "N/A"

    # Check the Stream URL
    if ($row.'Stream URL') {
        $streamUrl = $row.'Stream URL'
        try {
            Invoke-WebRequest -Uri $streamUrl -Method Head -TimeoutSec 20 -ErrorAction Stop | Out-Null
            $streamStatus = "OK"
        } catch {
            $streamStatus = "[FAILED]"
        }
    }

    # Check the Webcam URL
    if ($row.'Webcam URL') {
        $webcamUrl = $row.'Webcam URL'
        try {
            Invoke-WebRequest -Uri $webcamUrl -Method Head -TimeoutSec 20 -ErrorAction Stop | Out-Null
            $webcamStatus = "OK"
        } catch {
            $webcamStatus = "[FAILED]"
        }
    }

    # Add the results to the list
    $results += [PSCustomObject]@{
        ICAO        = $row.ICAO
        IATA        = $row.IATA
        StreamURL   = $streamUrl
        StreamStatus = $streamStatus
        WebcamURL   = $webcamUrl
        WebcamStatus = $webcamStatus
    }
}

# Filter results based on the -Failed parameter
if ($Failed) {
    Write-Host "`nShowing only failed links:" -ForegroundColor Red
    $failedResults = $results | Where-Object { $_.StreamStatus -eq "[FAILED]" -or $_.WebcamStatus -eq "[FAILED]" }
    if ($failedResults) {
        $failedResults | Format-Table -AutoSize
    } else {
        Write-Host "No failed links found." -ForegroundColor Green
    }
} else {
    Write-Host "`nShowing all links (OK and FAILED):" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
}
