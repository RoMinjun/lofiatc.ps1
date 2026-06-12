Set-StrictMode -Version Latest

Describe 'LofiATC module updater' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifest = Join-Path $repoRoot 'packaging/LofiATC/LofiATC.psd1'
        Import-Module $moduleManifest -Force
    }

    AfterAll {
        Remove-Module LofiATC -Force -ErrorAction SilentlyContinue
    }

    It 'runs the downloaded installer without mutating the PowerShell profile' {
        $installRoot = Join-Path $TestDrive 'lofiatc'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $argsPath = Join-Path $TestDrive 'installer-args.json'
        $env:LOFIATC_TEST_INSTALLER_ARGS = $argsPath

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            @'
param(
    [string]$InstallRoot,
    [string]$Ref,
    [string]$Repository,
    [switch]$SkipPowerShellProfile
)

[pscustomobject]@{
    InstallRoot = $InstallRoot
    Ref = $Ref
    Repository = $Repository
    SkipPowerShellProfile = $SkipPowerShellProfile.IsPresent
} | ConvertTo-Json | Set-Content -Path $env:LOFIATC_TEST_INSTALLER_ARGS -Encoding UTF8
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        try {
            Update-LofiATC -InstallRoot $installRoot -Ref 'feature/install-module-command' -Repository 'RoMinjun/lofiatc.ps1'

            $installerArgs = Get-Content -Path $argsPath -Raw | ConvertFrom-Json
            $installerArgs.InstallRoot | Should -Be $installRoot
            $installerArgs.Ref | Should -Be 'feature/install-module-command'
            $installerArgs.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
            $installerArgs.SkipPowerShellProfile | Should -BeTrue
        }
        finally {
            Remove-Item Env:\LOFIATC_TEST_INSTALLER_ARGS -ErrorAction SilentlyContinue
        }
    }
}
