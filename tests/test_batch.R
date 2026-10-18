source('source/reviewer.R');source('source/batch.R')
# Test loop behavior without scanning data or making API calls.
check_netcdf <- function(path,...) {
 if(path=='broken.nc') stop('Synthetic unreadable file')
 x<-data.frame(check = 'units',status = 'PASS',detail = 'Synthetic good check')
 attr(x,'review_evidence')<-list(filename = list(basename = path),observed = list(variable = 'synthetic'))
 x
}
review_checks <- function(checks,report_dir,...) {
 run<-file.path(report_dir,'review-test');dir.create(run)
 f<-attr(checks,'review_evidence')$filename$basename
 if(f=='token-limit.nc') {
  write.csv(data.frame(llm_status = 'TOKEN_LIMIT',result = 'INCOMPLETE',reason = 'Token budget exhausted'),
    file.path(run,'review_index.csv'),row.names = FALSE)
  stop('Synthetic token exhaustion')
 }
 write.csv(data.frame(llm_status = 'COMPLETED',result = 'PASS',reason = 'No issues identified'),
    file.path(run,'review_index.csv'),row.names = FALSE)
 run
}
out<-tempfile();dir.create(out)
specs<-lapply(c('broken.nc','token-limit.nc','valid.nc'),function(p)list(path = p))
r<-run_netcdf_reviews(specs,out,send_to_api = TRUE)
stopifnot(identical(r$index$result,c('INCOMPLETE','INCOMPLETE','PASS')))
stopifnot(identical(r$index$checks_status,c('ERROR','COMPLETED','COMPLETED')))
stopifnot(identical(r$index$llm_status,c('NOT_RUN','TOKEN_LIMIT','COMPLETED')))
stopifnot(nrow(read.csv(file.path(r$run_dir,'summary.csv')))==3)
stopifnot(nrow(read.csv(file.path(r$run_dir,'flagged_files.csv')))==2)
r<-run_netcdf_reviews(list(list(path = 'valid.nc')),out,send_to_api = FALSE)
stopifnot(r$index$result=='INCOMPLETE',r$index$llm_status=='NOT_RUN')
unlink(out,recursive = TRUE)
cat('Sequential batch tests passed: scan error and token limit do not prevent the next file; checkpoint and summary rows retained. No API calls.\n')
