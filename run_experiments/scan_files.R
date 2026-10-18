# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")

# Configuration ---------------------------------------------------------------
data_file_paths <- "config/data_file_paths.csv"
data_root <- ""                         # base directory for relative input paths
output_dir <- "output"                  # local overrides: config/paths.local.R
scan_values <- TRUE
use_system_tools <- TRUE
include_history <- TRUE

# Scan and save ---------------------------------------------------------------
paths <- project_paths(data_root, output_dir)
file_specs <- read_data_file_paths(data_file_paths, data_root = paths$data_root)
file_specs <- configure_scan_specs(file_specs, scan_values = scan_values,
  use_system_tools = use_system_tools, include_history = include_history)
result <- scan_netcdf_files(file_specs, output_dir = paths$output_dir)
print(result$index, row.names = FALSE)
