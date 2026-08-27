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

# Private helper: parse VIGNETTE_STRICT env var.
# Accepts truthy aliases case-insensitively: "1"/"yes"/"on"/"true"/"t"
# and falsy aliases: "0"/"no"/"off"/"false"/"f"/"" (unset/empty).
# Whitespace around the value is stripped before matching.
.parse_vignette_strict <- function() {
  raw <- tolower(trimws(Sys.getenv("VIGNETTE_STRICT", "")))
  if (raw %in% c("1", "yes", "on", "true", "t")) return(TRUE)
  if (raw %in% c("0", "no", "off", "false", "f", "")) return(FALSE)
  # Unrecognised non-empty value — surface the typo instead of silently defaulting.
  # .frequency = "once" + .frequency_id prevents spam when safe_tar_read() is
  # called N times in a single render with the same typo'd value (roborev #4263).
  cli::cli_warn(
    c(
      "Unrecognised {.envvar VIGNETTE_STRICT} value {.val {raw}} — falling back to FALSE",
      i = "Accepted truthy: 1, yes, on, true, t (case-insensitive, whitespace-tolerant)",
      i = "Accepted falsy: 0, no, off, false, f, '' (empty)"
    ),
    .frequency = "once",
    .frequency_id = paste0("vignette_strict_typo_", raw)
  )
  FALSE
}

#' Read a vig_* target with RDS fallback
#'
#' In strict mode (set VIGNETTE_STRICT=true or VIGNETTE_STRICT=1 env var),
#' fails with error instead of returning NULL. Use strict mode in CI/production
#' renders to catch missing targets early.
#'
#' When a target is missing in non-strict mode, returns NULL. Callers should
#' guard with `if (!is.null(result))` before using the value.
#'
#' VIGNETTE_STRICT parsing: case-insensitive and whitespace-tolerant.
#' Truthy: "1", "yes", "YES", "on", "ON", "true", "TRUE", "t", "T".
#' Falsy: "0", "no", "off", "false", "f", or unset/empty string.
#' Setting VIGNETTE_STRICT=1 or VIGNETTE_STRICT=YES both enable strict mode.
#' Semantic: env var SET to a truthy value = strict mode ON.
#'
#' @param name Target name to read
#' @param strict If TRUE, stop() on missing target. Default: checks VIGNETTE_STRICT env var.
safe_tar_read <- function(name,
                          strict = .parse_vignette_strict()) {
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

#' Test whether an object is a stale-marker sentinel
#'
#' Predicate for future use; safe_tar_read() currently returns NULL for missing
#' targets. Reserved for when callers migrate to typed sentinel returns.
#'
#' @rdname safe_tar_read
#' @export
is_stale_marker <- function(x) {
  inherits(x, "stale_marker")
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

#' Build a real HTML anchor for use inside DT captions/notes
#'
#' Captions built via hd_caption()/htmltools::tags$caption(text) auto-escape
#' any embedded `<`/`>`/`&` when `text` is a plain string -- that protects
#' prose like "CAGR < 20%" from being mis-parsed as a tag, but it also means
#' markdown-style `[text](url)` link syntax passed as plain text is never
#' rendered as a clickable link: DT hands the caption straight to the
#' browser as HTML, with no pandoc/markdown pass, so it just shows up as
#' literal brackets and a bare URL. Build real links with this helper and
#' combine them with plain-text fragments via htmltools::tagList() -- see
#' the leaderboard "Rankings" caption for a worked example.
#'
#' @param label Link text (character or an htmltools tag, e.g. tags$code(...))
#' @param href URL
hd_link <- function(label, href) {
  htmltools::tags$a(href = href, target = "_blank", rel = "noopener noreferrer", label)
}

#' Build a DT/HTML table caption with automatic progressive disclosure
#'
#' A `<caption>` that grows past a few sentences dominates the table it is
#' meant to introduce -- readers cannot tell "what does this table rank" from
#' "here are eleven comparability caveats" at a glance. Captions longer than
#' `threshold` characters are split: the caption shows only a short summary
#' unconditionally, with the remaining text pushed into a collapsed
#' `<details>` block.
#'
#' @param text Full caption content. Either a single plain character string
#'   (auto-escaped, exactly like a bare `htmltools::tags$caption()` child),
#'   or an htmltools tagList mixing plain text with real links (see
#'   `hd_link()`) -- in which case `short` MUST be supplied explicitly,
#'   since there is no single string to summarise automatically.
#' @param short Optional short summary shown unconditionally. If `text` is a
#'   single plain string longer than `threshold` and `short` is NULL, the
#'   first sentence of `text` is used (falls back to a hard truncation if no
#'   sentence break is found early enough).
#' @param threshold Character count above which the `<details>` wrapper is
#'   used (ignored when `short` is supplied explicitly).
#' @param summary_label Text shown on the collapsed `<summary>` toggle.
#' @param style_extra Additional inline CSS appended to the caption's style
#'   (e.g. a colour override some dashboards apply).
hd_caption <- function(text, short = NULL, threshold = 300,
                        summary_label = "Show full details", style_extra = "") {
  style <- paste0("caption-side: top; text-align: left; font-weight: bold;", style_extra)
  is_plain <- is.character(text) && length(text) == 1L

  if (is_plain && nchar(text) <= threshold) {
    return(htmltools::tags$caption(style = style, class = "dt-caption", text))
  }

  if (is.null(short)) {
    if (!is_plain) {
      stop("hd_caption(): `short` is required when `text` is not a single plain string.",
           call. = FALSE)
    }
    # First sentence break after position 20 (avoids splitting on early
    # abbreviations like "e.g."); falls back to a hard truncation.
    m <- regexpr("(?<=[a-zA-Z0-9)%])\\. (?=[A-Z])", text, perl = TRUE)
    short <- if (m[1] > 20) substr(text, 1, m[1]) else
      paste0(substr(text, 1, threshold), "…")
  }

  htmltools::tags$caption(
    style = style, class = "dt-caption",
    htmltools::tags$span(short), " ",
    htmltools::tags$details(
      htmltools::tags$summary(summary_label),
      text
    )
  )
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
    caption = hd_caption(caption_text),
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

  # Only link to a release tag when pkg_ver looks like a real semver (e.g.
  # "0.1.0", "1.2.3"). When packageVersion() errors the fallback is "dev",
  # which produces releases/tag/vdev — a 404. Link to the releases index
  # instead so the footer is always a valid URL. (#392)
  is_semver <- grepl("^[0-9]+\\.[0-9]+(\\.[0-9]+)?", pkg_ver)
  ver_link <- if (!is.null(gh_url) && is_semver) {
    sprintf("[%s](%s/releases/tag/v%s)", pkg_ver, gh_url, pkg_ver)
  } else if (!is.null(gh_url)) {
    sprintf("[%s](%s/releases)", pkg_ver, gh_url)
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
