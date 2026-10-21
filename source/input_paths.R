# Path-only preflight: no NetCDF opens, value reads, credentials or API calls.
missing_input_files <- function(file_specs) {
  if (!is.list(file_specs) || !length(file_specs)) stop("Supply a nonempty list of file specifications.")
  paths <- vapply(file_specs, function(spec) {
    path <- if (is.list(spec)) spec$path else NULL
    if (!is.character(path) || length(path) != 1 || is.na(path) || !nzchar(trimws(path)))
      stop("Every file specification must contain one nonempty path.")
    path.expand(path)
  }, character(1))
  absolute <- grepl("^(/|[A-Za-z]:[/\\\\])", paths)
  paths[!absolute] <- file.path(getwd(), paths[!absolute])
  unique(unname(paths[!file.exists(paths) | dir.exists(paths)]))
}
check_input_files <- function(file_specs, report_dir = NULL) {
  missing <- missing_input_files(file_specs)
  report <- NULL
  if (!is.null(report_dir)) {
    if (!is.character(report_dir) || length(report_dir) != 1 || is.na(report_dir) || !nzchar(report_dir))
      stop("Set a valid report_dir for the missing-file list.")
    if (!dir.exists(report_dir) && !dir.create(report_dir, recursive = TRUE)) stop("Cannot create report_dir.")
    report <- file.path(report_dir, "missing_files.csv")
    write.csv(data.frame(data_file_path = missing), report, row.names = FALSE)
  }
  if (length(missing)) {
    # Print outside stop(): R/RStudio can truncate a long error message.
    writeLines(c("Input files not found:", paste0("- ", missing)))
    message <- paste0("Input preflight failed: ", length(missing), " missing input file(s). ",
      if (!is.null(report)) paste0("Complete list saved to ", report, ". ") else "Complete list printed above. ",
      "No scan started.")
    stop(structure(list(message = message, call = NULL, missing_files = missing),
      class = c("missing_input_files", "error", "condition")))
  }
  invisible(missing)
}
