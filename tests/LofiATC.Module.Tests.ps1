Set-StrictMode -Version Latest

Describe 'LofiATC module updater' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $scriptEntryPoint = Join-Path $repoRoot 'lofiatc.ps1'
        $moduleManifest = Join-Path $repoRoot 'packaging/LofiATC/LofiATC.psd1'
        $installedOnlyParameters = @('UpdateSources', 'Version', 'SourceDiffLimit', 'Ref', 'Repository')
        Remove-Module LofiATC -Force -ErrorAction SilentlyContinue
        Import-Module $moduleManifest -Force

        function Get-TestParameterAstMap {
            param([System.Management.Automation.Language.ParamBlockAst]$ParamBlock)

            $result = @{}
            foreach ($parameter in $ParamBlock.Parameters) {
                $result[$parameter.Name.VariablePath.UserPath] = $parameter
            }
            return $result
        }

        function Get-TestValidationSignature {
            param([System.Management.Automation.ParameterMetadata]$Parameter)

            $signatures = @()
            foreach ($attribute in $Parameter.Attributes) {
                if ($attribute -is [System.Management.Automation.ValidateSetAttribute]) {
                    $values = @($attribute.ValidValues | Sort-Object)
                    $signatures += 'ValidateSet:{0}' -f ($values -join ',')
                }
                elseif ($attribute -is [System.Management.Automation.ValidateRangeAttribute]) {
                    $signatures += 'ValidateRange:{0},{1}' -f $attribute.MinRange, $attribute.MaxRange
                }
                elseif ($attribute -is [System.Management.Automation.ValidatePatternAttribute]) {
                    $signatures += 'ValidatePattern:{0}' -f $attribute.RegexPattern
                }
            }
            return (@($signatures | Sort-Object) -join ';')
        }

        function Get-TestHelpDescription {
            param($ParameterHelp)

            $text = @($ParameterHelp.Description | ForEach-Object { $_.Text }) -join ' '
            return (($text -replace '\s+', ' ').Trim())
        }
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

    It 'exposes validated ATC recovery parameters on the installed command' {
        $parameters = (Get-Command lofiatc).Parameters

        $parameters.Keys | Should -Contain 'AutoRecover'
        $parameters.Keys | Should -Contain 'RetryCount'
        $parameters.Keys | Should -Contain 'RecoverAlternateChannel'

        $retryRange = @($parameters.RetryCount.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] })[0]
        $retryRange.MinRange | Should -Be 1
        $retryRange.MaxRange | Should -Be 10
    }

    Context 'CLI parameter parity' {
        It 'keeps shared names, types, aliases, defaults, and validation rules aligned' {
            $parseTokens = $null
            $parseErrors = $null
            $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptEntryPoint,
                [ref]$parseTokens,
                [ref]$parseErrors
            )
            $parseErrors | Should -BeNullOrEmpty

            $scriptCommand = Get-Command $scriptEntryPoint
            $wrapperCommand = Get-Command lofiatc
            $wrapperParseTokens = $null
            $wrapperParseErrors = $null
            $wrapperAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $wrapperCommand.Definition,
                [ref]$wrapperParseTokens,
                [ref]$wrapperParseErrors
            )
            $wrapperParseErrors | Should -BeNullOrEmpty
            $scriptAstParameters = Get-TestParameterAstMap -ParamBlock $scriptAst.ParamBlock
            $wrapperAstParameters = Get-TestParameterAstMap -ParamBlock $wrapperAst.ParamBlock
            $scriptNames = @($scriptAstParameters.Keys | Sort-Object)
            $forwardedWrapperNames = @(
                $wrapperAstParameters.Keys |
                    Where-Object { $_ -notin $installedOnlyParameters } |
                    Sort-Object
            )

            Compare-Object $scriptNames $forwardedWrapperNames | Should -BeNullOrEmpty

            foreach ($name in $scriptNames) {
                $scriptParameter = $scriptCommand.Parameters[$name]
                $wrapperParameter = $wrapperCommand.Parameters[$name]
                $scriptDefault = $scriptAstParameters[$name].DefaultValue
                $wrapperDefault = $wrapperAstParameters[$name].DefaultValue

                $wrapperParameter.ParameterType.FullName | Should -Be $scriptParameter.ParameterType.FullName
                (@($wrapperParameter.Aliases | Sort-Object) -join ',') |
                    Should -Be (@($scriptParameter.Aliases | Sort-Object) -join ',')
                (Get-TestValidationSignature -Parameter $wrapperParameter) |
                    Should -Be (Get-TestValidationSignature -Parameter $scriptParameter)

                if ($null -eq $scriptDefault) {
                    $wrapperDefault | Should -BeNullOrEmpty
                }
                else {
                    $wrapperDefault.Extent.Text | Should -Be $scriptDefault.Extent.Text
                }
            }
        }

        It 'limits intentional wrapper-only parameters to the documented updater controls' {
            $scriptParameters = (Get-Command $scriptEntryPoint).Parameters
            $wrapperParameters = (Get-Command lofiatc).Parameters

            foreach ($name in $installedOnlyParameters) {
                $wrapperParameters.Keys | Should -Contain $name
                $scriptParameters.Keys | Should -Not -Contain $name
            }
        }

        It 'documents every shared parameter consistently in both help surfaces' {
            $parseTokens = $null
            $parseErrors = $null
            $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
                $scriptEntryPoint,
                [ref]$parseTokens,
                [ref]$parseErrors
            )
            $scriptAstParameters = Get-TestParameterAstMap -ParamBlock $scriptAst.ParamBlock
            $scriptNames = @($scriptAstParameters.Keys)
            $scriptHelp = Get-Help $scriptEntryPoint -Full
            $wrapperHelp = Get-Help lofiatc -Full

            foreach ($name in $scriptNames) {
                $scriptParameterHelp = @($scriptHelp.Parameters.Parameter | Where-Object Name -eq $name)[0]
                $wrapperParameterHelp = @($wrapperHelp.Parameters.Parameter | Where-Object Name -eq $name)[0]
                $scriptDescription = Get-TestHelpDescription -ParameterHelp $scriptParameterHelp
                $wrapperDescription = Get-TestHelpDescription -ParameterHelp $wrapperParameterHelp

                $scriptDescription | Should -Not -BeNullOrEmpty
                $wrapperDescription | Should -Be $scriptDescription
            }
        }
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

    It 'aborts before downloading when the requested ref cannot be resolved' {
        $installRoot = Join-Path $TestDrive 'lofiatc-api-fallback'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $markerPath = Join-Path $installRoot 'active-marker.txt'
        'active' | Set-Content -Path $markerPath

        Mock Invoke-RestMethod -ModuleName LofiATC {
            throw 'Response status code does not indicate success: 504 (Gateway Time-out).'
        }

        Mock Invoke-WebRequest -ModuleName LofiATC {
            throw 'The updater must not download an unverified ref.'
        }

        {
            Update-LofiATC `
                -InstallRoot $installRoot `
                -Ref 'feature/install-module-command' `
                -Repository 'RoMinjun/lofiatc.ps1'
        } | Should -Throw '*504*'

        Get-Content -Path $markerPath | Should -Be 'active'
        Should -Invoke Invoke-WebRequest -ModuleName LofiATC -Times 0
    }

    It 'shows the checked-out commit after updating a Git installation' {
        $installRoot = Join-Path $TestDrive 'git-update'
        New-Item -ItemType Directory -Path (Join-Path $installRoot '.git') -Force | Out-Null
        $script:gitUpdatePulled = $false

        Mock git -ModuleName LofiATC {
            $global:LASTEXITCODE = 0
            if ($args -contains 'pull') {
                $script:gitUpdatePulled = $true
                return
            }
            if ($args -contains '--abbrev-ref') {
                return 'test'
            }
            if ($args -contains 'ls-remote') {
                return 'db17a101234567890db17a101234567890db17a1 refs/heads/test'
            }
            if ($args -contains 'rev-parse' -and $script:gitUpdatePulled) {
                return 'db17a101234567890db17a101234567890db17a1'
            }
            if ($args -contains 'rev-parse') {
                return 'afe8201234567890afe8201234567890afe82012'
            }
            if ($args -contains 'get-url') {
                return 'git@github.com:RoMinjun/lofiatc.ps1.git'
            }
        }

        $output = Update-LofiATC -InstallRoot $installRoot 6>&1

        $text = $output -join "`n"
        $text | Should -Match 'Updated commit:'
        $text | Should -Match 'db17a101234567890db17a101234567890db17a1'
        $text | Should -Match 'https://github\.com/RoMinjun/lofiatc\.ps1/commit/db17a101234567890db17a101234567890db17a1'
        Should -Invoke git -ModuleName LofiATC -ParameterFilter {
            $args -contains 'pull' -and $args -contains '--ff-only'
        }
        Should -Invoke git -ModuleName LofiATC -ParameterFilter {
            $args -contains 'rev-parse' -and $args -contains 'HEAD'
        }
    }

    It 'previews a Git update without pulling or changing the checkout' {
        $installRoot = Join-Path $TestDrive 'git-update-preview'
        New-Item -ItemType Directory -Path (Join-Path $installRoot '.git') -Force | Out-Null

        Mock git -ModuleName LofiATC {
            $global:LASTEXITCODE = 0
            if ($args -contains '--abbrev-ref') {
                return 'test'
            }
            if ($args -contains 'ls-remote') {
                return 'db17a101234567890db17a101234567890db17a1 refs/heads/test'
            }
            if ($args -contains 'rev-parse') {
                return 'afe8201234567890afe8201234567890afe82012'
            }
            if ($args -contains 'get-url') {
                return 'git@github.com:RoMinjun/lofiatc.ps1.git'
            }
            if ($args -contains 'pull') {
                throw 'Preview mode must not pull.'
            }
        }

        $output = Update-LofiATC -InstallRoot $installRoot -WhatIf 6>&1
        $text = $output -join "`n"

        $text | Should -Match 'Installed commit:'
        $text | Should -Match 'Available commit:'
        Should -Invoke git -ModuleName LofiATC -Times 0 -ParameterFilter {
            $args -contains 'pull'
        }
    }

    It 'previews an installer update without downloading or writing files' {
        $installRoot = Join-Path $TestDrive 'release-preview'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $markerPath = Join-Path $installRoot 'active-marker.txt'
        'active' | Set-Content -Path $markerPath
        [pscustomobject]@{
            Repository = 'RoMinjun/lofiatc.ps1'
            Ref        = 'v0.1.0'
            Release    = 'v0.1.0'
            Commit     = 'afe8201234567890afe8201234567890afe82012'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        Mock Get-LofiATCReleaseInfo -ModuleName LofiATC {
            return [pscustomobject]@{
                tag_name = 'v0.2.0'
                assets   = @()
            }
        }
        Mock Resolve-LofiATCCommit -ModuleName LofiATC {
            return 'db17a101234567890db17a101234567890db17a10'
        }
        Mock Invoke-WebRequest -ModuleName LofiATC {
            throw 'Preview mode must not download files.'
        }

        $output = Update-LofiATC -InstallRoot $installRoot -WhatIf 6>&1
        $text = $output -join "`n"

        $text | Should -Match 'Installed version: v0\.1\.0'
        $text | Should -Match 'Available version: v0\.2\.0'
        Get-Content -Path $markerPath | Should -Be 'active'
        Should -Invoke Invoke-WebRequest -ModuleName LofiATC -Times 0
    }

    It 'rejects a release installer checksum mismatch before execution' {
        $installRoot = Join-Path $TestDrive 'release-checksum-mismatch'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $markerPath = Join-Path $installRoot 'active-marker.txt'
        'active' | Set-Content -Path $markerPath
        [pscustomobject]@{
            Repository = 'RoMinjun/lofiatc.ps1'
            Ref        = 'v0.1.0'
            Release    = 'v0.1.0'
            Commit     = 'afe8201234567890afe8201234567890afe82012'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        Mock Get-LofiATCReleaseInfo -ModuleName LofiATC {
            return [pscustomobject]@{
                tag_name = 'v0.2.0'
                assets   = @(
                    [pscustomobject]@{ name = 'install.ps1'; browser_download_url = 'https://example.invalid/install.ps1' },
                    [pscustomobject]@{ name = 'install.ps1.sha256'; browser_download_url = 'https://example.invalid/install.ps1.sha256' }
                )
            }
        }
        Mock Resolve-LofiATCCommit -ModuleName LofiATC {
            return 'db17a101234567890db17a101234567890db17a10'
        }
        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            if ($Uri -like '*.sha256') {
                "$('0' * 64)  install.ps1" | Set-Content -Path $OutFile -Encoding ascii
            }
            else {
                "throw 'This unverified installer must not run.'" | Set-Content -Path $OutFile -Encoding UTF8
            }
        }

        {
            Update-LofiATC -InstallRoot $installRoot -Release latest
        } | Should -Throw '*SHA-256 checksum mismatch*'

        Get-Content -Path $markerPath | Should -Be 'active'
        Should -Invoke Invoke-WebRequest -ModuleName LofiATC -Times 2
    }

    It 'verifies and runs a release installer with the selected release tag' {
        $installRoot = Join-Path $TestDrive 'release-update-success'
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        $argsPath = Join-Path $TestDrive 'release-installer-args.json'
        $env:LOFIATC_TEST_INSTALLER_ARGS = $argsPath
        [pscustomobject]@{
            Repository = 'RoMinjun/lofiatc.ps1'
            Ref        = 'v0.1.0'
            Release    = 'v0.1.0'
            Commit     = 'afe8201234567890afe8201234567890afe82012'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        Mock Get-LofiATCReleaseInfo -ModuleName LofiATC {
            return [pscustomobject]@{
                tag_name = 'v0.2.0'
                assets   = @(
                    [pscustomobject]@{ name = 'install.ps1'; browser_download_url = 'https://example.invalid/install.ps1' },
                    [pscustomobject]@{ name = 'install.ps1.sha256'; browser_download_url = 'https://example.invalid/install.ps1.sha256' }
                )
            }
        }
        Mock Resolve-LofiATCCommit -ModuleName LofiATC {
            return 'db17a101234567890db17a101234567890db17a10'
        }
        Mock Invoke-WebRequest -ModuleName LofiATC {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing
            )

            if ($Uri -like '*.sha256') {
                "$script:releaseInstallerHash  install.ps1" | Set-Content -Path $OutFile -Encoding ascii
                return
            }

            @'
param(
    [string]$InstallRoot,
    [string]$Repository,
    [string]$Release,
    [switch]$SkipPowerShellProfile
)

[pscustomobject]@{
    InstallRoot = $InstallRoot
    Repository = $Repository
    Release = $Release
    SkipPowerShellProfile = $SkipPowerShellProfile.IsPresent
} | ConvertTo-Json | Set-Content -Path $env:LOFIATC_TEST_INSTALLER_ARGS -Encoding UTF8
'@ | Set-Content -Path $OutFile -Encoding UTF8
            $script:releaseInstallerHash = (Get-FileHash -Path $OutFile -Algorithm SHA256).Hash.ToLowerInvariant()
        }

        try {
            $output = Update-LofiATC -InstallRoot $installRoot -Release latest 6>&1
            $installerArgs = Get-Content -Path $argsPath -Raw | ConvertFrom-Json

            $installerArgs.InstallRoot | Should -Be $installRoot
            $installerArgs.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
            $installerArgs.Release | Should -Be 'v0.2.0'
            $installerArgs.SkipPowerShellProfile | Should -BeTrue
            ($output -join "`n") | Should -Match 'Updated commit:'
        }
        finally {
            Remove-Item Env:\LOFIATC_TEST_INSTALLER_ARGS -ErrorAction SilentlyContinue
            Remove-Variable -Name releaseInstallerHash -Scope Script -ErrorAction SilentlyContinue
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
            Release               = 'v0.1.0'
            Commit                = '1234567890abcdef1234567890abcdef12345678'
            ArtifactSha256        = 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd'
            InstalledAtUtc        = '2026-06-20T12:00:00.0000000Z'
            InstallRoot           = $installRoot
            ModuleRoot            = 'C:\Modules\LofiATC'
            ShellShimPath         = $null
            PowerShellProfilePath = 'C:\Profiles\Microsoft.PowerShell_profile.ps1'
        } | ConvertTo-Json | Set-Content -Path (Join-Path $installRoot '.lofiatc-install.json') -Encoding UTF8

        $version = Get-LofiATCVersion -InstallRoot $installRoot

        $version.Repository | Should -Be 'RoMinjun/lofiatc.ps1'
        $version.Ref | Should -Be 'main'
        $version.Release | Should -Be 'v0.1.0'
        $version.Commit | Should -Be '1234567890abcdef1234567890abcdef12345678'
        $version.ArtifactSha256 | Should -Be 'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd'
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
