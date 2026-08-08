[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$ModuleRoot,
    [string]$ShellShimPath,
    [string]$PowerShellProfilePath,
    [string]$Ref = 'main',
    [string]$Repository = 'RoMinjun/lofiatc.ps1',
    [string]$Revision,
    [string]$SourcePath,
    [switch]$SkipCommitResolution,
    [switch]$SkipShellShim,
    [switch]$SkipPowerShellProfile,
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LofiATCIsWindows = $env:OS -eq 'Windows_NT'

Function Get-DefaultInstallRoot {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'lofiatc')
    }

    return (Join-Path $HOME '.local/share/lofiatc')
}

Function Get-DefaultModuleRoot {
    $modulePath = @(
        $env:PSModulePath -split [System.IO.Path]::PathSeparator |
            Where-Object { $_ -and $_.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase) }
    ) | Select-Object -First 1

    if ($modulePath) {
        return (Join-Path $modulePath 'LofiATC')
    }

    return (Join-Path $HOME '.local/share/powershell/Modules/LofiATC')
}

Function Get-DefaultShellShimPath {
    if ($script:LofiATCIsWindows) {
        return $null
    }

    return (Join-Path $HOME '.local/bin/lofiatc')
}

Function Write-LofiATCInstallMetadata {
    param(
        [string]$Path,
        [string]$Repository,
        [string]$Ref,
        [string]$Commit,
        [string]$InstallRoot,
        [string]$ModuleRoot,
        [string]$ShellShimPath,
        [bool]$ShellShimManaged,
        [string]$PowerShellProfilePath,
        [bool]$PowerShellProfileManaged
    )

    $metadata = [pscustomobject]@{
        Repository               = $Repository
        Ref                      = $Ref
        Commit                   = $Commit
        InstalledAtUtc           = [DateTime]::UtcNow.ToString('o')
        InstallRoot              = $InstallRoot
        ModuleRoot               = $ModuleRoot
        ShellShimPath            = $ShellShimPath
        ShellShimManaged         = $ShellShimManaged
        PowerShellProfilePath    = $PowerShellProfilePath
        PowerShellProfileManaged = $PowerShellProfileManaged
    }

    $metadataPath = Join-Path $Path '.lofiatc-install.json'
    $metadata | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8
}

Function Get-LofiATCInstallMetadata {
    param([string]$Path)

    $metadataPath = Join-Path $Path '.lofiatc-install.json'
    if (-not (Test-Path $metadataPath)) {
        return $null
    }

    try {
        return (Get-Content -Path $metadataPath -Raw | ConvertFrom-Json)
    }
    catch {
        Write-Warning "Could not read existing install metadata at $metadataPath."
        return $null
    }
}

Function Get-LofiATCSourceCommit {
    param(
        [string]$SourcePath,
        [string]$Repository,
        [string]$Ref,
        [string]$Revision,
        [switch]$SkipCommitResolution
    )

    if (-not [string]::IsNullOrWhiteSpace($Revision)) {
        return $Revision.ToLowerInvariant()
    }

    if ($SourcePath -and (Test-Path (Join-Path $SourcePath '.git'))) {
        $workingTreeChanges = git -C $SourcePath status --porcelain --untracked-files=no 2>$null
        if ($LASTEXITCODE -eq 0 -and $workingTreeChanges) {
            Write-Warning "The local source checkout has uncommitted changes, so the installed commit will be recorded as unknown."
            return $null
        }

        $sourceCommit = git -C $SourcePath rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($sourceCommit)) {
            return $sourceCommit.Trim()
        }
    }

    if ($SourcePath) {
        return $null
    }

    if ($SkipCommitResolution) {
        return $null
    }

    try {
        $escapedRef = [System.Uri]::EscapeDataString($Ref)
        $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/commits/$escapedRef" -Headers @{
            Accept = 'application/vnd.github+json'
        }
        if ($commit.sha) {
            return [string]$commit.sha
        }
    }
    catch {
        Write-Warning "Could not resolve '$Ref' to a commit hash. Installing by ref instead. $($_.Exception.Message)"
    }

    return $null
}

