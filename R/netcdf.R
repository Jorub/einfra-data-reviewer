# Filename claims are evidence to verify, not a substitute for file contents.
parse_netcdf_filename <- function(path) {
  name <- basename(path)
  fields <- strsplit(sub("\\.(nc|nc4|cdf)$", "", name, ignore.case = TRUE), "_", fixed = TRUE)[[1]]
  issues <- character()
  if (length(fields) != 8 || any(!nzchar(fields)))
    return(list(basename = name, valid = FALSE, issues = "Expected eight nonempty underscore-separated fields"))
  names(fields) <- c("source","variable","units","spatial_coverage","start","end","spatial_resolution","frequency")
  date_ok <- function(x) grepl("^[0-9]{6}$",x) && substr(x,5,6) %in% sprintf("%02d",1:12) && substr(x,1,4)!="0000"
  if (!date_ok(fields['start'])) issues <- c(issues,"Malformed start date; expected YYYYMM")
  if (!date_ok(fields['end'])) issues <- c(issues,"Malformed end date; expected YYYYMM")
  if (!length(issues) && fields['start']>fields['end']) issues <- c(issues,"Start date is later than end date")
  if (!fields['frequency'] %in% c("hourly","daily","monthly","yearly","annual")) issues <- c(issues,"Unrecognized temporal frequency")
  list(basename = name, valid = !length(issues), fields = as.list(fields), issues = issues,
       note = "Filename fields are claims, not verified metadata. Resolution code 025 means 0.25 degrees; other codes require an agreed mapping.")
}

# Reduce disclosure from free-text history; review the preview before submission.
sanitize_history <- function(text, max_chars = 6000L) {
  text <- paste(as.character(text), collapse = "\n")
  # Redact credential-like assignments and authorization headers before paths.
  text <- gsub("(?i)(authorization[ :]+bearer[ ]+)[^\\s\"']+", "\\1[REDACTED]", text, perl = TRUE)
  text <- gsub("(?i)((?:api[_-]?key|access[_-]?token|password|passwd|secret|token)[ ]*[=:][ ]*)(?:\"[^\"]*\"|'[^']*'|[^\\s;]+)",
               "\\1[REDACTED]", text, perl = TRUE)
  text <- gsub("(?i)\\b(?:sk-|ghp_|github_pat_)[A-Za-z0-9_-]+", "[REDACTED]", text, perl = TRUE)
  text <- gsub("https?://[^\\s\"']+", "[URL REDACTED]", text, perl = TRUE)
  text <- gsub("[^\\s\"']+@[^\\s\"']+", "[IDENTITY REDACTED]", text, perl = TRUE)
  # Absolute, home-relative, relative-with-slash and Windows paths. Keep CDO operators.
  text <- gsub("(?:[A-Za-z]:[\\\\/]|~/|/|\\.\\.?/)[^\\s\"']+", "[PATH REDACTED]", text, perl = TRUE)
  list(text = substr(text, 1L, max_chars), truncated = nchar(text) > max_chars,
       redacted = TRUE,
       note = "Common paths/credentials/URLs redacted automatically; not a guarantee. Inspect preview. History records operations, not proof that processing was correct.")
}

