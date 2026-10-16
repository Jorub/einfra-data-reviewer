# Sources ====================================================================
source("setup.R")
source("R/reviewer.R")
source("R/netcdf.R")
source("R/batch.R")

# Settings ===================================================================
output_dir <- ""                     # private persistent reports directory
model <- "thinker"
max_tokens <- 8192L
reasoning_effort <- NULL
clear_key_after <- TRUE               # clear in-memory key when the batch finishes
send_to_api <- FALSE                  # explicit approval for the three selected payloads
# This pilot supports monthly Celsius temperature on regular lon/lat grids only.
# Enter each file's own expected dates, resolution and spatial extent below.
file_specs <- list(
  list(path="",expected_units="degC",resolution=0.25,start_month="2000-01",
       end_month="2019-12",global_grid=TRUE,include_history=TRUE),
  list(path="",expected_units="degC",resolution=0.25,start_month="2000-01",
       end_month="2019-12",global_grid=TRUE,include_history=TRUE),
  list(path="",expected_units="degC",resolution=0.25,start_month="2000-01",
       end_month="2019-12",global_grid=TRUE,include_history=TRUE)
)

# Authentication once per session ============================================
# Inspect previews with send_to_api=FALSE before approving remote submission.
# A subsequent full rerun will rescan files; resume/retry-only support is future work.
if(send_to_api && !exists("key",envir=.einfra,inherits=FALSE)) set_api_key()

# Sequential scan; per-file failures are recorded, not allowed to end the loop.
result <- run_netcdf_reviews(file_specs,output_dir=output_dir,model=model,
  max_tokens=max_tokens,reasoning_effort=reasoning_effort,send_to_api=send_to_api)
print(result$index,row.names=FALSE)
if(send_to_api && clear_key_after) clear_api_key()
