# Sources ---------------------------------------------------------------------
source("source/reviewer.R")
source("source/configuration.R")

# Configuration ---------------------------------------------------------------
report_dir <- "output"                    # required only if send_to_api is TRUE
model <- "thinker"
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
reasoning_effort <- NULL
max_tokens <- 8192L
send_to_api <- FALSE                 # synthetic offline example by default
required_columns <- c("id", "value")
numeric_columns <- "value"
ranges <- list(value = c(0, 10))
unique_key <- "id"

# Synthetic offline pilot -----------------------------------------------------
paths <- project_paths(output_dir = report_dir)
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
  if (!exists("key", envir = .einfra, inherits = FALSE)) set_api_key(credentials_file)
  run <- review_checks(checks, model = model, approved_payload = preview,
    send = TRUE, report_dir = paths$output_dir, max_tokens = max_tokens,
    reasoning_effort = reasoning_effort)
  print(read.csv(file.path(run, "summary.csv")), row.names = FALSE)
}
# API preflight is available separately after loading private credentials.
