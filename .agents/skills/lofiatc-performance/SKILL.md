---
name: lofiatc-performance
description: Measure and improve LofiATC runtime performance while preserving behavior and cross-platform compatibility. Use for slow startup, delayed menus, map load latency, weather waits, CSV or JSON processing cost, repeated channel switching, player startup, OCR latency, excessive memory or CPU use, and performance-regression reviews. Do not use for speculative cleanup without a measurable slow scenario.
---

# Improve LofiATC performance

Read `AGENTS.md` and [performance-surfaces.md](references/performance-surfaces.md). Do not optimize before identifying the dominant cost.

## Define and measure

1. Define the user scenario, platform, PowerShell version, player, dataset, network state, and requested switches.
2. Separate cold start, warm start, CPU work, filesystem work, network wait, browser work, and external process startup.
3. Capture a baseline with one warm-up and at least five comparable runs when practical. Report the median; include spread or outliers when meaningful.
4. Add temporary `Stopwatch` instrumentation at ownership boundaries rather than timing only the entire command.
5. Keep network responses, source data, and optional dependencies controlled or mocked when comparing code paths.

## Optimize

1. Target the largest measured contributor with the smallest behavior-preserving change.
2. Prefer reducing repeated work, batching existing requests, lazy optional work, efficient lookups, and bounded caching with invalidation.
3. Preserve PowerShell 5.1, test mode, output order, selection semantics, process cleanup, and error behavior.
4. Do not add parallelism, caching, or a dependency without accounting for rate limits, stale state, memory, cancellation, and all supported platforms.
5. Remove temporary instrumentation unless it becomes intentional verbose diagnostics.

## Prove the result

1. Rerun the same measurements and report baseline versus candidate using the same statistic.
2. Add a deterministic regression test for the optimized behavior; avoid brittle wall-clock assertions in normal CI.
3. Run functional tests for the touched module and full tests for cross-cutting changes.
4. Check memory/process cleanup and repeated-use behavior, not only the first invocation.
5. State what was not measurable locally and use the matching platform CI or user smoke test.
