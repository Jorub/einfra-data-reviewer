source("source/grouped_review.R")

work <- tempfile(); dir.create(work)
paths <- c("/sourceA/raw/shared.nc", "/sourceB/raw/shared.nc", "/sourceA/processed/shared.nc",
  "/unique/z_last_in_alphabet.nc", "/unique/a_first_in_alphabet.nc", "/unique/final_file.nc")
short <- data.frame(data_file_path = paths)
statuses <- c("PASS", "FAIL", "REVIEW", "NOT_CHECKED")
for (i in seq_along(grouped_check_names())) short[[grouped_check_names()[i]]] <- rep(statuses, length.out = 6)
table <- review_heatmap_table(short)
stopifnot(identical(table$data_file_path, paths), !anyDuplicated(table$filename_label),
  all(grepl("shared.nc [", table$filename_label[1:3], fixed = TRUE)),
  grepl("sourceA/raw", table$filename_label[1], fixed = TRUE),
  identical(table[grouped_check_names()], short[grouped_check_names()]))
write.csv(short, file.path(work, "summary_short.csv"), row.names = FALSE)
before <- tools::md5sum(file.path(work, "summary_short.csv"))
api_request <- function(...) stop("Unexpected model call")
set_api_key <- function(...) stop("Unexpected credential access")
device <- grDevices::dev.cur()
drawn <- list(); real_draw <- draw_review_heatmap
draw_review_heatmap <- function(table, page, pages, total, dimensions, style) {
  drawn[[length(drawn) + 1L]] <<- list(paths = table$data_file_path, statuses = table[grouped_check_names()], page = page)
  real_draw(table, page, pages, total, dimensions, style)
}
files <- write_review_heatmap(work, rows_per_page = 2, dpi = 72)
stopifnot(length(files) == 4, all(file.exists(files)), all(file.info(files)$size > 1000),
  identical(grDevices::dev.cur(), device), identical(before, tools::md5sum(file.path(work, "summary_short.csv"))),
  length(drawn) == 6)
for (page in 1:3) {
  rows <- ((page - 1) * 2 + 1):(page * 2)
  stopifnot(identical(drawn[[page]]$paths, paths[rows]), identical(drawn[[page + 3]]$paths, paths[rows]),
    identical(drawn[[page]]$statuses, short[rows, grouped_check_names()]))
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
unlink(work, recursive = TRUE)
cat("Heatmap passed: exact categorical results/order, duplicate filename context, PNG/PDF exports, pagination, device cleanup, stale-page handling and unchanged source CSV. No data/model/credential access.\n")
