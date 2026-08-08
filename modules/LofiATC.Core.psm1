# Functions dot-sourced by lofiatc.ps1. Keep script-scoped state in the entrypoint.
Function Get-LofiATCGenreMap {
    return @{
        "Chillhop"      = "https://youtu.be/X4VbdwhkE10" # Lofi Girl original
        "Synthwave"     = "https://youtu.be/4xDzrJKXOOY" # Lofi Girl Synthwave
        "SynthAmbient"  = "https://youtu.be/GSfT7H87zq4" # Lofi Girl Synthwave Ambient
        "Sad"           = "https://youtu.be/CwPCy1GLS38" # Lofi Girl sad
        "Piano"         = "https://youtu.be/5qap5aOn9sA" # Lofi Girl Piano
        "Classical"     = "https://youtu.be/jXAEIWcGXwE" # Lofi Girl Classical
        "Jazz"          = "https://youtu.be/E2vONfzoyRI" # Lofi Girl Jazz
        "RelaxJazz"     = "https://youtu.be/A8jDx9TLMQc" # Lofi Girl Relax Jazz
        "SleepAmbient"  = "https://youtu.be/xORCbIptqcc" # Lofi Girl Sleep Ambient
        "DarkAmbient"   = "https://youtu.be/S_MOd40zlYU" # Lofi Girl Dark Ambient
        "Medieval"      = "https://youtu.be/IxPANmjPaek" # Lofi Girl Medieval
        "Asian"         = "https://youtu.be/1Tl2FtV06qo" # Lofi Girl Asian
        "SleepChill"    = "https://youtu.be/JD-kMIpDfnY" # Lofi Girl Sleep/Chill
        "Guitar"        = "https://youtu.be/E_XmwjgRLz8" # Lofi Girl Guitar
        "Pomodoro"      = "https://youtu.be/qGohtGC5Rtk" # Lofi Girl Pomodoro (25min timer with breaks)
    }
}

Function Initialize-LofiATCState {
    $script:OnWindows = $env:OS -eq 'Windows_NT'
    $script:AirportData = $null

    $script:IanaToWindowsMap = @{
        "Etc/UTC"                        = "UTC"
        "Europe/London"                  = "GMT Standard Time"
        "Europe/Dublin"                  = "GMT Standard Time"
        "Europe/Amsterdam"               = "W. Europe Standard Time"
        "Europe/Paris"                   = "Romance Standard Time"
        "Europe/Berlin"                  = "W. Europe Standard Time"
        "Europe/Madrid"                  = "Romance Standard Time"
        "Europe/Brussels"                = "Romance Standard Time"
        "Europe/Rome"                    = "W. Europe Standard Time"
        "Europe/Vienna"                  = "W. Europe Standard Time"
        "Europe/Prague"                  = "Central Europe Standard Time"
        "Europe/Moscow"                  = "Russian Standard Time"
        "Europe/Athens"                  = "GTB Standard Time"
        "Europe/Bucharest"               = "GTB Standard Time"
        "Africa/Cairo"                   = "Egypt Standard Time"
        "Africa/Johannesburg"            = "South Africa Standard Time"
        "Asia/Jerusalem"                 = "Israel Standard Time"
        "Asia/Dubai"                     = "Arabian Standard Time"
        "Asia/Tehran"                    = "Iran Standard Time"
        "Asia/Riyadh"                    = "Arab Standard Time"
        "Asia/Karachi"                   = "Pakistan Standard Time"
        "Asia/Kolkata"                   = "India Standard Time"
        "Asia/Dhaka"                     = "Bangladesh Standard Time"
        "Asia/Bangkok"                   = "SE Asia Standard Time"
        "Asia/Singapore"                 = "Singapore Standard Time"
        "Asia/Hong_Kong"                 = "China Standard Time"
        "Asia/Shanghai"                  = "China Standard Time"
        "Asia/Taipei"                    = "Taipei Standard Time"
        "Asia/Tokyo"                     = "Tokyo Standard Time"
        "Asia/Seoul"                     = "Korea Standard Time"
        "Australia/Perth"                = "W. Australia Standard Time"
        "Australia/Adelaide"             = "Cen. Australia Standard Time"
        "Australia/Sydney"               = "AUS Eastern Standard Time"
        "Pacific/Auckland"               = "New Zealand Standard Time"
        "America/Halifax"                = "Atlantic Standard Time"
        "America/St_Johns"               = "Newfoundland Standard Time"
        "America/Argentina/Buenos_Aires" = "Argentina Standard Time"
        "America/Sao_Paulo"              = "E. South America Standard Time"
        "America/New_York"               = "Eastern Standard Time"
        "America/Chicago"                = "Central Standard Time"
        "America/Denver"                 = "Mountain Standard Time"
        "America/Phoenix"                = "US Mountain Standard Time"
        "America/Los_Angeles"            = "Pacific Standard Time"
        "America/Anchorage"              = "Alaskan Standard Time"
        "Pacific/Honolulu"               = "Hawaiian Standard Time"
    }

    $script:CurrentATCProcess = $null
    $script:CurrentWebcamProcess = $null
    $script:CurrentLofiProcess = $null

    $script:CurrentATCVolume = $null
    $script:CurrentLofiVolume = $null
    $script:CurrentLofiTrackResult = $null
    $script:CurrentLofiTrackCheckedAt = $null
    $script:LastAnnouncedLofiTrack = $null
    $script:StableLofiTrack = $null
    $script:StableLofiTrackSource = $null
    $script:CurrentLofiOcrVideoUrl = $null
    $script:CurrentLofiOcrVideoSource = $null
    $script:CurrentLofiOcrVideoResolvedAt = $null
}

Function Get-LofiATCIgnoredConfigParameterNames {
    return @(
        'Verbose',
        'Debug',
        'ErrorAction',
        'WarningAction',
        'InformationAction',
        'ProgressAction',
        'ErrorVariable',
        'WarningVariable',
        'InformationVariable',
        'OutVariable',
        'OutBuffer',
        'PipelineVariable',
        'SaveConfig',
        'LoadConfig',
        'ConfigPath'
    )
}

Function Get-LofiATCUserDataPath {
    if ($env:LOFIATC_USER_DATA) {
        return $env:LOFIATC_USER_DATA
    }

    if ($env:APPDATA) {
        return (Join-Path $env:APPDATA 'lofiatc')
    }

    if ($env:XDG_CONFIG_HOME) {
        return (Join-Path $env:XDG_CONFIG_HOME 'lofiatc')
    }

    return (Join-Path $HOME '.config/lofiatc')
}

