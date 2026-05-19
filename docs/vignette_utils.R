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
#'
#' In strict mode (set VIGNETTE_STRICT=true env var), fails with error instead
#' of returning NULL. Use strict mode in CI/production renders to catch missing
#' targets early.
#'
#' Accepted values for VIGNETTE_STRICT use R's as.logical() semantics:
#'   Accepts the logical literals "TRUE"/"T" and "FALSE"/"F" (case-insensitive,
#'   so "true", "True", "t", "false", "False", "f" all parse). Any other string
#'   (including "1", "0", "yes", "no") yields NA, which isTRUE() treats as FALSE.
#'   Use VIGNETTE_STRICT=true to enable strict mode; anything else disables it.
#'
#' @param name Target name to read
#' @param strict If TRUE, stop() on missing target. Default: checks VIGNETTE_STRICT env var.
safe_tar_read <- function(name,
                          strict = isTRUE(as.logical(Sys.getenv("VIGNETTE_STRICT", "false")))) {
  result <- tryCatch(

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

  if (is.null(result) && strict) {
    stop("VIGNETTE_STRICT: Target '", name, "' not found. Run tar_make() first.",
         call. = FALSE)
  }

  result
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

  # Identify numeric columns (after formatting they may be character, check original df)
  numeric_cols <- which(sapply(df, function(x) is.numeric(x) ||
                                   grepl("^[0-9.%$,-]+$", as.character(x[1]))))

  DT::datatable(
    df,
    caption = htmltools::tags$caption(
      style = "caption-side: top; text-align: left; font-weight: bold; color: #888;",
      caption_text
    ),
    rownames = FALSE,
    filter = "top",
    options = list(
      pageLength = 15,
      scrollX = TRUE,
      autoWidth = FALSE,
      dom = "frtip",
      search = list(regex = TRUE, caseInsensitive = TRUE),
      columnDefs = list(
        list(className = 'dt-right', targets = numeric_cols - 1)  # DT uses 0-based indexing
      ),
      initComplete = DT::JS(
        "function(settings, json) {",
        "  var isDark = document.documentElement.getAttribute('data-bs-theme') === 'dark'",
        "    || document.body.classList.contains('dark-mode');",
        "  if (isDark) {",
        "    $(this.api().table().container()).css({'color': '#ddd', 'background-color': '#1a1a1a'});",
        "    $(this.api().table().header()).css({'color': '#ddd', 'background-color': '#222'});",
        "    $('input', this.api().table().container()).css({'color': '#ddd', 'background-color': '#333', 'border-color': '#555'});",
        "  }",
        "}"
      )
    )
  )
}

#' DT table transposed: few rows + many columns → columns become rows
#' @param df Data frame with few rows (<= 5) and many columns
#' @param caption_text Caption string
hd_dt_wide <- function(df, caption_text) {
  if (is.null(df) || nrow(df) == 0) return(invisible(NULL))

  # Transpose: column names become first column, row values become columns
  row_labels <- if ("period" %in% names(df)) df$period else paste0("Row ", seq_len(nrow(df)))
  t_df <- data.frame(
    Metric = setdiff(names(df), "period"),
    stringsAsFactors = FALSE
  )
  for (i in seq_len(nrow(df))) {
    vals <- vapply(t_df$Metric, function(col) {
      v <- df[[col]][i]
      if (is.numeric(v)) format(v, digits = 3) else as.character(v)
    }, character(1))
    t_df[[row_labels[i]]] <- vals
  }

  hd_dt(t_df, caption_text)
}

#' Emit build-info footer with linked version, SHA, R version
#' @param pkg_name Package name (default: "historicaldata")
build_info <- function(pkg_name = "historicaldata") {
  gh_url <- tryCatch({
    remote <- system("git remote get-url origin 2>/dev/null", intern = TRUE)
    sub("\\.git$", "", sub("^git@github\\.com:", "https://github.com/", remote))
  }, error = function(e) NULL)

  git_sha_short <- tryCatch(
    system("git rev-parse --short HEAD 2>/dev/null", intern = TRUE),
    error = function(e) "N/A"
  )
  git_sha_short <- if (length(git_sha_short) == 0 || git_sha_short == "") "N/A" else git_sha_short
  git_sha_full <- tryCatch(
    system("git rev-parse HEAD 2>/dev/null", intern = TRUE),
    error = function(e) git_sha_short
  )

  pkg_ver <- tryCatch(as.character(packageVersion(pkg_name)), error = function(e) "dev")
  r_ver <- as.character(getRversion())
  build_time <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  ver_link <- if (!is.null(gh_url)) {
    sprintf("[%s](%s/releases/tag/v%s)", pkg_ver, gh_url, pkg_ver)
  } else pkg_ver

  sha_link <- if (!is.null(gh_url) && git_sha_short != "N/A") {
    sprintf("[`%s`](%s/commit/%s)", git_sha_short, gh_url, git_sha_full)
  } else sprintf("`%s`", git_sha_short)

  r_link <- sprintf("[%s](https://cran.r-project.org/doc/manuals/r-release/NEWS.html)", r_ver)

  sprintf(
    "**%s** %s | **Git** %s | **R** %s | **Built** %s",
    pkg_name, ver_link, sha_link, r_link, build_time
  )
}
