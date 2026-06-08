Function Get-LofiATCInstallRoot {
    if ($env:LOFIATC_INSTALL_ROOT) {
        return $env:LOFIATC_INSTALL_ROOT
    }

    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'lofiatc')
    }

    return (Join-Path $HOME '.local/share/lofiatc')
}

Function Get-LofiATCInstalledScriptPath {
    $installRoot = Get-LofiATCInstallRoot
    return (Join-Path $installRoot 'lofiatc.ps1')
}

Function Update-LofiATCSources {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-LofiATCInstallRoot),
        [string]$Ref = 'main'
    )

    $sourceUrl = "https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/$Ref/liveatc_sources.csv"
    $targetPath = Join-Path $InstallRoot 'liveatc_sources.csv'

    if (-not (Test-Path $InstallRoot)) {
        throw "Install root not found: $InstallRoot"
    }

    Invoke-WebRequest -Uri $sourceUrl -OutFile $targetPath -UseBasicParsing
    Write-Host "Updated liveatc_sources.csv at $targetPath"
}

Function Update-LofiATC {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-LofiATCInstallRoot),
        [string]$Ref = 'main'
    )

    $gitDir = Join-Path $InstallRoot '.git'
    if (Test-Path $gitDir) {
        git -C $InstallRoot pull --ff-only
        return
    }

    $installScript = Join-Path $InstallRoot 'install.ps1'
    if (Test-Path $installScript) {
        & $installScript -InstallRoot $InstallRoot -Ref $Ref
        return
    }

    throw "Cannot update app files automatically. Re-run the lofiatc install.ps1 installer."
}

Function lofiatc {
<#
.SYNOPSIS
Streams lofi music with live air traffic control.

.DESCRIPTION
Runs the installed lofiatc.ps1 script while preserving PowerShell-native help,
parameter completion, and ValidateSet completion for common options.

.PARAMETER UpdateSources
Refreshes liveatc_sources.csv in the installed app directory and exits.
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
        [ValidateSet("Chillhop", "Synthwave", "Jazz", "DarkAmbient", "Medieval", "Sad", "Piano", "SleepChill", "RelaxJazz", "Classical", "Guitar", "Pomodoro", "SleepAmbient", "SynthAmbient", "Asian")]
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
        [switch]$KeepOpen,
        [switch]$UpdateSources
    )

    if ($UpdateSources) {
        Update-LofiATCSources
        return
    }

    $scriptPath = Get-LofiATCInstalledScriptPath
    if (-not (Test-Path $scriptPath)) {
        throw "lofiatc.ps1 was not found at $scriptPath. Re-run the installer or set LOFIATC_INSTALL_ROOT."
    }

    $forwardedParameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'UpdateSources') {
            $forwardedParameters[$key] = $PSBoundParameters[$key]
        }
    }

    & $scriptPath @forwardedParameters
}

Export-ModuleMember -Function lofiatc, Update-LofiATC, Update-LofiATCSources
