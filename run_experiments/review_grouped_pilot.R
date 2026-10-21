# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

# Configuration ---------------------------------------------------------------
scan_dir <- ""                          # existing saved scan folder
output_dir <- "output"
input_rows <- c(1, 5, 13)               # choose rows from that scan's review_index.csv
model <- "thinker"
max_tokens <- 20000L
reasoning_effort <- NULL
max_input_bytes <- 64000L
request_timeout <- 600                  # maximum seconds for each complete API request
connection_timeout <- 20                # maximum seconds to establish the connection
max_concurrent_requests <- 1L           # set 4 for concurrent LLM review; account-wide maximum is 4
heatmap_rows_per_page <- 50L             # PNG/PDF overview pagination
prompt_file <- "docs/grouped-review-prompt.md"
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
send_to_api <- FALSE                    # preview first; TRUE explicitly approves selected evidence
clear_key_after <- TRUE

# Pilot selected cached files -------------------------------------------------
paths <- project_paths(output_dir = output_dir)
if (send_to_api) set_api_key(credentials_file)
result <- run_grouped_pilot(scan_dir, output_dir = paths$output_dir, input_rows = input_rows,
  model = model, max_tokens = max_tokens, reasoning_effort = reasoning_effort,
  max_input_bytes = max_input_bytes, prompt_file = prompt_file, send_to_api = send_to_api,
  request_timeout = request_timeout, connection_timeout = connection_timeout,
  max_concurrent_requests = max_concurrent_requests, heatmap_rows_per_page = heatmap_rows_per_page)
print(result$index, row.names = FALSE)
if (clear_key_after) clear_api_key()
