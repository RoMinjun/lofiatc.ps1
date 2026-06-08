# Functions dot-sourced by lofiatc.ps1. Keep script-scoped state in the entrypoint.
Function Get-Favorite {
    param([string]$path)

    if (-not (Test-Path $path)) {
        return @()
    }

    try {
        $data = Get-Content -Path $path -Raw | ConvertFrom-Json
    }
    catch {
        return @()
    }

    if ($null -eq $data) {
        return @()
    }

    $items = @($data)

    if ($items.Count -eq 1 -and $items[0] -is [string]) {
        return @()
    }

    foreach ($f in $items) {
        if (-not $f.PSObject.Properties['ICAO'] -or -not $f.PSObject.Properties['Channel']) {
            return @()
        }

        if (-not $f.PSObject.Properties['Count']) {
            $f | Add-Member -Name Count -Value 1 -MemberType NoteProperty
        }

        if (-not $f.PSObject.Properties['LastUsed']) {
            $f | Add-Member -Name LastUsed -Value (Get-Date) -MemberType NoteProperty
        }
    }

    return $items
}

# Function to save favorites back to the JSON file
Function Save-Favorite {
    param([array]$favorites, [string]$path)

    $items = @($favorites)

    if ($items.Count -eq 0) {
        '[]' | Set-Content -Path $path
        return
    }

    $items | ConvertTo-Json -Depth 5 | Set-Content -Path $path
}

# Function to add or update a favorite entry
Function Add-Favorite {
    param(
        [string]$path,
        [string]$ICAO,
        [string]$Channel,
        [int]$maxEntries = 10
    )

    $favorites = Get-Favorite -path $path
    $existing = $favorites | Where-Object { $_.ICAO -eq $ICAO -and $_.Channel -eq $Channel }
    if ($existing) {
        $existing.Count++
        $existing.LastUsed = Get-Date
        $favorites = $favorites | Where-Object { !(($_.ICAO -eq $ICAO) -and ($_.Channel -eq $Channel)) }
        $favorites = , $existing + $favorites
    }
    else {
        $newEntry = [pscustomobject]@{
            ICAO     = $ICAO
            Channel  = $Channel
            Count    = 1
            LastUsed = Get-Date
        }
        $favorites = , $newEntry + $favorites
    }
    $favorites = $favorites | Sort-Object -Property @{Expression = 'Count'; Descending = $true }, @{Expression = 'LastUsed'; Descending = $true }
    if ($favorites.Count -gt $maxEntries) { $favorites = $favorites[0..($maxEntries - 1)] }
    Save-Favorite -favorites $favorites -path $path
}

# Function to remove a favorite entry
Function Remove-Favorite {
    param(
        [string]$path,
        [string]$ICAO,
        [string]$Channel
    )

    $favorites = @(Get-Favorite -path $path)

    if ($favorites.Count -eq 0) {
        Save-Favorite -favorites @() -path $path
        return $false
    }

    $updated = @(
        $favorites | Where-Object {
            !(($_.ICAO -eq $ICAO) -and ($_.Channel -eq $Channel))
        }
    )

    $removed = $updated.Count -ne $favorites.Count

    Save-Favorite -favorites $updated -path $path

    return $removed
}

# Function to open the FlightAware radar page for a given ICAO code
Function Select-FavoriteATC {
    param(
        [array]$favorites,
        [array]$atcSources,
        [switch]$UseFZF
    )

    $favEntries = foreach ($fav in $favorites) {
        if ($fav.Channel -eq '__AIRPORT__') {
            $airportEntries = @($atcSources | Where-Object { $_.ICAO -eq $fav.ICAO })

            foreach ($entry in $airportEntries) {
                [pscustomobject]@{
                    Display = "[{0}] {1} - {2} [Airport favorite] ({3})" -f $entry.ICAO, $entry.'Airport Name', $entry.'Channel Description', $fav.Count
                    Entry   = $entry
                }
            }
        }
        else {
            $entry = $atcSources | Where-Object {
                $_.ICAO -eq $fav.ICAO -and $_.'Channel Description' -eq $fav.Channel
            } | Select-Object -First 1

            if ($entry) {
                [pscustomobject]@{
                    Display = "[{0}] {1} - {2} ({3})" -f $entry.ICAO, $entry.'Airport Name', $entry.'Channel Description', $fav.Count
                    Entry   = $entry
                }
            }
        }
    }

    if (-not $favEntries -or $favEntries.Count -eq 0) {
        return $null 
    }

    $labels = $favEntries.Display
    $sel = if ($UseFZF) { 
        Select-ItemFZF -prompt 'Select a favorite' -items $labels
    } else { 
        Select-Item -prompt 'Select a favorite:' -items $labels
    }
    if ($sel) {
        $fav = $favEntries | Where-Object { $_.Display -eq $sel }
        return @{
            StreamUrl   = $fav.Entry.'Stream URL'
            WebcamUrl   = $fav.Entry.'Webcam URL'
            AirportInfo = $fav.Entry
        }
    }
    else { 
        return $null
    }
}