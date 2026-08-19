# Performance surfaces

## Startup and module loading

- Distinguish PowerShell process startup from script module loading.
- Check repeated file reads, scriptblock creation, configuration/profile discovery, command detection, and eager optional initialization.
- Preserve `LOFIATC_TEST_MODE` and avoid adding work at dot-source time.

## Data and selection

- Inspect repeated CSV imports, linear scans inside loops, repeated property enumeration, unnecessary pipeline materialization, and large JSON conversions.
- Prefer a lookup built once per operation when repeated ICAO/channel access dominates.
- Preserve canonical ordering and user-visible selection order.

## Map and weather

- Measure airport-data load, marker construction, JSON serialization, HTML generation, browser launch, NOAA batching, VATSIM fallback, and map request handling separately.
- Preserve `-NoWeather` as a fast path.
- Avoid slow optional work in the persistent map request loop.

## Network and caches

- Attribute elapsed time to each endpoint and fallback. Keep every request bounded.
- Define freshness and invalidation before caching. Never trade speed for corrupted or silently stale user data.
- Avoid duplicate requests and prefer existing batched endpoints.

## Players, webcam, and OCR

- Separate resolver time, executable discovery, process creation, stream readiness, ffmpeg capture, and OCR processing.
- Optimize managed operations without hiding external-player latency or leaving orphan processes.
- Test repeated channel changes and long-lived persistent sessions for resource growth.

## Reporting

Report scenario, environment, sample count, baseline median, candidate median, absolute change, percentage change, functional checks, and limitations. Do not claim a general speedup from a single uncontrolled run.
