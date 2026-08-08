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

Function Get-LofiATCInstallMetadata {
    param([string]$InstallRoot = (Get-LofiATCInstallRoot))

    $metadataPath = Join-Path $InstallRoot '.lofiatc-install.json'
    if (-not (Test-Path $metadataPath)) {
        return $null
    }

    try {
        return (Get-Content -Path $metadataPath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning "Could not read LofiATC install metadata at $metadataPath. Falling back to main."
        return $null
    }
}

Function Get-LofiATCInstallRef {
    $metadata = Get-LofiATCInstallMetadata
    if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Ref)) {
        return [string]$metadata.Ref
    }

    return 'main'
}

Function Get-LofiATCInstallRepository {
    $metadata = Get-LofiATCInstallMetadata
    if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Repository)) {
        return [string]$metadata.Repository
    }

    return 'RoMinjun/lofiatc.ps1'
}

Function Get-LofiATCVersion {
    [CmdletBinding()]
    param([string]$InstallRoot = (Get-LofiATCInstallRoot))

    $metadata = Get-LofiATCInstallMetadata -InstallRoot $InstallRoot
    if (-not $metadata) {
        throw "LofiATC install metadata was not found at $(Join-Path $InstallRoot '.lofiatc-install.json')."
    }

    $commit = if ($metadata.PSObject.Properties['Commit']) {
        [string]$metadata.Commit
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($commit) -and (Test-Path (Join-Path $InstallRoot '.git'))) {
        $gitCommit = git -C $InstallRoot rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitCommit)) {
            $commit = $gitCommit.Trim()
        }
    }

    return [pscustomobject]@{
        Repository            = [string]$metadata.Repository
        Ref                   = [string]$metadata.Ref
        Commit                = $commit
        InstalledAtUtc        = [string]$metadata.InstalledAtUtc
        InstallRoot           = if ($metadata.PSObject.Properties['InstallRoot']) { [string]$metadata.InstallRoot } else { $InstallRoot }
        ModuleRoot            = if ($metadata.PSObject.Properties['ModuleRoot']) { [string]$metadata.ModuleRoot } else { $null }
        ShellShimPath         = if ($metadata.PSObject.Properties['ShellShimPath']) { [string]$metadata.ShellShimPath } else { $null }
        ShellShimManaged      = if ($metadata.PSObject.Properties['ShellShimManaged']) { [bool]$metadata.ShellShimManaged } else { $null }
        PowerShellProfilePath = if ($metadata.PSObject.Properties['PowerShellProfilePath']) { [string]$metadata.PowerShellProfilePath } else { $null }
        ProfileManaged        = if ($metadata.PSObject.Properties['PowerShellProfileManaged']) { [bool]$metadata.PowerShellProfileManaged } else { $null }
    }
}

Function Resolve-LofiATCCommit {
    param(
        [string]$Repository,
        [string]$Ref
    )

    if ($Ref -match '^[0-9a-fA-F]{40}$') {
        return $Ref.ToLowerInvariant()
    }

    $escapedRef = [System.Uri]::EscapeDataString($Ref)
    $commitUrl = "https://api.github.com/repos/$Repository/commits/$escapedRef"
    $commit = Invoke-RestMethod -Uri $commitUrl -Headers @{
        Accept = 'application/vnd.github+json'
    }

    if (-not $commit.sha) {
        throw "GitHub did not return a commit hash for ref '$Ref'."
    }

    return [string]$commit.sha
}

