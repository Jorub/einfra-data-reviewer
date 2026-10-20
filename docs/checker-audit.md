# Checker audit — 2026-10-20

Scope: implementation review and offline synthetic checks following a real batch in which CFtime was absent and model attempts exhausted 8192 completion tokens. No real server data, private credentials or live inference were accessed.

## Defects corrected

1. Missing scan prerequisites: required calendar/JSON packages were not checked before value scanning. New direct/checker scan entrypoints check ncdf4, CFtime and jsonlite; the supported batch scanner fails before creating a batch when a prerequisite is missing. Existing saved scans are not repaired by package installation.
2. False annual-boundary failures: CFtime can represent midnight with a date only. The checker compared that to a full timestamp string and wrongly rejected complete annual bounds. The comparison now normalises date-only midnight; non-midnight or partial-year intervals are still tested against full-year requirements.
3. Fractional/string token budgets could pass the client guard and lead to avoidable request rejection. Completion budgets must now be finite integers in the supported client range; provider model limits still apply.

## Evidence and visibility improvements

- NetCDF storage type is exported alongside scale/offset, so diagnoses need not assume signed-short storage without evidence.
- The saved-review stage prints its effective model and max_tokens and records review-settings.json. Tests confirm an explicit 16384 setting reaches mocked requests and metadata unchanged.

## What was exercised

- Annual Gregorian, no-leap and 360-day coverage; genuine full-year bounds, missing/duplicate years and partial-year endpoints/intervals.
- Monthly pressure, specific/relative humidity, shortwave/longwave fluxes, signed wind components, wind speed and a validly named albedo fixture. Negative components/net radiation are not automatically treated as invalid.
- Packed short data with fill values, scale_factor and add_offset: decoded extrema/mean and stored type are correct, and source checksums remain unchanged.
- Existing suites cover monthly boundary acceptance, daily/hourly missing periods, coordinate ordering/resolution, masks/limited latitude policies, statistics, redaction, private setup, saved reviews, API failure continuation and retry accounting.

## Findings that are not implementation defects

- The observed 8192 limit matches the runner's current default, not an API reduction. Timeout and token defaults are unchanged by this audit. Configure a different budget explicitly at the top of the runner and verify the printed effective setting.
- Malformed filenames still stop contents inspection by the agreed policy. Missing history still fails by the project's provenance policy.
- Existing caches with missing time checks need a new scan (or an explicitly implemented time-only refresh); this patch does not silently replace them or pretend checks were performed.
- Radiation identity/net-versus-downwelling, negative ET treatment and source temporal semantics require actual provenance and scientific review. Generic numerical tests do not establish those properties. No new physical thresholds or correction rules were introduced.

Passing synthetic tests does not establish that every NetCDF encoding or model diagnosis is correct. Unsupported real time encodings remain visible as NOT_CHECKED rather than guessed. Inspect actual scan checks before resubmitting the new project batch.
