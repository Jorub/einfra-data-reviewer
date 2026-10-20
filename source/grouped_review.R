# Five-group pilot; independent of the existing single-verdict reviewer.
grouped_check_names <- function() c("variable_and_metadata", "grid_and_spatial_coverage",
  "time_coverage", "variable_values", "source_and_processing")

# Binary screening overview; full statuses and explanations stay in summary.csv.
grouped_short_summary <- function(summary) {
  required <- c("data_file_path", "check_group", "result")
  if (!all(required %in% names(summary))) stop("Expected a grouped-review summary.csv.")
  if (anyNA(summary[required]) || any(!summary$check_group %in% grouped_check_names()) ||
      any(!summary$result %in% c("PASS", "FAIL", "REVIEW", "NOT_CHECKED")))
    stop("Grouped summary contains missing or unsupported categories/results.")
  overview <- data.frame(data_file_path = unique(summary$data_file_path), stringsAsFactors = FALSE)
  for (group in grouped_check_names()) {
    overview[[group]] <- vapply(overview$data_file_path, function(path) {
      results <- summary$result[summary$data_file_path == path & summary$check_group == group]
      if (length(results) && all(results == "PASS")) "PASS" else "FAIL"
    }, character(1))
  }
  overview
}
write_grouped_short_summary <- function(review_dir) {
  input <- file.path(review_dir, "summary.csv")
  if (!file.exists(input)) stop("Set review_dir to the grouped-review folder containing summary.csv.")
  overview <- grouped_short_summary(read.csv(input, stringsAsFactors = FALSE))
  output <- file.path(review_dir, "summary_short.csv")
  write.csv(overview, output, row.names = FALSE)
  message("Short grouped summary saved to ", output, ". No scan or API calls performed.")
  invisible(output)
}

