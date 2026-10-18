# Tests run in separate R processes so mocks cannot leak between suites.
files <- sort(list.files("tests", pattern = "^test_.*[.]R$", full.names = TRUE))
if (!length(files)) stop("Run from the repository root.")
failed <- character()
for (file in files) {
  message("Running ", file)
  status <- system2(file.path(R.home("bin"), "Rscript"), shQuote(file))
  if (status != 0L) failed <- c(failed, file)
}
if (length(failed)) stop("Failed: ", paste(failed, collapse = ", "))
message("All ", length(files), " offline suites passed. No live model calls.")
