# Source checks

## Schema

```text
Continent,Country,City,State/Province,Airport Name,ICAO,IATA,Channel Description,Stream URL,Webcam URL,NearbyICAOs
```

## Deterministic checks

For the base file:

```powershell
./tools/Sort-ATCSources.ps1 -InputCsvPath "atc_sources.csv" -InPlace
./tools/Sort-ATCSources.ps1 -InputCsvPath "atc_sources.csv" -Check
./tools/Check-AirportSource.ps1 -CsvPath "./atc_sources.csv"
```

For the live file:

```powershell
./tools/Sort-ATCSources.ps1 -InputCsvPath "liveatc_sources.csv" -InPlace
./tools/Sort-ATCSources.ps1 -InputCsvPath "liveatc_sources.csv" -Check
```

Do not run `Check-AirportSource.ps1` against `liveatc_sources.csv`.

## Network interpretation

- Distinguish redirects, Cloudflare challenges, resolver failures, timeouts, transient outages, and confirmed removal.
- A failed `HEAD` request is insufficient to remove a source.
- Do not run a full source refresh as a side effect of unrelated work.
- Prefer authoritative airport sources for metadata and permitted first-party sources for stream provenance.
