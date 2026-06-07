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
Select a random ATC stream from the list of sources. When combined with -ICAO,
choose a random channel for that airport.

.PARAMETER PlayLofiGirlVideo
Play the Lofi Girl video instead of just the audio.

.PARAMETER UseFZF
Use fzf for searching and filtering channels.

.PARAMETER UseBaseCSV
Force the script to load atc_sources.csv even if liveatc_sources.csv exists.

.PARAMETER UseFavorite
Load a previously saved favorite from favorites.json and skip continent/country selection. The file stores how often you play each stream and keeps the top entries.

.PARAMETER Player
Specify the media player to use (VLC, Potplayer, MPC-HC or MPV).

If not specified, the script auto-detects a suitable player:
- On Windows, it first checks the default app for .mp4 and uses it if supported and available in PATH.
- If no supported default is available, it falls back to the first supported installed player.
- On non-Windows systems, it prefers MPV first, then VLC.

.PARAMETER ATCVolume
Volume level for the ATC stream. Default is 65.

.PARAMETER LofiVolume
Volume level for the Lofi Girl stream. Default is 50.

.PARAMETER LofiSource
Specify a custom URL or file path for the Lofi audio/video source Defaults to the Lofi Girl Youtube stream if not provided.

.PARAMETER LofiGenre
Specify a Lofi genre preset. Valid options: Chillhop, Synthwave, SynthAmbient, Sad, Piano, Classical, Jazz, RelaxJazz, SleepAmbient, DarkAmbient, Medieval, Asian, SleepChill, Guitar, Pomodoro. This is overridden by -LofiSource.

.PARAMETER ICAO
Specify an airport by ICAO code. If multiple channels exist you will be prompted to select one unless -RandomATC is used to choose randomly.

.PARAMETER OpenRadar
Open the FlightAware radar page for the selected ICAO after displaying the welcome screen.

.PARAMETER SaveConfig
Save the parameters used for the current run to a configuration file.

.PARAMETER ConfigPath
Optional path for the saved configuration file. Defaults to a file named `config.json` beside the script.

.PARAMETER Nearby
Shows a list of nearby airports to your current device location (IP as fallback)

.PARAMETER NearbyRadius
If specified, to be used in combination with -Nearby, to change the radius of nearby airports in kilometers

.PARAMETER ShowMap
Generates and opens an interactive HTML map in your browser showing all available ATC sources.

.PARAMETER NoWeather
Skips the live METAR weather fetch when loading the map to vastly improve startup speed.

.PARAMETER Dark
Initializes the HTML Map in Dark Mode.

.PARAMETER CheckDependencies
Checks required files, player availability, optional tools, and network dependencies, then prints a dependency report and exits.

.PARAMETER KeepOpen
When used with -ShowMap, keeps the interactive map open after selecting a channel and allows repeated channel selections from the map.
#>

[CmdletBinding()]
param (
    [switch]$IncludeWebcamIfAvailable,
    [switch]$NoLofiMusic,
    [switch]$RandomATC,
    [switch]$PlayLofiGirlVideo,
    [switch]$UseFZF,
    [switch]$UseBaseCSV,
    [switch]$UseFavorite,
    [ValidateSet("VLC", "MPV", "Potplayer", "MPC-HC")]
    [string]$Player,
    [ValidateRange(0,100)]
    [int]$ATCVolume = 65,
    [ValidateRange(0,100)]
    [int]$LofiVolume = 50,
    [string]$LofiSource = "https://youtu.be/X4VbdwhkE10",
    [ValidateSet("Chillhop", "Synthwave", "Jazz", "DarkAmbient","Medieval", "Sad", "Piano", "SleepChill", "RelaxJazz", "Classical", "Guitar", "Pomodoro", "SleepAmbient", "SynthAmbient", "Asian", "DarkAmbient")]
    [string]$LofiGenre,
    [ValidatePattern('^[A-Za-z0-9]{4}$')]
    [string]$ICAO,
    [switch]$LoadConfig,
    [switch]$SaveConfig,
    [string]$ConfigPath,
    [switch]$OpenRadar,
    [switch]$Nearby,
    [ValidateRange(1,5000)]
    [int]$NearbyRadius = 500,
    [switch]$ShowMap,
    [switch]$NoWeather,
    [switch]$Dark,
    [switch]$CheckDependencies,
    [Alias("Persistent")]
    [switch]$KeepOpen
)

