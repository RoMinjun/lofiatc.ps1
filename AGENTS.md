# AGENTS.md

## Purpose

This file contains repository-level guidance for AI coding agents working on `lofiatc.ps1`.

The project is a cross-platform PowerShell application that combines live ATC audio, lofi playback, optional webcam playback, weather/airport data, favorites, and an interactive browser map. Changes should remain focused, reviewable, and compatible with the existing CLI and installation flow.

When working in this repository:

- Preserve existing behavior unless the task explicitly changes it.
- Prefer the smallest complete change that solves the requested problem.
- Avoid unrelated refactors.
- Update tests and documentation when behavior or user-facing options change.
- Do not invent airport metadata, stream URLs, source provenance, or external-service behavior.

## Repository layout

Use the existing ownership boundaries instead of putting new logic into whichever file is easiest.

| Path | Responsibility |
|---|---|
| `lofiatc.ps1` | CLI parameters, top-level orchestration, module loading, configuration flow, top-level error handling |
| `modules/LofiATC.Core.psm1` | Shared application logic, selection/configuration helpers, dependency checks, common helpers |
| `modules/LofiATC.Player.psm1` | Player detection, stream resolution, media process handling, lofi playback/OCR-related player logic |
| `modules/LofiATC.Favorites.psm1` | Favorites loading, selection, tracking, and persistence |
| `modules/LofiATC.Weather.psm1` | Weather, METAR, airport/location/time-related functionality |
| `modules/LofiATC.Map.psm1` | Interactive map, local browser interaction, persistent playback controls, map HTML/JavaScript |
| `packaging/LofiATC/` | Installed PowerShell module and updater-facing functionality |
| `install.ps1` | Installation and staged replacement logic |
| `uninstall.ps1` | Removal of installed files/profile integration |
| `tools/` | Maintainer utilities for ATC sources, airport metadata, sorting, and diagnostics |
| `tests/` | Pester test suites |
| `atc_sources.csv` | Maintained base ATC source dataset |
| `liveatc_sources.csv` | More frequently refreshed ATC source dataset |

### Feature placement

As a general rule:

- Keep `lofiatc.ps1` thin. It should coordinate features, not contain large implementations.
- Put media/player/process behavior in `LofiATC.Player.psm1`.
- Put map UI, local map API/listener behavior, and persistent map controls in `LofiATC.Map.psm1`.
- Put weather/METAR/location functionality in `LofiATC.Weather.psm1`.
- Put favorites behavior in `LofiATC.Favorites.psm1`.
- Put shared selection/config/dependency/helper logic in `LofiATC.Core.psm1`.

If a task crosses modules, keep the public flow simple and move reusable logic into the module that owns the behavior.

## Module-loading model

`lofiatc.ps1` reads the `.psm1` files as UTF-8 text and dot-sources them into the script scope.

Important consequences:

- Do not assume these files behave like independently imported PowerShell modules.
- Do not add `Export-ModuleMember` to the runtime modules unless the loading architecture is intentionally being redesigned.
- Functions and script-scoped state can interact across the dot-sourced files.
- Keep shared mutable state to a minimum.
- Prefer passing data through parameters and return values when practical.
- Existing `$script:` state used for persistent playback/map state may be extended when the feature genuinely requires shared session state, but do not introduce script-scoped variables for simple local calculations.

## PowerShell compatibility

The documented minimum is **PowerShell 5.1**. New runtime code must remain compatible with PowerShell 5.1 unless the task explicitly changes the supported version.

Do not introduce PowerShell 7-only syntax or features into application code, including:

- ternary expressions (`condition ? a : b`)
- null-coalescing operators (`??`, `??=`)
- pipeline chain operators (`&&`, `||`)
- `ForEach-Object -Parallel`
- other APIs or syntax unavailable on Windows PowerShell 5.1

Prefer constructs already used by the repository.

### Cross-platform behavior

The project supports Windows, macOS, and Linux.

