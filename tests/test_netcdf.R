source("R/reviewer.R")
source("R/netcdf.R")
library(ncdf4)
if (!requireNamespace("CFtime", quietly = TRUE)) stop("Install CFtime before running calendar-aware tests.")
make_fixture <- function(path, units = "degC", variable = "t2m", months = 1:24,
                         spacing = 0.25, calendar = "standard", all_missing = FALSE,
                         history = "Synthetic source; monthly mean computed from daily mean inputs") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lon <- ncdim_def("lon", "degrees_east", seq(1, by = spacing, length.out = 4))
  lat <- ncdim_def("lat", "degrees_north", c(40, 40 + spacing))
  # Fixture dates generated in calendar space; no invalid POSIX dates for 360_day.
  cal_days <- CFtime::as_timestamp(CFtime::CFtime("days since 2000-01-01", calendar, 0:740), format = "date")
  offsets <- which(substr(cal_days, 9, 10) == "01")[months] - 1
  td <- ncdim_def("time", "days since 2000-01-01", offsets, calendar = calendar)
  def <- ncvar_def(variable, units, list(lon, lat, td), missval = -9999, prec = "float")
  n <- nc_create(path, def)
  values <- array(rep(c(NA, 2, 5, 10, 15, 20, 25, 30), length(months)), c(4, 2, length(months)))
  if (units == "K") values <- values + 273.15
  if (all_missing) values[, , 5] <- NA
  ncvar_put(n, def, values)
  if (!is.null(history)) ncatt_put(n, 0, "history", history)
  nc_close(n)
}
run_fixture <- function(name = "synthetic_t2m_degC_region_200001_200112_025_monthly.nc", ...) {
  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE))
  f <- file.path(d, name); make_fixture(f, ...)
  before <- tools::md5sum(f)
  x <- check_netcdf(f, use_system_tools = FALSE)
  stopifnot(identical(before, tools::md5sum(f)), !grepl(d, prepare_review(x), fixed = TRUE))
  x
}
x <- run_fixture(); stopifnot(!any(x$status %in% c("FAIL", "WARN")))
stopifnot(attr(x, "review_evidence")$value_scan$slices == 24)
x <- run_fixture(units = "K"); stopifnot(x$status[x$check == "filename_units"] == "FAIL")
x <- run_fixture(name = "synthetic_t2m_K_region_200001_200112_025_monthly.nc", units = "K")
stopifnot(!any(x$status %in% c("FAIL", "WARN")))
x <- run_fixture(months = (1:24)[-5]); stopifnot(x$status[x$check == "time_coverage"] == "FAIL")
x <- run_fixture(months = c(1:4, 4, 6:24)); stopifnot(x$status[x$check == "time_coverage"] == "FAIL")
x <- run_fixture(name = "synthetic_tmin_degC_region_200001_200108_025_monthly.nc", variable = "tmin", months = 1:20)
stopifnot(!any(x$status %in% c("FAIL", "WARN")), !"complete_years" %in% x$check)
x <- run_fixture(name = "synthetic_tmin_degC_region_200001_200108_025_monthly.nc", variable = "tmin", months = 1:20, history = NULL)
stopifnot(x$status[x$check == "provenance_evidence"] == "FAIL", x$status[x$check == "extrema_aggregation_provenance"] == "FAIL")
x <- run_fixture(spacing = .5); stopifnot(x$status[x$check == "lon_resolution"] == "FAIL")
x <- run_fixture(calendar = "360_day"); stopifnot(x$status[x$check == "time_coverage"] == "PASS")
x <- run_fixture(all_missing = TRUE); stopifnot(x$status[x$check == "nonempty_time_slices"] == "FAIL")
# A regional fixture cannot pass global extent; global files also require ocean data.
x <- run_fixture(name = "synthetic_t2m_degC_global_200001_200112_025_monthly.nc")
stopifnot(x$status[x$check == "global_data_coverage"] == "FAIL", x$status[x$check == "lon_global_extent"] == "FAIL")
x <- run_fixture(name = "synthetic_t2m_degC_land_200001_200112_025_monthly.nc")
stopifnot(x$status[x$check == "land_data_coverage"] == "WARN")
x <- run_fixture(name = "synthetic_pr_mm_region_200001_200112_025_monthly.nc", variable = "pr", units = "mm")
stopifnot(attr(x, "review_evidence")$family$family == "precip", !any(x$status %in% c("FAIL", "WARN")))
# History retention/redaction and opt-out.
d <- tempfile(); dir.create(d); f <- file.path(d, "synthetic_t2m_degC_region_200001_200112_025_monthly.nc")
make_fixture(f, history = paste("cdo -addc,273.15 /mnt/private/input.nc /mnt/private/output.nc",
 "api_key=FAKE_HISTORY_CREDENTIAL authorization: Bearer FAKE_BEARER_CREDENTIAL",
 "https://example.org/private?token=FAKE_QUERY_CREDENTIAL", sep = "\n"))
