param(
    [string]$JsonOutputPath
)

Set-StrictMode -Version Latest

Describe 'lofiatc.ps1 helper functions' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $scriptPath = Join-Path $repoRoot 'lofiatc.ps1'

        $env:LOFIATC_TEST_MODE = '1'
        . $scriptPath

        $script:OnWindows = $false
        $script:AirportData = $null
        $script:IanaToWindowsMap = @{
            'Etc/UTC'          = 'UTC'
            'Europe/London'    = 'GMT Standard Time'
            'America/New_York' = 'Eastern Standard Time'
            'Asia/Tokyo'       = 'Tokyo Standard Time'
        }
    }

    Context 'sanity' {
        It 'loads functions from lofiatc.ps1' {
            Get-Command Resolve-StreamUrl -CommandType Function | Should -Not -Be $null
            Get-Command Resolve-Player -CommandType Function | Should -Not -Be $null
            Get-Command Get-DistanceKm -CommandType Function | Should -Not -Be $null
        }
    }

    Context 'Resolve-StreamUrl' {
        It 'converts LiveATC .pls links to d.liveatc.net URLs' {
            Resolve-StreamUrl 'https://www.liveatc.net/play/klax_twr.pls' | Should -Be 'http://d.liveatc.net/klax_twr'
        }

        It 'returns non-special URLs unchanged' {
            $url = 'https://example.com/audio.mp3'
            Resolve-StreamUrl $url | Should -Be $url
        }
    }

    Context 'Resolve-Player' {
        It 'returns the explicitly requested player' {
            Resolve-Player -explicitPlayer 'MPV' | Should -Be 'MPV'
        }

        It 'prefers mpv on non-Windows when available' {
            Mock Get-Command {
                [pscustomobject]@{ Path = '/usr/bin/mpv' }
            } -ParameterFilter { $Name -eq 'mpv' }

            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'vlc' }

            Resolve-Player -explicitPlayer '' | Should -Be 'MPV'
        }

        It 'falls back to VLC on non-Windows when mpv is unavailable and vlc exists' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mpv' }
            Mock Get-Command {
                [pscustomobject]@{ Path = '/usr/bin/vlc' }
            } -ParameterFilter { $Name -eq 'vlc' }

            Resolve-Player -explicitPlayer '' | Should -Be 'VLC'
        }
    }

    Context 'Distance and unit conversion' {
        It 'returns zero distance for identical coordinates' {
            Get-DistanceKm -Lat1 51.47 -Lon1 -0.4543 -Lat2 51.47 -Lon2 -0.4543 | Should -Be 0
        }

        It 'converts kilometers to nautical miles' {
            ConvertTo-NauticalMiles -Kilometers 18.52 -Decimals 1 | Should -Be 10
        }

        It 'treats null input as zero because the parameter is typed as double' {
            ConvertTo-NauticalMiles -Kilometers $null | Should -Be 0
        }
    }

    Context 'ConvertFrom-METAR' {
        It 'decodes common METAR fields' {
            $decoded = ConvertFrom-METAR 'EGLL 121650Z 18012G20KT 9999 BKN020 18/12 Q1013'

            $decoded.Wind | Should -Match '180.*12 knots'
            $decoded.Visibility | Should -Be '10+ km (Unlimited)'
            $decoded.Ceiling | Should -Be 'Broken at 2000 ft'
            $decoded.Temperature | Should -Be '18°C'
            $decoded.DewPoint | Should -Be '12°C'
            $decoded.Pressure | Should -Be '1013 hPa'
        }

        It 'marks unavailable fields when the METAR does not contain them' {
            $decoded = ConvertFrom-METAR 'INVALID METAR'

            $decoded.Visibility | Should -Be 'Unavailable'
            $decoded.Ceiling | Should -Be 'Unavailable'
            $decoded.Temperature | Should -Be 'Unavailable'
            $decoded.DewPoint | Should -Be 'Unavailable'
            $decoded.Pressure | Should -Be 'Unavailable'
        }
    }

    Context 'ConvertTo-TimeZoneInfo' {
        It 'resolves a valid timezone id' {
            $tz = ConvertTo-TimeZoneInfo -IanaId 'Europe/London'
            $tz | Should -Not -Be $null
        }
    }

    Context 'Favorites persistence' {
        BeforeEach {
            $script:testDrivePath = Join-Path $TestDrive 'favorites.json'
            if (Test-Path $script:testDrivePath) {
                Remove-Item $script:testDrivePath -Force
            }
        }

        It 'returns an empty array when favorites file does not exist' {
            @(Get-Favorite -path $script:testDrivePath).Count | Should -Be 0
        }

        It 'adds a new favorite entry' {
            Add-Favorite -path $script:testDrivePath -ICAO 'KLAX' -Channel 'Tower' -maxEntries 10

            $favorites = @(Get-Favorite -path $script:testDrivePath)
            $favorites.Count | Should -Be 1
            $favorites[0].ICAO | Should -Be 'KLAX'
            $favorites[0].Channel | Should -Be 'Tower'
            $favorites[0].Count | Should -Be 1
        }

        It 'increments count when the same favorite is added again' {
            Add-Favorite -path $script:testDrivePath -ICAO 'KLAX' -Channel 'Tower' -maxEntries 10
            Add-Favorite -path $script:testDrivePath -ICAO 'KLAX' -Channel 'Tower' -maxEntries 10

            $favorites = @(Get-Favorite -path $script:testDrivePath)
            $favorites.Count | Should -Be 1
            $favorites[0].Count | Should -Be 2
        }

        It 'keeps only the requested maximum number of favorites' {
            1..5 | ForEach-Object {
                Add-Favorite -path $script:testDrivePath -ICAO ('KX{0:D2}' -f $_) -Channel 'Tower' -maxEntries 3
            }

            @(Get-Favorite -path $script:testDrivePath).Count | Should -Be 3
        }
    }

    Context 'Get-VLCVolumeArg' {
        It 'returns rc/stdin settings on non-Windows platforms' {
            $result = Get-VLCVolumeArg -volume 50

            $result.Mode | Should -Be 'RCStdin'
            $result.Value | Should -Be 128
            $result.Prepend | Should -Match 'extraintf rc'
        }

        It 'forces zero volume when NoAudio is set' {
            $result = Get-VLCVolumeArg -volume 90 -NoAudio
            $result.Value | Should -Be 0
        }
    }

    Context 'Get-NearbyAirports' {
        BeforeEach {
            $script:AirportData = [pscustomobject]@{
                KLAX = [pscustomobject]@{
                    icao    = 'KLAX'
                    name    = 'Los Angeles International'
                    city    = 'Los Angeles'
                    country = 'United States'
                    lat     = 33.9416
                    lon     = -118.4085
                }
                KSFO = [pscustomobject]@{
                    icao    = 'KSFO'
                    name    = 'San Francisco International'
                    city    = 'San Francisco'
                    country = 'United States'
                    lat     = 37.6213
                    lon     = -122.3790
                }
                RJTT = [pscustomobject]@{
                    icao    = 'RJTT'
                    name    = 'Tokyo Haneda'
                    city    = 'Tokyo'
                    country = 'Japan'
                    lat     = 35.5494
                    lon     = 139.7798
                }
            }

            $script:atcSources = @(
                [pscustomobject]@{ ICAO = 'KLAX' },
                [pscustomobject]@{ ICAO = 'KSFO' },
                [pscustomobject]@{ ICAO = 'RJTT' }
            )

            $script:userLocation = [pscustomobject]@{
                Latitude  = 34.0
                Longitude = -118.4
            }
        }

        It 'returns nearby airports inside the requested radius sorted by distance' {
            $results = Get-NearbyAirports -UserLocation $script:userLocation -AtcSources $script:atcSources -Radius 600

            $results.Count | Should -Be 2
            $results[0].ICAO | Should -Be 'KLAX'
            $results[1].ICAO | Should -Be 'KSFO'
        }
    }

    Context 'Get-METAR-LastUpdatedTime' {
        It 'reports elapsed time from the METAR timestamp' {
            Mock Get-METAR-TAF {
                [pscustomobject]@{
                    Report = 'KLAX 121650Z 18012KT 9999 FEW020 18/12 Q1013'
                }
            }

            $result = Get-METAR-LastUpdatedTime -ICAO 'KLAX'
            $result | Should -Match 'minutes|hours'
        }
    }
}