Function Test-LofiATCPathsOverlap {
    param(
        [string]$First,
        [string]$Second
    )

    $firstPath = [System.IO.Path]::GetFullPath($First).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $secondPath = [System.IO.Path]::GetFullPath($Second).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = if ($script:LofiATCIsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }
    $separator = [System.IO.Path]::DirectorySeparatorChar

    return (
        $firstPath.Equals($secondPath, $comparison) -or
        $firstPath.StartsWith("$secondPath$separator", $comparison) -or
        $secondPath.StartsWith("$firstPath$separator", $comparison)
    )
}

Function Test-LofiATCStagedInstall {
    param(
        [string]$StagedInstallRoot,
        [string]$StagedModuleRoot
    )

    $requiredAppPaths = @(
        'lofiatc.ps1',
        'atc_sources.csv',
        'liveatc_sources.csv',
        'modules',
        'templates',
        'install.ps1',
        'uninstall.ps1',
        '.lofiatc-install.json'
    )

    foreach ($relativePath in $requiredAppPaths) {
        $candidate = Join-Path $StagedInstallRoot $relativePath
        if (-not (Test-Path $candidate)) {
            throw "Staged install is missing required path: $relativePath"
        }
    }

    $manifestPath = Join-Path $StagedModuleRoot 'LofiATC.psd1'
    $modulePath = Join-Path $StagedModuleRoot 'LofiATC.psm1'
    if (-not (Test-Path $manifestPath) -or -not (Test-Path $modulePath)) {
        throw "Staged PowerShell module is incomplete: $StagedModuleRoot"
    }

    Test-ModuleManifest -Path $manifestPath -ErrorAction Stop | Out-Null

    $powerShellExecutable = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $escapedManifestPath = $manifestPath.Replace("'", "''")
    $validationScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$escapedManifestPath' -Force
foreach (`$commandName in 'lofiatc', 'Update-LofiATC', 'Update-LofiATCSources', 'Get-LofiATCVersion') {
    if (-not (Get-Command `$commandName -ErrorAction SilentlyContinue)) {
        throw "Staged module did not export required command: `$commandName"
    }
}
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($validationScript))
    $validationOutput = & $powerShellExecutable -NoProfile -NonInteractive -EncodedCommand $encodedCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Staged module validation failed: $($validationOutput -join [Environment]::NewLine)"
    }
}

Function Move-LofiATCDirectoryIntoPlace {
    param(
        [string]$StagedPath,
        [string]$TargetPath,
        [string]$BackupPath
    )

    if (Test-Path $TargetPath) {
        Move-Item -LiteralPath $TargetPath -Destination $BackupPath
    }

    Move-Item -LiteralPath $StagedPath -Destination $TargetPath
}

Function ConvertTo-ShellSingleQuotedString {
    param([string]$Value)

    return "'$($Value.Replace("'", "'\''"))'"
}

Function Install-LofiATCShellShim {
    param(
        [string]$ShimPath,
        [string]$TargetScriptPath
    )

    if (-not $ShimPath) {
        return
    }

    $shimDir = Split-Path -Parent $ShimPath
    if ($shimDir -and -not (Test-Path $shimDir)) {
        New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    }

    $quotedTarget = ConvertTo-ShellSingleQuotedString -Value $TargetScriptPath
    $shimContent = @"
#!/usr/bin/env sh
exec pwsh -NoProfile -File $quotedTarget "`$@"
"@

    $shimContent = $shimContent -replace "`r`n", "`n"
    Set-Content -Path $ShimPath -Value $shimContent -Encoding UTF8

    $chmod = Get-Command chmod -ErrorAction SilentlyContinue
    if ($chmod) {
        & $chmod +x $ShimPath
    }

    $pathEntries = @($env:PATH -split [System.IO.Path]::PathSeparator)
    if ($shimDir -and $shimDir -notin $pathEntries) {
        Write-Warning "$shimDir is not currently in PATH. Add it to PATH to run 'lofiatc' from bash/zsh/fish."
    }

    Write-Host "Installed shell launcher to $ShimPath"
}

