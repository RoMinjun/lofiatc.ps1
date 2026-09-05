# Airport research and reporting

## Research order

1. Read the current `RoMinjun/Airports` README, contribution guidance, target branch, and nearby JSON entries to establish repository scope and schema.
2. Establish the candidate's identity and current operational status from a governmental aviation source. Separately verify its full display name; authority code tables and aeronautical headings may publish only a terse location label.
3. Corroborate the record with at least one independent source; seek a third or additional sources whenever practical.
4. Verify coordinates and elevation against an aerodrome chart, AIP entry, or government directory where available. Confirm whether coordinates identify the aerodrome reference point rather than a runway end, terminal, city, or navigation aid.
5. Verify the timezone using the geographic location and a current IANA time-zone source. Do not derive a permanent timezone from a current UTC offset.
6. Test cited links near the end of the task. A search-engine extract or previously indexed PDF is not evidence that the link is still available. For sites that rotate aeronautical cycles, discover the current document from the publisher's index rather than modifying an old URL by guesswork.
7. For identifier changes, search the authority's historical change products. Match the old and new records using a stable facility/site identifier, coordinates, or another authoritative identity key, and cite the effective cycle. Prefer an explicit change report containing both deletion and addition records over an inference from unrelated old and new pages.
8. When evidence is packaged in a ZIP or another archive, link both the authority's archive/edition page and the direct official download. In the report, name the archive member inspected, the stable keys used to match records, the relevant actions or values, and the extraction method. Do not make reviewers download an unexplained archive and guess where the evidence is.

Useful governmental evidence varies by jurisdiction and can include a national AIP, civil aviation authority airport register, FAA airport data, Transport Canada publications, or another official aeronautical information service. ICAO publications may provide strong primary evidence but do not replace the explicit governmental-source requirement when no government publication has been checked.

Wikipedia, search-result snippets, map pins, and general airport aggregators can help discovery but should not be the sole basis for a field. Two sites repeating the same OurAirports, OpenFlights, or other upstream record count as one lineage, not two independent confirmations.

## Evidence matrix

For each proposed airport, capture:

| Field | Proposed value | Exact source value and location | Transformation or decision | Agreement or caveat |
|---|---|---|---|---|
| ICAO |  |  |  |
| IATA |  |  |  |
| Name |  |  |  |
| City |  |  |  |
| State/subdivision |  |  |  |
| Country |  |  |  |
| Latitude/longitude |  |  |  |
| Elevation |  |  |  |
| IANA timezone |  |  |  |

Use the current target schema's actual field names in the final proposed entry. Leave genuinely optional fields in the form required by that schema. If a required field cannot meet the evidence threshold, classify the candidate as `Needs research` rather than manufacturing a complete object.

## Pull-request evidence format

Keep the human-facing evidence compact enough to paste directly into a pull request. Use this shape for each merge-ready record:

```markdown
# `Airport name` (`ICAO`)
https://official.example/airport-record
https://supporting.example/airport-record (supporting source)

Short evidence note only when needed, such as an identifier replacement, source disagreement, coordinate conversion, or archive member inspected.
```

If one authoritative airport record publishes the ordinary metadata fields, do not repeat every field in a large table. Briefly state that the record supplies the name, location, coordinates, elevation, and identifiers. Show exact source values and calculations for transformed coordinates, integer rounding, disputed values, or identifier history. For an archive, name the member and stable record key. Put official sources before aggregators.

After the per-airport sections, provide one parseable target-schema JSON object containing all merge-ready records and explicit removal instructions for stale keys. End with concise audit metadata only when useful.

Write this complete report to the requested `.md` file, or `airport-recommendations.md` when no path is given. Before reporting, parse the JSON, confirm every record key equals its `icao` value, check that each object has exactly the current target fields and types, reject duplicate keys, compare the fragment with the current dataset to prevent duplicate-airport additions, verify that every proposed field traces to an exact extracted value or a disclosed transformation/decision, and verify every Markdown link resolves.

Do not create external issues, branches, commits, or pull requests unless the user separately asks for delivery.
