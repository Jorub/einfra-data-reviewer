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

## Workflow

There are exactly four configured scripts in `run_experiments/`:

| Script | Purpose |
| --- | --- |
| `scan_files.R` | Check all input paths, scan the listed NetCDF files and save evidence. |
| `review_grouped_scans.R` | Review saved scans with five separate LLM assessments. |
| `summarise_grouped_review.R` | Regenerate the short summary and heatmap from saved grouped results. |
| `query_llm.R` | Send a general editable prompt independently of the NetCDF workflow. |

Run from the project root. Keep settings near the top of each script and run from the top after editing them. `setup.R` remains the separate setup entrypoint.

## 1. Scan and save (no API key required)

Open `run_experiments/scan_files.R`, set `data_file_paths`, `data_root` and `output_dir`, then run it. The input table can contain one file or many; use the same script for either.

Before scanning, it checks **every input path**. All missing paths are printed and saved to `output_dir/missing_files.csv`, then the batch stops before opening NetCDF contents. Correct every listed path and rerun. There is no separate path-check runner. Existing directories are rejected as file inputs; presence does not prove valid data. The CSV is regenerated on every preflight, including an empty table when all files exist. The reusable helpers `missing_input_files(file_specs)` and `check_input_files(file_specs, report_dir = output_dir)` remain available in `source/input_paths.R`.

Scans read all time layers sequentially and checkpoint a `scan-<id>` folder with one random identifier after each file. Daily/hourly files may take substantial time. No model is called during this stage. New scans check ncdf4, CFtime and jsonlite before starting; missing prerequisites stop with setup instructions instead of completing an expensive scan without time checks.

Each batch includes **`data_overview.csv`**, one row per requested input once preflight passes, including files that subsequently become unreadable or disappear. Older saved batches may already contain missing-file rows. It contains the table path and resolved input path, variable, units, mean/min/max, grid endpoints/extents/spacing/counts, layer count, time coverage and missing-period count. `recorded_operations` retains the included redacted history (possibly multiline), without inferring a complete recipe. File size/mtime, scan time and scanner version are included; exact scanner-file checksums are stored in each `scan-record.json`. Source size/mtime before and after the scan are recorded; they are not content hashes.

Detailed per-file outputs remain:

- `checks.csv`, `local-diagnostics.rds`, `review-preview.json`.
- `file-summary.csv`, `layer-statistics.csv`, `time-period-issues.csv` (complete missing/unexpected/duplicate period lists).
- `file-metadata.json` (including actual NetCDF storage type and packing attributes), `scan-record.json`, `recorded-conversions.csv`, `conversion-notes.txt`.

An unsupported or malformed file may have fewer diagnostics; missing values do not imply a clean check. Overview means are unweighted finite cell-time averages, not area-weighted climate means. See [review policy](docs/review-policy.md) for scientific conventions and limitations.

## 2. Review saved scans

Open `run_experiments/review_grouped_scans.R`. Set `scan_dir` to the saved scan folder containing `review_index.csv`. Leave `input_rows = NULL` for all files or select row numbers, for example `c(1, 5, 13)`, for a small trial or targeted repeat. One runner handles both. It uses cached evidence without reopening source files or checking whether they have changed. Use fresh scans when source data or scientific checks change.

Run first with `send_to_api = FALSE` and inspect each `grouped-preview.txt`. Set TRUE and rerun to submit the selected evidence. This explicitly approves the built-in basename, selected metadata, diagnostics and redacted processing history. Raw arrays and full input paths are not automatically submitted. Redaction is best-effort: inspect previews and do not send confidential filenames or notes.

The configured defaults are model `thinker`, **20,000 completion tokens**, `reasoning_effort = NULL`, a 64 kB input guard, **600 seconds** per request, **20 seconds** to connect, and **four concurrent requests**. Settings remain near the top of the runner and are recorded in `pilot-settings.json` and per-attempt metadata. Completion budgets can include reasoning. NULL omits the reasoning field and uses the provider default; support for explicit settings is model-dependent. A budget does not guarantee completion.

