# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/inventory.R")
source("source/batch.R")

# Configuration ---------------------------------------------------------------
root <- ""                              # temperature folder with raw/processed subfolders
output_dir <- "output"
recursive <- TRUE
scan_values <- TRUE
use_system_tools <- TRUE
include_history <- TRUE

# Discover and scan -----------------------------------------------------------
paths <- project_paths(data_root = root, output_dir = output_dir)
root <- paths$data_root
if (!nzchar(root) || !dir.exists(root)) stop("Set root to the temperature folder.")
if (!dir.exists(paths$output_dir)) dir.create(paths$output_dir, recursive = TRUE)
root <- normalizePath(root, mustWork = TRUE)
out <- normalizePath(paths$output_dir, mustWork = TRUE)
if (identical(root, out) || startsWith(paste0(out, "/"), paste0(root, "/")))
  stop("Keep outputs outside the scanned data folder.")
file_specs <- folder_file_specs(root, family = "temperature", recursive = recursive,
  scan_values = scan_values, use_system_tools = use_system_tools, include_history = include_history)
resolved <- vapply(file_specs, function(spec) spec$path, character(1))
attr(file_specs, "data_file_paths") <- substring(resolved, nchar(root) + 2L)
result <- scan_netcdf_files(file_specs, output_dir = out)
write.csv(data.frame(data_file_path = attr(file_specs, "data_file_paths"), input_path = resolved),
  file.path(result$run_dir, "input-files.csv"), row.names = FALSE)
writeLines(attr(file_specs, "excluded_entries"), file.path(result$run_dir, "excluded-entries.txt"))
print(result$index, row.names = FALSE)
