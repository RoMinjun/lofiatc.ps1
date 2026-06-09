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
Optional path for the saved configuration file. Defaults to user data when installed, with repo-local config as a compatibility fallback.

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

Initialize-LofiATCState
$LofiGenres = Get-LofiATCGenreMap

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
        if (-not $ConfigPath) { $ConfigPath = Resolve-LofiATCUserFilePath -FileName 'config.json' -ScriptDir $scriptDir }
        Import-LofiATCConfig -ConfigPath $ConfigPath -BoundParameters $PSBoundParameters
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
        if (-not $ConfigPath) { $ConfigPath = Join-Path (Initialize-LofiATCUserDataPath) 'config.json' }
        Export-LofiATCConfig -CommandPath $MyInvocation.MyCommand.Path -ConfigPath $ConfigPath
    }

    # Test the selected player
    Test-Player -player $Player | Out-Null

    # Define paths for CSV files and favorites JSON
    $baseCsv = Join-Path $scriptDir 'atc_sources.csv'
    $liveCsv = Join-Path $scriptDir 'liveatc_sources.csv'
    $favoritesJson = Resolve-LofiATCUserFilePath -FileName 'favorites.json' -ScriptDir $scriptDir
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

    # Load ATC sources and favorites, then resolve the selected stream.
    $atcSources = Import-ATCSource -csvPath $csvPath
    $favorites = Get-Favorite -path $favoritesJson
    $selection = Resolve-SelectedATCStream `
        -AtcSources $atcSources `
        -Favorites $favorites `
        -CsvPath $csvPath `
        -ScriptDir $scriptDir `
        -FavoritesPath $favoritesJson `
        -ICAO $ICAO `
        -NearbyRadius $NearbyRadius `
        -Player $Player `
        -ATCVolume $ATCVolume `
        -LofiVolume $LofiVolume `
        -LofiMusicUrl $lofiMusicUrl `
        -Nearby:$Nearby `
        -ShowMap:$ShowMap `
        -KeepOpen:$KeepOpen `
        -UseFZF:$UseFZF `
        -UseFavorite:$UseFavorite `
        -RandomATC:$RandomATC `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
        -NoWeather:$NoWeather `
        -Dark:$Dark `
        -NoLofiMusic:$NoLofiMusic `
        -PlayLofiGirlVideo:$PlayLofiGirlVideo

    Start-LofiATCSession `
        -SelectedATC $selection.SelectedATC `
        -Player $Player `
        -LofiMusicUrl $lofiMusicUrl `
        -FavoritesPath $favoritesJson `
        -MaxFavorites $maxFavorites `
        -ATCVolume $ATCVolume `
        -LofiVolume $LofiVolume `
        -NoLofiMusic:$NoLofiMusic `
        -PlayLofiGirlVideo:$PlayLofiGirlVideo `
        -IncludeWebcamIfAvailable:$IncludeWebcamIfAvailable `
        -OpenRadar:$OpenRadar `
        -RandomATC:$RandomATC `
        -PlayerWasSpecified:($PSCmdlet -and $PSCmdlet.MyInvocation.BoundParameters["Player"])
}
catch [System.OperationCanceledException] {
    Write-Warning $_.Exception.Message
    exit 1
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
