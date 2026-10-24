source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

# Real synthetic arrays: invalid naming/selection must not suppress unrelated evidence.
work <- tempfile(); dir.create(work)
make_input <- function(name, variables = "tp", units = "mm", times = c(0, 366, 731), missing_lat = FALSE) {
  path <- file.path(work, name)
  lon <- ncdf4::ncdim_def("lon", "degrees_east", c(1, 1.25))
  lat <- ncdf4::ncdim_def(if (missing_lat) "row" else "lat", if (missing_lat) "" else "degrees_north", c(40.25, 40))
  td <- ncdf4::ncdim_def("time", "days since 2000-01-01", times)
  defs <- lapply(variables, function(v) ncdf4::ncvar_def(v, units, list(lon, lat, td), missval = -9999))
  nc <- ncdf4::nc_create(path, defs)
  for (v in variables) ncdf4::ncvar_put(nc, v, array(seq_len(4 * length(times)), c(2, 2, length(times))))
  ncdf4::ncatt_put(nc, 0, "history", "cdo mul /synthetic/private/oceanmask_ithaca_global_025.nc input.nc output.nc")
  ncdf4::nc_close(nc)
  path
}
scan <- function(path, ...) {
  before <- tools::md5sum(path)
  checks <- check_netcdf(path, use_system_tools = FALSE, ...)
  stopifnot(identical(before, tools::md5sum(path)), !grepl("/synthetic/private", prepare_review(checks), fixed = TRUE))
  checks
}
status <- function(checks, name) {
  stopifnot(sum(checks$check == name) == 1)
  checks$status[checks$check == name]
}
invalid_date <- make_input("fldas_tp_mm_land_200001_2002112_025_yearly.nc")
checks <- scan(invalid_date)
e <- attr(checks, "review_evidence")
stopifnot(status(checks, "filename_format") == "FAIL", e$filename$fields$end == "2002112",
  status(checks, "lon_resolution") == "PASS", status(checks, "lat_resolution") == "PASS",
  status(checks, "time_coverage") == "NOT_CHECKED", status(checks, "time_internal_coverage") == "PASS",
  e$observed$time$count == 3, e$observed$time$first == "2000-01-01",
  status(checks, "history_provenance") == "PASS", status(checks, "nonfinite_values") == "PASS",
  nrow(attr(checks, "local_slice_statistics")) == 3, e$value_scan$global_max == 12,
  nrow(attr(checks, "local_mask_provenance")$references) == 1)
gapped <- make_input("fldas_tp_mm_land_200001_2003112_025_yearly.nc", times = c(0, 731))
x <- scan(gapped)
stopifnot(status(x, "time_coverage") == "NOT_CHECKED", status(x, "time_internal_coverage") == "FAIL",
  identical(attr(x, "local_period_details")$period, "2001"), status(x, "nonfinite_values") == "PASS")
# Missing unit and coverage claims do not shift dates, invent units, or disable albedo scans.
albedo <- make_input("era5-land_albedo_200001_200003_025_monthly.nc", "albedo", "1", c(0, 31, 60))
x <- scan(albedo); e <- attr(x, "review_evidence")
stopifnot(status(x, "filename_format") == "FAIL", e$filename$fields$units == "", e$filename$fields$spatial_coverage == "",
  e$filename$fields$variable == "albedo", e$observed$units == "1", e$observed$variable == "albedo",
  status(x, "filename_units") == "NOT_CHECKED", status(x, "time_coverage") == "PASS",
  status(x, "lon_resolution") == "PASS", status(x, "nonfinite_values") == "PASS",
  status(x, "history_provenance") == "PASS", !any(x$check %in% c("land_data_coverage", "global_data_coverage")))
grouped <- grouped_checks(x)
stopifnot(status(grouped, "mask_provenance") == "NOT_CHECKED",
  grepl("scope is unavailable", attr(grouped, "review_evidence")$mask_provenance$finding, fixed = TRUE))
