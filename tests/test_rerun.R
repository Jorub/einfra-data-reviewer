source("source/reviewer.R")
source("source/rerun.R")
# Entire test is synthetic; neither raw input data nor the API are accessed.
root <- tempfile(); dir.create(root)
batch <- file.path(root, "original"); dir.create(batch)
make_old <- function(i, status, fail = FALSE) {
  p <- file.path(batch, paste0("file", i)); dir.create(p)
  checks <- data.frame(check = "units", status = if (fail) "FAIL" else "PASS", detail = "Synthetic check")
  attr(checks, "review_evidence") <- list(filename = list(basename = paste0("synthetic", i, ".nc")), observed = list(variable = "t2m"))
  saveRDS(checks, file.path(p, "local-diagnostics.rds"))
  jsonlite::write_json(list(requested_model = "mock", finish_reason = if (status == "TOKEN_LIMIT") "length" else "stop",
    llm_status = status, usage = list(completion_tokens = 8192L, total_tokens = 9000L)), file.path(p, "metadata.json"), auto_unbox = TRUE)
  data.frame(filename = paste0("synthetic", i, ".nc"), checks_status = "COMPLETED", llm_status = status,
    result = if (fail) "FAIL" else "INCOMPLETE", reason = "Previous outcome", report_path = p)
}
old <- rbind(make_old(1, "TOKEN_LIMIT", TRUE), make_old(2, "TOKEN_LIMIT"), make_old(3, "COMPLETED"))
write.csv(old, file.path(batch, "review_index.csv"), row.names = FALSE)
before <- tools::md5sum(file.path(batch, "review_index.csv"))
seen <- numeric()
review_checks <- function(checks, report_dir, max_tokens, ...) {
  seen <<- c(seen, max_tokens)
  p <- file.path(report_dir, "review-mock"); dir.create(p)
  f <- attr(checks, "review_evidence")$filename$basename
  status <- if (max_tokens == 8192L) "TOKEN_LIMIT" else if (f == "synthetic2.nc") "API_ERROR" else "COMPLETED"
  jsonlite::write_json(list(requested_model = "mock", llm_status = status, max_tokens = max_tokens,
    finish_reason = if (status == "TOKEN_LIMIT") "length" else "stop",
    usage = list(completion_tokens = 100, total_tokens = 200)), file.path(p, "metadata.json"), auto_unbox = TRUE)
  row <- review_summary(checks, status, if (status == "COMPLETED") list(verdict = "PASS", reason = "Synthetic review") else NULL)
  write.csv(cbind(row, llm_status = status, report_path = p), file.path(p, "review_index.csv"), row.names = FALSE)
  if (status != "COMPLETED") stop("Synthetic request failure")
  p
}
r <- rerun_llm_reviews(batch, root, model = "mock", send_to_api = TRUE)
stopifnot(identical(seen, c(16384, 16384)), r$index$llm_status[1] == "COMPLETED",
  r$index$result[1] == "FAIL", r$index$llm_status[2] == "API_ERROR", r$index$rerun_status[3] == "NOT_SELECTED")
stopifnot(identical(before, tools::md5sum(file.path(batch, "review_index.csv"))))
a <- read.csv(file.path(r$run_dir, "attempts.csv")); stopifnot(nrow(a) == 4, all(c(0, 1) %in% a$attempt))
seen <- numeric()
r <- rerun_llm_reviews(batch, root, model = "mock", send_to_api = TRUE, same_budget_first = TRUE)
stopifnot(identical(seen, c(8192, 16384, 8192, 16384)))
stopifnot(retry_budget(list(max_tokens = 4096), 8192)$tokens == 4096)
stopifnot(retry_budget(list(finish_reason = "length", usage = list(completion_tokens = 8192)), 4096)$tokens == 8192)
stopifnot(inherits(try(rerun_llm_reviews(batch, root), silent = TRUE), "try-error"))
unlink(root, recursive = TRUE)
cat("Rerun tests passed: cached diagnostics only, selected statuses, doubled/same-then-double budgets, preserved original results, attempt accounting and continued errors. No API calls.\n")
