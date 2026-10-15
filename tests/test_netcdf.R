source("R/reviewer.R")
source("R/netcdf.R")
library(ncdf4)
make_fixture <- function(path, units="degC", missing_month=FALSE, duplicate_month=FALSE,
                         spacing=90, calendar="standard", all_missing=FALSE) {
  dates <- seq(as.Date("2000-01-15"),by="month",length.out=24)
  if(missing_month) dates <- dates[-5]
  if(duplicate_month) dates[5] <- dates[4]
  lon <- ncdim_def("lon","degrees_east",seq(-135,by=spacing,length.out=4))
  lat <- ncdim_def("lat","degrees_north",c(-45,45))
  time <- ncdim_def("time","days since 2000-01-01",as.numeric(dates-as.Date("2000-01-01")),calendar=calendar)
  def <- ncvar_def("t2m",units,list(lon,lat,time),missval=-9999,prec="float")
  n <- nc_create(path,def)
  values <- array(rep(c(NA,2,5,10,15,20,25,30),length(dates)),c(4,2,length(dates)))
  if(all_missing) values[,,5] <- NA
  ncvar_put(n,def,values);nc_close(n)
}
run <- function(...) {
 f <- tempfile(fileext=".nc");on.exit(unlink(f));make_fixture(f,...)
 before <- tools::md5sum(f)
 x <- check_netcdf(f,resolution=90,start_month="2000-01",end_month="2001-12",use_system_tools=FALSE)
 stopifnot(identical(before,tools::md5sum(f)))
 stopifnot(!grepl(f,prepare_review(x),fixed=TRUE))
 x
}
x <- run(); stopifnot(!any(x$status=="FAIL"))
stopifnot(attr(x,"review_evidence")$value_scan$slices==24)
x <- run(units="K");stopifnot(x$status[x$check=="temperature_units"]=="FAIL")
x <- run(missing_month=TRUE);stopifnot(x$status[x$check=="monthly_time_axis"]=="FAIL")
x <- run(duplicate_month=TRUE);stopifnot(x$status[x$check=="monthly_time_axis"]=="FAIL")
x <- run(spacing=80);stopifnot(x$status[x$check=="lon_resolution"]=="FAIL")
x <- run(calendar="360_day");stopifnot(x$status[x$check=="monthly_time_axis"]=="NOT_CHECKED")
x <- run(all_missing=TRUE);stopifnot(x$status[x$check=="nonempty_time_slices"]=="FAIL")
stopifnot(nchar(prepare_review(x),type="bytes")<16000)
cat("NetCDF tests passed: valid baseline, wrong units, missing/duplicate months, wrong resolution, unsupported calendar, missing slice, unchanged input, and payload path exclusion.\n")
