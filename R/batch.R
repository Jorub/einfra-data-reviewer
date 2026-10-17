# Sequential pilot runner. Each file has an explicit scientific contract.
# No automatic retries: record failure, checkpoint index, continue.
run_netcdf_reviews <- function(file_specs, output_dir, model = "thinker",
                               max_tokens = 8192L, reasoning_effort = NULL,
                               send_to_api = FALSE, max_input_bytes = 64000L) {
  if(!is.list(file_specs)||!length(file_specs)) stop("Supply a nonempty list of file specifications.")
  if(!is.character(output_dir)||length(output_dir)!=1||is.na(output_dir)||!nzchar(output_dir)) stop("Set output_dir.")
  if(!dir.exists(output_dir)&&!dir.create(output_dir,recursive = TRUE)) stop("Cannot create output_dir.")
  batch <- tempfile("batch-",tmpdir = output_dir)
  if(!dir.create(batch)) stop("Cannot create batch directory.")
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
  checkpoint <- function() {
    write.csv(index,file.path(batch,"review_index.csv"),row.names = FALSE)
    write.csv(index[c("filename","result","reason")],file.path(batch,"summary.csv"),row.names = FALSE)
    write.csv(index[index$result!="PASS",],file.path(batch,"flagged_files.csv"),row.names = FALSE)
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
      do.call(check_netcdf,spec)
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
