# Updates atc_sources.csv by fetching data from LiveATC
param(
    [string[]]$ICAO
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$csvPath   = Join-Path $scriptDir '..\atc_sources.csv'

# Helper function: fetch ATC streams
function Get-LiveATCSources {
    param([string]$Url)
    $icao = $Url -replace ".*icao=([A-Za-z0-9]+).*", '$1'
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    $feeds = @()
    $current = ''
    $content -split '<tr>' | ForEach-Object {
        $row = $_.Trim()
        if ($row -match '<td[^>]*bgcolor="lightblue"[^>]*>\s*<strong>(?<f>[^<]+)</strong>') {
            $current = $matches['f'].Trim()
        }
        elseif ($row -match '<td[^>]*>\s*<a href="(?<u>[^"]+\.pls)"') {
            $feeds += [PSCustomObject]@{
                Airport = $icao
                Channel = $current
                URL     = 'https://www.liveatc.net' + $matches['u']
            }
        }
    }
    return $feeds
}

# Helper function: fetch airport details
function Get-AirportDetails {
    param([string]$Url)
    $content = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    $result = [PSCustomObject]@{
        ICAO='';IATA='';Airport='';City='';Province='';Country='';Continent=''
    }
    $content -split '<tr>' | ForEach-Object {
        $row = $_.Trim()
        if ($row -match '<td[^>]*>\s*<strong>ICAO:\s*</strong>(?<icao>[^<]+)\s*<strong>&nbsp;&nbsp;IATA:\s*</strong>(?<iata>[^<]+)\s*&nbsp;&nbsp;<strong>Airport:</strong>\s*(?<airport>[^<]+)') {
            $result.ICAO = $matches['icao'].Trim()
            $result.IATA = $matches['iata'].Trim()
            $result.Airport = $matches['airport'].Trim()
        }
        elseif ($row -match '<td[^>]*>\s*<strong>City:\s*</strong>\s*(?<city>[^<]+)(?:\s*<strong>&nbsp;&nbsp;State/Province:</strong>\s*(?<prov>[^<]+))?') {
            $result.City = $matches['city'].Trim()
            if ($matches['prov']) { $result.Province = $matches['prov'].Trim() }
        }
        elseif ($row -match '<td[^>]*>\s*<strong>Country:\s*</strong>\s*(?<country>[^<]+)\s*<strong>&nbsp;&nbsp;Continent:</strong>\s*(?<continent>[^<]+)') {
            $result.Country = $matches['country'].Trim()
            $result.Continent = $matches['continent'].Trim()
        }
    }
    return @($result)
}

# Combine ATC feeds with airport details in repo CSV format
function Combine-Data {
    param($Feeds,$Details)
    $combined = @()
    foreach($f in $Feeds){
        $d = $Details | Where-Object { $_.ICAO -eq $f.Airport }
        if($d){ $d = $d[0] }
        $combined += [PSCustomObject][ordered]@{
            Continent = $d.Continent
            Country   = $d.Country
            City      = $d.City
            'State/Province' = $d.Province
            'Airport Name'   = $d.Airport
            ICAO     = $d.ICAO
            IATA     = $d.IATA
            'Channel Description' = $f.Channel
            'Stream URL'  = $f.URL
            'Webcam URL'  = ''
        }
    }
    return $combined
}

# Import existing data if available
$existing = if(Test-Path $csvPath){ Import-Csv $csvPath } else { @() }

if(-not $ICAO){ $ICAO = $existing.ICAO | Sort-Object -Unique }

$newData = @()
foreach($code in $ICAO){
    $url = "https://www.liveatc.net/search/?icao=$code"
    try{
        $feeds   = Get-LiveATCSources -Url $url
        $details = Get-AirportDetails -Url $url
        $newData += Combine-Data -Feeds $feeds -Details $details
    }catch{
        Write-Warning "Failed to fetch data for $code"
    }
}

# Merge and deduplicate by Stream URL
$merged = @($existing + $newData) | Sort-Object 'Stream URL' -Unique

$header = 'Continent','Country','City','State/Province','Airport Name','ICAO','IATA','Channel Description','Stream URL','Webcam URL'
$merged | Select-Object $header | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "Updated $csvPath with" $merged.Count "entries." -ForegroundColor Green
