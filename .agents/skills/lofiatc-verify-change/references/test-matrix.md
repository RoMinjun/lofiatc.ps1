# Change-to-test matrix

| Changed area | Minimum targeted validation |
|---|---|
| `lofiatc.ps1`, Core, Player, Favorites, Weather, Map | `tests/lofiatc.Tests.ps1` |
| `install.ps1`, `uninstall.ps1` | `tests/Install.Tests.ps1` |
| `packaging/LofiATC/` | `tests/LofiATC.Module.Tests.ps1` |
| `tools/`, source sorting logic | `tests/SourceTools.Tests.ps1` plus the applicable tool check |
| `atc_sources.csv` | base sort check and `Check-AirportSource.ps1` |
| `liveatc_sources.csv` | live sort check; do not run airport-source coverage against the live file |
| CLI parameters/help | entrypoint tests, installed-module parity/completion tests, README review |
| `.agents/skills/` | skill `quick_validate.py`, TODO scan, link/path review, trigger-overlap review |

Use `LOFIATC_TEST_MODE=1` for runtime Pester tests. For a non-trivial change, run `Invoke-Pester ./tests -CI` when the environment permits.

Always inspect the GitHub matrix for PowerShell 7 on Windows, Ubuntu, and macOS, Windows PowerShell 5.1, and the repository's PowerShell 5.1 syntax check.
