source("source/run_paths.R")
source("source/input_paths.R")

# Sequential pilot runner. Each file has an explicit scientific contract.
# No automatic retries: record failure, checkpoint index, continue.
run_netcdf_reviews <- function(file_specs, output_dir, model = "thinker",
                               max_tokens = 8192L, reasoning_effort = NULL,
                               send_to_api = FALSE, max_input_bytes = 64000L) {
  if(!is.list(file_specs)||!length(file_specs)) stop("Supply a nonempty list of file specifications.")
  if(!is.character(output_dir)||length(output_dir)!=1||is.na(output_dir)||!nzchar(output_dir)) stop("Set output_dir.")
  check_input_files(file_specs, report_dir = output_dir) # save/print every missing path before scanning
  if(!dir.exists(output_dir)&&!dir.create(output_dir,recursive = TRUE)) stop("Cannot create output_dir.")
  batch <- new_scan_directory(output_dir)
  # Explicit opt-in covers the built-in filename/metadata/summary/history payloads
  # for these selected files. It is not authorization for arbitrary directories.
  names_only <- vapply(file_specs,function(s) {
    p <- s$path
    if(is.character(p)&&length(p)==1&&!is.na(p)&&nzchar(p)) basename(p) else "unspecified"
  },character(1))
  input_paths <- vapply(file_specs, function(s) {
    p <- s$path
    if (is.character(p) && length(p) == 1 && !is.na(p)) p else ""
  }, character(1))
  index <- data.frame(input_index = seq_along(file_specs),filename = names_only,input_path = input_paths,
    variable = "unspecified",checks_status = "PENDING",llm_status = "NOT_RUN",result = "INCOMPLETE",
    reason = "Not processed yet",report_path = "",stringsAsFactors = FALSE)
  overview <- vector("list", length(file_specs))
  checkpoint <- function() {
    write.csv(index,file.path(batch,"review_index.csv"),row.names = FALSE)
    write.csv(index[c("filename","result","reason")],file.path(batch,"summary.csv"),row.names = FALSE)
    write.csv(index[index$result!="PASS",],file.path(batch,"flagged_files.csv"),row.names = FALSE)
    rows <- lapply(seq_along(file_specs), function(i) {
      prefix <- index[i, c("input_index", "filename", "input_path", "checks_status"), drop = FALSE]
      displayed <- attr(file_specs, "data_file_paths")
      prefix$data_file_path <- if (length(displayed) == length(file_specs)) displayed[i] else index$input_path[i]
      cbind(prefix, if (is.null(overview[[i]])) empty_data_overview() else overview[[i]])
    })
    write.csv(do.call(rbind, rows), file.path(batch, "data_overview.csv"), row.names = FALSE)
  }
  checkpoint()
  for(i in seq_along(file_specs)) {
    message("File ",i,"/",length(file_specs),": ",names_only[i])
    local_dir <- file.path(batch,sprintf("file-%03d",i))
    dir.create(local_dir)
    index$report_path[i] <- local_dir
    tryCatch({
    # Stage 1 failures remain distinguishable from LLM failures.
    checks <- tryCatch({
      spec <- file_specs[[i]]
      if(!is.list(spec)||is.null(spec$path)||!nzchar(spec$path)) stop("Missing input path in file specification.")
      before <- source_file_stamp(spec$path)
      checked <- do.call(check_netcdf, spec)
      after <- source_file_stamp(spec$path)
      attr(checked, "scan_record") <- list(scanner_version = attr(checked, "review_evidence")$checker_version,
        scan_time_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
        scanner_files_md5 = as.list(tools::md5sum(c("source/netcdf.R", "source/netcdf_time.R", "source/netcdf_families.R", "source/mask_provenance.R"))),
        before = before, after = after,
        source_unchanged_during_scan = identical(before, after))
      checked
    },error = function(e) {
      index$checks_status[i] <<- "ERROR"
      index$reason[i] <<- paste("NetCDF check error:",conditionMessage(e))
      writeLines(conditionMessage(e),file.path(local_dir,"check-error.txt"))
      NULL
    })
    if(is.null(checks)) { checkpoint();next }
    index$checks_status[i] <- "COMPLETED"
    variable <- attr(checks,"review_evidence")$observed$variable
    if(!is.null(variable)) index$variable[i] <- variable
    saveRDS(checks,file.path(local_dir,"local-diagnostics.rds"))
    write_diagnostic_tables(checks, local_dir)
    overview[[i]] <- data_overview_row(checks, local_dir)
    write.csv(checks,file.path(local_dir,"checks.csv"),row.names = FALSE)
    initial <- review_summary(checks,"NOT_COMPLETED")
    index$result[i] <- initial$result; index$reason[i] <- initial$reason
    preview <- tryCatch(as.character(prepare_review(checks)),error = function(e) {
      index$llm_status[i] <<- "PREPARATION_ERROR"
      index$reason[i] <<- paste("Payload preparation error:",conditionMessage(e))
      NULL
    })
    if(is.null(preview)) { checkpoint();next }
    writeLines(preview,file.path(local_dir,"review-preview.json"))
    # This function never prompts for a key inside the loop.
    if(!send_to_api) {
      row <- review_summary(checks,"NOT_RUN")
      index$result[i] <- row$result; index$reason[i] <- row$reason
      checkpoint();next
    }
    failure <- NULL
    run <- tryCatch(review_checks(checks,model = model,approved_payload = preview,send = TRUE,
      report_dir = local_dir,max_tokens = max_tokens,reasoning_effort = reasoning_effort,
      max_input_bytes = max_input_bytes),
      error = function(e) { failure <<- conditionMessage(e);NULL })
    if(!is.null(run)) {
      row <- read.csv(file.path(run,"review_index.csv"),stringsAsFactors = FALSE)
      index$llm_status[i] <- row$llm_status[1];index$result[i] <- row$result[1]
      index$reason[i] <- row$reason[1];index$report_path[i] <- run
    } else {
      # Recover the persisted status from review_checks, including token limits.
      attempts <- list.dirs(local_dir,recursive = FALSE,full.names = TRUE)
      records <- file.path(attempts,"review_index.csv")
      records <- records[file.exists(records)]
      if(length(records)) {
        r <- read.csv(records[1],stringsAsFactors = FALSE)
        index$llm_status[i] <- r$llm_status[1];index$result[i] <- r$result[1]
        index$reason[i] <- r$reason[1];index$report_path[i] <- dirname(records[1])
      } else {
        row <- review_summary(checks,"REQUEST_ERROR")
        index$llm_status[i] <- "REQUEST_ERROR";index$result[i] <- row$result
        index$reason[i] <- paste(row$reason,failure,sep = "; ")
      }
      writeLines(failure,file.path(local_dir,"review-error.txt"))
    }
    },error = function(e) {
      # Unexpected per-file exceptions must not abort subsequent inputs.
      if(index$result[i]!="FAIL") index$result[i] <<- "INCOMPLETE"
      if(index$checks_status[i]=="PENDING") index$checks_status[i] <<- "ERROR"
      index$llm_status[i] <<- "FILE_ERROR"
      index$reason[i] <<- paste("Unexpected per-file error:",conditionMessage(e))
    })
    checkpoint()
  }
  message("Batch finished. Short summary: ",file.path(batch,"summary.csv"))
  invisible(list(index = index,run_dir = batch))
}

