# Project scaffolding ---------------------------------------------------------
setup_project <- function(project_root = ".", private_dir = path.expand("~/.config/einfra-data-reviewer")) {
  for (folder in c("source", "run_experiments", "config", "output", "docs", "tests")) {
    path <- file.path(project_root, folder)
    if (!dir.exists(path) && !dir.create(path, recursive = TRUE)) stop("Cannot create project directory.")
  }
  if (!dir.exists(private_dir) && !dir.create(private_dir, recursive = TRUE, mode = "0700"))
    stop("Cannot create private credentials directory.")
  credentials <- file.path(private_dir, "credentials.R")
  if (!file.exists(credentials)) {
    if (!file.copy(file.path(project_root, "config", "credentials.example.R"), credentials, overwrite = FALSE))
      stop("Cannot create credentials template.")
    Sys.chmod(credentials, mode = "0600")
  }
  invisible(NULL)
}
