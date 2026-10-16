# Sources ====================================================================
source("setup.R")
source("R/inventory.R")

# Settings ===================================================================
# Set paths locally; keep private configuration out of public commits.
root <- ""
report_dir <- ""                    # outside the scanned data root
recursive <- TRUE

# Inventory ==================================================================
if (!nzchar(root) || !dir.exists(root)) stop("Set root to the sim directory in Settings.")
if (!nzchar(report_dir)) stop("Set report_dir in Settings.")
inventory <- inventory_netcdf(root, report_dir, recursive = recursive)
summary <- read.csv(file.path(report_dir, "inventory-summary.csv"))
print(summary, row.names = FALSE)
# Share this summary for planning, not the path-containing inventory.csv.
# Counts are variable records, not necessarily unique files. No API call is made.
