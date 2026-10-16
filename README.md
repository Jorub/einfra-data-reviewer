# eINFRA data reviewer for RStudio

Read-only CSV/NetCDF checks and optional remote LLM review. No local model or GPU is needed. Uses `https://llm.ai.e-infra.cz/v1`.

## Setup and entry scripts

Clone/upload this repository into persistent storage and open `einfra-data-reviewer.Rproj`. Run `source("setup.R")`: only missing `curl`, `jsonlite`, `getPass`, `ncdf4` and `CFtime` packages are installed; installed versions are not updated.

All entry scripts put user settings immediately below their source statements. Set paths locally; do not commit private configuration. There are no file pickers or path prompts. Only the API key uses a hidden prompt.

- `netcdf_example.R`: one file; inspect checks/preview, then optionally submit.
- `three_file_example.R`: three selected files, processed sequentially; a file error does not stop the next.
- `inventory_sim.R`: local metadata inventory of a directory, no API calls or value scans.
- `llm_example.R`: independent editable text prompt and Markdown response.
- `start_here.R`: synthetic CSV example with deliberate errors.

`send_to_api = FALSE` is the default. Inspect the preview before explicitly approving the selected payloads with TRUE. Sources load once; the three-file example asks for the key once before looping. It can clear the key after the batch. A full rerun rescans and creates a new report folder: retry-only/resume support is not implemented yet.

## Filename-derived expectations

The current common NetCDF checker parses:

`DATASET_VARIABLE_UNIT_SCALE_START_END_SPATIALRESOLUTION_TEMPORALRESOLUTION.nc`

Do not manually repeat units, dates or frequency in `file_specs`. Example:

```r
file_specs <- list(
  list(path = "<first file>"),
  list(path = "<second file>"),
  list(path = "<third file>")
)
```

Eight nonempty fields and valid YYYYMM endpoints are required. Malformed dates are flagged, not silently repaired. Kelvin and Celsius are both supported; the filename's units are checked against the NetCDF attribute. Known Celsius/Kelvin spelling variants are normalized, but arbitrary physical unit conversions or variable-name aliases are not guessed. A variable can be selected explicitly if needed. All project files must have a 0.25-degree grid and the established `025` filename code. Both the filename and actual coordinate spacing are checked against this project requirement; neither is allowed to redefine it.

A matching NetCDF variable is selected by filename where possible. Multiple candidates are not silently reduced to the first. Regular rectilinear longitude/latitude/time dimensions are supported. Nonsingleton extra dimensions, unsupported grids or time encodings remain visible as blocking coverage gaps, not clean passes. The numerical scan reads all time slices one at a time with ncdf4 fill-value and packing decoding; quantiles are unweighted spatial summaries, not area-weighted climate means. This is still a potentially large I/O job for daily/hourly files.

## Variable-family review policies

`R/netcdf_families.R` supplies separate review requirements for `evap`, `other`, `precip`, `runoff`, `snow`, `soilmoisture` and `temperature`. Family and raw/processed stage are inferred from folder names when available. Here `raw` means already preprocessed/harmonised to common units and the 0.25-degree grid, not untouched downloaded data. `processed` generally means additional time/spatial subsets; an optional `family` selector is allowed. These hints do not override filename/content contradictions. Regional scale names do not impose global extent.

The family functions guide scientific LLM review; they are not a comprehensive deterministic validator for every environmental quantity:

- Temperature: unit/offset direction and Tmin/Tmax aggregation semantics.
- Precipitation: rate versus accumulation and correct duration/sum/mean.
- Evaporation: actual/potential quantity, rate/accumulation and source sign convention.
- Runoff: depth/rate/discharge and surface/subsurface/total quantity.
- Snow: depth, snow-water equivalent, snowfall flux or cover fraction; stocks versus fluxes.
- Soil moisture: volumetric fraction versus mass/area and layer/depth integration.
- Other: actual quantity identification, including radiation, humidity, pressure, heat fluxes, groundwater and LAI.

