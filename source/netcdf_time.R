# Calendar-aware time checks, based on filename endpoints rather than fixed years.
netcdf_time_checks <- function(values, units, calendar, filename, bounds = NULL) {
  rows <- list()
  add <- function(name, status, detail) rows[[length(rows) + 1L]] <<- data.frame(
    check = name, status = if (is.logical(status)) if (isTRUE(status)) "PASS" else "FAIL" else status,
    detail = detail, stringsAsFactors = FALSE)
  period_details <- data.frame(kind = character(), period = character(), stringsAsFactors = FALSE)
  layer_timestamps <- character()
  evidence <- list(units = units, calendar = calendar, count = length(values))
  ordered <- length(values) > 0 && all(is.finite(values)) && all(diff(values) > 0)
  add("time_numeric_order", ordered, "Finite, unique and increasing native time coordinates")
  finish <- function() list(checks = do.call(rbind, rows), evidence = evidence, period_details = period_details, layer_timestamps = layer_timestamps)
  if (!all(is.finite(values)) || !length(values)) return(finish())
  if (!requireNamespace("CFtime", quietly = TRUE)) {
    add("time_coverage", "NOT_CHECKED", "CFtime unavailable; run setup.R")
    return(finish())
  }
  tryCatch({
    # Use interval midpoints for period labels when valid CF bounds are available.
    points <- values
    if (!is.null(bounds)) {
      valid <- is.matrix(bounds) && nrow(bounds) == 2 && ncol(bounds) == length(values) &&
        all(is.finite(bounds)) && all(bounds[1, ] < bounds[2, ]) &&
        all(values >= bounds[1, ] & values <= bounds[2, ])
      add("time_bounds", valid, "Bounds must be ordered finite intervals containing each timestamp")
      if (valid) points <- colMeans(bounds) else bounds <- NULL
    }
    time <- CFtime::CFtime(units, calendar, points)
    stamps <- CFtime::as_timestamp(time, format = "timestamp")
    layer_timestamps <- stamps
    dates <- substr(stamps, 1, 10)
    evidence$first <- stamps[1]; evidence$last <- tail(stamps, 1)
    evidence$bounds_used <- !is.null(bounds)
    f <- filename$fields
    frequency <- f$frequency
    first <- paste0(substr(f$start, 1, 4), "-", substr(f$start, 5, 6), "-01")
    # Generate calendar-valid days, then retain exactly the named month interval.
    n_years <- as.integer(substr(f$end, 1, 4)) - as.integer(substr(f$start, 1, 4)) + 1
    days <- CFtime::as_timestamp(CFtime::CFtime(paste("days since", first), calendar,
      seq.int(0, n_years * 366 + 31)), format = "date")
    month_code <- gsub("-", "", substr(days, 1, 7), fixed = TRUE)
    days <- days[month_code >= f$start & month_code <= f$end]
    expected <- switch(frequency,
      monthly = unique(substr(days, 1, 7)),
      daily = days,
      hourly = as.vector(t(outer(days, sprintf("%02d", 0:23), paste, sep = "T"))),
      yearly = unique(substr(days, 1, 4)), annual = unique(substr(days, 1, 4)))
    actual <- switch(frequency, monthly = substr(dates, 1, 7), daily = dates,
      hourly = substr(stamps, 1, 13), yearly = substr(dates, 1, 4), annual = substr(dates, 1, 4))
    missing <- setdiff(expected, actual); unexpected <- setdiff(actual, expected)
    duplicates <- unique(actual[duplicated(actual)])
    period_details <- data.frame(kind = c(rep("missing", length(missing)), rep("unexpected", length(unexpected)),
      rep("duplicate", length(duplicates))), period = c(missing, unexpected, duplicates), stringsAsFactors = FALSE)
    duplicated <- sum(duplicated(actual))
    add("time_record_count", length(actual) == length(expected),
      paste("Expected", length(expected), frequency, "records; observed", length(actual)))
    add("time_coverage", identical(unname(actual), unname(expected)),
      sprintf("%d missing periods; %d unexpected periods; %d duplicate periods within filename coverage",
        length(missing), length(unexpected), duplicated))
    evidence$frequency <- frequency
    evidence$missing_periods <- head(missing, 24)
    evidence$unexpected_periods <- head(unexpected, 24)
    evidence$duplicate_periods <- duplicated
    evidence$missing_period_count <- length(missing)
    evidence$period_details_truncated <- length(missing) > 24 || length(unexpected) > 24
    if (frequency %in% c("yearly", "annual")) {
      complete_endpoints <- substr(f$start, 5, 6) == "01" && substr(f$end, 5, 6) == "12"
      add("annual_filename_completeness", complete_endpoints,
        "Annual products must declare full-year endpoints (January through December); partial endpoints require review")
      if (!is.null(bounds)) {
        lo <- CFtime::as_timestamp(CFtime::CFtime(units, calendar, bounds[1, ]), format = "timestamp")
        hi <- CFtime::as_timestamp(CFtime::CFtime(units, calendar, bounds[2, ]), format = "timestamp")
        # CFtime can omit the clock for exact midnight. Normalise that valid
        # representation before comparing full-year interval boundaries.
        lo <- gsub(" ", "T", lo, fixed = TRUE); hi <- gsub(" ", "T", hi, fixed = TRUE)
        date_only <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", lo)
        lo[date_only] <- paste0(lo[date_only], "T00:00:00")
        date_only <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", hi)
        hi[date_only] <- paste0(hi[date_only], "T00:00:00")
        yr <- as.integer(substr(dates, 1, 4))
        full <- substr(lo, 1, 19) == sprintf("%04d-01-01T00:00:00", yr) &
          substr(hi, 1, 19) == sprintf("%04d-01-01T00:00:00", yr + 1)
        add("annual_bounds_completeness", all(full), paste(sum(!full), "annual intervals are not full calendar years"))
      } else add("annual_aggregation_completeness", "NOT_CHECKED",
        "Annual records alone do not prove complete source-year aggregation; inspect processing provenance")
    }
    # Monthly/daily/hourly boundary years are allowed to be partial as declared.
    finish()
  }, error = function(e) {
    add("time_coverage", "NOT_CHECKED", "Calendar/time encoding could not be decoded; requires human review")
    finish()
  })
}
