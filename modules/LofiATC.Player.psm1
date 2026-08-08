# Functions dot-sourced by lofiatc.ps1. Keep script-scoped state in the entrypoint.

Function Get-DefaultAppForMP4 {
    try {
        $keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.mp4\UserChoice"
        if (Test-Path $keyPath) {
            $key = Get-ItemProperty -Path $keyPath -ErrorAction Stop
            $progID = $key.ProgID
        }
        else {
            $keyPath = "HKCR:\.mp4"
            if (Test-Path $keyPath) {
                $progID = (Get-ItemProperty -Path $keyPath -ErrorAction Stop).'(default)'
            }
            else {
                return $null
            }
        }

        if ($progID -like "Applications\*") {
            return $progID -replace "Applications\\"
            ""
        }
        else {
            return $progID
        }
    }
    catch {
        return $null
    }
}

# Main function to get user's location
Function Resolve-Player {
    param(
        [string]$ExplicitPlayer
    )

    if ($ExplicitPlayer) {
        return $ExplicitPlayer
    }

    if ($script:OnWindows) {
        $defaultApp = Get-DefaultAppForMP4
        $preferredPlayer = $null

        if ($defaultApp) {
            switch -Regex ($defaultApp.ToLower()) {
                'vlc' {
                    $preferredPlayer = 'VLC'
                }
                'mpv' {
                    $preferredPlayer = 'MPV'
                }
                'potplayer|daum' {
                    $preferredPlayer = 'Potplayer'
                }
                'mpc|mpc-hc' {
                    $preferredPlayer = 'MPC-HC'
                }
            }
        }

        if ($preferredPlayer) {
            $preferredCommand = switch ($preferredPlayer) {
                'VLC' {
                    'vlc.exe'
                }
                'MPV' {
                    'mpv.exe'
                }
                'Potplayer' {
                    'PotPlayerMini64.exe'
                }
                'MPC-HC' {
                    'mpc-hc64.exe'
                }
            }

            if (Get-Command $preferredCommand -ErrorAction SilentlyContinue) {
                return $preferredPlayer
            }
        }
    }

    $candidates = if ($script:OnWindows) {
        @(
            @{ 
                Name = "MPV"
                Command = "mpv.exe"
            }
            @{
                Name = "VLC"
                Command = "vlc.exe"
            }
            @{
                Name = "Potplayer"
                Command = "PotPlayerMini64.exe"
            }
            @{
                Name = "MPC-HC"
                Command = "mpc-hc64.exe"
            }
        )
    }
    else {
        @(
            @{
                Name = "MPV"
                Command = "mpv"
            }
            @{
                Name = "VLC"
                Command = "vlc"
            }
        )
    }

    foreach ($candidate in $candidates) {
        if (Get-Command $candidate.Command -ErrorAction SilentlyContinue) {
            return $candidate.Name
        }
    }

    throw "No supported media player found in PATH."
}

# Function to resolve links correctly
Function Resolve-StreamUrl {
    param([string]$url)

    $resolvedUrl = $url

    if ($url -match 'youtu(be)?\.com|youtu\.be') {
        try {
            if (Get-Command yt-dlp -ErrorAction SilentlyContinue) {
                $resolved = yt-dlp -g --no-warnings --skip-download -- $url 2>$null
            }
            elseif (Get-Command youtube-dl -ErrorAction SilentlyContinue) {
                $resolved = youtube-dl -g --no-warnings --skip-download -- $url 2>$null
            }
            if ($resolved) {
                $resolvedUrl = ($resolved -join '')
            }
        }
        catch {
            Write-Warning "Failed to resolve YouTube URL with yt-dlp/youtube-dl. Falling back to original URL."
        }
    }
    elseif ($url -match '\.pls(\?|$)') {
        try {
            if ($url -match ".*/(?<feed>[^\.]+)\.pls") {
                $feedName = $matches['feed']
                $resolvedUrl = "http://d.liveatc.net/$feedName"
            }
            else {
                Write-Warning "Could not parse feed name from the provided PLS URL. Falling back to original"
            }
        }
        catch {
            Write-Warning "Failed to resolve PLS URL. Falling back to original URL."
        }
    }
    elseif (($script:IsLinux -or $IsLinux) -and $url -match 'liveatc\.net') {
        try {
            $m3u = curl -sL -- $url
            $streamLine = $m3u -split "`n" | Where-Object { $_ -and ($_ -notmatch '^#') } | Select-Object -First 1
            if ($streamLine) {
                $resolvedUrl = $streamLine
            }
        }
        catch {
            Write-Warning "Failed to resolve LiveATC M3U. Falling back to original URL."
        }
    }

    return $resolvedUrl
}

