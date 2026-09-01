---
name: lofiatc-source-maintenance
description: Maintain and review LofiATC airport and stream source data in atc_sources.csv and liveatc_sources.csv. Use for adding, correcting, refreshing, sorting, validating, or removing source rows; checking airport coverage; investigating suspected dead feeds; or reviewing source-data pull requests. Do not use for ordinary runtime code changes with no CSV impact.
---

# Maintain ATC source data

Read `AGENTS.md`, `CONTRIBUTING.md`, and [source-checks.md](references/source-checks.md) before editing source rows.

## Verify before editing

1. Identify whether the requested change belongs in the maintained base dataset, refreshed live dataset, or both.
2. Verify every changed field from an authoritative or clearly permitted source. Record URLs and uncertainties.
3. Never invent airport metadata, channel names, LiveATC slugs, stream URLs, webcams, nearby relationships, or online status.
4. Treat automated network failures as diagnostic evidence, not deletion authority.

## Edit and validate

1. Preserve the exact CSV schema and avoid rewriting unrelated rows.
2. Canonically sort every changed CSV locally.
3. Run airport-source coverage against `atc_sources.csv` only. Airports present in `liveatc_sources.csv` are expected to exist in the base airport source set.
4. Run relevant Pester source-tool tests.
5. Inspect the diff for encoding changes, duplicate rows, fabricated data, and unrelated bulk churn.

## Report

List rows changed, verification sources, sorting/check results, inconclusive network checks, and any values deliberately left unchanged because they could not be verified.
