# State, network, and installed behavior

## Persisted state

- Store user state under `Get-LofiATCUserDataPath`.
- Use validated atomic replacement for JSON. Preserve last-known-good `.bak` behavior and malformed-file recovery.
- Define precedence, cache freshness, invalidation, and fallback behavior before implementing.
- Never overwrite valid state with partial, empty, or unvalidated external data.

## External services

- Add explicit timeouts and `-ErrorAction Stop` to requests.
- Decide whether the service is required for the selected feature or optional to unrelated playback.
- Return an intentional unavailable result for optional failures and expose useful verbose diagnostics.
- Mock success, timeout, malformed responses, cold failure, and cached fallback.
- Do not add credentials, private endpoints, or unnecessary dependencies.

## Installer and updater impact

- Determine whether runtime files, wrapper parameters, completions, or installed-module behavior must change.
- Preserve per-user installation, staged validation, rollback, repository/ref/commit metadata, and `-SkipPowerShellProfile`.
- Mock downloads and installation paths. Never perform a real installation into the agent host during routine testing.
- Provide a non-Git install-script test for user-facing changes.
