source("source/reviewer.R")
source("source/netcdf.R")
source("source/batch.R")
source("source/review_saved.R")

# Missing CFtime must prevent a costly batch instead of producing unverified time coverage.
requireNamespace <- function(package, ...) {
  if (identical(package, "CFtime")) FALSE else base::requireNamespace(package, ...)
}
out <- tempfile()
error <- tryCatch(scan_netcdf_files(list(list(path = "not-opened.nc")), out), error = function(e) conditionMessage(e))
stopifnot(grepl("CFtime", error), grepl("setup.R", error), !dir.exists(out))
error <- tryCatch(check_netcdf("not-opened.nc"), error = function(e) conditionMessage(e))
stopifnot(grepl("CFtime", error))
rm(requireNamespace)
check_scan_dependencies()

# Annual coverage, calendars, missing/duplicate years and genuine full-year bounds.
filename <- parse_netcdf_filename("synthetic_e_mm_region_200001_200212_025_yearly.nc")
status <- function(result, name) result$checks$status[result$checks$check == name]
for (calendar in c("standard", "noleap", "360_day")) {
  edges <- switch(calendar, standard = c(0, 366, 731, 1096), noleap = c(0, 365, 730, 1095),
    `360_day` = c(0, 360, 720, 1080))
  bounds <- rbind(head(edges, -1), tail(edges, -1))
  time <- netcdf_time_checks(colMeans(bounds), "days since 2000-01-01", calendar, filename, bounds)
  stopifnot(status(time, "time_coverage") == "PASS", status(time, "annual_bounds_completeness") == "PASS")
  missing <- netcdf_time_checks(colMeans(bounds)[c(1, 3)], "days since 2000-01-01", calendar, filename)
  stopifnot(status(missing, "time_coverage") == "FAIL", identical(missing$evidence$missing_periods, "2001"))
  duplicate <- netcdf_time_checks(c(0, 10, edges[2:3]), "days since 2000-01-01", calendar, filename)
  stopifnot(status(duplicate, "time_coverage") == "FAIL", duplicate$evidence$duplicate_periods == 1,
    "2000" %in% duplicate$period_details$period[duplicate$period_details$kind == "duplicate"])
}
partial <- parse_netcdf_filename("synthetic_e_mm_region_200001_200208_025_yearly.nc")
time <- netcdf_time_checks(c(0, 366, 731), "days since 2000-01-01", "standard", partial)
stopifnot(status(time, "annual_filename_completeness") == "FAIL")
bounds <- rbind(c(0, 366, 731), c(365, 731, 1096))
time <- netcdf_time_checks(colMeans(bounds), "days since 2000-01-01", "standard", filename, bounds)
stopifnot(status(time, "annual_bounds_completeness") == "FAIL")

# Exercise real NetCDF annual bound variables in both dimension orders, including
# the ambiguous 2-time-by-2-bound shape where names must determine orientation.
annual_dir <- tempfile(); dir.create(annual_dir)
for (time_first in c(FALSE, TRUE)) {
  path <- file.path(annual_dir, paste0("synthetic", as.integer(time_first), "_e_mm_region_200001_200112_025_yearly.nc"))
  lon <- ncdf4::ncdim_def("lon", "degrees_east", c(1, 1.25))
  lat <- ncdf4::ncdim_def("lat", "degrees_north", c(40.25, 40))
  td <- ncdf4::ncdim_def("time", "days since 2000-01-01", c(183, 548.5))
  bd <- ncdf4::ncdim_def("bounds", "", 1:2, create_dimvar = FALSE)
  variable <- ncdf4::ncvar_def("e", "mm", list(lon, lat, td), missval = -9999)
  bound_variable <- ncdf4::ncvar_def("time_bnds", td$units,
    if (time_first) list(td, bd) else list(bd, td), missval = -9999, prec = "double")
  nc <- ncdf4::nc_create(path, list(variable, bound_variable))
  ncdf4::ncvar_put(nc, variable, array(1:8, c(2, 2, 2)))
  bounds <- rbind(c(0, 366), c(366, 731))
  ncdf4::ncvar_put(nc, bound_variable, if (time_first) t(bounds) else bounds)
  ncdf4::ncatt_put(nc, "time", "bounds", "time_bnds")
  ncdf4::ncatt_put(nc, 0, "history", "Synthetic annual sums from complete monthly records")
  ncdf4::nc_close(nc)
  checks <- check_netcdf(path, use_system_tools = FALSE)
  stopifnot(checks$status[checks$check == "annual_bounds_completeness"] == "PASS",
    checks$status[checks$check == "time_coverage"] == "PASS")
}
unlink(annual_dir, recursive = TRUE)

