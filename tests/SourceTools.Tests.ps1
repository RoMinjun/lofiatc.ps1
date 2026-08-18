BeforeAll {
  $toolsPath = Join-Path (Join-Path $PSScriptRoot '..') 'tools'
  $sortScript = Join-Path $toolsPath 'Sort-ATCSources.ps1'
  $powerShellExecutable = (Get-Process -Id $PID).Path

  function Invoke-SourceSortCheck {
    param([Parameter(Mandatory)][string]$CsvPath)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powerShellExecutable
    $startInfo.Arguments = '-NoLogo -NoProfile -File "{0}" -InputCsvPath "{1}" -Check' -f `
      $sortScript, $CsvPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
      [void]$process.Start()
      $standardOutput = $process.StandardOutput.ReadToEnd()
      $standardError = $process.StandardError.ReadToEnd()
      $process.WaitForExit()

      $exitCode = $process.ExitCode
      $output = $standardOutput + $standardError
    }
    finally {
      $process.Dispose()
    }

    [pscustomobject]@{
      ExitCode = $exitCode
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
