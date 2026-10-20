source("source/reviewer.R")
source("source/llm.R")
p <- build_prompt("role","context","task","synthetic evidence","constraints","Markdown","specific answer")
stopifnot(grepl("Supplied evidence",p,fixed = TRUE),grepl("task",p,fixed = TRUE))
stopifnot(inherits(try(build_prompt("r","c",""),silent = TRUE),"try-error"))
f <- tempfile(fileext = ".txt");writeLines("synthetic source",f)
e <- read_prompt_evidence(f)
stopifnot(grepl("synthetic source",e,fixed = TRUE),!grepl(f,e,fixed = TRUE))
stopifnot(inherits(try(read_prompt_evidence(f,max_bytes = 1),silent = TRUE),"try-error"));unlink(f)
out <- tempfile();dir.create(out)
api_request <- function(route,payload) {
 stopifnot(!"reasoning_effort" %in% names(payload),payload$max_tokens==8192L)
 list(model = "mock",choices = list(list(finish_reason = "stop",message = list(content = "# Synthetic answer\nDone."))),usage = list(total_tokens = 10))
}
a <- ask_llm(p,"mock",out,approved_prompt = p,send = TRUE)
stopifnot(file.exists(file.path(a$run_dir,"response.md")),a$metadata$complete)
stopifnot(!anyDuplicated(c(a$run_dir,ask_llm(p,"mock",out,approved_prompt = p,send = TRUE)$run_dir)))
stopifnot(inherits(try(ask_llm(p,"mock",out,approved_prompt = "changed",send = TRUE),silent = TRUE),"try-error"))
for(mode in c("length","empty","error")) {
 api_request <- local({m<-mode;function(...) {
  if(m=="error") stop("Synthetic failure")
  list(choices = list(list(finish_reason = if(m=="length") "length" else "stop",
    message = list(content = if(m=="empty") "" else "Partial answer"))),usage = list())
 }})
 dest<-file.path(out,mode)
 stopifnot(inherits(try(ask_llm(p,"mock",dest,approved_prompt = p,send = TRUE),silent = TRUE),"try-error"))
 run <- list.dirs(dest,recursive = FALSE,full.names = TRUE)[1]
 metadata <- jsonlite::read_json(file.path(run,"metadata.json"))
 stopifnot(!file.exists(file.path(run,"response.md")), !metadata$complete,
   identical(metadata$status, switch(mode, length = "TOKEN_LIMIT", empty = "INCOMPLETE", error = "API_ERROR")),
   is.numeric(metadata$elapsed_seconds), metadata$elapsed_seconds >= 0, !is.null(metadata$finished_utc))
}
# Transport diagnostics retain useful categories while suppressing raw contents.
classes <- c("curl_error_operation_timedout", "curl_error_couldnt_resolve_host", "curl_error_couldnt_connect",
  "curl_error_ssl_connect_error", "curl_error_recv_error", "unrecognized_private_class")
labels <- c("TIMEOUT", "DNS_ERROR", "CONNECT_ERROR", "TLS_ERROR", "TRANSFER_ERROR", "UNKNOWN_TRANSPORT_ERROR")
for (i in seq_along(classes)) {
 condition <- structure(list(message = "FAKE_PRIVATE_SENTINEL https://private.invalid/token", call = NULL),
   class = c(classes[i], "error", "condition"))
 diagnostic <- connection_error_summary(condition)
 stopifnot(grepl(paste0("[", labels[i], "]"), diagnostic, fixed = TRUE),
   !grepl("FAKE_PRIVATE_SENTINEL", diagnostic, fixed = TRUE), !grepl("private.invalid", diagnostic, fixed = TRUE))
}
unlink(out,recursive = TRUE)
cat("Direct LLM tests passed: prompt building, text-only evidence, approval, request shape, Markdown output, unique runs and incomplete/error handling. No API calls.\n")