Function ConvertFrom-LofiTrackOcrText {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $ignoredPatterns = @(
        '^lofi\s*girl$',
        '^lofi\s+hip\s+hop\s+radio',
        '^beats\s+to\s+(relax|study)',
        '^@?lofigirl$'
    )

    $lines = @(
        $Text -split "`r?`n" |
            ForEach-Object { ($_ -replace '\s+', ' ').Trim(' ', '|', '_') } |
            Where-Object {
                $line = $_
                -not [string]::IsNullOrWhiteSpace($line) -and
                $line -match '[\p{L}\p{Nd}]' -and
                -not ($ignoredPatterns | Where-Object { $line -match $_ })
            }
    )

    if ($lines.Count -eq 0) {
        return $null
    }

    return ($lines | Select-Object -First 2) -join ' - '
}

Function ConvertFrom-LofiTrackOcrTsv {
    param(
        [AllowEmptyString()]
        [string]$Text,
        [double]$MinimumConfidence = 50
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        $rows = @($Text | ConvertFrom-Csv -Delimiter "`t")
    }
    catch {
        return $null
    }

    $lineKeys = [System.Collections.Generic.List[string]]::new()
    $wordsByLine = @{}
    foreach ($row in $rows) {
        if ([string]$row.level -ne '5' -or [string]::IsNullOrWhiteSpace([string]$row.text)) {
            continue
        }

        $confidence = 0.0
        if (-not [double]::TryParse(
            [string]$row.conf,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$confidence
        ) -or $confidence -lt $MinimumConfidence) {
            continue
        }

        $lineKey = '{0}:{1}:{2}:{3}' -f $row.page_num, $row.block_num, $row.par_num, $row.line_num
        if (-not $wordsByLine.ContainsKey($lineKey)) {
            $wordsByLine[$lineKey] = [System.Collections.Generic.List[object]]::new()
            $lineKeys.Add($lineKey)
        }
        $wordsByLine[$lineKey].Add($row)
    }

    $lines = foreach ($lineKey in $lineKeys) {
        $lineWords = @($wordsByLine[$lineKey] | Sort-Object { [int]$_.left })
        $accepted = [System.Collections.Generic.List[string]]::new()
        $previousRight = $null
        foreach ($word in $lineWords) {
            $left = [int]$word.left
            $height = [int]$word.height
            if ($null -ne $previousRight -and ($left - $previousRight) -gt [Math]::Max(90, $height * 3)) {
                break
            }

            $accepted.Add(([string]$word.text).Trim())
            $previousRight = $left + [int]$word.width
        }

        if ($accepted.Count -gt 0) {
            $accepted -join ' '
        }
    }

    return ConvertFrom-LofiTrackOcrText -Text ($lines -join "`n")
}

Function Write-LofiTrackUpdate {
    param([string]$Track)

    if ([string]::IsNullOrWhiteSpace($Track) -or $Track -eq $script:LastAnnouncedLofiTrack) {
        return
    }

    Write-Host "Lofi track: $Track" -ForegroundColor Cyan
    $script:LastAnnouncedLofiTrack = $Track
}

Function Resolve-StableLofiTrack {
    param(
        [string]$Track,
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Track)) {
        return $null
    }

    if ($script:StableLofiTrackSource -ne $Source) {
        $script:StableLofiTrack = $null
        $script:StableLofiTrackSource = $Source
        $script:LastAnnouncedLofiTrack = $null
    }

    if (-not $script:StableLofiTrack) {
        $script:StableLofiTrack = $Track
        return $Track
    }

    $titlePattern = '\s+-\s+.*$'
    $stableTitle = ($script:StableLofiTrack -replace $titlePattern, '') -replace '[^\p{L}\p{Nd}]', ''
    $detectedTitle = ($Track -replace $titlePattern, '') -replace '[^\p{L}\p{Nd}]', ''

    if ($stableTitle.Equals($detectedTitle, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $script:StableLofiTrack
    }

    $script:StableLofiTrack = $Track
    return $Track
}

