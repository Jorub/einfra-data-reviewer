source("source/reviewer.R")
source("source/llm.R")

# Exercise the real curl multi event loop with local response files only.
# Replace authenticated HTTP handle creation; no key or network access is used.
work <- tempfile(); dir.create(work)
success <- list(model = "fake", choices = list(list(finish_reason = "stop",
  message = list(content = "Synthetic answer"))), usage = list(completion_tokens = 5))
jsonlite::write_json(success, file.path(work, "valid.json"), auto_unbox = TRUE)
writeLines("FAKE_PRIVATE_INVALID_JSON", file.path(work, "invalid.json"))
seen_limits <- list()
real_parse <- parse_api_response
parse_api_response <- function(response) { response$status_code <- 200L; real_parse(response) }
api_request_handle <- function(route, payload, request_timeout, connection_timeout) {
  stopifnot(request_timeout == 600, connection_timeout == 20)
  seen_limits[[length(seen_limits) + 1L]] <<- "max_tokens" %in% names(payload)
  name <- payload$messages[[1]]$content
  curl::new_handle(url = paste0("file://", file.path(work, paste0(name, ".json"))))
}
pool <- curl::new_pool(total_con = 4, host_con = 4)
answers <- vector("list", 4)
for (i in 1:4) local({
  j <- i
  prompt <- c("valid", "invalid", "missing", "valid")[j]
  ask_llm(prompt, "fake", file.path(work, paste0("call-", j)), approved_prompt = prompt,
    send = TRUE, max_tokens = if (j == 4) NULL else 8192L, request_timeout = 600, pool = pool, callback = function(answer) answers[[j]] <<- answer)
})
while (any(vapply(answers, is.null, logical(1)))) curl::multi_run(timeout = 1, pool = pool)
stopifnot(answers[[1]]$text == "Synthetic answer", answers[[4]]$text == "Synthetic answer",
  inherits(answers[[2]], "error"), inherits(answers[[3]], "error"),
  !grepl("FAKE_PRIVATE_INVALID_JSON", conditionMessage(answers[[2]]), fixed = TRUE),
  !grepl(work, sub(".*raw details", "raw details", conditionMessage(answers[[3]])), fixed = TRUE))
for (j in 1:4) {
  attempt <- list.dirs(file.path(work, paste0("call-", j)), recursive = FALSE, full.names = TRUE)[1]
  metadata <- jsonlite::read_json(file.path(attempt, "metadata.json"))
  stopifnot(metadata$status == if (j %in% c(1, 4)) "COMPLETED" else "API_ERROR",
    metadata$request_timeout == 600, is.numeric(metadata$elapsed_seconds),
    metadata$max_tokens_source == if (j == 4) "provider_default" else "explicit")
}
stopifnot(identical(unlist(seen_limits), c(TRUE, TRUE, TRUE, FALSE)))
unlink(work, recursive = TRUE)
cat("Asynchronous LLM passed: real curl multi callbacks, saved response/error metadata and privacy using local files. No credentials or network calls.\n")
