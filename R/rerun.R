# Rerun selected LLM stages from cached checks; never reopen or modify NetCDF data.
read_attempt <- function(report_path) {
  p <- file.path(report_path, "metadata.json")
  if (!file.exists(p)) return(list())
  tryCatch(jsonlite::read_json(p, simplifyVector = FALSE), error = function(e) list())
}
retry_budget <- function(meta, fallback) {
  x <- meta$max_tokens
  source <- "recorded"
  if (is.null(x) && identical(meta$finish_reason, "length")) {
    x <- meta$usage$completion_tokens; source <- "inferred from completion tokens at length limit"
  }
  if (!is.numeric(x) || length(x) != 1 || !is.finite(x) || x < 256 || x > 65536) {
    x <- fallback; source <- "configured fallback"
  }
  list(tokens = as.integer(x), source = source)
}
rerun_llm_reviews <- function(batch_dir, output_dir, model = "thinker", reasoning_effort = NULL,
                              retry_statuses = "TOKEN_LIMIT", same_budget_first = FALSE,
                              fallback_max_tokens = 8192L, max_retry_tokens = 16384L,
                              max_input_bytes = 64000L, send_to_api = FALSE) {
  if (!isTRUE(send_to_api)) stop("Inspect cached diagnostics/previews, then explicitly set send_to_api = TRUE.")
  if (!all(retry_statuses %in% c("TOKEN_LIMIT", "API_ERROR", "EMPTY_RESPONSE", "INVALID_RESPONSE")))
    stop("Choose explicit supported LLM retry statuses; do not retry completed reviews.")
  for (x in list(fallback_max_tokens, max_retry_tokens))
    if (length(x) != 1 || !is.numeric(x) || !is.finite(x) || x < 256 || x > 65536) stop("Invalid completion budget.")
  source_index <- file.path(batch_dir, "review_index.csv")
  if (!file.exists(source_index)) stop("Original batch review_index.csv not found.")
  index <- read.csv(source_index, stringsAsFactors = FALSE, check.names = FALSE)
  required <- c("filename", "checks_status", "llm_status", "result", "reason", "report_path")
  if (!all(required %in% names(index))) stop("Unsupported original index schema.")
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output directory.")
  run <- tempfile("rerun-", tmpdir = output_dir)
  dir.create(run)
  selected <- which(index$llm_status %in% retry_statuses & index$checks_status == "COMPLETED")
  index$source_report_path <- index$report_path
  index$rerun_status <- "NOT_SELECTED"
  index$rerun_status[selected] <- "PENDING"
  attempts <- list()
  checkpoint <- function() {
    write.csv(index, file.path(run, "review_index.csv"), row.names = FALSE)
    write.csv(index[c("filename", "result", "reason")], file.path(run, "summary.csv"), row.names = FALSE)
    write.csv(index[index$result != "PASS", ], file.path(run, "flagged_files.csv"), row.names = FALSE)
    if (length(attempts)) write.csv(do.call(rbind, attempts), file.path(run, "attempts.csv"), row.names = FALSE)
  }
  record_attempt <- function(i, number, dir, meta, budget, budget_source) {
    metric <- function(x) if (is.numeric(x) && length(x) == 1) x else NA_real_
    attempts[[length(attempts) + 1L]] <<- data.frame(input_row = i, filename = index$filename[i],
      attempt = number, requested_max_tokens = budget, budget_source = budget_source,
      model = if (is.null(meta$requested_model)) "unknown" else meta$requested_model,
      llm_status = if (is.null(meta$llm_status)) "unknown" else meta$llm_status,
      finish_reason = if (is.null(meta$finish_reason)) "unknown" else meta$finish_reason,
      completion_tokens = metric(meta$usage$completion_tokens),
      reasoning_tokens = metric(meta$usage$completion_tokens_details$reasoning_tokens),
      prompt_tokens = metric(meta$usage$prompt_tokens), total_tokens = metric(meta$usage$total_tokens),
      report_path = dir, stringsAsFactors = FALSE)
  }
  checkpoint()
  message("Selected ", length(selected), " incomplete LLM reviews; NetCDF values will not be rescanned.")
  for (i in selected) {
    tryCatch({
      previous <- index$source_report_path[i]
      cache <- file.path(previous, "local-diagnostics.rds")
      if (!file.exists(cache)) cache <- file.path(dirname(previous), "local-diagnostics.rds")
      if (!file.exists(cache)) stop("Saved diagnostics unavailable; rescan this file separately.")
      checks <- readRDS(cache)
      meta <- read_attempt(previous)
      base <- retry_budget(meta, fallback_max_tokens)
      record_attempt(i, 0L, previous, meta, base$tokens, base$source)
      # For a token-limited attempt, double once, bounded by the configured cap.
      # An optional same-budget attempt precedes escalation only if requested.
      budgets <- if (index$llm_status[i] == "TOKEN_LIMIT") {
        larger <- max(base$tokens, min(2 * base$tokens, max_retry_tokens))
        if (larger <= base$tokens && !same_budget_first)
          stop("Retry cap does not allow a larger budget; raise max_retry_tokens or request a same-budget retry.")
        unique(c(if (same_budget_first) base$tokens, larger))
      } else base$tokens
      for (j in seq_along(budgets)) {
        destination <- file.path(run, sprintf("file-%03d-attempt-%02d", i, j))
        dir.create(destination)
        preview <- prepare_review(checks)
        writeLines(as.character(preview), file.path(destination, "review-preview.json"))
        failure <- NULL
        report <- tryCatch(review_checks(checks, model = model, approved_payload = preview,
          send = TRUE, report_dir = destination, max_tokens = budgets[j],
          reasoning_effort = reasoning_effort, max_input_bytes = max_input_bytes),
          error = function(e) { failure <<- conditionMessage(e); NULL })
        if (is.null(report)) {
          folders <- list.dirs(destination, recursive = FALSE, full.names = TRUE)
          valid <- folders[file.exists(file.path(folders, "review_index.csv"))]
          if (length(valid)) report <- valid[1]
        }
        if (is.null(report)) stop(if (is.null(failure)) "No attempt report produced" else failure)
        meta <- read_attempt(report)
        record_attempt(i, j, report, meta, budgets[j], "rerun setting")
        row <- read.csv(file.path(report, "review_index.csv"), stringsAsFactors = FALSE)
        for (name in c("result", "reason", "llm_status", "report_path")) index[i, name] <- row[1, name]
        index$rerun_status[i] <- if (row$llm_status[1] == "COMPLETED") "COMPLETED" else "STILL_INCOMPLETE"
        checkpoint()
        # Never escalate a transport/schema error or repeat a completed request.
        if (row$llm_status[1] != "TOKEN_LIMIT") break
      }
    }, error = function(e) {
      index$rerun_status[i] <<- "ERROR"
      index$reason[i] <<- paste(index$reason[i], "Rerun error:", conditionMessage(e))
    })
    checkpoint()
  }
  message("Rerun index saved to ", run)
  invisible(list(index = index, run_dir = run))
}