Function Get-LofiATCPowerShellProfilePath {
    if ($PROFILE -and $PROFILE.PSObject.Properties['CurrentUserCurrentHost']) {
        return [string]$PROFILE.CurrentUserCurrentHost
    }

    return [string]$PROFILE
}

Function Install-LofiATCPowerShellProfileImport {
    param([string]$ProfilePath)

    if (-not $ProfilePath) {
        return
    }

    $profileDir = Split-Path -Parent $ProfilePath
    if ($profileDir -and -not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    $profileContent = if (Test-Path $ProfilePath) {
        Get-Content -Path $ProfilePath -Raw
    }
    else {
        ''
    }

    if ($profileContent -match '(?m)^# >>> lofiatc module import$') {
        Write-Host "PowerShell profile already imports LofiATC: $ProfilePath"
        return
    }

    $profileBlock = @'

# >>> lofiatc module import
Import-Module LofiATC -ErrorAction SilentlyContinue
# <<< lofiatc module import
'@

    Add-Content -Path $ProfilePath -Value $profileBlock
    Write-Host "Added LofiATC import to PowerShell profile: $ProfilePath"
}

Function Remove-LofiATCPowerShellProfileImport {
    param([string]$ProfilePath)

    if (-not $ProfilePath -or -not (Test-Path $ProfilePath)) {
        return
    }

    $profileContent = Get-Content -Path $ProfilePath -Raw
    $updatedContent = $profileContent -replace '(?s)\r?\n?# >>> lofiatc module import\r?\nImport-Module LofiATC -ErrorAction SilentlyContinue\r?\n# <<< lofiatc module import\r?\n?', "`r`n"

    if ($updatedContent -ne $profileContent) {
        Set-Content -Path $ProfilePath -Value $updatedContent
        Write-Host "Removed LofiATC import from PowerShell profile: $ProfilePath"
    }
}

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultInstallRoot
}

$existingMetadata = Get-LofiATCInstallMetadata -Path $InstallRoot
$moduleRootFromMetadata = (
    -not $PSBoundParameters.ContainsKey('ModuleRoot') -and
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['ModuleRoot'] -and
    -not [string]::IsNullOrWhiteSpace($existingMetadata.ModuleRoot)
)
$shellShimFromMetadata = (
    -not $PSBoundParameters.ContainsKey('ShellShimPath') -and
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['ShellShimPath']
)
$profilePathFromMetadata = (
    -not $PSBoundParameters.ContainsKey('PowerShellProfilePath') -and
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['PowerShellProfilePath'] -and
    -not [string]::IsNullOrWhiteSpace($existingMetadata.PowerShellProfilePath)
)

if ($moduleRootFromMetadata) {
    $ModuleRoot = [string]$existingMetadata.ModuleRoot
}
elseif (-not $ModuleRoot) {
    $ModuleRoot = Get-DefaultModuleRoot
}

if ($shellShimFromMetadata) {
    $ShellShimPath = [string]$existingMetadata.ShellShimPath
}
elseif (-not $ShellShimPath) {
    $ShellShimPath = Get-DefaultShellShimPath
}

if ($profilePathFromMetadata) {
    $PowerShellProfilePath = [string]$existingMetadata.PowerShellProfilePath
}
elseif (-not $PowerShellProfilePath) {
    $PowerShellProfilePath = Get-LofiATCPowerShellProfilePath
}

if (
    $Uninstall -and
    -not $PSBoundParameters.ContainsKey('SkipPowerShellProfile') -and
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['PowerShellProfileManaged'] -and
    -not [bool]$existingMetadata.PowerShellProfileManaged
) {
    $SkipPowerShellProfile = $true
}

$shellShimManaged = if (-not $script:LofiATCIsWindows -and -not $SkipShellShim) {
    $true
}
elseif (
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['ShellShimManaged']
) {
    [bool]$existingMetadata.ShellShimManaged
}
else {
    $false
}

$powerShellProfileManaged = if (-not $SkipPowerShellProfile) {
    $true
}
elseif (
    $existingMetadata -and
    $existingMetadata.PSObject.Properties['PowerShellProfileManaged']
) {
    [bool]$existingMetadata.PowerShellProfileManaged
}
else {
    $false
}