No universal plausible-value thresholds are invented. The LLM must independently assess physical plausibility and processing evidence. These policies need representative server-side pilots for each family before a large run.

## Temporal and spatial coverage policy

CFtime handles CF calendars, including Gregorian, no-leap and 360-day. Filename coverage is checked independently for hourly, daily, monthly and annual/yearly products. CF time bounds, where readable, supply interval midpoints for period labels. Missing or duplicate periods inside the named interval are flagged. Differences in end dates between separate frequency products are not compared.

Monthly/daily/hourly products may legitimately start or end partway through a year. A monthly file ending in August is valid if every declared month is present. Annual/yearly filename endpoints must indicate full calendar years; partial annual intervals are flagged. Annual time bounds are checked when present. An annual timestamp alone cannot prove every source month was included; processing provenance must establish the aggregation, and reference-source checks may still be necessary.

Longitude/latitude order, degree units, geographic ranges and resolution are checked. Latitude domain is descriptive: coverage limited to 60S–60N and inclusion/exclusion of Antarctica are both allowed. `land` and `global` imply a full longitude span; other scale labels are treated as regional domains without guessing region boundaries.

- `global`: requires finite data over land and ocean within its represented coordinate domain; missing cells are flagged.
- `land`: approximately two-thirds of grid cells should be missing. The initial broad screening interval is **50–85% missing**, adjustable via `land_missing_range`; outside this interval gives a review flag, not proof of a bad mask.

These are grid-cell fractions, not area-weighted land fractions. Missingness does not independently establish a correct land mask. An independent mask comparison is not performed automatically.

## Provenance and processing history

Unclear essential source/aggregation provenance is a review failure, even when numerical checks pass. For monthly Tmin, for example, distinguish mean daily minima from the lowest temperature of the month. The original source may already have the named monthly/daily/annual frequency; a local aggregation step is not mandatory. Final values must have the temporal interpretation and units represented by the filename. Missing a local aggregation command is not automatically an error when the source already has the required frequency. However, a missing or empty NetCDF `history` attribute is a mandatory deterministic provenance FAIL, even if source metadata or external notes exist. Those can clarify semantics but do not override the required history record. A metadata-only units edit does not prove the numeric values required conversion. Optional `provenance_notes` may supply actual documentation; never invent it.

Selected source attributes, cell_methods and redacted global history enter the approved model preview. `ncdump -k`, `ncdump -h` and `cdo -s ntime` are queried when available, with 120-second command timeouts. Full command output stays in the local diagnostic object. History documents recorded operations, not proof that those operations fully explain the current file. History is capped at 6,000 characters with truncation reported.

Common credential patterns, paths, identities and URLs in history/provenance metadata are redacted. Redaction is best-effort: always inspect the preview. The basename itself is intentionally sent because it encodes expectations. Do not use filenames containing secrets. Do not submit raw full headers, raw arrays or private paths. Tools missing/failing are NOT_CHECKED, not automatically a data failure.

## Reports and verdicts

The model returns validated JSON with `verdict`, a short `reason`, and detailed `report_markdown`. R writes the human-readable report and CSVs; it does not extract verdicts from arbitrary prose. Local per-call files include:

- `summary.csv`: exactly `filename,result,reason`.
- `review_index.csv`: filename, variable, checks/LLM status and report path.
- `review.md`: detailed diagnosis and next actions.
- `metadata.json`: model, reasoning setting, usage, completion and finish reason.
- `checks.csv`, `local-diagnostics.rds`, `submitted-summary.json` and the selected response content.

Sequential batches also write a master `summary.csv`, `review_index.csv`, and `flagged_files.csv`, checkpointed after every file. All requested inputs are listed, including pending/unreadable files. No automatic retries or parallel calls. An unreadable file, API rejection, token limit or invalid response is recorded and the next file is processed. A killed container or lost output disk cannot be solved by per-file error handling; choose persistent writable storage.

