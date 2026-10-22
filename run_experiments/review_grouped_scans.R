# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

# Configuration ---------------------------------------------------------------
scan_dir <- ""                          # saved scan folder for all Ithaca paper input files
output_dir <- "output"
input_rows <- NULL                      # NULL = every row; test a few files with c(1, 5, 19)
model <- "thinker"
max_tokens <- 20000L
reasoning_effort <- NULL
max_input_bytes <- 64000L
request_timeout <- 600                  # maximum seconds for each complete API request
connection_timeout <- 20                # maximum seconds to establish the connection
max_concurrent_requests <- 1L           # sequential after observed HTTP 429 errors; maximum 4
heatmap_rows_per_page <- 50L             # PNG/PDF overview pagination
prompt_file <- "docs/grouped-review-prompt.md"
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
send_to_api <- FALSE                    # TRUE approves cached evidence for the selected batch
clear_key_after <- TRUE

# Review the complete saved batch ---------------------------------------------
paths <- project_paths(output_dir = output_dir)
if (send_to_api) set_api_key(credentials_file)
result <- run_grouped_pilot(scan_dir, output_dir = paths$output_dir, input_rows = input_rows,
  model = model, max_tokens = max_tokens, reasoning_effort = reasoning_effort,
  max_input_bytes = max_input_bytes, prompt_file = prompt_file, send_to_api = send_to_api,
  request_timeout = request_timeout, connection_timeout = connection_timeout,
  max_concurrent_requests = max_concurrent_requests, heatmap_rows_per_page = heatmap_rows_per_page)
print(result$index, row.names = FALSE)
if (clear_key_after) clear_api_key()
