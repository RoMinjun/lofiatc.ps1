BeforeAll {
    $setupScript = Join-Path $PSScriptRoot '../tools/Install-CIPester.ps1'
}

Describe 'CI Pester dependency setup' {
    BeforeEach {
        $script:setupCalls = 0
        Mock Install-Module {}
        Mock Import-Module { [pscustomobject]@{ Version = [version]'5.7.1' } }
        Mock Start-Sleep {}
    }

    It 'proceeds immediately after successful setup' {
        & $setupScript
        Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
            $MinimumVersion -eq '5.5.0' -and $MaximumVersion -eq '5.99.99' -and $ErrorAction -eq 'Stop'
        }
        Should -Invoke Import-Module -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'recovers from a transient <Stage> failure' -TestCases @(
        @{ Stage = 'Install-Module' }
        @{ Stage = 'Import-Module' }
    ) {
        param($Stage)
        Mock $Stage {
            $script:setupCalls++
            if ($script:setupCalls -eq 1) { throw 'Temporary module lookup failure' }
            [pscustomobject]@{ Version = [version]'5.7.1' }
        }
        & $setupScript
        $script:setupCalls | Should -Be 2
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 10 }
    }

    It 'fails after the retry budget is exhausted' {
        Mock Install-Module { throw 'Temporary module lookup failure' }
        { & $setupScript } | Should -Throw '*failed after 3 attempts*Temporary module lookup failure*'
        Should -Invoke Install-Module -Times 3 -Exactly
        Should -Invoke Import-Module -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'rejects an unsupported imported version' {
        Mock Import-Module { [pscustomobject]@{ Version = [version]'3.4.0' } }
        { & $setupScript -MaxAttempts 2 -DelaySeconds 0 } | Should -Throw '*failed after 2 attempts*supported version*'
        Should -Invoke Import-Module -Times 2 -Exactly
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }
}
