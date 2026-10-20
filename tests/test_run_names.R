source("source/run_paths.R")
work <- tempfile(); dir.create(work)
scan <- new_scan_directory(work)
id <- scan_run_id(scan)
stopifnot(basename(scan) == paste0("scan-", id))
review1 <- linked_run_directory(scan, work, "review")
writeLines("Keep original review intact", file.path(review1, "sentinel.txt"))
review2 <- linked_run_directory(scan, work, "review")
retry1 <- linked_run_directory(review1, work, "rerun")
retry2 <- linked_run_directory(retry1, work, "rerun")
refresh <- linked_run_directory(scan, work, "scan")
stopifnot(basename(review1) == paste0("review-", id),
  basename(review2) == paste0("review-", id, "-02"),
  basename(retry1) == paste0("rerun-", id, "-01"),
  basename(retry2) == paste0("rerun-", id, "-02"),
  basename(refresh) == paste0("scan-", id, "-02"),
  identical(readLines(file.path(review1, "sentinel.txt")), "Keep original review intact"),
  scan_run_id(retry2) == id, scan_run_id(refresh) == id)
# A refreshed scan still links to the same identifier; an existing file also reserves its name.
writeLines("Reserved file", file.path(work, paste0("review-", id, "-03")))
review4 <- linked_run_directory(refresh, work, "review")
stopifnot(basename(review4) == paste0("review-", id, "-04"))
legacy <- file.path(work, "batch-old123"); dir.create(legacy)
legacy_review <- linked_run_directory(legacy, work, "review")
stopifnot(basename(legacy_review) == "review-old123", dir.exists(legacy),
  jsonlite::read_json(file.path(legacy_review, "run-lineage.json"))$parent_run == legacy)
unlink(work, recursive = TRUE)
cat("Run naming passed: one shared scan identifier, numbered repeats/retries, refresh lineage, legacy adoption and no overwrites.\n")
