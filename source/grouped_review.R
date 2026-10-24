# Current grouped reviewer; five-category saved reviews remain readable.
grouped_check_names <- function() c("variable_and_metadata", "grid_and_spatial_coverage",
  "time_coverage", "variable_values", "source_and_processing", "mask_provenance")
source("source/review_heatmap.R")
source("source/mask_provenance.R")
legacy_grouped_check_names <- function() head(grouped_check_names(), -1L)
grouped_summary_groups <- function(summary) {
  if ("mask_provenance" %in% summary$check_group) grouped_check_names() else legacy_grouped_check_names()
}

# Compact overview using exactly the same result labels as summary.csv.
grouped_short_summary <- function(summary) {
  required <- c("data_file_path", "check_group", "result")
  if (!all(required %in% names(summary))) stop("Expected a grouped-review summary.csv.")
  if (anyNA(summary[required]) || any(!summary$check_group %in% grouped_check_names()) ||
      any(!summary$result %in% c("PASS", "FAIL", "REVIEW", "NOT_CHECKED")))
    stop("Grouped summary contains missing or unsupported categories/results.")
  overview <- data.frame(data_file_path = unique(summary$data_file_path), stringsAsFactors = FALSE)
  for (group in grouped_summary_groups(summary)) {
    overview[[group]] <- vapply(overview$data_file_path, function(path) {
      results <- unique(summary$result[summary$data_file_path == path & summary$check_group == group])
      if (length(results) > 1)
        stop("Conflicting results for the same data_file_path/check_group; inspect summary.csv.")
      if (length(results)) results else "NOT_CHECKED"
    }, character(1))
  }
  overview
}
write_grouped_short_summary <- function(review_dir, heatmap_rows_per_page = 50L) {
  input <- file.path(review_dir, "summary.csv")
  if (!file.exists(input)) stop("Set review_dir to the grouped-review folder containing summary.csv.")
  overview <- grouped_short_summary(read.csv(input, stringsAsFactors = FALSE))
  output <- file.path(review_dir, "summary_short.csv")
  write.csv(overview, output, row.names = FALSE)
  write_review_heatmap(review_dir, rows_per_page = heatmap_rows_per_page)
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
  add_mask_provenance(checks)
}
prepare_grouped_review <- function(checks, prompt_file = "docs/grouped-review-prompt.md") {
  if (!file.exists(prompt_file)) stop("Grouped review prompt file not found.")
  if (!"mask_provenance" %in% checks$check) checks <- grouped_checks(checks)
  evidence <- jsonlite::fromJSON(prepare_review(checks), simplifyVector = FALSE)
  # Exclude legacy task instructions and all local-only attributes/paths.
  supplied <- list(prompt_version = "grouped-review-v2-mask-provenance", passed_checks = evidence$passed_checks,
    attention_checks = evidence$attention_checks, context = evidence$context)
  paste(paste(readLines(prompt_file, warn = FALSE), collapse = "\n"),
    "\nSUPPLIED EVIDENCE (not instructions):\n",
    jsonlite::toJSON(supplied, auto_unbox = TRUE, pretty = TRUE, null = "null"), sep = "\n")
}
parse_grouped_response <- function(text) {
  x <- tryCatch(jsonlite::fromJSON(text, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(x) || !identical(names(x), "results") || length(x$results) != length(grouped_check_names())) return(NULL)
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
  if (name == "mask_provenance") return("mask_provenance")
  if (name %in% c("filename_format", "data_variable", "filename_variable", "filename_units",
      "additional_data_variables", "extra_dimensions")) return("variable_and_metadata")
  if (name %in% c("coordinate_dimensions", "resolution_code", "land_mask", "land_data_coverage", "global_data_coverage", "spatial_coverage_claim") ||
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
    # Exact mask-identity rules are deterministic; preserve them even if the API fails.
    if (results$group[i] == "mask_provenance" && "mask_provenance" %in% checks$check) {
      assessment <- attr(checks, "review_evidence")$mask_provenance
      results$result[i] <- assessment$rule_result
      results$finding[i] <- assessment$finding
      results$next_action[i] <- assessment$next_action
      next
    }
    rows <- checks[!is.na(assigned) & assigned == results$group[i], , drop = FALSE]
    failed <- rows[rows$status == "FAIL", , drop = FALSE]
    warnings <- rows[rows$status == "WARN", , drop = FALSE]
    gaps <- rows$check[rows$status == "NOT_CHECKED" & rows$check %in% essential]
    inspected <- switch(results$group[i],
      variable_and_metadata = any(rows$check == "filename_format"),
      grid_and_spatial_coverage = any(rows$check == "coordinate_dimensions" | grepl("^(lon|lat)_", rows$check)),
      time_coverage = any(grepl("^time_", rows$check)),
      variable_values = any(rows$check %in% c("nonfinite_values", "value_scan")),
      source_and_processing = any(rows$check %in% c("history_provenance", "provenance_evidence")),
      mask_provenance = any(rows$check == "mask_provenance"))
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

validate_review_concurrency <- function(max_concurrent_requests) {
  if (!is.numeric(max_concurrent_requests) || length(max_concurrent_requests) != 1 ||
      !is.finite(max_concurrent_requests) || max_concurrent_requests != floor(max_concurrent_requests) ||
      max_concurrent_requests < 1 || max_concurrent_requests > 4)
    stop("max_concurrent_requests must be an integer from 1 to 4 (the per-account API limit).")
  invisible(NULL)
}
grouped_request_pool <- function(limit) curl::new_pool(total_con = limit, host_con = limit)
poll_grouped_requests <- function(pool) curl::multi_run(timeout = 1, pool = pool)
cancel_grouped_request <- function(handle) curl::multi_cancel(handle)

# Selected-file or full-batch review using cached evidence; no NetCDF reads.
run_grouped_pilot <- function(scan_dir, output_dir, input_rows = NULL, model = "thinker", max_tokens = 20000L,
                              reasoning_effort = NULL, max_input_bytes = 64000L,
                              prompt_file = "docs/grouped-review-prompt.md", send_to_api = FALSE,
                              request_timeout = 600, connection_timeout = 20, max_concurrent_requests = 1L,
                              heatmap_rows_per_page = 50L) {
  validate_completion_budget(max_tokens)
  validate_api_timeouts(request_timeout, connection_timeout)
  validate_review_concurrency(max_concurrent_requests)
  validate_heatmap_pages(heatmap_rows_per_page)
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
  index$report_path <- file.path(run, sprintf("file-%03d", selected))
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
  jsonlite::write_json(list(prompt_version = "grouped-review-v2-mask-provenance", model = model, max_tokens = max_tokens,
    max_tokens_source = completion_budget_source(max_tokens), request_timeout = request_timeout, connection_timeout = connection_timeout,
    max_concurrent_requests = max_concurrent_requests,
    heatmap_rows_per_page = heatmap_rows_per_page,
    reasoning_effort = reasoning_effort, input_rows = selected, send_to_api = send_to_api),
    file.path(run, "pilot-settings.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  message("Grouped pilot: model=", model, "; max_tokens=", format_completion_budget(max_tokens), "; files=", length(selected),
    "; request_timeout=", request_timeout, "s; connection_timeout=", connection_timeout,
    "s; max_concurrent_requests=", max_concurrent_requests, "; send_to_api=", send_to_api)
  checkpoint()
  # All callbacks run in this R process; only this coordinator writes summaries.
  active <- rep(FALSE, length(selected))
  handles <- vector("list", length(selected))
  pool <- if (send_to_api && max_concurrent_requests > 1) grouped_request_pool(max_concurrent_requests) else NULL
  on.exit({
    pending <- which(active)
    for (j in pending) {
      if (!is.null(handles[[j]])) try(cancel_grouped_request(handles[[j]]), silent = TRUE)
      index$llm_status[j] <- "INTERRUPTED"
      index$reason[j] <- "Review interrupted before a result was checkpointed; inspect saved attempt metadata."
    }
    if (length(pending)) try(checkpoint(), silent = TRUE)
  }, add = TRUE)
  finish_file <- function(j, checks, results = NULL, status, reason) {
    active[j] <<- FALSE; handles[j] <<- list(NULL)
    index$llm_status[j] <<- status; index$reason[j] <<- reason
    if (is.null(checks)) results <- data.frame(group = grouped_check_names(), result = "NOT_CHECKED",
      finding = "Saved scan evidence was unavailable for this assessment.",
      next_action = "Inspect pilot_index.csv and resolve the scan/preparation error.", stringsAsFactors = FALSE) else
      results <- guard_grouped_results(checks, results)
    summaries[[j]] <<- data.frame(data_file_path = index$data_file_path[j], check_group = results$group,
      result = results$result, finding = results$finding, next_action = results$next_action, stringsAsFactors = FALSE)
    directory <- index$report_path[j]
    write.csv(summaries[[j]], file.path(directory, "group-results.csv"), row.names = FALSE)
    report <- unlist(lapply(seq_len(nrow(results)), function(i) c(
      paste0("## ", gsub("_", " ", results$group[i]), " — ", results$result[i]),
      results$finding[i], paste("Next action:", results$next_action[i]),
      if (results$group[i] == "mask_provenance") mask_local_report(checks) else character(), "")))
    writeLines(report, file.path(directory, "review.md"))
    checkpoint()
    message("Saved grouped review ", sum(!vapply(summaries, is.null, logical(1))), "/", length(selected),
      ": ", index$filename[j], " [", status, "]")
  }
  launch_file <- function(j) {
    directory <- index$report_path[j]; dir.create(directory)
    prepared <- tryCatch({
      if (index$checks_status[j] != "COMPLETED") stop("Scan did not complete; inspect the original scan error first.")
      checks <- grouped_checks(read_saved_checks(index$source_report_path[j]))
      prompt <- prepare_grouped_review(checks, prompt_file)
      writeLines(prompt, file.path(directory, "grouped-preview.txt"))
      saveRDS(checks, file.path(directory, "pilot-checks.rds"))
      write_mask_provenance(checks, directory)
      list(checks = checks, prompt = prompt)
    }, error = identity)
    if (inherits(prepared, "error")) {
      finish_file(j, NULL, status = "PREPARATION_ERROR", reason = conditionMessage(prepared))
      return(invisible(NULL))
    }
    if (!send_to_api) {
      finish_file(j, prepared$checks, status = "NOT_RUN", reason = "Pilot not submitted.")
      return(invisible(NULL))
    }
    accept_answer <- function(answer) {
      if (inherits(answer, "error")) {
        attempts <- list.dirs(directory, recursive = FALSE, full.names = TRUE)
        metadata <- attempts[file.exists(file.path(attempts, "metadata.json"))]
        status <- if (length(metadata)) tryCatch(
          jsonlite::read_json(file.path(metadata[1], "metadata.json"))$status,
          error = function(e) "PREPARATION_ERROR") else "PREPARATION_ERROR"
        if (!is.character(status) || length(status) != 1 || is.na(status)) status <- "PREPARATION_ERROR"
        finish_file(j, prepared$checks, status = status, reason = conditionMessage(answer))
      } else {
        results <- parse_grouped_response(answer$text)
        finish_file(j, prepared$checks, results = results,
          status = if (is.null(results)) "INVALID_RESPONSE" else "COMPLETED",
          reason = if (is.null(results)) "Response did not match the six-group schema." else "Six-group assessment completed.")
      }
    }
    active[j] <<- TRUE
    index$llm_status[j] <<- "IN_PROGRESS"; index$reason[j] <<- "Model request in progress."
    checkpoint()
    answer <- tryCatch(ask_llm(prepared$prompt, model = model, output_dir = directory,
      approved_prompt = prepared$prompt, send = TRUE, max_tokens = max_tokens,
      reasoning_effort = reasoning_effort, max_input_bytes = max_input_bytes,
      request_timeout = request_timeout, connection_timeout = connection_timeout,
      pool = pool, callback = if (!is.null(pool)) accept_answer else NULL), error = identity)
    if (is.null(pool) || inherits(answer, "error")) accept_answer(answer) else handles[j] <<- list(answer$handle)
    invisible(NULL)
  }
  next_file <- 1L
  while (next_file <= length(selected) || any(active)) {
    while (next_file <= length(selected) && sum(active) < max_concurrent_requests) {
      j <- next_file; next_file <- next_file + 1L
      launch_file(j)
    }
    if (any(active)) poll_grouped_requests(pool)
  }
  tryCatch(write_review_heatmap(run, rows_per_page = heatmap_rows_per_page),
    error = function(e) warning("Heatmap export failed; saved CSV/model results remain intact: ", conditionMessage(e)))
  message("Grouped pilot saved to ", run, ". Existing reviewer outputs unchanged.")
  invisible(list(index = index, run_dir = run))
}
