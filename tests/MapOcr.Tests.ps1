BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $env:LOFIATC_TEST_MODE = '1'
    . (Join-Path $repoRoot 'lofiatc.ps1')
}

Describe 'Nonblocking map track detection' {
    BeforeEach {
        $script:gate = [System.Threading.ManualResetEvent]::new($false)
        $script:started = [System.Threading.ManualResetEvent]::new($false)
        $script:cleaned = [System.Threading.ManualResetEvent]::new($false)
        $script:testWorker = New-LofiTrackWorker -Source 'test-source'
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testGate', $script:gate)
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testStarted', $script:started)
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testCleaned', $script:cleaned)
        $null = $script:testWorker.Pipeline.AddScript({
            function global:Get-LofiTrackOcr {
                param($Source)
                $null = $testStarted.Set()
                try {
                    while (-not $testGate.WaitOne(0)) { Start-Sleep -Milliseconds 20 }
                    return @{ ok = $true; available = $true; track = 'artist - title'; message = $Source }
                }
                finally { $null = $testCleaned.Set() }
            }
        }).Invoke()
        $script:testWorker.Pipeline.Commands.Clear()
        Mock New-LofiTrackWorker { $script:testWorker }
    }

    AfterEach {
        $null = $script:gate.Set()
        Stop-LofiTrackWorker
        $script:gate.Dispose()
        $script:started.Dispose()
        $script:cleaned.Dispose()
    }

    It 'returns immediately while detection runs and reuses the worker and result' {
        $pending = Get-LofiTrackOcrAsync -Source 'test-source'
        $pending.ok | Should -BeTrue
        $pending.track | Should -BeNullOrEmpty
        $script:started.WaitOne(5000) | Should -BeTrue
        $handle = $script:LofiTrackWorker.Handle
        (Get-LofiTrackOcrAsync -Source 'test-source').track | Should -BeNullOrEmpty
        $script:LofiTrackWorker.Handle | Should -Be $handle
        $null = $script:gate.Set()
        $handle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
        (Get-LofiTrackOcrAsync -Source 'test-source').track | Should -Be 'artist - title'
        (Get-LofiTrackOcrAsync -Source 'test-source').track | Should -Be 'artist - title'
        Should -Invoke New-LofiTrackWorker -Times 1 -Exactly
    }

    It 'cancels overdue detection and runs its cleanup' {
        $null = Get-LofiTrackOcrAsync -Source 'test-source'
        $script:started.WaitOne(5000) | Should -BeTrue
        $script:LofiTrackWorker.StartedAt = [datetime]::UtcNow.AddSeconds(-31)
        $result = Get-LofiTrackOcrAsync -Source 'test-source'
        $result.ok | Should -BeFalse
        $result.message | Should -Match 'timed out'
        $script:cleaned.WaitOne(5000) | Should -BeTrue
        $script:LofiTrackWorker | Should -BeNullOrEmpty
    }

    It 'cancels detection when lofi playback is stopped' {
        $null = Get-LofiTrackOcrAsync -Source 'test-source'
        $script:started.WaitOne(5000) | Should -BeTrue
        (Invoke-MapPlaybackAction -Action 'stop-lofi').lofi | Should -BeFalse
        $script:cleaned.WaitOne(5000) | Should -BeTrue
        $script:LofiTrackWorker | Should -BeNullOrEmpty
    }

    It 'returns a worker failure as a retryable track result' {
        $null = $script:testWorker.Pipeline.AddScript({
            function global:Get-LofiTrackOcr { throw 'OCR fixture failed' }
        }).Invoke()
        $null = Get-LofiTrackOcrAsync -Source 'test-source'
        $script:LofiTrackWorker.Handle.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
        $result = Get-LofiTrackOcrAsync -Source 'test-source'
        $result.ok | Should -BeFalse
        $result.message | Should -Match 'OCR fixture failed'
        $script:LofiTrackWorker | Should -BeNullOrEmpty
    }

    It 'terminates an in-flight native OCR process on cancellation' {
        $childScript = Join-Path $TestDrive 'ocr-child.ps1'
        $pidPath = Join-Path $TestDrive 'ocr-child.pid'
        Set-Content $childScript 'param($PidPath); Set-Content -LiteralPath $PidPath -Value $PID; Start-Sleep -Seconds 60'
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testExecutable', (Get-Process -Id $PID).Path)
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testChildScript', $childScript)
        $script:testWorker.Runspace.SessionStateProxy.SetVariable('testPidPath', $pidPath)
        $null = $script:testWorker.Pipeline.AddScript({
            function global:Get-LofiTrackOcr {
                try { & $testExecutable -NoProfile -File $testChildScript -PidPath $testPidPath }
                finally { $null = $testCleaned.Set() }
            }
        }).Invoke()
        $null = Get-LofiTrackOcrAsync -Source 'test-source'
        $deadline = [datetime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path $pidPath) -and [datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 20
        }
        Test-Path $pidPath | Should -BeTrue
        $child = Get-Process -Id ([int](Get-Content $pidPath))
        try {
            Stop-LofiTrackWorker
            $child.WaitForExit(5000) | Should -BeTrue
            $script:cleaned.WaitOne(5000) | Should -BeTrue
        }
        finally {
            if (-not $child.HasExited) { $child.Kill() }
            $child.Dispose()
        }
    }
}

