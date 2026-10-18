# Sources ---------------------------------------------------------------------
source("source/inventory.R")
source("source/configuration.R")

# Settings ===================================================================
# Set paths locally; keep private configuration out of public commits.
root <- ""
report_dir <- "output"                    # outside the scanned data root
recursive <- TRUE

# Inventory -------------------------------------------------------------------
paths <- project_paths(data_root = root, output_dir = report_dir)
root <- paths$data_root
report_dir <- paths$output_dir
if (!nzchar(root) || !dir.exists(root)) stop("Set root to the sim directory in Settings.")
if (!nzchar(report_dir)) stop("Set report_dir in Settings.")
inventory <- inventory_netcdf(root, report_dir, recursive = recursive)
summary <- read.csv(file.path(report_dir, "inventory-summary.csv"))
print(summary, row.names = FALSE)
# Share this summary for planning, not the path-containing inventory.csv.
# Counts are variable records, not necessarily unique files. No API call is made.
