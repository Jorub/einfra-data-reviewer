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

There are five configured scripts in `run_experiments/`:

| Script | Purpose |
| --- | --- |
| `scan_files.R` | Check all input paths, scan the listed NetCDF files and save evidence. |
| `review_grouped_scans.R` | Review saved scans with six separate category assessments. |
| `summarise_grouped_review.R` | Regenerate the short summary and heatmap from saved grouped results. |
| `merge_reviews.R` | Combine full and partial grouped reviews into one view without LLM calls. |
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

The configured reviewer defaults to model `thinker`, **`max_tokens = NULL`**, `reasoning_effort = NULL`, a 64 kB input guard, **600 seconds** per request, **20 seconds** to connect, and **one request at a time**. Settings remain near the top of the runner and are recorded in `pilot-settings.json` and per-attempt metadata. `max_tokens = NULL` omits the token-limit parameter entirely from the API request; a numeric value such as `20000L` sends an explicit cap. `reasoning_effort = NULL` separately omits the reasoning control; support for explicit reasoning settings is model-dependent.

Omitting our cap delegates the limit to the provider/model; it is not unlimited generation and does not extend the timeout. The provider's actual default limit is not assumed or inferred from token usage. Settings and attempt metadata retain `max_tokens: null` with `max_tokens_source: "provider_default"`; numeric requests record `"explicit"`. Actual usage and finish reason are saved separately. A response ending with `length` is still TOKEN_LIMIT and incomplete, even when our cap was omitted. Existing function callers retain their numeric defaults unless they explicitly pass NULL. The retained legacy retry helper preserves an explicitly omitted limit for one selected retry rather than inventing a numeric fallback or doubling observed usage.

Each run creates a new `review-<scan-id>` folder, with numbered suffixes for repeats. Existing results are preserved. **All selected rows receive fresh assessments**; completed results from earlier review folders are not automatically reused or merged. For targeted repeats, keep `scan_dir` pointing to the saved scans and select only the required `input_rows`. The resulting summary contains those selected rows. Use the separate merge script below to combine it with earlier completed assessments.

The editable prompt is [docs/grouped-review-prompt.md](docs/grouped-review-prompt.md). It requests six separate assessments: variable/metadata, grid/spatial coverage, time coverage, variable values, source/processing, and mask provenance. Each has a result, concrete finding and next action. PASS means no actionable issue within the performed checks; FAIL identifies a demonstrated problem or unmet explicit requirement; REVIEW asks for a specific verification; NOT_CHECKED identifies unavailable essential checking. Missing required history is a documentation FAIL in source/processing and, for land files, mask provenance; it does not fail unrelated numerical categories. Existing deterministic failures cannot be dismissed by a model PASS.

### Mask provenance

The sixth category, `mask_provenance`, applies only to files labelled `land`. R extracts recorded mask references and application evidence, and enforces the agreed identity rule; the LLM receives the basename-only evidence and explains the result. This category can therefore have a deterministic result even when a model request fails or previews are generated without submission. Consult `pilot_index.csv` separately for LLM completion.

| Result | Mask-provenance rule |
| --- | --- |
| PASS | History records application of approved `oceanmask_ithaca_global_025.nc`. A basename alone is sufficient; a missing directory is reported without failing. |
| REVIEW | A mask is identified but unapproved (for example `mask_land_ocean_025.nc`), application is unclear, or the available history is incomplete. |
| FAIL | Fully inspected land-file history identifies no mask file, including missing/empty history. This is a documentation failure, not proof of a wrong mask. |
| NOT_CHECKED | The scan stopped earlier, relevant evidence is withheld or irrecoverably redacted/truncated, or the file is outside land-only scope. |

PASS establishes the recorded mask identity, not mask contents or correct numerical application. Recognized application evidence includes CDO mul/ifthen-style commands using the mask as an input, or an explicit statement of use. A filename merely appearing as a reference or as a mask-creation output does not establish application. Other commands may require human verification and remain REVIEW; no history command is executed.