Function Resolve-LofiATCUserFilePath {
    param(
        [string]$FileName,
        [string]$ScriptDir
    )

    $userDataDir = Get-LofiATCUserDataPath
    $userPath = Join-Path $userDataDir $FileName
    $legacyPath = Join-Path $ScriptDir $FileName

    if (Test-Path $userPath) {
        return $userPath
    }

    if (Test-Path $legacyPath) {
        return $legacyPath
    }

    return $userPath
}

Function Initialize-LofiATCUserDataPath {
    $userDataDir = Get-LofiATCUserDataPath
    if (-not (Test-Path $userDataDir)) {
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    }

    return $userDataDir
}

Function Import-LofiATCConfig {
    param(
        [string]$ConfigPath,
        [hashtable]$BoundParameters
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Warning "Config file not found at $ConfigPath"
        return
    }

    $ignoredParameters = Get-LofiATCIgnoredConfigParameterNames
    $config = Get-Content -Path $ConfigPath | ConvertFrom-Json

    foreach ($prop in $config.PSObject.Properties) {
        $name = $prop.Name
        if ($name -in $ignoredParameters) {
            continue
        }

        if (-not $BoundParameters.ContainsKey($name) -and $null -ne $prop.Value -and $prop.Value -ne "") {
            Set-Variable -Name $name -Value $prop.Value -Scope 1
        }
    }

    Write-Information "Loaded config from $ConfigPath"
}

Function Export-LofiATCConfig {
    param(
        [string]$CommandPath,
        [string]$ConfigPath
    )

    $ignoredParameters = Get-LofiATCIgnoredConfigParameterNames
    $paramNames = (Get-Command $CommandPath).Parameters.Keys
    $config = @{}

    foreach ($name in $paramNames) {
        if ($name -in $ignoredParameters) {
            continue
        }

        $value = Get-Variable -Name $name -ValueOnly -Scope 1
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            $value = [bool]$value
        }

        if ($null -ne $value -and $value -ne "") {
            $config[$name] = $value
        }
    }

    $configDir = Split-Path -Parent $ConfigPath
    if ($configDir -and -not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $config | ConvertTo-Json | Set-Content -Path $ConfigPath
    Write-Information "Saved config to $ConfigPath"
}

Function Test-ConsoleKeyAvailable {
    return [console]::KeyAvailable
}

# Function to determine whether console key polling is safe in the current host/session
Function Test-InteractiveConsoleAvailable {
    try {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
            return $false
        }

        $null = [Console]::KeyAvailable
        return $true
    }
    catch {
        return $false
    }
}

# Function to read a key from the console, with an option to intercept (not display) the key press
Function Read-ConsoleKey {
    param(
        [switch]$Intercept
    )
    return [console]::ReadKey($Intercept)
}

# Function to check the default application for .mp4
Function Get-CurrentCoordinates {
    Write-Verbose "Attempting to load System.Device assembly..."
    $location = $null
    $AssemblyLoaded = $false

    try {
        Add-Type -AssemblyName System.Device -ErrorAction Stop
        $AssemblyLoaded = $true
        Write-Verbose "Successfully loaded System.Device assembly."
    }
    catch {
        Write-Verbose "Could not load System.Device assembly (this is normal on PowerShell Core or non-Windows OS)."
    }

    if ($AssemblyLoaded) {
        Write-Verbose "Attempting to get device location..."
        try {
            $GeoWatcher = New-Object System.Device.Location.GeoCoordinateWatcher
            $GeoWatcher.Start()

            Write-Verbose "Waiting 1 second for device watcher to initialize..."
            Start-Sleep -Seconds 1

            $startTime = Get-Date
            $timeoutSeconds = 10

            while ($GeoWatcher.Status -eq 'Initializing') {
                if ($GeoWatcher.Permission -eq 'Denied') {
                    break
                }
                if (((Get-Date) - $startTime).TotalSeconds -ge $timeoutSeconds) {
                    break
                }
                Start-Sleep -Milliseconds 100
            }

            if ($GeoWatcher.Permission -eq 'Denied') {
                Write-Warning 'Access Denied for device location.'
            }
            elseif ($GeoWatcher.Status -eq 'Ready') {
                Write-Verbose "Device location acquired."
                $loc = $GeoWatcher.Position.Location

                $location = [pscustomobject]@{
                    Latitude  = $loc.Latitude
                    Longitude = $loc.Longitude
                    Source    = 'Device'
                }
            }
            elseif ($GeoWatcher.Status -eq 'Initializing') {
                Write-Warning "Device location timed out after $($timeoutSeconds + 1) seconds."
                $GeoWatcher.Stop()
            }
            else {
                Write-Warning "Device location service failed. Status: $($GeoWatcher.Status)."
            }
        }
        catch { Write-Warning "An unexpected error occurred with the device location service. Error: $_" }
    }

    if (-not $location) {
        Write-Warning "Falling back to IP-based location."
        $location = Get-IPLocation
    }

    return $location
}

# Helper function for IP-based fallback
Function Get-IPLocation {
    try {
        $uri = "https://ipapi.co/json/"
        Write-Verbose "Attempting IP-based geolocation fallback..."
        $location = Invoke-RestMethod -Uri $uri -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop

        $hasLatitude = $location.PSObject.Properties['latitude'] -and $null -ne $location.latitude
        $hasLongitude = $location.PSObject.Properties['longitude'] -and $null -ne $location.longitude

        if ($hasLatitude -and $hasLongitude) {
            Write-Host "Using approximate location based on IP: $($location.city), $($location.country_name)." -ForegroundColor Yellow
            return [pscustomobject]@{
                Latitude  = [double]$location.latitude
                Longitude = [double]$location.longitude
                City      = $location.city
                Country   = $location.country_name
                Source    = 'IP'
            }
        }
        else {
            Write-Verbose "IP-based geolocation did not return coordinates."
            return $null
        }
    }
    catch {
        Write-Error "Failed to get location from IP geolocation service. $_"
        return $null
    }
}

