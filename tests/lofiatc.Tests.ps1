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
        BeforeEach {
            $script:OnWindows = $false
        }

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

        It 'uses the detected Windows default app when it exists in PATH' {
            $script:OnWindows = $true

            Mock Get-DefaultAppForMP4 { 'vlc' }
            Mock Get-Command {
                [pscustomobject]@{ Path = 'C:\Program Files\VideoLAN\VLC\vlc.exe' }
            } -ParameterFilter { $Name -eq 'vlc.exe' }

            Resolve-Player -explicitPlayer '' | Should -Be 'VLC'
        }

        It 'falls back to MPV first on Windows when the default app is unavailable' {
            $script:OnWindows = $true

            Mock Get-DefaultAppForMP4 { 'some-other-app' }

            Mock Get-Command {
                [pscustomobject]@{ Path = 'C:\mpv\mpv.com' }
            } -ParameterFilter { $Name -eq 'mpv.com' }

            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'vlc.exe' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'PotPlayerMini64.exe' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mpc-hc64.exe' }

            Resolve-Player -explicitPlayer '' | Should -Be 'MPV'
        }

        It 'falls back through VLC, Potplayer, then MPC-HC on Windows' {
            $script:OnWindows = $true

            Mock Get-DefaultAppForMP4 { $null }

            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mpv.com' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'vlc.exe' }
            Mock Get-Command {
                [pscustomobject]@{ Path = 'C:\PotPlayer\PotPlayerMini64.exe' }
            } -ParameterFilter { $Name -eq 'PotPlayerMini64.exe' }
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mpc-hc64.exe' }

            Resolve-Player -explicitPlayer '' | Should -Be 'Potplayer'
        }
    }

    Context 'Distance and unit conversion' {
        It 'returns zero distance for identical coordinates' {
            Get-DistanceKm -Lat1 51.47 -Lon1 -0.4543 -Lat2 51.47 -Lon2 -0.4543 | Should -Be 0
        }

        It 'converts kilometers to nautical miles' {
            ConvertTo-NauticalMiles -Kilometers 18.52 -Decimals 1 | Should -Be 10
        }

        It 'coerces null input to zero because the parameter is typed as double' {
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

    Context 'LoadConfig precedence' {
        BeforeEach {
            $script:configPath = Join-Path $TestDrive 'config.json'
            @'
{
  "Player": "VLC",
  "OpenRadar": true,
  "ATCVolume": 70,
  "LofiVolume": 45,
  "ICAO": "klax"
}
'@ | Set-Content -Path $script:configPath -Encoding UTF8
        }

        It 'loads values from config when not explicitly provided' {
            $config = Get-Content -Path $script:configPath -Raw | ConvertFrom-Json
            $dummyBoundParameters = @{}

            $Player = $null
            $OpenRadar = $false
            $ATCVolume = 65
            $LofiVolume = 50
            $ICAO = $null

            foreach ($prop in $config.PSObject.Properties) {
                $name = $prop.Name
                if (-not $dummyBoundParameters.ContainsKey($name) -and $null -ne $prop.Value -and $prop.Value -ne '') {
                    Set-Variable -Name $name -Value $prop.Value -Scope Local
                }
            }

            $Player | Should -Be 'VLC'
            $OpenRadar | Should -BeTrue
            $ATCVolume | Should -Be 70
            $LofiVolume | Should -Be 45
            $ICAO | Should -Be 'klax'
        }

        It 'keeps CLI values when both config and explicit values exist' {
            $config = Get-Content -Path $script:configPath -Raw | ConvertFrom-Json

            $Player = 'MPV'
            $OpenRadar = $false
            $ATCVolume = 20
            $LofiVolume = 10
            $ICAO = 'RJTT'
            $dummyBoundParameters = @{
                Player     = $true
                OpenRadar  = $true
                ATCVolume  = $true
                LofiVolume = $true
                ICAO       = $true
            }

            foreach ($prop in $config.PSObject.Properties) {
                $name = $prop.Name
                if (-not $dummyBoundParameters.ContainsKey($name) -and $null -ne $prop.Value -and $prop.Value -ne '') {
                    Set-Variable -Name $name -Value $prop.Value -Scope Local
                }
            }

            $Player | Should -Be 'MPV'
            $OpenRadar | Should -BeFalse
            $ATCVolume | Should -Be 20
            $LofiVolume | Should -Be 10
            $ICAO | Should -Be 'RJTT'
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

        It 'returns an empty array for malformed JSON' {
            '{not-valid-json' | Set-Content -Path $script:testDrivePath -Encoding UTF8

            @(Get-Favorite -path $script:testDrivePath).Count | Should -Be 0
        }

        It 'returns an empty array when JSON is valid but not a favorites array' {
            '"hello"' | Set-Content -Path $script:testDrivePath -Encoding UTF8

            @(Get-Favorite -path $script:testDrivePath).Count | Should -Be 0
        }
    }

    Context 'Import-ATCSource validation' {
        BeforeEach {
            $script:csvPath = Join-Path $TestDrive 'atc_sources.csv'
        }

        It 'loads a CSV when required columns exist' {
            @'
ICAO,Channel Description,Stream URL,Webcam URL,NearbyICAOs
KLAX,Tower,http://example.com/stream,,KSNA;KBUR
'@ | Set-Content -Path $script:csvPath -Encoding UTF8

            $result = Import-ATCSource -csvPath $script:csvPath
            $result.Count | Should -Be 1
            $result[0].ICAO | Should -Be 'KLAX'
        }

        It 'throws when required columns are missing' {
            @'
ICAO,Stream URL
KLAX,http://example.com/stream
'@ | Set-Content -Path $script:csvPath -Encoding UTF8

            { Import-ATCSource -csvPath $script:csvPath } | Should -Throw '*missing required column*'
        }
    }

    Context 'Import-ATCSource recommended columns' {
        BeforeEach {
            $script:csvPath = Join-Path $TestDrive 'atc_sources_recommended.csv'
        }

        It 'does not throw when only recommended columns are missing' {
            @'
ICAO,Channel Description,Stream URL
KLAX,Tower,http://example.com/stream
'@ | Set-Content -Path $script:csvPath -Encoding UTF8

            { Import-ATCSource -csvPath $script:csvPath } | Should -Not -Throw
        }

        It 'throws when the CSV is empty' {
            '' | Set-Content -Path $script:csvPath -Encoding UTF8

            { Import-ATCSource -csvPath $script:csvPath } | Should -Throw '*empty*'
        }
    }

    Context 'Test-JsonFileReadable' {
        BeforeEach {
            $script:jsonPath = Join-Path $TestDrive 'sample.json'
        }

        It 'returns OK for an optional missing file' {
            $result = Test-JsonFileReadable -Path $script:jsonPath -Optional

            $result.Ok | Should -BeTrue
            $result.Status | Should -Be 'OK'
        }

        It 'returns Missing for invalid JSON' {
            '{bad-json' | Set-Content -Path $script:jsonPath -Encoding UTF8

            $result = Test-JsonFileReadable -Path $script:jsonPath

            $result.Ok | Should -BeFalse
            $result.Status | Should -Be 'Missing'
        }

        It 'returns OK for valid JSON' {
            '{"hello":"world"}' | Set-Content -Path $script:jsonPath -Encoding UTF8

            $result = Test-JsonFileReadable -Path $script:jsonPath

            $result.Ok | Should -BeTrue
            $result.Status | Should -Be 'OK'
        }
    }

    Context 'Test-LofiATCDependencies' {
        BeforeEach {
            $script:scriptDir = Join-Path $TestDrive 'repo'
            New-Item -ItemType Directory -Path $script:scriptDir -Force | Out-Null

            'ICAO,Channel Description,Stream URL' | Set-Content -Path (Join-Path $script:scriptDir 'atc_sources.csv') -Encoding UTF8

            Mock Test-UrlReachable { $true }
        }

        It 'treats fzf as required only when UseFZF is set' {
            Mock Test-CommandAvailable {
                switch ($CommandName) {
                    'mpv' { '/usr/bin/mpv' }
                    'fzf' { $null }
                    default { $null }
                }
            }

            $withoutFzf = Test-LofiATCDependencies -ScriptDir $script:scriptDir -UseFZF:$false -ShowMap:$false
            $withFzf = Test-LofiATCDependencies -ScriptDir $script:scriptDir -UseFZF:$true -ShowMap:$false

            ($withoutFzf | Where-Object Name -eq 'fzf').Required | Should -BeFalse
            ($withoutFzf | Where-Object Name -eq 'fzf').Status | Should -Be 'Warning'

            ($withFzf | Where-Object Name -eq 'fzf').Required | Should -BeTrue
            ($withFzf | Where-Object Name -eq 'fzf').Status | Should -Be 'Missing'
        }
    }

    Context 'Get-VLCVolumeArg' {
        BeforeEach {
            $script:OnWindows = $false
        }

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

    Context 'Get-IPLocation' {
        It 'returns a normalized object from the HTTPS provider payload' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    latitude     = 33.9416
                    longitude    = -118.4085
                    city         = 'Los Angeles'
                    country_name = 'United States'
                }
            }
            Mock Write-Host {}

            $result = Get-IPLocation

            $result | Should -Not -BeNullOrEmpty
            $result.Latitude | Should -Be 33.9416
            $result.Longitude | Should -Be -118.4085
            $result.City | Should -Be 'Los Angeles'
            $result.Country | Should -Be 'United States'
            $result.Source | Should -Be 'IP'
        }

        It 'returns null when the provider call fails' {
            Mock Invoke-RestMethod { throw 'timeout' }
            Mock Write-Error {}

            $result = Get-IPLocation

            $result | Should -Be $null
        }

        It 'returns null when the payload has no coordinates' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    city         = 'Los Angeles'
                    country_name = 'United States'
                }
            }

            $result = Get-IPLocation

            $result | Should -Be $null
        }
    }

    Context 'Get-MapWeatherData' {
        It 'returns empty weather structures and skips web requests when NoWeather is set' {
            $sources = @(
                [pscustomobject]@{ ICAO = 'KLAX'; NearbyICAOs = 'KSNA;KBUR' },
                [pscustomobject]@{ ICAO = 'RJTT'; NearbyICAOs = '' }
            )

            Mock Invoke-RestMethod { throw 'Should not be called' }
            Mock Invoke-WebRequest { throw 'Should not be called' }

            $result = Get-MapWeatherData -AtcSources $sources -NoWeather

            $result | Should -Not -BeNullOrEmpty
            $result.WeatherMap.Count | Should -Be 0
            $result.IcaoToFallbacks.Count | Should -Be 0

            Should -Not -Invoke Invoke-RestMethod
            Should -Not -Invoke Invoke-WebRequest
        }
    }

    Context 'Get-AirportInfo remote failure behavior' {
        BeforeEach {
            $script:AirportData = $null
        }

        It 'returns null when remote airport database fetch fails' {
            Mock Invoke-RestMethod { throw 'network failure' }
            Mock Write-Error {}

            $result = Get-AirportInfo -ICAO 'KLAX'

            $result | Should -Be $null
        }

        It 'returns airport info from cached data without remote fetch' {
            $script:AirportData = [pscustomobject]@{
                KLAX = [pscustomobject]@{
                    icao = 'KLAX'
                    name = 'Los Angeles International'
                    tz   = 'America/Los_Angeles'
                    lat  = 33.9416
                    lon  = -118.4085
                }
            }

            Mock Invoke-RestMethod { throw 'Should not be called' }

            $result = Get-AirportInfo -ICAO 'KLAX'

            $result | Should -Not -BeNullOrEmpty
            $result.icao | Should -Be 'KLAX'
            Should -Not -Invoke Invoke-RestMethod
        }
    }

    Context 'Select-ATCFromMap cancellation path' {
        It 'throws OperationCanceledException when Q is pressed' {
            $server = Start-ATCMapServer -StartPort 59999 -MaxRetries 20
            $listener = $server.Listener

            Mock Start-Sleep {}
            Mock Write-Host {}
            Mock Test-InteractiveConsoleAvailable { $true }
            Mock Test-ConsoleKeyAvailable { $true }
            Mock Read-ConsoleKey {
                [pscustomobject]@{ Key = 'Q' }
            }

            try {
                $thrown = $null

                try {
                    Select-ATCFromMap -Listener $listener -TimeoutSeconds 5
                }
                catch {
                    $thrown = $_.Exception
                }

                $thrown | Should -Not -BeNullOrEmpty

                $allTypes = @(
                    $thrown.GetType().FullName
                    if ($thrown.InnerException) { $thrown.InnerException.GetType().FullName }
                )

                $allTypes | Should -Contain 'System.OperationCanceledException'
            }
            finally {
                try { $listener.Stop() } catch {}
                try { $listener.Close() } catch {}
            }
        }
    }

    Context 'Select-ATCFromMap non-interactive host path' {
        It 'times out cleanly when console cancellation is unavailable' {
            $server = Start-ATCMapServer -StartPort 59998 -MaxRetries 20
            $listener = $server.Listener

            Mock Write-Host {}
            Mock Test-InteractiveConsoleAvailable { $false }
            Mock Start-Sleep {}

            try {
                { Select-ATCFromMap -Listener $listener -TimeoutSeconds 0 } | Should -Throw '*Timed out waiting for a map selection*'
            }
            finally {
                try { $listener.Stop() } catch {}
                try { $listener.Close() } catch {}
            }
        }
    }

    Context 'Remove-StaleATCMapFiles' {
        It 'removes only old LofiATC temp map files' {
            $oldFile = Join-Path $TestDrive 'lofiatc_map_old.html'
            $newFile = Join-Path $TestDrive 'lofiatc_map_new.html'
            $otherFile = Join-Path $TestDrive 'something_else.html'

            'old' | Set-Content -Path $oldFile -Encoding UTF8
            'new' | Set-Content -Path $newFile -Encoding UTF8
            'other' | Set-Content -Path $otherFile -Encoding UTF8

            (Get-Item $oldFile).LastWriteTime = (Get-Date).AddHours(-30)
            (Get-Item $newFile).LastWriteTime = (Get-Date).AddHours(-1)

            Mock Get-ChildItem {
                @(
                    Get-Item $oldFile
                    Get-Item $newFile
                )
            }

            Remove-StaleATCMapFiles -MaxAgeHours 24

            Test-Path $oldFile | Should -BeFalse
            Test-Path $newFile | Should -BeTrue
            Test-Path $otherFile | Should -BeTrue
        }
    }

    Context 'Get-METAR-TAF fallback ICAO' {
        BeforeEach {
            $script:AirportData = [pscustomobject]@{
                KLAX = [pscustomobject]@{
                    icao = 'KLAX'
                    lat  = 33.9416
                    lon  = -118.4085
                }
                KSNA = [pscustomobject]@{
                    icao = 'KSNA'
                    lat  = 33.6757
                    lon  = -117.8678
                }
            }
        }

        It 'uses a fallback ICAO when the primary source is unavailable' {
            Mock Invoke-WebRequest {
                param($Uri)

                if ($Uri -like '*ids=KLAX*') {
                    [pscustomobject]@{ Content = 'no metar here' }
                }
                elseif ($Uri -like '*id=KLAX*') {
                    throw 'primary failed'
                }
                elseif ($Uri -like '*ids=KSNA*') {
                    [pscustomobject]@{ Content = 'KSNA 121650Z 18012KT 9999 FEW020 18/12 Q1013' }
                }
                else {
                    throw "Unexpected URI: $Uri"
                }
            }

            $result = Get-METAR-TAF -ICAO 'KLAX' -FallbackICAOs @('KSNA')

            $result.ICAO | Should -Be 'KSNA'
            $result.Report | Should -Match '^KSNA '
            $result.DistanceKm | Should -BeGreaterThan 0
            $result.DistanceNm | Should -BeGreaterThan 0
        }

        It 'returns the unavailable object when all sources fail' {
            Mock Invoke-WebRequest { throw 'network failed' }
            Mock Write-Error {}

            $result = Get-METAR-TAF -ICAO 'KLAX' -FallbackICAOs @('KSNA')

            $result.ICAO | Should -Be 'KLAX'
            $result.Report | Should -Be 'METAR/TAF data unavailable.'
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