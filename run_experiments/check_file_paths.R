# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/input_paths.R")

# Configuration ---------------------------------------------------------------
data_file_paths <- "config/data_file_paths.csv"
data_root <- ""                         # base directory for relative input paths
output_dir <- "output"                  # complete missing_files.csv is saved here

# List missing inputs without scanning ----------------------------------------
paths <- project_paths(data_root = data_root, output_dir = output_dir)
file_specs <- read_data_file_paths(data_file_paths, data_root = paths$data_root)
missing_files <- missing_input_files(file_specs)
check_input_files(file_specs, report_dir = paths$output_dir) # saves/prints all paths before stopping
message("All ", length(file_specs), " input files exist. No NetCDF scan or API calls performed.")