Function Resolve-LofiOcrVideoUrl {
    param(
        [string]$Source,
        [int]$CacheMinutes = 10
    )

    $now = Get-Date
    if (
        $script:CurrentLofiOcrVideoUrl -and
        $script:CurrentLofiOcrVideoSource -eq $Source -and
        $script:CurrentLofiOcrVideoResolvedAt -and
        (($now - $script:CurrentLofiOcrVideoResolvedAt).TotalMinutes -lt $CacheMinutes)
    ) {
        return $script:CurrentLofiOcrVideoUrl
    }

    $resolverPath = Test-CommandAvailable -CommandName 'yt-dlp'
    if (-not $resolverPath) {
        $resolverPath = Test-CommandAvailable -CommandName 'youtube-dl'
    }
    if (-not $resolverPath) {
        throw 'yt-dlp or youtube-dl is required for Lofi track OCR.'
    }

    $resolved = & $resolverPath `
        -g `
        --no-warnings `
        --skip-download `
        -f 'best[height<=720]/best' `
        -- `
        $Source 2>$null

    $videoUrl = @($resolved | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($videoUrl)) {
        throw 'Could not resolve a video stream for Lofi track OCR.'
    }

    $script:CurrentLofiOcrVideoUrl = [string]$videoUrl
    $script:CurrentLofiOcrVideoSource = $Source
    $script:CurrentLofiOcrVideoResolvedAt = $now

    return $script:CurrentLofiOcrVideoUrl
}

