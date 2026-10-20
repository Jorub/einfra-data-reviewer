# Review policy

These project-specific requirements govern checks and model review. They are not general environmental-data standards.

## Filename-derived expectations

The current common NetCDF checker parses:

`DATASET_VARIABLE_UNIT_SCALE_START_END_SPATIALRESOLUTION_TEMPORALRESOLUTION.nc`

Do not manually repeat units, dates or frequency in `file_specs`. Example:

```r
file_specs <- list(
  list(path = "<first file>"),
  list(path = "<second file>"),
  list(path = "<third file>")
)
```

Eight nonempty fields and valid YYYYMM endpoints are required. Malformed dates are flagged, not silently repaired. Kelvin and Celsius are both supported; the filename's units are checked against the NetCDF attribute. Known Celsius/Kelvin spelling variants are normalized, but arbitrary physical unit conversions or variable-name aliases are not guessed. A variable can be selected explicitly if needed. All project files must have a 0.25-degree grid and the established `025` filename code. Both the filename and actual coordinate spacing are checked against this project requirement; neither is allowed to redefine it.

A matching NetCDF variable is selected by filename where possible. Multiple candidates are not silently reduced to the first. Regular rectilinear longitude/latitude/time dimensions are supported. Nonsingleton extra dimensions, unsupported grids or time encodings remain visible as blocking coverage gaps, not clean passes. The numerical scan reads all time slices one at a time with ncdf4 fill-value and packing decoding; quantiles are unweighted spatial summaries, not area-weighted climate means. This is still a potentially large I/O job for daily/hourly files.

## Variable-family review policies

`R/netcdf_families.R` supplies separate review requirements for `evap`, `other`, `precip`, `runoff`, `snow`, `soilmoisture` and `temperature`. Family and raw/processed stage are inferred from folder names when available. Here `raw` means already preprocessed/harmonised to common units and the 0.25-degree grid, not untouched downloaded data. `processed` generally means additional time/spatial subsets; an optional `family` selector is allowed. These hints do not override filename/content contradictions. Regional scale names do not impose global extent.

The family functions guide scientific LLM review; they are not a comprehensive deterministic validator for every environmental quantity:

- Temperature: unit/offset direction and Tmin/Tmax aggregation semantics.
- Precipitation: rate versus accumulation and correct duration/sum/mean.
- Evaporation: actual/potential quantity, rate/accumulation and source sign convention.
- Runoff: depth/rate/discharge and surface/subsurface/total quantity.
- Snow: depth, snow-water equivalent, snowfall flux or cover fraction; stocks versus fluxes.
- Soil moisture: volumetric fraction versus mass/area and layer/depth integration.
- Other: actual quantity identification, including radiation, humidity, pressure, heat fluxes, groundwater and LAI.

No universal plausible-value thresholds are invented. The LLM must independently assess physical plausibility and processing evidence. These policies need representative server-side pilots for each family before a large run.

## Temporal and spatial coverage policy

CFtime handles CF calendars, including Gregorian, no-leap and 360-day. Filename coverage is checked independently for hourly, daily, monthly and annual/yearly products. CF time bounds, where readable, supply interval midpoints for period labels. Missing or duplicate periods inside the named interval are flagged. Differences in end dates between separate frequency products are not compared.

Monthly/daily/hourly products may legitimately start or end partway through a year. A monthly file ending in August is valid if every declared month is present. Annual/yearly filename endpoints must indicate full calendar years; partial annual intervals are flagged. Annual time bounds are checked when present. An annual timestamp alone cannot prove every source month was included; processing provenance must establish the aggregation, and reference-source checks may still be necessary.

Longitude/latitude order, degree units, geographic ranges and resolution are checked. Latitude domain is descriptive: coverage limited to 60S–60N and inclusion/exclusion of Antarctica are both allowed. `land` and `global` imply a full longitude span; other scale labels are treated as regional domains without guessing region boundaries.

