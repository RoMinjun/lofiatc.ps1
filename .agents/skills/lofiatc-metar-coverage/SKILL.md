---
name: lofiatc-metar-coverage
description: Audit whether ICAOs in LofiATC atc_sources.csv have current METAR coverage, validate configured NearbyICAOs, and discover verified alternate METAR stations when direct coverage is unavailable. Use for METAR coverage reports and explicitly authorized fallback updates, not for general weather runtime changes or ATC stream checks.
---

# Audit LofiATC METAR coverage

Read `AGENTS.md`, `CONTRIBUTING.md`, `tools/Check-METARSource.ps1`, and `tools/Get-MissingICAO.ps1` before acting because the scripts' parameters and side effects may change.

Keep challenge-solver URLs, credentials, responses, and cookies in separately installed personal configuration. When the resolver stage is needed, use the local `lofiatc-metar-private-access` skill if available. If private configuration is unavailable, complete the public audit, mark resolver discovery inconclusive, and ask for configuration rather than assuming localhost or adding an endpoint here.

## Run the primary audit

1. Confirm the repository root and inspect `git status`. A request to check coverage is read-only and does not authorize CSV edits.
2. Use `atc_sources.csv` as the base inventory unless the user explicitly includes `liveatc_sources.csv`.
3. Run `tools/Check-METARSource.ps1` in a child PowerShell process so its intentional `exit 1` does not terminate the agent's host process. Use the repository command shape:

   ```powershell
   .\Check-METARSource.ps1 -AtcSourcesCsv ..\atc_sources.csv -ForceRefresh
   ```

   Supply rooted temporary paths for `-CachedGz`, `-ExtractedCsv`, and `-OutReportCsv` so generated METAR data and reports do not enter the worktree. Use `-ForceRefresh` for a current audit unless the user explicitly accepts a dated cache.
4. Interpret exit code `0` as resolved by the script and exit code `1` as unresolved ICAOs written to the report. Distinguish those expected results from download, decompression, parsing, or network failures.
5. Record which direct ICAOs came from the Aviation Weather Center cache and which were recovered by the script's VATSIM same-ICAO fallback. A missing observation in one current snapshot is not proof that a station never reports.

## Verify configured alternates

`Check-METARSource.ps1` skips every source row whose `NearbyICAOs` field is non-empty. Its success message therefore does not prove that configured alternates currently report METARs.

- Parse every configured alternate separately. Treat semicolon as the repository's canonical delimiter; tolerate commas only while diagnosing legacy or tool output.
- Verify at least one alternate for each affected source ICAO against the fresh Aviation Weather Center cache or the VATSIM METAR endpoint.
- Reject blank tokens, malformed identifiers, the original ICAO itself, duplicates, and alternates that do not currently return a real METAR.
- Check geographic reasonableness using authoritative airport coordinates when available. Do not accept a distant reporting station solely because a discovery page suggested it.
- Report configured alternates as verified, stale, or inconclusive. Do not remove a stale alternate based on a single failed snapshot.

## Discover missing alternates safely

Use `tools/Get-MissingICAO.ps1` only when unresolved ICAOs remain. The script has no dry-run mode: it reads fixed relative paths, rewrites both source CSVs, creates `.bak` files, and writes `missing_from_metars_resolved.csv`.

1. Create an isolated temporary directory with this layout:

   ```text
   audit-root/
   |-- atc_sources.csv
   |-- liveatc_sources.csv
   `-- tools/
       |-- Get-MissingICAO.ps1
       `-- missing_from_metars.csv
   ```

2. Copy only the needed inputs into it and run the copied script from `audit-root/tools`. Obtain `-flaresolverrUrl` from the private local skill or user-provided runtime configuration. Never run the resolver directly against the real repository merely to discover candidates.
3. Read `missing_from_metars_resolved.csv` and the staged CSV diff. Treat `metar-taf.com` and its `stationSelectButton` value as discovery leads, not authoritative proof.
4. Require every proposed fallback to be a single four-character station ICAO, differ from the missing ICAO, return a valid current METAR from AWC or VATSIM, and be geographically suitable. Resolve ambiguous or non-ICAO output manually.
5. Remove the staging directory and solver artifacts after review. Do not retain full solver responses or cookies.

## Apply updates only when authorized

When the user explicitly asks to add or fix fallbacks:

- Update `NearbyICAOs` in every matching base row and in corresponding live rows only when that dataset is in scope.
- Preserve verified existing fallbacks and join multiple ICAOs with semicolons. Do not copy the resolver script's comma-joining behavior into repository data.
- Make the smallest CSV diff, then canonically sort each changed file.
- Run `tests/SourceTools.Tests.ps1`, the applicable sort checks, and the METAR audit again. Independently recheck the added alternates because `Check-METARSource.ps1` skips configured rows.
- Do not commit generated caches, missing reports, resolver output, `.bak` files, HTML, cookies, or private endpoint details.

## Report

Summarize counts for direct AWC coverage, direct VATSIM recovery, verified configured alternates, unresolved airports, proposed alternates, and inconclusive checks. For each unresolved or changed ICAO, name the verified alternate and public evidence used. Clearly state the cache retrieval time, network failures, script limitations, files changed, and validation actually run.