Function Get-LofiTrackOcr {
    param(
        [string]$Source,
        [int]$CacheSeconds = 8
    )

    $now = Get-Date
    if (
        $script:CurrentLofiTrackResult -and
        $script:CurrentLofiTrackCheckedAt -and
        (($now - $script:CurrentLofiTrackCheckedAt).TotalSeconds -lt $CacheSeconds)
    ) {
        return $script:CurrentLofiTrackResult
    }

    $ffmpegPath = Test-CommandAvailable -CommandName 'ffmpeg'
    $tesseractPath = Resolve-TesseractPath

    if (-not $ffmpegPath -or -not $tesseractPath) {
        $missing = @()
        if (-not $ffmpegPath) { $missing += 'ffmpeg' }
        if (-not $tesseractPath) { $missing += 'Tesseract OCR' }

        $script:CurrentLofiTrackResult = @{
            ok        = $true
            available = $false
            track     = $null
            message   = "Install $($missing -join ' and ') to enable Lofi track OCR."
        }
        $script:CurrentLofiTrackCheckedAt = $now
        return $script:CurrentLofiTrackResult
    }

    $tempBasePath = Join-Path ([System.IO.Path]::GetTempPath()) ("lofiatc_ocr_{0}" -f ([guid]::NewGuid().ToString('N')))
    $capturePath = "$tempBasePath.png"
    $ocrOutputPath = "$tempBasePath.tsv"

    try {
        $videoUrl = Resolve-LofiOcrVideoUrl -Source $Source
        $videoFilter = 'crop=iw*0.32:ih*0.10:iw*0.07:ih*0.045,scale=1240:-1,format=gray,eq=contrast=1.8:brightness=0.05'

        & $ffmpegPath `
            -hide_banner `
            -loglevel error `
            -nostdin `
            -rw_timeout 15000000 `
            -y `
            -i $videoUrl `
            -frames:v 1 `
            -vf $videoFilter `
            $capturePath 2>$null | Out-Null
        $ffmpegExitCode = $LASTEXITCODE

        if ($ffmpegExitCode -ne 0 -or -not (Test-Path -LiteralPath $capturePath)) {
            $script:CurrentLofiOcrVideoUrl = $null
            throw 'Could not capture the Lofi Girl title overlay.'
        }

        & $tesseractPath $capturePath $tempBasePath --psm 6 tsv 2>$null | Out-Null
        $ocrExitCode = $LASTEXITCODE
        if ($ocrExitCode -ne 0 -or -not (Test-Path -LiteralPath $ocrOutputPath)) {
            throw 'Tesseract could not read the Lofi Girl title overlay.'
        }

        $ocrText = [System.IO.File]::ReadAllText($ocrOutputPath, [System.Text.Encoding]::UTF8)
        $track = ConvertFrom-LofiTrackOcrTsv -Text $ocrText
        $track = Resolve-StableLofiTrack -Track $track -Source $Source
        Write-LofiTrackUpdate -Track $track
        $script:CurrentLofiTrackResult = @{
            ok        = $true
            available = $true
            track     = $track
            message   = if ($track) { 'Lofi track detected.' } else { 'Track title is not currently visible.' }
        }
    }
    catch {
        $script:CurrentLofiTrackResult = @{
            ok        = $false
            available = $true
            track     = $null
            message   = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path -LiteralPath $capturePath) {
            Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $ocrOutputPath) {
            Remove-Item -LiteralPath $ocrOutputPath -Force -ErrorAction SilentlyContinue
        }
    }

    $script:CurrentLofiTrackCheckedAt = $now
    return $script:CurrentLofiTrackResult
}

# Function to check if the selected player is available
Function Test-Player {
    param (
        [string]$player
    )

    $command = switch ($player) {
        "VLC" { 
            if ($script:OnWindows) {
                "vlc.exe"
            } 
            else {
                "vlc"
            }
        }
        "MPV" {
            if ($script:OnWindows) {
                "mpv.exe" 
            }
            else {
                "mpv"
            }
        }
        "Potplayer" {
            "PotPlayerMini64.exe"
        }
        "MPC-HC" {
            "mpc-hc64.exe"
        }
        default {
            throw "Unsupported player: $player"
        }
    }

    $fullPath = Get-Command $command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    if (-not $fullPath) {
        throw "$player is not installed or not available in PATH. Please install $player to proceed."
    }

    if ($script:OnWindows -and $player -eq 'VLC') {
        $scoopShimPath = [System.IO.Path]::ChangeExtension($fullPath, '.shim')

        if (Test-Path -LiteralPath $scoopShimPath) {
            $shimMetadata = Get-Content -LiteralPath $scoopShimPath -Raw -ErrorAction SilentlyContinue

            if ($shimMetadata -match '(?m)^\s*path\s*=\s*"(?<Target>[^"]+)"\s*$' -and (Test-Path -LiteralPath $matches.Target)) {
                $fullPath = $matches.Target
            }
        }
    }

    return $fullPath
}

# Function to load the ATC sources from the CSV file
Function Get-VLCVolumeArg {
    param (
        [int]$volume,
        [switch]$NoAudio
    )

    if ($script:OnWindows) {
        $vlcConfigPath = Join-Path $env:APPDATA "vlc\vlcrc"; $module = $null
        if (Test-Path $vlcConfigPath) {
            try {
                $line = Get-Content -Path $vlcConfigPath | Where-Object { $_ -match '^\s*aout\s*=' -and $_ -notmatch '^\s*#' } | Select-Object -First 1
                if ($line) {
                    $module = ($line -split "=")[1].Trim().ToLower()
                }
            }
            catch {
                Write-Error ("[{0}] {1}" -f $MyInvocation.MyCommand.Name, $_.Exception.Message)
                return
            }
        }
        $v = [math]::Round([double]$volume / 100, 2)
        switch -Regex ($module) {
            'mmdevice|wasapi' { 
                return "--aout=wasapi --mmdevice-volume=$v" 
            }
            'waveout' {
                return "--aout=waveout --waveout-volume=$v"
            }
            default {
                return "--aout=directx --directx-volume=$v"
            }
        }
    }
    else {
        $pct = [math]::Max(0, [math]::Min(100, $volume))
        $vlcVol = if ($NoAudio) {
            0
        } 
        else {
            [int][math]::Round($pct * 2.56)
        }
        return [PSCustomObject]@{
            Mode = 'RCStdin'
            Prepend = ' --intf qt --extraintf rc --rc-fake-tty --verbose=-1 --quiet'
            Value = $vlcVol
        }
    }
}

# Function to start a media player with the specified URL and arguments
Function Start-Player {
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]

    param (
        [string]$url,
        [string]$player,
        [switch]$noVideo,
        [switch]$noAudio,
        [switch]$basicArgs,
        [int]$volume = 100
    )

    $url = Resolve-StreamUrl $url
    if (-not $PSCmdlet.ShouldProcess("$player -> $url", 'Start media player')) {
        return
    }

    $playerArgs = switch ($player) {
        "VLC" {
            $vlcArgs = "`"$url`" --no-one-instance"; if ($noVideo) {
                $vlcArgs += " --no-video"
            }
            if ($script:OnWindows) {
                $vol = if ($noAudio) {
                    0
                } 
                else {
                    $volume
                }
                $vlcArgs += " $(Get-VLCVolumeArg -volume $vol -NoAudio:$noAudio) --no-volume-save --quiet"
                $vlcArgs
            }
            else {
                if ($noAudio) {
                    $vlcArgs += " --no-audio"
                }
                $vlcArgs += " --quiet"; $volSetting = Get-VLCVolumeArg -volume $volume -NoAudio:$noAudio
                $playerPath = Test-Player -player "VLC"
                $psi = New-Object Diagnostics.ProcessStartInfo
                $psi.FileName = $playerPath; $psi.Arguments = "$($volSetting.Prepend) $vlcArgs"
                $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
                $proc = [Diagnostics.Process]::Start($psi)
                $proc.StandardInput.WriteLine("volume $($volSetting.Value)")
                return
            }
        }
        "MPV" {
            $mpvArgs = "`"$url`""
            if ($noVideo) {
                $mpvArgs += " --no-video"
            }
            
            if ($noAudio) {
                $mpvArgs += " --no-audio"
            }

            if ($basicArgs) {
                $mpvArgs += " --force-window=immediate --cache=yes --cache-pause=no --terminal=no"
            }
            $mpvArgs += " --volume=$volume"; $mpvArgs
        }
        "Potplayer" {
            $potplayerArgs = "`"$url`""
            if ($noAudio) {
                $potplayerArgs += " /volume=0"
            }

            if ($basicArgs) {
                $potplayerArgs += " /new" 
            }

            $potplayerArgs += " /volume=$volume"; $potplayerArgs
        }
        "MPC-HC" {
            $mpchcArgs = "`"$url`""
            if ($noAudio) {
                $mpchcArgs += " /mute"
            }
            if ($basicArgs) {
                $mpchcArgs += " /new"
            }

            $mpchcArgs += " /volume $volume"
            $mpchcArgs
        }
    }

    $playerPath = Test-Player -player $player
    if ($IsLinux) {
        Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow -RedirectStandardError '/dev/null' *> $null | Out-Null
    }
    else {
        Start-Process -FilePath $playerPath -ArgumentList $playerArgs -NoNewWindow *> $null | Out-Null
    }
}

Function Start-LofiATCSession {
    param(
        [hashtable]$SelectedATC,
        [string]$Player,
        [string]$LofiMusicUrl,
        [string]$FavoritesPath,
        [int]$MaxFavorites = 10,
        [int]$ATCVolume = 65,
        [int]$LofiVolume = 50,
        [switch]$NoLofiMusic,
        [switch]$PlayLofiGirlVideo,
        [switch]$IncludeWebcamIfAvailable,
        [switch]$OpenRadar,
        [switch]$RandomATC,
        [switch]$PlayerWasSpecified
    )

    $selectedATCUrl = $SelectedATC.StreamUrl
    $selectedWebcamUrl = $SelectedATC.WebcamUrl

    Clear-Host
    Write-Welcome -airportInfo $SelectedATC.AirportInfo -OpenRadar:$OpenRadar

    if (-not $RandomATC) {
        Add-Favorite -path $FavoritesPath -ICAO $SelectedATC.AirportInfo.ICAO -Channel $SelectedATC.AirportInfo.'Channel Description' -maxEntries $MaxFavorites
    }

    if ($OpenRadar) {
        Open-Radar -ICAO $SelectedATC.AirportInfo.ICAO
    }

    if ($PlayerWasSpecified) {
        Write-Verbose "Player selected by user: $Player"
    }
    else {
        Write-Verbose "Default player selected: $Player"
    }

    Write-Verbose "Opening ATC stream: $selectedATCUrl"
    if ($selectedWebcamUrl) {
        Write-Verbose "Opening webcam stream: $selectedWebcamUrl"
    }

    Start-Player -url $selectedATCUrl -player $Player -noVideo -basicArgs -volume $ATCVolume

    if (-not $NoLofiMusic) {
        Write-Verbose "Opening Lofi Girl stream: $LofiMusicUrl"
        if ($PlayLofiGirlVideo) {
            Start-Player -url $LofiMusicUrl -player $Player -basicArgs -volume $LofiVolume
        }
        else {
            Start-Player -url $LofiMusicUrl -player $Player -noVideo -basicArgs -volume $LofiVolume
        }
    }

    if ($IncludeWebcamIfAvailable -and $selectedWebcamUrl) {
        Start-Player -url $selectedWebcamUrl -player $Player -noAudio -basicArgs
    }
}

# Function to start a media player process and return the process object for later management
# with support for different players and argument configurations
Function Start-PlayerProcess {
    [CmdletBinding()]
    param (
        [string]$Url,
        [string]$Player,
        [switch]$NoVideo,
        [switch]$NoAudio,
        [switch]$BasicArgs,
        [int]$Volume = 100
    )

    $Url = Resolve-StreamUrl $Url

    $playerArgs = switch ($Player) {
        "VLC" {
            $vlcArgs = "`"$Url`" --no-one-instance"
            if ($NoVideo) {
                $vlcArgs += " --no-video"
            }

            if ($script:OnWindows) {
                $vol = if ($NoAudio) {
                    0
                } 
                else {
                    $Volume
                }

                $vlcArgs += " $(Get-VLCVolumeArg -volume $vol -NoAudio:$NoAudio) --no-volume-save --quiet"
                $vlcArgs
            }
            else {
                if ($NoAudio) {
                    $vlcArgs += " --no-audio"
                }

                $vlcArgs += " --quiet"
                $vlcArgs
            }
        }
        "MPV" {
            $mpvArgs = "`"$Url`""
            if ($NoVideo) {
                $mpvArgs += " --no-video"
            }
            if ($NoAudio) {
                $mpvArgs += " --no-audio"
            }
            if ($BasicArgs) {
                $mpvArgs += " --force-window=immediate --cache=yes --cache-pause=no --terminal=no"
            }
            $mpvArgs += " --volume=$Volume"
            $mpvArgs
        }
        "Potplayer" {
            $potArgs = "`"$Url`""
            if ($NoAudio) {
                $potArgs += " /volume=0"
            }
            if ($BasicArgs) {
                $potArgs += " /new"
            }
            $potArgs += " /volume=$Volume"
            $potArgs
        }
        "MPC-HC" {
            $mpcArgs = "`"$Url`""
            if ($NoAudio) {
                $mpcArgs += " /mute"
            }
            if ($BasicArgs) {
                $mpcArgs += " /new"
            }

            $mpcArgs += " /volume $Volume"
            $mpcArgs
        }
        default {
            throw "Unsupported player: $Player"
        }
    }

    $playerPath = Test-Player -player $Player

    if ($Player -eq 'VLC' -and -not $script:OnWindows) {
        $volSetting = Get-VLCVolumeArg -volume $Volume -NoAudio:$NoAudio
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $playerPath
        $psi.Arguments = "$($volSetting.Prepend) $playerArgs"
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $proc = [Diagnostics.Process]::Start($psi)
        $proc.StandardInput.WriteLine("volume $($volSetting.Value)")
        return $proc
    }

    return Start-Process -FilePath $playerPath -ArgumentList $playerArgs -PassThru
}

# Function to stop a media player process gracefully
# with error handling to avoid issues if the process has already exited or cannot be stopped
Function Stop-ManagedProcess {
    param(
        [System.Diagnostics.Process]$Process
    )

    if ($null -eq $Process) {
        return
    }

    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "Failed to stop process cleanly: $_"
    }
}

# Function to check if a media player process is still running, with error handling to account
# for cases where the process may have already exited or is not accessible
Function Test-ManagedProcessAlive {
    param(
        [System.Diagnostics.Process]$Process
    )

    if ($null -eq $Process) {
        return $false
    }

    try {
        return -not $Process.HasExited
    }
    catch {
        return $false
    }
}
