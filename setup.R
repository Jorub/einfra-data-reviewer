# Sources ---------------------------------------------------------------------
source("source/project_setup.R")

# Configuration ---------------------------------------------------------------
required_packages <- c("curl", "jsonlite", "ncdf4", "CFtime")
private_dir <- path.expand("~/.config/einfra-data-reviewer")

# Setup -----------------------------------------------------------------------
setup_project(private_dir = private_dir)
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  configured_repos <- getOption("repos")
  if (is.null(configured_repos) || !length(configured_repos) ||
      any(is.na(configured_repos) | configured_repos == "@CRAN@" | !nzchar(configured_repos)))
    configured_repos <- c(CRAN = "https://cloud.r-project.org")
  install.packages(missing_packages, repos = configured_repos)
}
unavailable <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(unavailable)) stop("Setup incomplete; packages unavailable: ", paste(unavailable, collapse = ", "))
message("Setup complete. Fill your private credentials file only when API review is needed. Existing configuration preserved.")
