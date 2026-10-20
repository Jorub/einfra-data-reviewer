# Development history

Meaningful milestones, reconstructed from Git commits where applicable. Git history holds detailed changes; README.md describes current usage.

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