Function Format-LofiATCCommitLink {
    param(
        [string]$Repository,
        [string]$Commit
    )

    $commitUrl = "https://github.com/$Repository/commit/$Commit"
    $supportsVirtualTerminal = (
        $Host.UI -and
        $Host.UI.PSObject.Properties['SupportsVirtualTerminal'] -and
        $Host.UI.SupportsVirtualTerminal
    )

    if (-not $supportsVirtualTerminal) {
        return "$Commit ($commitUrl)"
    }

    $escape = [char]27
    return ('{0}]8;;{1}{0}\{2}{0}]8;;{0}\' -f $escape, $commitUrl, $Commit)
}

Function Get-LofiATCGitHubRepository {
    param([string]$InstallRoot)

    $remoteUrl = git -C $InstallRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
        return $null
    }

    $remoteUrl = $remoteUrl.Trim()
    if ($remoteUrl -match 'github\.com[/:](?<repository>[^/:\s]+/[^/\s]+?)(?:\.git)?$') {
        return $Matches.repository
    }

    return $null
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
        [string]$Ref,
        [string]$Repository,
        [int]$DiffLimit = 50
    )

    if ([string]::IsNullOrWhiteSpace($Ref)) {
        $metadata = Get-LofiATCInstallMetadata -InstallRoot $InstallRoot
        $Ref = if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Ref)) { [string]$metadata.Ref } else { 'main' }
    }

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        $metadata = Get-LofiATCInstallMetadata -InstallRoot $InstallRoot
        $Repository = if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Repository)) { [string]$metadata.Repository } else { 'RoMinjun/lofiatc.ps1' }
    }

    $sourceCommit = $null
    try {
        $sourceCommit = Resolve-LofiATCCommit -Repository $Repository -Ref $Ref
    }
    catch {
        Write-Warning "Could not resolve '$Ref' to a commit hash. Downloading by ref instead. $($_.Exception.Message)"
    }

    $sourceRevision = if ($sourceCommit) { $sourceCommit } else { $Ref }
    $sourceUrl = "https://raw.githubusercontent.com/$Repository/$sourceRevision/liveatc_sources.csv"
    $targetPath = Join-Path $InstallRoot 'liveatc_sources.csv'
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_sources_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

    if (-not (Test-Path $InstallRoot)) {
        throw "Install root not found: $InstallRoot"
    }

    Invoke-WebRequest -Uri $sourceUrl -OutFile $tempPath -UseBasicParsing

    try {
        if ($sourceCommit) {
            $commitLink = Format-LofiATCCommitLink -Repository $Repository -Commit $sourceCommit
            Write-Host "Source commit: $commitLink (ref: $Ref)"
        }

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
        [string]$Ref,
        [string]$Repository
    )

    $gitDir = Join-Path $InstallRoot '.git'
    if (Test-Path $gitDir) {
        git -C $InstallRoot pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            throw "git pull failed with exit code $LASTEXITCODE."
        }

        $updatedCommit = git -C $InstallRoot rev-parse HEAD
        if ($LASTEXITCODE -ne 0) {
            throw "Could not determine the updated Git commit."
        }

        $updatedCommit = $updatedCommit.Trim()
        $gitRepository = Get-LofiATCGitHubRepository -InstallRoot $InstallRoot
        if ([string]::IsNullOrWhiteSpace($gitRepository)) {
            $gitRepository = Get-LofiATCInstallRepository
        }

        $commitLink = Format-LofiATCCommitLink -Repository $gitRepository -Commit $updatedCommit
        Write-Host "Updated commit: $commitLink"
        return
    }

    if ([string]::IsNullOrWhiteSpace($Ref)) {
        $metadata = Get-LofiATCInstallMetadata -InstallRoot $InstallRoot
        $Ref = if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Ref)) { [string]$metadata.Ref } else { 'main' }
    }

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        $metadata = Get-LofiATCInstallMetadata -InstallRoot $InstallRoot
        $Repository = if ($metadata -and -not [string]::IsNullOrWhiteSpace($metadata.Repository)) { [string]$metadata.Repository } else { 'RoMinjun/lofiatc.ps1' }
    }

    $updateCommit = $null
    try {
        $updateCommit = Resolve-LofiATCCommit -Repository $Repository -Ref $Ref
    }
    catch {
        Write-Warning "Could not resolve '$Ref' to a commit hash. Updating by ref instead. $($_.Exception.Message)"
    }

    $tempInstaller = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_install_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    $installerRevision = if ($updateCommit) { $updateCommit } else { $Ref }
    $installerUrl = "https://raw.githubusercontent.com/$Repository/$installerRevision/install.ps1"
    $commitLink = if ($updateCommit) {
        Format-LofiATCCommitLink -Repository $Repository -Commit $updateCommit
    }
    else {
        $null
    }

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $tempInstaller -UseBasicParsing
        $installerParameters = @{
            InstallRoot           = $InstallRoot
            Ref                   = $Ref
            Repository            = $Repository
            Revision              = $updateCommit
            SkipPowerShellProfile = $true
        }
        if (-not $updateCommit) {
            $installerParameters.SkipCommitResolution = $true
        }

        & $tempInstaller @installerParameters
        if ($updateCommit) {
            Write-Host "Updated commit: $commitLink (ref: $Ref)"
        }
        return
    }
    finally {
        if (Test-Path $tempInstaller) {
            Remove-Item -Path $tempInstaller -Force
        }
    }
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

.PARAMETER Version
Shows the installed repository, ref, commit, timestamp, and install paths.

.PARAMETER SourceDiffLimit
Limits the number of added and removed sources printed by -UpdateSources. Use 0 to show all changes.

.PARAMETER Ref
Repository ref to use with -UpdateSources. Defaults to the ref recorded by the installer.

.PARAMETER ShowLofiTrack
Uses OCR to show the current Lofi Girl track in persistent map mode.
#>
    [CmdletBinding()]
    param (
        [switch]$IncludeWebcamIfAvailable,
        [switch]$NoLofiMusic,
        [switch]$RandomATC,
        [switch]$PlayLofiGirlVideo,
        [switch]$ShowLofiTrack,
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
        [switch]$Version,
        [string]$Ref = (Get-LofiATCInstallRef),
        [string]$Repository = (Get-LofiATCInstallRepository),
        [ValidateRange(0,10000)]
        [int]$SourceDiffLimit = 50
    )

    if ($Version) {
        Get-LofiATCVersion
        return
    }

    if ($UpdateSources) {
        Update-LofiATCSources -DiffLimit $SourceDiffLimit -Ref $Ref -Repository $Repository
        return
    }

    $scriptPath = Get-LofiATCInstalledScriptPath
    if (-not (Test-Path $scriptPath)) {
        throw "lofiatc.ps1 was not found at $scriptPath. Re-run the installer or set LOFIATC_INSTALL_ROOT."
    }

    $forwardedParameters = @{}
    foreach ($key in $PSBoundParameters.Keys) {
        if ($key -ne 'UpdateSources' -and $key -ne 'Version' -and $key -ne 'SourceDiffLimit' -and $key -ne 'Ref' -and $key -ne 'Repository') {
            $forwardedParameters[$key] = $PSBoundParameters[$key]
        }
    }

    & $scriptPath @forwardedParameters
}

Export-ModuleMember -Function lofiatc, Update-LofiATC, Update-LofiATCSources, Get-LofiATCVersion
