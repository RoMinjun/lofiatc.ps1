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

Function Get-LofiATCSourceKey {
    param([pscustomobject]$Source)

    return '{0}|{1}|{2}' -f $Source.ICAO, $Source.'Channel Description', $Source.'Stream URL'
}

Function Format-LofiATCSourceSummary {
    param([pscustomobject]$Source)

    $parts = @(
        $Source.ICAO,
        $Source.'Airport Name',
        $Source.'Channel Description'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    return ($parts -join ' - ')
}

Function Compare-LofiATCSourceCsv {
    param(
        [string]$OldPath,
        [string]$NewPath
    )

    if (-not (Test-Path $OldPath)) {
        return @{
            Added   = @(Import-Csv -Path $NewPath)
            Removed = @()
        }
    }

    $oldSources = @(Import-Csv -Path $OldPath)
    $newSources = @(Import-Csv -Path $NewPath)
    $oldByKey = @{}
    $newByKey = @{}

    foreach ($source in $oldSources) {
        $oldByKey[(Get-LofiATCSourceKey -Source $source)] = $source
    }

    foreach ($source in $newSources) {
        $newByKey[(Get-LofiATCSourceKey -Source $source)] = $source
    }

    $added = @(
        foreach ($key in $newByKey.Keys) {
            if (-not $oldByKey.ContainsKey($key)) {
                $newByKey[$key]
            }
        }
    ) | Sort-Object ICAO, 'Airport Name', 'Channel Description'

    $removed = @(
        foreach ($key in $oldByKey.Keys) {
            if (-not $newByKey.ContainsKey($key)) {
                $oldByKey[$key]
            }
        }
    ) | Sort-Object ICAO, 'Airport Name', 'Channel Description'

    return @{
        Added   = @($added)
        Removed = @($removed)
    }
}

Function Write-LofiATCSourceDiff {
    param(
        [array]$Added,
        [array]$Removed,
        [int]$Limit = 50
    )

    Write-Host ("Source changes: +{0} / -{1}" -f $Added.Count, $Removed.Count)

    if ($Added.Count -eq 0 -and $Removed.Count -eq 0) {
        Write-Host "No added or removed sources."
        return
    }

    $effectiveLimit = if ($Limit -lt 1) { [int]::MaxValue } else { $Limit }

    if ($Added.Count -gt 0) {
        Write-Host ""
        Write-Host "Added sources:"
        foreach ($source in ($Added | Select-Object -First $effectiveLimit)) {
            Write-Host ("  + {0}" -f (Format-LofiATCSourceSummary -Source $source))
        }

        if ($Added.Count -gt $effectiveLimit) {
            Write-Host ("  ... {0} more added sources" -f ($Added.Count - $effectiveLimit))
        }
    }

    if ($Removed.Count -gt 0) {
        Write-Host ""
        Write-Host "Removed sources:"
        foreach ($source in ($Removed | Select-Object -First $effectiveLimit)) {
            Write-Host ("  - {0}" -f (Format-LofiATCSourceSummary -Source $source))
        }

        if ($Removed.Count -gt $effectiveLimit) {
            Write-Host ("  ... {0} more removed sources" -f ($Removed.Count - $effectiveLimit))
        }
    }
}

Function Update-LofiATCSources {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = (Get-LofiATCInstallRoot),
        [string]$Ref = 'main',
        [int]$DiffLimit = 50
    )

    $sourceUrl = "https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/$Ref/liveatc_sources.csv"
    $targetPath = Join-Path $InstallRoot 'liveatc_sources.csv'
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_sources_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

    if (-not (Test-Path $InstallRoot)) {
        throw "Install root not found: $InstallRoot"
    }

    Invoke-WebRequest -Uri $sourceUrl -OutFile $tempPath -UseBasicParsing

    try {
        $diff = Compare-LofiATCSourceCsv -OldPath $targetPath -NewPath $tempPath
        Write-LofiATCSourceDiff -Added $diff.Added -Removed $diff.Removed -Limit $DiffLimit

        Copy-Item -Path $tempPath -Destination $targetPath -Force
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item -Path $tempPath -Force
        }
    }

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

.PARAMETER SourceDiffLimit
Limits the number of added and removed sources printed by -UpdateSources. Use 0 to show all changes.
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
        [switch]$UpdateSources,
        [ValidateRange(0,10000)]
        [int]$SourceDiffLimit = 50
    )

    if ($UpdateSources) {
        Update-LofiATCSources -DiffLimit $SourceDiffLimit
        return
    }

    $scriptPath = Get-LofiATCInstalledScriptPath
    if (-not (Test-Path $scriptPath)) {
        throw "lofiatc.ps1 was not found at $scriptPath. Re-run the installer or set LOFIATC_INSTALL_ROOT."
    }

    $forwardedParameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'UpdateSources' -and $key -ne 'SourceDiffLimit') {
            $forwardedParameters[$key] = $PSBoundParameters[$key]
        }
    }

    & $scriptPath @forwardedParameters
}

Export-ModuleMember -Function lofiatc, Update-LofiATC, Update-LofiATCSources
