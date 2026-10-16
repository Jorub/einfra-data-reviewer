source("R/reviewer.R")
source("R/netcdf.R")
stopifnot(parse_netcdf_filename("era5-land_t2m_degC_land_200001_201912_025_monthly.nc")$valid)
bad <- parse_netcdf_filename("fldas_tp_mm_land_198201_2022112_025_yearly.nc")
stopifnot(!bad$valid,grepl("end date",paste(bad$issues,collapse=" ")))
stopifnot(!parse_netcdf_filename("unstructured.nc")$valid)
checks <- data.frame(check="temperature_units",status="FAIL",detail="Expected Celsius; stored units: K")
attr(checks,"review_evidence") <- list(filename=parse_netcdf_filename("synthetic_t2m_degC_land_200001_201912_025_monthly.nc"),
  observed=list(variable="t2m",units="K",scale_factor=1,add_offset=0),
  value_scan=list(global_min=476.3959,global_max=588.2975),
  processing_history=list(text="cdo -addc,273.15 [PATH REDACTED] [PATH REDACTED]"))
p <- prepare_review(checks)
stopifnot(grepl('synthetic_t2m_degC_land_200001_201912_025_monthly.nc',p,fixed=TRUE))
# Mock API responses only: test software behavior, not model competence.
output <- tempfile();dir.create(output)
api_request <- function(route,payload) {
 stopifnot(payload$reasoning_effort=="medium")
 list(model="mock",choices=list(list(finish_reason="stop",message=list(content=
  jsonlite::toJSON(list(verdict="FAIL",reason="Wrong sign in the recorded Celsius conversion; implausible temperatures.",
    report_markdown="## Findings\nRecorded addc conversion has the wrong sign. Verify source before repair."),auto_unbox=TRUE)))),
  usage=list(completion_tokens=100))
}
run <- review_checks(checks,"mock",p,send=TRUE,report_dir=output,reasoning_effort="medium")
r <- read.csv(file.path(run,"summary.csv"))
stopifnot(identical(names(r),c("filename","result","reason")),r$result=="FAIL",file.exists(file.path(run,"review.md")))
m <- jsonlite::read_json(file.path(run,"metadata.json"));stopifnot(m$complete,m$llm_status=="COMPLETED",m$reasoning_effort=="medium")
# A model PASS cannot override deterministic failures.
parsed <- list(verdict="PASS",reason="No issues identified",report_markdown="Test report")
stopifnot(review_summary(checks,"COMPLETED",parsed)$result=="FAIL")
clean <- checks;clean$status <- "PASS"
stopifnot(review_summary(clean,"TOKEN_LIMIT")$result=="INCOMPLETE")
stopifnot(review_summary(checks,"TOKEN_LIMIT")$result=="FAIL")
stopifnot(is.null(parse_review_response('{"verdict":"MAYBE"}')))
stopifnot(is.null(parse_review_response('```json\n{}\n```')))
stopifnot(is.null(parse_review_response('{"verdict":"PASS","reason":"ok","report_markdown":"fine","extra":"bad"}')))
# Check persisted summaries for invalid, truncated, empty and failed API calls.
for(mode in c("invalid","length","empty","api_error")) {
 api_request <- local({kind <- mode;function(...) {
   if(kind=="api_error") stop("Synthetic transport failure")
   list(model="mock",choices=list(list(finish_reason=if(kind=="length") "length" else "stop",
       message=list(content=if(kind=="empty") "" else "not valid JSON"))),usage=list())
 }})
 dir <- file.path(output,mode);dir.create(dir)
 err <- try(review_checks(clean,"mock",prepare_review(clean),send=TRUE,report_dir=dir),silent=TRUE)
 stopifnot(inherits(err,"try-error"))
 rr <- list.dirs(dir,recursive=FALSE,full.names=TRUE)[1]
 stopifnot(read.csv(file.path(rr,"summary.csv"))$result=="INCOMPLETE")
 stopifnot(!jsonlite::read_json(file.path(rr,"metadata.json"))$complete)
}
# CSV quoting handles comma-containing filenames and explanations.
s <- review_summary(checks,"COMPLETED",list(verdict="FAIL",reason="One, two",report_markdown="Details"))
s$filename <- "synthetic,example.nc";f<-file.path(output,"quoted.csv");write.csv(s,f,row.names=FALSE)
stopifnot(identical(read.csv(f,stringsAsFactors=FALSE),s))
unlink(output,recursive=TRUE)
cat("Filename parsing, JSON schema, detailed report, CSV quoting, deterministic precedence and incomplete-response checkpoint tests passed. No live API calls.\n")

stopifnot(is.null(review_request("mock","test",8192)$reasoning_effort))
stopifnot(!"reasoning_effort" %in% names(review_request("mock","test",8192)))
stopifnot(review_request("mock","test",8192,"medium")$reasoning_effort=="medium")
b <- charToRaw('{"error":{"message":"Unsupported reasoning_effort; FAKE_PRIVATE_SENTINEL","param":"reasoning_effort"}}')
z <- http_error_summary(400,b)
stopifnot(grepl("reasoning_effort",z,fixed=TRUE),!grepl("FAKE_PRIVATE_SENTINEL",z,fixed=TRUE))
stopifnot(!grepl("FAKE_PRIVATE_SENTINEL",http_error_summary(400,charToRaw("FAKE_PRIVATE_SENTINEL")),fixed=TRUE))
cat("Optional reasoning field and whitelisted HTTP diagnostic tests passed.\n")
