# Run once from the project root in RStudio: source("setup.R")
# Install only missing runtime packages; leave installed versions unchanged.
required_packages <- c("curl", "jsonlite", "getPass")
missing_packages <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]

if (length(missing_packages)) {
  message("Installing missing packages: ", paste(missing_packages, collapse = ", "))
  configured_repos <- getOption("repos")
  if (is.null(configured_repos) || !length(configured_repos) ||
      any(is.na(configured_repos) | configured_repos == "@CRAN@" | !nzchar(configured_repos))) {
    configured_repos <- c(CRAN = "https://cloud.r-project.org")
  }
  install.packages(missing_packages, repos = configured_repos)
}

unavailable <- required_packages[!vapply(
  required_packages, requireNamespace, logical(1), quietly = TRUE
)]
if (length(unavailable)) {
  stop("Setup incomplete; packages unavailable: ", paste(unavailable, collapse = ", "),
       ". Check installation messages, network access, and library write permissions.")
}
message("Setup complete: curl, jsonlite, and getPass are available. No API key needed.")
