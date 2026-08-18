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

    It 'exposes and validates named profile parameters on the installed command' {
        $parameters = (Get-Command lofiatc).Parameters

        $parameters.Keys | Should -Contain 'Profile'
        $parameters.Keys | Should -Contain 'SaveProfile'
        $parameters.Keys | Should -Contain 'ListProfiles'
        $parameters.Keys | Should -Contain 'RemoveProfile'

        $profilePattern = @($parameters.Profile.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] })[0]
        $profilePattern.RegexPattern | Should -Be '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'
    }

    It 'completes saved profile names' {
        $previousUserDataPath = $env:LOFIATC_USER_DATA
        $env:LOFIATC_USER_DATA = Join-Path $TestDrive 'completion-user-data'
        $profilesPath = Join-Path $env:LOFIATC_USER_DATA 'profiles'
        New-Item -ItemType Directory -Path $profilesPath -Force | Out-Null
        '{}' | Set-Content -Path (Join-Path $profilesPath 'Work.json') -Encoding UTF8
        '{}' | Set-Content -Path (Join-Path $profilesPath 'Home.json') -Encoding UTF8

        try {
            $inputScript = 'lofiatc -Profile Wo'
            $completion = TabExpansion2 $inputScript $inputScript.Length
            @($completion.CompletionMatches.CompletionText) | Should -Contain 'Work'
            @($completion.CompletionMatches.CompletionText) | Should -Not -Contain 'Home'
        }
        finally {
            if ($null -eq $previousUserDataPath) {
                Remove-Item Env:\LOFIATC_USER_DATA -ErrorAction SilentlyContinue
            }
            else {
                $env:LOFIATC_USER_DATA = $previousUserDataPath
            }
        }
    }

    It 'runs the downloaded installer without mutating the PowerShell profile' {
        $installRoot = Join-Path $TestDrive 'lofiatc'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $argsPath = Join-Path $TestDrive 'installer-args.json'
        $env:LOFIATC_TEST_INSTALLER_ARGS = $argsPath
        $env:LOFIATC_TEST_INSTALLER_RAN = '0'

        Mock Invoke-RestMethod -ModuleName LofiATC {
            param(
                [string]$Uri,
                [hashtable]$Headers
            )

            return [pscustomobject]@{
                sha = 'afe8201234567890afe8201234567890afe82012'
            }
        }

        Mock Format-LofiATCCommitLink -ModuleName LofiATC {
            param(
                [string]$Repository,
                [string]$Commit
            )

            $env:LOFIATC_TEST_INSTALLER_RAN | Should -Be '0'
            return "$Commit (https://github.com/$Repository/commit/$Commit)"
        }

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            $Uri | Should -Be 'https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/afe8201234567890afe8201234567890afe82012/install.ps1'
            @'
param(
    [string]$InstallRoot,
    [string]$Ref,
    [string]$Repository,
    [string]$Revision,
    [switch]$SkipCommitResolution,
    [switch]$SkipPowerShellProfile
)

[pscustomobject]@{
    InstallRoot = $InstallRoot
    Ref = $Ref
    Repository = $Repository
    Revision = $Revision
    SkipCommitResolution = $SkipCommitResolution.IsPresent
    SkipPowerShellProfile = $SkipPowerShellProfile.IsPresent
} | ConvertTo-Json | Set-Content -Path $env:LOFIATC_TEST_INSTALLER_ARGS -Encoding UTF8
$env:LOFIATC_TEST_INSTALLER_RAN = '1'
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        try {
            $output = Update-LofiATC -InstallRoot $installRoot -Ref 'feature/install-module-command' -Repository 'RoMinjun/lofiatc.ps1' 6>&1

            $installerArgs = Get-Content -Path $argsPath -Raw | ConvertFrom-Json
            $installerArgs.InstallRoot | Should -Be $installRoot
            $installerArgs.Ref | Should -Be 'feature/install-module-command'
            $installerArgs.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
            $installerArgs.Revision | Should -Be 'afe8201234567890afe8201234567890afe82012'
            $installerArgs.SkipCommitResolution | Should -BeFalse
            $installerArgs.SkipPowerShellProfile | Should -BeTrue
            $text = $output -join "`n"
            $text | Should -Match 'Updated commit:'
            $text | Should -Match 'afe8201234567890afe8201234567890afe82012'
            $text | Should -Match 'https://github\.com/RoMinjun/lofiatc\.ps1/commit/afe8201234567890afe8201234567890afe82012'
            $text | Should -Match '\(ref: feature/install-module-command\)'
        }
        finally {
            Remove-Item Env:\LOFIATC_TEST_INSTALLER_ARGS -ErrorAction SilentlyContinue
            Remove-Item Env:\LOFIATC_TEST_INSTALLER_RAN -ErrorAction SilentlyContinue
        }
    }

    It 'does not retry commit resolution in the installer after the updater API request fails' {
        $installRoot = Join-Path $TestDrive 'lofiatc-api-fallback'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $argsPath = Join-Path $TestDrive 'fallback-installer-args.json'
        $env:LOFIATC_TEST_INSTALLER_ARGS = $argsPath

        Mock Invoke-RestMethod -ModuleName LofiATC {
            throw 'Response status code does not indicate success: 504 (Gateway Time-out).'
        }

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            $Uri | Should -Be 'https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/feature/install-module-command/install.ps1'
            @'
param(
    [string]$InstallRoot,
    [string]$Ref,
    [string]$Repository,
    [string]$Revision,
    [switch]$SkipCommitResolution,
    [switch]$SkipPowerShellProfile
)

[pscustomobject]@{
    Revision = $Revision
    SkipCommitResolution = $SkipCommitResolution.IsPresent
} | ConvertTo-Json | Set-Content -Path $env:LOFIATC_TEST_INSTALLER_ARGS -Encoding UTF8
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        try {
            $warnings = Update-LofiATC `
                -InstallRoot $installRoot `
                -Ref 'feature/install-module-command' `
                -Repository 'RoMinjun/lofiatc.ps1' 3>&1

            $installerArgs = Get-Content -Path $argsPath -Raw | ConvertFrom-Json
            $installerArgs.Revision | Should -BeNullOrEmpty
            $installerArgs.SkipCommitResolution | Should -BeTrue
            @($warnings).Count | Should -Be 1
            $warnings[0].ToString() | Should -Match "Could not resolve 'feature/install-module-command' to a commit hash"
        }
        finally {
            Remove-Item Env:\LOFIATC_TEST_INSTALLER_ARGS -ErrorAction SilentlyContinue
        }
    }

    It 'shows the checked-out commit after updating a Git installation' {
        $installRoot = Join-Path $TestDrive 'git-update'
        New-Item -ItemType Directory -Path (Join-Path $installRoot '.git') -Force | Out-Null

        Mock git -ModuleName LofiATC {
            $global:LASTEXITCODE = 0
            if ($args -contains 'rev-parse') {
                return 'db17a101234567890db17a101234567890db17a10'
            }
            if ($args -contains 'get-url') {
                return 'git@github.com:RoMinjun/lofiatc.ps1.git'
            }
        }

        $output = Update-LofiATC -InstallRoot $installRoot 6>&1

        $text = $output -join "`n"
        $text | Should -Match 'Updated commit:'
        $text | Should -Match 'db17a101234567890db17a101234567890db17a10'
        $text | Should -Match 'https://github\.com/RoMinjun/lofiatc\.ps1/commit/db17a101234567890db17a101234567890db17a10'
        Should -Invoke git -ModuleName LofiATC -ParameterFilter {
            $args -contains 'pull' -and $args -contains '--ff-only'
        }
        Should -Invoke git -ModuleName LofiATC -ParameterFilter {
            $args -contains 'rev-parse' -and $args -contains 'HEAD'
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

        Mock Invoke-RestMethod -ModuleName LofiATC {
            param(
                [uri]$Uri,
                [hashtable]$Headers
            )

            $Uri.OriginalString | Should -Be 'https://api.github.com/repos/RoMinjun/lofiatc.ps1/commits/feature%2Finstall-module-command'
            return [pscustomobject]@{
                sha = 'afe8201234567890afe8201234567890afe82012'
            }
        }

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            $Uri | Should -Be 'https://raw.githubusercontent.com/RoMinjun/lofiatc.ps1/afe8201234567890afe8201234567890afe82012/liveatc_sources.csv'
            @'
ICAO,Channel Description,Stream URL
KDKX,KDKX CTAF,https://www.liveatc.net/play/kdkx_ctaf.pls
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        $output = Update-LofiATCSources -InstallRoot $installRoot 6>&1

        Select-String -Path (Join-Path $installRoot 'liveatc_sources.csv') -Pattern 'KDKX' | Should -Not -BeNullOrEmpty
        $text = $output -join "`n"
        $text | Should -Match 'Source commit:'
        $text | Should -Match 'afe8201234567890afe8201234567890afe82012'
        $text | Should -Match 'https://github\.com/RoMinjun/lofiatc\.ps1/commit/afe8201234567890afe8201234567890afe82012'
    }

    It 'shows the source commit when the downloaded CSV has no changes' {
        $installRoot = Join-Path $TestDrive 'source-update-no-changes'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        @'
ICAO,Channel Description,Stream URL
KDKX,KDKX CTAF,https://www.liveatc.net/play/kdkx_ctaf.pls
'@ | Set-Content -Path (Join-Path $installRoot 'liveatc_sources.csv') -Encoding UTF8

        Mock Invoke-RestMethod -ModuleName LofiATC {
            return [pscustomobject]@{
                sha = 'e72d16a1234567890e72d16a1234567890e72d16'
            }
        }

        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            @'
ICAO,Channel Description,Stream URL
KDKX,KDKX CTAF,https://www.liveatc.net/play/kdkx_ctaf.pls
'@ | Set-Content -Path $OutFile -Encoding UTF8
        }

        $output = Update-LofiATCSources -InstallRoot $installRoot -Ref main 6>&1
        $text = $output -join "`n"

        $text | Should -Match 'Source commit:'
        $text | Should -Match 'e72d16a1234567890e72d16a1234567890e72d16'
        $text | Should -Match 'https://github\.com/RoMinjun/lofiatc\.ps1/commit/e72d16a1234567890e72d16a1234567890e72d16'
        $text | Should -Match '\(ref: main\)'
        $text | Should -Match 'No added or removed sources\.'
    }

    It 'reports installed version and path metadata' {
        $installRoot = Join-Path $TestDrive 'version-info'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        [pscustomobject]@{
            Repository            = 'RoMinjun/lofiatc.ps1'
            Ref                   = 'main'
            Commit                = '1234567890abcdef1234567890abcdef12345678'
            InstalledAtUtc        = '2026-06-20T12:00:00.0000000Z'
            InstallRoot           = $installRoot
            ModuleRoot            = 'C:\Modules\LofiATC'
            ShellShimPath         = $null
            PowerShellProfilePath = 'C:\Profiles\Microsoft.PowerShell_profile.ps1'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        $version = Get-LofiATCVersion -InstallRoot $installRoot

        $version.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
        $version.Ref | Should -Be 'main'
        $version.Commit | Should -Be '1234567890abcdef1234567890abcdef12345678'
        $version.InstallRoot | Should -Be $installRoot
        $version.ModuleRoot | Should -Be 'C:\Modules\LofiATC'
        $version.PowerShellProfilePath | Should -Be 'C:\Profiles\Microsoft.PowerShell_profile.ps1'

        $env:LOFIATC_INSTALL_ROOT = $installRoot
        try {
            $commandVersion = lofiatc -Version
            $commandVersion.Commit | Should -Be '1234567890abcdef1234567890abcdef12345678'
        }
        finally {
            Remove-Item Env:\LOFIATC_INSTALL_ROOT -ErrorAction SilentlyContinue
        }
    }
}
