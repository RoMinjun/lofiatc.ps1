[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$ModuleRoot,
    [string]$ShellShimPath,
    [string]$Ref = 'main',
    [string]$Repository = 'RoMinjun/lofiatc.ps1',
    [string]$SourcePath,
    [switch]$SkipShellShim,
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Function Get-DefaultInstallRoot {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'lofiatc')
    }

    return (Join-Path $HOME '.local/share/lofiatc')
}

Function Test-LofiATCWindows {
    return $env:OS -eq 'Windows_NT'
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
    if (Test-LofiATCWindows) {
        return $null
    }

    return (Join-Path $HOME '.local/bin/lofiatc')
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

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultInstallRoot
}

if (-not $ModuleRoot) {
    $ModuleRoot = Get-DefaultModuleRoot
}

if (-not $ShellShimPath) {
    $ShellShimPath = Get-DefaultShellShimPath
}

if ($Uninstall) {
    if (Test-Path $ModuleRoot) {
        Remove-Item -Path $ModuleRoot -Recurse -Force
        Write-Host "Removed PowerShell module: $ModuleRoot"
    }

    if ($ShellShimPath -and (Test-Path $ShellShimPath)) {
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
    'install.ps1'
)

$tempRoot = $null
$sourceRoot = $SourcePath

if (-not $sourceRoot) {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_install_{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $zipPath = Join-Path $tempRoot 'lofiatc.zip'
    $archiveUrl = "https://github.com/$Repository/archive/refs/heads/$Ref.zip"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

    $sourceRoot = Get-ChildItem -Path $tempRoot -Directory | Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path $sourceRoot)) {
    throw "Source path not found: $sourceRoot"
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

foreach ($item in $runtimeFiles) {
    $source = Join-Path $sourceRoot $item
    if (-not (Test-Path $source)) {
        continue
    }

    $destination = Join-Path $InstallRoot $item
    if ((Get-Item $source).PSIsContainer) {
        if (-not (Test-Path $destination)) {
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
        }

        Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
    }
    else {
        Copy-Item -Path $source -Destination $destination -Force
    }
}

$moduleSource = Join-Path $sourceRoot 'packaging/LofiATC'
if (-not (Test-Path $moduleSource)) {
    if (-not $SourcePath -and $Ref -eq 'main') {
        Write-Warning "The downloaded source archive does not contain packaging/LofiATC. If you downloaded install.ps1 from a non-main branch, rerun it with -Ref <branch-name>."
    }

    throw "Module source not found: $moduleSource"
}

New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $moduleSource '*') -Destination $ModuleRoot -Recurse -Force

$moduleManifest = Join-Path $ModuleRoot 'LofiATC.psd1'
Import-Module $moduleManifest -Force -Global

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

if (-not (Test-LofiATCWindows) -and -not $SkipShellShim) {
    Install-LofiATCShellShim -ShimPath $ShellShimPath -TargetScriptPath (Join-Path $InstallRoot 'lofiatc.ps1')
}

if ($tempRoot -and (Test-Path $tempRoot)) {
    Remove-Item -Path $tempRoot -Recurse -Force
}

Write-Host "Installed lofiatc app files to $InstallRoot"
Write-Host "Installed PowerShell command module to $ModuleRoot"
if (Test-LofiATCWindows) {
    Write-Host "Open a new PowerShell session, then run: lofiatc"
}
else {
    Write-Host "Open a new PowerShell session for completion/help, or run 'lofiatc' from your shell if the launcher directory is in PATH."
}
