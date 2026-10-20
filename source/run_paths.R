# Readable run names ----------------------------------------------------------
write_run_lineage <- function(run_dir, scan_id, stage, parent_dir = NULL) {
  jsonlite::write_json(list(scan_id = scan_id, stage = stage, parent_run = parent_dir),
    file.path(run_dir, "run-lineage.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(run_dir)
}
scan_run_id <- function(parent_dir) {
  lineage <- file.path(parent_dir, "run-lineage.json")
  if (file.exists(lineage)) {
    id <- jsonlite::read_json(lineage)$scan_id
    if (!is.character(id) || length(id) != 1 || !grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$", id))
      stop("Invalid saved scan identifier.")
    return(id)
  }
  # Adopt an existing legacy batch/rerun label; original reports are not renamed.
  label <- basename(normalizePath(parent_dir, mustWork = TRUE))
  label <- sub("^(batch|scan|review|rerun)-", "", label)
  label <- gsub("[^A-Za-z0-9_-]", "_", label)
  if (!nzchar(label) || !grepl("^[A-Za-z0-9]", label)) label <- paste0("saved", label)
  label
}
new_scan_directory <- function(output_dir) {
  run <- tempfile("scan-", tmpdir = output_dir)
  if (!dir.create(run)) stop("Cannot create scan directory.")
  id <- sub("^scan-", "", basename(run))
  write_run_lineage(run, id, "scan")
  run
}
linked_run_directory <- function(parent_dir, output_dir, stage) {
  if (!stage %in% c("scan", "review", "rerun")) stop("Unsupported run stage.")
  id <- scan_run_id(parent_dir)
  # mkdir reserves a name atomically: never reuse or overwrite an existing run.
  start <- if (stage == "rerun") 1L else 0L
  for (number in seq.int(start, 9999L)) {
    suffix <- if (number == 0L) "" else sprintf("-%02d", if (start == 0L) number + 1L else number)
    run <- file.path(output_dir, paste0(stage, "-", id, suffix))
    if (file.exists(run)) next
    if (dir.create(run, showWarnings = FALSE)) {
      write_run_lineage(run, id, stage, parent_dir)
      return(run)
    }
    if (!file.exists(run)) stop("Cannot create run directory; check output permissions.")
  }
  stop("Run numbering exhausted; choose another output directory.")
}
