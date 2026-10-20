# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")
source("source/review_saved.R")
source("source/refresh_history.R")

# Configuration ---------------------------------------------------------------
scan_dir <- ""                          # saved scan/review folder with full input paths
output_dir <- "output"
input_rows <- NULL                      # NULL: all completed scans; or e.g. c(2, 8)

# Refresh headers only --------------------------------------------------------
paths <- project_paths(output_dir = output_dir)
result <- refresh_saved_history(scan_dir, output_dir = paths$output_dir, input_rows = input_rows)
print(result$index[, c("filename", "history_refresh_status", "llm_status")], row.names = FALSE)
# Inspect new previews, then point review_scans.R at result$run_dir.
