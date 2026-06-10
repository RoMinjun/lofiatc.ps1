[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$ModuleRoot,
    [string]$ShellShimPath,
    [switch]$SkipPowerShellProfile,
    [switch]$RemoveUserData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Function Get-DefaultInstallRoot {
    if ($env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'lofiatc')
    }

    return (Join-Path $HOME '.local/share/lofiatc')
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

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultInstallRoot
}

$installScript = Join-Path $InstallRoot 'install.ps1'
if (-not (Test-Path $installScript)) {
    $installScript = Join-Path $PSScriptRoot 'install.ps1'
}

if (-not (Test-Path $installScript)) {
    throw "install.ps1 was not found. Cannot run uninstall."
}

$uninstallParams = @{
    InstallRoot = $InstallRoot
    Uninstall   = $true
}

if ($ModuleRoot) {
    $uninstallParams.ModuleRoot = $ModuleRoot
}

if ($ShellShimPath) {
    $uninstallParams.ShellShimPath = $ShellShimPath
}

if ($SkipPowerShellProfile) {
    $uninstallParams.SkipPowerShellProfile = $true
}

& $installScript @uninstallParams

if ($RemoveUserData) {
    $userDataPath = Get-LofiATCUserDataPath
    if (Test-Path $userDataPath) {
        Remove-Item -Path $userDataPath -Recurse -Force
        Write-Host "Removed user data directory: $userDataPath"
    }
}
