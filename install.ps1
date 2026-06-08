[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$ModuleRoot,
    [string]$Ref = 'main',
    [string]$Repository = 'RoMinjun/lofiatc.ps1',
    [string]$SourcePath,
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

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultInstallRoot
}

if (-not $ModuleRoot) {
    $ModuleRoot = Get-DefaultModuleRoot
}

if ($Uninstall) {
    if (Test-Path $ModuleRoot) {
        Remove-Item -Path $ModuleRoot -Recurse -Force
        Write-Host "Removed PowerShell module: $ModuleRoot"
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
    throw "Module source not found: $moduleSource"
}

New-Item -ItemType Directory -Path $ModuleRoot -Force | Out-Null
Copy-Item -Path (Join-Path $moduleSource '*') -Destination $ModuleRoot -Recurse -Force

if ($tempRoot -and (Test-Path $tempRoot)) {
    Remove-Item -Path $tempRoot -Recurse -Force
}

Write-Host "Installed lofiatc app files to $InstallRoot"
Write-Host "Installed PowerShell command module to $ModuleRoot"
Write-Host "Open a new PowerShell session, then run: lofiatc"
