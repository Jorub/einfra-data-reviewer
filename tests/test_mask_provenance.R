source("source/reviewer.R")
source("source/netcdf.R")
source("source/review_saved.R")
source("source/llm.R")
source("source/grouped_review.R")

make_mask_checks <- function(history, scope = "land", local = TRUE, withheld = FALSE) {
  checks <- data.frame(check = c("filename_format", "history_provenance"),
    status = c("PASS", if (is.null(history)) "FAIL" else "PASS"), detail = "Synthetic inspected metadata")
  attr(checks, "review_evidence") <- list(filename = list(basename = "synthetic_e_mm_land_200001_200112_025_yearly.nc",
    fields = list(spatial_coverage = scope, units = "mm")), observed = list(variable = "e", units = "mm"),
    processing_history = if (withheld) list(available = FALSE, present_in_file = TRUE, included_in_payload = FALSE) else
      if (is.null(history)) list(available = FALSE, present_in_file = FALSE) else c(list(available = TRUE), sanitize_history(history)))
  if (local && !withheld) attr(checks, "local_mask_provenance") <- mask_history_observation(history, scope, "synthetic raw history")
  checks
}
mask_result <- function(checks) attr(grouped_checks(checks), "review_evidence")$mask_provenance$rule_result
approved <- "cdo mul /private/masks/oceanmask_ithaca_global_025.nc input.nc output.nc"
generic <- "cdo ifthen /private/masks/mask_land_ocean_025.nc input.nc output.nc"
no_mask <- "cdo yearmean monthly.nc yearly.nc"
stopifnot(mask_result(make_mask_checks(approved)) == "PASS",
  mask_result(make_mask_checks(generic)) == "REVIEW",
  mask_result(make_mask_checks(no_mask)) == "FAIL", mask_result(make_mask_checks(NULL)) == "FAIL",
  mask_result(make_mask_checks(approved, scope = "global")) == "NOT_CHECKED",
  mask_result(make_mask_checks(approved, withheld = TRUE)) == "NOT_CHECKED",
  mask_result(make_mask_checks(approved, local = FALSE)) == "NOT_CHECKED",
  mask_result(make_mask_checks("cdo mul oceanmask_ithaca_global_025.nc input.nc output.nc", local = FALSE)) == "PASS")
# A bare reference, creation of the mask itself, or a variable rename does not establish mask application.
stopifnot(mask_result(make_mask_checks("Reference file oceanmask_ithaca_global_025.nc")) == "REVIEW",
  mask_result(make_mask_checks("cdo copy source.nc oceanmask_ithaca_global_025.nc")) == "REVIEW",
  mask_result(make_mask_checks("cdo chname,mask,e input.nc output.nc")) == "FAIL",
  mask_result(make_mask_checks(paste("cdo copy a.nc oceanmask_ithaca_global_025.nc", approved, sep = "\n"))) == "PASS")
quoted <- 'cdo mul "/private/shared masks/oceanmask_ithaca_global_025.nc" input.nc output.nc'
refs <- mask_history_references(quoted, "synthetic")
stopifnot(refs$recorded_path == "/private/shared masks/oceanmask_ithaca_global_025.nc", refs$recorded_application)
malformed <- data.frame(check = "filename_format", status = "FAIL", detail = "Uninspected contents")
stopifnot(mask_result(malformed) == "NOT_CHECKED")
# Recover identity/path from a cached raw ncdump header, without opening the original source.
cached <- make_mask_checks(approved, local = FALSE)
attr(cached, "local_tool_results") <- list(ncdump_header = list(status = "PASS", output = c("// global attributes:",
  paste0(" :history = ", jsonlite::toJSON(approved, auto_unbox = TRUE), ";"))))
stopifnot(mask_result(cached) == "PASS")
parsed <- grouped_checks(cached)
stopifnot(attr(parsed, "local_mask_provenance")$references$recorded_path == "/private/masks/oceanmask_ithaca_global_025.nc")
# Exact mask rules cannot be reversed by model interpretation, including optimistic PASS or missing response.
answer <- data.frame(group = grouped_check_names(), result = "PASS", finding = "Synthetic finding", next_action = "None.")
stopifnot(guard_grouped_results(grouped_checks(make_mask_checks(generic)), answer)$result[6] == "REVIEW",
  guard_grouped_results(grouped_checks(make_mask_checks(no_mask)), answer)$result[6] == "FAIL",
  guard_grouped_results(parsed, NULL)$result[6] == "PASS")
prompt <- prepare_grouped_review(cached)
stopifnot(grepl("oceanmask_ithaca_global_025.nc", prompt, fixed = TRUE),
  !grepl("/private", prompt, fixed = TRUE), !grepl("recorded_path", prompt, fixed = TRUE))