New scans keep extracted mask paths as local-only attributes. Existing saved scans can recover the global history from their cached full `ncdump -h` output without reopening the source. If only redacted evidence remains, the checker reports that limitation instead of guessing a path or declaring provenance absent. Respect `include_history = FALSE`: withheld history is not recovered into the model payload.

Per-file `mask-provenance.csv` records the mask filename, path exactly as visible, whether only the filename was available, application evidence and its source. The same recorded paths appear in the mask section of local `review.md`. The model receives mask basenames and application flags only, never recovered directories or raw headers. Inspect previews before submission; the original source files and cached scans are unchanged by grouped review.

For a small server test, set `input_rows <- c(1, 5, 19)` and `max_concurrent_requests <- 1L` in `review_grouped_scans.R`, using the latest saved scan folder. Start with `send_to_api <- FALSE` to inspect extracted evidence and local paths, then set TRUE and run from the top to test the six-category LLM response. Keep the existing token/time budgets. No rescan is needed when the cache includes sufficient history. The local test suite uses synthetic data and mocked inference, not your server files.

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

- `summary.csv`: **`data_file_path,check_group,result,finding,next_action`**, six rows per selected file in new reviews, with no overall verdict. Earlier five-category results retain their original scope.
- `summary_short.csv`: one row per `data_file_path`, followed by the six check-group columns in new reviews (five in older reviews) preserving exactly the detailed summary's PASS, FAIL, REVIEW or NOT_CHECKED labels. Missing categories are NOT_CHECKED. Identical repeated results collapse; conflicting results for the same path/category require inspection instead of silently changing their meaning. Different full paths stay separate.
- `summary_heatmap.png` and `summary_heatmap.pdf`: categorical overview with six category columns for new reviews (five for older reviews), filenames in CSV row order, and exact status text in every coloured cell. PASS is green, FAIL red, REVIEW amber and NOT_CHECKED light grey. Each filename has a second line identifying its saved report, such as `review-abc123/file-014`, read from `pilot_index.csv`. Merged results point to the selected original review/report folder, not a newly numbered merge row. Data directories are not printed. If the mapping is absent, the label explicitly says `Report folder unavailable`; no report number is guessed. Full data/report paths and explanations remain in the CSVs.
- `flagged_files.csv`: the non-PASS category rows.
- `pilot_index.csv`: API/preparation/schema completion status per selected file; a known deterministic failure can remain FAIL even if the LLM call failed. Preview-only rows are not completed model assessments.
- Each file retains `group-results.csv`, local `mask-provenance.csv`, a readable `review.md`, the submitted prompt, cached pilot checks and model response/usage metadata. A transport-complete response can still be INVALID_RESPONSE if its six-category JSON is invalid; use `pilot_index.csv` for assessment completion.
- `data_overview.csv` is copied unchanged when present, retaining the numerical overview separately.

For an already completed grouped review, run `run_experiments/summarise_grouped_review.R` with `review_dir` set to its folder. This regenerates `summary_short.csv` plus PNG/PDF heatmaps locally from the existing detailed summary, without scanning data or calling a model. Future grouped runs checkpoint the CSV after each file and render the heatmap once at normal batch completion, keeping plot rendering out of the API queue.

`heatmap_rows_per_page` is configured at the top of the review runner and the regeneration script (default 50, allowed 1–100). Long summaries become a multipage PDF and numbered PNGs such as summary_heatmap_001.png. The PNGs use 300 dpi; the PDF retains vector text/shapes. Plots use built-in R grid/graphics, with no new packages. Regeneration replaces only the heatmap exports and removes their stale numbered PNG pages; CSV assessments are unchanged. A batch export error is reported without invalidating saved model/CSV results. After an interrupted run, the regeneration script can plot the rows already saved in summary.csv.

The scan's `review_index.csv` and the grouped review's `pilot_index.csv` have different purposes. Set `scan_dir` to the scan folder and `review_dir` to the grouped review folder. Old single-verdict summaries do not have the grouped schema and cannot be passed to the grouped summary script.

## 4. Merge full and partial reviews

Open `run_experiments/merge_reviews.R`. Set `review_dirs` to grouped-review folders **in order from oldest to newest**, with the original full review first, then subsequent trials or retries:

