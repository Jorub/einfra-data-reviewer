source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

work <- tempfile(); dir.create(work)
scan <- file.path(work, "scan-concurrent"); dir.create(scan)
index <- data.frame(filename = sprintf("sample%d_e_mm_region_200001_200112_025_yearly.nc", 1:10),
  checks_status = "COMPLETED", report_path = file.path(scan, paste0("file-", 1:10)),
  input_path = paste0("/fake/input-", 1:10, ".nc"))
index$checks_status[7] <- "ERROR"
for (i in 1:10) {
  dir.create(index$report_path[i])
  checks <- data.frame(check = c("filename_format", "data_variable", "coordinate_dimensions",
    "time_coverage", "nonfinite_values", "history_provenance"), status = "PASS", detail = "Synthetic evidence")
  attr(checks, "review_evidence") <- list(filename = list(basename = index$filename[i], fields = list(units = "mm")),
    observed = list(variable = "e", units = "mm"))
  attr(checks, "local_tool_results") <- list(private = "FAKE_LOCAL_ONLY_SENTINEL")
  saveRDS(checks, file.path(index$report_path[i], "local-diagnostics.rds"))
}
write.csv(index, file.path(scan, "review_index.csv"), row.names = FALSE)
source_files <- list.files(scan, recursive = TRUE, full.names = TRUE)
before <- tools::md5sum(source_files)
valid <- jsonlite::toJSON(list(results = lapply(grouped_check_names(), function(group)
  list(group = group, result = "PASS", finding = "Synthetic inspected evidence", next_action = "None required."))), auto_unbox = TRUE)
check_netcdf <- function(...) stop("Unexpected NetCDF scan")
set_api_key <- function(...) stop("Unexpected credentials read")
pool_calls <- 0L; last_pool <- NULL; interrupt_mode <- FALSE
grouped_request_pool <- function(limit) {
  pool_calls <<- pool_calls + 1L
  p <- new.env(parent = emptyenv())
  p$pending <- list(); p$started <- integer(); p$completed <- integer(); p$cancelled <- integer()
  p$peak <- 0L; p$polls <- 0L; p$limit <- limit
  last_pool <<- p
  p
}
api_request_async <- function(route, payload, pool, done, fail, request_timeout, connection_timeout) {
  stopifnot(request_timeout == 600, connection_timeout == 20, payload$max_tokens == 20000L,
    !grepl("FAKE_LOCAL_ONLY_SENTINEL", payload$messages[[1]]$content, fixed = TRUE))
  id <- as.integer(sub(".*sample([0-9]+)_e_mm.*", "\\1", payload$messages[[1]]$content))
  pool$started <- c(pool$started, id)
  if (id == 10) stop("Synthetic client transport initialization failure")
  pool$pending[[as.character(id)]] <- list(done = done, fail = fail)
  pool$peak <- max(pool$peak, length(pool$pending))
  stopifnot(length(pool$pending) <= pool$limit)
  id
}
cancel_grouped_request <- function(handle) {
  last_pool$cancelled <- c(last_pool$cancelled, handle)
  last_pool$pending[[as.character(handle)]] <- NULL
}
poll_grouped_requests <- function(pool) {
  pool$polls <- pool$polls + 1L
  if (interrupt_mode && pool$polls == 2L)
    stop(structure(list(message = "Synthetic interruption", call = NULL), class = c("interrupt", "condition")))
  if (pool$polls == 1L) stopifnot(identical(pool$started, 1:4))
  # Complete in reverse order: the first slow request remains active until last.
  id <- as.integer(tail(names(pool$pending), 1))
  job <- pool$pending[[as.character(id)]]; pool$pending[[as.character(id)]] <- NULL
  pool$completed <- c(pool$completed, id)
  if (id == 2) job$fail(simpleError("API connection failed [TIMEOUT]; raw details suppressed.")) else
    if (id == 4) job$fail(simpleError(http_error_summary(429, charToRaw("FAKE_PROVIDER_SECRET")))) else {
      content <- if (id == 5) "{}" else if (id == 8) "" else as.character(valid)
      job$done(list(model = "fake", choices = list(list(finish_reason = if (id == 3) "length" else "stop",
        message = list(content = content))), usage = list(completion_tokens = 100)))
    }
  # Every completion must be saved before the next poll/refill; only one writer.
  run <- list.dirs(work, recursive = FALSE, full.names = TRUE)
  run <- tail(run[grepl("/review-", run)], 1)
  saved <- read.csv(file.path(run, "pilot_index.csv"))
  stopifnot(saved$llm_status[id] != "IN_PROGRESS",
    file.exists(file.path(saved$report_path[id], "group-results.csv")))
}
preview <- run_grouped_pilot(scan, work, max_concurrent_requests = 4, send_to_api = FALSE)
stopifnot(pool_calls == 0L, all(preview$index$llm_status[c(1:6, 8:10)] == "NOT_RUN"))
trial <- run_grouped_pilot(scan, work, model = "fake", max_concurrent_requests = 4, send_to_api = TRUE)
stopifnot(last_pool$peak == 4L, identical(last_pool$started, c(1:6, 8:10)),
  tail(last_pool$completed, 1) == 1L, length(last_pool$cancelled) == 0,
  identical(trial$index$llm_status, c("COMPLETED", "API_ERROR", "TOKEN_LIMIT", "API_ERROR",
    "INVALID_RESPONSE", "COMPLETED", "PREPARATION_ERROR", "INCOMPLETE", "COMPLETED", "API_ERROR")),
  !grepl("FAKE_PROVIDER_SECRET", trial$index$reason[4], fixed = TRUE),
  identical(before, tools::md5sum(source_files)))
summary <- read.csv(file.path(trial$run_dir, "summary.csv"))
short <- read.csv(file.path(trial$run_dir, "summary_short.csv"))
stopifnot(nrow(summary) == 50, nrow(short) == 10, identical(short$data_file_path, index$input_path),
  all(short[1, -1] == "PASS"), all(short[2, -1] == "NOT_CHECKED"))
settings <- jsonlite::read_json(file.path(trial$run_dir, "pilot-settings.json"))
stopifnot(settings$max_concurrent_requests == 4)
# Clean interruption cancels active local handles and retains completed checkpoints.
interrupt_mode <- TRUE
interrupted <- tryCatch(run_grouped_pilot(scan, work, model = "fake", max_concurrent_requests = 4,
  send_to_api = TRUE), interrupt = identity)
stopifnot(inherits(interrupted, "interrupt"), setequal(last_pool$cancelled, c(1L, 2L, 3L, 5L)))
runs <- list.dirs(work, recursive = FALSE, full.names = TRUE)
latest <- tail(runs[grepl("/review-", runs)], 1)
saved <- read.csv(file.path(latest, "pilot_index.csv"))
stopifnot(saved$llm_status[4] == "API_ERROR", all(saved$llm_status[c(1, 2, 3, 5)] == "INTERRUPTED"),
  nrow(read.csv(file.path(latest, "summary.csv"))) == 5)
for (invalid in list(0, 5, 1.5, NA_real_, Inf, "4", numeric()))
  stopifnot(inherits(try(validate_review_concurrency(invalid), silent = TRUE), "try-error"))
unlink(work, recursive = TRUE)
cat("Concurrent grouped review passed: four-slot cap, queue refill, out-of-order identity/checkpoints, errors, preview privacy and interrupt cancellation. No live API calls.\n")