# Privacy: raw headers/credential text are never copied into the submitted context or path table.
secret <- make_mask_checks(paste(approved, "api_key=FAKE_MASK_SECRET", sep = "\n"))
stopifnot(!grepl("FAKE_MASK_SECRET", prepare_grouped_review(secret), fixed = TRUE))
sensitive <- mask_history_references("cdo mul /api_key=FAKE_MASK_SECRET/oceanmask_ithaca_global_025.nc a.nc b.nc", "synthetic")
stopifnot(!any(grepl("FAKE_MASK_SECRET", unlist(sensitive), fixed = TRUE)))

work <- tempfile(); dir.create(work)
# A three-file saved-scan test exercises the runner and six-category exports with mocked inference.
scan <- file.path(work, "scan-mask-test"); dir.create(scan)
checks_list <- lapply(c(approved, generic, no_mask), make_mask_checks)
index <- data.frame(filename = paste0("synthetic-", 1:3, "_e_mm_land_200001_200112_025_yearly.nc"),
  input_path = paste0("/synthetic/", 1:3, ".nc"), checks_status = "COMPLETED",
  report_path = file.path(scan, sprintf("file-%03d", 1:3)))
for (i in 1:3) {
  dir.create(index$report_path[i]); saveRDS(checks_list[[i]], file.path(index$report_path[i], "local-diagnostics.rds"))
}
write.csv(index, file.path(scan, "review_index.csv"), row.names = FALSE)
# Fresh scans retain local mask references even when external tools are disabled.
nc_path <- file.path(work, "synthetic_t2m_degC_land_200001_200001_025_monthly.nc")
lon <- ncdf4::ncdim_def("lon", "degrees_east", c(0, 0.25))
lat <- ncdf4::ncdim_def("lat", "degrees_north", c(0, 0.25))
time <- ncdf4::ncdim_def("time", "days since 2000-01-01", 0, calendar = "standard")
var <- ncdf4::ncvar_def("t2m", "degC", list(lon, lat, time), missval = -9999)
nc <- ncdf4::nc_create(nc_path, var)
ncdf4::ncvar_put(nc, var, array(c(NA, NA, NA, 20), c(2, 2, 1)))
ncdf4::ncatt_put(nc, 0, "history", approved); ncdf4::nc_close(nc)
nc_before <- tools::md5sum(nc_path)
fresh <- check_netcdf(nc_path, use_system_tools = FALSE)
stopifnot(mask_result(fresh) == "PASS", identical(nc_before, tools::md5sum(nc_path)),
  attr(fresh, "local_mask_provenance")$references$recorded_path == "/private/masks/oceanmask_ithaca_global_025.nc",
  !grepl("/private", prepare_grouped_review(fresh), fixed = TRUE))
source_files <- list.files(scan, recursive = TRUE, full.names = TRUE)
before <- tools::md5sum(source_files)
check_netcdf <- function(...) stop("Unexpected source-data access")
set_api_key <- function(...) stop("Unexpected credential access")
api_calls <- 0L
api_request <- function(route, payload, request_timeout, connection_timeout) {
  api_calls <<- api_calls + 1L
  stopifnot(!grepl("/private", payload$messages[[1]]$content, fixed = TRUE))
  text <- jsonlite::toJSON(list(results = lapply(grouped_check_names(), function(group)
    list(group = group, result = "PASS", finding = "Synthetic supplied evidence inspected.", next_action = "None required."))),
    auto_unbox = TRUE)
  list(model = "synthetic", choices = list(list(finish_reason = "stop", message = list(content = text))),
    usage = list(completion_tokens = 100))
}
trial <- run_grouped_pilot(scan, work, input_rows = 1:3, model = "synthetic", send_to_api = TRUE)
short <- read.csv(file.path(trial$run_dir, "summary_short.csv"))
stopifnot(api_calls == 3, identical(short$mask_provenance, c("PASS", "REVIEW", "FAIL")),
  all(trial$index$llm_status == "COMPLETED"), nrow(read.csv(file.path(trial$run_dir, "summary.csv"))) == 18,
  all(file.exists(file.path(trial$index$report_path, "mask-provenance.csv"))),
  identical(before, tools::md5sum(source_files)))
local <- read.csv(file.path(trial$index$report_path[1], "mask-provenance.csv"))
report <- paste(readLines(file.path(trial$index$report_path[1], "review.md")), collapse = "\n")
stopifnot(local$recorded_path == "/private/masks/oceanmask_ithaca_global_025.nc", grepl(local$recorded_path, report, fixed = TRUE))
# Five-category summaries remain five categories when regenerated: no retroactive mask verdicts.
legacy <- read.csv(file.path(trial$run_dir, "summary.csv"))
legacy <- legacy[legacy$check_group != "mask_provenance", ]
legacy_short <- grouped_short_summary(legacy)
stopifnot(identical(names(legacy_short), c("data_file_path", legacy_grouped_check_names())),
  !"mask_provenance" %in% names(review_heatmap_table(legacy_short)))
unlink(work, recursive = TRUE)
cat("Mask provenance passed: approved/generic/missing cases, land-only scope, recorded application, cached headers, withheld/redacted evidence, private paths, exact rule guards and a three-file mocked six-category review. Original scans unchanged; no live inference.\n")