$LofiGenres = @{
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

# Explicitly set OS variables at the script scope
$script:OnWindows = $env:OS -eq 'Windows_NT'

# Cache for airport database
$script:AirportData = $null

# Mapping of common IANA time zones to Windows IDs for PowerShell 5.1
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

$script:ModuleRoot = Join-Path $PSScriptRoot 'modules'
$script:ModuleFiles = @(
    'LofiATC.Core.psm1',
    'LofiATC.Player.psm1',
    'LofiATC.Favorites.psm1',
    'LofiATC.Weather.psm1',
    'LofiATC.Map.psm1'
)

foreach ($moduleFile in $script:ModuleFiles) {
    $modulePath = Join-Path $script:ModuleRoot $moduleFile
    $moduleScript = [System.IO.File]::ReadAllText($modulePath, [System.Text.Encoding]::UTF8)
    . ([scriptblock]::Create($moduleScript))
}

$script:CurrentATCProcess = $null
$script:CurrentWebcamProcess = $null
$script:CurrentLofiProcess = $null

$script:CurrentATCVolume = $null
$script:CurrentLofiVolume = $null

# Allow unit tests to dot-source this script without running the interactive main flow.
if ($env:LOFIATC_TEST_MODE -eq '1') {
    if ($MyInvocation.InvocationName -ne '.') {
        Write-Warning "LOFIATC_TEST_MODE is enabled for this PowerShell session. Interactive execution is being skipped. Run `"Remove-Item Env:LOFIATC_TEST_MODE`" or start a new session to run the script normally."
    }
    return
}

try {
    # set reference point for relative paths
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

    # Load config if specified, then override with any directly provided parameters
    if ($LoadConfig) {
        if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'config.json' }
        if (Test-Path $ConfigPath) {
            $config = Get-Content -Path $ConfigPath | ConvertFrom-Json
            foreach ($prop in $config.PSObject.Properties) {
                $name = $prop.Name
                if ($name -in @(
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
                )) {
                    continue
                }

                if (-not $PSBoundParameters.ContainsKey($name) -and $null -ne $prop.Value -and $prop.Value -ne "") {
                    Set-Variable -Name $name -Value $prop.Value -Scope Local
                }
            }
            Write-Information "Loaded config from $ConfigPath"
        }
        else {
            Write-Warning "Config file not found at $ConfigPath"
        }
    }

    if ($ICAO) {
        $ICAO = $ICAO.Trim().ToUpperInvariant()

        if ($ICAO -notmatch '^[A-Z0-9]{4}$') {
            throw "ICAO must be a 4-character airport code."
        }
    }
    
    if ($CheckDependencies) {
        $dependencyResults = Test-LofiATCDependencies `
            -ScriptDir $scriptDir `
            -SelectedPlayer $Player `
            -UseFZF:$UseFZF `
            -ShowMap:$ShowMap

        Write-DependencyReport -Results $dependencyResults

        $requiredFailures = @($dependencyResults | Where-Object { $_.Required -and $_.Status -eq 'Missing' })
        if ($requiredFailures.Count -gt 0) {
            exit 1
        }

        exit 0
    }

    # Resolve player from parameters or config
    $Player = Resolve-Player -explicitPlayer $Player

    # Save config if specified, excluding common PowerShell parameters and any that were directly provided to override config values
    if ($SaveConfig) {
        if (-not $ConfigPath) { $ConfigPath = Join-Path $scriptDir 'config.json' }
        $paramNames = (Get-Command $MyInvocation.MyCommand.Path).Parameters.Keys
        $config = @{}
        foreach ($name in $paramNames) {
            if ($name -notin @(
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
            )) {
                $value = Get-Variable -Name $name -ValueOnly
                if ($value -is [System.Management.Automation.SwitchParameter]) {
                    $value = [bool]$value
                }

                if ($null -ne $value -and $value -ne "") {
                    $config[$name] = $value
                }
            }
        }
        $config | ConvertTo-Json | Set-Content -Path $ConfigPath
        Write-Information "Saved config to $ConfigPath"
    }

    # Test the selected player
    Test-Player -player $Player | Out-Null

    # Define paths for CSV files and favorites JSON
    $baseCsv = Join-Path $scriptDir 'atc_sources.csv'
    $liveCsv = Join-Path $scriptDir 'liveatc_sources.csv'
    $favoritesJson = Join-Path $scriptDir 'favorites.json'
    $maxFavorites = 10

    if (-not $UseBaseCSV -and (Test-Path $liveCsv)) {
        Write-Information "Using live sources CSV: $liveCsv"; $csvPath = $liveCsv
    }
    else {
        Write-Information "Using base sources CSV: $baseCsv"; $csvPath = $baseCsv
    }

    if ($LofiGenre -and (-not $PSBoundParameters.ContainsKey('LofiSource'))) {
        $lofiMusicUrl = $LofiGenres[$LofiGenre]
    }
    else {
        $lofiMusicUrl = $LofiSource
    }

    # Load ATC sources, favorites, and determine user location if needed
    $atcSources = Import-ATCSource -csvPath $csvPath
    $favorites = Get-Favorite -path $favoritesJson
    $currentUserLocation = $null

    # If -Nearby is specified, get user location and find nearby airports
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

            $sortedAirports = Get-NearbyAirports -UserLocation $currentUserLocation -AtcSources $atcSources -Radius $NearbyRadius

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

    # If -ShowMap is specified, open the interactive map and allow selection from there
    $mapSelectedChannelIndex = $null

    if ($ShowMap) {
        $mapSelection = Select-ATCMap `
            -AtcSources $atcSources `
            -Favorites $favorites `
            -CsvPath $csvPath `
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
            -LofiMusicUrl $lofiMusicUrl `
            -LofiVolume $LofiVolume `
            -StartRandom:$RandomATC `
            -FavoritesPath $favoritesJson

        if ($KeepOpen) {
            exit 0
        }

        if ($mapSelection -and $mapSelection.ICAO) {
            $ICAO = $mapSelection.ICAO
            $mapSelectedChannelIndex = $mapSelection.ChannelIndex
        }
    }

    # Determine the selected ATC stream based on ICAO, channel, favorites, or random selection
    $selectedATC = $null
    if ($ICAO) {
        $icaoMatches = $atcSources | Where-Object { $_.ICAO -eq $ICAO }
        if (-not $icaoMatches) {
            throw "No ATC stream found for ICAO $ICAO."
        }

        if ($null -ne $mapSelectedChannelIndex) {
            $icaoMatches = @($icaoMatches)

            if ($mapSelectedChannelIndex -lt 0 -or $mapSelectedChannelIndex -ge $icaoMatches.Count) {
                throw "Invalid channel index returned from map for ICAO $ICAO."
            }

            $match = $icaoMatches[$mapSelectedChannelIndex]
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

        $selectedATC = @{
            StreamUrl   = $match.'Stream URL'
            WebcamUrl   = $match.'Webcam URL'
            AirportInfo = $match
        }
    }

    # If no ICAO was specified or selected, allow user to select based on favorites, random selection, or manual navigation through continents/countries/states
    if (-not $selectedATC) {
        if ($RandomATC) {
            $selectedATC = Get-RandomATCStream -atcSources $atcSources
        }
        else {
            if ($UseFavorite) {
                $selectedATC = Select-FavoriteATC -favorites $favorites -atcSources $atcSources -UseFZF:$UseFZF
            }
            if (-not $selectedATC) {
                if ($UseFZF) {
                    $selectedATC = Select-ATCStreamFZF -atcSources $atcSources
                }
                else {
                    while (-not $selectedATC) {
                        $selectedContinent = Select-Item -prompt "Select a continent:" -items ($atcSources.Continent | Sort-Object -Unique)
                        do {
                            $countries = @($atcSources | Where-Object { $_.Continent.Trim().ToLower() -eq $selectedContinent.Trim().ToLower() } | Select-Object -ExpandProperty Country | Sort-Object -Unique)
                            $selectedCountry = Select-Item -prompt "Select a country from ${selectedContinent}:" -items $countries -AllowBack
                            if ($null -eq $selectedCountry) {
                                $selectedContinent = $null
                                break
                            }
                            $states = @($atcSources | Where-Object {
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
                                    $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry -state $selectedState
                                } while (-not $selectedATC -and $selectedCountry)

                                if (-not $selectedCountry) {
                                    continue
                                }
                            }
                            else {
                                $selectedATC = Select-ATCStream -atcSources $atcSources -continent $selectedContinent -country $selectedCountry
                            }
                        } while (-not $selectedATC)
                    }
                }
            }
        }
    }

    # Final check to ensure a valid ATC stream was selected before proceeding
    if (-not $selectedATC -or -not $selectedATC.AirportInfo) {
        throw "No ATC stream was selected."
    }

    $selectedATCUrl = $selectedATC.StreamUrl
    $selectedWebcamUrl = $selectedATC.WebcamUrl
    Clear-Host
    Write-Welcome -airportInfo $selectedATC.AirportInfo -OpenRadar:$OpenRadar
    if (-not $RandomATC) {
        Add-Favorite -path $favoritesJson -ICAO $selectedATC.AirportInfo.ICAO -Channel $selectedATC.AirportInfo.'Channel Description' -maxEntries $maxFavorites
    }
    if ($OpenRadar) {
        Open-Radar -ICAO $selectedATC.AirportInfo.ICAO
    }

    if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Player"]) {
        Write-Verbose "Player selected by user: $Player"
    }
    else {
        Write-Verbose "Default player selected: $Player"
    }

    if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) {
        Write-Verbose "Opening ATC stream: $selectedATCUrl"
        if ($selectedWebcamUrl) {
            Write-Verbose "Opening webcam stream: $selectedWebcamUrl"
        }
    }

    Start-Player -url $selectedATCUrl -player $Player -noVideo -basicArgs -volume $ATCVolume

    if (-not $NoLofiMusic) {
        if ($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Verbose"]) {
            Write-Verbose "Opening Lofi Girl stream: $lofiMusicUrl"
        }
        if ($PlayLofiGirlVideo) {
            Start-Player -url $lofiMusicUrl -player $Player -basicArgs -volume $LofiVolume
        }
        else {
            Start-Player -url $lofiMusicUrl -player $Player -noVideo -basicArgs -volume $LofiVolume
        }
    }

    if ($IncludeWebcamIfAvailable -and $selectedWebcamUrl) {
        Start-Player -url $selectedWebcamUrl -player $Player -noAudio -basicArgs
    }
}
catch [System.OperationCanceledException] {
    Write-Warning $_.Exception.Message
    exit 1
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

