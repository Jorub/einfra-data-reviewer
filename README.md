# eINFRA data reviewer for RStudio

A small, read-only CSV validation and remote reasoning prototype. No local LLM or GPU is needed. Uses the eINFRA OpenAI-compatible API at `https://llm.ai.e-infra.cz/v1`.

## Start in RStudio / JupyterHub

1. Clone or upload this repository into persistent storage and open the `.Rproj`.
2. Run `source("setup.R")`. It installs only missing packages (`curl`, `jsonlite`, `getPass`) and verifies they are available; installed packages are not updated.
3. Open `start_here.R` and run the synthetic offline example section by section.
4. Run `set_api_key()` interactively: the hidden prompt keeps the key in process memory only. The key is never saved by this project. Do not paste it into code, chat, notebooks, or console commands.
5. `list_models()` checks server network access and authentication. Choose an available model; aliases can change.
6. Inspect `prepare_review(checks)` and explicitly pass that exact preview to `review_checks(..., send = TRUE, report_dir = chosen_path)`. Only the displayed validation summary is submitted; no raw CSV, file path, actual column names or source code is included by the built-in checker.
7. Read local reports and run `clear_api_key()` when finished.

## Scope and limits

Current checks: required columns, nonempty table, duplicate column names, finite numeric values, caller-defined ranges and unique keys. Ranges are explicit scientific contracts, not model guesses. Dates, units, NetCDF metadata, checksums, processing comparisons and code review are future extensions; this prototype does not check them. Only CSV inputs should be used. It does not execute RDS files or model-generated commands and never modifies inputs. PASS is not proof of correct science. Model output is advice and cannot override failed numerical checks. No automated remediation or agent loop is provided.

The API models cannot inspect server files, browse or run tools through this client. Current availability and container outbound network access must be tested in your own environment. There has been no live-key test from your server.

## Credential and report handling

The public repository contains no real key or project data. Credentials are held in a private R environment, never in request bodies or saved reports. HTTP error bodies and low-level connection details are suppressed. Workspace/history saving is disabled in the supplied RStudio project; do not manually save the R session while a key is loaded. Any code running under your account can potentially inspect R memory: this is not a credential vault. Use your own account/key in a trusted container.

Only approved summary text is sent remotely. Reports may still be sensitive and must remain in private persistent storage; `reports/`, `data/`, `private/`, history and common credential files are Git-ignored. Git-ignore is a convenience, not a guarantee: inspect staged changes before publishing. Custom callers can supply arbitrary check details, so always review the outgoing preview. Do not enable HTTP debugging.

API calls are bounded to 16 kB summary text and a chosen completion budget. Usage and finish reason are saved. Failed or truncated calls are explicitly incomplete; no automatic retries. Reports retain deterministic results separately from model interpretation.

## Tests

`Rscript tests/test_offline.R`

Uses synthetic data and a clearly fake credential sentinel; no network or real secrets.

## Provenance

Prepared with Codex assistance, adapting the design of the user's local eINFRA offload client. No credentials were read or copied. Official service documentation: https://docs-ng.cerit.io/en/docs/ai-as-a-service/chat-ai

## User-supplied paths

Select a CSV with `file.choose()` or pass its path to `check_csv(path = ...)`. Use `check_files(paths = ...)` for multiple CSVs sharing a validation contract. Supply `report_dir` explicitly when calling the API reviewer. No machine-specific data directory is embedded in the program. Input paths remain local and are omitted from built-in review summaries. Keep reports outside the public Git checkout when possible. The relative `source("R/reviewer.R")` identifies project code, not a data location.