# Function to determine the appropriate player based on user input, system defaults, and availability in PATH
Function Import-ATCSource {
    param (
        [string]$csvPath
    )

    if (-not (Test-Path $csvPath)) {
        throw "The ATC sources CSV file ($csvPath) was not found. Please create it before running the script."
    }

    $rows = Import-Csv -Path $csvPath

    if (-not $rows -or $rows.Count -eq 0) {
        throw "The ATC sources CSV file ($csvPath) is empty."
    }

    $requiredColumns = @(
        'ICAO',
        'Channel Description',
        'Stream URL'
    )

    $recommendedColumns = @(
        'Webcam URL',
        'NearbyICAOs'
    )

    $columns = @($rows[0].PSObject.Properties.Name)

    $missingRequired = @($requiredColumns | Where-Object { $_ -notin $columns })
    if ($missingRequired.Count -gt 0) {
        throw "The ATC sources CSV file is missing required column(s): $($missingRequired -join ', ')"
    }

    $missingRecommended = @($recommendedColumns | Where-Object { $_ -notin $columns })
    if ($missingRecommended.Count -gt 0) {
        Write-Verbose "ATC sources CSV is missing recommended column(s): $($missingRecommended -join ', ')"
    }

    return $rows
}

Function Open-Radar {
    param([string]$ICAO)

    $url = "https://beta.flightaware.com/live/airport/$ICAO"
    if ($script:OnWindows) { 
        Start-Process $url
    }
    elseif ($IsMacOS) {
        & open $url
    }
    else {
        & xdg-open $url
    }
}

# Select a favorite ATC stream from the favorites list, showing play counts and channel info, and return the stream details if selected
Function Select-Item {
    param (
        [string]$prompt,
        [array]$items,
        [switch]$AllowBack)

    while ($true) {
        Clear-Host
        Write-Host $prompt -ForegroundColor Yellow
        $i = 1
        foreach ($item in $items) {
            Write-Host "$i. $item"; $i++ 
        }
        if ($AllowBack) {
            Write-Host "0. Go Back" 
        }

        $userChoice = Read-Host "Enter the number of your choice"
        if ($AllowBack -and $userChoice -eq '0') {
            return $null 
        }

        if ($userChoice -match '^\d+$') {
            $index = [int]$userChoice - 1
            if ($index -ge 0 -and $index -lt $items.Count) { return $items[$index].Trim() }
        }

        Write-Error "Error: Invalid selection."
        Start-Sleep -Seconds 1
    }
}

# Function to use fzf for item selection, returning the selected item or exiting if no selection is made
Function Select-ItemFZF {
    param (
        [string]$prompt,
        [array]$items
    )

    $selectedItem = $items | fzf --prompt "$prompt> " --exact

    if ($selectedItem) {
        return $selectedItem.Trim()
    }

    throw "No selection made in fzf."
}

# Function to select an ATC stream based on continent, country, and optionally state/province, 
# with support for webcam availability indication and channel selection if multiple channels exist for the same airport
Function Select-ATCStream {
    param (
        [array]$atcSources, 
        [string]$continent, 
        [string]$country, 
        [string]$state
    )

    while ($true) {
        Clear-Host
        $choices = $atcSources | Where-Object {
            $_.Continent.Trim().ToLower() -eq $continent.Trim().ToLower() -and
            $_.Country.Trim().ToLower() -eq $country.Trim().ToLower() -and
            (
                -not $state -or (
                    -not [string]::IsNullOrWhiteSpace($_.'State/Province') -and
                    $_.'State/Province'.Trim().ToLower() -eq $state.Trim().ToLower()
                )
            )
        }

        if ($choices.Count -eq 0) { 
            Write-Error "No ATC streams available for the selected country."
            return $null 
        }

        $airports = $choices | Group-Object -Property City, 'Airport Name' | ForEach-Object {
            $city = $_.Group[0].City
            $airportName = $_.Group[0].'Airport Name'
            $hasWebcam = $_.Group | Where-Object { -not [string]::IsNullOrWhiteSpace($_.'Webcam URL') } | Measure-Object
            $webcamIndicator = if ($hasWebcam.Count -gt 0) { "[Webcam available]" } else { "" }
            "[{0}] {1} {2}" -f $city, $airportName, $webcamIndicator
        } | Sort-Object

        $airportSel = Select-Item -prompt "Select an airport from ${country}:" -items $airports -AllowBack
        if ($null -eq $airportSel) {
            return $null
        }

        $airportChoices = $choices | Where-Object {
            "[{0}] {1}" -f $_.City, $_.'Airport Name' -eq ($airportSel -replace '\s\[Webcam available\]', '')
        }

        while ($true) {
            if ($airportChoices.Count -gt 1) {
                $airportNameForPrompt = ($airportSel -replace '\s\[Webcam available\]', '')
                $channels = $airportChoices | ForEach-Object {
                    $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
                    "{0}{1}" -f $_.'Channel Description', $webcamIndicator
                } | Sort-Object -Unique
                $chanSel = Select-Item -prompt "Select a channel for ${airportNameForPrompt}:" -items $channels -AllowBack
                if ($null -eq $chanSel) { break }
                $chanClean = $chanSel -replace '\s\[Webcam available\]', ''
                $selected = $airportChoices | Where-Object { $_.'Channel Description' -eq $chanClean }
            }
            else { 
                $selected = $airportChoices[0]
            }

            if ($selected) {
                return @{
                    StreamUrl   = $selected.'Stream URL'
                    WebcamUrl   = $selected.'Webcam URL'
                    AirportInfo = $selected
                }
            }
        }
    }
}

# Function to select an ATC stream using fzf for filtering, showing webcam availability and channel info in the selection list
Function Select-ATCStreamFZF {
    param (
        [array]$atcSources
    )

    Clear-Host

    $choices = $atcSources | ForEach-Object {
        $webcamInfo = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL')) { " [Webcam available]" } else { "" }
        $state = $_.'State/Province'
        $location = if (-not [string]::IsNullOrWhiteSpace($state)) {
            "{0}, {1}, {2}" -f $_.City, $state, $_.'Country'
        }
        else {
            "{0}, {1}" -f $_.City, $_.'Country'
        }

        [pscustomobject]@{
            Display = "[{0}] {1} ({2}/{3}) | {4}{5}" -f $location, $_.'Airport Name', $_.'ICAO', $_.'IATA', $_.'Channel Description', $webcamInfo
            Entry   = $_
        }
    }

    $selectedChoice = Select-ItemFZF -prompt "Select an ATC stream" -items $choices.Display
    $match = $choices | Where-Object { $_.Display -eq $selectedChoice } | Select-Object -First 1

    if (-not $match) {
        throw "No matching ATC stream found for the selected fzf entry."
    }

    return @{
        StreamUrl   = $match.Entry.'Stream URL'
        WebcamUrl   = $match.Entry.'Webcam URL'
        AirportInfo = $match.Entry
    }
}

