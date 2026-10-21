# Sources ---------------------------------------------------------------------
source("source/configuration.R")
source("source/merge_reviews.R")

# Configuration ---------------------------------------------------------------
review_dirs <- c(                        # grouped-review folders, oldest to newest
  "",                                   # original full review
  ""                                    # later review of selected files
)
output_dir <- "output"
heatmap_rows_per_page <- 50L

# Merge saved results without scans or LLM calls -------------------------------
paths <- project_paths(output_dir = output_dir)
result <- merge_grouped_reviews(review_dirs, output_dir = paths$output_dir,
  heatmap_rows_per_page = heatmap_rows_per_page)
print(result$run_dir)
