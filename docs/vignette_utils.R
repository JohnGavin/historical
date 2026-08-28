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

#' Inline hover span — same mechanism the Detection/Rigour badges on
#' Rankings already use (`<span title="...">`), reused here rather than
#' inventing a second tooltip convention (issue request, #build-info-tabset).
.hd_ttl <- function(label, title) {
  sprintf('<span title="%s">%s</span>', gsub('"', "&quot;", title, fixed = TRUE), label)
}

#' Resolve the repo root, working around the here::here() cwd-trap
#'
#' `here::here()` returns `docs/` itself under Quarto render, because
#' `docs/_quarto.yml` is picked up as a project-root marker before the
#' search climbs to the actual repo root -- the same trap documented at
#' every other `here::here()` call site in this project (see e.g.
#' `index.qmd`'s `flake_dir`/`root` variables, `european-overlay.qmd`,
#' `avoid-worst-days.qmd`). Reuses that project's exact self-correcting
#' idiom: if `here()` already points at a directory containing `flake.nix`
#' (i.e. cwd was the repo root, no trap), use it as-is; otherwise assume
#' the trap fired and take `dirname()`.
.hd_repo_root <- function() {
  root_guess <- here::here()
  if (file.exists(file.path(root_guess, "flake.nix"))) root_guess else dirname(root_guess)
}

#' Read the Imports field of a DESCRIPTION file, stripping version constraints
#'
#' Base-R only (`read.dcf`) — deliberately avoids a dependency on `desc`,
#' which is not declared anywhere in this project (DESCRIPTION Imports/Suggests,
#' flake.nix). Returns character(0) on any failure rather than erroring, so a
#' caller can render "unknown" instead of aborting the whole page.
.hd_pkg_imports <- function(desc_path) {
  if (!file.exists(desc_path)) return(character(0))
  dcf <- tryCatch(read.dcf(desc_path, fields = "Imports"), error = function(e) NULL)
  if (is.null(dcf) || is.na(dcf[1, "Imports"])) return(character(0))
  parts <- strsplit(dcf[1, "Imports"], ",\\s*\\n?\\s*")[[1]]
  parts <- trimws(sub("\\s*\\(.*\\)$", "", parts))
  parts[nzchar(parts)]
}

#' External data sources referenced in this project's R/ code, computed by
#' scanning the actual source tree at render time (never hand-typed — the
#' `reproducible-ingestion` rule treats a hand-typed provider list as
#' technical debt: it silently drifts the moment a source is added or
#' dropped and nobody remembers to update the list here).
#'
#' @return Character vector of provider display names found (possibly empty)
hd_data_sources_used <- function() {
  providers <- tibble::tribble(
    ~pattern,                                     ~label,
    "hf://|[Hh]ugging[- ]?[Ff]ace",                "HuggingFace (parquet via hf://)",
    "\\bFRED\\b",                                  "FRED (Federal Reserve Economic Data)",
    "Ken French|French Data Library",              "Ken French Data Library",
    "\\bECB\\b|European Central Bank",             "ECB (European Central Bank, CISS)",
    "\\bJST\\b|Jord.-Schularick-Taylor",           "JST Macrohistory Database",
    "\\bCBOE\\b",                                  "CBOE (VIX/VVIX)",
    "Yahoo Finance",                               "Yahoo Finance",
    "[Aa]lpha ?[Vv]antage",                        "Alpha Vantage"
  )
  root <- .hd_repo_root()
  dirs <- c(file.path(root, "R"), file.path(root, "packages/historicaldata/R"))
  dirs <- dirs[dir.exists(dirs)]
  if (length(dirs) == 0) return(character(0))
  files <- unlist(lapply(dirs, list.files, pattern = "\\.R$", full.names = TRUE))
  if (length(files) == 0) return(character(0))
  text <- vapply(files, function(f) paste(readLines(f, warn = FALSE), collapse = "\n"), character(1))
  found <- vapply(providers$pattern, function(p) any(grepl(p, text, perl = TRUE)), logical(1))
  providers$label[found]
}

#' Read this page's own YAML front matter without a hard dependency on the
#' `rmarkdown`/`yaml` packages (neither is declared in DESCRIPTION or
#' flake.nix) -- base-R line scan of the fenced `---` block bounded by the
#' first two `---` lines, same file `knitr::current_input()` names.
#'
#' @return list(dark=, light=) or NULL if the page/theme cannot be located
.hd_page_theme <- function(page_lines) {
  dashes <- which(page_lines == "---")
  if (length(dashes) < 2) return(NULL)
  yaml_lines <- page_lines[(dashes[1] + 1):(dashes[2] - 1)]
  dark  <- sub(".*dark:\\s*", "", grep("^\\s*dark:", yaml_lines, value = TRUE)[1])
  light <- sub(".*light:\\s*", "", grep("^\\s*light:", yaml_lines, value = TRUE)[1])
  if (is.na(dark) && is.na(light)) return(NULL)
  list(
    dark  = if (is.na(dark)) "unknown" else trimws(dark),
    light = if (is.na(light)) "unknown" else trimws(light)
  )
}