if ($Uninstall) {
    if (Test-Path $ModuleRoot) {
        Remove-Item -Path $ModuleRoot -Recurse -Force
        Write-Host "Removed PowerShell module: $ModuleRoot"
    }

    if (-not $SkipPowerShellProfile) {
        Remove-LofiATCPowerShellProfileImport -ProfilePath $PowerShellProfilePath
    }

    $removeShellShim = (
        $PSBoundParameters.ContainsKey('ShellShimPath') -or
        -not $existingMetadata -or
        -not $existingMetadata.PSObject.Properties['ShellShimManaged'] -or
        [bool]$existingMetadata.ShellShimManaged
    )
    if ($removeShellShim -and $ShellShimPath -and (Test-Path $ShellShimPath)) {
        Remove-Item -Path $ShellShimPath -Force
        Write-Host "Removed shell launcher: $ShellShimPath"
    }

    if (Test-Path $InstallRoot) {
        Remove-Item -Path $InstallRoot -Recurse -Force
        Write-Host "Removed install directory: $InstallRoot"
    }

    Write-Host "User data was left intact. Remove it manually from APPDATA/lofiatc if desired."
    return
}

$runtimeFiles = @(
    'lofiatc.ps1',
    'atc_sources.csv',
    'liveatc_sources.csv',
    'modules',
    'templates',
    'install.ps1',
    'uninstall.ps1'
)

$tempRoot = $null
$sourceRoot = $SourcePath
$transactionId = [guid]::NewGuid().ToString('N')
$installParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($InstallRoot))
$moduleParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($ModuleRoot))
$installLeaf = Split-Path -Leaf $InstallRoot
$moduleLeaf = Split-Path -Leaf $ModuleRoot
$stagedInstallRoot = Join-Path $installParent ".$installLeaf.stage.$transactionId"
$stagedModuleRoot = Join-Path $moduleParent ".$moduleLeaf.stage.$transactionId"
$installBackup = Join-Path $installParent ".$installLeaf.backup.$transactionId"
$moduleBackup = Join-Path $moduleParent ".$moduleLeaf.backup.$transactionId"
$installCommitted = $false
$moduleCommitted = $false
$transactionSucceeded = $false

if (Test-LofiATCPathsOverlap -First $InstallRoot -Second $ModuleRoot) {
    throw "InstallRoot and ModuleRoot must be separate, non-nested directories."
}