# Function to select a random ATC stream from the list of sources, optionally filtered by ICAO code if specified, and return the stream details
Function Get-RandomATCStream {
    param (
        [array]$atcSources
    )
    $randomIndex = Get-Random -Minimum 0 -Maximum $atcSources.Count
    $selectedStream = $atcSources[$randomIndex]
    return @{
        StreamUrl   = $selectedStream.'Stream URL'
        WebcamUrl   = $selectedStream.'Webcam URL'
        AirportInfo = $selectedStream
    }
}

Function Select-ATCStreamByICAO {
    param(
        [array]$AtcSources,
        [string]$ICAO,
        [Nullable[int]]$MapSelectedChannelIndex,
        [switch]$RandomATC,
        [switch]$UseFZF,
        [switch]$IncludeWebcamIfAvailable
    )

    $icaoMatches = @($AtcSources | Where-Object { $_.ICAO -eq $ICAO })
    if (-not $icaoMatches) {
        throw "No ATC stream found for ICAO $ICAO."
    }

    if ($null -ne $MapSelectedChannelIndex) {
        if ($MapSelectedChannelIndex -lt 0 -or $MapSelectedChannelIndex -ge $icaoMatches.Count) {
            throw "Invalid channel index returned from map for ICAO $ICAO."
        }

        $match = $icaoMatches[$MapSelectedChannelIndex]
    }
    elseif ($icaoMatches.Count -eq 1 -or $RandomATC) {
        $match = if ($RandomATC -and $icaoMatches.Count -gt 1) {
            Get-Random -InputObject $icaoMatches
        }
        else {
            $icaoMatches[0]
        }
    }
    else {
        $channels = $icaoMatches | ForEach-Object {
            $webcamIndicator = if (-not [string]::IsNullOrWhiteSpace($_.'Webcam URL') -and $IncludeWebcamIfAvailable) { " [Webcam available]" } else { "" }
            "{0}{1}" -f $_.'Channel Description', $webcamIndicator
        } | Sort-Object -Unique

        $chanSel = if ($UseFZF) {
            Select-ItemFZF -prompt "Select a channel for ${ICAO}" -items $channels
        }
        else {
            Select-Item -prompt "Select a channel for ${ICAO}:" -items $channels
        }

        $chanClean = $chanSel -replace '\s\[Webcam available\]', ''
        $match = $icaoMatches | Where-Object { $_.'Channel Description' -eq $chanClean } | Select-Object -First 1
    }

    if (-not $match) {
        throw "No matching ATC channel found for ICAO $ICAO."
    }

    return @{
        StreamUrl   = $match.'Stream URL'
        WebcamUrl   = $match.'Webcam URL'
        AirportInfo = $match
    }
}

Function Select-ATCStreamManually {
    param(
        [array]$AtcSources
    )

    $selectedATC = $null

    while (-not $selectedATC) {
        $selectedContinent = Select-Item -prompt "Select a continent:" -items ($AtcSources.Continent | Sort-Object -Unique)
        do {
            $countries = @($AtcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique)
            $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items $countries -AllowBack
            if ($null -eq $selectedCountry) {
                $selectedContinent = $null
                break
            }

            $states = @($AtcSources | Where-Object {
                    $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() -and
                    $_.Country.Trim().ToLower() -eq $selectedCountry.Trim().ToLower() -and
                    -not [string]::IsNullOrWhiteSpace($_.'State/Province')
                } | Select-Object -ExpandProperty 'State/Province' | Sort-Object -Unique)

            if ($states.Count -gt 0) {
                do {
                    $selectedState = Select-Item -prompt "Select a state or province from ${selectedCountry}:" -items $states -AllowBack
                    if ($null -eq $selectedState) {
                        $selectedCountry = $null
                        break
                    }

                    $selectedATC = Select-ATCStream -atcSources $AtcSources -continent $selectedContinent -country $selectedCountry -state $selectedState
                } while (-not $selectedATC -and $selectedCountry)

                if (-not $selectedCountry) {
                    continue
                }
            }
            else {
                $selectedATC = Select-ATCStream -atcSources $AtcSources -continent $selectedContinent -country $selectedCountry
            }
        } while (-not $selectedATC)
    }

    return $selectedATC
}