# Discovery only: no values or API calls. Expectations still come from filenames.
folder_file_specs <- function(root, family, recursive = TRUE,
                              scan_values = TRUE, use_system_tools = TRUE,
                              include_history = TRUE) {
  allowed <- c("evap", "other", "precip", "runoff", "snow", "soilmoisture", "temperature")
  if (length(family) != 1 || !family %in% allowed) stop("Choose one supported family for this folder.")
  files <- netcdf_file_inventory(root, recursive = recursive)
  excluded <- attr(files, "excluded_entries")
  if (!length(files)) stop("No eligible .nc, .nc4 or .cdf files found under the selected root.")
  specs <- lapply(sort(unique(as.character(files))), function(path) list(
    path = path, family = family, scan_values = scan_values,
    use_system_tools = use_system_tools, include_history = include_history))
  attr(specs, "excluded_entries") <- excluded
  specs
}

# Source identity is local only; file stat checks are not content checksums.
source_file_stamp <- function(path) {
  info <- file.info(path)
  list(bytes = unname(info$size), modified_utc = format(info$mtime, tz = "UTC", usetz = TRUE))
}
empty_data_overview <- function() {
  data.frame(variable = NA_character_, units = NA_character_, mean = NA_real_, min = NA_real_, max = NA_real_,
    lon_first = NA_real_, lon_last = NA_real_, lat_first = NA_real_, lat_last = NA_real_,
    lon_min = NA_real_, lon_max = NA_real_, lat_min = NA_real_, lat_max = NA_real_,
    lon_spacing = NA_real_, lat_spacing = NA_real_, n_lon = NA_real_, n_lat = NA_real_,
    n_layers = NA_real_, time_first = NA_character_, time_last = NA_character_, missing_period_count = NA_real_,
    recorded_operations = NA_character_, history_truncated = NA, scanner_version = NA_character_,
    scan_time_utc = NA_character_, bytes = NA_real_, modified_utc = NA_character_,
    source_unchanged_during_scan = NA, stringsAsFactors = FALSE)
}
data_overview_row <- function(checks, directory) {
  row <- empty_data_overview()
  summary <- read.csv(file.path(directory, "file-summary.csv"), stringsAsFactors = FALSE)
  names_to_copy <- intersect(names(row), names(summary))
  row[1, names_to_copy] <- summary[1, names_to_copy]
  evidence <- attr(checks, "review_evidence")
  row$lon_spacing <- if (is.null(evidence$observed$lon$spacing_min)) NA_real_ else evidence$observed$lon$spacing_min
  row$lat_spacing <- if (is.null(evidence$observed$lat$spacing_min)) NA_real_ else evidence$observed$lat$spacing_min
  history <- evidence$processing_history
  row$history_truncated <- isTRUE(history$truncated)
  if (isTRUE(history$available)) {
    # Preserve included, redacted history verbatim; do not infer execution order or corrections.
    row$recorded_operations <- paste(history$text, collapse = "\n")
  }
  record <- attr(checks, "scan_record")
  if (!is.null(record)) {
    row$scanner_version <- if (is.null(record$scanner_version)) NA_character_ else record$scanner_version
    row$scan_time_utc <- record$scan_time_utc
    row$bytes <- record$before$bytes; row$modified_utc <- record$before$modified_utc
    row$source_unchanged_during_scan <- record$source_unchanged_during_scan
  }
  row
}
scan_netcdf_files <- function(file_specs, output_dir) {
  check_scan_dependencies()
  run_netcdf_reviews(file_specs, output_dir = output_dir, send_to_api = FALSE)
}