try {
    $sourceCommit = Get-LofiATCSourceCommit `
        -SourcePath $sourceRoot `
        -Repository $Repository `
        -Ref $Ref `
        -Revision $Revision `
        -SkipCommitResolution:$SkipCommitResolution

    if (-not $sourceRoot) {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_install_{0}" -f $transactionId)
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $zipPath = Join-Path $tempRoot 'lofiatc.zip'
        $archiveUrl = if ($sourceCommit) {
            "https://github.com/$Repository/archive/$sourceCommit.zip"
        }
        else {
            "https://github.com/$Repository/archive/refs/heads/$Ref.zip"
        }
        Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

        $sourceRoot = Get-ChildItem -Path $tempRoot -Directory | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $sourceRoot -or -not (Test-Path $sourceRoot)) {
        throw "Source path not found: $sourceRoot"
    }

    $moduleSource = Join-Path $sourceRoot 'packaging/LofiATC'
    if (-not (Test-Path $moduleSource)) {
        if (-not $SourcePath -and $Ref -eq 'main') {
            Write-Warning "The downloaded source archive does not contain packaging/LofiATC. If you downloaded install.ps1 from a non-main branch, rerun it with -Ref <branch-name>."
        }

        throw "Module source not found: $moduleSource"
    }

    New-Item -ItemType Directory -Path $installParent -Force | Out-Null
    New-Item -ItemType Directory -Path $moduleParent -Force | Out-Null
    New-Item -ItemType Directory -Path $stagedInstallRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $stagedModuleRoot -Force | Out-Null

    foreach ($item in $runtimeFiles) {
        $source = Join-Path $sourceRoot $item
        if (-not (Test-Path $source)) {
            throw "Required runtime path not found in source: $item"
        }

        Copy-Item -LiteralPath $source -Destination $stagedInstallRoot -Recurse -Force
    }

    Copy-Item -Path (Join-Path $moduleSource '*') -Destination $stagedModuleRoot -Recurse -Force
    Write-LofiATCInstallMetadata `
        -Path $stagedInstallRoot `
        -Repository $Repository `
        -Ref $Ref `
        -Commit $sourceCommit `
        -InstallRoot ([System.IO.Path]::GetFullPath($InstallRoot)) `
        -ModuleRoot ([System.IO.Path]::GetFullPath($ModuleRoot)) `
        -ShellShimPath $ShellShimPath `
        -ShellShimManaged $shellShimManaged `
        -PowerShellProfilePath $PowerShellProfilePath `
        -PowerShellProfileManaged $powerShellProfileManaged

    Test-LofiATCStagedInstall -StagedInstallRoot $stagedInstallRoot -StagedModuleRoot $stagedModuleRoot

    Move-LofiATCDirectoryIntoPlace -StagedPath $stagedInstallRoot -TargetPath $InstallRoot -BackupPath $installBackup
    $installCommitted = $true
    Move-LofiATCDirectoryIntoPlace -StagedPath $stagedModuleRoot -TargetPath $ModuleRoot -BackupPath $moduleBackup
    $moduleCommitted = $true

    $moduleManifest = Join-Path $ModuleRoot 'LofiATC.psd1'
    Import-Module $moduleManifest -Force -Global

    if (-not $SkipPowerShellProfile) {
        Install-LofiATCPowerShellProfileImport -ProfilePath $PowerShellProfilePath
    }

    if (-not $script:LofiATCIsWindows -and -not $SkipShellShim) {
        Install-LofiATCShellShim -ShimPath $ShellShimPath -TargetScriptPath (Join-Path $InstallRoot 'lofiatc.ps1')
    }

    $transactionSucceeded = $true
}
catch {
    $installError = $_
    Remove-Module LofiATC -Force -ErrorAction SilentlyContinue

    if ($moduleCommitted -and (Test-Path $ModuleRoot)) {
        Remove-Item -LiteralPath $ModuleRoot -Recurse -Force
    }
    if (Test-Path $moduleBackup) {
        Move-Item -LiteralPath $moduleBackup -Destination $ModuleRoot
    }

    if ($installCommitted -and (Test-Path $InstallRoot)) {
        Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    }
    if (Test-Path $installBackup) {
        Move-Item -LiteralPath $installBackup -Destination $InstallRoot
    }

    $restoredManifest = Join-Path $ModuleRoot 'LofiATC.psd1'
    if (Test-Path $restoredManifest) {
        Import-Module $restoredManifest -Force -Global -ErrorAction SilentlyContinue
    }

    throw $installError
}
finally {
    foreach ($cleanupPath in @($stagedInstallRoot, $stagedModuleRoot, $tempRoot)) {
        if ($cleanupPath -and (Test-Path $cleanupPath)) {
            Remove-Item -LiteralPath $cleanupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($transactionSucceeded) {
        foreach ($backupPath in @($installBackup, $moduleBackup)) {
            if (Test-Path $backupPath) {
                Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$shadowingCommands = @(
    Get-Command lofiatc -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -ne 'Function' -or $_.Source -ne 'LofiATC' }
)

if ($shadowingCommands.Count -gt 0) {
    Write-Warning "Another command named 'lofiatc' exists. If tab completion does not work in a new shell, remove the older command or add 'Import-Module LofiATC' to your PowerShell profile."
    foreach ($command in $shadowingCommands) {
        $location = if ($command.Path) { $command.Path } else { $command.Source }
        Write-Warning "Conflicting command: $($command.CommandType) $($command.Name) $location"
    }
}

Write-Host "Installed lofiatc app files to $InstallRoot"
Write-Host "Installed PowerShell command module to $ModuleRoot"
if ($script:LofiATCIsWindows) {
    Write-Host "Open a new PowerShell session, then run: lofiatc"
}
else {
    Write-Host "Open a new PowerShell session for completion/help, or run 'lofiatc' from your shell if the launcher directory is in PATH."
}