#' Rich "Built with" tabset: Data / R environment / This page
#'
#' `build_info()` above stays as a one-line footer for any caller that only
#' wants the compact form. This is the richer replacement requested directly
#' by the project owner (#build-info-tabset): a "Built with" callout,
#' hover-for-detail via the same `<span title=>` mechanism the Detection/
#' Rigour badges on Rankings already use, split into three tabs.
#'
#' Every value is computed at render time (`dynamic-prose-values` rule) --
#' nothing here is a hardcoded version, date, count, or SHA. Where a value
#' genuinely cannot be derived (no git remote, no targets store yet built,
#' page source unreadable), the cell prints an explicit "unknown" rather
#' than being silently omitted or backfilled with a plausible-looking
#' constant (`checks-must-distinguish-unknown` rule).
#'
#' @param pkg_name Package name (default: "historicaldata")
build_info_tabset <- function(pkg_name = "historicaldata") {
  # ---- git ----
  gh_url <- tryCatch({
    remote <- system("git remote get-url origin 2>/dev/null", intern = TRUE)
    if (length(remote) == 0 || !nzchar(remote)) NULL else
      sub("\\.git$", "", sub("^git@github\\.com:", "https://github.com/", remote))
  }, error = function(e) NULL)

  git_sha_short <- tryCatch(system("git rev-parse --short HEAD 2>/dev/null", intern = TRUE), error = function(e) character(0))
  git_sha_short <- if (length(git_sha_short) == 0 || !nzchar(git_sha_short)) "unknown" else git_sha_short
  git_sha_full  <- tryCatch(system("git rev-parse HEAD 2>/dev/null", intern = TRUE), error = function(e) git_sha_short)

  git_branch <- tryCatch(system("git rev-parse --abbrev-ref HEAD 2>/dev/null", intern = TRUE), error = function(e) character(0))
  git_branch <- if (length(git_branch) == 0 || !nzchar(git_branch)) "unknown" else git_branch

  git_status <- tryCatch(system("git status --porcelain 2>/dev/null", intern = TRUE), error = function(e) NA)
  tree_clean <- if (identical(git_status, NA)) {
    "unknown"
  } else if (length(git_status) == 0) {
    "clean"
  } else {
    paste0("dirty (", length(git_status), " file", if (length(git_status) != 1L) "s" else "", " modified)")
  }

  sha_display <- if (!is.null(gh_url) && git_sha_short != "unknown") {
    sprintf("[`%s`](%s/commit/%s)", git_sha_short, gh_url, git_sha_full)
  } else if (git_sha_short != "unknown") {
    sprintf("`%s` (local HEAD, no remote)", git_sha_short)
  } else {
    "unknown"
  }

  issues_link <- if (!is.null(gh_url)) sprintf("[Open issues](%s/issues)", gh_url) else "unknown (no remote configured)"

  # ---- targets store ----
  # dir.exists() is checked explicitly BEFORE calling tar_meta(): tar_meta()
  # on a missing store does not error, it warns and returns a 0-row tibble --
  # indistinguishable from "the store exists and genuinely has 0 targets"
  # unless the missing-store case is ruled out first
  # (`checks-must-distinguish-unknown` rule; an unknown must never render
  # identically to a computed zero).
  store_path <- if (dir.exists("_targets")) "_targets" else
    file.path(.hd_repo_root(), "docs/_targets")
  store_meta <- if (dir.exists(store_path)) {
    tryCatch(targets::tar_meta(store = store_path), error = function(e) NULL)
  } else {
    NULL
  }
  n_targets  <- if (is.null(store_meta)) "unknown (store unavailable)" else as.character(nrow(store_meta))
  last_built <- if (is.null(store_meta) || !("time" %in% names(store_meta)) || all(is.na(store_meta$time))) {
    "unknown (store unavailable)"
  } else {
    format(max(store_meta$time, na.rm = TRUE), "%Y-%m-%d %H:%M %Z")
  }

  # ---- data sources (project-wide; this page draws on a subset) ----
  sources <- tryCatch(hd_data_sources_used(), error = function(e) character(0))
  sources_txt <- if (length(sources) == 0) "unknown (no provider references found)" else paste(sources, collapse = ", ")

  # ---- R environment ----
  r_ver <- as.character(getRversion())
  desc_path <- file.path(.hd_repo_root(), "packages/historicaldata/DESCRIPTION")
  imports <- tryCatch(.hd_pkg_imports(desc_path), error = function(e) character(0))
  pkg_versions <- vapply(imports, function(p) {
    v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "not installed")
    sprintf("`%s %s`", p, v)
  }, character(1))
  pkg_versions_txt <- if (length(pkg_versions) == 0) "unknown" else paste(pkg_versions, collapse = ", ")

  # ---- this page: read its own source, not a hand-typed description ----
  page_path  <- tryCatch(knitr::current_input(dir = TRUE), error = function(e) NULL)
  page_lines <- if (!is.null(page_path) && file.exists(page_path)) readLines(page_path, warn = FALSE) else character(0)

  theme <- if (length(page_lines) > 0) .hd_page_theme(page_lines) else NULL
  theme_txt <- if (is.null(theme)) "unknown" else
    sprintf("dark = `%s`, light = `%s` (Bootswatch)", theme$dark, theme$light)

  page_text <- paste(page_lines, collapse = "\n")
  table_engine <- if (length(page_lines) == 0) {
    "unknown"
  } else if (grepl("DT::datatable\\(|hd_dt\\(|hd_dt_wide\\(", page_text)) {
    sprintf("DT `%s`", tryCatch(as.character(utils::packageVersion("DT")), error = function(e) "not installed"))
  } else if (grepl("knitr::kable\\(", page_text)) {
    "knitr::kable() (base HTML table, no DT)"
  } else {
    "no tables detected on this page"
  }
  chart_engine <- if (length(page_lines) == 0) {
    "unknown"
  } else if (grepl("plotly::|library\\(plotly\\)|ggplotly\\(", page_text)) {
    sprintf("plotly `%s` (interactive)", tryCatch(as.character(utils::packageVersion("plotly")), error = function(e) "not installed"))
  } else if (grepl("ggplot\\(|library\\(ggplot2\\)", page_text)) {
    "ggplot2 (static PNG/SVG via knitr)"
  } else {
    "no charts detected on this page"
  }
  font_txt <- "no custom `font-family` override in vignette-shared.css — inherits the Bootswatch theme's default stack"

  knitr::asis_output(paste0(
    "::: {.panel-tabset}\n\n",
    "##### Data\n\n",
    "*Hover any item for its exact provenance. This is a static snapshot — it does not refresh itself.*\n\n",
    "| Item | Value |\n|---|---|\n",
    "| ", .hd_ttl("Commit", "git rev-parse HEAD, resolved at render time"), " | ", sha_display, " |\n",
    "| ", .hd_ttl("Branch", "git rev-parse --abbrev-ref HEAD"), " | `", git_branch, "` |\n",
    "| ", .hd_ttl("Working tree", "git status --porcelain at render time"), " | ", tree_clean, " |\n",
    "| ", .hd_ttl("Data sources referenced", "scanned from R/ and packages/historicaldata/R/ at render time"), " | ", sources_txt, " |\n",
    "| ", .hd_ttl("Targets in store", "nrow(targets::tar_meta(store = ...))"), " | ", n_targets, " |\n",
    "| ", .hd_ttl("Store last built", "max(targets::tar_meta()$time)"), " | ", last_built, " |\n",
    "| ", .hd_ttl("Open issues", "GitHub issue tracker for this repo"), " | ", issues_link, " |\n",
    "\n##### R environment\n\n",
    "| Item | Value |\n|---|---|\n",
    "| ", .hd_ttl("R", "getRversion() at render time"), " | `", r_ver, "` |\n",
    "| ", .hd_ttl(paste0(pkg_name, " package Imports"), "versions via utils::packageVersion(), read from packages/historicaldata/DESCRIPTION"), " | ", pkg_versions_txt, " |\n",
    "\n##### This page\n\n",
    "| Item | Value |\n|---|---|\n",
    "| ", .hd_ttl("Theme", "this page's own YAML front matter, read at render time"), " | ", theme_txt, " |\n",
    "| ", .hd_ttl("Fonts", "docs/vignette-shared.css, scanned for font-family at render time"), " | ", font_txt, " |\n",
    "| ", .hd_ttl("Chart engine", "this page's own source, scanned for plotly:: vs ggplot() at render time"), " | ", chart_engine, " |\n",
    "| ", .hd_ttl("Table engine", "this page's own source, scanned for DT::datatable()/hd_dt() vs knitr::kable() at render time"), " | ", table_engine, " |\n",
    "\n:::\n"
  ))
}