Function Resolve-SelectedATCStream {
    param(
        [array]$AtcSources,
        [array]$Favorites,
        [string]$CsvPath,
        [string]$ScriptDir,
        [string]$FavoritesPath,
        [string]$ICAO,
        [int]$NearbyRadius,
        [string]$Player,
        [int]$ATCVolume,
        [int]$LofiVolume,
        [string]$LofiMusicUrl,
        [switch]$Nearby,
        [switch]$ShowMap,
        [switch]$KeepOpen,
        [switch]$UseFZF,
        [switch]$UseFavorite,
        [switch]$RandomATC,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoWeather,
        [switch]$Dark,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [switch]$ShowLofiTrack
    )

    $currentUserLocation = $null

    if ($Nearby) {
        if ($ICAO) {
            Write-Host "-Nearby switch detected, ignoring -ICAO $ICAO." -ForegroundColor Yellow
            $ICAO = $null
        }

        $currentUserLocation = Get-CurrentCoordinates
        if (-not $currentUserLocation) {
            Write-Error "Could not determine your location. Please select manually."
        }
        else {
            $locationLabel = if ($currentUserLocation.Source -eq 'Device') {
                "your current device location"
            } else {
                "$($currentUserLocation.City), $($currentUserLocation.Country)"
            }

            Write-Host "Finding airports near $locationLabel..." -ForegroundColor Green

            $sortedAirports = Get-NearbyAirports -UserLocation $currentUserLocation -AtcSources $AtcSources -Radius $NearbyRadius

            if (-not $ShowMap) {
                if ($sortedAirports.Count -eq 0) {
                    Write-Error "No LiveATC streams found near your location."
                }
                else {
                    $choices = $sortedAirports | ForEach-Object {
                        "[{0}] {1}, {2} ({3}km away)" -f $_.ICAO, $_.Name, $_.City, ([math]::Round($_.Distance))
                    }

                    $prompt = "Select a nearby airport:"
                    $selectedChoice = if ($UseFZF) {
                        Select-ItemFZF -prompt $prompt -items $choices
                    }
                    else {
                        Select-Item -prompt $prompt -items $choices
                    }

                    if ($selectedChoice -match "^\[(?<icao>\w{4})\]") {
                        $ICAO = $matches.icao
                    }
                    else {
                        throw "Invalid nearby airport selection."
                    }
                }
            }
        }
    }

    $mapSelectedChannelIndex = $null

    if ($ShowMap) {
        $mapSelection = Select-ATCMap `
            -AtcSources $AtcSources `
            -Favorites $Favorites `
            -CsvPath $CsvPath `
            -ScriptDir $ScriptDir `
            -UserLocation $currentUserLocation `
            -Radius $NearbyRadius `
            -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
            -NoWeather:$NoWeather `
            -Dark:$Dark `
            -KeepOpen:$KeepOpen `
            -Player $Player `
            -ATCVolume $ATCVolume `
            -NoLofiMusic:$NoLofiMusic `
            -PlayLofiGirlVideo:$PlayLofiGirlVideo `
            -ShowLofiTrack:$ShowLofiTrack `
            -LofiMusicUrl $LofiMusicUrl `
            -LofiVolume $LofiVolume `
            -StartRandom:$RandomATC `
            -FavoritesPath $FavoritesPath

        if ($KeepOpen) {
            exit 0
        }

        if ($mapSelection -and $mapSelection.ICAO) {
            $ICAO = $mapSelection.ICAO
            $mapSelectedChannelIndex = $mapSelection.ChannelIndex
        }
    }

    $selectedATC = $null

    if ($ICAO) {
        $selectedATC = Select-ATCStreamByICAO `
            -AtcSources $AtcSources `
            -ICAO $ICAO `
            -MapSelectedChannelIndex $mapSelectedChannelIndex `
            -RandomATC:$RandomATC `
            -UseFZF:$UseFZF `
            -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable
    }

    if (-not $selectedATC) {
        if ($RandomATC) {
            $selectedATC = Get-RandomATCStream -atcSources $AtcSources
        }
        else {
            if ($UseFavorite) {
                $selectedATC = Select-FavoriteATC -favorites $Favorites -atcSources $AtcSources -UseFZF:$UseFZF
            }

            if (-not $selectedATC) {
                if ($UseFZF) {
                    $selectedATC = Select-ATCStreamFZF -atcSources $AtcSources
                }
                else {
                    $selectedATC = Select-ATCStreamManually -AtcSources $AtcSources
                }
            }
        }
    }

    if (-not $selectedATC -or -not $selectedATC.AirportInfo) {
        throw "No ATC stream was selected."
    }

    return [pscustomobject]@{
        SelectedATC         = $selectedATC
        CurrentUserLocation = $currentUserLocation
        ICAO                = $ICAO
    }
}

# Function to calculate the distance in kilometers between two sets of latitude and longitude coordinates using the Haversine formula
Function Get-DistanceKm {
    param (
        [double]$Lat1,
        [double]$Lon1,
        [double]$Lat2,
        [double]$Lon2
    )

    $rad = [math]::PI / 180
    $dLat = ($Lat2 - $Lat1) * $rad
    $dLon = ($Lon2 - $Lon1) * $rad
    $a = [math]::Pow([math]::Sin($dLat / 2), 2) + [math]::Cos($Lat1 * $rad) * [math]::Cos($Lat2 * $rad) * [math]::Pow([math]::Sin($dLon / 2), 2)
    $c = 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))
    return [math]::Round(6371 * $c)
}

# Function to convert a distance in kilometers to nautical miles, with optional rounding to a specified number of decimal places
Function ConvertTo-NauticalMiles {
    param(
        [double]$Kilometers,
        [int]$Decimals = 0
    )

    $nm = $Kilometers / 1.852
    return [math]::Round($nm, $Decimals)
}

