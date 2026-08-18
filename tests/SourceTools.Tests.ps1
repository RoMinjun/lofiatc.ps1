BeforeAll {
  $toolsPath = Join-Path (Join-Path $PSScriptRoot '..') 'tools'
  $sortScript = Join-Path $toolsPath 'Sort-ATCSources.ps1'
  $powerShellExecutable = (Get-Process -Id $PID).Path

  function Invoke-SourceSortCheck {
    param([Parameter(Mandatory)][string]$CsvPath)

    $output = & $powerShellExecutable -NoLogo -NoProfile -File $sortScript `
      -InputCsvPath $CsvPath -Check 2>&1 | Out-String
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Output = $output
    }
  }
}

Describe 'ATC source validation' {
  It 'accepts a sorted source with the expected schema and unique rows' {
    $path = Join-Path $TestDrive 'valid.csv'
    @'
"Continent","Country","City","State/Province","Airport Name","ICAO","IATA","Channel Description","Stream URL","Webcam URL","NearbyICAOs"
"Europe","Netherlands","Amsterdam","","Amsterdam Airport Schiphol","EHAM","AMS","EHAM Tower","https://example.test/eham","",""
"North America","United States","Seattle","Washington","Seattle-Tacoma International Airport","KSEA","SEA","KSEA Tower","https://example.test/ksea","",""
'@ | Set-Content -Path $path -Encoding UTF8

    $result = Invoke-SourceSortCheck -CsvPath $path

    $result.ExitCode | Should -Be 0
    $result.Output | Should -Match 'already sorted'
  }

  It 'rejects a source with an unexpected schema' {
    $path = Join-Path $TestDrive 'invalid-schema.csv'
    @'
"ICAO","Stream URL"
"EHAM","https://example.test/eham"
'@ | Set-Content -Path $path -Encoding UTF8

    $result = Invoke-SourceSortCheck -CsvPath $path

    $result.ExitCode | Should -Be 2
    $result.Output | Should -Match 'Unexpected CSV schema'
  }

  It 'rejects exact duplicate rows' {
    $path = Join-Path $TestDrive 'duplicates.csv'
    @'
"Continent","Country","City","State/Province","Airport Name","ICAO","IATA","Channel Description","Stream URL","Webcam URL","NearbyICAOs"
"Europe","Netherlands","Amsterdam","","Amsterdam Airport Schiphol","EHAM","AMS","EHAM Tower","https://example.test/eham","",""
"Europe","Netherlands","Amsterdam","","Amsterdam Airport Schiphol","EHAM","AMS","EHAM Tower","https://example.test/eham","",""
'@ | Set-Content -Path $path -Encoding UTF8

    $result = Invoke-SourceSortCheck -CsvPath $path

    $result.ExitCode | Should -Be 2
    $result.Output | Should -Match 'duplicate row group'
  }
}
