# Current entrypoints and existing saved runs

## Four configured scripts

`run_experiments/` now contains only:

- `scan_files.R`: all NetCDF scanning, including a single-file table and automatic all-input path preflight.
- `review_grouped_scans.R`: all current NetCDF LLM review; choose `input_rows` for either a trial or a full batch.
- `summarise_grouped_review.R`: regenerate short summaries and heatmaps without scanning or API calls.
- `query_llm.R`: general editable LLM prompts and Markdown responses.

The old single-verdict review runner and the separate pilot, path-check, single-file, temperature-folder, inventory, retry, history-refresh and CSV-example runners were deleted. Their previous versions remain in Git history. Reusable source functions are retained, including compatibility helpers used by existing caches and tests. Setup remains in `setup.R` at the project root.

Before pulling, privately preserve any settings you edited in a runner being deleted. Do not commit API keys or private paths. Put input paths in your configured CSV or ignored `config/paths.local.R`, and credentials in their separate private file. Functions belong in `source/`; run the configured scripts from the project root.

## Using existing saved evidence

No source data, scan folders, review folders or private configuration are moved or deleted by this cleanup. Keep reports in their original locations: saved relative paths assume the project-root working directory. Preserve `run-lineage.json` when copying new runs; moving report folders does not automatically update saved paths.

Set `scan_dir` in `review_grouped_scans.R` to an existing scan folder containing `review_index.csv` and cached diagnostics. Older no-API batch folders with that scan schema can also be used. Source files do not need to remain accessible to review cached evidence. A new scan is needed if an earlier scan failed, the source changed, or the scientific checks changed.

Set `review_dir` in `summarise_grouped_review.R` to a grouped-review folder containing the five-group `summary.csv`. Its `pilot_index.csv` records execution status. Old single-verdict summaries are a different schema; they are preserved but cannot be regenerated as five-group summaries without a grouped assessment.

Review calls do not automatically reuse completed results from earlier review folders. Select only the rows needing a repeat to avoid paying for completed calls again. Each new folder contains results for its selected rows; automatic consolidation across runs is not implemented. The older single-verdict retry helper is not compatible with grouped-review indexes.

## Settings and output

Run `setup.R` if dependencies or initial folders are missing; it preserves existing configuration. The current CSV requires `data_file_path`; `family` and `provenance_notes` are optional. Relative input paths resolve against `data_root`, and relative output paths against the project root. An empty input table stops with instructions rather than guessing a directory.

Current grouped settings stay unchanged: 20,000 completion tokens, provider-default reasoning, 600-second request and 20-second connection timeouts, up to four concurrent requests. Scans remain sequential. Scientific checks and the four result labels are unchanged.

New scans use `scan-<id>`. Reviews reuse the id as `review-<id>`, adding numbered suffixes for repeats. Original runs are not overwritten. Setup creates the default output directory; runners create explicitly configured external output directories when needed. Existing reports without newer statistics or scan identity remain usable within their available evidence; this cleanup does not fabricate missing diagnostics.
