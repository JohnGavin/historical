# Vignette utilities for examples.qmd
#
# Provides show_code() and hd_dt() helpers.
# Source this in the setup chunk.

#' Display code from a code_vig_* target as a collapsible block
#' @param target_name The vig_* target name (code_ prefix added automatically)
show_code <- function(target_name) {
  code_target <- paste0("code_", target_name)
  code <- tryCatch(
    targets::tar_read_raw(code_target),
    error = function(e) {
      # Try both locations (rendered from docs/ or project root)
      rds_dirs <- c("../inst/extdata/vignettes", "inst/extdata/vignettes")
      for (d in rds_dirs) {
        rds <- file.path(d, paste0(code_target, ".rds"))
        if (file.exists(rds)) return(readRDS(rds))
      }
      "# Code not available"
    }
  )
  # Trim leading/trailing whitespace
  code <- trimws(code)
  knitr::asis_output(paste0(
    '\n<details><summary>Show code</summary>\n\n```r\n',
    code,
    '\n```\n\n</details>\n'
  ))
}

#' Read a vig_* target with RDS fallback
safe_tar_read <- function(name) {
  tryCatch(
    targets::tar_read_raw(name),
    error = function(e) {
      rds_dirs <- c("../inst/extdata/vignettes", "inst/extdata/vignettes")
      for (d in rds_dirs) {
        rds <- file.path(d, paste0(name, ".rds"))
        if (file.exists(rds)) return(readRDS(rds))
      }
      NULL
    }
  )
}

#' DT table with caption, sortable, compact
hd_dt <- function(df, caption_text) {
  if (is.null(df)) return(invisible(NULL))
  DT::datatable(
    df,
    caption = htmltools::tags$caption(
      style = "caption-side: top; text-align: left; font-weight: bold; color: #ddd;",
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
