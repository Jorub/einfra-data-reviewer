# Contributing

Read README.md and docs/review-policy.md before changing scientific checks. This project supports read-only diagnostics and optional model interpretation; do not repair source data automatically.

## Organisation and R style

Put reusable functions in meaningful scripts under source/ and execution scripts under run_experiments/. Run scripts from the repository root. Keep dependencies/setup work in setup.R, not in every runner. Prefer existing data idioms and simple functions.

Execution script order: library calls, source calls, configuration, execution. Keep editable variables together immediately below sources. Use RStudio section headers (`# Main section -----`, `## Subsection -----`), spaces around `=` and after commas, and compact readable formatting. Avoid needless line breaks, deep nesting or dense one-liners. Do not reformat unrelated code during a small change.

Machine-specific paths belong in ignored config/paths.local.R; shared relative paths and approved file tables can be versioned. Credentials belong in a separate private file outside the checkout. No interactive file/key prompts. Missing configuration should produce clear instructions without exposing values.

## Validation

Run `Rscript tests/run_all.R` after setup. It starts each test in a separate process to isolate mocks. The suite includes synthetic NetCDF checks, CSV checks, request/schema validation, batch continuation, retries, setup and saved-scan integration. No live credentials or paid/service inference are required. Parse changed runners and inspect their top configuration blocks. Report unrun checks and environmental limitations honestly.

Changing scientific policy, sampling, transformations, verdict criteria, timeout/budget/retry defaults, concurrency or data disclosure requires discussion before implementation. Routine implementation details within agreed scope do not need repeated confirmation. Consider shared-server CPU, memory and storage I/O when proposing concurrency.

## Privacy and generated files

Never commit real credentials, data arrays, private configuration or local scan/review outputs. output/ and common report/config paths are ignored, but ignore rules are not a guarantee. Inspect staged diffs and new files before publishing. Basenames and approved evidence are sent to eINFRA; paths and raw tool outputs stay local by default. Redaction has known limitations: inspect previews and preserve scientific operator syntax. Never print a key to test configuration.

Keep existing reports and source files intact during migrations. Full paths in local indexes identify files with equal basenames. Cached reviews intentionally do not reopen source files; use fresh scans after input/checker changes and do not claim automatic freshness verification.

## Commits and review

Keep commits coherent. Explain what changed and why, with relevant validation and material limitations; simple changes do not need a long template. Inspect staged content and exclude unrelated user changes. Follow existing branch conventions or an explicitly agreed branch; do not rewrite published history or push without task authorization. No mandatory prefix or PR template is imposed.

AI-assisted commits must identify at least the actual contributing model. Reasoning settings are optional. For work performed with the model agreed in this project, a clear body footer is:

```text
AI-assisted-by: GPT-6.1 Sol
```

Credit a different actual model when applicable; do not invent an email address or credit AI for unrelated human work. PR descriptions should state the resulting behaviour, validation and important limitations.

Update README.md when current setup/usage/outputs change. Record meaningful milestones and decisions in docs/history.md, without copying every small commit or conversation. Keep the README's AI-assistance statement accurate. Do not retrofit old commit attribution by rewriting history.
