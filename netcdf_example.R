# Open in RStudio and run section by section. Data paths stay local.
source("setup.R")
source("R/reviewer.R")
source("R/netcdf.R")

# Select the supplied ERA5-Land monthly Celsius file in the file picker.
data_path <- file.choose()
checks <- check_netcdf(
  path = data_path, expected_units = "degC", resolution = 0.25,
  start_month = "2000-01", end_month = "2019-12",
  global_grid = TRUE, scan_values = TRUE, use_system_tools = TRUE,
  include_history = TRUE
)
print(checks)
# If data_variable fails due to ambiguity, rerun with variable = "actual_name".

# Full time-slice summaries and tool outputs remain local.
View(attr(checks, "local_slice_statistics"))
print(attr(checks, "local_tool_results"))
preview <- prepare_review(checks)
cat(preview)

# After inspecting the payload, explicitly request the LLM review:
# set_api_key() # skip if already set in this session
# print(list_models())
# report_dir <- readline("Local report directory: ")
# saveRDS(checks, file.path(report_dir, "netcdf-local-diagnostics.rds"))
# run <- review_checks(checks, model = "thinker", approved_payload = preview,
#               send = TRUE, report_dir = report_dir, max_tokens = 8192L,
#               reasoning_effort = "medium")
# read.csv(file.path(run, "summary.csv")) # capture run <- review_checks(...) above
# clear_api_key()
