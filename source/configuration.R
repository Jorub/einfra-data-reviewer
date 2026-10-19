# Configuration ---------------------------------------------------------------
project_paths <- function(data_root = "", output_dir = "output", local_file = "config/paths.local.R") {
  if (!file.exists("einfra-data-reviewer.Rproj")) stop("Run from the repository root (open the RStudio project).")
  paths <- new.env(parent = baseenv())
  paths$data_root <- data_root; paths$output_dir <- output_dir
  if (file.exists(local_file)) sys.source(local_file, envir = paths)
  for (name in c("data_root", "output_dir")) {
    value <- paths[[name]]
    if (!is.character(value) || length(value) != 1 || is.na(value)) stop("Invalid path configuration: ", name)
  }
  if (!nzchar(paths$output_dir)) stop("Set output_dir.")
  list(data_root = paths$data_root, output_dir = paths$output_dir)
}

# Input table -----------------------------------------------------------------
read_data_file_paths <- function(table_file, data_root = "") {
  if (!file.exists(table_file)) stop("Input table missing: ", table_file)
  table <- read.csv(table_file, stringsAsFactors = FALSE, check.names = FALSE)
  if (anyDuplicated(names(table)) || !"data_file_path" %in% names(table) || !nrow(table))
    stop("Supply a nonempty CSV with a unique data_file_path column; family is optional.")
  paths <- table$data_file_path
  if (!is.character(paths) || anyNA(paths) || any(!nzchar(trimws(paths)))) stop("Input paths must be nonempty text.")
  absolute <- grepl("^(/|~|[A-Za-z]:[/\\\\])", paths)
  if (any(!absolute) && !nzchar(data_root)) stop("Relative input paths require data_root.")
  resolved <- path.expand(paths)
  resolved[!absolute] <- file.path(data_root, paths[!absolute])
  # File existence is checked per file by the scan, so one missing file cannot stop a batch.
  specs <- lapply(seq_along(paths), function(i) {
    spec <- list(path = resolved[i])
    if ("family" %in% names(table) && !is.na(table$family[i])) {
      group <- trimws(as.character(table$family[i]))
      if (nzchar(group)) spec$family <- group
    }
    if ("provenance_notes" %in% names(table) && !is.na(table$provenance_notes[i])) spec$provenance_notes <- table$provenance_notes[i]
    spec
  })
  attr(specs, "data_file_paths") <- paths
  specs
}

# Apply scan controls while preserving input-table identity.
configure_scan_specs <- function(file_specs, scan_values = TRUE, use_system_tools = TRUE, include_history = TRUE) {
  displayed <- attr(file_specs, "data_file_paths")
  result <- lapply(file_specs, function(spec) {
    spec$scan_values <- scan_values; spec$use_system_tools <- use_system_tools
    spec$include_history <- include_history
    spec
  })
  attr(result, "data_file_paths") <- displayed
  result
}