Each run creates a new `review-<scan-id>` folder, with numbered suffixes for repeats. Existing results are preserved. **All selected rows receive fresh assessments**; completed results from earlier review folders are not automatically reused or merged. For targeted repeats, keep `scan_dir` pointing to the saved scans and select only the required `input_rows`. The resulting summary contains those selected rows. A consolidated recovery/merge workflow is not implemented yet.

The editable prompt is [docs/grouped-review-prompt.md](docs/grouped-review-prompt.md). It requests five separate assessments: variable/metadata, grid/spatial coverage, time coverage, variable values, and source/processing. Each has a result, concrete finding and next action. PASS means no actionable issue within the performed checks; FAIL identifies a demonstrated problem or unmet explicit requirement; REVIEW asks for a specific verification; NOT_CHECKED identifies unavailable essential checking. Missing required history remains a documentation FAIL confined to source/processing, rather than failing every category. Existing deterministic failures cannot be dismissed by a model PASS.

### Concurrent LLM reviews and execution errors

`max_concurrent_requests` accepts integers 1–4; 1 runs sequentially. This applies to model reviews only. NetCDF scans remain sequential.

The documented eINFRA limit is **four concurrent API requests per account**, with additional requests receiving HTTP 429. See the [CERIT-SC announcement of 10 March 2026](https://docs.cerit-sc.cz/en/docs/news#important-llm-update-new-rate-limits-for-api-concurrent-requests). Other scripts using the same account share that allowance; reduce this runner's setting when necessary.

Concurrent reviews use the existing curl package's asynchronous connection pool within one R session. No extra R processes, new packages or credential files are created. At most the configured number of requests are in flight, and a queued file starts as a slot becomes available. One coordinator writes the combined tables after each completion, retaining input-row order even when responses finish out of order. Each attempt keeps its own prompt, response/error metadata and report. HTTP/API errors, token limits, invalid responses and scan failures do not stop later files; there are no automatic retries.

Applied concurrency and timeout settings are printed and saved in pilot-settings.json. Pending calls appear as IN_PROGRESS in pilot_index.csv. A normal R interruption attempts to cancel active local transfers and marks uncheckpointed calls INTERRUPTED, preserving completed reports. A forced RStudio/session termination cannot run cleanup reliably or guarantee remote inference has stopped; inspect saved indexes before restarting. Submission still requires `send_to_api = TRUE`; previews make no API calls even with concurrency set to 4. An already running sequential script keeps its current behaviour until a new run is sourced.

Connection failures retain fixed safe categories such as TIMEOUT, DNS_ERROR, CONNECT_ERROR, TLS_ERROR, TRANSFER_ERROR or UNKNOWN_TRANSPORT_ERROR without saving raw curl messages. Metadata records elapsed time, token usage and finish reason. Older attempts may show NOT_COMPLETED with an API-failure reason; suppressed transport details cannot be recovered. Use `pilot_index.csv` to distinguish execution problems from scientific findings. A TOKEN_LIMIT can be retried using saved scans without scanning the source again; no retry is automatic.

### Credentials

Setup creates a placeholder file outside the repository at `~/.config/einfra-data-reviewer/credentials.R`. Edit that private file to define `api_key`. Where supported it is created with account-only permissions. An existing file is never overwritten. You can set `credentials_file` in API runners to another private location.

Keys are read only when API calls are enabled, held in R memory and never intentionally included in reports or logs. There are no hidden interactive prompts. This is a plain-text secret, not a vault: protect backups and account access. Do not print or commit it, and do not save authenticated R workspaces. Sourcing `source/reviewer.R` again clears its key environment. Keys should be cleared with `clear_api_key()` when finished.

## 3. Results and regenerated overviews

The grouped review produces:

- `summary.csv`: **`data_file_path,check_group,result,finding,next_action`**, five rows per selected file, with no overall verdict.
- `summary_short.csv`: one row per `data_file_path`, followed by the five check-group columns preserving exactly the detailed summary's PASS, FAIL, REVIEW or NOT_CHECKED labels. Missing categories are NOT_CHECKED. Identical repeated results collapse; conflicting results for the same path/category require inspection instead of silently changing their meaning. Different full paths stay separate.
- `summary_heatmap.png` and `summary_heatmap.pdf`: categorical overview with five columns, filenames in CSV row order, and exact status text in every coloured cell. PASS is green, FAIL red, REVIEW amber and NOT_CHECKED light grey. Duplicate basenames receive distinguishing parent-folder context; full paths and explanations remain in the CSVs.
- `flagged_files.csv`: the non-PASS category rows.
- `pilot_index.csv`: API/preparation/schema completion status per selected file; a known deterministic failure can remain FAIL even if the LLM call failed. Preview-only rows are not completed model assessments.
- Each file retains `group-results.csv`, a readable `review.md`, the submitted prompt, cached pilot checks and model response/usage metadata. A transport-complete response can still be INVALID_RESPONSE if its five-category JSON is invalid; use `pilot_index.csv` for assessment completion.
- `data_overview.csv` is copied unchanged when present, retaining the numerical overview separately.

For an already completed grouped review, run `run_experiments/summarise_grouped_review.R` with `review_dir` set to its folder. This regenerates `summary_short.csv` plus PNG/PDF heatmaps locally from the existing detailed summary, without scanning data or calling a model. Future grouped runs checkpoint the CSV after each file and render the heatmap once at normal batch completion, keeping plot rendering out of the API queue.

`heatmap_rows_per_page` is configured at the top of the review runner and the regeneration script (default 50, allowed 1–100). Long summaries become a multipage PDF and numbered PNGs such as summary_heatmap_001.png. The PNGs use 300 dpi; the PDF retains vector text/shapes. Plots use built-in R grid/graphics, with no new packages. Regeneration replaces only the heatmap exports and removes their stale numbered PNG pages; CSV assessments are unchanged. A batch export error is reported without invalidating saved model/CSV results. After an interrupted run, the regeneration script can plot the rows already saved in summary.csv.

The scan's `review_index.csv` and the grouped review's `pilot_index.csv` have different purposes. Set `scan_dir` to the scan folder and `review_dir` to the grouped review folder. Old single-verdict summaries do not have the five-group schema and cannot be passed to the grouped summary script.

## General LLM queries

Use `run_experiments/query_llm.R` independently of scans. Set the model, token budget, prompt sections, evidence and output directory near the top. Run with `send_to_api = FALSE` to preview, then explicitly enable submission. A successful call saves the response as `response.md`, with the prompt and metadata in its own `llm-*` folder. Explicit text attachments are included verbatim without automatic redaction. The model has no browsing, file access, tools or prior-call memory. Its general-query budget remains separate from the grouped review defaults.

## Validation and migration

Run `Rscript tests/run_all.R` from the root. Tests use synthetic data and mock model calls, never real credentials or live inference. Representative server files are still needed to evaluate scientific usefulness and runtime.

For removed entrypoints and preservation of existing reports/settings, see [migration](docs/migration.md). Significant milestones are in [history](docs/history.md). Existing cached outputs and reusable helpers remain intact. Current limitations include no interrupted-scan resume, automatic cache freshness verification, automatic consolidation of separate review runs, arbitrary multi-level grids or independent reference-product/mask comparisons.

Earlier previews may contain damaged CDO ranges such as `seltimestep,1[PATH REDACTED]`. The current sanitizer preserves `seltimestep,1/20`, but cannot recover text already lost in an old preview. Use fresh scans or the retained `refresh_saved_history()` helper in `source/refresh_history.R` before relying on affected evidence.

Service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/ai-api

## AI assistance

This project was developed with substantial AI assistance from GPT-6.1 Sol, with design decisions and review by the user. Offline tests validate implementation behaviour; model-generated scientific diagnoses require human review. AI involvement is also credited in new commit messages.
