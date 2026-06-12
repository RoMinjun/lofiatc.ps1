Set-StrictMode -Version Latest

Describe 'LofiATC module updater' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifest = Join-Path $repoRoot 'packaging/LofiATC/LofiATC.psd1'
        Remove-Module LofiATC -Force -ErrorAction SilentlyContinue
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

    It 'updates sources from the installed ref by default' {
        $installRoot = Join-Path $TestDrive 'source-update'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        'ICAO,Channel Description,Stream URL' | Set-Content -Path (Join-Path $installRoot 'liveatc_sources.csv') -Encoding UTF8
        [pscustomobject]@{
            Repository = 'RoMinjun/lofiatc.ps1'
            Ref        = 'feature/install-module-command'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            $Uri | Should -Be 'https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/feature/install-module-command/liveatc_sources.csv'
            @'
ICAO,Channel Description,Stream URL
KDKX,KDKX CTAF,https://www.liveatc.net/play/kdkx_ctaf.pls
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        Update-LofiATCSources -InstallRoot $installRoot

        Select-String -Path (Join-Path $installRoot 'liveatc_sources.csv') -Pattern 'KDKX' | Should -Not -BeNullOrEmpty
    }
}
