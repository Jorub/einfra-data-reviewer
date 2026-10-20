source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")
source("source/review_saved.R")
source("source/refresh_history.R")

# Preserve numerical operators while hiding actual paths, URLs and credentials.
history <- paste("cdo seltimestep,1/20 /private/input.nc /private/output.nc",
  "cdo -seltimestep,1/20/2 './private/a.nc' '../private/b.nc'",
  "cdo remapnn,/private/grid.nc /private/2024/input.nc ~/private/output.nc",
  "cdo -selindexbox,1,20,1,40 C:\\private\\input.nc output.nc",
  "api_key=FAKE_HISTORY_TOKEN https://example.org/private/input.nc",
  "cdo seltimestep,1/20 /private/seltimestep,1/20/file.nc /1/20",
  sep = "\n")
redacted <- sanitize_history(history)
stopifnot(grepl("seltimestep,1/20", redacted$text, fixed = TRUE),
  grepl("-seltimestep,1/20/2", redacted$text, fixed = TRUE),
  grepl("-selindexbox,1,20,1,40", redacted$text, fixed = TRUE))
for (secret in c("/private/", "../private/", "C:\\private", "FAKE_HISTORY_TOKEN", "https://example.org"))
  stopifnot(!grepl(secret, redacted$text, fixed = TRUE))
stopifnot(!grepl("__CDO_NUMERIC_RANGE_SLASH__", redacted$text, fixed = TRUE))
# A history-only refresh retains numeric diagnostics and original cache.
work <- tempfile(); dir.create(work)
path <- file.path(work, "synthetic_t2m_degC_region_200001_200002_025_monthly.nc")
lon <- ncdf4::ncdim_def("lon", "degrees_east", c(1, 1.25))
lat <- ncdf4::ncdim_def("lat", "degrees_north", c(40, 40.25))
td <- ncdf4::ncdim_def("time", "days since 2000-01-01", c(0, 31))
var <- ncdf4::ncvar_def("t2m", "degC", list(lon, lat, td), missval = -9999)
nc <- ncdf4::nc_create(path, var)
ncdf4::ncvar_put(nc, var, array(1:8, c(2, 2, 2)))
ncdf4::ncatt_put(nc, 0, "history", "Synthetic monthly means; cdo seltimestep,1/20 /private/input.nc /private/output.nc")
ncdf4::nc_close(nc)
checks <- check_netcdf(path, use_system_tools = FALSE)
# Simulate a cache produced by the old, damaging sanitizer.
evidence <- attr(checks, "review_evidence")
evidence$processing_history$text <- "cdo seltimestep,1[PATH REDACTED] [PATH REDACTED] [PATH REDACTED]"
attr(checks, "review_evidence") <- evidence
stamp <- source_file_stamp(path)
attr(checks, "scan_record") <- list(before = stamp, after = stamp, source_unchanged_during_scan = TRUE)
cache <- file.path(work, "original"); dir.create(cache)
saveRDS(checks, file.path(cache, "local-diagnostics.rds"))
index <- data.frame(filename = basename(path), input_path = path, checks_status = "COMPLETED",
  report_path = cache, llm_status = "COMPLETED", result = "FAIL", reason = "Old interpretation")
write.csv(index, file.path(cache, "review_index.csv"), row.names = FALSE)
original <- tools::md5sum(file.path(cache, "local-diagnostics.rds"))
check_netcdf <- function(...) stop("No rescan permitted")
api_request <- function(...) stop("No API permitted")
result <- refresh_saved_history(cache, file.path(work, "out"))
stopifnot(result$index$llm_status == "NOT_RUN", result$index$history_refresh_status == "REFRESHED")
updated <- read_saved_checks(result$index$report_path)
stopifnot(identical(unname(as.matrix(updated)), unname(as.matrix(checks))))
stopifnot(identical(attr(updated, "local_slice_statistics"), attr(checks, "local_slice_statistics")),
  identical(attr(updated, "review_evidence")$value_scan, attr(checks, "review_evidence")$value_scan),
  grepl("seltimestep,1/20", prepare_review(updated), fixed = TRUE),
  identical(original, tools::md5sum(file.path(cache, "local-diagnostics.rds"))))
# Changed input identity must block reuse rather than quietly merge old statistics.
Sys.setFileTime(path, Sys.time() + 60)
blocked <- refresh_saved_history(cache, file.path(work, "out"))
stopifnot(blocked$index$history_refresh_status == "ERROR", blocked$index$llm_status == "PREPARATION_ERROR")
unlink(work, recursive = TRUE)
cat("History regression passed: numeric ranges retained, paths/secrets hidden, header-only refresh preserves statistics/cache and blocks changed files.\n")
