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

#' Format large numbers as human-readable (1.2T, 345M, 12K)
human_number <- function(x) {
  ifelse(is.na(x), "",
    ifelse(abs(x) >= 1e12, paste0(round(x / 1e12, 1), "T"),
    ifelse(abs(x) >= 1e9, paste0(round(x / 1e9, 1), "B"),
    ifelse(abs(x) >= 1e6, paste0(round(x / 1e6, 1), "M"),
    ifelse(abs(x) >= 1e3, paste0(round(x / 1e3, 1), "K"),
    as.character(round(x, 1)))))))
}

#' Format dates: strip 00:00:00 timestamps
clean_dates <- function(x) {
  if (inherits(x, c("POSIXct", "POSIXlt"))) return(as.Date(x))
  if (is.character(x)) return(sub(" 00:00:00$", "", x))
  x
}

#' DT table with caption, sortable, human-readable formatting
hd_dt <- function(df, caption_text) {
  if (is.null(df)) return(invisible(NULL))

  # Format large numbers
  for (col in names(df)) {
    if (is.numeric(df[[col]]) && col %in% c("market_cap", "volume_avg", "total_obs",
                                              "Obs", "Days", "Trading Days", "n")) {
      df[[col]] <- human_number(df[[col]])
    }
    # Format percentages
    if (is.numeric(df[[col]]) && col %in% c("yield_pct", "missing_pct", "expense_ratio")) {
      df[[col]] <- ifelse(is.na(df[[col]]), "", paste0(round(df[[col]] * 100, 2), "%"))
    }
    # Format beta/returns to 2dp
    if (is.numeric(df[[col]]) && col %in% c("beta_3yr", "ytd_return", "three_yr_return")) {
      df[[col]] <- ifelse(is.na(df[[col]]), "", round(df[[col]], 2))
    }
    # Clean dates
    df[[col]] <- clean_dates(df[[col]])
  }

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
      autoWidth = FALSE,
      dom = "frtip"
    )
  )
}
