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
check_input_files <- function(file_specs) {
  missing <- missing_input_files(file_specs)
  if (length(missing)) {
    message <- paste0("Input preflight failed: ", length(missing), " input file(s) not found from this R session:\n",
      paste0("- ", missing, collapse = "\n"),
      "\nDirectories are not valid input files. Correct the paths or mount/access, then rerun. No scan started.")
    stop(structure(list(message = message, call = NULL, missing_files = missing),
      class = c("missing_input_files", "error", "condition")))
  }
  invisible(missing)
}
