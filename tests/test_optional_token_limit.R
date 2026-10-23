source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")
source("source/rerun.R")

work <- tempfile(); dir.create(work)
# Omission is different from sending JSON null, zero or an invented numeric cap.
for (budget in list(NULL, 20000L)) {
  payload <- review_request("synthetic", "test", budget)
  encoded <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
  stopifnot(identical("max_tokens" %in% names(payload), !is.null(budget)),
    identical(grepl('"max_tokens"', encoded, fixed = TRUE), !is.null(budget)))
}
validate_completion_budget(NULL)
for (bad in list(NA_real_, Inf, numeric(), c(20000, 30000), "20000", 0, 12.5))
  stopifnot(inherits(try(validate_completion_budget(bad), silent = TRUE), "try-error"))
stopifnot(format_completion_budget(NULL) == "provider default (max_tokens omitted)",
  format_completion_budget(20000L) == "20000")
requests <- list(); response_text <- "Synthetic response"; finish <- "stop"; fail <- FALSE
api_request <- function(route, payload, ...) {
  requests[[length(requests) + 1L]] <<- payload
  if (fail) stop("Synthetic transport failure")
  list(model = "synthetic", choices = list(list(finish_reason = finish, message = list(content = response_text))),
    usage = list(completion_tokens = 1234, prompt_tokens = 100, total_tokens = 1334))
}
set_api_key <- function(...) stop("Unexpected credential access")
for (budget in list(NULL, 20000L)) {
  answer <- ask_llm("Synthetic task", "synthetic", work, "Synthetic task", send = TRUE,
    max_tokens = budget, request_timeout = 600, connection_timeout = 20)
  metadata <- jsonlite::read_json(file.path(answer$run_dir, "metadata.json"))
  stopifnot(identical("max_tokens" %in% names(tail(requests, 1)[[1]]), !is.null(budget)),
    "max_tokens" %in% names(metadata), identical(metadata$max_tokens, budget),
    metadata$max_tokens_source == if (is.null(budget)) "provider_default" else "explicit",
    metadata$usage$completion_tokens == 1234, metadata$request_timeout == 600, metadata$connection_timeout == 20)
}
# Provider defaults can still produce a length finish; never mark that complete or infer its cap from usage.
finish <- "length"
limited <- file.path(work, "length")
stopifnot(inherits(try(ask_llm("test", "synthetic", limited, "test", send = TRUE, max_tokens = NULL), silent = TRUE), "try-error"))
attempt <- list.dirs(limited, recursive = FALSE, full.names = TRUE)[1]
metadata <- jsonlite::read_json(file.path(attempt, "metadata.json"))
stopifnot(metadata$status == "TOKEN_LIMIT", is.null(metadata$max_tokens), metadata$max_tokens_source == "provider_default",
  is.null(retry_budget(metadata, 8192L)$tokens), metadata$usage$completion_tokens == 1234)
finish <- "stop"; fail <- TRUE
failed <- file.path(work, "error")
stopifnot(inherits(try(ask_llm("test", "synthetic", failed, "test", send = TRUE, max_tokens = NULL), silent = TRUE), "try-error"))
attempt <- list.dirs(failed, recursive = FALSE, full.names = TRUE)[1]
metadata <- jsonlite::read_json(file.path(attempt, "metadata.json"))
stopifnot(metadata$status == "API_ERROR", is.null(metadata$max_tokens), metadata$max_tokens_source == "provider_default")
fail <- FALSE
# Shared single-verdict wrapper records the same optional-limit semantics.
checks <- data.frame(check = c("filename_format", "data_variable", "coordinate_dimensions", "time_coverage", "nonfinite_values", "history_provenance"),
  status = "PASS", detail = "Synthetic inspected evidence")
