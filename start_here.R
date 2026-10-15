# Open this project in RStudio; run one section at a time.
# Install missing dependencies once (no API key required):
# source("setup.R")
source("R/reviewer.R")

# Offline pilot: synthetic example only, no API call.
f <- tempfile(fileext = ".csv")
write.csv(data.frame(id = c(1, 1, 3), value = c(2, -4, NA)), f, row.names = FALSE)
checks <- check_csv(f, required_columns = c("id", "value"),
                    numeric_columns = "value", ranges = list(value = c(0, 10)),
                    unique_key = "id")
print(checks)

# API preflight: uncomment in your own interactive RStudio session.
# set_api_key()
# models <- list_models()
# print(models)

# Explicit review approval: inspect everything that would be sent.
preview <- prepare_review(checks)
cat(preview)
# Pick an available reasoning model, e.g. thinker if list_models() lists it.
# review_checks(checks, model = "thinker", approved_payload = preview, send = TRUE,
#               report_dir = report_dir)
# clear_api_key()

# Remove the temporary synthetic file.
unlink(f)

# Your data: select paths at runtime in RStudio; never hard-code server folders.
# data_path <- file.choose()
# report_dir <- readline("Local report directory (not sent to the API): ")
# checks <- check_csv(data_path, required_columns = c("your_required_column"))
# preview <- prepare_review(checks)
# cat(preview)
# review_checks(checks, model = "thinker", approved_payload = preview,
#               send = TRUE, report_dir = report_dir)
# For several CSVs with the same contract:
# results <- check_files(paths = c(first_path, second_path),
#                        required_columns = c("your_required_column"))
