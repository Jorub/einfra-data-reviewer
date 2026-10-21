# eINFRA data reviewer for RStudio

Read-only NetCDF diagnostics and optional eINFRA LLM review. Scan files once, save the evidence, and run model reviews later without reopening the data. No local model or GPU is required.

## Setup

Open `einfra-data-reviewer.Rproj` in RStudio and run from the repository root:

```r
source("setup.R")
```

Setup creates required directories and installs only missing `curl`, `jsonlite`, `ncdf4` and `CFtime` packages. Existing dependencies and private configuration are not overwritten. Review external CDO/ncdump availability separately; their absence is recorded. Setup never reads your API key.

## Structure

```text
source/              reusable functions
run_experiments/     scripts to configure and execute from the project root
config/              input-file table, path template and credential template
output/              ignored local outputs, or use external persistent storage
tests/               synthetic and mocked offline tests
docs/                review policy, migration notes and development history
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding and contribution rules and [AGENTS.md](AGENTS.md) for agent instructions.

## Paths and input files

Edit `config/data_file_paths.csv` with one row per file:

```csv
data_file_path,family
temperature/raw/example.nc,temperature
precip/processed/example.nc,precip
```

`data_file_path` is required; `family` is optional when inference is sufficient. Optional `provenance_notes` supplies actual source documentation. Relative file paths resolve against `data_root`, not the CSV location. Absolute paths are also supported. The checker still derives scientific expectations from each filename, not the example names above. A preflight checks every resolved input path before starting a batch; any missing files stop the scan with the complete list of missing full paths.

Set `data_root` and `output_dir` near the top of the runner. To use machine-specific overrides, copy `config/paths.local.example.R` to ignored `config/paths.local.R`. That file contains paths only, never credentials. Relative output/table paths resolve from the repository root. Shared relative paths may be tracked; review input tables before publishing them.

## Check file paths first

For a quick standalone check, open `run_experiments/check_file_paths.R`, set `data_file_paths` and `data_root` near the top, then run from the project root. It saves **all missing full paths** to `output_dir/missing_files.csv`, prints the complete list, then raises a short error if any are absent. This avoids R/RStudio truncation of long error messages. `missing_files` retains the character-vector list in the R session. The final success message rechecks the paths, so running that line separately after an error cannot falsely report that all inputs exist. It does not open NetCDF contents, create a scan batch, load credentials or call a model. Existing directories are rejected as file inputs; file presence does not prove valid data.

The sourced helper `missing_input_files(file_specs)` returns only missing paths without throwing. `check_input_files(file_specs, report_dir = output_dir)` saves and prints the full list before raising an error. The CSV is regenerated on every check, with zero rows when all files exist, to clear any stale report. All scan runners automatically apply that check before creating a new scan batch or reading values. Correct every listed path or mount/access issue, then rerun. The check reflects availability from the current R session; a file removed or becoming unreadable later is still recorded as a per-file scan error, allowing other inputs to continue. Existing cached LLM reviews are unaffected and do not require source paths to exist.

## 1. Scan and save (no API key required)

Choose a runner, edit its configuration, then run it from the top:

- `run_experiments/scan_files.R`: read `config/data_file_paths.csv`.
- `run_experiments/scan_file.R`: one explicitly configured file.
- `run_experiments/scan_temperature.R`: discover the temperature folder, including raw/processed subfolders; excludes hidden entries and symlinks.

Scans read all time layers sequentially and checkpoint a `scan-<id>` folder with one random identifier after each file. Daily/hourly files may take substantial time. No model is called during this stage. New scans check ncdf4, CFtime and jsonlite before starting; missing prerequisites stop with setup instructions instead of completing an expensive scan without time checks.

Each batch includes **`data_overview.csv`**, one row per requested input once preflight passes, including files that subsequently become unreadable or disappear. Older saved batches may already contain missing-file rows. It contains the table path and resolved input path, variable, units, mean/min/max, grid endpoints/extents/spacing/counts, layer count, time coverage and missing-period count. `recorded_operations` retains the included redacted history (possibly multiline), without inferring a complete recipe. File size/mtime, scan time and scanner version are included; exact scanner-file checksums are stored in each `scan-record.json`. Source size/mtime before and after the scan are recorded; they are not content hashes.

Detailed per-file outputs remain:

- `checks.csv`, `local-diagnostics.rds`, `review-preview.json`.
- `file-summary.csv`, `layer-statistics.csv`, `time-period-issues.csv` (complete missing/unexpected/duplicate period lists).
- `file-metadata.json` (including actual NetCDF storage type and packing attributes), `scan-record.json`, `recorded-conversions.csv`, `conversion-notes.txt`.

An unsupported or malformed file may have fewer diagnostics; missing values do not imply a clean check. Overview means are unweighted finite cell-time averages, not area-weighted climate means. See [review policy](docs/review-policy.md) for scientific conventions and limitations.

## 2. Review saved scans

Open `run_experiments/review_scans.R`. Set `scan_dir` to the saved `scan-<id>` directory containing `review_index.csv`. This also accepts old no-API `batch-*` folders without renaming them; new descendants adopt that saved label. It uses cached checks, without opening source files or verifying whether they have changed. Use a fresh scan after changing input data or checker logic; old caches cannot acquire new statistics by asking the model again.

With `send_to_api = FALSE`, the script saves updated previews without calling the service. Inspect them, then explicitly enable submission with TRUE. Selecting TRUE approves the built-in basename, selected metadata, diagnostics and redacted-history payloads for the selected cached files; raw arrays and input paths are not automatically submitted. Redaction is best-effort, not a privacy guarantee. Do not submit confidential filenames or notes.

The model/effort/token/input-size settings are visible at the top. Each saved-scan review prints its effective model/budget and saves review-settings.json before any calls, so an edited but unsourced runner cannot be mistaken for the applied configuration. Existing budgets remain unchanged: default 8192 completion tokens, 64 kB input guard, 180-second API timeout and 20-second connection timeout. Completion budgets can include reasoning. `reasoning_effort = NULL` omits that field and uses the provider default; explicit support is model-dependent. Timeout/resource changes and parallel execution are separate future choices, not bundled into the restructure.

Reviews reuse the scan identifier: `scan-abc123` produces `review-abc123`. Repeated reviews use `review-abc123-02`, `-03`, etc.; original scans/reviews remain unchanged. Each top-level run saves run-lineage.json linking its scan identifier and exact parent folder. Already completed reviews are retained without repeating calls. Per-file errors do not stop the next file.

### Credentials

Setup creates a placeholder file outside the repository at `~/.config/einfra-data-reviewer/credentials.R`. Edit that private file to define `api_key`. Where supported it is created with account-only permissions. An existing file is never overwritten. You can set `credentials_file` in API runners to another private location.

Keys are read only when API calls are enabled, held in R memory and never intentionally included in reports or logs. There are no hidden interactive prompts. This is a plain-text secret, not a vault: protect backups and account access. Do not print or commit it, and do not save authenticated R workspaces. Sourcing `source/reviewer.R` again clears its key environment. Keys should be cleared with `clear_api_key()` when finished.

### Error overview and detailed review

- **`summary.csv`** remains exactly `filename,result,reason`, listing every input.
- **`flagged_files.csv`** lists non-PASS rows with full identity/status/report context.
- `review_index.csv` distinguishes scan failures, model completion, TOKEN_LIMIT and API_ERROR, including input paths when available.
- Detailed attempts retain `review.md`, validated response JSON, submitted evidence and metadata with model, usage, token budget and finish reason.

The deterministic `data_overview.csv` is copied forward unchanged when present; model conclusions do not modify statistics. FAIL includes strict provenance/naming flags, not only incorrect numerical values. A known deterministic failure remains FAIL even if the LLM is unfinished. Scan-only summary rows cannot constitute a completed LLM review.

Connection errors now retain fixed safe categories (TIMEOUT, DNS_ERROR, CONNECT_ERROR, TLS_ERROR, TRANSFER_ERROR or UNKNOWN_TRANSPORT_ERROR) without logging raw curl messages. Direct/grouped model attempts record elapsed seconds and API_ERROR reliably. Older grouped attempts may show NOT_COMPLETED alongside an "API request failed" reason because of a status-saving bug; their suppressed messages cannot establish the original transport cause. The legacy reviewer retains its 180-second request timeout; grouped runners expose the separately configured timeout described below.

## Five-category review pilot

For the **complete paper-data batch**, use `run_experiments/review_grouped_scans.R`. Set `scan_dir` to the saved scan folder for the paper input table, leave `input_rows = NULL` to include every row, and enable `send_to_api = TRUE` after inspecting the evidence. This uses the same five-category prompt, 20,000-token budget and per-file error isolation as the pilot. Missing/unreadable/invalid inputs remain visible rather than silently excluded. All selected rows receive fresh assessments in a new review folder; previous pilot responses are not automatically reused. No data are rescanned. Both the detailed `summary.csv` and compact `summary_short.csv` are generated automatically. The batch is limited to the files already in that scan index; it does not discover other server files.

Use `run_experiments/review_grouped_pilot.R` to try the revised prompt on **three saved scans** before replacing the established reviewer. Set `scan_dir` to the original scan folder and choose `input_rows` from its `review_index.csv`; the example selects rows 1, 5 and 13. Run from the top with `send_to_api = FALSE`, inspect each `grouped-preview.txt`, then set TRUE and rerun to submit. No NetCDF rescan is performed. Credentials are loaded only when submission is enabled.

The editable prompt is [docs/grouped-review-prompt.md](docs/grouped-review-prompt.md). It requests five separate assessments: variable/metadata, grid/spatial coverage, time coverage, variable values, and source/processing. Each has a result, concrete finding and next action. PASS means no actionable issue within the performed checks; FAIL identifies a demonstrated problem or unmet explicit requirement; REVIEW asks for a specific verification; NOT_CHECKED identifies unavailable essential checking. Missing required history remains a documentation FAIL confined to source/processing, rather than failing every category. Existing deterministic failures cannot be dismissed by a model PASS.

The pilot starts at the current experiment's **20,000 completion tokens**, with `reasoning_effort = NULL`. This is a test budget, not a guarantee of completion; usage and finish reasons are saved per attempt. Both grouped runners expose `request_timeout <- 600` and `connection_timeout <- 20` near the top, in seconds. The request limit covers the whole call, including connection and waiting for a response; responses return as soon as available. Applied timeouts are printed and saved in pilot-settings.json and each attempt metadata.json. The input-size guard remains 64 kB. After a request ending at the old 180-second limit, first test `input_rows <- 1` (BESS) with 600 seconds before retrying the full batch. Compare findings, token usage and elapsed seconds before further resource changes.

### Concurrent LLM reviews

`max_concurrent_requests` is configured near the top of both grouped runners. The full-batch runner uses **4**; the small pilot keeps **1**. Valid settings are integers 1–4, with 1 retaining the sequential path. The function default also remains 1 for existing callers. This applies to model reviews of saved scans; NetCDF scans remain sequential.

The documented eINFRA limit is **four concurrent API requests per account**, with additional requests receiving HTTP 429. See the [CERIT-SC announcement of 10 March 2026](https://docs.cerit-sc.cz/en/docs/news#important-llm-update-new-rate-limits-for-api-concurrent-requests). Other scripts using the same account share that allowance; reduce this runner's setting when necessary.

Concurrent reviews use the existing curl package's asynchronous connection pool within one R session. No extra R processes, new packages or credential files are created. At most the configured number of requests are in flight, and a queued file starts as a slot becomes available. One coordinator writes the combined tables after each completion, retaining input-row order even when responses finish out of order. Each attempt keeps its own prompt, response/error metadata and report. HTTP/API errors, token limits, invalid responses and scan failures do not stop later files; there are no automatic retries.

Applied concurrency and timeout settings are printed and saved in pilot-settings.json. Pending calls appear as IN_PROGRESS in pilot_index.csv. A normal R interruption attempts to cancel active local transfers and marks uncheckpointed calls INTERRUPTED, preserving completed reports. A forced RStudio/session termination cannot run cleanup reliably or guarantee remote inference has stopped; inspect saved indexes before restarting. Submission still requires `send_to_api = TRUE`; previews make no API calls even with concurrency set to 4. An already running sequential script keeps its current behaviour until a new run is sourced.

Pilot outputs use a separate numbered `review-<scan-id>` folder:

- `summary.csv`: **`data_file_path,check_group,result,finding,next_action`**, five rows per selected file, with no overall verdict.
- `summary_short.csv`: one row per `data_file_path`, followed by the five check-group columns preserving exactly the detailed summary's PASS, FAIL, REVIEW or NOT_CHECKED labels. Missing categories are NOT_CHECKED. Identical repeated results collapse; conflicting results for the same path/category require inspection instead of silently changing their meaning. Different full paths stay separate.
- `summary_heatmap.png` and `summary_heatmap.pdf`: categorical overview with five columns, filenames in CSV row order, and exact status text in every coloured cell. PASS is green, FAIL red, REVIEW amber and NOT_CHECKED light grey. Duplicate basenames receive distinguishing parent-folder context; full paths and explanations remain in the CSVs.
- `flagged_files.csv`: the non-PASS category rows.
- `pilot_index.csv`: API/preparation/schema completion status per selected file; a known deterministic failure can remain FAIL even if the LLM call failed. Preview-only rows are not completed model assessments.
- Each file retains `group-results.csv`, a readable `review.md`, the submitted prompt, cached pilot checks and model response/usage metadata. A transport-complete response can still be INVALID_RESPONSE if its five-category JSON is invalid; use `pilot_index.csv` for assessment completion.
- `data_overview.csv` is copied unchanged when present, retaining the numerical overview separately.

For an already completed grouped review, run `run_experiments/summarise_grouped_review.R` with `review_dir` set to its folder. This regenerates `summary_short.csv` plus PNG/PDF heatmaps locally from the existing detailed summary, without scanning data or calling a model. Future grouped runs checkpoint the CSV after each file and render the heatmap once at normal batch completion, keeping plot rendering out of the API queue.

`heatmap_rows_per_page` is configured at the top of both review runners and the regeneration script (default 50, allowed 1–100). Long summaries become a multipage PDF and numbered PNGs such as summary_heatmap_001.png. The PNGs use 300 dpi; the PDF retains vector text/shapes. Plots use built-in R grid/graphics, with no new packages. Regeneration replaces only the heatmap exports and removes their stale numbered PNG pages; CSV assessments are unchanged. A batch export error is reported without invalidating saved model/CSV results. After an interrupted run, the regeneration script can plot the rows already saved in summary.csv.

Original scans and the established reviewer remain intact. The pilot does not create the legacy `review_index.csv`; do not point the existing retry runner at a pilot folder. To repeat a trial, run the pilot again against the saved scan with selected rows. A cached `pct`/`percent` units mismatch is corrected as a known spelling equivalence in the pilot copy, without rescaling values or rewriting the original scan.

## Repair old redacted history without a value scan

Older previews may contain `seltimestep,1[PATH REDACTED]` instead of `seltimestep,1/20`. The current sanitizer preserves complete numeric CDO argument ranges while still redacting paths. Lost text cannot be reconstructed from the old preview.

Use `run_experiments/refresh_scan_history.R`: set `scan_dir` to the existing scan batch and optionally select `input_rows`. It opens original NetCDF headers to refresh only the included processing history, reuses numerical diagnostics, and writes a numbered scan revision such as `scan-abc123-02` with the same identifier. No value scan, API call or credentials are needed. Original reports remain untouched. Selected refreshed rows are marked NOT_RUN so old model interpretations are not treated as current; inspect the corrected preview before pointing `review_scans.R` at the new folder.

This requires cached stable source size/mtime records and the original input paths. A missing/changed file or failed refresh is recorded as PREPARATION_ERROR and excluded from initial submission. Size/mtime checks are not content checksums; if file identity is uncertain, do a fresh scan. Absent/withheld history is not automatically introduced into the payload. Statistics are retained unchanged; included history, history-derived conversion exports and overview operations are regenerated.

## Retry unfinished model calls

Use `run_experiments/rerun_reviews.R`, selecting the latest batch/rerun folder and explicit statuses. This works with existing cached reports in their original locations. Default: TOKEN_LIMIT only, once at twice the previous budget up to 16384. Optional same-budget-first retry; API errors, when explicitly selected, retry at their original budget. No unbounded automatic retries. Completed calls are not repeated.

Retries reuse the scan identifier and are always numbered, for example `rerun-abc123-01` and `rerun-abc123-02`. Each retry keeps the original results unchanged and saves an updated full index, short summary, flagged rows and `attempts.csv` (budgets, completion/reasoning/prompt tokens and finish reasons). Older budget inference and maximum settings are described in the runner. Recorded relative paths assume the original project-root working directory; moving report directories is not supported automatically.

## Other runners

- `run_experiments/query_llm.R`: editable text prompt and Markdown answer; explicit text attachments are included verbatim after preview, without automatic redaction. No model browsing, tools or prior-call memory.
- `run_experiments/inventory_files.R`: metadata inventory without a value scan or model call.
- `run_experiments/csv_example.R`: synthetic CSV demonstration.

## Validation and migration

Run `Rscript tests/run_all.R` from the root. Tests use synthetic data and mock model calls, never real credentials or live inference. Representative server files are still needed to evaluate scientific usefulness and runtime.

For renamed scripts and preserving existing reports/settings, see [migration](docs/migration.md). Significant development milestones are in [history](docs/history.md). Current limitations include no interrupted-scan resume, automatic cache freshness verification, arbitrary multi-level grids or independent reference-product/mask comparisons.

Service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/ai-api

## AI assistance

This project was developed with substantial AI assistance from GPT-6.1 Sol, with design decisions and review by the user. Offline tests validate implementation behaviour; model-generated scientific diagnoses require human review. AI involvement is also credited in new commit messages.
