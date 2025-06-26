# Import functions from the script without running the bottom execution block
$scriptPath = Join-Path $PSScriptRoot '..' 'lofiatc.ps1'
$scriptContent = Get-Content $scriptPath -Raw
$funcContent = $scriptContent -split '# Determine the player to use',2
Invoke-Expression $funcContent[0]

Describe 'Get-METAR-TAF and ConvertFrom-METAR' {
    $sampleHtml = '<html><head><meta name="description" content="KJFK 121651Z 18015G25KT 10SM BKN015 OVC030 22/18 A2992. Additional text"></head></html>'
    Mock Invoke-WebRequest { [pscustomobject]@{ Content = $sampleHtml } }
    $metar = Get-METAR-TAF -ICAO 'KJFK'
    It 'returns raw METAR' { $metar | Should -Be 'KJFK 121651Z 18015G25KT 10SM BKN015 OVC030 22/18 A2992' }
    $decoded = ConvertFrom-METAR -metar $metar
    It 'decodes wind' { $decoded.Wind | Should -Be '180\u00B0 at 15 knots, gusting to 25 knots' }
    It 'decodes visibility' { $decoded.Visibility | Should -Be '16.093 km' }
    It 'decodes ceiling' { $decoded.Ceiling | Should -Be 'Broken at 1500 ft' }
    It 'decodes temperature' { $decoded.Temperature | Should -Be '22\u00B0C' }
    It 'decodes dewpoint' { $decoded.DewPoint | Should -Be '18\u00B0C' }
    It 'decodes pressure' { $decoded.Pressure | Should -Be '1013.2 hPa' }
}

Describe 'Selection functions' {
    Context 'Select-Item' {
        Mock Read-Host { '2' }
        It 'returns the chosen item' {
            Select-Item -prompt 'Choose' -items @('A','B','C') | Should -Be 'B'
        }
    }

    Context 'Select-ATCStream' {
        $atcSources = @(
            [pscustomobject]@{ Continent='North America'; Country='USA'; City='New York'; 'Airport Name'='JFK'; ICAO='KJFK'; IATA='JFK'; 'Channel Description'='Tower'; 'Stream URL'='towerUrl'; 'Webcam URL'='' },
            [pscustomobject]@{ Continent='North America'; Country='USA'; City='New York'; 'Airport Name'='JFK'; ICAO='KJFK'; IATA='JFK'; 'Channel Description'='Ground'; 'Stream URL'='groundUrl'; 'Webcam URL'='http://cam' }
        )
        Mock Select-Item {
            param($prompt,$items)
            if ($prompt -like 'Select an airport*') { return $items[0] }
            else { return $items[1] }
        }
        $result = Select-ATCStream -atcSources $atcSources -continent 'North America' -country 'USA'
        It 'returns correct stream URL' { $result.StreamUrl | Should -Be 'groundUrl' }
        It 'returns correct webcam URL' { $result.WebcamUrl | Should -Be 'http://cam' }
    }
}
