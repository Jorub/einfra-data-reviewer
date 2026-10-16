# eINFRA data reviewer for RStudio

A small, read-only CSV/NetCDF validation and remote reasoning prototype. No local LLM or GPU is needed. Uses the eINFRA OpenAI-compatible API at `https://llm.ai.e-infra.cz/v1`.

## Start in RStudio / JupyterHub

1. Clone or upload this repository into persistent storage and open the `.Rproj`.
2. Run `source("setup.R")`. It installs only missing packages (`curl`, `jsonlite`, `getPass`, `ncdf4`) and verifies they are available; installed packages are not updated.
3. Open `start_here.R` and run the synthetic offline example section by section.
4. Run `set_api_key()` interactively: the hidden prompt keeps the key in process memory only. The key is never saved by this project. Do not paste it into code, chat, notebooks, or console commands.
5. `list_models()` checks server network access and authentication. Choose an available model; aliases can change.
6. Inspect `prepare_review(checks)` and explicitly pass that exact preview to `review_checks(..., send = TRUE, report_dir = chosen_path)`. Only the displayed validation summary is submitted; no raw CSV, file path, actual column names or source code is included by the built-in checker.
7. Read local reports and run `clear_api_key()` when finished.

## Scope and limits

Current checks: required columns, nonempty table, duplicate column names, finite numeric values, caller-defined ranges and unique keys. Ranges are explicit scientific contracts, not model guesses. NetCDF validation is described below. Download-manifest checksums, processing comparisons, and code review are future extensions. It does not execute RDS files or model-generated commands and never modifies inputs. PASS is not proof of correct science. Model output is advice and cannot override failed numerical checks. No automated remediation or agent loop is provided.

The API models cannot inspect server files, browse or run tools through this client. Current availability and container outbound network access must be tested in your own environment. There has been no live-key test from your server.

## Credential and report handling

The public repository contains no real key or project data. Credentials are held in a private R environment, never in request bodies or saved reports. HTTP error bodies and low-level connection details are suppressed. Workspace/history saving is disabled in the supplied RStudio project; do not manually save the R session while a key is loaded. Any code running under your account can potentially inspect R memory: this is not a credential vault. Use your own account/key in a trusted container.

Only approved summary text is sent remotely. Reports may still be sensitive and must remain in private persistent storage; `reports/`, `data/`, `private/`, history and common credential files are Git-ignored. Git-ignore is a convenience, not a guarantee: inspect staged changes before publishing. Custom callers can supply arbitrary check details, so always review the outgoing preview. Do not enable HTTP debugging.

API calls are bounded to 16 kB summary text and a chosen completion budget. Usage and finish reason are saved. Failed or truncated calls are explicitly incomplete; no automatic retries. Reports retain deterministic results separately from model interpretation.

## Tests

`Rscript tests/test_offline.R` and `Rscript tests/test_netcdf.R`

Uses synthetic data and a clearly fake credential sentinel; no network or real secrets.

## Provenance

Prepared with Codex assistance, adapting the design of the user's local eINFRA offload client. No credentials were read or copied. Official service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/chat-ai

## User-supplied paths

Select a CSV with `file.choose()` or pass its path to `check_csv(path = ...)`. Use `check_files(paths = ...)` for multiple CSVs sharing a validation contract. Supply `report_dir` explicitly when calling the API reviewer. No machine-specific data directory is embedded in the program. Input paths remain local and are omitted from built-in review summaries. Keep reports outside the public Git checkout when possible. The relative `source("R/reviewer.R")` identifies project code, not a data location.

## NetCDF temperature baseline

Open `netcdf_example.R` after pulling the latest repository. Select the input file at runtime; no server path is embedded in code. The example contract is monthly Celsius temperature, 0.25-degree global grid, January 2000 through December 2019 (240 records). Adjust expectations only deliberately. Set `variable` explicitly if more than one data variable matches the coordinate dimensions. This initial NetCDF checker is specialized for rectilinear temperature grids.

Checks cover degree coordinate units, regular spacing, monotonicity, conventional longitude/latitude ranges, global grid extent, Celsius units, time count/order and exact monthly coverage. Time decoding supports seconds/minutes/hours/days since a date in standard/Gregorian/proleptic Gregorian calendars; unsupported calendars, timezone offsets, or origins are reported NOT_CHECKED. Monthly sampling does not prove monthly-mean semantics. A reference mask is required to verify global land coverage; it is not inferred from the missing fraction. No physical temperature threshold is invented.

All months are scanned one slice at a time using ncdf4's missing-value and packing decoding. Local diagnostics retain each slice's missing/nonfinite counts and unweighted spatial quantiles. The model preview includes selected variable metadata, expected contract, diagnostic counts, overall extremes and at most eight representative slice summaries. These are not area-weighted climate means and are not a reference-product comparison. Paths, global history attributes, raw grids, and full command output are excluded. Metadata may still be sensitive: inspect the preview.

When installed, `ncdump -k` independently queries file format and `cdo -s ntime` independently counts time records. Commands read the input and have no output-file arguments. Full tool output is retained only in the local `local_tool_results` attribute, never automatically sent to the API. Unavailable/failed tools produce NOT_CHECKED rather than implying the input is invalid. The external commands have no enforced timeout in this prototype. Both tools still require validation in the user's server environment.

`review_evidence`, `local_slice_statistics`, and `local_tool_results` are attributes of the returned checks. Only `review_evidence` enters `prepare_review()`. Optionally save the full checks object with `saveRDS()` in private report storage. No model call is needed to run deterministic checks.

NetCDF tests create small synthetic fixtures in temporary storage: clean baseline, wrong units, missing/duplicate months, wrong resolution, unsupported calendar, and all-missing slice. They verify input checksums are unchanged and outgoing payloads exclude input paths. The real server file has not been accessed or tested by the developer.

