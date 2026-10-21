# Sources ---------------------------------------------------------------------
source("source/grouped_review.R")

# Configuration ---------------------------------------------------------------
review_dir <- ""                       # grouped-review folder containing summary.csv
heatmap_rows_per_page <- 50L             # long file lists become readable PDF/PNG pages

# Derive a short overview from saved results -----------------------------------
write_grouped_short_summary(review_dir, heatmap_rows_per_page = heatmap_rows_per_page)
