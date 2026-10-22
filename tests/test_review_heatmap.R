source("source/grouped_review.R")

work <- tempfile(); dir.create(work)
paths <- c("/sourceA/raw/shared.nc", "/sourceB/raw/shared.nc", "/sourceA/processed/shared.nc",
  "/unique/z_last_in_alphabet.nc", "/unique/a_first_in_alphabet.nc", "/unique/final_file.nc")
short <- data.frame(data_file_path = paths)
statuses <- c("PASS", "FAIL", "REVIEW", "NOT_CHECKED")
for (i in seq_along(grouped_check_names())) short[[grouped_check_names()[i]]] <- rep(statuses, length.out = 6)
index <- data.frame(data_file_path = rev(paths),
  report_path = rev(file.path("output", c(rep("review-original", 3), rep("review-retry", 3)),
    c("file-001", "file-014", "file-019", "file-012", "file-018", "file-035"))))
table <- review_heatmap_table(short, index)
stopifnot(identical(table$data_file_path, paths), !anyDuplicated(table$filename_label),
  all(grepl("shared.nc\n[", table$filename_label[1:3], fixed = TRUE)),
  grepl("review-original/file-014", table$filename_label[2], fixed = TRUE),
  grepl("review-retry/file-012", table$filename_label[4], fixed = TRUE),
  !any(grepl("sourceA|sourceB|/unique", table$filename_label)),
  identical(table[grouped_check_names()], short[grouped_check_names()]))
write.csv(short, file.path(work, "summary_short.csv"), row.names = FALSE)
write.csv(index, file.path(work, "pilot_index.csv"), row.names = FALSE)
index_before <- tools::md5sum(file.path(work, "pilot_index.csv"))
before <- tools::md5sum(file.path(work, "summary_short.csv"))
api_request <- function(...) stop("Unexpected model call")
set_api_key <- function(...) stop("Unexpected credential access")
device <- grDevices::dev.cur()
drawn <- list(); real_draw <- draw_review_heatmap
draw_review_heatmap <- function(table, page, pages, total, dimensions, style) {
  drawn[[length(drawn) + 1L]] <<- list(paths = table$data_file_path, statuses = table[grouped_check_names()], labels = table$filename_label, page = page)
  real_draw(table, page, pages, total, dimensions, style)
}
files <- write_review_heatmap(work, rows_per_page = 2, dpi = 72)
stopifnot(length(files) == 4, all(file.exists(files)), all(file.info(files)$size > 1000),
  identical(grDevices::dev.cur(), device), identical(before, tools::md5sum(file.path(work, "summary_short.csv"))),
  length(drawn) == 6)
for (page in 1:3) {
  rows <- ((page - 1) * 2 + 1):(page * 2)
  stopifnot(identical(drawn[[page]]$paths, paths[rows]), identical(drawn[[page + 3]]$paths, paths[rows]),
    identical(drawn[[page]]$statuses, short[rows, grouped_check_names()]),
    identical(drawn[[page]]$labels, table$filename_label[rows]))
}
pdf <- file(files[1], "rb"); signature <- readBin(pdf, "raw", 5); close(pdf)
stopifnot(rawToChar(signature) == "%PDF-")
png <- file(files[2], "rb"); signature <- readBin(png, "raw", 8); close(png)
stopifnot(identical(as.integer(signature), c(137L, 80L, 78L, 71L, 13L, 10L, 26L, 10L)))
# A shorter single-page regeneration replaces its own stale page PNGs only.
writeLines("User note", file.path(work, "summary_heatmap_notes.txt"))
files <- write_review_heatmap(work, rows_per_page = 50, dpi = 72)
stopifnot(file.exists(file.path(work, "summary_heatmap.png")), length(files) == 2,
  !any(file.exists(file.path(work, sprintf("summary_heatmap_%03d.png", 1:3)))),
  file.exists(file.path(work, "summary_heatmap_notes.txt")),
  identical(before, tools::md5sum(file.path(work, "summary_short.csv"))))
bad <- short; bad$variable_values[1] <- "UNKNOWN"
stopifnot(inherits(try(review_heatmap_table(bad), silent = TRUE), "try-error"))
bad <- short; bad$data_file_path[2] <- bad$data_file_path[1]
stopifnot(inherits(try(review_heatmap_table(bad), silent = TRUE), "try-error"))
for (invalid in list(0, 101, 1.5, NA_real_, Inf, "50"))
  stopifnot(inherits(try(validate_heatmap_pages(invalid), silent = TRUE), "try-error"))
stopifnot(identical(index_before, tools::md5sum(file.path(work, "pilot_index.csv"))))
missing <- index[-1, ]
stopifnot(grepl("Report folder unavailable", review_filename_labels(paths, missing)[6], fixed = TRUE),
  all(grepl("Report folder unavailable", review_filename_labels(paths), fixed = TRUE)))
duplicated_index <- rbind(index, index[1, ])
stopifnot(inherits(try(review_heatmap_table(short, duplicated_index), silent = TRUE), "try-error"))
# Regenerate a genuine old five-column heatmap using the same plotting code.
legacy <- file.path(work, "legacy"); dir.create(legacy)
legacy_short <- short[c("data_file_path", legacy_grouped_check_names())]
write.csv(legacy_short, file.path(legacy, "summary_short.csv"), row.names = FALSE)
write.csv(index, file.path(legacy, "pilot_index.csv"), row.names = FALSE)
draw_review_heatmap <- real_draw
legacy_exports <- write_review_heatmap(legacy, dpi = 72)
stopifnot(all(file.exists(legacy_exports)), ncol(review_heatmap_table(legacy_short, index)) == 7)
unlink(work, recursive = TRUE)
cat("Heatmap passed: exact categorical results/order, saved report identifiers, path-based matching, missing-index labels, PNG/PDF exports, pagination, device cleanup, stale-page handling and unchanged source CSV. No data/model/credential access.\n")
