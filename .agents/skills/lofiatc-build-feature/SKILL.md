---
name: lofiatc-build-feature
description: Build or modify LofiATC runtime features and PowerShell functions. Use for new CLI options, selection behavior, map actions, player support, weather or network integrations, profiles, favorites, caches, installer-facing behavior, and refactors that change user-visible functionality. Do not use for source-only CSV maintenance, pure performance investigations, or issue-board administration.
---

# Build a LofiATC feature

Read the repository `AGENTS.md` before acting. Preserve its module boundaries and PowerShell 5.1 requirements.

## Establish the contract

1. Trace the current call path with `rg`; do not infer behavior from filenames alone.
2. State the requested user outcome, inputs, outputs, failure behavior, and compatibility constraints.
3. Identify the owning module. Keep `lofiatc.ps1` limited to parameters and orchestration.
4. Read only the applicable reference:
   - Functions or CLI parameters: [functions-and-cli.md](references/functions-and-cli.md)
   - Map or media behavior: [map-and-player.md](references/map-and-player.md)
   - Persistence, network, installer, or updater behavior: [state-network-installer.md](references/state-network-installer.md)

## Implement

1. Make the smallest complete change in the owning module.
2. Preserve existing behavior unless the request explicitly changes it.
3. Keep reusable functions non-interactive and use `throw` rather than `exit`.
4. Keep test-mode module loading free of browsers, players, prompts, and external requests.
5. Update packaging, installed-command forwarding, completion, help, and README when the public contract requires it.

## Verify

1. Add tests for successful behavior, invalid input, dependency failure, and state transitions that the feature introduces.
2. Mock network calls, processes, browsers, and destructive filesystem actions.
3. Invoke `$lofiatc-verify-change` to select the relevant local checks.
4. Inspect the final diff for unrelated refactors, PowerShell 7-only syntax, generated files, and user data.
5. Give the user a branch-specific install-script smoke test when the feature is intended for manual validation.
