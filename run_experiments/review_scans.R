# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/review_saved.R")

# Configuration ---------------------------------------------------------------
scan_dir <- ""                          # saved batch-* folder, not a data directory
output_dir <- "output"
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
model <- "thinker"
max_tokens <- 8192L                      # unchanged budget; includes reasoning
reasoning_effort <- NULL
max_input_bytes <- 64000L
send_to_api <- FALSE                    # TRUE approves selected cached evidence for submission
clear_key_after <- TRUE

# Review saved scans ----------------------------------------------------------
paths <- project_paths(output_dir = output_dir)
if (send_to_api) set_api_key(credentials_file)
result <- review_saved_scans(scan_dir, output_dir = paths$output_dir, model = model,
  max_tokens = max_tokens, reasoning_effort = reasoning_effort,
  max_input_bytes = max_input_bytes, send_to_api = send_to_api)
print(result$index, row.names = FALSE)
if (clear_key_after) clear_api_key()