```r
review_dirs <- c(
  "output/review-original",
  "output/review-single-file-retry",
  "output/review-remaining-files"
)
```

These are examples: use actual review folders containing both `summary.csv` and `pilot_index.csv`. The list order defines priority explicitly; filesystem timestamps are not used. Set `output_dir` and `heatmap_rows_per_page` at the top, then run the whole script. No credentials, source data, rescans or LLM calls are needed.

The merge uses **full data paths**, preserving first-seen file order. For each file it selects the newest assessment whose scan and LLM review both completed. A later API error, token limit, preparation failure or pending request cannot replace an earlier completed assessment. A completed assessment is selected as a whole: its FAIL, REVIEW and NOT_CHECKED categories are retained, even if older results were PASS. If no completed assessment exists, the latest available execution status and deterministic findings remain visible. Pending files without saved group rows appear as NOT_CHECKED. Equal basenames in different directories stay separate; `/home/...` and `/mnt/...` aliases are not automatically equated. Confirm that the supplied reviews concern the intended file versions; the merge does not verify source content identity.

Outputs go into a new, numbered-if-needed `merge-<id>` folder. Original reviews remain unchanged. It contains:

- `summary.csv`, `summary_short.csv`, `flagged_files.csv` and PNG/PDF heatmaps in the existing grouped formats. `summarise_grouped_review.R` can regenerate this merged overview later.
- `pilot_index.csv`: the selected execution status and original report references per file, with `selected_review_dir`, `selected_review_order` and `selection_reason`. Individual detailed reports stay in their original review folders.
- `review_changes.csv`: category verdict changes between consecutive completed assessments in the supplied order, including old/new findings, next actions and originating review folders. PASS-to-NOT_CHECKED changes are recorded too. An empty file with column headers means no comparable verdicts changed. Failed API attempts are not treated as completed scientific assessments.
- `review_sources.csv`: the ordered input folders and checksums of their summary/index CSVs; `merge-settings.json` and `run-lineage.json` record the merge settings and origin. Five-category inputs remain usable: an all-legacy merge stays five-category; a mixed merge marks the absent mask assessment NOT_CHECKED for files selected from legacy reviews. No favourable per-category mixing is performed. No numerical scan statistics are recalculated or consolidated; existing `data_overview.csv` files remain in their original runs.

Keep original review folders available so report references remain usable. A merged folder can itself be an input to a later merge; its source-list files preserve the chain back to earlier reviews.

## General LLM queries

Use `run_experiments/query_llm.R` independently of scans. Set the model, token budget, prompt sections, evidence and output directory near the top. Run with `send_to_api = FALSE` to preview, then explicitly enable submission. A successful call saves the response as `response.md`, with the prompt and metadata in its own `llm-*` folder. Explicit text attachments are included verbatim without automatic redaction. The model has no browsing, file access, tools or prior-call memory. Its general-query budget remains separate from the grouped review defaults: the example keeps 8192 tokens, and setting `max_tokens <- NULL` opts into omission there too.

## Validation and migration

Run `Rscript tests/run_all.R` from the root. Tests use synthetic data and mock model calls, never real credentials or live inference. Representative server files are still needed to evaluate scientific usefulness and runtime.

For removed entrypoints and preservation of existing reports/settings, see [migration](docs/migration.md). Significant milestones are in [history](docs/history.md). Existing cached outputs and reusable helpers remain intact. Current limitations include no interrupted-scan resume, automatic cache freshness verification, arbitrary multi-level grids or independent reference-product/mask comparisons.

Earlier previews may contain damaged CDO ranges such as `seltimestep,1[PATH REDACTED]`. The current sanitizer preserves `seltimestep,1/20`, but cannot recover text already lost in an old preview. Use fresh scans or the retained `refresh_saved_history()` helper in `source/refresh_history.R` before relying on affected evidence.

Service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/ai-api

## AI assistance

This project was developed with substantial AI assistance from GPT-6.1 Sol, with design decisions and review by the user. Offline tests validate implementation behaviour; model-generated scientific diagnoses require human review. AI involvement is also credited in new commit messages.
