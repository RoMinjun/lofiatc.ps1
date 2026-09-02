---
name: lofiatc-airport-recommendations
description: Recommend verified, paste-ready airport JSON records with README-ready evidence for RoMinjun/Airports when LofiATC source ICAOs are absent from airports.json or existing airport metadata appears incorrect. Use for airport coverage audits and evidence-backed addition or correction proposals, not for ATC stream maintenance or automatically changing an external repository.
---

# Recommend airport dataset changes

Read `AGENTS.md`, `CONTRIBUTING.md`, and [research-and-reporting.md](references/research-and-reporting.md) before researching candidates.

This skill recommends changes to the `RoMinjun/Airports` dataset consumed by LofiATC. A recommendation is not permission to edit that repository, open an issue, or submit a pull request.

## Find candidates

1. Compare unique, non-empty ICAO values in `atc_sources.csv` with the current `airports.json` from `RoMinjun/Airports`. Use `tools/Check-AirportSource.ps1` when appropriate, but independently confirm its reported gaps against the current target branch.
2. Treat rows from `liveatc_sources.csv` as supporting leads only unless the user explicitly includes them. Base coverage is authoritative for LofiATC's maintained airport-source check.
3. Before recommending an addition, verify that the identifier belongs to an airport or aerodrome accepted by the target dataset. Do not assume every four-letter ATC source identifier is an airport; FIRs, control centers, shared feeds, local identifiers, obsolete codes, and typographical errors require different handling.
4. Check for renamed airports, replacement ICAOs, duplicate records, aliases, and case differences. Recommend a correction instead of an addition when that matches the evidence.

## Require corroborated evidence

For every proposed record or correction:

- Use at least two independent sources. Prefer three or more.
- Require at least one governmental source, such as a national civil aviation authority, official AIP, government aerodrome directory, or equivalent government publication.
- Prefer sources in this order: national aviation authority or official AIS data/change reports; other government aviation publications; the responsible public airport authority or airport operator; recognized aviation organizations; secondary aggregators only when primary evidence is unavailable for a field.
- Use current primary sources wherever possible. An airport operator can corroborate facts but does not satisfy the governmental-source requirement unless it is demonstrably the responsible public authority.
- Do not count mirrors or pages derived from the same underlying dataset as independent sources.
- Cite evidence at field level. Verify the ICAO, official name, municipality, country/subdivision, coordinates, elevation, IATA code when assigned, and IANA timezone rather than copying a complete record from one aggregator.
- Verify the display name independently from the identifier. An AIP/ERSA heading or code-decoded location can omit descriptors such as `Airport`, `Airfield`, or `Heliport`; do not assume that terse label is the complete target name. Check a second reliable public-facing or operator source and use the supported full facility name, while documenting material naming variants.
- Make every proposed JSON value traceable to the cited sources. When one linked airport record contains all ordinary fields, a short note naming the fields and published values is enough; do not force a large field-by-field table. Give exact document locations and transformations only where reviewers need them, especially for coordinates, rounding, disagreements, or archived evidence.
- For an identifier replacement, first look for a direct official narrative notice from the responsible authority. Also check structured authority change products such as NASR change reports, NFDD entries, AIP amendments, or official before-and-after cycle records tied to the same facility. If no standalone notice is found, use the strongest official structured change record and say so. A current listing with the new identifier alone is not enough to prove what the old identifier became.
- Check every cited URL immediately before reporting. Prefer stable record or publication-index pages over edition-specific file URLs. If only a dated or cycle-specific document carries the evidence, include its effective date, verify that its URL currently resolves, and also cite a stable landing page when available.
- Record publication or effective dates when available. Explain material disagreements and omit or mark unresolved fields instead of guessing.
- Respect source licenses and repository contribution rules. Verification does not authorize bulk copying from a restricted dataset.

## Form the recommendation

Inspect the current target repository schema and contribution instructions before formatting proposed JSON; do not rely on a remembered schema. Preserve exact types, null/empty conventions, keying, ordering, coordinate precision, elevation units, and timezone format.

For each candidate, report one outcome:

- **Recommend addition** — evidence supports a missing, in-scope airport.
- **Recommend correction** — an existing record or LofiATC source identifier is wrong or outdated.
- **Needs research** — minimum evidence or required fields are unresolved.
- **Do not recommend** — the identifier is not an eligible airport record, is already present, or lacks reliable support.

Provide a concise rationale, a schema-compatible proposed entry only when sufficiently verified, field-level source links, disagreements, confidence, and the suggested destination (`RoMinjun/Airports`, LofiATC source data, or neither). Never present uncertain data as ready to merge.

For merge-ready recommendations, always include:

1. A standalone, parseable JSON object containing only the proposed `airports.json` records. Use the target dataset's exact field order and types, with no comments, ellipses, trailing commas, citations, or provenance-only properties.
2. Concise Markdown evidence suitable for direct use as a pull-request description. Use one heading per airport in the form ``# `Airport name` (`ICAO`)``, followed by the primary URL and supporting URLs. Put the official or governmental source first. Add only short annotations for identifier changes, conversions, conflicts, or facts that are not obvious on the linked record. Keep source URLs and review metadata out of `airports.json`.
3. Explicit replacement instructions when an airport already exists under a stale key. State which old key must be removed so the paste-ready fragment does not create a duplicate. When useful, also provide a valid RFC 6902 JSON Patch describing removals and additions.

Do not copy issue numbers, closing keywords, or phrases such as `Could be used for #...` from an example. Include issue or pull-request linkage only when the user explicitly requests it for the current output.

Write the complete deliverable to a user-specified `.md` path. If none is supplied, use `airport-recommendations.md` in the current workspace. Inspect an existing file before replacing it and do not overwrite unrelated content. Keep the PR-facing airport sections brief, then include paste-ready JSON and replacement instructions. Add audit detail only when needed to explain non-obvious evidence. Treat it as a generated review artifact and do not stage or commit it unless the user asks.

Parse the target JSON before writing the report. Include only `Recommend addition` and `Recommend correction` records in paste-ready output; keep `Needs research` and `Do not recommend` candidates outside it. In the final response, link to the generated Markdown file.
