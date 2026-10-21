# Development history

Meaningful milestones, reconstructed from Git commits where applicable. Git history holds detailed changes; README.md describes current usage.

## 2026-10-21 — Guard the standalone path-check success message

- Recheck path availability before printing success, including when RStudio runs the final expression separately after a missing-file error. Preserve the complete missing-path list, CSV export and scan-blocking error.

## 2026-10-21 — Categorical review heatmap

- Export a filename-by-category heatmap as PNG and vector PDF alongside grouped results. Preserve CSV row order and exact PASS/FAIL/REVIEW/NOT_CHECKED labels; use green/red/amber/light-grey fills with status text. Distinguish repeated basenames using parent-folder context without dropping rows or exposing full paths unnecessarily.
- Render locally with built-in R graphics and no new packages or model calls. Generate once after grouped batch completion and from the existing summary-regeneration runner. Paginate long lists at configurable heatmap_rows_per_page (default 50) into a multipage PDF and numbered PNGs, keeping request checkpoints lightweight.
- Verify exact data/label preservation, filename disambiguation, page order, output signatures, graphics-device cleanup, stale generated-page replacement and unchanged input CSV. Inspect PNG and rendered PDF previews against the supplied 35-file summary; real server inputs were not opened.

## 2026-10-21 — Persist and print the full missing-file overview

- Save every missing path to output_dir/missing_files.csv and print the full list before raising a short error, avoiding long stop() messages that R/RStudio may truncate. Apply this to standalone checking and all scan batches. No NetCDF values or API calls are started.
- Regenerate the CSV on each check, including an empty table when all paths exist, so a corrected run cannot leave a stale missing-file report. Keep the missing_files vector and typed error available.
- Test a 50-file long-path list, complete console/CSV output, stale-report clearing and absence of scan-batch creation before error.

## 2026-10-21 — Stop scans early with a complete missing-file list

- Add a lightweight path-only preflight and a standalone configured checker. Return all missing full paths as a character vector; automatic batch validation lists them together and errors before creating a scan batch or reading NetCDF values. Reject directory paths as input files. No credentials, API calls or NetCDF dependencies are required for the standalone check.
- Apply the guard to all shared scan entrypoints, replacing the previous behaviour of discovering missing paths late inside the file loop. Content errors after a successful preflight still checkpoint and continue; a file disappearing after the check remains a per-file scan error. Cached LLM reviews still work without original source files.
- Test multiple missing inputs, duplicate/path expansion, invalid specifications, zero scan/API work before failure and no new batch directory. Preserve integration coverage for unreadable existing files and saved reviews after source removal.

## 2026-10-20 — Four concurrent saved-scan LLM reviews

- Add max_concurrent_requests (1–4), using the agreed four requests in the full grouped runner and retaining one for pilots/existing function callers. Respect the documented per-account limit; other account activity shares those slots. Keep NetCDF scanning sequential and preserve the 600/20-second timeouts, token budget, scientific prompt and verdict vocabulary.
- Use curl's in-process asynchronous pool without extra packages, R worker processes or credential copies. Refill available slots, isolate per-file transport/HTTP/token/schema/preparation failures and keep one coordinator writing checkpoints. Preserve input-row identity/order and all detailed/compact outputs as responses finish out of order. No automatic retries are introduced.
- Save concurrency settings and in-progress status; cancel local active handles on a normal interrupt and retain completed checkpoints. Forced session termination and remote cancellation remain outside the cleanup guarantee.
- Validate queue width/refill, out-of-order identity, HTTP 429 and other failure continuation, private-payload exclusion, preview-only behaviour, unchanged scans and interruption cleanup with mocked requests. Exercise real curl multi callbacks using only local response files, without network access or credentials.

## 2026-10-20 — Consistent compact and detailed verdict labels