# Read-only NetCDF diagnostics. Caller supplies paths and scientific expectations.
check_netcdf <- function(path, variable = NULL, expected_units = "degC",
                         resolution = 0.25, start_month = "2000-01",
                         end_month = "2019-12", global_grid = TRUE,
                         scan_values = TRUE, use_system_tools = TRUE,
                         include_history = TRUE) {
  if (!requireNamespace("ncdf4", quietly = TRUE)) stop("Run setup.R to install ncdf4.")
  if (!file.exists(path)) stop("NetCDF input does not exist.")
  if (!identical(expected_units, "degC")) stop("This initial checker implements Celsius contracts only.")
  stopifnot(length(resolution) == 1, is.finite(resolution), resolution > 0)
  expected_dates <- seq(as.Date(paste0(start_month, "-01")),
                        as.Date(paste0(end_month, "-01")), by = "month")
  expected_months <- format(expected_dates, "%Y-%m")
  nc <- tryCatch(ncdf4::nc_open(path), error = function(e) stop("Cannot open NetCDF input."))
  on.exit(ncdf4::nc_close(nc))
  getatt <- function(v, a, default = NULL) {
    x <- ncdf4::ncatt_get(nc, v, a)
    if (isTRUE(x$hasatt)) x$value else default
  }
  rows <- list()
  add <- function(check, status, detail) rows[[length(rows) + 1L]] <<- data.frame(
    check = check, status = if (is.logical(status)) if (isTRUE(status)) "PASS" else "FAIL" else status,
    detail = detail, stringsAsFactors = FALSE)
  find_dim <- function(kind) {
    hit <- names(nc$dim)[vapply(nc$dim, function(d) {
      n <- tolower(d$name); u <- tolower(d$units)
      if (kind == "lon") n %in% c("lon", "longitude") || u %in% c("degrees_east", "degree_east")
      else if (kind == "lat") n %in% c("lat", "latitude") || u %in% c("degrees_north", "degree_north")
      else n %in% c("time", "valid_time") || grepl(" since ", u, fixed = TRUE)
    }, logical(1))]
    if (length(hit) == 1) hit else NA_character_
  }
  dims <- c(lon = find_dim("lon"), lat = find_dim("lat"), time = find_dim("time"))
  add("coordinate_dimensions", !anyNA(dims), "Requires uniquely identifiable longitude, latitude and time dimensions")
  filename <- parse_netcdf_filename(path)
  add("filename_format", filename$valid, if(filename$valid) "Eight fields and valid YYYYMM dates" else paste(filename$issues,collapse = "; "))
  evidence <- list(filename = filename, contract = list(variable = variable, units = expected_units,
    resolution_degrees = resolution, first_month = start_month, last_month = end_month,
    records = length(expected_months), global_grid = global_grid),
    limits = c("Land-mask correctness requires a reference mask; not checked.",
      "Monthly-mean semantics and product provenance cannot be established from values alone.",
      "No fixed plausible-temperature limits were assumed. Celsius-like values do not prove correct units."))
  finish <- function() {
    result <- do.call(rbind, rows)
    attr(result, "review_evidence") <- evidence
    result
  }
  if (include_history) {
    history <- getatt(0, "history")
    evidence$processing_history <- if (is.null(history))
      list(source = "NetCDF global history attribute (also shown by ncdump -h)", available = FALSE) else
      c(list(source = "NetCDF global history attribute (also shown by ncdump -h)", available = TRUE),
        sanitize_history(history))
  }
  if (anyNA(dims)) return(finish())
  candidates <- names(nc$var)[vapply(nc$var, function(v)
    all(dims %in% vapply(v$dim, function(d) d$name, character(1))), logical(1))]
  if (is.null(variable) && length(candidates) == 1) variable <- candidates[1]
  found <- length(variable) == 1 && variable %in% candidates
  add("data_variable", found, paste("Variables with longitude, latitude and time:", paste(candidates, collapse = ", ")))
  if (!found) return(finish())
  v <- nc$var[[variable]]
  dn <- vapply(v$dim, function(d) d$name, character(1))
  dl <- vapply(v$dim, function(d) d$len, numeric(1))
  extra_ok <- all(dl[!dn %in% dims] == 1)
  add("extra_dimensions", extra_ok, "Additional dimensions must be singleton; no implicit level selection")
  units <- getatt(variable, "units", "")
  normalized <- gsub("[ _°-]", "", tolower(as.character(units)))
  add("temperature_units", normalized %in% c("degc", "degreecelsius", "degreescelsius", "celsius", "degreec", "degreesc"),
      paste("Expected Celsius; stored units:", substr(units, 1, 120)))
  if (isTRUE(filename$valid)) {
    f <- filename$fields
    same_units <- function(x) {
      z <- gsub("[ _°-]", "", tolower(x))
      if(z %in% c("degc","degreecelsius","degreescelsius","celsius","degreec","degreesc")) "degc" else z
    }
    add("filename_units", identical(same_units(f$units),same_units(as.character(units))),
        paste("Filename units:",f$units,"; stored units:",units))
    add("filename_expected_period", identical(paste0(substr(f$start,1,4),"-",substr(f$start,5,6)),start_month) &&
        identical(paste0(substr(f$end,1,4),"-",substr(f$end,5,6)),end_month),
        "Filename dates compared with the caller's explicit monthly contract")
    add("filename_frequency", if(f$frequency=="monthly") "PASS" else "NOT_CHECKED",
        "This pilot validates monthly data only; other frequencies need their own checker")
    if(f$spatial_resolution=="025") add("filename_resolution",abs(resolution-.25)<1e-8,
      "Filename 025 compared with the caller's explicit resolution")
    else add("filename_resolution","NOT_CHECKED","Resolution code needs an agreed mapping")
    add("filename_variable", identical(f$variable,variable),
      paste("Filename variable:",f$variable,"; selected variable:",variable,"; aliases require explicit review"))
  }
  evidence$observed <- list(variable = variable, units = substr(units, 1, 120),
    dimensions = as.list(setNames(dl, dn)),
    scale_factor = getatt(variable, "scale_factor", 1),
    add_offset = getatt(variable, "add_offset", 0),
    fill_value = getatt(variable, "_FillValue"), missing_value = getatt(variable, "missing_value"),
    cell_methods = substr(getatt(variable, "cell_methods", "not supplied"), 1, 200))
  for (axis in c("lon", "lat")) {
    d <- nc$dim[[dims[[axis]]]]; x <- d$vals
    finite <- length(x) > 1 && all(is.finite(x))
    monotone <- finite && (all(diff(x) > 0) || all(diff(x) < 0))
    spacing <- monotone && all(abs(abs(diff(x)) - resolution) < max(1e-6, resolution * 1e-5))
    add(paste0(axis, "_coordinates"), monotone, "Coordinates must be finite, unique and strictly monotonic")
    add(paste0(axis, "_resolution"), spacing, paste("Expected spacing:", resolution, "degrees"))
    degree_units <- tolower(d$units) %in% if (axis == "lon") c("degrees_east", "degree_east") else c("degrees_north", "degree_north")
    add(paste0(axis, "_units"), degree_units, paste("Stored coordinate units:", substr(d$units, 1, 100)))
    if (finite) {
      evidence$observed[[axis]] <- list(min = min(x), max = max(x), count = length(x),
        direction = if (all(diff(x) > 0)) "increasing" else "decreasing",
        spacing_min = min(abs(diff(x))), spacing_max = max(abs(diff(x))))
      limits_ok <- if (axis == "lat") min(x) >= -90 && max(x) <= 90 else
        ((min(x) >= -180 && max(x) <= 180) || (min(x) >= 0 && max(x) <= 360))
      add(paste0(axis, "_geographic_range"), limits_ok, "Coordinates within conventional geographic limits")
      if (global_grid) {
        global <- if (axis == "lon") abs((max(x)-min(x)+resolution)-360) < resolution/10 else
          abs(min(x)+90) <= resolution && abs(max(x)-90) <= resolution
        add(paste0(axis, "_global_extent"), global, "Checks grid extent only, not validity of land/ocean mask")
      }
    }
  }
  td <- nc$dim[[dims[["time"]]]]; t <- td$vals
  calendar <- tolower(getatt(td$name, "calendar", "standard"))
  supported <- calendar %in% c("standard", "gregorian", "proleptic_gregorian")
  pattern <- "^(seconds?|minutes?|hours?|days?) since (.+)$"
  match <- regexec(pattern, td$units, ignore.case = TRUE); parts <- regmatches(td$units, match)[[1]]
  dates <- NULL
  if (supported && length(parts) == 3 && all(is.finite(t))) {
    origin_text <- sub("[ ]*(UTC|Z)$", "", parts[3], ignore.case = TRUE)
    origin_text <- sub("T", " ", origin_text, fixed = TRUE)
    # Explicitly reject timezone offsets rather than silently decoding them wrong.
    timezone_ok <- !grepl("[+-][0-9]{2}:?[0-9]{2}$", origin_text)
    origin <- tryCatch(as.POSIXct(origin_text, tz = "UTC"), error = function(e) NA)
    if (timezone_ok && !is.na(origin)) {
      multiplier <- switch(substr(tolower(parts[2]), 1, 1), s = 1, m = 60, h = 3600, d = 86400)
      dates <- as.Date(origin + t * multiplier, tz = "UTC")
      # Standard mixed calendars before the Gregorian reform require a CF decoder.
      if (calendar != "proleptic_gregorian" && (any(dates < as.Date("1582-10-15")) || as.Date(origin) < as.Date("1582-10-15"))) dates <- NULL
    }
  }
  evidence$observed$time <- list(units = td$units, calendar = calendar, count = length(t))
  add("time_record_count", length(t) == length(expected_months), paste("Expected", length(expected_months), "records; observed", length(t)))
  add("time_numeric_order", all(is.finite(t)) && all(diff(t) > 0), "Time coordinates must be finite, unique and increasing")
  if (is.null(dates)) {
    add("monthly_time_axis", "NOT_CHECKED", "Unsupported calendar/time units/origin; calendar-aware decoding required")
  } else {
    months <- format(dates, "%Y-%m")
    missing <- setdiff(expected_months, months); unexpected <- setdiff(months, expected_months)
    duplicates <- sum(duplicated(months))
    add("monthly_time_axis", identical(months, expected_months),
      sprintf("%d missing months; %d unexpected months; %d duplicate monthly records",length(missing),length(unexpected),duplicates))
    evidence$observed$time$first <- as.character(dates[1])
    evidence$observed$time$last <- as.character(tail(dates,1))
    evidence$observed$time$missing_months <- head(missing,12)
    evidence$observed$time$unexpected_months <- head(unexpected,12)
    if (isTRUE(filename$valid) && filename$fields$frequency=="monthly") {
      actual_start <- format(min(dates),"%Y%m"); actual_end <- format(max(dates),"%Y%m")
      add("filename_actual_period", identical(filename$fields$start,actual_start) && identical(filename$fields$end,actual_end),
          paste("Actual monthly endpoints:",actual_start,"to",actual_end))
    }
    years <- sort(unique(substr(months,1,4)))
    incomplete <- lapply(years,function(y) {
      missing <- setdiff(paste0(y,"-",sprintf("%02d",1:12)),months)
      if(length(missing)) data.frame(year = y,missing_months = paste(missing,collapse = ", ")) else NULL
    })
    incomplete <- do.call(rbind,incomplete)
    add("complete_years", if(is.null(incomplete)) "PASS" else "WARN",
        if(is.null(incomplete)) "All represented years contain all 12 months" else
          paste(nrow(incomplete),"incomplete years including boundary years; coverage limitation requires human review"))
    evidence$observed$time$incomplete_years <- if(is.null(incomplete)) list() else head(incomplete,12)
    evidence$observed$time$incomplete_year_details_truncated <- !is.null(incomplete) && nrow(incomplete)>12
  }
  add("land_mask", "NOT_CHECKED", "No independent reference land mask supplied")
  add("monthly_mean_semantics", "NOT_CHECKED", "Monthly timestamps do not establish that values are monthly means")
  if (scan_values && extra_ok) {
    ti <- match(dims[["time"]], dn); nt <- dl[ti]
    stats <- vector("list", nt)
    message("Scanning ",nt," time slices read-only; fill values and scale/offset handled by ncdf4.")
    for (i in seq_len(nt)) {
      start <- rep(1, length(dl)); count <- dl; start[ti] <- i; count[ti] <- 1
      values <- as.vector(ncdf4::ncvar_get(nc, variable, start = start, count = count))
      good <- values[is.finite(values)]
      q <- if(length(good)) as.numeric(quantile(good,c(0,.01,.5,.99,1),names = FALSE)) else rep(NA_real_,5)
      stats[[i]] <- data.frame(index = i, missing = sum(is.na(values)), nonfinite = sum(!is.finite(values)&!is.na(values)),
        finite = length(good), total = length(values), min = q[1],p01 = q[2],median = q[3],p99 = q[4],max = q[5])
    }
    stats <- do.call(rbind,stats)
    add("nonfinite_values", sum(stats$nonfinite)==0, paste(sum(stats$nonfinite),"nonmissing nonfinite values"))
    add("nonempty_time_slices", all(stats$finite>0), paste(sum(stats$finite==0),"time slices without finite values"))
    evidence$value_scan <- list(scope = "All time slices; unweighted spatial quantiles, not land-area means",
      slices = nt, finite_min = min(stats$finite), finite_max = max(stats$finite),
      missing_fraction_min = min(stats$missing/stats$total),missing_fraction_max = max(stats$missing/stats$total),
      representative_slices = stats[unique(round(seq(1,nt,length.out = min(8,nt)))),])
    if (any(stats$finite>0)) {
      evidence$value_scan$global_min <- min(stats$min,na.rm = TRUE)
      evidence$value_scan$global_max <- max(stats$max,na.rm = TRUE)
    }
    evidence$limits <- c(evidence$limits,"Raw value/scale inconsistencies are hypotheses for review; no reference-product comparison was performed.")
  } else add("value_scan", "NOT_CHECKED", "Value scan disabled or extra dimensions require explicit selection")
  tool_results <- list()
  if (use_system_tools) {
    run <- function(executable,args) {
      exe <- Sys.which(executable)
      if (!nzchar(exe)) return(list(status = "NOT_CHECKED",output = character()))
      err <- tempfile(); on.exit(unlink(err))
      out <- suppressWarnings(tryCatch(system2(exe,args = args,stdout = TRUE,stderr = err),error = function(e) structure(character(),status = 1L)))
      status <- attr(out,"status"); if(is.null(status)) status <- 0L
      list(status = if(status==0) "PASS" else "NOT_CHECKED",output = out)
    }
    format_result <- run("ncdump",c("-k",shQuote(path)))
    add("ncdump_readability",format_result$status,"Independent format query; unavailable tools or failures are not a data verdict")
    # Return raw tool output only as a local attribute, never in API evidence.
    tool_results$ncdump <- format_result
    header_result <- run("ncdump",c("-h",shQuote(path)))
    add("ncdump_header",header_result$status,"Full header retained locally; only redacted global history is submitted")
    tool_results$ncdump_header <- header_result
    cdo_result <- run("cdo",c("-s","ntime",shQuote(path)))
    count <- suppressWarnings(as.numeric(trimws(cdo_result$output)))
    if(identical(cdo_result$status,"PASS") && length(count)==1 && is.finite(count))
      add("cdo_time_count", count==length(t), paste("CDO:",count,"; R:",length(t)))
    else add("cdo_time_count","NOT_CHECKED","CDO unavailable or time count query failed")
    tool_results$cdo <- cdo_result
  } else add("system_tools","NOT_CHECKED","External tool queries disabled")
  result <- finish()
  if(exists("stats",inherits = FALSE)) attr(result,"local_slice_statistics") <- stats
  attr(result,"local_tool_results") <- tool_results
  result
}
