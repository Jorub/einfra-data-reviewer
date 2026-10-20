source("source/reviewer.R")
source("source/configuration.R")
source("source/netcdf.R")
source("source/batch.R")
source("source/review_saved.R")
source("source/project_setup.R")

# Synthetic files with duplicate basenames in different directories.
work <- tempfile(); dir.create(work)
name <- "synthetic_t2m_degC_region_200001_200002_025_monthly.nc"
for (folder in c("raw", "processed")) {
  dir.create(file.path(work, folder))
  lon <- ncdf4::ncdim_def("lon", "degrees_east", c(1, 1.25))
  lat <- ncdf4::ncdim_def("lat", "degrees_north", c(40.25, 40))
  td <- ncdf4::ncdim_def("time", "days since 2000-01-01", c(0, 31))
  var <- ncdf4::ncvar_def("t2m", "degC", list(lon, lat, td), missval = -9999)
  n <- ncdf4::nc_create(file.path(work, folder, name), var)
  ncdf4::ncvar_put(n, var, array(c(NA, 1:7), c(2, 2, 2)))
  ncdf4::ncatt_put(n, 0, "history", "Synthetic monthly-mean source; cdo subc,273.15 input output")
  ncdf4::nc_close(n)
}
inputs <- file.path(work, "inputs.csv")
write.csv(data.frame(data_file_path = c(file.path("raw", name), file.path("processed", name), "missing.nc"),
  family = "temperature"), inputs, row.names = FALSE)
# Spreadsheet/hand-edited CSV categories may have surrounding or quoted spaces.
input_table <- read.csv(inputs, stringsAsFactors = FALSE)
input_table$family <- c("temperature  ", "  temperature", "   ")
write.csv(input_table, inputs, row.names = FALSE)
specs <- read_data_file_paths(inputs, work)
stopifnot(specs[[1]]$family == "temperature", specs[[2]]$family == "temperature", is.null(specs[[3]]$family))
specs <- configure_scan_specs(specs, use_system_tools = FALSE)
attr(specs, "data_file_paths") <- c(file.path("raw", name), file.path("processed", name), "missing.nc")
# Scanning must not invoke inference or need credentials.
api_request <- function(...) stop("Unexpected API call")
scan <- scan_netcdf_files(specs, file.path(work, "outputs"))
overview <- read.csv(file.path(scan$run_dir, "data_overview.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(overview) == 3, overview$data_file_path[1] != overview$data_file_path[2],
  all(overview$mean[1:2] == 4), all(overview$min[1:2] == 1), all(overview$max[1:2] == 7),
  all(overview$n_layers[1:2] == 2), overview$checks_status[3] == "ERROR",
  all(!is.na(overview$bytes[1:2])), all(overview$source_unchanged_during_scan[1:2]))
original_index <- tools::md5sum(file.path(scan$run_dir, "review_index.csv"))
# Reviewing cached evidence must still work when source files no longer exist.
unlink(file.path(work, c("raw", "processed")), recursive = TRUE)
check_netcdf <- function(...) stop("Unexpected rescan")
api_calls <- 0L
requested_budgets <- numeric()
api_request <- function(route, payload) {
  requested_budgets <<- c(requested_budgets, payload$max_tokens)
  api_calls <<- api_calls + 1L
  if (api_calls == 1L) stop("Synthetic API failure")
  list(model = "fake", choices = list(list(finish_reason = "stop", message = list(content =
    '{"verdict":"PASS","reason":"No issue identified in synthetic evidence","report_markdown":"Synthetic review."}'))),
    usage = list(prompt_tokens = 100, completion_tokens = 30, total_tokens = 130))
}
review <- review_saved_scans(scan$run_dir, file.path(work, "outputs"), model = "fake", max_tokens = 16384L, send_to_api = TRUE)
settings <- jsonlite::read_json(file.path(review$run_dir, "review-settings.json"))
stopifnot(settings$max_tokens == 16384, all(requested_budgets == 16384), api_calls == 2, review$index$llm_status[1] == "API_ERROR", review$index$llm_status[2] == "COMPLETED",
  review$index$checks_status[3] == "ERROR", identical(original_index, tools::md5sum(file.path(scan$run_dir, "review_index.csv"))),
  identical(readLines(file.path(scan$run_dir, "data_overview.csv")), readLines(file.path(review$run_dir, "data_overview.csv"))))
# A preview-only second stage must not submit or mark an LLM review completed.
preview <- review_saved_scans(scan$run_dir, file.path(work, "outputs"), send_to_api = FALSE)
stopifnot(api_calls == 2, all(preview$index$llm_status[1:2] == "NOT_RUN"))
# Setup creates directories/templates and never overwrites private configuration.
project <- file.path(work, "project"); dir.create(project)
dir.create(file.path(project, "config"))
file.copy("config/credentials.example.R", file.path(project, "config", "credentials.example.R"))
private <- file.path(work, "private")
setup_project(project, private)
credentials <- file.path(private, "credentials.R")
writeLines('api_key <- "SYNTHETIC_ONLY_NOT_A_REAL_KEY"', credentials)
before <- tools::md5sum(credentials)
setup_project(project, private)
stopifnot(identical(before, tools::md5sum(credentials)), dir.exists(file.path(project, "output")))
set_api_key(credentials)
stopifnot(identical(.einfra$key, "SYNTHETIC_ONLY_NOT_A_REAL_KEY"))
clear_api_key()
bad <- file.path(private, "bad.R"); writeLines('stop("SYNTHETIC_SECRET_DO_NOT_DISCLOSE")', bad)
message <- tryCatch(set_api_key(bad), error = function(e) conditionMessage(e))
stopifnot(!grepl("SYNTHETIC_SECRET_DO_NOT_DISCLOSE", message, fixed = TRUE))
# Path overrides are separate from credentials; absolute input paths also work.
override <- file.path(work, "paths.R"); writeLines('data_root <- "example-root"', override)
paths <- project_paths(output_dir = "output", local_file = override)
stopifnot(paths$data_root == "example-root", paths$output_dir == "output")
write.csv(data.frame(data_file_path = file.path(work, "absolute.nc")), inputs, row.names = FALSE)
stopifnot(read_data_file_paths(inputs)[[1]]$path == file.path(work, "absolute.nc"))
unlink(work, recursive = TRUE)
cat("Stage integration passed: scans without credentials/API, path-based identities, complete overview, cached review after source removal, API error continuation, unchanged scans, private setup preservation and safe credential errors.\n")
