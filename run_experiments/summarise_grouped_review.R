# Sources ---------------------------------------------------------------------
source("source/grouped_review.R")

# Configuration ---------------------------------------------------------------
review_dir <- ""                       # grouped-review folder containing summary.csv

# Derive a short overview from saved results -----------------------------------
write_grouped_short_summary(review_dir)
