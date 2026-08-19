---
name: lofiatc-verify-change
description: Select and run proportionate validation for LofiATC changes. Use after modifying runtime modules, CLI parameters, installer or updater code, ATC source data, map behavior, players, profiles, favorites, weather, tools, tests, documentation, or repo skills; also use to prepare a PR validation report or diagnose platform-specific CI coverage gaps.
---

# Verify a LofiATC change

Read `AGENTS.md`, inspect `git status`, and identify the requested diff before running checks. Read [test-matrix.md](references/test-matrix.md) to map touched paths to targeted tests.

## Workflow

1. Run `git diff --check` and inspect the actual diff, not only its file list.
2. Search touched runtime code for PowerShell 7-only syntax, unbounded requests, `exit` in modules, empty catches, unsafe interpolation, and unmanaged processes.
3. Run the smallest relevant Pester suite first with `LOFIATC_TEST_MODE=1`.
4. Run the complete suite for non-trivial or cross-module changes when PowerShell is available.
5. Run source sorting and airport-source checks only when their data is in scope.
6. Verify help, README, installed module, completion, and installer parity for public changes.
7. If PowerShell or a platform is unavailable locally, state that limitation and require the matching CI job; never claim it passed locally.
8. Report commands actually run, results, skipped checks, and remaining manual validation.

Do not weaken assertions or skip a failing platform solely to make CI green. Use the GitHub CI repair workflow to inspect failed job logs.
