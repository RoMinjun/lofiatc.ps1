Set-StrictMode -Version Latest

Describe 'LofiATC installer' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $installScript = Join-Path $repoRoot 'install.ps1'
        $uninstallScript = Join-Path $repoRoot 'uninstall.ps1'
    }

    AfterEach {
        Remove-Module LofiATC -Force -ErrorAction SilentlyContinue
    }

    It 'replaces app and module directories exactly and records install metadata' {
        $installRoot = Join-Path $TestDrive 'app/lofiatc'
        $moduleRoot = Join-Path $TestDrive 'modules/LofiATC'
        $profilePath = Join-Path $TestDrive 'profile/Microsoft.PowerShell_profile.ps1'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        Set-Content -Path (Join-Path $installRoot 'stale-app-file.txt') -Value 'stale'
        Set-Content -Path (Join-Path $moduleRoot 'stale-module-file.ps1') -Value 'stale'

        & $installScript `
            -InstallRoot $installRoot `
            -ModuleRoot $moduleRoot `
            -PowerShellProfilePath $profilePath `
            -SourcePath $repoRoot `
            -Repository 'RoMinjun/lofiatc.ps1' `
            -Ref 'feature/install-module-command' `
            -Revision 'afe8201234567890afe8201234567890afe82012' `
            -SkipPowerShellProfile `
            -SkipShellShim

        Test-Path (Join-Path $installRoot 'stale-app-file.txt') | Should -BeFalse
        Test-Path (Join-Path $moduleRoot 'stale-module-file.ps1') | Should -BeFalse
        Test-Path (Join-Path $installRoot 'lofiatc.ps1') | Should -BeTrue
        Test-Path (Join-Path $moduleRoot 'LofiATC.psd1') | Should -BeTrue

        $metadata = Get-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Raw | ConvertFrom-Json
        $metadata.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
        $metadata.Ref | Should -Be 'feature/install-module-command'
        $metadata.Commit | Should -Be 'afe8201234567890afe8201234567890afe82012'
        $metadata.InstallRoot | Should -Be ([System.IO.Path]::GetFullPath($installRoot))
        $metadata.ModuleRoot | Should -Be ([System.IO.Path]::GetFullPath($moduleRoot))
        $metadata.ShellShimManaged | Should -BeFalse
        $metadata.PowerShellProfilePath | Should -Be $profilePath
        $metadata.PowerShellProfileManaged | Should -BeFalse

        @(Get-ChildItem -Path (Split-Path -Parent $installRoot) -Force -Filter '.lofiatc.*').Count | Should -Be 0
        @(Get-ChildItem -Path (Split-Path -Parent $moduleRoot) -Force -Filter '.LofiATC.*').Count | Should -Be 0
    }

    It 'leaves the active installation untouched when staged validation fails' {
        $installRoot = Join-Path $TestDrive 'existing-app/lofiatc'
        $moduleRoot = Join-Path $TestDrive 'existing-modules/LofiATC'
        $invalidSource = Join-Path $TestDrive 'invalid-source'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $invalidSource -Force | Out-Null
        Set-Content -Path (Join-Path $installRoot 'active-marker.txt') -Value 'active-app'
        Set-Content -Path (Join-Path $moduleRoot 'active-marker.txt') -Value 'active-module'
        Copy-Item -Path (Join-Path $repoRoot 'lofiatc.ps1') -Destination $invalidSource

        {
            & $installScript `
                -InstallRoot $installRoot `
                -ModuleRoot $moduleRoot `
                -SourcePath $invalidSource `
                -SkipPowerShellProfile `
                -SkipShellShim
        } | Should -Throw

        Get-Content (Join-Path $installRoot 'active-marker.txt') | Should -Be 'active-app'
        Get-Content (Join-Path $moduleRoot 'active-marker.txt') | Should -Be 'active-module'
        @(Get-ChildItem -Path (Split-Path -Parent $installRoot) -Force -Filter '.lofiatc.*').Count | Should -Be 0
        @(Get-ChildItem -Path (Split-Path -Parent $moduleRoot) -Force -Filter '.LofiATC.*').Count | Should -Be 0
    }

    It 'leaves the active installation untouched when a release checksum mismatches' {
        $installRoot = Join-Path $TestDrive 'release-existing/lofiatc'
        $moduleRoot = Join-Path $TestDrive 'release-modules/LofiATC'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        Set-Content -Path (Join-Path $installRoot 'active-marker.txt') -Value 'active-app'
        Set-Content -Path (Join-Path $moduleRoot 'active-marker.txt') -Value 'active-module'

        Mock Invoke-RestMethod {
            param(
                [string]$Uri,
                [hashtable]$Headers
            )

            if ($Uri -like '*/releases/*') {
                return [pscustomobject]@{
                    tag_name = 'v0.2.0'
                    assets   = @(
                        [pscustomobject]@{ name = 'lofiatc-v0.2.0.zip'; browser_download_url = 'https://example.invalid/lofiatc-v0.2.0.zip' },
                        [pscustomobject]@{ name = 'lofiatc-v0.2.0.zip.sha256'; browser_download_url = 'https://example.invalid/lofiatc-v0.2.0.zip.sha256' }
                    )
                }
            }

            return [pscustomobject]@{
                sha = 'db17a101234567890db17a101234567890db17a10'
            }
        }

        Mock Invoke-WebRequest {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            if ($Uri -like '*.sha256') {
                "$('0' * 64)  lofiatc-v0.2.0.zip" | Set-Content -Path $OutFile -Encoding ascii
            }
            else {
                'not a valid or verified archive' | Set-Content -Path $OutFile -Encoding UTF8
            }
        }

        {
            & $installScript `
                -InstallRoot $installRoot `
                -ModuleRoot $moduleRoot `
                -Release v0.2.0 `
                -SkipPowerShellProfile `
                -SkipShellShim
        } | Should -Throw '*SHA-256 checksum mismatch*'

        Get-Content (Join-Path $installRoot 'active-marker.txt') | Should -Be 'active-app'
        Get-Content (Join-Path $moduleRoot 'active-marker.txt') | Should -Be 'active-module'
        @(Get-ChildItem -Path (Split-Path -Parent $installRoot) -Force -Filter '.lofiatc.*').Count | Should -Be 0
        @(Get-ChildItem -Path (Split-Path -Parent $moduleRoot) -Force -Filter '.LofiATC.*').Count | Should -Be 0
    }

    It 'verifies and installs a complete stable release archive' {
        $installRoot = Join-Path $TestDrive 'stable-app/lofiatc'
        $moduleRoot = Join-Path $TestDrive 'stable-modules/LofiATC'
        $fixtureRoot = Join-Path $TestDrive 'release-fixture'
        $packageRoot = Join-Path $fixtureRoot 'lofiatc-v0.2.0'
        $fixtureArchivePath = Join-Path $fixtureRoot 'lofiatc-v0.2.0.zip'
        $fixtureChecksumPath = "$fixtureArchivePath.sha256"
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

        foreach ($path in @('lofiatc.ps1', 'atc_sources.csv', 'liveatc_sources.csv', 'modules', 'templates', 'install.ps1', 'uninstall.ps1', 'packaging')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot $path) -Destination $packageRoot -Recurse -Force
        }

        Compress-Archive -Path $packageRoot -DestinationPath $fixtureArchivePath
        $archiveHash = (Get-FileHash -Path $fixtureArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        "$archiveHash  lofiatc-v0.2.0.zip" | Set-Content -Path $fixtureChecksumPath -Encoding ascii

        Mock Invoke-RestMethod {
            param(
                [string]$Uri,
                [hashtable]$Headers
            )

            if ($Uri -like '*/releases/*') {
                return [pscustomobject]@{
                    tag_name = 'v0.2.0'
                    assets   = @(
                        [pscustomobject]@{ name = 'lofiatc-v0.2.0.zip'; browser_download_url = 'https://example.invalid/lofiatc-v0.2.0.zip' },
                        [pscustomobject]@{ name = 'lofiatc-v0.2.0.zip.sha256'; browser_download_url = 'https://example.invalid/lofiatc-v0.2.0.zip.sha256' }
                    )
                }
            }

            return [pscustomobject]@{
                sha = 'db17a101234567890db17a101234567890db17a10'
            }
        }

        Mock Invoke-WebRequest {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            if ($Uri -like '*.sha256') {
                Copy-Item -LiteralPath $fixtureChecksumPath -Destination $OutFile
            }
            else {
                Copy-Item -LiteralPath $fixtureArchivePath -Destination $OutFile
            }
        }

        & $installScript `
            -InstallRoot $installRoot `
            -ModuleRoot $moduleRoot `
            -Release v0.2.0 `
            -SkipPowerShellProfile `
            -SkipShellShim

        $metadata = Get-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Raw | ConvertFrom-Json
        $metadata.Release | Should -Be 'v0.2.0'
        $metadata.Ref | Should -Be 'v0.2.0'
        $metadata.Commit | Should -Be 'db17a101234567890db17a101234567890db17a10'
        $metadata.ArtifactSha256 | Should -Be $archiveHash
        Test-Path (Join-Path $moduleRoot 'LofiATC.psd1') | Should -BeTrue
    }

    It 'preserves custom install paths and managed profile ownership during updates and uninstall' {
        $installRoot = Join-Path $TestDrive 'custom-app/lofiatc'
        $moduleRoot = Join-Path $TestDrive 'custom-modules/LofiATC'
        $profilePath = Join-Path $TestDrive 'custom-profile/Microsoft.PowerShell_profile.ps1'

        & $installScript `
            -InstallRoot $installRoot `
            -ModuleRoot $moduleRoot `
            -PowerShellProfilePath $profilePath `
            -SourcePath $repoRoot `
            -Revision 'afe8201234567890afe8201234567890afe82012' `
            -SkipShellShim

        & $installScript `
            -InstallRoot $installRoot `
            -SourcePath $repoRoot `
            -Revision 'db17a101234567890db17a101234567890db17a10' `
            -SkipPowerShellProfile `
            -SkipShellShim

        $metadata = Get-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Raw | ConvertFrom-Json
        $metadata.ModuleRoot | Should -Be ([System.IO.Path]::GetFullPath($moduleRoot))
        $metadata.PowerShellProfilePath | Should -Be $profilePath
        $metadata.PowerShellProfileManaged | Should -BeTrue
        $metadata.Commit | Should -Be 'db17a101234567890db17a101234567890db17a10'
        (Get-Content -Path $profilePath -Raw) | Should -Match '# >>> lofiatc module import'

        & $uninstallScript -InstallRoot $installRoot

        Test-Path $installRoot | Should -BeFalse
        Test-Path $moduleRoot | Should -BeFalse
        if (Test-Path $profilePath) {
            (Get-Content -Path $profilePath -Raw) | Should -Not -Match '# >>> lofiatc module import'
        }
    }
}