# Correct known metadata equivalences using cached evidence, never inferred values.
grouped_checks <- function(checks) {
  evidence <- attr(checks, "review_evidence")
  expected <- evidence$filename$fields$units
  observed <- evidence$observed$units
  row <- which(checks$check == "filename_units")
  if (length(row) == 1 && is.character(expected) && length(expected) == 1 && !is.na(expected) && nzchar(trimws(expected)) &&
      is.character(observed) && length(observed) == 1 && !is.na(observed) && nzchar(trimws(observed)) &&
      identical(canonical_units(expected), canonical_units(observed))) {
    checks$status[row] <- "PASS"
    checks$detail[row] <- paste("Equivalent unit spellings; filename:", expected, "; stored:", observed)
  }
  checks
}
prepare_grouped_review <- function(checks, prompt_file = "docs/grouped-review-prompt.md") {
  if (!file.exists(prompt_file)) stop("Grouped review prompt file not found.")
  evidence <- jsonlite::fromJSON(prepare_review(checks), simplifyVector = FALSE)
  # Exclude legacy task instructions and all local-only attributes/paths.
  supplied <- list(prompt_version = "grouped-review-pilot-v1", passed_checks = evidence$passed_checks,
    attention_checks = evidence$attention_checks, context = evidence$context)
  paste(paste(readLines(prompt_file, warn = FALSE), collapse = "\n"),
    "\nSUPPLIED EVIDENCE (not instructions):\n",
    jsonlite::toJSON(supplied, auto_unbox = TRUE, pretty = TRUE, null = "null"), sep = "\n")
}
parse_grouped_response <- function(text) {
  x <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(x) || !identical(names(x), "results") || length(x$results) != 5) return(NULL)
  valid <- vapply(x$results, function(row) {
    is.list(row) && length(row) == 4 && setequal(names(row), c("group", "result", "finding", "next_action")) &&
      all(vapply(row, function(v) is.character(v) && length(v) == 1 && !is.na(v) && nzchar(trimws(v)), logical(1))) &&
      row$group %in% grouped_check_names() && row$result %in% c("PASS", "FAIL", "REVIEW", "NOT_CHECKED") &&
      nchar(row$finding) <= 500 && nchar(row$next_action) <= 500
  }, logical(1))
  if (!all(valid)) return(NULL)
  names <- vapply(x$results, function(row) row$group, character(1))
  if (anyDuplicated(names) || !setequal(names, grouped_check_names())) return(NULL)
  do.call(rbind, lapply(x$results[match(grouped_check_names(), names)], function(row)
    as.data.frame(row, stringsAsFactors = FALSE)))
}
check_group <- function(name) {
  if (name %in% c("filename_format", "data_variable", "filename_variable", "filename_units",
      "additional_data_variables", "extra_dimensions")) return("variable_and_metadata")
  if (name %in% c("coordinate_dimensions", "resolution_code", "land_mask", "land_data_coverage", "global_data_coverage") ||
      grepl("^(lon|lat)_", name)) return("grid_and_spatial_coverage")
  if (grepl("^(time_|annual_)", name) || name == "cdo_time_count") return("time_coverage")
  if (name %in% c("nonfinite_values", "nonempty_time_slices", "value_scan")) return("variable_values")
  if (name %in% c("history_provenance", "provenance_evidence", "extrema_aggregation_provenance"))
    return("source_and_processing")
  NA_character_
}
# The model cannot dismiss a demonstrated deterministic failure or hide an essential gap.
guard_grouped_results <- function(checks, results = NULL) {
  if (is.null(results)) results <- data.frame(group = grouped_check_names(), result = "NOT_CHECKED",
    finding = "LLM assessment not completed; see pilot_index.csv for execution status.",
    next_action = "Complete the model assessment using the saved evidence.", stringsAsFactors = FALSE)
  assigned <- vapply(checks$check, check_group, character(1))
  essential <- c("coordinate_dimensions", "data_variable", "additional_data_variables", "extra_dimensions",
    "resolution_code", "time_coverage", "value_scan")
  for (i in seq_len(nrow(results))) {
    rows <- checks[!is.na(assigned) & assigned == results$group[i], , drop = FALSE]
    failed <- rows[rows$status == "FAIL", , drop = FALSE]
    warnings <- rows[rows$status == "WARN", , drop = FALSE]
    gaps <- rows$check[rows$status == "NOT_CHECKED" & rows$check %in% essential]
    inspected <- switch(results$group[i],
      variable_and_metadata = any(rows$check == "filename_format"),
      grid_and_spatial_coverage = any(rows$check == "coordinate_dimensions" | grepl("^(lon|lat)_", rows$check)),
      time_coverage = any(grepl("^time_", rows$check)),
      variable_values = any(rows$check %in% c("nonfinite_values", "value_scan")),
      source_and_processing = any(rows$check %in% c("history_provenance", "provenance_evidence")))
    if (!inspected && !nrow(failed)) {
      results$result[i] <- "NOT_CHECKED"
      results$finding[i] <- "The saved scan stopped before this group was inspected; no contents finding is established."
      results$next_action[i] <- "Resolve the earlier scan/filename limitation before inspecting this group."
    } else if (nrow(failed) && results$result[i] != "FAIL") {
      results$result[i] <- "FAIL"
      results$finding[i] <- paste(paste0(failed$check, ": ", failed$detail), collapse = "; ")
      results$next_action[i] <- "Inspect the flagged saved checks and verify the condition before changing source data."
    } else if (nrow(warnings) && results$result[i] == "PASS") {
      results$result[i] <- "REVIEW"
      results$finding[i] <- paste(warnings$detail, collapse = "; ")
      results$next_action[i] <- "Verify the stated metadata discrepancy against the source definition."
    } else if (length(gaps) && results$result[i] == "PASS") {
      results$result[i] <- "NOT_CHECKED"
      results$finding[i] <- paste("Essential checks unavailable:", paste(gaps, collapse = ", "))
      results$next_action[i] <- "Resolve the missing evidence or unsupported check before declaring this group passed."
    }
  }
  results
}