# No recognised filename structure: still inspect observed coordinates, timestamps, units and values.
unknown <- make_input("unstructured.nc", "tp", "mm")
x <- scan(unknown)
stopifnot(status(x, "filename_format") == "FAIL", status(x, "time_coverage") == "NOT_CHECKED",
  status(x, "lon_resolution") == "PASS", status(x, "nonempty_time_slices") == "PASS",
  attr(x, "review_evidence")$observed$variable == "tp")
# Wrong units and a masking rename are local flags; all independent checks continue.
mismatch <- make_input("synthetic_tp_mm_region_200001_200212_025_yearly.nc", "mask", "K")
x <- scan(mismatch)
stopifnot(status(x, "filename_variable") == "WARN", status(x, "filename_units") == "FAIL",
  status(x, "time_coverage") == "PASS", status(x, "lon_resolution") == "PASS", status(x, "nonfinite_values") == "PASS")
# Ambiguous variables are never silently chosen, including an unavailable explicit selection.
ambiguous <- make_input("synthetic_tp_mm_region_200001_200212_025_yearly.nc", c("a", "b"))
for (selected in list(NULL, "absent")) {
  x <- scan(ambiguous, variable = selected)
  stopifnot(status(x, "data_variable") == "NOT_CHECKED", status(x, "value_scan") == "NOT_CHECKED",
    status(x, "time_coverage") == "PASS", status(x, "lon_resolution") == "PASS",
    status(x, "history_provenance") == "PASS", is.null(attr(x, "local_slice_statistics")))
}
# Even an unsupported spatial axis leaves a readable time axis and history inspectable.
unsupported <- make_input("synthetic_tp_mm_region_200001_200212_025_yearly.nc", missing_lat = TRUE)
x <- scan(unsupported)
stopifnot(status(x, "lat_coordinates") == "NOT_CHECKED", status(x, "time_coverage") == "PASS",
  status(x, "lon_resolution") == "PASS", status(x, "history_provenance") == "PASS", status(x, "value_scan") == "NOT_CHECKED")
# Scan/export/review separation works for the two original classes of malformed name.
scanned <- scan_netcdf_files(lapply(c(invalid_date, albedo), function(p) list(path = p, use_system_tools = FALSE)), work)
stopifnot(all(scanned$index$checks_status == "COMPLETED"), all(scanned$index$result == "FAIL"),
  all(file.exists(file.path(scanned$index$report_path, "layer-statistics.csv"))),
  all(file.exists(file.path(scanned$index$report_path, "time-period-issues.csv"))))
overview <- read.csv(file.path(scanned$run_dir, "data_overview.csv"))
stopifnot(all(overview$n_layers == 3), all(is.finite(overview$mean)))
# A model PASS cannot erase naming failures, but is allowed in the independent checked groups.
api_request <- function(...) list(model = "synthetic", choices = list(list(finish_reason = "stop",
  message = list(content = as.character(jsonlite::toJSON(list(results = lapply(grouped_check_names(), function(g)
    list(group = g, result = "PASS", finding = "Synthetic supplied evidence inspected.", next_action = "None required."))), auto_unbox = TRUE))))))
set_api_key <- function(...) stop("Unexpected credentials")
unlink(c(invalid_date, albedo))
trial <- run_grouped_pilot(scanned$run_dir, work, send_to_api = TRUE)
stopifnot(all(trial$index$llm_status == "COMPLETED"))
short <- read.csv(file.path(trial$run_dir, "summary_short.csv"))
stopifnot(all(short$variable_and_metadata == "FAIL"), all(short$variable_values == "PASS"),
  all(short$source_and_processing == "PASS"), short$time_coverage[1] == "NOT_CHECKED", short$time_coverage[2] == "PASS",
  short$mask_provenance[1] == "PASS", short$mask_provenance[2] == "NOT_CHECKED")
unlink(work, recursive = TRUE)
cat("Independent checks passed: malformed dates/field counts, observed gaps, unknown claims, wrong units/names, ambiguous variables, unsupported axes, read-only scans, local exports and cached grouped review. No credentials/live inference.\n")