x <- check_netcdf(f, use_system_tools = FALSE); p <- as.character(prepare_review(x))
stopifnot(grepl("-addc,273.15", p, fixed = TRUE))
for (secret in c("/mnt/private", "FAKE_HISTORY_CREDENTIAL", "FAKE_BEARER_CREDENTIAL", "FAKE_QUERY_CREDENTIAL"))
  stopifnot(!grepl(secret, p, fixed = TRUE))
y <- check_netcdf(f, use_system_tools = FALSE, include_history = FALSE)
stopifnot(!attr(y, "review_evidence")$processing_history$available)
stopifnot(sanitize_history(paste(rep("x", 7000), collapse = ""))$truncated)
unlink(d, recursive = TRUE)
# Hourly/daily/annual coverage: no comparison between different products.
fn <- function(freq, start = "200002", end = "200002") parse_netcdf_filename(
  paste0("synthetic_pr_mm_region_", start, "_", end, "_025_", freq, ".nc"))
tm <- function(vals, cal, freq, start = "200002", end = "200002", bounds = NULL)
  netcdf_time_checks(vals, "hours since 2000-02-01", cal, fn(freq, start, end), bounds)
z <- tm(seq(0, by = 24, length.out = 29), "standard", "daily")
stopifnot(z$checks$status[z$checks$check == "time_coverage"] == "PASS")
z <- tm(seq(0, by = 24, length.out = 28), "noleap", "daily")
stopifnot(z$checks$status[z$checks$check == "time_coverage"] == "PASS")
z <- tm(seq(0, by = 24, length.out = 30), "360_day", "daily")
stopifnot(z$checks$status[z$checks$check == "time_coverage"] == "PASS")
z <- tm(0:(29*24-1), "standard", "hourly")
stopifnot(z$checks$status[z$checks$check == "time_coverage"] == "PASS")
z <- tm((0:(29*24-1))[-12], "standard", "hourly")
stopifnot(z$checks$status[z$checks$check == "time_coverage"] == "FAIL")
z <- tm(c(0, 366*24), "standard", "yearly", "200001", "200108")
stopifnot(z$checks$status[z$checks$check == "annual_filename_completeness"] == "FAIL")
stopifnot(all(vapply(c("evap", "other", "precip", "runoff", "snow", "soilmoisture", "temperature"),
  function(f) netcdf_family("example.nc", "unknown", f)$family == f, logical(1))))
cat("Filename-derived multi-family NetCDF tests passed: Celsius/Kelvin, precipitation, monthly August, provenance, missing/duplicate records, CF calendars, hourly gaps, annual completeness, coverage policy, redaction and unchanged inputs.\n")
# Valid global-domain fixtures may be pole-to-pole or limited to 60S–60N.
d <- tempfile(); dir.create(d)
make_domain <- function(scale, latitude, missing = FALSE) {
  f <- file.path(d, paste0("synthetic_t2m_K_", scale, "_200001_200001_025_monthly.nc"))
  lon <- ncdim_def("lon", "degrees_east", seq(-179.875, 179.875, by = .25))
  lat <- ncdim_def("lat", "degrees_north", latitude)
  time <- ncdim_def("time", "days since 2000-01-01", 0)
  v <- ncvar_def("t2m", "K", list(lon, lat, time), -9999)
  n <- nc_create(f, v)
  vals <- array(280, c(length(lon$vals), length(latitude), 1))
  if (missing) vals[seq_len(floor(length(vals) * 2 / 3))] <- NA
  ncvar_put(n, v, vals)
  ncatt_put(n, 0, "source", "Synthetic documented test product")
  ncatt_put(n, 0, "history", "Synthetic fixture construction; native monthly values, no temporal aggregation")
  ncatt_put(n, "t2m", "cell_methods", "time: mean")
  nc_close(n)
  check_netcdf(f, use_system_tools = FALSE)
}
z <- make_domain("global", seq(-89.875, 89.875, by = .25))
stopifnot(!any(z$status %in% c("FAIL", "WARN")))
z <- make_domain("global", seq(-59.875, 59.875, by = .25))
stopifnot(!any(z$status %in% c("FAIL", "WARN")))
z <- make_domain("land", seq(-89.875, 89.875, by = .25), TRUE)
stopifnot(z$status[z$check == "land_data_coverage"] == "PASS")
stopifnot(!"lat_global_extent" %in% z$check)
unlink(d, recursive = TRUE)
cat("Global full/limited latitude and approximate land-fraction coverage tests passed.\n")

