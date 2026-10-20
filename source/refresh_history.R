# Refresh history from headers, retaining cached numeric diagnostics -----------
refresh_history_checks <- function(checks, input_path) {
  evidence <- attr(checks, "review_evidence")
  history <- evidence$processing_history
  if (!isTRUE(history$available)) stop("Only previously included history can be refreshed; absent/withheld history needs separate handling.")
  record <- attr(checks, "scan_record")
  if (is.null(record$before) || !isTRUE(record$source_unchanged_during_scan))
    stop("A stable source size/mtime record is required; do a fresh scan for this file.")
  if (!file.exists(input_path) || !identical(source_file_stamp(input_path), record$after))
    stop("Source file is missing or its recorded size/mtime changed; do a fresh scan instead.")
  # nc_open reads metadata/coordinates; no environmental data arrays are requested.
  nc <- ncdf4::nc_open(input_path)
  on.exit(ncdf4::nc_close(nc))
  raw <- ncdf4::ncatt_get(nc, 0, "history")
  if (!isTRUE(raw$hasatt) || !any(!is.na(raw$value) & nzchar(trimws(as.character(raw$value)))))
    stop("Previously present history is now absent; do a fresh scan.")
  refreshed <- c(list(available = TRUE), sanitize_history(raw$value))
  if (!identical(source_file_stamp(input_path), record$after)) stop("Source changed during header refresh.")
  evidence$processing_history <- refreshed
  attr(checks, "review_evidence") <- evidence
  record$history_refresh <- list(time_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    sanitizer_version = refreshed$sanitizer_version,
    scope = "History attribute only; cached numeric diagnostics unchanged; size/mtime is not a checksum")
  attr(checks, "scan_record") <- record
  checks
}

# A new batch preserves the original cache, previews and previous model results.
refresh_saved_history <- function(scan_dir, output_dir, input_rows = NULL) {
  index_file <- file.path(scan_dir, "review_index.csv")
  if (!file.exists(index_file)) stop("Set scan_dir to a batch/retry folder with review_index.csv.")
  index <- read.csv(index_file, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("input_path", "checks_status", "report_path", "llm_status", "filename", "result", "reason")
  if (!all(required %in% names(index))) stop("Index needs full input paths and saved scan records; use a newer scan.")
  if (is.null(input_rows)) input_rows <- which(index$checks_status == "COMPLETED")
  if (!is.numeric(input_rows) || anyNA(input_rows) || any(input_rows != as.integer(input_rows)) ||
      any(input_rows < 1 | input_rows > nrow(index))) stop("input_rows must be valid index row numbers.")
  if (!nzchar(output_dir)) stop("Set output_dir.")
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output directory.")
  run <- tempfile("batch-", tmpdir = output_dir); dir.create(run)
  overview_file <- file.path(scan_dir, "data_overview.csv")
  overview <- if (file.exists(overview_file)) read.csv(overview_file, stringsAsFactors = FALSE, check.names = FALSE) else NULL
  if (!is.null(overview) && nrow(overview) != nrow(index)) stop("Overview/index row mismatch; cannot safely refresh.")
  index$history_source_report_path <- index$report_path
  index$history_refresh_status <- "NOT_SELECTED"
  checkpoint <- function() {
    write.csv(index, file.path(run, "review_index.csv"), row.names = FALSE)
    write.csv(index[c("filename", "result", "reason")], file.path(run, "summary.csv"), row.names = FALSE)
    write.csv(index[index$result != "PASS", ], file.path(run, "flagged_files.csv"), row.names = FALSE)
    if (!is.null(overview)) write.csv(overview, file.path(run, "data_overview.csv"), row.names = FALSE)
  }
  for (name in c("input-files.csv", "excluded-entries.txt")) {
    file <- file.path(scan_dir, name)
    if (file.exists(file)) file.copy(file, file.path(run, name))
  }
  checkpoint()
  for (i in unique(input_rows)) {
    tryCatch({
      checks <- read_saved_checks(index$history_source_report_path[i])
      if (!isTRUE(attr(checks, "review_evidence")$processing_history$available)) {
        index$history_refresh_status[i] <- "NOT_APPLICABLE_OR_WITHHELD"
      } else {
        checks <- refresh_history_checks(checks, index$input_path[i])
        directory <- file.path(run, sprintf("file-%03d", i)); dir.create(directory)
        saveRDS(checks, file.path(directory, "local-diagnostics.rds"))
        write.csv(checks, file.path(directory, "checks.csv"), row.names = FALSE)
        write_diagnostic_tables(checks, directory)
        writeLines(as.character(prepare_review(checks)), file.path(directory, "review-preview.json"))
        index$report_path[i] <- directory
        index$llm_status[i] <- "NOT_RUN"
        summary <- review_summary(checks, "NOT_RUN")
        index$result[i] <- summary$result; index$reason[i] <- summary$reason
        index$history_refresh_status[i] <- "REFRESHED"
        if (!is.null(overview) && "recorded_operations" %in% names(overview)) {
          history <- attr(checks, "review_evidence")$processing_history
          overview$recorded_operations[i] <- history$text
          if ("history_truncated" %in% names(overview)) overview$history_truncated[i] <- history$truncated
        }
      }
    }, error = function(e) {
      index$history_refresh_status[i] <<- "ERROR"
      index$llm_status[i] <<- "PREPARATION_ERROR"
      if (index$result[i] != "FAIL") index$result[i] <<- "INCOMPLETE"
      index$reason[i] <<- paste("History refresh error:", conditionMessage(e))
    })
    checkpoint()
  }
  message("Header refresh saved to ", run, ". No data-value scan or API calls performed.")
  invisible(list(index = index, run_dir = run))
}
