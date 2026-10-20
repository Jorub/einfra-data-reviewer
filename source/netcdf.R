source("source/netcdf_families.R")
source("source/netcdf_time.R")

# Filename claims are the expected contract. Do not silently repair malformed names.
parse_netcdf_filename <- function(path) {
  name <- basename(path)
  fields <- strsplit(sub("\\.(nc|nc4|cdf)$", "", name, ignore.case = TRUE), "_", fixed = TRUE)[[1]]
  if (length(fields) != 8 || any(!nzchar(fields)))
    return(list(basename = name, valid = FALSE, issues = "Expected eight nonempty underscore-separated fields"))
  names(fields) <- c("source", "variable", "units", "spatial_coverage", "start", "end", "spatial_resolution", "frequency")
  issues <- character()
  date_ok <- function(x) grepl("^[0-9]{6}$", x) && substr(x, 5, 6) %in% sprintf("%02d", 1:12) && substr(x, 1, 4) != "0000"
  if (!date_ok(fields['start'])) issues <- c(issues, "Malformed start date; expected YYYYMM")
  if (!date_ok(fields['end'])) issues <- c(issues, "Malformed end date; expected YYYYMM")
  if (!length(issues) && fields['start'] > fields['end']) issues <- c(issues, "Start date is later than end date")
  if (!fields['frequency'] %in% c("hourly", "daily", "monthly", "yearly", "annual")) issues <- c(issues, "Unrecognized temporal frequency")
  list(basename = name, valid = !length(issues), fields = as.list(fields), issues = issues)
}
canonical_units <- function(x) {
  z <- tolower(gsub("[ _°]", "", x))
  if (z %in% c("degc", "degreecelsius", "degreescelsius", "celsius", "degreec", "degreesc")) "degc" else
    if (z %in% c("k", "kelvin", "kelvins")) "k" else z
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
  # Protect only complete numeric CDO argument tokens, not arbitrary slash text.
  # Example: seltimestep,1/20 is a range; remapnn,/private/grid is a path.
  number <- "[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
  argument <- paste0(number, "(?:/", number, "){0,2}")
  operator <- paste0("(?<![[:alnum:]_./\\\\-])-?[A-Za-z][A-Za-z0-9_-]*,", argument,
    "(?:,", argument, ")*(?=$|[[:space:]\"';)])")
  marker <- "__CDO_NUMERIC_RANGE_SLASH__"
  while (grepl(marker, text, fixed = TRUE)) marker <- paste0(marker, "X")
  locations <- gregexpr(operator, text, perl = TRUE)
  regmatches(text, locations) <- lapply(regmatches(text, locations), function(tokens)
    gsub("/", marker, tokens, fixed = TRUE))
  # Absolute, home-relative, relative-with-slash and Windows paths. Keep CDO operators.
  text <- gsub("(?:[A-Za-z]:[\\\\/]|~/|/|\\.\\.?/)[^\\s\"']+", "[PATH REDACTED]", text, perl = TRUE)
  text <- gsub(marker, "/", text, fixed = TRUE)
  list(text = substr(text, 1L, max_chars), truncated = nchar(text) > max_chars,
       sanitizer_version = "cdo-numeric-ranges-v2",
       redacted = TRUE,
       note = "Common paths/credentials/URLs redacted automatically; not a guarantee. Inspect preview. History records operations, not proof that processing was correct.")
}