Describe 'Persistent map HTTP controls during OCR' {
    It 'serves stop, resume, restart and a second channel while OCR is held open' {
        $server = Start-ATCMapServer
        $gate = [System.Threading.ManualResetEvent]::new($false)
        $started = [System.Threading.ManualResetEvent]::new($false)
        $session = [System.Management.Automation.PowerShell]::Create()
        try {
            $null = $session.AddScript({
                param($Root, $Listener, $Gate, $Started)
                . (Join-Path $Root 'lofiatc.ps1')
                $script:testGate = $Gate
                $script:testStarted = $Started
                $script:originalWorkerFactory = ${function:New-LofiTrackWorker}
                function New-LofiTrackWorker {
                    param($Source)
                    $worker = & $script:originalWorkerFactory -Source $Source
                    $worker.Runspace.SessionStateProxy.SetVariable('testGate', $script:testGate)
                    $worker.Runspace.SessionStateProxy.SetVariable('testStarted', $script:testStarted)
                    return $worker
                }
                function Get-LofiTrackOcr {
                    param($Source)
                    $null = $testStarted.Set()
                    while (-not $testGate.WaitOne(0)) { Start-Sleep -Milliseconds 20 }
                    return @{ ok = $true; available = $true; track = 'artist - title'; message = 'Detected' }
                }
                function Test-InteractiveConsoleAvailable { return $false }
                function Start-PlayerProcess { return [System.Diagnostics.Process]::GetCurrentProcess() }
                function Test-ManagedProcessAlive { param($Process) return $null -ne $Process }
                function Stop-ManagedProcess { param($Process) }
                $sources = @(
                    [pscustomobject]@{ ICAO = 'TEST'; 'Channel Description' = 'Tower'; 'Airport Name' = 'Fixture'; 'Stream URL' = 'test:one'; 'Webcam URL' = '' },
                    [pscustomobject]@{ ICAO = 'TEST'; 'Channel Description' = 'Approach'; 'Airport Name' = 'Fixture'; 'Stream URL' = 'test:two'; 'Webcam URL' = '' }
                )
                Start-PersistentATCMapSession -Listener $Listener -AtcSources $sources -Player MPV `
                    -ATCVolume 50 -LofiVolume 50 -LofiMusicUrl 'test-source' -ShowLofiTrack -MapControlToken 'test-token'
            }).AddArgument($repoRoot).AddArgument($server.Listener).AddArgument($gate).AddArgument($started)
            $handle = $session.BeginInvoke()
            $uri = "http://127.0.0.1:$($server.Port)/?token=test-token&"
            (Invoke-RestMethod ($uri + 'icao=TEST&channelIndex=0') -TimeoutSec 10).channel | Should -Be 'Tower'
            (Invoke-RestMethod ($uri + 'action=lofi-track') -TimeoutSec 5).ok | Should -BeTrue
            $started.WaitOne(5000) | Should -BeTrue
            foreach ($action in @('stop-atc', 'resume-atc', 'restart')) {
                (Invoke-RestMethod ($uri + "action=$action") -TimeoutSec 5).ok | Should -BeTrue
            }
            (Invoke-RestMethod ($uri + 'icao=TEST&channelIndex=1') -TimeoutSec 5).channel | Should -Be 'Approach'
            $gate.WaitOne(0) | Should -BeFalse
            (Invoke-RestMethod ($uri + 'action=stop-all') -TimeoutSec 5).stopped | Should -BeTrue
        }
        finally {
            $null = $gate.Set()
            $session.Stop()
            $session.Dispose()
            $server.Listener.Close()
            $gate.Dispose()
            $started.Dispose()
        }
    }
}
