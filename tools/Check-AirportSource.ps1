[CmdletBinding()]
param (
    [Parameter()]
    [string] $CsvPath = "$PSScriptRoot\..\atc_sources.csv",

    [Parameter()]
    [string] $IcaoColumnName = "ICAO"
)

begin {
    $jsonUrl = "https://raw.githubusercontent.com/RoMinjun/Airports/refs/heads/master/airports.json"
    $missingIcaos = [System.Collections.Generic.List[string]]::new()
    $exitCode = 0

    # Resolve the relative CSV path to a full path for clear error messages
    try {
        $ResolvedCsvPath = (Resolve-Path -Path $CsvPath -ErrorAction Stop).Path
    } catch {
        Write-Error "Error: Could not find the CSV file at path: $CsvPath"
        Write-Error $_.Exception.Message
        exit 1
    }
}

process {
    try {
        Write-Host "Checking ICAOs from $ResolvedCsvPath..."
        if (-not (Test-Path -Path $ResolvedCsvPath)) {
            throw "CSV file not found at $ResolvedCsvPath"
        }
        
        $csvData = Import-Csv -Path $ResolvedCsvPath -ErrorAction Stop
        
        if (-not ($csvData | Get-Member -Name $IcaoColumnName)) {
            throw "Column '$IcaoColumnName' not found in the CSV file. Available columns are: $($csvData[0].PSObject.Properties.Name -join ', ')"
        }

        # Get unique, non-empty ICAO codes from the specified column
        $IcaoCodes = $csvData | Select-Object -ExpandProperty $IcaoColumnName -Unique | Where-Object { $_ -ne "" }
        
        if ($IcaoCodes.Count -eq 0) {
            throw "No ICAO codes found in the '$IcaoColumnName' column of $ResolvedCsvPath"
        }
        
        Write-Host "Found $($IcaoCodes.Count) unique ICAO codes in the CSV."

        Write-Host "Downloading airports.json from $jsonUrl..."
        
        $airportsData = Invoke-RestMethod -Uri $jsonUrl -ErrorAction Stop
        
        # Get all ICAO keys from the downloaded JSON
        $validIcaos = $airportsData.PSObject.Properties.Name
        
        Write-Host "Successfully downloaded and parsed $($validIcaos.Count) airport entries."

        foreach ($icao in $IcaoCodes) {
            # Use -cnotin for a case-sensitive comparison
            if ($icao -cnotin $validIcaos) {
                $missingIcaos.Add($icao)
            }
        }

        if ($missingIcaos.Count -eq 0) {
            Write-Host "Success: All $($IcaoCodes.Count) ICAO codes are valid and found in airports.json."
        } else {
            Write-Warning "Error: The following $($missingIcaos.Count) ICAO codes were not found in airports.json:"
            foreach ($missing in $missingIcaos) {
                Write-Warning "- $missing"
            }
            $exitCode = 1
        }
    }
    catch {
        Write-Error "An error occurred during the process:"
        Write-Error $_.Exception.Message
        $exitCode = 1
    }
}

end {
    exit $exitCode
}