- `global`: requires finite data over land and ocean within its represented coordinate domain; missing cells are flagged.
- `land`: approximately two-thirds of grid cells should be missing. The initial broad screening interval is **50–85% missing**, adjustable via `land_missing_range`; outside this interval gives a review flag, not proof of a bad mask.

These are grid-cell fractions, not area-weighted land fractions. Missingness does not independently establish a correct land mask. An independent mask comparison is not performed automatically.

## Provenance and processing history

Unclear essential source/aggregation provenance is a review failure, even when numerical checks pass. For monthly Tmin, for example, distinguish mean daily minima from the lowest temperature of the month. The original source may already have the named monthly/daily/annual frequency; a local aggregation step is not mandatory. Final values must have the temporal interpretation and units represented by the filename. Missing a local aggregation command is not automatically an error when the source already has the required frequency. However, a missing or empty NetCDF `history` attribute is a mandatory deterministic provenance FAIL, even if source metadata or external notes exist. Those can clarify semantics but do not override the required history record. A metadata-only units edit does not prove the numeric values required conversion. Optional `provenance_notes` may supply actual documentation; never invent it.

Selected source attributes, cell_methods and redacted global history enter the approved model preview. `ncdump -k`, `ncdump -h` and `cdo -s ntime` are queried when available, with 120-second command timeouts. Full command output stays in the local diagnostic object. History documents recorded operations, not proof that those operations fully explain the current file. History is capped at 6,000 characters with truncation reported.

Common credential patterns, paths, identities and URLs in history/provenance metadata are redacted. Redaction is best-effort: always inspect the preview. The basename itself is intentionally sent because it encodes expectations. Do not use filenames containing secrets. Do not submit raw full headers, raw arrays or private paths. Tools missing/failing are NOT_CHECKED, not automatically a data failure.


## Five-group pilot interpretation

The optional grouped-review pilot tests a revised interpretation alongside the established single-verdict reviewer. It emits variable/metadata, grid/spatial coverage, time coverage, variable values and source/processing results separately. PASS covers performed checks, FAIL identifies demonstrated inconsistencies or unmet explicit requirements, REVIEW identifies a concrete concern needing verification, and NOT_CHECKED identifies unavailable essential checks. A deterministic FAIL blocks PASS within its own group; WARN becomes REVIEW rather than a whole-file failure. Required missing history remains a source/processing documentation FAIL. Optional attributes, unperformed independent mask comparisons and missing local aggregation commands for native-frequency source products do not by themselves establish a data error. Exact unresolved source/temporal definitions still require attention, with a specific question or verification rather than generic provenance objections in every group.

Known `pct`, `percent` and `%` unit spellings are equivalent. This is metadata normalization, never an inferred percentage/fraction numeric conversion. The pilot corrects this known cached mismatch in a copy; original scan evidence remains intact. The established reviewer and its retry format are unchanged; the pilot's per-group summary and completion index are separate formats.

## Interpretation and limitations

PASS means no issue identified within performed checks, not scientific certification. FAIL includes known data, naming or provenance flags. INCOMPLETE means important checks or model assessment did not finish. Deterministic FAIL/WARN cannot be overridden by model PASS. Unsupported essential checks block PASS.

Means are finite decoded cell-time arithmetic averages, not spatial-area or duration-weighted climate means. Grid first/last values are coordinate centres in storage order. Complete missing-period lists stay local; the prompt retains a bounded sample. `recorded-conversions.csv` extracts CDO addc/subc/mulc/divc from included redacted history; other tools/expressions require inspection. No match does not establish no conversion occurred.

Processing history is evidence of recorded operations, not proof of execution order, completeness or correctness. The sanitizer preserves complete numeric CDO argument ranges such as `seltimestep,1/20`. Earlier caches may contain damaged text from path redaction; use the header-only refresh runner before resubmission. Redaction is still best-effort, especially for other scientific expressions. Inspect the original header before accepting interpretations that depend on obscured syntax.
