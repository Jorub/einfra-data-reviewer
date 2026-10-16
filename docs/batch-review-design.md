# From the temperature pilot to a server audit

Status: design and code audit, not an implemented weekend batch runner.

## Current limitations established by code inspection

`check_netcdf()` currently defaults to Celsius, 0.25 degrees, monthly 2000–2019 and global extent. It explicitly rejects non-Celsius contracts. It assumes one uniquely identifiable 1-D longitude, latitude and time dimension, a single selected data variable and no nonsingleton extra dimensions. The date comparison is monthly and only supports a limited set of Gregorian CF time encodings. Global extents are unsuitable for regional/subset files. Structural validity is not proof of land-mask correctness or monthly-mean semantics.

It scans every time slice and decodes fill values and packing with ncdf4. This provides useful metadata and numerical summaries across many variables but does not supply scientific meaning automatically. It does not currently count values outside configured physical ranges, compare spatial masks, track anomalous time-to-time jumps, or compare reference products. Its per-slice read can still be large on high-resolution grids. External commands lack explicit timeouts. Exceptions currently stop the single-file run. It has no batch inventory, checkpoint/resume, disk preflight, job budget or machine-readable model verdict. These are blockers to an unattended server-wide run.

## Proposed stages

1. Inventory only: explicit root paths, recursive option, `.nc`/`.nc4` selection, no symlink traversal by default. Record filenames, size, mtime and all data-variable metadata locally. Exclude output directory. Classify coordinate/bounds/grid-mapping variables separately; never silently select the first variable. Unsupported grids/variables remain in the inventory as requiring review.
2. Contracts: a local manifest maps each file/variable to approved expectations (quantity, units, time frequency and coverage, grid/extent, mask and optional bounds). No universal Celsius or 2000–2019 defaults. Filename hints are suggestions, not source truth. Unknown profiles trigger REVIEW_NEEDED rather than PASS.
3. Deterministic scan: generic format/coordinate/time/packing checks plus quantity-specific checks. Temperature bounds must be explicit and unit-aware. Precipitation/evaporation require distinction between rate and accumulation, interval length and sign convention; radiation may be flux or accumulated energy. Generic finite-value checks remain separate from scientific plausibility. Unsupported calendars/grids should be SKIPPED/NOT_CHECKED with an explicit reason, never coerced into a false result. Scan in bounded chunks, log scope, and distinguish sampling from full coverage.
4. Optional LLM diagnosis: selected metadata, numerical diagnostics and redacted processing history, with approved submission policy and bounded per-file budget. Do not send full paths, raw arrays or raw full headers. Use one chosen model sequentially. No automatic repair or model-generated tool execution. For broad detection, review every supported file within the approved job budget, not just files with deterministic failures: the pilot showed a numerically implausible field can otherwise pass structural checks.
5. Local triage: rows keyed by file and variable, with filename/path, profile, deterministic status/reasons, diagnostic scope, model status/findings, severity/confidence, processing time and report link. A filename goes in `flagged_files.csv` if any variable fails or is flagged by the model. Keep `incomplete_files.csv` for unreadable, unsupported, skipped, unconfigured and API-failed files. NO_ISSUE_IDENTIFIED is not a scientific certification.

## Reliability required before weekend deployment

Write a per-file checkpoint after each completed stage; resume must check file size/mtime plus contract, checker and prompt versions, and ideally a checksum where feasible. Changed files or settings require rescanning. An API failure must not discard deterministic results or be recorded as a clean review. Support retry of incomplete reviews without rescanning data; avoid unbounded automatic retries. Record UTC timing, usage, requested/returned model and finish reason. Enforce total token/request budget, explicit tool timeouts, max input size and available disk space. Keep reports outside the public checkout. The API key stays in the running process; a restarted R session requires re-entry.

First pilot on a small, representative set with clean and deliberately faulty examples of each included variable family. Then confirm scope, resource use and persistent RStudio/JupyterHub execution before launching the whole inventory. A browser session alone does not establish that a weekend job survives container shutdown.

## Inputs still to agree

Variable families and conventions; raw versus processed scope; file frequencies and calendars; expected grids; approximate file count/size; approved diagnostic thresholds; and whether unknown contracts are reviewed manually or inferred as explicitly unverified suggestions. No server root paths should be committed to this public repository.