# All scientific expectations come from the filename; family and notes add context.
check_netcdf <- function(path, variable = NULL, family = NULL, provenance_notes = "",
                         scan_values = TRUE, use_system_tools = TRUE, include_history = TRUE,
                         land_missing_range = c(0.50, 0.85)) {
  if (!requireNamespace("ncdf4", quietly = TRUE)) stop("Run setup.R to install ncdf4.")
  if (!file.exists(path)) stop("NetCDF input does not exist.")
  if (!is.character(provenance_notes) || length(provenance_notes) != 1 || is.na(provenance_notes)) stop("provenance_notes must be text.")
  if (length(land_missing_range) != 2 || any(!is.finite(land_missing_range)) ||
      land_missing_range[1] < 0 || land_missing_range[2] > 1 || land_missing_range[1] > land_missing_range[2])
    stop("land_missing_range must be two ordered fractions in [0, 1].")
  filename <- parse_netcdf_filename(path)
  rows <- list()
  add <- function(check, status, detail) rows[[length(rows) + 1L]] <<- data.frame(
    check = check, status = if (is.logical(status)) if (isTRUE(status)) "PASS" else "FAIL" else status,
    detail = detail, stringsAsFactors = FALSE)
  evidence <- list(checker_version = "filename-family-v5-team-diagnostics", filename = filename, policy = list(
    expectations = "Parsed from filename, checked against contents; no cross-frequency product comparisons",
    provenance = "Missing/empty history attribute is a mandatory provenance FAIL, even with other metadata or notes. Unclear source/temporal meaning also fails; native-frequency sources need not have a local aggregation step",
    project_stage_meaning = "raw is already preprocessed/harmonised to common units and 0.25-degree grid, not untouched downloads; processed usually contains spatial/time subsets",
    temporal_values = "Values must have the quantity, units and temporal interpretation represented by the filename frequency; metadata/history or source documentation must explain that interpretation",
    project_grid_degrees = 0.25,
    masking = "Masking may retain actual environmental values under variable name mask. Restore intended variable name/units; do not infer binary contents from the name alone",
    temporal = "Monthly/daily/hourly boundary years may end as declared; annual products require complete years"))
  finish <- function() {
    x <- do.call(rbind, rows)
    essential <- c("coordinate_dimensions", "data_variable", "additional_data_variables", "extra_dimensions", "resolution_code", "time_coverage", "value_scan")
    evidence$blocking_gaps <- x$check[x$status == "NOT_CHECKED" & x$check %in% essential]
    attr(x, "review_evidence") <- evidence
    x
  }
  add("filename_format", filename$valid, if (filename$valid) "Eight fields and valid YYYYMM endpoints" else paste(filename$issues, collapse = "; "))
  if (!filename$valid) return(finish())
  f <- filename$fields
  profile <- netcdf_family(path, f$variable, family)
  evidence$family <- profile
  pieces <- strsplit(gsub("\\\\", "/", dirname(path)), "/", fixed = TRUE)[[1]]
  evidence$stage <- if ("processed" %in% pieces) "processed" else if ("raw" %in% pieces) "raw" else "unspecified"
  # Project-wide invariant, independent of filename claims.
  resolution <- 0.25
  resolution_ok <- TRUE
  evidence$contract <- c(f, list(resolution_degrees = resolution))
  add("resolution_code", identical(f$spatial_resolution, "025"),
    "All project grids are 0.25 degrees; filename must use the established 025 code")
  n <- tryCatch(ncdf4::nc_open(path), error = function(e) stop("Cannot open NetCDF input."))
  on.exit(ncdf4::nc_close(n))
  att <- function(v, a, default = NULL) {
    x <- ncdf4::ncatt_get(n, v, a)
    if (isTRUE(x$hasatt)) x$value else default
  }
  stored_history <- att(0, "history")
  history_present <- !is.null(stored_history) && any(!is.na(stored_history) & nzchar(trimws(as.character(stored_history))))
  add("history_provenance", history_present,
    if (history_present) "Nonempty NetCDF history attribute present; adequacy still requires review" else
      "PROVENANCE: NetCDF history attribute is missing or empty; mandatory provenance requirement failed")
  history <- if (include_history && history_present) stored_history else NULL
  provenance <- list()
  for (a in c("source", "references", "institution", "title", "comment")) {
    x <- att(0, a)
    if (!is.null(x)) provenance[[a]] <- sanitize_history(x, 1000L)$text
  }
  evidence$source_metadata <- provenance
  evidence$provenance_notes <- sanitize_history(provenance_notes, 2000L)$text
  evidence$processing_history <- if (is.null(history)) list(available = FALSE, present_in_file = history_present, included_in_payload = FALSE) else
    c(list(available = TRUE), sanitize_history(history))
  find_dim <- function(kind) {
    hit <- names(n$dim)[vapply(n$dim, function(d) {
      name <- tolower(d$name); units <- tolower(d$units)
      switch(kind,
        lon = name %in% c("lon", "longitude") || units %in% c("degrees_east", "degree_east"),
        lat = name %in% c("lat", "latitude") || units %in% c("degrees_north", "degree_north"),
        time = name %in% c("time", "valid_time") || grepl(" since ", units, fixed = TRUE))
    }, logical(1))]
    if (length(hit) == 1) hit else NA_character_
  }
  dims <- c(lon = find_dim("lon"), lat = find_dim("lat"), time = find_dim("time"))
  add("coordinate_dimensions", if (!anyNA(dims)) "PASS" else "NOT_CHECKED",
      "Requires regular one-dimensional longitude/latitude/time dimensions; unsupported grids need review")
  if (anyNA(dims)) return(finish())
  candidates <- names(n$var)[vapply(n$var, function(v) all(dims %in% vapply(v$dim, function(d) d$name, character(1))), logical(1))]
  if (is.null(variable)) {
    if (f$variable %in% candidates) variable <- f$variable else if (length(candidates) == 1) variable <- candidates[1]
  }
  found <- length(variable) == 1 && variable %in% candidates
  add("data_variable", if (found) "PASS" else "NOT_CHECKED", paste("Data-variable candidates:", paste(candidates, collapse = ", ")))
  if (!found) return(finish())
  remaining <- setdiff(candidates, variable)
  if (length(remaining)) add("additional_data_variables", "NOT_CHECKED",
    paste("Other data variables not scanned in this filename-variable review:", paste(remaining, collapse = ", ")))
  add("filename_variable", if (identical(variable, f$variable)) "PASS" else "WARN",
    if (identical(variable, "mask") && f$variable != "mask")
      paste("NAMING/METADATA: masking left variable named mask instead of", f$variable,
        "; restore intended name and verify units; name alone does not imply binary values") else
      paste("Filename claims", f$variable, "; selected variable", variable, "; differing aliases require confirmation"))
  v <- n$var[[variable]]
  dn <- vapply(v$dim, function(d) d$name, character(1)); dl <- vapply(v$dim, function(d) d$len, numeric(1))
  extra_ok <- all(dl[!dn %in% dims] == 1)
  add("extra_dimensions", if (extra_ok) "PASS" else "NOT_CHECKED", "Nonsingleton extra dimensions require explicit layer/member handling")
  units <- as.character(att(variable, "units", ""))
  add("filename_units", identical(canonical_units(f$units), canonical_units(units)), paste("Filename:", f$units, "; stored:", units))
  cell_methods <- as.character(att(variable, "cell_methods", ""))
  evidence$observed <- list(variable = variable, units = units, dimensions = as.list(setNames(dl, dn)),
    long_name = sanitize_history(att(variable, "long_name", ""), 500L)$text,
    standard_name = sanitize_history(att(variable, "standard_name", ""), 500L)$text,
    scale_factor = att(variable, "scale_factor", 1), add_offset = att(variable, "add_offset", 0),
    fill_value = att(variable, "_FillValue"), missing_value = att(variable, "missing_value"),
    cell_methods = sanitize_history(cell_methods, 1000L)$text)
  has_provenance <- nzchar(provenance_notes) || (length(history) && any(nzchar(history))) ||
    any(vapply(provenance, function(x) nzchar(x), logical(1)))
  add("provenance_evidence", if (has_provenance) "NOT_CHECKED" else "FAIL",
    if (has_provenance) "Evidence supplied; LLM must assess source traceability and aggregation semantics, not just presence" else
      "No source/processing provenance supplied; filename alone cannot establish traceability")
  if (profile$family == "temperature" && tolower(f$variable) %in% c("tmin", "tmax", "tasmin", "tasmax") && f$frequency %in% c("monthly", "yearly", "annual")) {
    aggregation_text <- paste(cell_methods, history, provenance_notes, unlist(provenance), collapse = " ")
    evidence$family$requirements <- c(profile$requirements,
      "Missing or ambiguous Tmin/Tmax aggregation is a provenance FAIL even if time coverage is complete. Identify mean daily extrema versus period extrema.")
    if (!nzchar(trimws(aggregation_text))) add("extrema_aggregation_provenance", "FAIL",
      "Aggregation undocumented: cannot distinguish mean daily extrema from period extrema")
  }
  for (axis in c("lon", "lat")) {
    d <- n$dim[[dims[[axis]]]]; x <- d$vals
    finite <- length(x) > 1 && all(is.finite(x))
    monotone <- finite && (all(diff(x) > 0) || all(diff(x) < 0))
    add(paste0(axis, "_coordinates"), monotone, "Finite, unique, strictly monotonic coordinates")
    spacing <- if (resolution_ok) monotone && all(abs(abs(diff(x)) - resolution) < max(1e-6, resolution * 1e-5)) else NA
    add(paste0(axis, "_resolution"), if (!resolution_ok) "NOT_CHECKED" else if (spacing) "PASS" else "FAIL", "Spacing compared with project-wide 0.25-degree requirement and filename 025 claim")
    degree_units <- tolower(d$units) %in% if (axis == "lon") c("degrees_east", "degree_east") else c("degrees_north", "degree_north")
    add(paste0(axis, "_units"), degree_units, paste("Coordinate units:", d$units))
    if (finite) {
      evidence$observed[[axis]] <- list(first = x[1], last = tail(x, 1), min = min(x), max = max(x), count = length(x), units = d$units,
        direction = if (all(diff(x) > 0)) "increasing" else "decreasing",
        spacing_min = min(abs(diff(x))), spacing_max = max(abs(diff(x))))
      range_ok <- if (axis == "lat") min(x) >= -90 && max(x) <= 90 else
        (min(x) >= -180 && max(x) <= 180) || (min(x) >= 0 && max(x) <= 360)
      add(paste0(axis, "_geographic_range"), range_ok, "Conventional geographic coordinate limits")
      if (axis == "lat") {
        evidence$observed$latitude_coverage_policy <- "Latitude extent is descriptive: limited coverage such as 60S–60N and inclusion/exclusion of Antarctica are both allowed; do not flag solely for these differences."
      }
      if (axis == "lon" && f$spatial_coverage %in% c("global", "land") && resolution_ok) {
        full <- if (axis == "lon") abs(max(x) - min(x) + resolution - 360) < resolution / 10 else
          abs(min(x) + 90) <= resolution && abs(max(x) - 90) <= resolution
        add(paste0(axis, "_global_extent"), full, "land/global longitude grid compared with a full 360-degree span; latitude domain is allowed to vary")
      }
    }
  }
  td <- n$dim[[dims[["time"]]]]; t <- td$vals
  calendar <- tolower(att(td$name, "calendar", "standard"))
  bounds <- NULL; bounds_name <- att(td$name, "bounds")
  if (!is.null(bounds_name) && bounds_name %in% names(n$var)) {
    bv <- n$var[[bounds_name]]; sizes <- vapply(bv$dim, function(d) d$len, numeric(1))
    bn <- vapply(bv$dim, function(d) d$name, character(1))
    if (length(sizes) == 2 && dims[["time"]] %in% bn && sizes[which(bn != dims[["time"]])][1] == 2) {
      bounds <- ncdf4::ncvar_get(n, bounds_name, collapse_degen = FALSE)
      if (match(dims[["time"]], bn) == 1) bounds <- base::t(bounds)
    } else add("time_bounds", "NOT_CHECKED", "Time bounds have unsupported dimensions")
  }
  time_result <- netcdf_time_checks(t, td$units, calendar, filename, bounds)
  rows[[length(rows) + 1L]] <- time_result$checks
  evidence$observed$time <- time_result$evidence
  add("land_mask", "NOT_CHECKED", "No independent land mask supplied; do not infer mask correctness from missing fraction")
  if (scan_values && extra_ok) {
    ti <- match(dims[["time"]], dn); nt <- dl[ti]; stats <- vector("list", nt)
    message("Scanning ", nt, " time slices read-only: ", basename(path))
    for (i in seq_len(nt)) {
      start <- rep(1, length(dl)); count <- dl; start[ti] <- i; count[ti] <- 1
      values <- as.vector(ncdf4::ncvar_get(n, variable, start = start, count = count))
      good <- values[is.finite(values)]
      q <- if (length(good)) as.numeric(quantile(good, c(0, .01, .5, .99, 1), names = FALSE)) else rep(NA_real_, 5)
      stats[[i]] <- data.frame(index = i, missing = sum(is.na(values)), nonfinite = sum(!is.finite(values) & !is.na(values)),
        finite = length(good), total = length(values), mean = if (length(good)) mean(good) else NA_real_, min = q[1], p01 = q[2], median = q[3], p99 = q[4], max = q[5])
    }
    stats <- do.call(rbind, stats)
    stats$timestamp <- if (length(time_result$layer_timestamps) == nrow(stats)) time_result$layer_timestamps else NA_character_
    add("nonfinite_values", sum(stats$nonfinite) == 0, paste(sum(stats$nonfinite), "nonmissing nonfinite values"))
    add("nonempty_time_slices", all(stats$finite > 0), paste(sum(stats$finite == 0), "time slices without finite values"))
    evidence$value_scan <- list(scope = "All time slices; unweighted spatial quantiles, not area means", slices = nt,
      finite_min = min(stats$finite), finite_max = max(stats$finite),
      missing_fraction_min = min(stats$missing / stats$total), missing_fraction_max = max(stats$missing / stats$total),
      representative_slices = stats[unique(round(seq(1, nt, length.out = min(8, nt)))), ])
    fraction <- stats$missing / stats$total
    if (f$spatial_coverage == "global")
      add("global_data_coverage", all(stats$finite == stats$total),
        paste("Global means land plus ocean within represented domain: missing fraction ranges", signif(min(fraction), 4), "to", signif(max(fraction), 4)))
    if (f$spatial_coverage == "land") {
      within <- all(fraction >= land_missing_range[1] & fraction <= land_missing_range[2])
      add("land_data_coverage", if (within) "PASS" else "WARN",
        paste("Approximate grid-cell missing-fraction screen:", paste(land_missing_range, collapse = " to "),
          "; observed", signif(min(fraction), 4), "to", signif(max(fraction), 4), "; not an independent mask validation"))
      evidence$policy$land_missing_fraction_screen <- as.list(land_missing_range)
    }
    if (any(stats$finite > 0)) {
      valid_means <- stats$finite > 0
      evidence$value_scan$global_mean <- weighted.mean(stats$mean[valid_means], stats$finite[valid_means])
      evidence$value_scan$mean_definition <- "Arithmetic mean of all finite cell-time values, no spatial-area or duration weighting"
      evidence$value_scan$global_min <- min(stats$min, na.rm = TRUE)
      evidence$value_scan$global_max <- max(stats$max, na.rm = TRUE)
    }
  } else add("value_scan", "NOT_CHECKED", "Values not scanned; extra dimensions or disabled scan require follow-up")
  tool_results <- list()
  if (use_system_tools) {
    run_tool <- function(executable, args) {
      exe <- Sys.which(executable)
      if (!nzchar(exe)) return(list(status = "NOT_CHECKED", output = character()))
      err <- tempfile(); on.exit(unlink(err))
      out <- suppressWarnings(tryCatch(system2(exe, args = args, stdout = TRUE, stderr = err, timeout = 120),
        error = function(e) structure(character(), status = 1L)))
      status <- attr(out, "status"); if (is.null(status)) status <- 0L
      list(status = if (status == 0) "PASS" else "NOT_CHECKED", output = out)
    }
    tool_results$ncdump <- run_tool("ncdump", c("-k", shQuote(path)))
    tool_results$ncdump_header <- run_tool("ncdump", c("-h", shQuote(path)))
    add("ncdump_readability", tool_results$ncdump$status, "Independent format query; raw output stays local")
    add("ncdump_header", tool_results$ncdump_header$status, "Full header stays local; selected metadata/history enter preview")
    tool_results$cdo <- run_tool("cdo", c("-s", "ntime", shQuote(path)))
    ct <- suppressWarnings(as.numeric(trimws(tool_results$cdo$output)))
    if (tool_results$cdo$status == "PASS" && length(ct) == 1 && is.finite(ct))
      add("cdo_time_count", ct == length(t), paste("CDO:", ct, "; R:", length(t)))
    else add("cdo_time_count", "NOT_CHECKED", "CDO unavailable or count query failed")
  } else add("system_tools", "NOT_CHECKED", "External queries disabled")
  result <- finish()
  if (exists("stats", inherits = FALSE)) attr(result, "local_slice_statistics") <- stats
  attr(result, "local_period_details") <- time_result$period_details
  attr(result, "local_tool_results") <- tool_results
  result
}