attr(checks, "review_evidence") <- list(filename = list(basename = "synthetic_e_mm_land_200001_200112_025_yearly.nc",
  fields = list(units = "mm", spatial_coverage = "land")), observed = list(variable = "e", units = "mm"),
  processing_history = list(available = TRUE, text = "cdo mul oceanmask_ithaca_global_025.nc input.nc output.nc"))
response_text <- as.character(jsonlite::toJSON(list(verdict = "PASS", reason = "Synthetic inspected evidence.", report_markdown = "Synthetic report."), auto_unbox = TRUE))
review <- review_checks(checks, "synthetic", prepare_review(checks), send = TRUE, report_dir = work, max_tokens = NULL)
metadata <- jsonlite::read_json(file.path(review, "metadata.json"))
stopifnot(is.null(metadata$max_tokens), metadata$max_tokens_source == "provider_default",
  !"max_tokens" %in% names(tail(requests, 1)[[1]]))
# The legacy retry helper preserves explicit omission rather than reinstating a numeric fallback or doubling usage.
old <- file.path(work, "old-review"); dir.create(old)
old_report <- file.path(old, "file-001"); dir.create(old_report)
saveRDS(checks, file.path(old_report, "local-diagnostics.rds"))
jsonlite::write_json(list(max_tokens = NULL, max_tokens_source = "provider_default", requested_model = "synthetic",
  llm_status = "TOKEN_LIMIT", finish_reason = "length", usage = list(completion_tokens = 1234)),
  file.path(old_report, "metadata.json"), auto_unbox = TRUE, null = "null")
write.csv(data.frame(filename = "synthetic.nc", checks_status = "COMPLETED", llm_status = "TOKEN_LIMIT",
  result = "INCOMPLETE", reason = "Synthetic previous length limit", report_path = old_report),
  file.path(old, "review_index.csv"), row.names = FALSE)
before_calls <- length(requests)
retried <- rerun_llm_reviews(old, work, send_to_api = TRUE)
attempts <- read.csv(file.path(retried$run_dir, "attempts.csv"))
stopifnot(length(requests) == before_calls + 1, all(is.na(attempts$requested_max_tokens)),
  attempts$budget_source[2] == "provider default (max_tokens omitted)", retried$index$llm_status == "COMPLETED")
# Current grouped review: saved scans only, unchanged timeout/concurrency, strict six-group response.
scan <- file.path(work, "scan-optional-limit"); dir.create(scan)
report <- file.path(scan, "file-001"); dir.create(report)
saveRDS(checks, file.path(report, "local-diagnostics.rds"))
write.csv(data.frame(filename = "synthetic.nc", input_path = "/synthetic/file.nc", checks_status = "COMPLETED", report_path = report),
  file.path(scan, "review_index.csv"), row.names = FALSE)
response_text <- as.character(jsonlite::toJSON(list(results = lapply(grouped_check_names(), function(group)
  list(group = group, result = "PASS", finding = "Synthetic checked evidence.", next_action = "None required."))), auto_unbox = TRUE))
trial <- run_grouped_pilot(scan, work, input_rows = 1, send_to_api = TRUE, max_tokens = NULL)
settings <- jsonlite::read_json(file.path(trial$run_dir, "pilot-settings.json"))
stopifnot(is.null(settings$max_tokens), settings$max_tokens_source == "provider_default",
  settings$request_timeout == 600, settings$connection_timeout == 20, settings$max_concurrent_requests == 1,
  trial$index$llm_status == "COMPLETED", !"max_tokens" %in% names(tail(requests, 1)[[1]]))
# The configured script opts in explicitly; numeric defaults of existing function callers are preserved.
expressions <- parse("run_experiments/review_grouped_scans.R")
assignment <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) && identical(x[[2]], as.name("max_tokens")), as.list(expressions))
stopifnot(length(assignment) == 1, is.null(assignment[[1]][[3]]))
unlink(work, recursive = TRUE)
cat("Optional token limit passed: true JSON omission, explicit budgets, metadata/usage, length/API failures, provider-default retries and six-group saved-scan review. No credentials or live inference.\n")
