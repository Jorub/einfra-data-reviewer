# Local-only NetCDF inventory. No API calls, value scans or data modifications.
# Folder/filename hints are not scientific validation contracts.
sim_family_hint <- function(relative_path) {
  pieces <- strsplit(gsub("\\\\", "/", relative_path), "/", fixed = TRUE)[[1]]
  families <- c("temperature", "precip", "evap", "runoff", "soilmoisture", "snow",
    "hiq_lai", "sensibleheat", "relative_humidity", "groundwaterlevel", "latentheat",
    "vaporpressure", "cloudcover", "radiation", "shortrad", "netrad", "longrad")
  hit <- families[families %in% pieces]
  if (!length(hit)) return("unknown")
  # Most specific radiation subfolder takes precedence.
  tail(hit, 1)
}
netcdf_file_inventory <- function(root, recursive = TRUE) {
  if (!dir.exists(root)) stop("Choose an existing data root.")
  root <- normalizePath(root, mustWork = TRUE)
  dirs <- root; result <- character(); excluded <- character()
  while (length(dirs)) {
    current <- dirs[1]; dirs <- dirs[-1]
    entries <- list.files(current, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    if (!length(entries)) next
    links <- nzchar(Sys.readlink(entries))
    hidden <- startsWith(basename(entries), ".")
    excluded <- c(excluded, entries[links | hidden])
    entries <- entries[!links & !hidden]
    info <- file.info(entries)
    isdir <- !is.na(info$isdir) & info$isdir
    if (recursive) dirs <- c(dirs, entries[isdir])
    result <- c(result, entries[!isdir & grepl("\\.(nc|nc4|cdf)$", entries, ignore.case = TRUE)])
  }
  attr(result, "excluded_entries") <- excluded
  result
}
inventory_netcdf <- function(root, report_dir, recursive = TRUE) {
  if (!requireNamespace("ncdf4", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE))
    stop("Run setup.R first.")
  root <- normalizePath(root, mustWork = TRUE)
  if (!dir.exists(report_dir) && !dir.create(report_dir, recursive = TRUE)) stop("Cannot create report directory.")
  report_dir <- normalizePath(report_dir, mustWork = TRUE)
  if (identical(root, report_dir) || startsWith(paste0(report_dir,"/"),paste0(root,"/")))
    stop("Keep reports outside the scanned data root.")
  files <- netcdf_file_inventory(root, recursive)
  writeLines(attr(files,"excluded_entries"),file.path(report_dir,"inventory-excluded-entries.txt"))
  rows <- list()
  empty_row <- function(path) {
    rel <- substring(path,nchar(root)+2L)
    pieces <- strsplit(rel,"/",fixed = TRUE)[[1]]
    info <- file.info(path)
    data.frame(path = path,filename = basename(path),relative_path = rel,
      bytes = info$size,modified_utc = format(info$mtime,tz = "UTC",usetz = TRUE),
      family_hint = sim_family_hint(rel),
      stage_hint = if("raw" %in% pieces) "raw" else if("processed" %in% pieces) "processed" else "unspecified",
      frequency_hint = if(grepl("(^|_)daily([_.]|$)",basename(path))) "daily" else
        if(grepl("(^|_)monthly([_.]|$)",basename(path))) "monthly" else
        if(grepl("(^|_)(annual|yearly)([_.]|$)",basename(path))) "annual" else "unknown",
      variable = NA_character_,role = "unclassified",units = NA_character_,long_name = NA_character_,
      standard_name = NA_character_,dimensions = NA_character_,calendar = NA_character_,
      time_units = NA_character_,inspection_status = "METADATA_ONLY",note = "Values and scientific expectations not checked",
      stringsAsFactors = FALSE)
  }
  inspect_one <- function(path) {
    base <- empty_row(path)
    tryCatch({
      n <- ncdf4::nc_open(path)
      on.exit(ncdf4::nc_close(n))
      att <- function(v,a,default = "") {
        x <- ncdf4::ncatt_get(n,v,a)
        if(isTRUE(x$hasatt)) paste(x$value,collapse = " ") else default
      }
      auxiliary <- unique(unlist(lapply(c(names(n$dim),names(n$var)),function(v)
        c(att(v,"bounds"),att(v,"grid_mapping")))))
      if(!length(n$var)) {
        base$inspection_status <- "REVIEW_NEEDED";base$note <- "No data variables listed by ncdf4"
        return(base)
      }
      do.call(rbind,lapply(names(n$var),function(name) {
        v <- n$var[[name]]; row <- base;row$variable <- name
        row$role <- if(name %in% auxiliary) "auxiliary" else "data_candidate"
        row$units <- att(name,"units")
        row$long_name <- att(name,"long_name")
        row$standard_name <- att(name,"standard_name")
        ds <- vapply(v$dim,function(d)d$name,character(1))
        lens <- vapply(v$dim,function(d)d$len,numeric(1))
        row$dimensions <- as.character(jsonlite::toJSON(as.list(setNames(lens,ds)),auto_unbox = TRUE))
        td <- v$dim[vapply(v$dim,function(d) tolower(d$name) %in% c("time","valid_time") || grepl(" since ",tolower(d$units),fixed = TRUE),logical(1))]
        if(length(td)==1) {
          row$calendar <- att(td[[1]]$name,"calendar","standard")
          row$time_units <- td[[1]]$units
        }
        row
      }))
    },error = function(e) {
      base$inspection_status <- "ERROR";base$note <- conditionMessage(e);base
    })
  }
  for(i in seq_along(files)) {
    message("Inventory ",i,"/",length(files),": ",basename(files[i]))
    rows[[i]] <- inspect_one(files[i])
    # Progress checkpoint after each file; local paths stay local.
    saveRDS(do.call(rbind,rows),file.path(report_dir,"inventory-progress.rds"))
  }
  result <- if(length(rows)) do.call(rbind,rows) else empty_row(file.path(root,"placeholder"))[FALSE,]
  write.csv(result,file.path(report_dir,"inventory.csv"),row.names = FALSE,na = "")
  summary <- if(nrow(result)) aggregate(rep(1L,nrow(result)),
    result[c("family_hint","stage_hint","frequency_hint","role","inspection_status")],sum) else data.frame()
  if(ncol(summary)) names(summary)[ncol(summary)] <- "variable_records"
  write.csv(summary,file.path(report_dir,"inventory-summary.csv"),row.names = FALSE)
  message("Inventory complete: ",length(files)," files; ",nrow(result)," variable records. No API requests made.")
  invisible(result)
}