- Preserve PASS, FAIL, REVIEW and NOT_CHECKED in summary_short.csv exactly as in summary.csv. Replace the earlier binary screening mapping that made concerns and unfinished assessments look like established failures. Keep the one-file/five-category layout.
- Existing reviews can regenerate the compact table locally without API calls or changes to detailed results. Missing categories remain NOT_CHECKED; identical duplicate results collapse, while conflicting duplicate verdicts are reported rather than silently reinterpreted.
- Regression coverage verifies all four labels, incomplete calls, missing groups, duplicate handling and unchanged detailed summaries during regeneration.

## 2026-10-20 — Configurable grouped-review timeouts

- After a failed server request elapsed 180.024 seconds at the configured 180-second ceiling, expose request_timeout and connection_timeout at the top of both grouped runners. Use the agreed 600-second request limit and unchanged 20-second connection limit, passing both explicitly to curl and recording the applied settings in run/attempt metadata.
- Preserve 20,000-token grouped budgets, reasoning settings and legacy reviewer defaults. A response returns as soon as available; increasing the waiting limit is independent of increasing token budgets. First validate on BESS alone before a full retry.
- Recognize timeout wording locally when older curl versions lack a typed condition, emitting only a fixed TIMEOUT label. Test timeout validation/propagation/metadata, legacy error privacy and existing error isolation without live model calls.

## 2026-10-20 — Reliable API-failure status and safe transport diagnostics

- Correct direct/grouped review error metadata that remained NOT_COMPLETED: the error handler updated a local object while the writer read the enclosing unchanged object. Persist the updated error metadata explicitly as API_ERROR, with completion time and elapsed seconds.
- Classify known curl condition classes into fixed safe timeout, DNS, connection, TLS and transfer labels without exposing raw error messages, URLs or credentials. Existing suppressed failures cannot be retrospectively diagnosed. Preserve timeout, token, reasoning and retry settings.
- Test saved API_ERROR propagation into grouped indexes, incomplete/token-limit distinctions, elapsed timing and private-sentinel exclusion across known and unknown transport conditions. No live API calls or user credentials were used.

## 2026-10-20 — Full paper-input grouped review

- Add a configured grouped-review runner for every row in the saved paper-input scan. NULL input_rows selects the full index, while explicit pilot subsets remain supported. Preserve the selected model, 20,000-token budget, sequential calls and per-file error continuation.
- Produce detailed and compact category summaries without reopening source data. Original scans/reviews remain intact; the full run reassesses all selected rows rather than silently omitting prior pilot files or failed inputs. No additional server discovery or live model execution was performed during development.

## 2026-10-20 — Compact category screening overview

- Add summary_short.csv with one row per full data_file_path and five PASS/FAIL category columns, derived in R from the detailed grouped results without another model call. Only PASS maps to PASS; REVIEW, NOT_CHECKED and absent categories map to FAIL as screening flags requiring attention, with original meanings/explanations retained in summary.csv.
- Generate the overview at pilot checkpoints and provide a configured runner for existing saved results. Preserve original detailed reports and scans. Repeated identical paths aggregate conservatively; distinct paths remain distinct.
- Verify category mapping, missing groups, duplicate handling, automatic export and regeneration without additional API calls or modification of the detailed summary.

## 2026-10-20 — Five-category review pilot

- Add an editable prompt and separate selected-file runner using cached scans, with five independent results: variable/metadata, grid/spatial coverage, time coverage, variable values and source/processing. Require a brief concrete finding and feasible next action per group; retain detailed per-file reports and the separate numerical overview.
- Pilot PASS/FAIL/REVIEW/NOT_CHECKED categories keep missing-history documentation failures separate from numerical findings and avoid turning optional metadata or unperformed optional checks into blanket failures. Deterministic failures and essential gaps guard each category. The established single-verdict reviewer remains available.
- Start the three-file experiment with the previously chosen 20,000 completion tokens, provider-default reasoning setting and unchanged transport limits. Save API/schema completion separately, continue after individual failures and preserve original scans. No live model calls were made during implementation.
- Normalize pct/percent/% as equivalent metadata spellings; correct the known mismatch only in pilot cache copies without numerical conversion. Add mocked regression coverage for five-group schemas, category guards, private local-attribute exclusion, cached-only execution, continuation after token/schema failures and original-cache preservation.

