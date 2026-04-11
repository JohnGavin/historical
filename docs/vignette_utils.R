# Vignette utilities: safe_tar_read with RDS fallback for CI
#
# Source this in every vignette setup chunk.

safe_tar_read <- function(name) {
  # Try targets store first
  tryCatch(
    targets::tar_read_raw(name),
    error = function(e) {
      # Fallback to pre-exported RDS
      rds_path <- file.path(here::here("inst/extdata/vignettes"), paste0(name, ".rds"))
      if (file.exists(rds_path)) {
        readRDS(rds_path)
      } else {
        cli::cli_warn("Target {name} not available (no _targets/ store or RDS fallback).")
        NULL
      }
    }
  )
}

# DT helper: sortable table with caption
hd_dt <- function(df, caption_text) {
  if (is.null(df)) return(invisible(NULL))
  DT::datatable(
    df,
    caption = htmltools::tags$caption(
      style = "caption-side: top; font-size: 1.05em; font-weight: bold; color: #ddd;",
      caption_text
    ),
    rownames = FALSE,
    filter = "top",
    options = list(
      pageLength = 15,
      scrollX = TRUE,
      autoWidth = TRUE,
      dom = "frtip"
    )
  )
}