- Avoid hard-coded Windows paths in shared runtime logic.
- Use `Join-Path`, `$PSScriptRoot`, and existing path helpers.
- Guard OS-specific behavior explicitly.
- Do not assume `powershell.exe`; PowerShell Core installations use `pwsh`.
- Do not assume a specific browser opener, media-player path, package manager, home directory, or path separator.
- When adding player behavior, preserve the current Windows and non-Windows selection rules unless intentionally changing them.

## Coding style

Follow the style of the file being edited.

Preferred practices:

- Use descriptive PowerShell verb-noun function names.
- Use `param(...)` blocks and validation attributes for user-controlled values where appropriate.
- Prefer `[string]::IsNullOrWhiteSpace(...)` when testing user/source text.
- Prefer early validation with clear errors.
- Return structured objects/hashtables when the caller needs multiple values.
- Keep functions focused.
- Avoid deeply nested control flow when a guard clause is clearer.
- Do not silently swallow unexpected exceptions.
- Use comments for non-obvious behavior, not to narrate straightforward code.
- Preserve the repository's existing indentation and line-continuation style in touched code.
- Avoid large formatting-only changes.

### Errors and process termination

Inside reusable runtime functions:

- Prefer `throw` for unrecoverable failures.
- Prefer `return` for normal control flow.
- Do **not** call `exit` from a helper in `modules/`; it can terminate the host PowerShell process and bypass the entrypoint's error handling.

The CLI entrypoint owns process exit behavior. It currently catches normal failures, writes an error, and exits non-zero. User cancellation may use `System.OperationCanceledException`.

Standalone maintainer scripts under `tools/` may own their process exit codes when that is already part of the script's contract.

## Test mode

The repository intentionally supports loading the application without starting the interactive main flow.

Tests set:

```powershell
$env:LOFIATC_TEST_MODE = '1'
```

When this is set, `lofiatc.ps1` loads the runtime functions and returns before interactive execution.

Preserve this behavior. Do not make module loading perform interactive work, open browsers, start players, or make unnecessary external requests.

## Testing requirements

The GitHub Actions test workflow runs Pester on Windows with:

```powershell
$env:LOFIATC_TEST_MODE = '1'
Invoke-Pester ./tests -CI
```

Run the most relevant tests for every code change. Run the complete suite before considering a non-trivial change finished when the environment allows it.

Useful targeted commands:

```powershell
$env:LOFIATC_TEST_MODE = '1'
Invoke-Pester ./tests/lofiatc.Tests.ps1

$env:LOFIATC_TEST_MODE = '1'
Invoke-Pester ./tests/Install.Tests.ps1

$env:LOFIATC_TEST_MODE = '1'
Invoke-Pester ./tests/LofiATC.Module.Tests.ps1
```

Use mocks for network calls, external programs, browsers, players, and destructive filesystem behavior where practical.

Add or update tests when changing:

- stream URL resolution
- player detection or process arguments
- configuration behavior
- favorites
- nearby/airport selection
- map request/action handling
- weather/METAR parsing
- OCR parsing/stabilization
- installer/updater behavior
- CLI parameter interactions
- error handling

Do not weaken assertions merely to make a change pass.

## CLI and documentation

The command-line interface is part of the public contract.

When adding or changing a parameter:

1. Update the `param(...)` block in `lofiatc.ps1`.
2. Update comment-based help (`.PARAMETER`).
3. Update configuration save/load behavior if the option is persistable.
4. Update installed-module/tab-completion behavior if applicable.
5. Add tests for validation and interactions with other switches.
6. Update `README.md`, especially:
   - Usage Recipes
   - Parameters (Quick Reference)
   - relevant feature section
   - dependency requirements if new software is needed

Avoid renaming or removing an existing CLI parameter without explicit instruction. Prefer aliases when maintaining backward compatibility is reasonable.

## Interactive map changes

`modules/LofiATC.Map.psm1` combines PowerShell server/session logic with generated browser UI behavior.

When modifying the map:

