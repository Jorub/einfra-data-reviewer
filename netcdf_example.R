# Sources ====================================================================
source("setup.R")
source("R/reviewer.R")
source("R/netcdf.R")

# Settings ===================================================================
# Set paths locally. Do not commit private paths or credentials to GitHub.
data_path <- ""
report_dir <- ""
variable <- NULL                    # optional actual variable selector if ambiguous
family <- NULL                      # infer from folder; optional family selector
provenance_notes <- ""              # optional supplied documentation, never invented
scan_values <- TRUE
use_system_tools <- TRUE
include_history <- TRUE
model <- "thinker"
reasoning_effort <- NULL             # omit field; use API/model default
max_tokens <- 8192L
max_input_bytes <- 64000L            # local payload guard; bytes, not tokens
send_to_api <- FALSE                 # explicit approval after inspecting preview

# Validate settings ==========================================================
if (!nzchar(data_path) || !file.exists(data_path))
  stop("Set data_path in the Settings block to an existing NetCDF file.")
if (!nzchar(report_dir)) stop("Set report_dir in the Settings block.")
if (!dir.exists(report_dir) && !dir.create(report_dir, recursive = TRUE))
  stop("Cannot create report_dir.")

# Read-only checks ===========================================================
checks <- check_netcdf(
  path = data_path, variable = variable, family = family,
  provenance_notes = provenance_notes, scan_values = scan_values,
  use_system_tools = use_system_tools, include_history = include_history
)
print(checks)
saveRDS(checks, file.path(report_dir, "netcdf-local-diagnostics.rds"))
write.csv(checks, file.path(report_dir, "netcdf-checks.csv"), row.names = FALSE)

# Preview ====================================================================
preview <- prepare_review(checks)
cat(preview, "\n")
writeLines(as.character(preview), file.path(report_dir, "review-preview.json"))

# Optional remote review =====================================================
# The only interactive input is the hidden credential prompt. No key is saved.
if (send_to_api) {
  if (!exists("key", envir = .einfra, inherits = FALSE)) set_api_key()
  run <- review_checks(
    checks, model = model, approved_payload = preview, send = TRUE,
    report_dir = report_dir, max_tokens = max_tokens,
    reasoning_effort = reasoning_effort, max_input_bytes = max_input_bytes
  )
  print(read.csv(file.path(run, "summary.csv")), row.names = FALSE)
}
# Detailed local diagnostics remain available in checks; no viewer popup is opened.
