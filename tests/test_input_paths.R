source("source/configuration.R")
source("source/batch.R")

work <- tempfile(); dir.create(work); work <- normalizePath(work, mustWork = TRUE)
present <- file.path(work, "present file.nc"); writeLines("Path-only fixture", present)
missing <- file.path(work, c("missing-one.nc", "missing-two.nc"))
table_file <- file.path(work, "inputs.csv")
write.csv(data.frame(data_file_path = c(basename(present), basename(missing), basename(missing[1])),
  family = "temperature"), table_file, row.names = FALSE)
specs <- read_data_file_paths(table_file, data_root = work)
stopifnot(identical(missing_input_files(specs), missing),
  identical(check_input_files(list(list(path = present))), character()))
# Relative and home-relative paths expand without reading any file contents.
original_wd <- getwd(); setwd(work)
stopifnot(identical(missing_input_files(list(list(path = "missing-one.nc"))), missing[1]))
setwd(original_wd)
home_missing <- file.path("~", basename(work), "not-a-real-input.nc")
stopifnot(identical(missing_input_files(list(list(path = home_missing))), path.expand(home_missing)))
stopifnot(identical(missing_input_files(list(list(path = work))), work))
# Fail before any scan, inference or batch-folder creation, listing every missing path.
scan_calls <- 0L; api_calls <- 0L
check_netcdf <- function(...) { scan_calls <<- scan_calls + 1L; stop("Unexpected data read") }
api_request <- function(...) { api_calls <<- api_calls + 1L; stop("Unexpected API request") }
output <- file.path(work, "output")
printed <- capture.output(error <- tryCatch(run_netcdf_reviews(specs, output, send_to_api = TRUE), error = identity))
saved <- read.csv(file.path(output, "missing_files.csv"), stringsAsFactors = FALSE)
stopifnot(inherits(error, "missing_input_files"), identical(error$missing_files, missing),
  all(paste0("- ", missing) %in% printed), identical(saved$data_file_path, missing),
  scan_calls == 0L, api_calls == 0L, length(list.dirs(output, recursive = FALSE)) == 0)
for (invalid in list(list(), list(list()), list(list(path = NA_character_)), list(list(path = ""))))
  stopifnot(inherits(try(missing_input_files(invalid), silent = TRUE), "try-error"))
# A correction allows preflight to pass; it does not claim valid NetCDF contents.
for (path in missing) writeLines("Another path-only fixture", path)
stopifnot(identical(check_input_files(specs, report_dir = output), character()),
  nrow(read.csv(file.path(output, "missing_files.csv"))) == 0, scan_calls == 0L, api_calls == 0L)
# A long complete list survives independently of R's error-message display limit.
many <- file.path(work, paste0(sprintf("missing-%03d-", 1:50), strrep("x", 100), ".nc"))
printed <- capture.output(error <- tryCatch(check_input_files(lapply(many, function(path) list(path = path)),
  report_dir = output), error = identity))
stopifnot(length(error$missing_files) == 50, all(paste0("- ", many) %in% printed),
  identical(read.csv(file.path(output, "missing_files.csv"))$data_file_path, many))
unlink(work, recursive = TRUE)
cat("Input preflight passed: all missing paths returned/listed, expansion, directories, duplicate paths, zero scan/API calls and no batch created before failure.\n")