- Keep browser UI state and PowerShell playback state synchronized.
- Preserve persistent-map behavior (`-ShowMap -KeepOpen` / `-Persistent`).
- Treat channel index + ICAO selections as untrusted input and validate them before indexing source arrays.
- Validate volume and action inputs server-side even when the browser UI already constrains them.
- Reuse existing HTML/JavaScript escaping and serialization patterns instead of interpolating arbitrary source text directly into script fragments.
- Ensure temporary listeners/files/processes are cleaned up on success, error, and cancellation.
- Do not make the map require live weather when `-NoWeather` is specified.
- Avoid blocking the map request loop with slow unrelated work.
- Preserve behavior for repeated channel switching, stopping/restarting playback, favorites, random selection, webcam playback, and lofi playback when touching those paths.

For UI changes, test both the initial map state and state changes after a channel has already been selected.

## Media/player changes

Supported players currently include VLC, MPV, PotPlayer, and MPC-HC.

When changing player behavior:

- Keep player-specific arguments isolated.
- Do not assume all players support the same flags.
- Keep no-audio/no-video semantics correct for ATC, lofi, and webcam processes.
- Preserve volume bounds of `0..100`.
- Stop or replace managed processes deliberately; avoid orphaning media-player processes.
- Keep URL resolution separate from process launching when possible.
- External commands such as `yt-dlp`, `youtube-dl`, `ffmpeg`, and Tesseract are optional unless the selected feature requires them.
- A missing optional dependency should not break unrelated features.

## ATC source data

The CSV schema is:

```text
Continent,Country,City,State/Province,Airport Name,ICAO,IATA,Channel Description,Stream URL,Webcam URL,NearbyICAOs
```

Treat source-data changes differently from normal code changes.

### Never fabricate source data

Do not guess or synthesize:

- ICAO/IATA codes
- airport names
- coordinates or nearby-airport relationships
- channel names
- LiveATC stream slugs/URLs
- webcam URLs
- state/province values
- whether a feed is currently online

If authoritative information cannot be verified, leave the existing value unchanged or report the uncertainty.

### Source provenance

Follow `CONTRIBUTING.md`:

- Do not add third-party source lists, stream URLs, or metadata unless there is clear permission to use them.
- Prefer authoritative aviation/airport sources for airport metadata when available.
- Do not copy bulk datasets from unrelated projects merely because they are convenient.

### Base versus live data

- `atc_sources.csv` is the base dataset and must not be deleted.
- `liveatc_sources.csv` is the more frequently refreshed source file.
- Runtime behavior prefers `liveatc_sources.csv` when present unless `-UseBaseCSV` is used.

Do not casually replace one file with the other.

### Sorting

CSV changes must remain canonically sorted.

After changing the base file:

```powershell
./tools/Sort-ATCSources.ps1 -InputCsvPath "atc_sources.csv" -InPlace
```

After changing the live file:

```powershell
./tools/Sort-ATCSources.ps1 -InputCsvPath "liveatc_sources.csv" -InPlace
```

To verify without modifying:

```powershell
./tools/Sort-ATCSources.ps1 -InputCsvPath "atc_sources.csv" -Check
./tools/Sort-ATCSources.ps1 -InputCsvPath "liveatc_sources.csv" -Check
```

Do not rely on the GitHub Actions auto-sort job to fix an agent's local output.

### Network checks are not authoritative deletion signals

Be conservative when declaring a source dead.

`tools/CheckATCSources.ps1` currently performs HTTP `HEAD` checks and contains a TODO noting Cloudflare/direct-streaming limitations. The README also documents LiveATC challenge-page behavior.

Therefore:

- A failed automated HTTP check alone is **not** sufficient reason to delete a stream.
- Retry/verify through the appropriate source mechanism when possible.
- Distinguish a transient network failure, bot protection, redirect issue, resolver problem, and a genuinely removed feed.
- Do not bulk-remove rows solely because a CI/container environment cannot reach them.
- Preserve failures for manual review when certainty is low.

### Source-refresh tools

Do not run a full source refresh as a side effect of unrelated work.