## 2026-10-20 — Human-readable linked run folders

- Use a single random scan identifier across scan-<id>, review-<id> and numbered rerun-<id>-01 folders. Repeated reviews and refreshed scan revisions receive numbered suffixes, never overwrite prior runs, and keep explicit parent/scan identity in run-lineage.json.
- Keep existing legacy batch/retry folders usable without renaming them. Adopt their saved label for newly linked stages. No scientific checks or model settings changed.

## 2026-10-20 — Audit scan and review reliability

- Block new scans before reading values when ncdf4, CFtime or jsonlite is unavailable. Previously a missing calendar package allowed expensive scans whose temporal coverage remained unchecked.
- Correct annual-bound completeness checks for CFtime's valid date-only representation of midnight. Full calendar years no longer fail solely because the timestamp omitted T00:00:00; genuine partial intervals still fail.
- Add observed storage type to numerical evidence to avoid unsupported packing assumptions. Validate integer completion budgets and print/save the effective model/token settings without changing defaults.
- Add annual Gregorian/no-leap/360-day boundary, missing/duplicate-year, PET input, signed wind/radiation, packed-short decoding and resource-setting propagation regressions. Existing malformed-filename policy, negative-ET interpretation, timeout and token defaults are unchanged.

## 2026-10-20 — Preserve numeric CDO ranges in redacted history

- Fix path redaction that changed seltimestep,1/20 into a misleading single-timestep operation. Protect complete numeric CDO argument tokens while continuing to redact file paths and credentials; record sanitizer version in included history.
- Add a header-only refresh runner for saved diagnostics. Preserve original reports and cached statistics, regenerate corrected previews/history-derived exports in a new batch, and invalidate previous model conclusions for refreshed rows. Block source size/mtime mismatches and refresh failures before submission.
- Regression coverage checks numeric/stepped ranges, privacy redaction, unchanged scan values and original caches, no rescan/API calls, and refusal to refresh changed source files.

## 2026-10-19 — Input-table whitespace

- Trim surrounding whitespace from the optional variable-category field when reading the CSV. Whitespace-only categories are treated as unspecified, allowing inference. Preserve file paths and provenance text unchanged. Regression coverage includes quoted whitespace from spreadsheet-style exports.

## 2026-10-18 — Separate saved scans from model review

- Move reusable functions to source/ and runners to run_experiments/; add configuration templates, repository contribution/agent guidance and a current usage README.
- Add a data_file_paths.csv input table, separate path overrides and external private credential loading. Setup creates folders/templates and preserves existing configuration.
- Separate scan-only batches from later saved-evidence reviews, retaining per-file diagnostics and existing retry semantics. Checkpoint a combined deterministic data_overview.csv, preserving path-based identity and recording scan/source-file identity information.
- Preserve random run labels and existing report folders. Add synthetic stage integration covering review after source removal, missing inputs, duplicate names, API failure continuation and safe setup/credential handling.
- Keep scientific checks, token/timeout defaults, sequential execution and the sanitizer unchanged. Slash-containing operator redaction is a known follow-up, not an established scientific finding.

## 2026-10-17 — Retry and diagnostic exports

- 3ef506d: retry selected incomplete model reviews using cached diagnostics, preserving attempt budgets/usage and original results; clarify retained mask variable names.
- 67ae83b: export full missing-period lists, per-layer means/extrema, grid metadata and recorded scalar conversions.

## 2026-10-16 — Broader filename-based review

- 7fb0b24 and 1d4cbb1: derive expectations from structured filenames; support multiple variable families and harmonised raw-stage conventions with a fixed project grid.
- f7ea899: make missing/empty history a mandatory project provenance failure.
- 8199473 and 5969bee: add sequential selected-file and temperature-folder review with per-file error isolation.
- d14ce2b and 377924f: configurable input-size guard and optional reasoning controls; safe API diagnostics.
- 6977368 and 2f79066: top-of-script configuration and a separate editable direct-LLM prompt example.

Earlier initial development remains documented in Git history. Historical design notes are retained separately in batch-review-design.md and do not define current behaviour.
