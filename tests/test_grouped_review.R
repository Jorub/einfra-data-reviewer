source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

# Five exact groups; reject missing, duplicate or unexpected fields/results.
response <- list(results = lapply(grouped_check_names(), function(group) list(group = group, result = "PASS",
  finding = paste("Synthetic supplied checks inspected for", group), next_action = "None required.")))
text <- as.character(jsonlite::toJSON(response, auto_unbox = TRUE))
parsed <- parse_grouped_response(text)
stopifnot(nrow(parsed) == 5, all(parsed$result == "PASS"))
bad <- response; bad$results[[5]]$group <- bad$results[[1]]$group
stopifnot(is.null(parse_grouped_response(jsonlite::toJSON(bad, auto_unbox = TRUE))))
bad <- response; bad$results[[1]]$finding <- ""
stopifnot(is.null(parse_grouped_response(jsonlite::toJSON(bad, auto_unbox = TRUE))))

checks <- data.frame(check = c("filename_format", "coordinate_dimensions", "data_variable", "filename_units",
  "time_coverage", "nonfinite_values", "history_provenance"), status = "PASS", detail = "Synthetic checked evidence")
attr(checks, "review_evidence") <- list(filename = list(basename = "synthetic_e_mm_region_200001_200112_025_yearly.nc",
  fields = list(units = "mm")), observed = list(variable = "e", units = "mm"))
attr(checks, "local_tool_results") <- list(private = "FAKE_LOCAL_PATH_NOT_FOR_MODEL")
protected <- checks; protected$status[protected$check == "history_provenance"] <- "FAIL"
protected$detail[protected$check == "history_provenance"] <- "Required history is absent"
results <- guard_grouped_results(protected, parsed)
stopifnot(results$result[results$group == "source_and_processing"] == "FAIL",
  all(results$result[results$group != "source_and_processing"] == "PASS"))
# Unavailable time checks cannot become a model PASS.
gap <- checks; gap$status[gap$check == "time_coverage"] <- "NOT_CHECKED"
stopifnot(guard_grouped_results(gap, parsed)$result[3] == "NOT_CHECKED")
# A malformed filename does not establish missing history or any contents finding.
malformed <- checks[1, ]; malformed$status <- "FAIL"
results <- guard_grouped_results(malformed, parsed)
stopifnot(results$result[1] == "FAIL", all(results$result[2:5] == "NOT_CHECKED"))
# pct/percent is a known equivalence, not a data correction or numeric rescale.
percent <- checks
attr(percent, "review_evidence")$filename$fields$units <- "pct"
attr(percent, "review_evidence")$observed$units <- "percent"
percent$status[percent$check == "filename_units"] <- "FAIL"
normal <- grouped_checks(percent)
stopifnot(percent$status[percent$check == "filename_units"] == "FAIL",
  normal$status[normal$check == "filename_units"] == "PASS",
  canonical_units("pct") == canonical_units("percent"), canonical_units("%") == "percent")
blank <- percent
attr(blank, "review_evidence")$filename$fields$units <- ""
attr(blank, "review_evidence")$observed$units <- ""
stopifnot(grouped_checks(blank)$status[blank$check == "filename_units"] == "FAIL")
prompt <- prepare_grouped_review(checks)
stopifnot(!grepl("FAKE_LOCAL_PATH_NOT_FOR_MODEL", prompt, fixed = TRUE))

work <- tempfile(); dir.create(work)
scan <- file.path(work, "scan-fixture"); dir.create(scan)
inputs <- list(checks, protected, percent)
index <- data.frame(filename = c("first.nc", "second.nc", "third.nc"), checks_status = "COMPLETED",
  report_path = file.path(scan, paste0("file-", 1:3)), input_path = paste0("/fake/", 1:3, ".nc"))
for (i in 1:3) {
  dir.create(index$report_path[i]); saveRDS(inputs[[i]], file.path(index$report_path[i], "local-diagnostics.rds"))
}
write.csv(index, file.path(scan, "review_index.csv"), row.names = FALSE)
before <- tools::md5sum(file.path(scan, "review_index.csv"))
# No API calls during preview; no NetCDF access at any point.
check_netcdf <- function(...) stop("Unexpected rescan")
api_calls <- 0L
api_request <- function(...) stop("No API allowed in preview")
preview <- run_grouped_pilot(scan, work, 1:3, send_to_api = FALSE)
stopifnot(all(preview$index$llm_status == "NOT_RUN"))
api_request <- function(route, payload) {
  api_calls <<- api_calls + 1L
  stopifnot(payload$max_tokens == 20000L)
  if (api_calls == 1) return(list(model = "fake", choices = list(list(finish_reason = "length",
    message = list(content = ""))), usage = list(completion_tokens = 20000)))
  content <- if (api_calls == 2) text else '{"results":[]}'
  list(model = "fake", choices = list(list(finish_reason = "stop", message = list(content = content))),
    usage = list(completion_tokens = 100))
}
trial <- run_grouped_pilot(scan, work, 1:3, model = "fake", send_to_api = TRUE)
summary <- read.csv(file.path(trial$run_dir, "summary.csv"))
short <- read.csv(file.path(trial$run_dir, "summary_short.csv"))
stopifnot(nrow(short) == 3, identical(names(short), c("data_file_path", grouped_check_names())),
  all(short[1, -1] == "FAIL"), all(short[3, -1] == "FAIL"),
  all(short[2, 2:5] == "PASS"), short$source_and_processing[2] == "FAIL")
# REVIEW and unperformed/missing groups cannot become a binary PASS; duplicates
# of the same file collapse conservatively, preserving full path identity.
mixed <- summary[summary$data_file_path == "/fake/2.nc", ]
mixed$result[1] <- "REVIEW"
mixed <- rbind(mixed, transform(mixed[2, ], result = "NOT_CHECKED"))
mixed <- mixed[mixed$check_group != "time_coverage", ]
binary <- grouped_short_summary(mixed)
stopifnot(nrow(binary) == 1, all(binary[1, 2:4] == "FAIL"), binary$variable_values == "PASS")
before_summary <- tools::md5sum(file.path(trial$run_dir, "summary.csv"))
unlink(file.path(trial$run_dir, "summary_short.csv"))
write_grouped_short_summary(trial$run_dir)
stopifnot(identical(before_summary, tools::md5sum(file.path(trial$run_dir, "summary.csv"))),
  identical(short, read.csv(file.path(trial$run_dir, "summary_short.csv"))), api_calls == 3)
stopifnot(api_calls == 3, identical(trial$index$llm_status, c("TOKEN_LIMIT", "COMPLETED", "INVALID_RESPONSE")),
  nrow(summary) == 15, identical(names(summary), c("data_file_path", "check_group", "result", "finding", "next_action")),
  all(summary$result[summary$data_file_path == "/fake/1.nc"] == "NOT_CHECKED"),
  sum(summary$result[summary$data_file_path == "/fake/2.nc"] == "FAIL") == 1,
  all(summary$result[summary$data_file_path == "/fake/3.nc"] == "NOT_CHECKED"),
  identical(before, tools::md5sum(file.path(scan, "review_index.csv"))))
unlink(work, recursive = TRUE)
cat("Grouped pilot passed: exact five-group schema, per-group guards, known unit equivalence, preview privacy, cached-only execution, token/schema errors and preserved scans. No live API calls.\n")
