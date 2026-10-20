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

`data_file_path` is required; `family` is optional when inference is sufficient. Optional `provenance_notes` supplies actual source documentation. Relative file paths resolve against `data_root`, not the CSV location. Absolute paths are also supported. The checker still derives scientific expectations from each filename, not the example names above. Missing files are recorded and do not stop later files.

Set `data_root` and `output_dir` near the top of the runner. To use machine-specific overrides, copy `config/paths.local.example.R` to ignored `config/paths.local.R`. That file contains paths only, never credentials. Relative output/table paths resolve from the repository root. Shared relative paths may be tracked; review input tables before publishing them.

## 1. Scan and save (no API key required)

Choose a runner, edit its configuration, then run it from the top:

- `run_experiments/scan_files.R`: read `config/data_file_paths.csv`.
- `run_experiments/scan_file.R`: one explicitly configured file.
- `run_experiments/scan_temperature.R`: discover the temperature folder, including raw/processed subfolders; excludes hidden entries and symlinks.

Scans read all time layers sequentially and checkpoint a random `batch-*` folder after each file. Daily/hourly files may take substantial time. No model is called during this stage.

Each batch includes **`data_overview.csv`**, one row per requested input, including unreadable/missing files. It contains the table path and resolved input path, variable, units, mean/min/max, grid endpoints/extents/spacing/counts, layer count, time coverage and missing-period count. `recorded_operations` retains the included redacted history (possibly multiline), without inferring a complete recipe. File size/mtime, scan time and scanner version are included; exact scanner-file checksums are stored in each `scan-record.json`. Source size/mtime before and after the scan are recorded; they are not content hashes.

Detailed per-file outputs remain:

- `checks.csv`, `local-diagnostics.rds`, `review-preview.json`.
- `file-summary.csv`, `layer-statistics.csv`, `time-period-issues.csv` (complete missing/unexpected/duplicate period lists).
- `file-metadata.json`, `scan-record.json`, `recorded-conversions.csv`, `conversion-notes.txt`.

An unsupported or malformed file may have fewer diagnostics; missing values do not imply a clean check. Overview means are unweighted finite cell-time averages, not area-weighted climate means. See [review policy](docs/review-policy.md) for scientific conventions and limitations.

## 2. Review saved scans

Open `run_experiments/review_scans.R`. Set `scan_dir` to the saved `batch-*` directory containing `review_index.csv`. This also accepts old no-API batches. It uses cached checks, without opening source files or verifying whether they have changed. Use a fresh scan after changing input data or checker logic; old caches cannot acquire new statistics by asking the model again.

With `send_to_api = FALSE`, the script saves updated previews without calling the service. Inspect them, then explicitly enable submission with TRUE. Selecting TRUE approves the built-in basename, selected metadata, diagnostics and redacted-history payloads for the selected cached files; raw arrays and input paths are not automatically submitted. Redaction is best-effort, not a privacy guarantee. Do not submit confidential filenames or notes.

The model/effort/token/input-size settings are visible at the top. Existing budgets remain unchanged: default 8192 completion tokens, 64 kB input guard, 180-second API timeout and 20-second connection timeout. Completion budgets can include reasoning. `reasoning_effort = NULL` omits that field and uses the provider default; explicit support is model-dependent. Timeout/resource changes and parallel execution are separate future choices, not bundled into the restructure.

Reviews create a new random `batch-*` folder; original scans remain unchanged. Already completed reviews are retained without repeating calls. Per-file errors do not stop the next file.

### Credentials

Setup creates a placeholder file outside the repository at `~/.config/einfra-data-reviewer/credentials.R`. Edit that private file to define `api_key`. Where supported it is created with account-only permissions. An existing file is never overwritten. You can set `credentials_file` in API runners to another private location.

Keys are read only when API calls are enabled, held in R memory and never intentionally included in reports or logs. There are no hidden interactive prompts. This is a plain-text secret, not a vault: protect backups and account access. Do not print or commit it, and do not save authenticated R workspaces. Sourcing `source/reviewer.R` again clears its key environment. Keys should be cleared with `clear_api_key()` when finished.

### Error overview and detailed review

- **`summary.csv`** remains exactly `filename,result,reason`, listing every input.
- **`flagged_files.csv`** lists non-PASS rows with full identity/status/report context.
- `review_index.csv` distinguishes scan failures, model completion, TOKEN_LIMIT and API_ERROR, including input paths when available.
- Detailed attempts retain `review.md`, validated response JSON, submitted evidence and metadata with model, usage, token budget and finish reason.

The deterministic `data_overview.csv` is copied forward unchanged when present; model conclusions do not modify statistics. FAIL includes strict provenance/naming flags, not only incorrect numerical values. A known deterministic failure remains FAIL even if the LLM is unfinished. Scan-only summary rows cannot constitute a completed LLM review.

## Repair old redacted history without a value scan

Older previews may contain `seltimestep,1[PATH REDACTED]` instead of `seltimestep,1/20`. The current sanitizer preserves complete numeric CDO argument ranges while still redacting paths. Lost text cannot be reconstructed from the old preview.

Use `run_experiments/refresh_scan_history.R`: set `scan_dir` to the existing scan batch and optionally select `input_rows`. It opens original NetCDF headers to refresh only the included processing history, reuses numerical diagnostics, and writes a new random `batch-*` folder. No value scan, API call or credentials are needed. Original reports remain untouched. Selected refreshed rows are marked NOT_RUN so old model interpretations are not treated as current; inspect the corrected preview before pointing `review_scans.R` at the new folder.

This requires cached stable source size/mtime records and the original input paths. A missing/changed file or failed refresh is recorded as PREPARATION_ERROR and excluded from initial submission. Size/mtime checks are not content checksums; if file identity is uncertain, do a fresh scan. Absent/withheld history is not automatically introduced into the payload. Statistics are retained unchanged; included history, history-derived conversion exports and overview operations are regenerated.

## Retry unfinished model calls

Use `run_experiments/rerun_reviews.R`, selecting the latest batch/rerun folder and explicit statuses. This works with existing cached reports in their original locations. Default: TOKEN_LIMIT only, once at twice the previous budget up to 16384. Optional same-budget-first retry; API errors, when explicitly selected, retry at their original budget. No unbounded automatic retries. Completed calls are not repeated.

Each `rerun-*` keeps the original results unchanged and saves an updated full index, short summary, flagged rows and `attempts.csv` (budgets, completion/reasoning/prompt tokens and finish reasons). Older budget inference and maximum settings are described in the runner. Recorded relative paths assume the original project-root working directory; moving report directories is not supported automatically.

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
