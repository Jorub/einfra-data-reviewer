# Agent instructions

Read README.md and CONTRIBUTING.md before changing this repository. They contain portable project and contribution rules; do not depend on personal skills being installed. Read docs/review-policy.md before changing checks or verdict interpretation.

## Working here

- Run from the repository root. Reusable code is in source/; run_experiments/ has five configured scripts: scan_files.R, review_grouped_scans.R, summarise_grouped_review.R, merge_reviews.R and query_llm.R. Use input_rows for small review trials rather than adding another runner.
- Read-only data inspection is the product. Never modify source datasets or execute model-generated repair commands.
- Do not read real credential files or print keys for inspection. Use synthetic credentials and mocked API calls in tests. Do not submit user data to the service merely to test a code change.
- Preserve output/report folders and cached diagnostics during restructuring. Do not delete generated files that may be the user's only saved run. Follow the path-compatibility notes in docs/migration.md.
- Discuss consequential new design choices with the user before implementing dependent work. Preserve agreed defaults during structural changes. Carry existing decisions forward and handle routine authorised details autonomously.

## Validation

After dependency setup, run `Rscript tests/run_all.R`. It isolates tests in separate processes and makes no live inference calls. Parse edited R entrypoints. For a change to scan/review separation, retain the integration check that source files can be removed after scanning and model review still uses the saved evidence.

Follow CONTRIBUTING.md for commit detail, AI model attribution and docs/history.md updates. Finish with a concise account of changes, validation, remaining limitations and the next runner/settings the user needs. Never claim a live server test was performed when only synthetic tests ran.
