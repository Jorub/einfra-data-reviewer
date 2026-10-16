# First step for the sim audit: local metadata inventory only.
source("setup.R")
source("R/inventory.R")

root <- readline("Path to the sim folder: ")
report_dir <- readline("Private report directory outside sim: ")
inventory <- inventory_netcdf(root, report_dir, recursive = TRUE)

summary <- read.csv(file.path(report_dir, "inventory-summary.csv"))
print(summary, row.names = FALSE)
# Share this summary for planning, not the path-containing inventory.csv.
# Counts are variable records, not necessarily unique files.
