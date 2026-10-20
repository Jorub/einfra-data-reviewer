# Development history

Meaningful milestones, reconstructed from Git commits where applicable. Git history holds detailed changes; README.md describes current usage.

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
