# Merge saved grouped assessments without opening data or contacting a model.
source("source/grouped_review.R")
source("source/run_paths.R")

read_merge_review <- function(review_dir) {
  if (!dir.exists(review_dir)) stop("Review folder does not exist: ", review_dir)
  review_dir <- normalizePath(review_dir, mustWork = TRUE)
  summary_file <- file.path(review_dir, "summary.csv")
  index_file <- file.path(review_dir, "pilot_index.csv")
  if (!file.exists(summary_file) || !file.exists(index_file))
    stop("Each review folder must contain summary.csv and pilot_index.csv: ", review_dir)
  summary <- read.csv(summary_file, stringsAsFactors = FALSE, check.names = FALSE)
  index <- read.csv(index_file, stringsAsFactors = FALSE, check.names = FALSE)
  summary_columns <- c("data_file_path", "check_group", "result", "finding", "next_action")
  index_columns <- c("data_file_path", "filename", "checks_status", "llm_status", "reason", "report_path")
  if (!all(summary_columns %in% names(summary)) || !all(index_columns %in% names(index)))
    stop("Expected grouped summary and completion-index schemas: ", review_dir)
  if (!nrow(index) || anyNA(index[index_columns]) || any(!nzchar(trimws(index$data_file_path))) ||
      anyDuplicated(index$data_file_path) || any(!grepl("^(/|[A-Za-z]:[/\\\\])", index$data_file_path)))
    stop("Review index must identify each file once using its full data path: ", review_dir)
  if (anyNA(summary[summary_columns]) || any(!nzchar(trimws(summary$finding))) ||
      any(!nzchar(trimws(summary$next_action))) || any(!summary$data_file_path %in% index$data_file_path) ||
      any(!summary$check_group %in% grouped_check_names()) ||
      any(!summary$result %in% c("PASS", "FAIL", "REVIEW", "NOT_CHECKED")))
    stop("Invalid grouped summary fields, results or file identities: ", review_dir)
  for (i in seq_len(nrow(index))) {
    rows <- summary[summary$data_file_path == index$data_file_path[i], summary_columns, drop = FALSE]
    if (nrow(rows) && (anyDuplicated(rows$check_group) ||
        !(setequal(rows$check_group, grouped_check_names()) || setequal(rows$check_group, legacy_grouped_check_names()))))
      stop("Each assessed file must have exactly one row per check group: ", index$data_file_path[i])
    if (!nrow(rows) && index$llm_status[i] == "COMPLETED")
      stop("Completed assessment has no saved group results: ", index$data_file_path[i])
  }
  list(directory = review_dir, summary = summary, index = index,
    summary_md5 = unname(tools::md5sum(summary_file)), index_md5 = unname(tools::md5sum(index_file)))
}

merge_review_rows <- function(review, path, groups = grouped_check_names()) {
  rows <- review$summary[review$summary$data_file_path == path, , drop = FALSE]
  if (!nrow(rows)) rows <- data.frame(data_file_path = path, check_group = groups,
    result = "NOT_CHECKED", finding = "No assessment was saved for this file in the selected review.",
    next_action = "Inspect pilot_index.csv and complete the assessment using saved scan evidence.",
    stringsAsFactors = FALSE)
  missing <- setdiff(groups, rows$check_group)
  if (length(missing)) rows <- rbind(rows, data.frame(data_file_path = path, check_group = missing,
    result = "NOT_CHECKED", finding = "Mask provenance was not assessed in this earlier five-category review.",
    next_action = "Run a current grouped review using the saved scan evidence.", stringsAsFactors = FALSE))
  rows[match(groups, rows$check_group),
    c("data_file_path", "check_group", "result", "finding", "next_action"), drop = FALSE]
}

bind_review_indexes <- function(rows) {
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  do.call(rbind, lapply(rows, function(row) {
    for (name in setdiff(columns, names(row))) row[[name]] <- NA
    row[columns]
  }))
}