# Inspect PET-like fields and packed storage without guessing signs or quantities.
work <- tempfile(); dir.create(work)
make_input <- function(code, units, values, precision = "float", packed = FALSE) {
  path <- file.path(work, paste0("synthetic_", code, "_", units, "_region_200001_200002_025_monthly.nc"))
  lon <- ncdf4::ncdim_def("lon", "degrees_east", c(1, 1.25))
  lat <- ncdf4::ncdim_def("lat", "degrees_north", c(40.25, 40))
  td <- ncdf4::ncdim_def("time", "days since 2000-01-01", c(0, 31))
  var <- ncdf4::ncvar_def(code, units, list(lon, lat, td), missval = -9999, prec = precision)
  nc <- ncdf4::nc_create(path, var)
  ncdf4::ncvar_put(nc, var, array(values, c(2, 2, 2)))
  if (packed) {
    ncdf4::ncatt_put(nc, code, "scale_factor", 0.1)
    ncdf4::ncatt_put(nc, code, "add_offset", 250)
  }
  ncdf4::ncatt_put(nc, 0, "history", "Synthetic documented source; native monthly means; no unrecorded conversion")
  if (code == "ssrd") ncdf4::ncatt_put(nc, code, "long_name", "Net shortwave land (original SWLAND)")
  ncdf4::nc_close(nc)
  before <- tools::md5sum(path)
  checks <- check_netcdf(path, family = "other", use_system_tools = FALSE)
  stopifnot(identical(before, tools::md5sum(path)), !any(checks$status %in% c("FAIL", "WARN")))
  checks
}
for (input in list(list("ssrd", "Wm-2", 101:108), list("strd", "Wm-2", -70:-63),
    list("sp", "Pa", 100001:100008), list("r", "pct", 60:67),
    list("2sh", "kgkg-1", seq(.001, .008, by = .001)), list("u2m", "ms-1", -4:3),
    list("v2m", "ms-1", -3:4), list("u10", "ms-1", 1:8), list("albedo", "1", rep(.2, 8)))) {
  x <- make_input(input[[1]], input[[2]], input[[3]])
  observed <- attr(x, "review_evidence")
  stopifnot(observed$observed$storage_type == "float", observed$observed$time$count == 2,
    abs(observed$value_scan$global_mean - mean(input[[3]])) < 1e-4,
    all(x$status[x$check == "time_coverage"] == "PASS"))
  if (input[[1]] == "ssrd") stopifnot(grepl("Net shortwave", observed$observed$long_name, fixed = TRUE))
}
x <- make_input("packed", "K", c(NA, 100, 200, 300, NA, 100, 200, 300), "short", TRUE)
evidence <- attr(x, "review_evidence")
stopifnot(evidence$observed$storage_type == "short", evidence$value_scan$global_min == 260,
  evidence$value_scan$global_max == 280, evidence$value_scan$global_mean == 270)
# Invalid budgets must stop before contacting the API.
for (budget in list("8192", 8192.5, Inf, NA_real_, numeric(), 100, 65537))
  stopifnot(inherits(try(validate_completion_budget(budget), silent = TRUE), "try-error"))
validate_completion_budget(16384L)
unlink(work, recursive = TRUE)
cat("Audit regression passed: prerequisite failure before scans, annual calendars/bounds/gaps, PET-like variables, signed fields, packed decoding, storage metadata and integer budgets. No API calls.\n")