`tools/UpdateATCSources.ps1` is a maintainer operation that can depend on external services and may take substantial time. Run it only when the task is specifically about refreshing sources.

When source rows are changed, also consider:

```powershell
./tools/Check-AirportSource.ps1 -CsvPath "./atc_sources.csv"
```

Network-dependent checks may be skipped or reported as inconclusive when the execution environment cannot access their dependencies.

## Installer and updater changes

Installation behavior is safety-sensitive because it modifies user files and PowerShell profile integration.

When changing `install.ps1`, `uninstall.ps1`, or `packaging/LofiATC/`:

- Preserve per-user installation behavior unless explicitly changing it.
- Preserve staged validation/replacement and rollback behavior.
- Avoid leaving partial installs after failure.
- Do not unexpectedly mutate the user's PowerShell profile.
- Keep repository/ref/commit tracking coherent.
- Preserve `-SkipPowerShellProfile` semantics.
- Test update behavior for both installer-based and Git-based installations when relevant.
- Mock downloads and external GitHub/API calls in unit tests.

Do not perform real installation into the agent host's user profile as part of routine testing.

## External services and network behavior

The application interacts with services outside this repository. External responses are not under our control.

- Use explicit timeouts for new network requests.
- Fail gracefully when optional external data is unavailable.
- Do not turn a temporary API failure into corrupted local state.
- Cache only when there is a clear invalidation/age policy.
- Do not hard-code credentials, tokens, cookies, or private endpoints.
- Never commit secrets.
- Prefer existing endpoints and helpers over adding a new dependency for equivalent data.

## Dependencies

Keep dependencies minimal.

Before introducing a new required external program, PowerShell module, web service, or JavaScript dependency:

- verify that an existing dependency cannot solve the problem;
- consider PowerShell 5.1 and all supported operating systems;
- make it optional when the feature itself is optional;
- add dependency detection;
- update `README.md`;
- add useful failure messaging.

Do not add a dependency solely to avoid writing a small amount of straightforward PowerShell.

## Git and change scope

Keep changes easy to review.

- Before starting work on a GitHub issue, create a new dedicated branch from the requested base branch (or the repository default when none is specified) and link it to the issue, preferably with `gh issue develop`. If the issue is in the project board's `Ready` status, move it to `In progress` when work begins.
- One logical change per branch/PR.
- Avoid unrelated cleanup.
- Do not rewrite large CSVs unless the task requires data changes.
- Do not reformat entire PowerShell modules for a small fix.
- Preserve line endings/encoding when possible.
- Use clear commit messages describing the behavior changed.

Branches under `feature/**` and `enhancement/**` are covered by the repository's push test workflow.

Before finishing, inspect the diff and make sure generated files, temporary map files, test artifacts, local configuration, favorites, credentials, and editor files are not included.

## Definition of done

Before declaring a task complete, verify the applicable items:

- [ ] The change is in the correct module/file.
- [ ] PowerShell 5.1 compatibility is preserved.
- [ ] Windows/macOS/Linux behavior was considered.
- [ ] No secrets or fabricated source data were introduced.
- [ ] Error paths clean up processes/files/listeners appropriately.
- [ ] Relevant Pester tests were added or updated.
- [ ] Relevant tests pass.
- [ ] CSVs were canonically sorted if source data changed.
- [ ] Failed source checks were not treated as authoritative without verification.
- [ ] CLI help and README were updated for user-facing changes.
- [ ] Installer/module packaging was updated if runtime files or installed behavior require it.
- [ ] The final diff contains no unrelated refactors or generated junk.

## Agent response expectations

When reporting completed work:

- State what changed and why.
- Name the important files touched.
- Report the tests/checks actually run and whether they passed.
- Clearly identify anything that could not be validated.
- For source-data work, cite the source used to verify metadata/URLs and call out uncertain rows instead of guessing.
- Do not claim a network source is dead, an installer works on a platform, or a player behaves correctly unless that conclusion was actually validated.
