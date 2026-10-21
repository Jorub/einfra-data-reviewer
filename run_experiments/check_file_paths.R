# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/input_paths.R")

# Configuration ---------------------------------------------------------------
data_file_paths <- "config/data_file_paths.csv"
data_root <- ""                         # base directory for relative input paths

# List missing inputs without scanning ----------------------------------------
paths <- project_paths(data_root = data_root)
file_specs <- read_data_file_paths(data_file_paths, data_root = paths$data_root)
missing_files <- missing_input_files(file_specs)
if (length(missing_files)) print(missing_files)
check_input_files(file_specs)            # stops with every missing full path
message("All ", length(file_specs), " input files exist. No NetCDF scan or API calls performed.")
