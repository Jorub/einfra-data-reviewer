source("source/run_paths.R")

# Saved scans -----------------------------------------------------------------
read_saved_checks <- function(report_path) {
  cache <- file.path(report_path, "local-diagnostics.rds")
  if (!file.exists(cache)) cache <- file.path(dirname(report_path), "local-diagnostics.rds")
  if (!file.exists(cache)) stop("Cached diagnostics not found; a fresh scan is required for this file.")
  readRDS(cache)
}

# Review without reopening source files ---------------------------------------
review_saved_scans <- function(scan_dir, output_dir, model = "thinker", max_tokens = 8192L,
                               reasoning_effort = NULL, max_input_bytes = 64000L, send_to_api = FALSE) {
  validate_completion_budget(max_tokens)
  file <- file.path(scan_dir, "review_index.csv")
  if (!file.exists(file)) stop("Saved scan review_index.csv not found.")
  index <- read.csv(file, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("filename", "checks_status", "llm_status", "result", "reason", "report_path")
  if (!all(required %in% names(index))) stop("Unsupported saved scan index schema.")
  if (!nzchar(output_dir)) stop("Set output_dir.")
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output directory.")
  run <- linked_run_directory(scan_dir, output_dir, "review")
  index$source_report_path <- index$report_path
  # Failed initial calls belong in rerun_reviews.R; do not repeat completed reviews.
  selected <- which(index$checks_status == "COMPLETED" & index$llm_status %in%
    c("NOT_RUN", "NOT_COMPLETED", "PENDING"))
  checkpoint <- function() {
    write.csv(index, file.path(run, "review_index.csv"), row.names = FALSE)
    write.csv(index[c("filename", "result", "reason")], file.path(run, "summary.csv"), row.names = FALSE)
    write.csv(index[index$result != "PASS", ], file.path(run, "flagged_files.csv"), row.names = FALSE)
  }
  # Preserve the deterministic overview exactly; reviews do not invent missing scan fields.
  for (name in c("data_overview.csv", "input-files.csv", "excluded-entries.txt")) {
    origin <- file.path(scan_dir, name)
    if (file.exists(origin)) file.copy(origin, file.path(run, name), overwrite = FALSE)
  }
  jsonlite::write_json(list(model = model, max_tokens = max_tokens, reasoning_effort = reasoning_effort,
    max_input_bytes = max_input_bytes, send_to_api = send_to_api, selected_files = length(selected),
    source_scan_dir = scan_dir, time_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)),
    file.path(run, "review-settings.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  message("Effective review settings: model=", model, "; max_tokens=", max_tokens,
    "; selected files=", length(selected), "; send_to_api=", send_to_api)
  checkpoint()
  for (i in selected) {
    message("Saved review ", i, "/", nrow(index), ": ", index$filename[i])
    local_dir <- file.path(run, sprintf("file-%03d", i)); dir.create(local_dir)
    tryCatch({
      checks <- read_saved_checks(index$source_report_path[i])
      preview <- prepare_review(checks)
      saveRDS(checks, file.path(local_dir, "local-diagnostics.rds"))
      write.csv(checks, file.path(local_dir, "checks.csv"), row.names = FALSE)
      write_diagnostic_tables(checks, local_dir)
      writeLines(as.character(preview), file.path(local_dir, "review-preview.json"))
      index$report_path[i] <- local_dir
      if (send_to_api) {
        failure <- NULL
        report <- tryCatch(review_checks(checks, model = model, approved_payload = preview, send = TRUE,
          report_dir = local_dir, max_tokens = max_tokens, reasoning_effort = reasoning_effort,
          max_input_bytes = max_input_bytes), error = function(e) { failure <<- conditionMessage(e); NULL })
        if (is.null(report)) {
          attempts <- list.dirs(local_dir, recursive = FALSE, full.names = TRUE)
          found <- attempts[file.exists(file.path(attempts, "review_index.csv"))]
          if (length(found)) report <- found[1]
        }
        if (!is.null(report)) {
          row <- read.csv(file.path(report, "review_index.csv"), stringsAsFactors = FALSE)
          for (field in c("llm_status", "result", "reason")) index[i, field] <- row[1, field]
          index$report_path[i] <- report
        } else {
          row <- review_summary(checks, "REQUEST_ERROR")
          index$llm_status[i] <- "REQUEST_ERROR"; index$result[i] <- row$result
          index$reason[i] <- paste(row$reason, failure, sep = "; ")
        }
        if (!is.null(failure)) writeLines(failure, file.path(local_dir, "review-error.txt"))
      }
    }, error = function(e) {
      index$llm_status[i] <<- "PREPARATION_ERROR"
      if (index$result[i] != "FAIL") index$result[i] <<- "INCOMPLETE"
      index$reason[i] <<- paste(index$reason[i], "Saved review error:", conditionMessage(e))
    })
    checkpoint()
  }
  message("Saved review results: ", run, ". No source data were opened.")
  invisible(list(index = index, run_dir = run))
}
