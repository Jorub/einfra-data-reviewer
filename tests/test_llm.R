source("R/reviewer.R")
source("R/llm.R")
p <- build_prompt("role","context","task","synthetic evidence","constraints","Markdown","specific answer")
stopifnot(grepl("Supplied evidence",p,fixed=TRUE),grepl("task",p,fixed=TRUE))
stopifnot(inherits(try(build_prompt("r","c",""),silent=TRUE),"try-error"))
f <- tempfile(fileext=".txt");writeLines("synthetic source",f)
e <- read_prompt_evidence(f)
stopifnot(grepl("synthetic source",e,fixed=TRUE),!grepl(f,e,fixed=TRUE))
stopifnot(inherits(try(read_prompt_evidence(f,max_bytes=1),silent=TRUE),"try-error"));unlink(f)
out <- tempfile();dir.create(out)
api_request <- function(route,payload) {
 stopifnot(!"reasoning_effort" %in% names(payload),payload$max_tokens==8192L)
 list(model="mock",choices=list(list(finish_reason="stop",message=list(content="# Synthetic answer\nDone."))),usage=list(total_tokens=10))
}
a <- ask_llm(p,"mock",out,approved_prompt=p,send=TRUE)
stopifnot(file.exists(file.path(a$run_dir,"response.md")),a$metadata$complete)
stopifnot(!anyDuplicated(c(a$run_dir,ask_llm(p,"mock",out,approved_prompt=p,send=TRUE)$run_dir)))
stopifnot(inherits(try(ask_llm(p,"mock",out,approved_prompt="changed",send=TRUE),silent=TRUE),"try-error"))
for(mode in c("length","empty","error")) {
 api_request <- local({m<-mode;function(...) {
  if(m=="error") stop("Synthetic failure")
  list(choices=list(list(finish_reason=if(m=="length") "length" else "stop",
    message=list(content=if(m=="empty") "" else "Partial answer"))),usage=list())
 }})
 dest<-file.path(out,mode)
 stopifnot(inherits(try(ask_llm(p,"mock",dest,approved_prompt=p,send=TRUE),silent=TRUE),"try-error"))
 run <- list.dirs(dest,recursive=FALSE,full.names=TRUE)[1]
 stopifnot(!file.exists(file.path(run,"response.md")),!jsonlite::read_json(file.path(run,"metadata.json"))$complete)
}
unlink(out,recursive=TRUE)
cat("Direct LLM tests passed: prompt building, text-only evidence, approval, request shape, Markdown output, unique runs and incomplete/error handling. No API calls.\n")