# Function to fetch METAR and TAF data for a given ICAO code, with fallback options
Function Write-Welcome {
    param (
        [object]$airportInfo,
        [switch]$OpenRadar
    )

    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [Console]::OutputEncoding = $utf8; $OutputEncoding = $utf8
    }
    catch {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] $($_.Exception.Message)"
        return 
    }

    function Get-Emoji {
        param(
            [int]$CodePoint,
            [switch]$VS16
        )

        $s = [System.Char]::ConvertFromUtf32($CodePoint)
        if ($VS16) {
            $s += [char]0xFE0F
        }
        return $s
    }

    $airplane = Get-Emoji 0x2708 -VS16
    $location = Get-Emoji 0x1F4CD
    $earth = Get-Emoji 0x1F30D
    $departure = Get-Emoji 0x1F6EB
    $clock = Get-Emoji 0x23F0
    $weather = Get-Emoji 0x1F326 -VS16
    $wind = Get-Emoji 0x1F32C -VS16
    $eye = Get-Emoji 0x1F441 -VS16
    $cloud = Get-Emoji 0x2601 -VS16
    $thermometer = Get-Emoji 0x1F321 -VS16
    $droplet = Get-Emoji 0x1F4A7
    $barometer = Get-Emoji 0x1F4CF
    $note = Get-Emoji 0x1F4DD
    $sunrise = Get-Emoji 0x1F305
    $sunset = Get-Emoji 0x1F304
    $antenna = Get-Emoji 0x1F4E1
    $mic = Get-Emoji 0x1F5E3 -VS16
    $headphones = Get-Emoji 0x1F3A7
    $script:camera = Get-Emoji 0x1F3A5
    $link = Get-Emoji 0x1F517
    $hourglass = Get-Emoji 0x23F3
    $radar = Get-Emoji 0x1F4E1

    $fallbacks = if ($airportInfo.NearbyICAOs) {
        $airportInfo.NearbyICAOs -split ';' 
    }
    else {
        @()
    }

    $metarInfo = Get-METAR-TAF -ICAO $airportInfo.ICAO -FallbackICAOs $Fallbacks
    $decodedMetar = ConvertFrom-METAR -metar $metarInfo.Report
    $airportDateTime = Get-AirportDateTime -ICAO $airportInfo.ICAO
    $sunTimes = Get-AirportSunriseSunset -ICAO $airportInfo.ICAO
    $lastUpdatedTime = Get-METAR-LastUpdatedTime -ICAO $airportInfo.ICAO -FallbackICAOs $fallbacks

    Write-Output "$airplane Welcome to $($airportInfo.'Airport Name')"
    Write-Output "    $location City:        $($airportInfo.City)"
    Write-Output "    $earth Country:     $($airportInfo.Country)"
    Write-Output "    $departure ICAO/IATA:   $($airportInfo.ICAO)/$($airportInfo.IATA)`n"
    Write-Output "$clock Current Date/Time:`n    $airportDateTime`n"
    Write-Output "$weather Weather Information:"
    Write-Output "    $wind Wind:        $($decodedMetar.Wind)"
    Write-Output "    $eye Visibility:  $($decodedMetar.Visibility)"
    Write-Output "    $cloud Ceiling:     $($decodedMetar.Ceiling)"
    Write-Output "    $thermometer Temperature: $($decodedMetar.Temperature)"
    Write-Output "    $droplet Dew Point:   $($decodedMetar.DewPoint)"
    Write-Output "    $barometer Pressure:    $($decodedMetar.Pressure)"
    Write-Output "    $note Raw METAR:   $($metarInfo.Report)`n"

    if ($sunTimes) {
        Write-Output "$sunrise Sunrise/Sunset Times:"
        Write-Output "    $sunrise Sunrise: $($sunTimes.Sunrise)"
        Write-Output "    $sunset Sunset:  $($sunTimes.Sunset)`n"
    }

    Write-Output "$antenna Air Traffic Control:"
    Write-Output "    $mic Channel: $($airportInfo.'Channel Description')"
    Write-Output "    $headphones Stream:  $($airportInfo.'Stream URL')`n"

    if ($OpenRadar -or -not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
        Write-Output "$link External Links:"
        if ($OpenRadar) {
            Write-Output "    $radar Radar:  https://beta.flightaware.com/live/airport/$($airportInfo.ICAO)"
        }
        if (-not [string]::IsNullOrWhiteSpace($airportInfo.'Webcam URL')) {
            Write-Output "    $script:camera Webcam: $($airportInfo.'Webcam URL')"
        }
        Write-Output ""
    }

    $sourceName = if ($metarInfo.Source) {
        $metarInfo.Source
    } 
    else {
        'Unknown source'
    }

    $sourceUrl = if ($metarInfo.SourceUrl) {
        " ($($metarInfo.SourceUrl))"
    }
    else {
        ''
    }

    Write-Output "$link Data Source: METAR data retrieved from $sourceName$sourceUrl"

    if ($metarInfo.ICAO -ne $airportInfo.ICAO -and $metarInfo.DistanceKm) {
        $distNmText = if ($metarInfo.DistanceNm) {
            "/$($metarInfo.DistanceNm)nm" 
        }
        else {
            ""
        }
        Write-Output "    $radar Using fallback METAR from $($metarInfo.ICAO) ($($metarInfo.DistanceKm)km$distNmText away)"
    }
    Write-Output "    $hourglass Last Updated: $lastUpdatedTime ago`n"
}

# Function to get the appropriate VLC volume argument based on the operating system and audio module
Function Get-NearbyAirports {
    param (
        [object]$UserLocation,
        [array]$AtcSources,
        [int]$Radius
    )

    if (-not $script:AirportData) {
        Get-AirportInfo -ICAO "KLAX" | Out-Null
    }

    $allAirports = $script:AirportData.PSObject.Properties | ForEach-Object {
        $_.Value
    }

    $nearbyList = foreach ($airport in $allAirports) {
        if ($AtcSources.ICAO -contains $airport.icao) {
            [pscustomobject]@{
                ICAO     = $airport.icao
                Name     = $airport.name
                City     = $airport.city
                Country  = $airport.country
                Distance = (Get-DistanceKm -Lat1 $UserLocation.Latitude -Lon1 $UserLocation.Longitude -Lat2 $airport.lat -Lon2 $airport.lon)
            }
        }
    }
    return $nearbyList | Where-Object { $_.Distance -lt $Radius } | Sort-Object Distance | Select-Object -First 50
}

# Removes old temporary LofiATC map files from the temp directory
Function Add-DependencyResult {
    param(
        [string]$Name,
        [bool]$Required,
        [ValidateSet('OK', 'Missing', 'Warning')]
        [string]$Status,
        [string]$Details,
        [string]$Category = 'Dependency'
    )

    [pscustomobject]@{
        Name     = $Name
        Required = $Required
        Status   = $Status
        Details  = $Details
        Category = $Category
    }
}

Function Test-CommandAvailable {
    param([string]$CommandName)

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        return $null
    }

    if ($cmd.Path) {
        return $cmd.Path
    }

    return $cmd.Name
}

Function Resolve-TesseractPath {
    $commandPath = Test-CommandAvailable -CommandName 'tesseract'
    if ($commandPath) {
        return $commandPath
    }

    if (-not $script:OnWindows) {
        return $null
    }

    $uninstallRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        $installEntries = Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue
        foreach ($entry in $installEntries) {
            $properties = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
            if (-not $properties -or $properties.DisplayName -notmatch 'Tesseract') {
                continue
            }

            $installDirectory = $properties.InstallLocation
            if (-not $installDirectory -and $properties.DisplayIcon) {
                $displayIcon = ([string]$properties.DisplayIcon).Trim('"') -replace ',\d+$', ''
                $installDirectory = Split-Path -Parent $displayIcon
            }

            if ($installDirectory) {
                $registeredPath = Join-Path $installDirectory 'tesseract.exe'
                if (Test-Path -LiteralPath $registeredPath -PathType Leaf) {
                    return $registeredPath
                }
            }
        }
    }

    $candidates = @(
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Tesseract-OCR\tesseract.exe' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Tesseract-OCR\tesseract.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Tesseract-OCR\tesseract.exe' }),
        $(if ($env:SCOOP) { Join-Path $env:SCOOP 'apps\tesseract\current\tesseract.exe' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'scoop\apps\tesseract\current\tesseract.exe' })
    ) | Where-Object { $_ }

    $candidatePath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($candidatePath) {
        return $candidatePath
    }

    if ($env:LOCALAPPDATA) {
        $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        $wingetPath = Get-ChildItem -LiteralPath $wingetRoot -Filter 'tesseract.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($wingetPath) {
            return $wingetPath
        }
    }

    return $null
}

Function Test-UrlReachable {
    param(
        [string]$Url,
        [int]$TimeoutSec = 5
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    }
    catch {
        return $false
    }
}

