# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")

# Configuration ---------------------------------------------------------------
data_file_path <- ""                    # absolute path or relative to data_root
family <- NULL                          # optional override; otherwise infer
variable <- NULL                        # optional actual variable selector
provenance_notes <- ""
data_root <- ""
output_dir <- "output"
scan_values <- TRUE
use_system_tools <- TRUE
include_history <- TRUE

# Scan and save ---------------------------------------------------------------
paths <- project_paths(data_root, output_dir)
if (!nzchar(data_file_path)) stop("Set data_file_path.")
absolute <- grepl("^(/|~|[A-Za-z]:)", data_file_path)
if (!absolute && !nzchar(paths$data_root)) stop("Relative input requires data_root.")
resolved <- if (absolute) path.expand(data_file_path) else file.path(paths$data_root, data_file_path)
file_specs <- list(list(path = resolved, family = family, variable = variable,
  provenance_notes = provenance_notes, scan_values = scan_values,
  use_system_tools = use_system_tools, include_history = include_history))
attr(file_specs, "data_file_paths") <- data_file_path
result <- scan_netcdf_files(file_specs, output_dir = paths$output_dir)
print(result$index, row.names = FALSE)
