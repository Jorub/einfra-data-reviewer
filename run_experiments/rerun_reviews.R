# Sources ---------------------------------------------------------------------
source("source/reviewer.R")
source("source/configuration.R")
source("source/rerun.R")

# Configuration ---------------------------------------------------------------
batch_dir <- ""                      # original batch folder containing review_index.csv
output_dir <- "output"                     # private destination; original results stay unchanged
model <- "thinker"
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
reasoning_effort <- NULL
retry_statuses <- "TOKEN_LIMIT"       # optionally add API_ERROR for one manual retry
same_budget_first <- FALSE            # TRUE: repeat original budget before doubling
fallback_max_tokens <- 8192L          # only used if old metadata cannot establish budget
max_retry_tokens <- 16384L           # default: one retry at double an 8192-token limit
max_input_bytes <- 64000L
send_to_api <- FALSE                  # explicit approval for selected cached evidence/new prompt
clear_key_after <- TRUE

# Retry LLM stage only --------------------------------------------------------
paths <- project_paths(output_dir = output_dir)
if (send_to_api && !exists("key", envir = .einfra, inherits = FALSE)) set_api_key(credentials_file)
result <- rerun_llm_reviews(batch_dir = batch_dir, output_dir = paths$output_dir,
  model = model, reasoning_effort = reasoning_effort, retry_statuses = retry_statuses,
  same_budget_first = same_budget_first, fallback_max_tokens = fallback_max_tokens,
  max_retry_tokens = max_retry_tokens, max_input_bytes = max_input_bytes,
  send_to_api = send_to_api)
print(result$index, row.names = FALSE)
if (clear_key_after) clear_api_key()