# Wrong filename grid code is a naming failure even when coordinates are 0.25.
x <- run_fixture(name = "synthetic_t2m_degC_region_200001_200112_050_monthly.nc")
stopifnot(x$status[x$check == "resolution_code"] == "FAIL", x$status[x$check == "lon_resolution"] == "PASS")
# Supplied native-frequency documentation is evidence; no local aggregation command is required.
x <- run_fixture(history = "Native monthly source; original values already Celsius; only spatial remapping was performed")
p <- prepare_review(x)
stopifnot(!any(x$status == "FAIL"), grepl("raw does not mean untouched downloads", p, fixed = TRUE),
          grepl("Do not invent a local temporal aggregation requirement", p, fixed = TRUE))
cat("Project raw-stage, native-frequency source and fixed-grid convention tests passed.\n")

# Missing history remains a deterministic provenance FAIL despite other notes.
d <- tempfile(); dir.create(d)
f <- file.path(d, "synthetic_t2m_degC_region_200001_200112_025_monthly.nc")
make_fixture(f, history = NULL)
x <- check_netcdf(f, use_system_tools = FALSE, provenance_notes = "Documented synthetic native monthly source")
stopifnot(x$status[x$check == "history_provenance"] == "FAIL")
n <- nc_open(f, write = TRUE); ncatt_put(n, 0, "history", "   "); nc_close(n)
x <- check_netcdf(f, use_system_tools = FALSE)
stopifnot(x$status[x$check == "history_provenance"] == "FAIL")
n <- nc_open(f, write = TRUE); ncatt_put(n, 0, "history", "Documented native monthly source"); nc_close(n)
x <- check_netcdf(f, use_system_tools = FALSE, include_history = FALSE)
stopifnot(x$status[x$check == "history_provenance"] == "PASS",
          attr(x, "review_evidence")$processing_history$present_in_file,
          !attr(x, "review_evidence")$processing_history$available)
unlink(d, recursive = TRUE)
cat("Mandatory history tests passed: missing/empty histories fail, external notes cannot override, withheld history remains distinguishable from absent history.\n")

# Team-facing diagnostics: all dates locally, statistics and recorded conversions.
x <- run_fixture(months = (1:24)[-5], history = "cdo -subc,273.15 input output; cdo -mulc,1e-3 input output")
stopifnot(identical(attr(x, "local_period_details")$period, "2000-05"))
d <- tempfile(); dir.create(d)
write_diagnostic_tables(x, d)
layer <- read.csv(file.path(d, "layer-statistics.csv"))
summary <- read.csv(file.path(d, "file-summary.csv"))
ops <- read.csv(file.path(d, "recorded-conversions.csv"))
stopifnot(nrow(layer) == 23, abs(layer$mean[1] - mean(c(2, 5, 10, 15, 20, 25, 30))) < 1e-10,
  layer$min[1] == 2, layer$max[1] == 30, !anyNA(layer$timestamp),
  summary$n_layers == 23, summary$lon_first == 1, summary$lon_last == 1.75,
  abs(summary$mean - layer$mean[1]) < 1e-10, summary$missing_period_count == 1,
  identical(ops$operator, c("subc", "mulc")), identical(ops$constant, c(273.15, .001)))
# API evidence remains compact even for long gaps; local list has every period.
f <- parse_netcdf_filename("synthetic_t2m_degC_region_200001_200112_025_daily.nc")
t <- netcdf_time_checks(c(0, 730), "days since 2000-01-01", "standard", f)
stopifnot(nrow(t$period_details) > 24, length(t$evidence$missing_periods) == 24,
  sum(t$period_details$kind == "missing") == t$evidence$missing_period_count)
unlink(d, recursive = TRUE)
cat("Team diagnostic exports passed: complete gap list, means/extrema, coordinates, layer counts and recorded numeric conversions.\n")
