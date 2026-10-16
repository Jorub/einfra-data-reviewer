# Sources ====================================================================
source("setup.R")
source("R/reviewer.R")
source("R/netcdf.R")
source("R/inventory.R")
source("R/batch.R")

# Settings ===================================================================
root <- ""                           # temperature folder; includes raw/processed below it
output_dir <- ""                     # private persistent directory outside root
family <- "temperature"
recursive <- TRUE
scan_values <- TRUE
use_system_tools <- TRUE
include_history <- TRUE
model <- "thinker"
reasoning_effort <- NULL
max_tokens <- 8192L
max_input_bytes <- 64000L
send_to_api <- FALSE                  # explicit approval for discovered files' review payloads
clear_key_after <- TRUE

# Discover files =============================================================
if (!nzchar(root) || !dir.exists(root)) stop("Set root to the temperature folder in Settings.")
if (!nzchar(output_dir)) stop("Set output_dir in Settings.")
if (!dir.exists(output_dir) && !dir.create(output_dir, recursive = TRUE)) stop("Cannot create output_dir.")
root <- normalizePath(root, mustWork = TRUE)
output_dir <- normalizePath(output_dir, mustWork = TRUE)
if (identical(root, output_dir) || startsWith(paste0(output_dir, "/"), paste0(root, "/")))
  stop("Keep output_dir outside the scanned temperature folder.")
file_specs <- folder_file_specs(root, family = family, recursive = recursive,
  scan_values = scan_values, use_system_tools = use_system_tools, include_history = include_history)
planned_paths <- vapply(file_specs, function(s) s$path, character(1))
plan <- data.frame(filename = basename(planned_paths), path = planned_paths,
  bytes = file.info(planned_paths)$size, stringsAsFactors = FALSE)
print(plan[c("filename", "bytes")], row.names = FALSE)
message("Discovered ", nrow(plan), " files (", round(sum(plan$bytes, na.rm = TRUE) / 1024^3, 2),
        " GiB). NetCDF checks and API calls, if enabled, will run sequentially.")
# No paths or file expectations are copied into public code; inspect the discovered list.

# Authenticate once and run ==================================================
if (send_to_api && !exists("key", envir = .einfra, inherits = FALSE)) set_api_key()
result <- run_netcdf_reviews(file_specs, output_dir = output_dir, model = model,
  max_tokens = max_tokens, reasoning_effort = reasoning_effort,
  send_to_api = send_to_api, max_input_bytes = max_input_bytes)
write.csv(plan, file.path(result$run_dir, "input-files.csv"), row.names = FALSE)
writeLines(attr(file_specs, "excluded_entries"), file.path(result$run_dir, "excluded-entries.txt"))
print(result$index, row.names = FALSE)
if (send_to_api && clear_key_after) clear_api_key()
