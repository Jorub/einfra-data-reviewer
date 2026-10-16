# Family-specific review requirements. Sources may already have the named frequency. No guessed physical bounds or conversions.
family_review <- function(name, requirements) list(family = name, requirements = requirements)
check_temperature <- function() family_review("temperature", c(
  "Check physical plausibility in the declared Kelvin or Celsius units and inspect the conversion direction.",
  "For Tmin/Tmax aggregates establish whether values are means of daily extrema or extrema over the entire period. Timestamp frequency alone is insufficient."))
check_precip <- function() family_review("precip", c(
  "Establish whether values are rates or interval accumulations, and whether temporal aggregation used the right sum/mean and duration.",
  "Investigate negative precipitation and conversion factors, including calendar-dependent month lengths; distinguish negligible numerical artifacts from material errors."))
check_evap <- function() family_review("evap", c(
  "Establish rate versus accumulation, evaporation versus potential evaporation, and the documented positive/negative flux convention.",
  "Do not treat all negative evaporation as an error: resolve the source convention and any condensation before diagnosing."))
check_runoff <- function() family_review("runoff", c(
  "Identify runoff depth/rate versus discharge, surface versus subsurface versus total runoff, duration and any area conversion.",
  "Check that aggregation and units are consistent; do not assume discharge and depth are interchangeable."))
check_snow <- function() family_review("snow", c(
  "Identify snowfall accumulation/rate, snow depth, snow-water equivalent or snow-cover fraction before assessing values.",
  "Distinguish stocks from fluxes; establish aggregation semantics and whether density conversions were justified."))
check_soilmoisture <- function() family_review("soilmoisture", c(
  "Identify volumetric fraction versus mass/area, layer depth and any depth-integration conversion.",
  "Do not compare or sum layers without knowing their thicknesses and variable semantics; inspect extra dimensions."))
check_other <- function() family_review("other", c(
  "Identify the actual quantity from variable metadata and source evidence; this family contains heterogeneous variables.",
  "Check radiation flux versus accumulated energy, humidity fraction versus percent and relative versus specific humidity, pressure units, heat-flux sign conventions, groundwater datum/direction, and LAI versus a fraction when applicable.",
  "Explicitly report unresolved quantity-specific semantics rather than forcing a generic interpretation."))
netcdf_family <- function(path, variable, family = NULL) {
  allowed <- c("evap", "other", "precip", "runoff", "snow", "soilmoisture", "temperature")
  if (is.null(family)) {
    pieces <- strsplit(gsub("\\\\", "/", dirname(path)), "/", fixed = TRUE)[[1]]
    hit <- intersect(allowed, pieces)
    if (length(hit) == 1) family <- hit
  }
  if (is.null(family)) {
    v <- tolower(variable)
    family <- if (v %in% c("t2m", "tmin", "tmax", "tas", "tasmin", "tasmax", "temperature")) "temperature" else
      if (v %in% c("tp", "pr", "precip", "precipitation")) "precip" else "other"
  }
  if (length(family) != 1 || !family %in% allowed) stop("Unknown variable family.")
  get(paste0("check_", family), mode = "function")()
}
