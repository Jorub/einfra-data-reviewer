source("source/merge_reviews.R")

work <- tempfile(); dir.create(work)
make_review <- function(name, paths, statuses, values = list()) {
  folder <- file.path(work, name); dir.create(folder)
  index <- data.frame(data_file_path = paths, filename = basename(paths), checks_status = "COMPLETED",
    llm_status = statuses, reason = ifelse(statuses == "COMPLETED", "Assessment completed.", "API HTTP 429."),
    report_path = file.path(folder, paste0("file-", seq_along(paths))), stringsAsFactors = FALSE)
  summary <- do.call(rbind, lapply(seq_along(paths), function(i) {
    result <- if (statuses[i] == "COMPLETED") rep("PASS", 5) else rep("NOT_CHECKED", 5)
    if (length(values) >= i && length(values[[i]])) result <- values[[i]]
    data.frame(data_file_path = paths[i], check_group = grouped_check_names(), result = result,
      finding = paste(name, basename(paths[i]), grouped_check_names()), next_action = "Synthetic next action.")
  }))
  write.csv(index, file.path(folder, "pilot_index.csv"), row.names = FALSE)
  write.csv(summary, file.path(folder, "summary.csv"), row.names = FALSE)
  folder
}
a <- "/data/raw/shared.nc"; b <- "/data/processed/shared.nc"
c <- "/data/keep-failed-verdict.nc"; d <- "/data/still-incomplete.nc"; e <- "/data/added.nc"
old <- make_review("review-fixture", c(a, b, c, d), c("COMPLETED", "COMPLETED", "COMPLETED", "API_ERROR"),
  list(rep("PASS", 5), c("FAIL", rep("PASS", 4)), c("FAIL", rep("PASS", 4)), c("FAIL", rep("NOT_CHECKED", 4))))
retry <- make_review("review-fixture-02", c(a, b, c, d, e),
  c("COMPLETED", "COMPLETED", "API_ERROR", "API_ERROR", "COMPLETED"),
  list(c("PASS", "NOT_CHECKED", "PASS", "PASS", "PASS"), rep("PASS", 5), rep("NOT_CHECKED", 5),
    c("FAIL", rep("NOT_CHECKED", 4)), rep("REVIEW", 5)))
sources <- unlist(lapply(c(old, retry), function(folder) file.path(folder, c("summary.csv", "pilot_index.csv"))))
before <- tools::md5sum(sources)
api_request <- function(...) stop("Unexpected API call")
set_api_key <- function(...) stop("Unexpected credential access")
check_netcdf <- function(...) stop("Unexpected NetCDF scan")
merged <- merge_grouped_reviews(c(old, retry), output_dir = file.path(work, "output"))
short <- read.csv(file.path(merged$run_dir, "summary_short.csv"), stringsAsFactors = FALSE)
stopifnot(identical(short$data_file_path, c(a, b, c, d, e)), nrow(merged$summary) == 25,
  short$grid_and_spatial_coverage[1] == "NOT_CHECKED", short$variable_and_metadata[2] == "PASS",
  short$variable_and_metadata[3] == "FAIL", short$variable_and_metadata[4] == "FAIL",
  merged$index$llm_status[4] == "API_ERROR", all(short[5, -1] == "REVIEW"),
  merged$index$selected_review_dir[3] == normalizePath(old),
  merged$index$selected_review_dir[1] == normalizePath(retry),
  merged$index$report_path[3] == file.path(old, "file-3"),
  identical(before, tools::md5sum(sources)), nrow(merged$changes) == 2,
  any(merged$changes$previous_result == "FAIL" & merged$changes$result == "PASS"),
  any(merged$changes$previous_result == "PASS" & merged$changes$result == "NOT_CHECKED"),
  file.exists(file.path(merged$run_dir, "summary_heatmap.png")),
  file.exists(file.path(merged$run_dir, "summary_heatmap.pdf")),
  all(c("summary.csv", "pilot_index.csv", "review_changes.csv", "review_sources.csv", "merge-settings.json",
    "flagged_files.csv", "run-lineage.json") %in% list.files(merged$run_dir)))
labels <- review_heatmap_table(short, merged$index)$filename_label
stopifnot(grepl("review-fixture/file-3", labels[3], fixed = TRUE),
  grepl("review-fixture-02/file-1", labels[1], fixed = TRUE))
trace <- read.csv(file.path(merged$run_dir, "review_sources.csv"), stringsAsFactors = FALSE)
stopifnot(identical(trace$review_dir, normalizePath(c(old, retry))),
  jsonlite::read_json(file.path(merged$run_dir, "run-lineage.json"))$stage == "merge")
# Folder priority is explicit, not based on directory timestamps or a favourable status.
# Mock only the already-tested rendering for further selection/validation checks.
write_review_heatmap <- function(...) invisible(NULL)
reversed <- merge_grouped_reviews(c(retry, old), output_dir = file.path(work, "output"))
stopifnot(reversed$summary$result[reversed$summary$data_file_path == b][1] == "FAIL",
  reversed$summary$result[reversed$summary$data_file_path == a][2] == "PASS")
# A merged view remains a readable input; source report references stay intact.
again <- merge_grouped_reviews(c(merged$run_dir, retry), output_dir = file.path(work, "output"))
stopifnot(identical(again$summary, merged$summary), again$index$report_path[3] == file.path(old, "file-3"))
# An interrupted index can contain pending files with no saved summary yet.
pending <- make_review("review-pending", "/data/pending.nc", "IN_PROGRESS")
write.csv(read.csv(file.path(pending, "summary.csv"))[FALSE, ], file.path(pending, "summary.csv"), row.names = FALSE)
partial <- merge_grouped_reviews(c(old, pending), output_dir = file.path(work, "output"))
stopifnot(all(partial$summary$result[partial$summary$data_file_path == "/data/pending.nc"] == "NOT_CHECKED"))
# Invalid sources fail before allocating an output folder.
expect_invalid <- function(dirs) {
  destination <- tempfile(tmpdir = work)
  stopifnot(inherits(try(merge_grouped_reviews(dirs, destination), silent = TRUE), "try-error"), !dir.exists(destination))
}
expect_invalid(c(old, old)); expect_invalid(""); expect_invalid(file.path(work, "absent"))
bad <- make_review("review-bad", "/data/bad.nc", "COMPLETED")
original <- read.csv(file.path(bad, "summary.csv"))
write.csv(original[-1, ], file.path(bad, "summary.csv"), row.names = FALSE); expect_invalid(bad)
invalid <- original; invalid$result[1] <- "UNKNOWN"
write.csv(invalid, file.path(bad, "summary.csv"), row.names = FALSE); expect_invalid(bad)
invalid <- original; invalid$data_file_path[1] <- "/data/unknown.nc"
write.csv(invalid, file.path(bad, "summary.csv"), row.names = FALSE); expect_invalid(bad)
write.csv(original, file.path(bad, "summary.csv"), row.names = FALSE)
index <- read.csv(file.path(bad, "pilot_index.csv"))
write.csv(rbind(index, index), file.path(bad, "pilot_index.csv"), row.names = FALSE); expect_invalid(bad)
stopifnot(identical(before, tools::md5sum(sources)))
unlink(work, recursive = TRUE)
cat("Review merge passed: explicit priority, full-path identity, whole-file completion, failed-request fallback, preserved NOT_CHECKED, changed verdicts, report provenance, pending files, invalid schemas, heatmap exports and unchanged source reviews. No API/data/credential access.\n")