if ($JsonOutputPath -and -not $env:LOFIATC_PESTER_SELFHOST) {
    try {
        $env:LOFIATC_PESTER_SELFHOST = '1'
        $env:LOFIATC_TEST_MODE = '1'

        $config = New-PesterConfiguration
        $config.Run.Path = $PSCommandPath
        $config.Run.PassThru = $true
        $config.Output.Verbosity = if ($env:CI) { 'Detailed' } else { 'Diagnostic' }

        $captured = & { Invoke-Pester -Configuration $config } *>&1

        $result = $captured | Where-Object {
            $_ -and
            $_.PSObject -and
            ($_.PSObject.Properties.Name -contains 'PassedCount') -and
            ($_.PSObject.Properties.Name -contains 'FailedCount')
        } | Select-Object -Last 1

        if (-not $result) {
            throw 'Could not extract the Pester result object.'
        }

        $consoleText = ($captured | ForEach-Object {
            if ($_ -is [string]) {
                $_
            }
            elseif ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.ToString()
            }
            else {
                ($_ | Out-String).TrimEnd()
            }
        }) -join [Environment]::NewLine

        [pscustomobject]@{
            Summary = [pscustomobject]@{
                PassedCount  = $result.PassedCount
                FailedCount  = $result.FailedCount
                SkippedCount = $result.SkippedCount
                Duration     = $result.Duration
                Result       = $result.Result
                Verbosity    = $config.Output.Verbosity
            }
            ConsoleOutput = $consoleText
            Failed = @($result.Failed | ForEach-Object {
                [pscustomobject]@{
                    Name       = $_.ExpandedName
                    Path       = $_.Path
                    Result     = $_.Result
                    Duration   = $_.Duration
                    Error      = if ($_.ErrorRecord) { $_.ErrorRecord.ToString() } else { $null }
                    StackTrace = if ($_.ErrorRecord -and $_.ErrorRecord.ScriptStackTrace) { $_.ErrorRecord.ScriptStackTrace } else { $null }
                }
            })
            Passed = @($result.Passed | ForEach-Object {
                [pscustomobject]@{
                    Name     = $_.ExpandedName
                    Path     = $_.Path
                    Result   = $_.Result
                    Duration = $_.Duration
                }
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $JsonOutputPath -Encoding UTF8

        if ($result.FailedCount -gt 0) {
            exit 1
        }
    }
    finally {
        Remove-Item Env:LOFIATC_PESTER_SELFHOST -ErrorAction SilentlyContinue
    }
}
