# Review overview style: categorical colours, never a numerical gradient.
review_heatmap_style <- function() list(
  colours = c(PASS = "#B9DEC5", FAIL = "#E9A29B", REVIEW = "#F5D78D", NOT_CHECKED = "#E4E7EB"),
  foreground = "#202A33", background = "white", font = "sans",
  filename_pt = 8.5, status_pt = 8.5, heading_pt = 10, title_pt = 14,
  cell_width = 1.45, row_height = 0.34, margin = 0.3,
  headings = c(variable_and_metadata = "Variable /\nmetadata", grid_and_spatial_coverage = "Spatial\ncoverage",
    time_coverage = "Time\ncoverage", variable_values = "Variable\nvalues",
    source_and_processing = "Source /\nprocessing", mask_provenance = "Mask\nprovenance"))

# Match saved report folders by full data identity, never infer them from row numbers.
review_filename_labels <- function(paths, index = NULL) {
  filenames <- basename(gsub("\\\\", "/", paths))
  references <- rep("Report folder unavailable", length(paths))
  if (!is.null(index)) {
    if (!all(c("data_file_path", "report_path") %in% names(index)) ||
        anyNA(index$data_file_path) || anyDuplicated(index$data_file_path))
      stop("Heatmap requires unique data_file_path/report_path mappings in pilot_index.csv.")
    matched <- index$report_path[match(paths, index$data_file_path)]
    available <- !is.na(matched) & nzchar(trimws(matched))
    references[available] <- vapply(matched[available], function(path) {
      parts <- strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1]]
      paste(tail(parts[nzchar(parts) & parts != "."], 2), collapse = "/")
    }, character(1))
  }
  paste0(filenames, "\n[", references, "]")
}
review_heatmap_table <- function(short, index = NULL) {
  groups <- if ("mask_provenance" %in% names(short)) grouped_check_names() else legacy_grouped_check_names()
  statuses <- names(review_heatmap_style()$colours)
  if (!all(c("data_file_path", groups) %in% names(short)) || !nrow(short))
    stop("Provide a nonempty grouped summary_short.csv with all five legacy or six current categories.")
  if (!is.character(short$data_file_path) || anyNA(short$data_file_path) || anyDuplicated(short$data_file_path) ||
      any(!nzchar(short$data_file_path)) || anyNA(short[groups]) || any(!unlist(short[groups]) %in% statuses))
    stop("Heatmap input has missing/duplicate paths or unsupported statuses; inspect summary_short.csv.")
  data.frame(short[c("data_file_path", groups)], filename_label = review_filename_labels(short$data_file_path, index),
    stringsAsFactors = FALSE, check.names = FALSE)
}
validate_heatmap_pages <- function(rows_per_page) {
  if (!is.numeric(rows_per_page) || length(rows_per_page) != 1 || !is.finite(rows_per_page) ||
      rows_per_page != floor(rows_per_page) || rows_per_page < 1 || rows_per_page > 100)
    stop("heatmap_rows_per_page must be an integer from 1 to 100.")
  invisible(NULL)
}
review_heatmap_dimensions <- function(labels, rows, style, groups = grouped_check_names()) {
  grDevices::pdf(NULL, family = style$font)
  on.exit(grDevices::dev.off(), add = TRUE)
  grob <- grid::textGrob(labels, gp = grid::gpar(fontsize = style$filename_pt, fontfamily = style$font))
  filename_width <- max(4.5, grid::convertWidth(grid::grobWidth(grob), "inches", valueOnly = TRUE) * 1.15 + 0.2)
  list(filename_width = filename_width, width = 2 * style$margin + filename_width + 0.15 + length(groups) * style$cell_width,
    height = 2.3 + rows * style$row_height)
}
draw_review_heatmap <- function(table, page, pages, total, dimensions, style) {
  grid::grid.newpage()
  grid::grid.rect(gp = grid::gpar(fill = style$background, col = NA))
  text <- function(label, x, y, size, just = "centre", bold = FALSE) grid::grid.text(label,
    x = grid::unit(x, "inches"), y = grid::unit(y, "inches"), just = just,
    gp = grid::gpar(fontsize = size, fontfamily = style$font, fontface = if (bold) "bold" else "plain",
      col = style$foreground))
  groups <- intersect(grouped_check_names(), names(table))
  height <- dimensions$height
  left <- style$margin + dimensions$filename_width + 0.15
  top <- height - 1.75
  text("Data review overview", style$margin, height - 0.3, style$title_pt, just = "left", bold = TRUE)
  text(paste0(total, " files in saved summary", if (pages > 1) paste0(" | Page ", page, " of ", pages) else ""),
    style$margin, height - 0.59, style$filename_pt, just = "left")
  legend <- names(style$colours)
  legend_x <- left + 0.7 + (seq_along(legend) - 1) * 1.55
  grid::grid.rect(x = grid::unit(legend_x, "inches"), y = grid::unit(height - 0.98, "inches"),
    width = grid::unit(1.4, "inches"), height = grid::unit(0.25, "inches"),
    gp = grid::gpar(fill = unname(style$colours), col = NA))
  text(legend, legend_x, height - 0.98, style$status_pt)
  centres <- left + (seq_along(groups) - 0.5) * style$cell_width
  text(style$headings[groups], centres, top + 0.27, style$heading_pt, bold = TRUE)
  text("Dataset file / report", left - 0.12, top + 0.27, style$heading_pt, just = "right", bold = TRUE)
  y <- top - (seq_len(nrow(table)) - 0.5) * style$row_height
  text(table$filename_label, left - 0.12, y, style$filename_pt, just = "right")
  statuses <- unname(unlist(table[groups], use.names = FALSE))
  x_cells <- rep(centres, each = nrow(table)); y_cells <- rep(y, times = length(groups))
  grid::grid.rect(x = grid::unit(x_cells, "inches"), y = grid::unit(y_cells, "inches"),
    width = grid::unit(style$cell_width - 0.025, "inches"), height = grid::unit(style$row_height - 0.025, "inches"),
    gp = grid::gpar(fill = unname(style$colours[statuses]), col = NA))
  text(statuses, x_cells, y_cells, style$status_pt)
  text("REVIEW: investigate | NOT_CHECKED: assessment unavailable | Findings: summary.csv | Execution: pilot_index.csv",
    style$margin, 0.23, style$filename_pt, just = "left")
  invisible(NULL)
}