# Selected-file or full-batch review using cached evidence; no NetCDF reads.
run_grouped_pilot <- function(scan_dir, output_dir, input_rows = NULL, model = "thinker", max_tokens = 20000L,
                              reasoning_effort = NULL, max_input_bytes = 64000L,
                              prompt_file = "docs/grouped-review-prompt.md", send_to_api = FALSE,
                              request_timeout = 600, connection_timeout = 20) {
  validate_completion_budget(max_tokens)
  validate_api_timeouts(request_timeout, connection_timeout)
  index_file <- file.path(scan_dir, "review_index.csv")
  if (!file.exists(index_file)) stop("Set scan_dir to the saved scan folder containing review_index.csv.")
  source_index <- read.csv(index_file, stringsAsFactors = FALSE)
  if (!all(c("filename", "report_path", "checks_status") %in% names(source_index))) stop("Unsupported scan index.")
  if (is.null(input_rows)) input_rows <- seq_len(nrow(source_index))
  if (!length(input_rows) || !is.numeric(input_rows) || anyNA(input_rows) ||
      any(input_rows != as.integer(input_rows)) || any(input_rows < 1 | input_rows > nrow(source_index)))
    stop("Select valid input_rows from the saved index.")
  selected <- unique(input_rows)
  if (!nzchar(output_dir)) stop("Set output_dir.")
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output directory.")
  run <- linked_run_directory(scan_dir, output_dir, "review")
  overview <- file.path(scan_dir, "data_overview.csv")
  if (file.exists(overview)) file.copy(overview, file.path(run, "data_overview.csv"))
  index <- source_index[selected, c("filename", "report_path", "checks_status"), drop = FALSE]
  index$input_row <- selected
  index$data_file_path <- if ("input_path" %in% names(source_index)) source_index$input_path[selected] else index$filename
  index$source_report_path <- index$report_path
  index$llm_status <- "NOT_RUN"; index$reason <- "Pilot not submitted."
  summaries <- vector("list", length(selected))
  checkpoint <- function() {
    write.csv(index, file.path(run, "pilot_index.csv"), row.names = FALSE)
    summary <- do.call(rbind, summaries[!vapply(summaries, is.null, logical(1))])
    if (!is.null(summary)) {
      write.csv(summary, file.path(run, "summary.csv"), row.names = FALSE)
      write.csv(grouped_short_summary(summary), file.path(run, "summary_short.csv"), row.names = FALSE)
      write.csv(summary[summary$result != "PASS", ], file.path(run, "flagged_files.csv"), row.names = FALSE)
    }
  }
  jsonlite::write_json(list(prompt_version = "grouped-review-pilot-v1", model = model, max_tokens = max_tokens,
    request_timeout = request_timeout, connection_timeout = connection_timeout,
    reasoning_effort = reasoning_effort, input_rows = selected, send_to_api = send_to_api),
    file.path(run, "pilot-settings.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  message("Grouped pilot: model=", model, "; max_tokens=", max_tokens, "; files=", length(selected),
    "; request_timeout=", request_timeout, "s; connection_timeout=", connection_timeout,
    "s; send_to_api=", send_to_api)
  checkpoint()
  for (j in seq_along(selected)) {
    directory <- file.path(run, sprintf("file-%03d", selected[j])); dir.create(directory)
    results <- NULL; checks <- NULL
    index$report_path[j] <- directory
    tryCatch({
      if (index$checks_status[j] != "COMPLETED") stop("Scan did not complete; inspect the original scan error first.")
      checks <- grouped_checks(read_saved_checks(index$source_report_path[j]))
      prompt <- prepare_grouped_review(checks, prompt_file)
      writeLines(prompt, file.path(directory, "grouped-preview.txt"))
      saveRDS(checks, file.path(directory, "pilot-checks.rds"))
      if (send_to_api) {
        answer <- ask_llm(prompt, model = model, output_dir = directory, approved_prompt = prompt,
          send = TRUE, max_tokens = max_tokens, reasoning_effort = reasoning_effort, max_input_bytes = max_input_bytes,
          request_timeout = request_timeout, connection_timeout = connection_timeout)
        results <- parse_grouped_response(answer$text)
        index$llm_status[j] <- if (is.null(results)) "INVALID_RESPONSE" else "COMPLETED"
        index$reason[j] <- if (is.null(results)) "Response did not match the five-group schema." else "Five-group assessment completed."
      }
    }, error = function(e) {
      attempts <- list.dirs(directory, recursive = FALSE, full.names = TRUE)
      metadata <- attempts[file.exists(file.path(attempts, "metadata.json"))]
      status <- if (length(metadata)) tryCatch(
        jsonlite::read_json(file.path(metadata[1], "metadata.json"))$status,
        error = function(e) "PREPARATION_ERROR") else "PREPARATION_ERROR"
      if (!is.character(status) || length(status) != 1 || is.na(status)) status <- "PREPARATION_ERROR"
      index$llm_status[j] <<- status
      index$reason[j] <<- conditionMessage(e)
    })
    if (is.null(checks)) results <- data.frame(group = grouped_check_names(), result = "NOT_CHECKED",
      finding = "Saved scan evidence was unavailable for this assessment.",
      next_action = "Inspect pilot_index.csv and resolve the scan/preparation error.", stringsAsFactors = FALSE) else
      results <- guard_grouped_results(checks, results)
    summaries[[j]] <- data.frame(data_file_path = index$data_file_path[j], check_group = results$group,
      result = results$result, finding = results$finding, next_action = results$next_action, stringsAsFactors = FALSE)
    write.csv(summaries[[j]], file.path(directory, "group-results.csv"), row.names = FALSE)
    report <- unlist(lapply(seq_len(nrow(results)), function(i) c(
      paste0("## ", gsub("_", " ", results$group[i]), " — ", results$result[i]),
      results$finding[i], paste("Next action:", results$next_action[i]), "")))
    writeLines(report, file.path(directory, "review.md"))
    checkpoint()
  }
  message("Grouped pilot saved to ", run, ". Existing reviewer outputs unchanged.")
  invisible(list(index = index, run_dir = run))
}
