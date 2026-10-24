# Mask identity is a provenance check, independent of numerical mask validation.
approved_mask_basenames <- function() "oceanmask_ithaca_global_025.nc"

mask_history_references <- function(history, origin) {
  empty <- data.frame(mask_filename = character(), recorded_path = character(), path_detail = character(),
    recorded_application = logical(), evidence_source = character(), stringsAsFactors = FALSE)
  if (is.null(history) || !length(history)) return(empty)
  lines <- unlist(strsplit(paste(history, collapse = "\n"), "\n", fixed = TRUE), use.names = FALSE)
  pattern <- "\"[^\"\r\n]+[.](?:nc4|nc|cdf)\"|'[^'\r\n]+[.](?:nc4|nc|cdf)'|[^[:space:]\"',;<>]+[.](?:nc4|nc|cdf)"
  rows <- list()
  for (line in lines) {
    files <- regmatches(line, gregexpr(pattern, line, perl = TRUE, ignore.case = TRUE))[[1]]
    if (!length(files)) next
    files <- sub("^[\"']", "", sub("[\"']$", "", files))
    files <- sub("^[A-Za-z_][A-Za-z0-9_]*=", "", files)
    names <- basename(gsub("\\\\", "/", files))
    candidates <- which(grepl("mask|(^|[_-])lsm([_.-]|$)", names, ignore.case = TRUE))
    if (!length(candidates)) next
    cdo_mask <- grepl("\\bcdo\\b", line) &&
      grepl("(^|[[:space:]])-?(mul|ifthen|ifnotthen|ifthenelse)(?=[[:space:]])", line, perl = TRUE)
    described_use <- grepl("(?i)\\b(masked|masking)\\b.*\\b(using|with)\\b|\\bmask\\b.*\\b(applied|used)\\b|\\bused\\b.*\\bmask\\b", line, perl = TRUE) &&
      !grepl("(?i)\\b(not|never|unused)\\b", line, perl = TRUE)
    for (i in candidates) {
      sensitive <- grepl("(?i)(https?://|api[_-]?key|access[_-]?token|password|passwd|secret[=:]|sk-|ghp_|github_pat_)", files[i], perl = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(mask_filename = if (sensitive) "[SENSITIVE REFERENCE REDACTED]" else names[i],
        recorded_path = if (sensitive) "[SENSITIVE REFERENCE REDACTED]" else files[i],
        path_detail = if (sensitive) "redacted" else if (grepl("[/\\\\]", files[i])) "path_recorded" else "filename_only",
        recorded_application = (cdo_mask && i < length(files)) || described_use,
        evidence_source = origin, stringsAsFactors = FALSE)
    }
  }
  if (length(rows)) unique(do.call(rbind, rows)) else empty
}

# Decode only the global history attribute from a cached ncdump header, never eval().
cached_header_history <- function(checks) {
  header <- attr(checks, "local_tool_results")$ncdump_header
  if (!identical(header$status, "PASS") || !length(header$output)) return(NULL)
  text <- paste(header$output, collapse = "\n")
  pattern <- '(?m)^\\s*:history\\s*=\\s*((?:"(?:[^"\\\\]|\\\\.)*"\\s*,?\\s*)+);'
  match <- regexec(pattern, text, perl = TRUE)
  fields <- regmatches(text, match)[[1]]
  if (length(fields) != 2) return(NULL)
  strings <- regmatches(fields[2], gregexpr('"(?:[^"\\\\]|\\\\.)*"', fields[2], perl = TRUE))[[1]]
  values <- lapply(strings, function(x) tryCatch(jsonlite::fromJSON(x), error = function(e) NULL))
  if (any(vapply(values, is.null, logical(1)))) return(NULL)
  paste(unlist(values, use.names = FALSE), collapse = "\n")
}

mask_history_observation <- function(history, scope, origin, visibility_limited = FALSE, inspected = TRUE) {
  list(scope = scope, inspected = inspected, visibility_limited = visibility_limited,
    history_missing = is.null(history) || !length(history) || !any(nzchar(trimws(history))),
    evidence_source = origin, references = mask_history_references(history, origin))
}
mask_observation <- function(checks) {
  evidence <- attr(checks, "review_evidence")
  scope <- evidence$filename$fields$spatial_coverage
  if (is.null(scope)) scope <- evidence$contract$spatial_coverage
  if (is.null(scope)) scope <- "unknown"
  history <- evidence$processing_history
  inspected <- any(checks$check == "history_provenance") || !is.null(history)
  if (!inspected) return(mask_history_observation(NULL, scope, "uninspected", inspected = FALSE))
  if (isFALSE(history$included_in_payload) && isTRUE(history$present_in_file))
    return(mask_history_observation(NULL, scope, "history withheld", visibility_limited = TRUE))
  if (any(checks$check == "history_provenance" & checks$status == "FAIL"))
    return(mask_history_observation(NULL, scope, "missing NetCDF history"))
  local <- attr(checks, "local_mask_provenance")
  if (!is.null(local)) return(local)
  raw <- cached_header_history(checks)
  if (!is.null(raw)) return(mask_history_observation(raw, scope, "cached ncdump history"))
  limited <- !isTRUE(history$available) || isTRUE(history$truncated) || (!is.null(history$text) && grepl("[PATH REDACTED]", history$text, fixed = TRUE))
  mask_history_observation(if (isTRUE(history$available)) history$text else NULL, scope,
    "included sanitized history", visibility_limited = limited)
}

assess_mask_provenance <- function(observation) {
  result <- function(status, finding, action) list(status = status, finding = finding, next_action = action)
  if (!isTRUE(observation$inspected)) return(result("NOT_CHECKED", "The scan stopped before mask provenance could be inspected.",
    "Resolve the earlier scan/filename issue before assessing mask provenance."))
  if (is.null(observation$scope) || !length(observation$scope) || is.na(observation$scope) ||
      observation$scope %in% c("", "unknown")) return(result("NOT_CHECKED",
    "Filename land/global scope is unavailable; mask references were inspected but the land-only requirement cannot be assigned.",
    "Confirm the missing coverage label; recorded mask references remain in the local report."))
  if (!identical(observation$scope, "land")) return(result("NOT_CHECKED",
    "The land-mask provenance requirement applies to land-labelled files; this file is outside that scope.",
    "No land-mask provenance assessment is made for this scope."))
  refs <- observation$references
  if (!nrow(refs)) {
    if (isTRUE(observation$visibility_limited)) return(result("NOT_CHECKED",
      "Mask identity cannot be established from withheld, truncated or path-redacted history.",
      "Include complete mask evidence or refresh the header evidence; do not infer missing provenance from redaction."))
    return(result("FAIL", "MASK PROVENANCE: no identifiable mask file is documented in the inspected processing history.",
      "Document the mask file used, including its recorded path and application step; do not change data based on this documentation failure alone."))
  }
  known <- refs$mask_filename %in% approved_mask_basenames()
  applied <- refs$recorded_application
  if (all(known) && any(applied) && !isTRUE(observation$visibility_limited)) return(result("PASS",
    paste("Recorded application of approved mask", paste(unique(refs$mask_filename), collapse = ", "),
      "establishes mask identity; mask contents and numerical application are not independently validated.",
      if (all(refs$path_detail == "filename_only")) "Directory not recorded." else "Recorded paths are in the local report."), "None required."))
  why <- if (any(!known)) "An identified mask is not on the approved mask list." else
    if (!any(applied)) "The approved filename is referenced, but its application is not established." else
      "An approved mask is referenced, but history visibility is incomplete."
  result("REVIEW", paste(why, "Recorded masks:", paste(head(unique(refs$mask_filename), 3), collapse = ", ")),
    "Verify which mask was actually applied and whether it is the intended ITHACA mask. Recorded paths are in the local mask-provenance.csv.")
}

add_mask_provenance <- function(checks) {
  observation <- mask_observation(checks)
  assessment <- assess_mask_provenance(observation)
  evidence <- attr(checks, "review_evidence")
  evidence$mask_provenance <- list(scope = observation$scope, evidence_source = observation$evidence_source,
    inspected = observation$inspected, visibility_limited = observation$visibility_limited,
    required_approved_masks = approved_mask_basenames(), rule_result = assessment$status,
    finding = assessment$finding, next_action = assessment$next_action,
    reference_count = nrow(observation$references),
    references = head(observation$references[c("mask_filename", "recorded_application", "path_detail")], 20))
  attributes_saved <- attributes(checks)
  checks <- checks[checks$check != "mask_provenance", , drop = FALSE]
  checks[nrow(checks) + 1L, ] <- list("mask_provenance",
    if (assessment$status == "REVIEW") "WARN" else assessment$status, assessment$finding)
  for (name in setdiff(names(attributes_saved), c("names", "row.names", "class"))) attr(checks, name) <- attributes_saved[[name]]
  attr(checks, "review_evidence") <- evidence
  attr(checks, "local_mask_provenance") <- observation
  checks
}
write_mask_provenance <- function(checks, report_dir) {
  observation <- attr(checks, "local_mask_provenance")
  if (is.null(observation)) return(invisible(NULL))
  write.csv(observation$references, file.path(report_dir, "mask-provenance.csv"), row.names = FALSE)
  invisible(NULL)
}
mask_local_report <- function(checks) {
  refs <- attr(checks, "local_mask_provenance")$references
  if (is.null(refs) || !nrow(refs)) return(character())
  c("Recorded mask references (local report only):", paste0("- ", unique(refs$recorded_path)),
    if (any(refs$path_detail == "filename_only")) paste("Directory not recorded for:",
      paste(unique(refs$mask_filename[refs$path_detail == "filename_only"]), collapse = ", ")) else character(),
    "Paths are recorded evidence; existence and mask contents were not checked.")
}