PASS means no issue identified within the performed checks, not scientific certification. FAIL means a known data/naming/coverage or provenance flag. INCOMPLETE means essential checks or meaningful LLM assessment could not finish. A deterministic FAIL/WARN cannot be overridden by model PASS. A known file failure remains FAIL even when its LLM call fails; the separate LLM status preserves that distinction. Unsupported essential checks prevent an overall PASS.

## Keys and API controls

Use your own key through `set_api_key()`; `list_models()` checks authentication and availability. The key is held in memory, not written to code, prompts, metadata or reports. Sourcing `R/reviewer.R` again resets that environment; restarting R also requires re-entry. Workspace/history saving is disabled in the project. Do not manually save an authenticated R workspace. Other code under the same account can inspect memory: this is not a credential vault.

`reasoning_effort = NULL` omits the field and uses the provider's configured default; it does not disable reasoning. Medium was rejected for thinker in our live pilot. Explicit low/medium/high settings remain model-dependent and should only be used after verification. Completion budgets include internal reasoning where applicable. Default max_tokens is 8192; review summaries have a configurable 64 kB request guard (`max_input_bytes`); this is a byte limit, not a token/context measurement. Invalid/truncated responses remain incomplete. HTTP diagnostics whitelist categories, never arbitrary provider bodies/headers. No automatic retries or silent parameter substitutions.

## Direct LLM text example

`llm_example.R` exposes model/output settings and editable role, context, task, evidence, constraints, output format and success criteria. Optional explicit UTF-8 text files are included verbatim after preview; there is no automatic content redaction or directory discovery for this separate text client. References to paths/URLs do not supply their contents. Calls have no browsing, tool execution or memory.

Each successful call saves a unique folder containing `prompt.md`, `response.md` and `metadata.json`, and returns the text in R. Truncated text is `response.partial.md`. Never execute model output automatically.

## Tests and next steps

```r
source("tests/test_offline.R")
source("tests/test_netcdf.R")
source("tests/test_inventory.R")
source("tests/test_review_output.R")
source("tests/test_llm.R")
source("tests/test_batch.R")
```

Tests use synthetic files and mocked API responses, never real credentials or network inference. They cover filename-derived contracts, units, missing/duplicate periods, CF calendars, annual completeness, monthly boundary acceptance, provenance, coverage screens, unchanged inputs, response validation and per-file errors. These do not prove model diagnostic competence on every family. Test representative real files next; automatic directory-wide review, checkpoint resume, arbitrary multi-level grids, reference-product comparisons and download-manifest checksum checks are not implemented yet.

## Public repository hygiene and style

Only generic code, instructions and synthetic tests belong here. Keep data and reports outside the checkout; common credentials, data/report folders and R session files are Git-ignored. Inspect staged changes before publishing; Git-ignore is not a security guarantee. Use spaces before and after `=` in R assignments, defaults and named arguments. AI-assisted code is reviewed and tested; no keys were read or copied into this repository.

Service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/ai-api
CF calendars: https://cran.r-project.org/package=CFtime

### Larger filename/family review payloads

The original 16 kB client limit was too small for some metadata/history payloads. NetCDF reviewer and batch defaults now use `max_input_bytes = 64000L`, also exposed in the entry scripts. No evidence is silently removed to fit. Rejected requests report actual/configured bytes before any API call. Input size is recorded in successful request metadata. Inspect a large preview and respect the chosen model's actual context limit before increasing this guard further. This input setting is separate from `max_tokens`, the completion/reasoning budget.

### Required history attribute

`history_provenance` deterministically fails when the global NetCDF history attribute is missing or whitespace-only. It is checked through ncdf4 even when ncdump is unavailable. `include_history = FALSE` withholds history text from the API but does not disable the local presence check; the preview distinguishes withheld from absent history. Presence alone does not establish adequate provenance. No processing steps should be fabricated to fill a missing attribute.