Function Test-JsonFileReadable {
    param(
        [string]$Path,
        [switch]$Optional
    )

    if (-not (Test-Path $Path)) {
        return @{
            Ok      = [bool]$Optional
            Details = if ($Optional) { 'Not found; optional.' } else { 'File not found.' }
            Status  = if ($Optional) { 'OK' } else { 'Missing' }
        }
    }

    try {
        $null = Get-Content -Path $Path -Raw | ConvertFrom-Json
        return @{
            Ok      = $true
            Details = 'Exists and contains valid JSON.'
            Status  = 'OK'
        }
    }
    catch {
        return @{
            Ok      = $false
            Details = "Exists but contains invalid JSON: $($_.Exception.Message)"
            Status  = 'Missing'
        }
    }
}

Function Test-LofiATCDependencies {
    param(
        [string]$ScriptDir,
        [string]$SelectedPlayer,
        [switch]$UseFZF,
        [switch]$ShowMap,
        [switch]$ShowLofiTrack
    )

    $results = @()

    $baseCsv = Join-Path $ScriptDir 'atc_sources.csv'
    $liveCsv = Join-Path $ScriptDir 'liveatc_sources.csv'
    $favoritesJson = Resolve-LofiATCUserFilePath -FileName 'favorites.json' -ScriptDir $ScriptDir
    $configJson = Resolve-LofiATCUserFilePath -FileName 'config.json' -ScriptDir $ScriptDir

    $hasCsv = (Test-Path $baseCsv) -or (Test-Path $liveCsv)
    $results += Add-DependencyResult `
        -Name 'ATC source CSV' `
        -Required $true `
        -Status $(if ($hasCsv) { 'OK' } else { 'Missing' }) `
        -Details $(if ($hasCsv) { 'Found atc_sources.csv or liveatc_sources.csv.' } else { 'Neither atc_sources.csv nor liveatc_sources.csv exists.' })

    $configCheck = Test-JsonFileReadable -Path $configJson -Optional
    $results += Add-DependencyResult `
        -Name 'config.json' `
        -Required $false `
        -Status $configCheck.Status `
        -Details $configCheck.Details

    if (Test-Path $favoritesJson) {
        $favoritesCheck = Test-JsonFileReadable -Path $favoritesJson -Optional
        $results += Add-DependencyResult `
            -Name 'favorites.json' `
            -Required $false `
            -Status $favoritesCheck.Status `
            -Details $favoritesCheck.Details
    }
    else {
        $results += Add-DependencyResult `
            -Name 'favorites.json' `
            -Required $false `
            -Status 'OK' `
            -Details 'Not found; it will be created when needed.'
    }

    $playerCandidates = if ($script:OnWindows) {
        @(
            @{ Name = 'MPV'; Command = 'mpv.exe' }
            @{ Name = 'VLC'; Command = 'vlc.exe' }
            @{ Name = 'Potplayer'; Command = 'PotPlayerMini64.exe' }
            @{ Name = 'MPC-HC'; Command = 'mpc-hc64.exe' }
        )
    }
    else {
        @(
            @{ Name = 'MPV'; Command = 'mpv' }
            @{ Name = 'VLC'; Command = 'vlc' }
        )
    }

    if ($SelectedPlayer) {
        $selectedCommand = switch ($SelectedPlayer) {
            'VLC'       { if ($script:OnWindows) { 'vlc.exe' } else { 'vlc' } }
            'MPV'       { if ($script:OnWindows) { 'mpv.exe' } else { 'mpv' } }
            'Potplayer' { 'PotPlayerMini64.exe' }
            'MPC-HC'    { 'mpc-hc64.exe' }
            default     { $null }
        }

        $selectedPath = if ($selectedCommand) { Test-CommandAvailable -CommandName $selectedCommand } else { $null }

        $results += Add-DependencyResult `
            -Name "Player ($SelectedPlayer)" `
            -Required $true `
            -Status $(if ($selectedPath) { 'OK' } else { 'Missing' }) `
            -Details $(if ($selectedPath) { $selectedPath } else { "$SelectedPlayer not found in PATH." })
    }
    else {
        $anyPlayerFound = $false

        foreach ($candidate in $playerCandidates) {
            $playerPath = Test-CommandAvailable -CommandName $candidate.Command
            if ($playerPath) {
                $anyPlayerFound = $true
            }

            $results += Add-DependencyResult `
                -Name "Player candidate: $($candidate.Name)" `
                -Required $false `
                -Status $(if ($playerPath) { 'OK' } else { 'Warning' }) `
                -Details $(if ($playerPath) { $playerPath } else { 'Not found in PATH.' })
        }

        $results += Add-DependencyResult `
            -Name 'At least one supported player available' `
            -Required $true `
            -Status $(if ($anyPlayerFound) { 'OK' } else { 'Missing' }) `
            -Details $(if ($anyPlayerFound) { 'One or more supported players found.' } else { 'No supported players found in PATH.' })
    }

    $fzfPath = Test-CommandAvailable -CommandName 'fzf'
    $results += Add-DependencyResult `
        -Name 'fzf' `
        -Required ([bool]$UseFZF) `
        -Status $(if ($UseFZF) {
            if ($fzfPath) { 'OK' } else { 'Missing' }
        } else {
            if ($fzfPath) { 'OK' } else { 'Warning' }
        }) `
        -Details $(if ($UseFZF) {
            if ($fzfPath) { $fzfPath } else { 'fzf not found in PATH.' }
        } else {
            if ($fzfPath) { "$fzfPath (installed)" } else { 'Not installed; only needed with -UseFZF.' }
        })

    $ytdlpPath = Test-CommandAvailable -CommandName 'yt-dlp'
    $youtubeDlPath = Test-CommandAvailable -CommandName 'youtube-dl'

    $results += Add-DependencyResult `
        -Name 'yt-dlp' `
        -Required $false `
        -Status $(if ($ytdlpPath) { 'OK' } else { 'Warning' }) `
        -Details $(if ($ytdlpPath) { $ytdlpPath } else { 'Not found; used for reliable YouTube URL resolution.' }) `
        -Category 'Optional Tool'

    $results += Add-DependencyResult `
        -Name 'youtube-dl' `
        -Required $false `
        -Status $(if ($youtubeDlPath) { 'OK' } else { 'Warning' }) `
        -Details $(if ($youtubeDlPath) { $youtubeDlPath } else { 'Not found; fallback for YouTube URL resolution.' }) `
        -Category 'Optional Tool'

    $ffmpegPath = Test-CommandAvailable -CommandName 'ffmpeg'
    $tesseractPath = Resolve-TesseractPath
    $ocrResolverPath = if ($ytdlpPath) { $ytdlpPath } else { $youtubeDlPath }

    $results += Add-DependencyResult `
        -Name 'Lofi OCR stream resolver' `
        -Required ([bool]$ShowLofiTrack) `
        -Status $(if ($ocrResolverPath) { 'OK' } elseif ($ShowLofiTrack) { 'Missing' } else { 'Warning' }) `
        -Details $(if ($ocrResolverPath) { $ocrResolverPath } else { 'Install yt-dlp or youtube-dl to resolve the livestream video.' }) `
        -Category 'Optional Tool'

    $results += Add-DependencyResult `
        -Name 'ffmpeg (Lofi OCR)' `
        -Required ([bool]$ShowLofiTrack) `
        -Status $(if ($ffmpegPath) { 'OK' } elseif ($ShowLofiTrack) { 'Missing' } else { 'Warning' }) `
        -Details $(if ($ffmpegPath) { $ffmpegPath } else { 'ffmpeg not found in PATH; required to capture the title overlay.' }) `
        -Category 'Optional Tool'

    $results += Add-DependencyResult `
        -Name 'tesseract (Lofi OCR)' `
        -Required ([bool]$ShowLofiTrack) `
        -Status $(if ($tesseractPath) { 'OK' } elseif ($ShowLofiTrack) { 'Missing' } else { 'Warning' }) `
        -Details $(if ($tesseractPath) { $tesseractPath } else { 'Tesseract OCR not found in PATH or a standard Windows install location.' }) `
        -Category 'Optional Tool'

    if ($IsLinux) {
        $curlPath = Test-CommandAvailable -CommandName 'curl'
        $xdgOpenPath = Test-CommandAvailable -CommandName 'xdg-open'

        $results += Add-DependencyResult `
            -Name 'curl' `
            -Required $false `
            -Status $(if ($curlPath) { 'OK' } else { 'Warning' }) `
            -Details $(if ($curlPath) { $curlPath } else { 'Not found; only used by the current Linux LiveATC resolution path.' }) `
            -Category 'Optional Tool'

        $results += Add-DependencyResult `
            -Name 'xdg-open' `
            -Required ([bool]$ShowMap) `
            -Status $(if ($ShowMap) {
                if ($xdgOpenPath) { 'OK' } else { 'Missing' }
            } else {
                if ($xdgOpenPath) { 'OK' } else { 'Warning' }
            }) `
            -Details $(if ($ShowMap) {
                if ($xdgOpenPath) { $xdgOpenPath } else { 'xdg-open not found in PATH.' }
            } else {
                if ($xdgOpenPath) { "$xdgOpenPath (installed)" } else { 'Not installed; only needed with -ShowMap.' }
            })
    }
    elseif ($IsMacOS) {
        $openPath = Test-CommandAvailable -CommandName 'open'

        $results += Add-DependencyResult `
            -Name 'open' `
            -Required ([bool]$ShowMap) `
            -Status $(if ($ShowMap) {
                if ($openPath) { 'OK' } else { 'Missing' }
            } else {
                if ($openPath) { 'OK' } else { 'Warning' }
            }) `
            -Details $(if ($ShowMap) {
                if ($openPath) { $openPath } else { 'open command not found.' }
            } else {
                if ($openPath) { "$openPath (installed)" } else { 'Not installed; only needed with -ShowMap.' }
            })
    }
    elseif ($script:OnWindows) {
        $results += Add-DependencyResult `
            -Name 'Default browser opening' `
            -Required ([bool]$ShowMap) `
            -Status 'OK' `
            -Details $(if ($ShowMap) { 'Uses Start-Process on Windows.' } else { 'Not requested.' })
    }

    $airportDbOk = Test-UrlReachable -Url 'https://raw.githubusercontent.com/rominjun/Airports/master/airports.json'
    $results += Add-DependencyResult `
        -Name 'Airport database service' `
        -Required $false `
        -Status $(if ($airportDbOk) { 'OK' } else { 'Warning' }) `
        -Details 'Used for airport metadata.' `
        -Category 'Network'

    $noaaOk = Test-UrlReachable -Url 'https://aviationweather.gov/api/data/metar?ids=KLAX'
    $results += Add-DependencyResult `
        -Name 'NOAA METAR service' `
        -Required $false `
        -Status $(if ($noaaOk) { 'OK' } else { 'Warning' }) `
        -Details 'Used for weather/METAR data.' `
        -Category 'Network'

    $vatsimOk = Test-UrlReachable -Url 'https://metar.vatsim.net/metar.php?id=KLAX'
    $results += Add-DependencyResult `
        -Name 'VATSIM METAR service' `
        -Required $false `
        -Status $(if ($vatsimOk) { 'OK' } else { 'Warning' }) `
        -Details 'Fallback weather source.' `
        -Category 'Network'

    return $results
}

Function Write-DependencyReport {
    param([array]$Results)

    Write-Host '========================' -ForegroundColor Cyan
    Write-Host 'LofiATC Dependency Check' -ForegroundColor Cyan
    Write-Host '========================' -ForegroundColor Cyan

    foreach ($result in $Results) {
        $color = switch ($result.Status) {
            'OK' {
                'Green'
            }
            'Missing' {
                if ($result.Required) {
                    'Red'
                }
                else {
                    'Yellow'
                }
            }
            'Warning' {
                'Yellow'
            }
            default {
                'White'
            }
        }

        $reqText = if ($result.Required) {
            'Required'
        }
        else {
            'Optional'
        }

        Write-Host ("[{0}] {1} - {2}" -f $result.Status.ToUpperInvariant(), $result.Name, $reqText) -ForegroundColor $color
        Write-Host ("    {0}" -f $result.Details)
    }

    $requiredFailures = @($Results | Where-Object { $_.Required -and $_.Status -eq 'Missing' })

    Write-Host ''
    if ($requiredFailures.Count -eq 0) {
        Write-Host 'Dependency check passed.' -ForegroundColor Green
    }
    else {
        Write-Host ("Dependency check failed. Missing required items: {0}" -f $requiredFailures.Count) -ForegroundColor Red
    }
}
