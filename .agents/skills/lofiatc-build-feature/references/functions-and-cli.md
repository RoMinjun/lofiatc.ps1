# Functions and CLI changes

## Functions

- Put shared selection, configuration, dependency, and general helpers in `LofiATC.Core.psm1`.
- Put process and media behavior in `LofiATC.Player.psm1`; favorites, weather, and map behavior in their named modules.
- Remember that runtime modules are read and dot-sourced into script scope, not imported independently. Do not add `Export-ModuleMember`.
- Prefer parameters and return values over new `$script:` state. Use structured objects when callers need several results.
- Validate user-controlled values early. Preserve volume bounds and validate array indexes before use.
- Throw unrecoverable errors from helpers. Reserve `exit` for the CLI entrypoint or standalone maintainer tools.
- Avoid PowerShell 7-only syntax and APIs. Confirm Windows PowerShell 5.1 parsing.

## CLI parameters

Treat a parameter as a public contract. Inspect and update, when applicable:

1. `lofiatc.ps1` comment help and `param(...)` declaration.
2. Configuration/profile load, save, precedence, and exclusion lists.
3. Installed module forwarding and tab completion under `packaging/LofiATC/`.
4. Validation and interactions with existing switches.
5. CLI parity and behavior tests.
6. README usage recipes, quick reference, and feature documentation.

Explicit CLI arguments must continue to override loaded configuration and profiles.