merge_grouped_reviews <- function(review_dirs, output_dir = "output", heatmap_rows_per_page = 50L) {
  if (!is.character(review_dirs) || !length(review_dirs) || anyNA(review_dirs) ||
      any(!nzchar(trimws(review_dirs)))) stop("List review_dirs in order from oldest to newest.")
  validate_heatmap_pages(heatmap_rows_per_page)
  reviews <- lapply(path.expand(review_dirs), read_merge_review)
  groups <- if (any(vapply(reviews, function(review) "mask_provenance" %in% review$summary$check_group, logical(1))))
    grouped_check_names() else legacy_grouped_check_names()
  directories <- vapply(reviews, function(review) review$directory, character(1))
  if (anyDuplicated(directories)) stop("List each review folder only once.")
  if (!is.character(output_dir) || length(output_dir) != 1 || is.na(output_dir) || !nzchar(output_dir))
    stop("Set output_dir.")
  paths <- unique(unlist(lapply(reviews, function(review) review$index$data_file_path), use.names = FALSE))
  summaries <- indexes <- vector("list", length(paths))
  changes <- list()
  for (i in seq_along(paths)) {
    path <- paths[i]
    candidates <- which(vapply(reviews, function(review) path %in% review$index$data_file_path, logical(1)))
    completed <- candidates[vapply(reviews[candidates], function(review) {
      row <- review$index[review$index$data_file_path == path, , drop = FALSE]
      row$llm_status == "COMPLETED" && row$checks_status == "COMPLETED"
    }, logical(1))]
    selected <- tail(if (length(completed)) completed else candidates, 1)
    review <- reviews[[selected]]
    summaries[[i]] <- merge_review_rows(review, path, groups)
    row <- review$index[review$index$data_file_path == path, , drop = FALSE]
    row$selected_review_dir <- review$directory
    row$selected_review_order <- selected
    row$selection_reason <- if (length(completed)) "Newest completed assessment in review_dirs order." else
      "No completed assessment; latest available execution status and deterministic results retained."
    indexes[[i]] <- row
    # Compare consecutive completed assessments, including NOT_CHECKED groups.
    if (length(completed) > 1) for (j in seq.int(2, length(completed))) {
      previous <- reviews[[completed[j - 1]]]; current <- reviews[[completed[j]]]
      before <- merge_review_rows(previous, path, groups); after <- merge_review_rows(current, path, groups)
      changed <- which(before$result != after$result)
      if (length(changed)) changes[[length(changes) + 1L]] <- data.frame(
        data_file_path = path, check_group = before$check_group[changed],
        previous_result = before$result[changed], result = after$result[changed],
        previous_finding = before$finding[changed], finding = after$finding[changed],
        previous_next_action = before$next_action[changed], next_action = after$next_action[changed],
        previous_review_dir = previous$directory, review_dir = current$directory, stringsAsFactors = FALSE)
    }
  }
  summary <- do.call(rbind, summaries)
  index <- bind_review_indexes(indexes)
  empty_changes <- data.frame(data_file_path = character(), check_group = character(),
    previous_result = character(), result = character(), previous_finding = character(), finding = character(),
    previous_next_action = character(), next_action = character(), previous_review_dir = character(),
    review_dir = character(), stringsAsFactors = FALSE)
  changes <- if (length(changes)) do.call(rbind, changes) else empty_changes
  if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output_dir.")
  run <- linked_run_directory(directories[1], output_dir, "merge")
  write.csv(summary, file.path(run, "summary.csv"), row.names = FALSE)
  write.csv(index, file.path(run, "pilot_index.csv"), row.names = FALSE)
  write.csv(summary[summary$result != "PASS", ], file.path(run, "flagged_files.csv"), row.names = FALSE)
  write.csv(changes, file.path(run, "review_changes.csv"), row.names = FALSE)
  sources <- data.frame(review_order = seq_along(reviews), review_dir = directories,
    summary_md5 = vapply(reviews, function(review) review$summary_md5, character(1)),
    index_md5 = vapply(reviews, function(review) review$index_md5, character(1)))
  write.csv(sources, file.path(run, "review_sources.csv"), row.names = FALSE)
  jsonlite::write_json(list(review_dirs = directories,
    selection_rule = "Newest completed whole-file assessment in explicit folder order; otherwise latest available.",
    heatmap_rows_per_page = heatmap_rows_per_page, created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)),
    file.path(run, "merge-settings.json"), auto_unbox = TRUE, pretty = TRUE)
  # Save the short CSV even if a graphics-device problem prevents heatmap export.
  write.csv(grouped_short_summary(summary), file.path(run, "summary_short.csv"), row.names = FALSE)
  tryCatch(write_review_heatmap(run, rows_per_page = heatmap_rows_per_page),
    error = function(e) warning("Heatmap export failed; merged CSV results remain intact: ", conditionMessage(e)))
  message("Merged ", length(paths), " files from ", length(reviews), " reviews into ", run,
    ". No scans or API calls performed. Changed verdicts: ", nrow(changes), ".")
  invisible(list(run_dir = run, index = index, summary = summary, changes = changes))
}