## Processing history and full headers

NetCDF checks now query `ncdump -h` when available. The complete header stays in `attr(checks, "local_tool_results")$ncdump_header$output`, which may contain private metadata and must be kept local. The model receives the global `history` attribute, read directly through ncdf4, in `review_evidence$processing_history`. This is the same attribute shown near the bottom of `ncdump -h`; raw full headers are not submitted.

Common credential assignments, bearer tokens, URLs, identities and paths are redacted before the history enters the preview. Redaction is best-effort and cannot establish that arbitrary metadata is free of secrets. Inspect the outgoing preview and opt out with `include_history = FALSE` if needed. History is capped at 6,000 characters after redaction; truncation is explicitly reported. Operation names and numerical arguments such as CDO conversion constants remain visible for diagnostic review. History describes recorded steps, not independent proof of correctness.

After upgrading, rerun `source("R/reviewer.R")`, `source("R/netcdf.R")`, and `check_netcdf(...)` to rebuild `checks`; an existing object does not acquire history automatically. Recreate the preview before any API submission. This changes the review from blind numerical diagnosis to history-informed diagnosis; keep earlier reports separate when comparing the two.

## Scientific review prompt and batch-audit planning

The `scientific-triage-v2` prompt requests independent plausibility assessment, prioritised actionable findings, explicit confidence levels and discriminating next checks. It distinguishes a wrong operation recorded in history from proof that it fully explains the current file. Routine PASS entries are compacted to their check names; failures, coverage gaps and scientific evidence remain. Existing previews must be rebuilt after reloading `R/reviewer.R`.

A server-wide weekend runner is **not ready yet**. The current checker remains a specialised monthly Celsius pilot. See `docs/batch-review-design.md` for its audited limitations and the proposed variable contracts, persistent per-file checkpoints, local flagged-filename lists, API budgets and incomplete-review handling. Do not use the pilot's default scientific expectations as a contract for unrelated variables.

## Inventory the sim tree before configuring the weekend audit

Run `inventory_sim.R` section by section in RStudio. Enter the data root and a private report directory outside the root at the prompts. No directory is hard-coded. This first stage reads metadata only, makes no API calls, and does not judge scientific correctness. It records every NetCDF data-variable candidate (not only the first), identifies common bounds/grid-mapping auxiliary variables, and records unreadable files without abandoning the rest of the inventory.

The discovery step accepts `.nc`, `.nc4`, and `.cdf`, skips hidden directories/files (including `.ipynb_checkpoints`) and symlinks, and records those excluded entries locally. CSV/tabular and compressed NetCDF files are not included. Folder names provide unverified hints for the environmental families under sim; filename suffixes provide unverified daily/monthly/annual hints. Neither is a scientific contract.

Local outputs are `inventory.csv` (contains paths and metadata), `inventory-summary.csv` (family/stage/frequency/role/status counts, without paths), and an RDS progress checkpoint. Summary counts are variable records, not necessarily distinct files. The current inventory can be rerun but does not yet resume from its checkpoint. Review the summary before sharing it; keep detailed reports private.

Test: `Rscript tests/test_inventory.R`. Next use the inventory to establish variable and temporal/grid contracts before enabling a full numerical scan and LLM batch review. The temperature checker still must not be applied unchanged to all environmental variables.

## Filename-aware single-file review and short CSV

The single-file pilot now sends the basename and parsed `SOURCE_VARIABLE_UNIT_SCALE_START_END_SPATIALRESOLUTION_TEMPORALRESOLUTION` fields in the explicitly approved preview. No input directory is submitted. Do not use filenames containing secrets. Parsing requires eight nonempty fields and valid YYYYMM endpoints; unrecognized patterns require review rather than guessed repairs. The initial monthly-temperature checker compares the filename's units, variable, period and known resolution code against the caller contract and observed file. Other resolution codes, aliases and nonmonthly validation still need extension before server-wide use.

Monthly scans flag missing/duplicate months and incomplete represented years, including partial boundary years, while distinguishing coverage warnings from deterministic errors. No comparisons of end dates between separate frequency products are made.

The `scientific-triage-v3-json` prompt asks for a validated JSON object containing verdict, short reason, and detailed Markdown. R writes `review.md` for humans, `review-response.json` for the model response, `summary.csv` with exactly `filename,result,reason`, and `review_index.csv` with variable, check status, LLM status and report path. These are per-run single-file outputs; an all-file aggregation runner is not implemented yet. The original checks and local diagnostics remain alongside them. A PASS means no issue identified within supplied checks, not scientific certification.

Deterministic FAIL/WARN cannot be overridden by model PASS. A failed/truncated/invalid API response records its LLM status and produces INCOMPLETE if there were no deterministic flags; an already known file problem remains FAIL with the LLM failure also noted. Therefore always keep the index as well as the short summary. JSON with an invalid schema is not silently reinterpreted as prose. Error messages identify the run directory; no guessed repairs or automatic retries occur. The default completion budget is now 8192 tokens after the observed reasoning-only truncation at 4096.

After pulling, reload both modules and rerun the monthly example to rebuild filename-aware diagnostics and preview. Reloading `R/reviewer.R` clears the in-memory key, so enter it again with `set_api_key()` before submitting. Capture `run <- review_checks(...)` and open `file.path(run, "summary.csv")` and `file.path(run, "review.md")`.

Tests: `Rscript tests/test_review_output.R` uses mock API responses (no network) to verify JSON validation, CSV quoting, model/deterministic precedence, successful detailed reports and incomplete/error reporting. Synthetic NetCDF tests verify malformed names, time gaps, filename evidence and path exclusion; they do not establish how a real model will diagnose the server file.