# Render only from the saved table; never open source data or call a model.
write_review_heatmap <- function(review_dir, rows_per_page = 50L, dpi = 300L) {
  validate_heatmap_pages(rows_per_page)
  if (!is.numeric(dpi) || length(dpi) != 1 || !is.finite(dpi) || dpi < 72 || dpi > 600)
    stop("Heatmap dpi must be between 72 and 600.")
  input <- file.path(review_dir, "summary_short.csv")
  if (!file.exists(input)) stop("Grouped summary_short.csv not found in review_dir.")
  index_file <- file.path(review_dir, "pilot_index.csv")
  index <- if (file.exists(index_file)) read.csv(index_file, stringsAsFactors = FALSE) else NULL
  table <- review_heatmap_table(read.csv(input, stringsAsFactors = FALSE), index)
  style <- review_heatmap_style()
  dimensions <- review_heatmap_dimensions(table$filename_label, min(nrow(table), rows_per_page), style,
    intersect(grouped_check_names(), names(table)))
  rows <- split(seq_len(nrow(table)), ceiling(seq_len(nrow(table)) / rows_per_page))
  pages <- length(rows)
  temporary <- tempfile(".heatmap-", tmpdir = review_dir); dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  pdf <- file.path(temporary, "summary_heatmap.pdf")
  grDevices::pdf(pdf, width = dimensions$width, height = dimensions$height,
    family = style$font, useDingbats = FALSE)
  device <- grDevices::dev.cur()
  tryCatch(for (page in seq_along(rows)) draw_review_heatmap(table[rows[[page]], ], page, pages,
    nrow(table), dimensions, style), finally = grDevices::dev.off(device))
  pngs <- if (pages == 1) "summary_heatmap.png" else sprintf("summary_heatmap_%03d.png", seq_len(pages))
  for (page in seq_along(rows)) {
    grDevices::png(file.path(temporary, pngs[page]), width = dimensions$width, height = dimensions$height,
      units = "in", res = dpi, type = if (capabilities("cairo")) "cairo" else getOption("bitmapType"), bg = style$background)
    device <- grDevices::dev.cur()
    tryCatch(draw_review_heatmap(table[rows[[page]], ], page, pages, nrow(table), dimensions, style),
      finally = grDevices::dev.off(device))
  }
  generated <- c("summary_heatmap.pdf", pngs)
  if (!all(file.copy(file.path(temporary, generated), file.path(review_dir, generated), overwrite = TRUE)))
    stop("Could not save all heatmap exports; CSV review results remain intact.")
  stale <- setdiff(list.files(review_dir, pattern = "^summary_heatmap(_[0-9]+)?[.]png$"), pngs)
  if (length(stale)) unlink(file.path(review_dir, stale))
  message("Heatmap saved: ", file.path(review_dir, "summary_heatmap.pdf"), " and ", pages, " PNG page(s).")
  invisible(file.path(review_dir, generated))
}
