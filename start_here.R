# Sources ====================================================================
source("setup.R")
source("R/reviewer.R")

# Settings ===================================================================
report_dir <- ""                    # required only if send_to_api is TRUE
model <- "thinker"
reasoning_effort <- NULL
max_tokens <- 8192L
send_to_api <- FALSE                 # synthetic offline example by default
required_columns <- c("id", "value")
numeric_columns <- "value"
ranges <- list(value = c(0, 10))
unique_key <- "id"

# Synthetic offline pilot ====================================================
f <- tempfile(fileext = ".csv")
write.csv(data.frame(id = c(1, 1, 3), value = c(2, -4, NA)), f, row.names = FALSE)
checks <- check_csv(f, required_columns = required_columns,
                    numeric_columns = numeric_columns, ranges = ranges,
                    unique_key = unique_key)
print(checks)
unlink(f)
preview <- prepare_review(checks)
cat(preview, "\n")

# Optional remote review =====================================================
if (send_to_api) {
  if (!nzchar(report_dir)) stop("Set report_dir in Settings before enabling the API.")
  if (!exists("key", envir = .einfra, inherits = FALSE)) set_api_key()
  run <- review_checks(checks, model = model, approved_payload = preview,
    send = TRUE, report_dir = report_dir, max_tokens = max_tokens,
    reasoning_effort = reasoning_effort)
  print(read.csv(file.path(run, "summary.csv")), row.names = FALSE)
}
# API preflight is available separately via set_api_key() and list_models().
