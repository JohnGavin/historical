# QA gate targets — look-ahead bias prevention
#
# Mandatory follow-up from PR #181 (2026-05-16) per look-ahead-bias-prevention rule.
# Every tar_make() runs these checks. Any match aborts the pipeline with a file:line
# report so the developer knows exactly where to fix.
#
# Opt-out: append `# look-ahead-safe` to any line that intentionally uses one of
# the forbidden patterns (e.g. lead(ym) to build a join key that is NOT itself
# a return or price series). Document why the pattern is safe in that comment.

# ---- helpers ----

#' Scan files for lead(ym) used for month-key construction (S1)
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_lead_ym <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("\\blead\\s*\\(\\s*ym\\b", lines)
    # Exclude comment lines (#' docstrings and # comments) — they describe
    # the forbidden pattern but don't execute it.
    m <- m[!grepl("^\\s*#", lines[m])]
    # Exclude lines that carry the explicit opt-out marker
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Scan files for slider forward-window without a lead-shifted input (S2)
#'
#' Pattern: slide_dbl(...) with .before = 0 on a variable that is NOT already
#' lead-shifted (i.e. the variable name does NOT end in _lead).
#'
#' Opt-out: append `# look-ahead-safe` to the slide_dbl() call line when the
#' input is genuinely forward-looking (e.g. a forecast series).
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_unleaded_slider <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("slide_dbl\\s*\\(", lines)
    bad <- m[vapply(m, function(i) {
      # Look ahead up to 5 lines for the .before argument
      block <- paste(lines[i:min(length(lines), i + 5L)], collapse = " ")
      has_before_zero <- grepl("\\.before\\s*=\\s*0\\b", block)
      input_is_lead   <- grepl("_lead\\b", block)
      has_opt_out     <- grepl("# look-ahead-safe", block, fixed = TRUE)
      has_before_zero && !input_is_lead && !has_opt_out
    }, logical(1L))]
    if (length(bad) == 0L) return(NULL)
    tibble::tibble(file = f, line = bad, code = lines[bad])
  })
  dplyr::bind_rows(results)
}

#' Scan files for zoo::na.approx (look-ahead via linear interpolation) (S3)
#'
#' zoo::na.approx uses tomorrow's value to fill today's NA — this is look-ahead
#' bias in any backtest feature. See na-propagation-rolling-stats rule.
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_na_approx <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("(zoo::)?na\\.approx\\s*\\(", lines)
    m <- m[!grepl("^\\s*#", lines[m])]                                     # skip comments
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]            # explicit opt-out
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Scan files for cumulative products/sums of forward_* variables (S4)
#'
#' Accumulating forward returns at time T into a series indexed by T uses
#' information not available at T. Opt-out: append `# look-ahead-safe`.
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_forward_cumulative <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("(cumprod|cumsum)\\s*\\([^)]*\\bforward_", lines)
    m <- m[!grepl("^\\s*#", lines[m])]                                     # skip comments
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Scan rendered HTML for diagram click URLs that lack a line anchor (S5)
#'
#' Only inspects Mermaid `click` directive lines — lines that match
#' `click <NODE> "URL" _blank`. This avoids false positives from ordinary
#' source-code links and caption links that appear elsewhere in rendered HTML.
#'
#' Any hit means a node in diagram_node_links.R has a missing or NA line.
#'
#' @param html_dir Character. Directory to scan for *.html files.
#' @param repo Character. GitHub owner/repo slug (used to scope the pattern).
#' @return A tibble with columns file, line, url. Zero rows = no hits.
check_no_bare_diagram_urls <- function(html_dir,
                                        repo = "JohnGavin/historical") {
  html_files <- list.files(html_dir, pattern = "\\.html$",
                            full.names = TRUE, recursive = TRUE)
  # Pattern: a Mermaid click directive whose URL lacks a #L<n> anchor.
  # Must start with (optional whitespace +) "click " so we only match
  # diagram nodes, not prose links or caption anchors.
  pat <- sprintf(
    "^\\s*click\\s+\\S+\\s+\"(https://github\\.com/%s/blob/[^\"]+\\.R)\"",
    gsub("/", "\\\\/", repo)
  )
  results <- purrr::map(html_files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m     <- grep(pat, lines, perl = TRUE)
    if (length(m) == 0L) return(NULL)
    # Extract just the URL from the first capture group
    urls <- regmatches(lines[m],
                       regexpr(
                         sprintf(
                           "https://github\\.com/%s/blob/[^\"]+\\.R",
                           gsub("/", "\\\\/", repo)
                         ),
                         lines[m], perl = TRUE
                       ))
    # Keep only URLs that lack the #L<n> anchor
    no_anchor <- !grepl("#L[0-9]+$", urls, perl = TRUE)
    if (!any(no_anchor)) return(NULL)
    tibble::tibble(
      file = f,
      line = m[no_anchor],
      url  = urls[no_anchor]
    )
  })
  dplyr::bind_rows(results)
}

#' Verify that every #L<n> anchor is within the target file's line count (S6)
#'
#' Reads each R file referenced by a `#L<n>` URL and checks that `<n>` does
#' not exceed the file's actual line count.
#'
#' @param html_dir Character. Directory to scan for *.html files.
#' @param repo_root Character. Absolute path to the repository root.
#' @param repo Character. GitHub owner/repo slug (used to scope the pattern).
#' @return A tibble with columns file, line, url, anchor_line, max_line. Zero rows = no violations.
check_anchor_in_range <- function(html_dir,
                                   repo_root,
                                   repo = "JohnGavin/historical") {
  html_files <- list.files(html_dir, pattern = "\\.html$",
                            full.names = TRUE, recursive = TRUE)
  # Pattern: a github.com blob URL for a .R file with a #L<n> anchor
  pat <- sprintf(
    "https://github\\.com/%s/blob/[^\"' ]+\\.R#L([0-9]+)",
    gsub("/", "\\\\/", repo)
  )
  results <- purrr::map(html_files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m     <- grep(pat, lines, perl = TRUE)
    if (length(m) == 0L) return(NULL)
    url_matches <- regmatches(lines[m], gregexpr(pat, lines[m], perl = TRUE))
    purrr::map2_dfr(m, url_matches, function(ln, urls) {
      purrr::map_dfr(urls, function(url) {
        # Extract relative file path from URL (everything after /blob/<ref>/)
        rel_path   <- sub(sprintf("https://github\\.com/%s/blob/[^/]+/", repo), "", url)
        rel_path   <- sub("#L[0-9]+$", "", rel_path)
        anchor_n   <- as.integer(sub(".*#L", "", url))
        abs_path   <- file.path(repo_root, rel_path)
        if (!file.exists(abs_path)) {
          # Missing file is itself a violation — stale or renamed source link
          return(tibble::tibble(file = f, line = ln, url = url,
                                anchor_line = anchor_n, max_line = NA_integer_))
        }
        max_ln     <- length(readLines(abs_path, warn = FALSE))
        if (anchor_n > max_ln) {
          tibble::tibble(file = f, line = ln, url = url,
                         anchor_line = anchor_n, max_line = max_ln)
        } else NULL
      })
    })
  })
  dplyr::bind_rows(results)
}

#' Check that every strategy in strategy_names appears in the leaderboard (S7)
#'
#' Exported as a standalone helper so unit tests can exercise the logic without
#' running `tar_make()`.  The `qa_leaderboard_coverage` target calls this
#' function directly.
#'
#' Also asserts that the `ssr` and `top5pct_share` columns are present in the
#' leaderboard tibble and that at least one row has a non-NA value for each
#' (i.e. the stability metrics were computed for at least one strategy).
#' Added in #400 (PR 4/6).
#'
#' @param strategy_names Tibble with at least `short_name` and `code_name`
#'   columns (the output of the `strategy_names` targets pipeline target).
#' @param leaderboard Tibble with at least a `strategy` column (the output of
#'   the `leaderboard` targets pipeline target).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_coverage <- function(strategy_names, leaderboard) {
  expected <- strategy_names$short_name
  observed <- unique(leaderboard$strategy)
  missing  <- setdiff(expected, observed)

  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard missing {length(missing)}/{length(expected)} strategy/strategies:",
      setNames(
        sprintf("  %s (code_name: %s)",
                missing,
                strategy_names$code_name[match(missing, strategy_names$short_name)]),
        rep("i", length(missing))
      ),
      "i" = "Add the corresponding add_meta() calls in R/plan_leaderboard.R."
    ))
  }

  # Assert SSR column present and populated (#400)
  if (!"ssr" %in% names(leaderboard)) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing required column {.field ssr}.",
      "i" = "Add the SSR computation block to R/plan_leaderboard.R (#400)."
    ))
  }
  if (all(is.na(leaderboard$ssr))) {
    cli::cli_abort(c(
      "x" = "Leaderboard column {.field ssr} is entirely NA — no stability metrics were computed.",
      "i" = "Check that portfolio return targets are available and have >= 38 months (#400)."
    ))
  }

  # Assert top5pct_share column present and populated (#400)
  if (!"top5pct_share" %in% names(leaderboard)) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing required column {.field top5pct_share}.",
      "i" = "Add the top5pct computation block to R/plan_leaderboard.R (#400)."
    ))
  }
  if (all(is.na(leaderboard$top5pct_share))) {
    cli::cli_abort(c(
      "x" = "Leaderboard column {.field top5pct_share} is entirely NA — no top-5% shares were computed.",
      "i" = "Check that portfolio return targets are available (#400)."
    ))
  }

  invisible(TRUE)
}


#' Assert every vignette has at least one inter-vignette link (S8)
#'
#' Scans all .qmd files in `vignettes_dir` (excluding index.qmd, which is the
#' homepage) for a `## Related vignettes` or `#### Related Vignettes` section.
#' Aborts with a message naming the missing files if any are found.
#'
#' @param vignettes_dir Character. Directory to scan for *.qmd files.
#' @return `TRUE` invisibly on success.
#' @noRd
check_vignette_cross_refs <- function(vignettes_dir = here::here("docs")) {
  qmd_files <- list.files(vignettes_dir, pattern = "\\.qmd$", full.names = TRUE)
  # Skip index.qmd — homepage navigation covers the entire site
  qmd_files <- qmd_files[basename(qmd_files) != "index.qmd"]
  missing <- character(0)
  for (f in qmd_files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    has_section <- grepl("## Related [Vv]ignettes", txt) ||
                   grepl("#### Related [Vv]ignettes", txt)
    if (!has_section) {
      missing <- c(missing, basename(f))
    }
  }
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = "Vignettes missing 'Related Vignettes' section ({length(missing)} file{?s}):",
      setNames(sprintf("  %s", missing), rep("i", length(missing))),
      "i" = "Add a '## Related vignettes' or '#### Related Vignettes' section to each."
    ))
  }
  invisible(TRUE)
}


#' Assert leaderboard cagr/vol/max_dd are within a plausible FRACTIONAL range (S9)
#'
#' Guards against the #637 defect class: a strategy's `.norm_*` helper in
#' R/plan_leaderboard.R forgetting to convert its source metrics target's
#' native PERCENT convention (x * 100) to the leaderboard's canonical
#' FRACTION convention. A strategy stored as percent shows up here as ~100x
#' its true value (e.g. cagr = 7.70 instead of 0.077), which these bounds
#' catch even though `sharpe` (scale-free) would look fine either way.
#'
#' Bounds are deliberately generous — they are a scale-error gate, not a
#' performance-plausibility gate:
#'   - `vol`: [0, 2] (0%-200% annualised volatility)
#'   - `max_dd`: [-1, 0] (a drawdown cannot exceed -100% of peak equity, and
#'     drawdown is never positive; mom_prepeak's bankruptcy floor is exactly
#'     -1.0, see packages/historicaldata/R/utils_mom_prepeak_metrics.R:73)
#'   - `cagr`: [-1, 3] (-100% to +300% annualised — wide enough for small-n
#'     sub-period rows and volatile overlay strategies, tight enough to catch
#'     a stray x100)
#'
#' @param leaderboard Tibble with at least `strategy`, `period`, `cagr`,
#'   `vol`, `max_dd` columns (the output of the `leaderboard` targets
#'   pipeline target).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_metric_ranges <- function(leaderboard) {
  required_cols <- c("strategy", "period", "cagr", "vol", "max_dd")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_metric_ranges() (S9) requires strategy, period, cagr, vol, max_dd."
    ))
  }

  bounds <- list(
    cagr   = c(-1, 3),
    vol    = c(0, 2),
    max_dd = c(-1, 0)
  )

  offenders <- purrr::map_dfr(names(bounds), function(col) {
    vals <- leaderboard[[col]]
    lo <- bounds[[col]][1]
    hi <- bounds[[col]][2]
    bad <- !is.na(vals) & (vals < lo | vals > hi)
    if (!any(bad)) return(NULL)
    tibble::tibble(
      strategy = leaderboard$strategy[bad],
      period   = leaderboard$period[bad],
      metric   = col,
      value    = vals[bad],
      lo       = lo,
      hi       = hi
    )
  })

  if (nrow(offenders) > 0L) {
    msgs <- purrr::pmap_chr(
      offenders[, c("strategy", "period", "metric", "value", "lo", "hi")],
      function(strategy, period, metric, value, lo, hi) {
        sprintf("  %s / %s -- %s = %s (expected [%s, %s])",
                strategy, period, metric,
                format(value, digits = 4), lo, hi)
      }
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard metric(s) out of plausible fractional range in ",
        "{nrow(offenders)} place(s) (likely a percent-vs-fraction unit bug, #637):"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = "Check the source metrics target's convention and convert in its .norm_* helper in R/plan_leaderboard.R."
    ))
  }

  invisible(TRUE)
}


#' Assert leaderboard period labels are canonical (S10)
#'
#' Guards against the #643 defect class: a strategy's source metrics target
#' uses a non-canonical `period` label (e.g. "Full" instead of "Full Period")
#' that silently drops the strategy from every `filter(period == "Full
#' Period")` consumer -- the docs/leaderboard.qmd headline ranking table
#' (filters on "Full Period" at two places) and the correlation/redundancy
#' join in R/plan_leaderboard.R (`ifelse(period == "Full Period", ...)`).
#'
#' Two assertions:
#'   1. Every distinct `strategy` has at least one row with
#'      `period == "Full Period"` -- the canonical full-sample label every
#'      leaderboard consumer filters on.
#'   2. Every value in `period` is a member of `PERIOD_LABELS_ALLOWED`
#'      (R/plan_partitions.R) -- the single source of truth for the allowed
#'      vocabulary. "OOS" is deliberately its own label, distinct from
#'      "Testing" -- see the `PERIOD_LABELS_ALLOWED` comment in
#'      R/plan_partitions.R for why the two windows are not interchangeable.
#'
#' @param leaderboard Tibble with at least `strategy` and `period` columns
#'   (the output of the `leaderboard` targets pipeline target).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_period_vocab <- function(leaderboard) {
  required_cols <- c("strategy", "period")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_period_vocab() (S10) requires strategy, period."
    ))
  }

  # ── Assertion 1: every strategy has a canonical "Full Period" row ────────
  full_period_strategies <- unique(
    leaderboard$strategy[leaderboard$period == "Full Period"]
  )
  all_strategies <- unique(leaderboard$strategy)
  missing_full <- setdiff(all_strategies, full_period_strategies)

  if (length(missing_full) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(missing_full),
        " strategy/strategies missing a canonical {.val Full Period} row:"
      ),
      setNames(sprintf("  %s", missing_full), rep("i", length(missing_full))),
      "i" = paste0(
        "Every consumer of the leaderboard (docs/leaderboard.qmd headline ",
        "table, correlation/redundancy join in R/plan_leaderboard.R) filters ",
        "on period == \"Full Period\" -- a strategy using a different label ",
        "(e.g. \"Full\") for its full-sample row is silently dropped (#643)."
      ),
      "i" = "Normalise the label in the strategy's .norm_* helper in R/plan_leaderboard.R."
    ))
  }

  # ── Assertion 2: no period value outside the canonical vocabulary ────────
  observed_periods <- unique(leaderboard$period)
  bad_periods <- setdiff(observed_periods, PERIOD_LABELS_ALLOWED)

  if (length(bad_periods) > 0L) {
    offender_msgs <- vapply(bad_periods, function(p) {
      strats <- unique(leaderboard$strategy[leaderboard$period == p])
      sprintf("  %s -- used by: %s", p, paste(strats, collapse = ", "))
    }, character(1L))
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard {.field period} column has ", length(bad_periods),
        " value(s) outside the canonical vocabulary:"
      ),
      setNames(offender_msgs, rep("i", length(offender_msgs))),
      "i" = paste0(
        "Allowed values (R/plan_partitions.R PERIOD_LABELS_ALLOWED): ",
        paste(PERIOD_LABELS_ALLOWED, collapse = ", "), "."
      ),
      "i" = "Normalise the label in the strategy's .norm_* helper in R/plan_leaderboard.R (#643)."
    ))
  }

  invisible(TRUE)
}


#' Assert port_returns has no calendar-month gaps and flag thin-coverage
#' months
#'
#' Guards against the #641 defect class: `port_returns` used to chain four
#' `inner_join()`s across its constituent strategies (`stk_max`, `stk_drif`,
#' `fac_max`, `fac_drif`), so any month missing from ONE constituent
#' silently deleted that month for ALL FOUR -- 128 of an expected ~190+
#' rows, including every March (`stk_drif_portfolio` had no March rows at
#' all). R/plan_portfolio_opt.R now builds `port_returns` from an explicit
#' calendar-complete monthly spine (bounded to the overlap of the two
#' stock-level series' own date ranges) and LEFT-joins all four
#' constituents onto it -- a missing constituent surfaces as an explicit NA
#' in that column, not a deleted row.
#'
#' Two assertions:
#'   1. `cli_abort()` if the `date` column has ANY calendar-month gap
#'      between its min and max -- structurally this should be impossible
#'      given the spine-based join described above (see the comment on the
#'      `port_returns` target), so a gap here means either the spine
#'      construction was changed back to using literal ym values, or
#'      `stk_max_portfolio`/`stk_drif_portfolio` (R/plan_stock_backtest.R)
#'      no longer overlap at all. Names every missing month.
#'   2. `cli_warn()` (deliberately NOT abort) for any row where fewer than 2
#'      of the 4 constituents report a value -- `port_combined`'s
#'      `.port_weighted_return()` renormalisation guard (R/plan_portfolio_opt.R)
#'      turns such rows into NA rather than a single-strategy bet dressed up
#'      as a diversified portfolio. In the data as of #641 this is the
#'      expected, benign live-edge lag between stock-level and factor-level
#'      data feeds (currently the most recent 1-2 months) -- NOT a defect --
#'      so it warns rather than aborting, and names the affected month(s)
#'      plus which constituent(s) are missing so a genuine regression is
#'      still visible.
#'
#' @param port_returns Tibble from the `port_returns` target; must have
#'   `date` and the four strategy columns `stk_max`, `stk_drif`, `fac_max`,
#'   `fac_drif`.
#' @return `TRUE` invisibly (assertion 1 always holds on return; assertion 2
#'   may have warned).
#' @noRd
check_portfolio_join_coverage <- function(port_returns) {
  required_cols <- c("date", "stk_max", "stk_drif", "fac_max", "fac_drif")
  missing_cols <- setdiff(required_cols, names(port_returns))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "port_returns is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_portfolio_join_coverage() requires date, stk_max, stk_drif, fac_max, fac_drif."
    ))
  }

  # ── Assertion 1: no calendar-month gap in the date sequence ─────────────
  d <- sort(unique(port_returns$date))
  expected_ym <- format(seq(min(d), max(d), by = "month"), "%Y-%m")
  # port_returns dates are anchored to the 15th (paste0(ym, "-15")); compare
  # on year-month, not exact Date, so day-of-month never produces a false gap.
  observed_ym <- format(d, "%Y-%m")
  missing_months <- setdiff(expected_ym, observed_ym)

  if (length(missing_months) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "port_returns has ", length(missing_months),
        " calendar-month gap(s) in its date sequence:"
      ),
      setNames(sprintf("  %s", missing_months), rep("i", length(missing_months))),
      "i" = paste0(
        "port_returns builds a calendar-complete spine specifically so ",
        "this cannot happen (#641) -- check for a changed spine/join in ",
        "R/plan_portfolio_opt.R or a new gap in stk_max_portfolio / ",
        "stk_drif_portfolio (R/plan_stock_backtest.R)."
      )
    ))
  }

  # ── Assertion 2: flag (warn, don't abort) thin-coverage months ──────────
  strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
  avail <- rowSums(!is.na(as.matrix(port_returns[, strat_cols])))
  thin <- port_returns[avail < 2L, , drop = FALSE]

  if (nrow(thin) > 0L) {
    thin_msgs <- vapply(seq_len(nrow(thin)), function(i) {
      row <- thin[i, ]
      missing_strats <- strat_cols[is.na(row[strat_cols])]
      sprintf("  %s -- missing: %s", format(row$date, "%Y-%m"),
              paste(missing_strats, collapse = ", "))
    }, character(1L))
    cli::cli_warn(c(
      "!" = paste0(
        length(thin_msgs), " month(s) have fewer than 2 of 4 constituent ",
        "strategies reporting a value (renormalised to NA in port_combined ",
        "rather than a single-strategy bet, #641):"
      ),
      setNames(thin_msgs, rep("i", length(thin_msgs))),
      "i" = paste0(
        "Usually the benign live-edge lag between stock-level and ",
        "factor-level data feeds -- verify if this list grows or covers ",
        "a month that isn't at the trailing edge."
      )
    ))
  }

  invisible(TRUE)
}


# ---- QA gate plan ----

plan_qa_gates <- function() {
  list(
    # QA gate: look-ahead bias — 4 forbidden patterns
    #
    # Runs on EVERY tar_make() via cue = "always". Aborts the pipeline on any
    # match, printing file:line:code for each violation.
    #
    # Opt-out for legitimate uses: add `# look-ahead-safe` to the offending line
    # and document why the pattern is safe (e.g. join-key construction where
    # the lead-shifted column is never used as a return series).
    targets::tar_target(
      qa_look_ahead_bias,
      command = {
        files <- list.files(here::here("R"), pattern = "\\.R$",
                            full.names = TRUE, recursive = TRUE)
        files <- files[basename(files) != "plan_qa_gates.R"]

        s1 <- check_no_lead_ym(files)
        s2 <- check_no_unleaded_slider(files)
        s3 <- check_no_na_approx(files)
        s4 <- check_no_forward_cumulative(files)

        all_hits <- dplyr::bind_rows(
          if (nrow(s1) > 0L) dplyr::mutate(s1, check = "S1: lead(ym)") else NULL,
          if (nrow(s2) > 0L) dplyr::mutate(s2, check = "S2: slide_dbl forward without _lead") else NULL,
          if (nrow(s3) > 0L) dplyr::mutate(s3, check = "S3: na.approx (forbidden)") else NULL,
          if (nrow(s4) > 0L) dplyr::mutate(s4, check = "S4: cumulative of forward_*") else NULL
        )

        if (nrow(all_hits) > 0L) {
          msgs <- purrr::pmap_chr(
            all_hits[, c("check", "file", "line", "code")],
            function(check, file, line, code) {
              sprintf("  %s -- %s:%d -- %s", check, basename(file), line, trimws(code))
            }
          )
          cli::cli_abort(c(
            "x" = "Look-ahead bias patterns detected in {nrow(all_hits)} place(s):",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }

        cli::cli_inform(c("v" = "qa_look_ahead_bias: all 4 checks passed (0 patterns detected)"))
        nrow(all_hits)  # 0 on success; downstream gates can depend on this value target
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: diagram click URLs must have #L<n> anchors (S5)
    #
    # Runs whenever docs/ HTML changes. Aborts if any GitHub blob URL for
    # a .R file lacks a #L<n> anchor — which means diagram_node_links.R
    # has a missing or NA line number entry.
    targets::tar_target(
      qa_no_bare_diagram_urls,
      command = {
        html_dir <- here::here("docs")
        hits <- check_no_bare_diagram_urls(html_dir)
        if (nrow(hits) > 0L) {
          msgs <- purrr::pmap_chr(
            hits[, c("file", "line", "url")],
            function(file, line, url) {
              sprintf("  S5: %s:%d -- %s", basename(file), line, url)
            }
          )
          cli::cli_abort(c(
            "x" = "Diagram click URLs without #L<n> anchors in {nrow(hits)} place(s):",
            "i" = "Add line numbers to R/diagram_node_links.R for each node.",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }
        cli::cli_inform(c("v" = "qa_no_bare_diagram_urls: S5 passed (0 bare URLs detected)"))
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every #L<n> anchor must be within the target file's line count (S6)
    #
    # Catches stale line numbers after code edits. Aborts if any anchor points
    # beyond the file's actual line count.
    targets::tar_target(
      qa_anchor_in_range,
      command = {
        html_dir  <- here::here("docs")
        repo_root <- here::here()
        hits <- check_anchor_in_range(html_dir, repo_root)
        if (nrow(hits) > 0L) {
          msgs <- purrr::pmap_chr(
            hits[, c("file", "line", "url", "anchor_line", "max_line")],
            function(file, line, url, anchor_line, max_line) {
              if (is.na(max_line)) {
                sprintf("  S6: %s:%d -- target file not found -- %s",
                        basename(file), line, url)
              } else {
                sprintf("  S6: %s:%d -- #L%d exceeds file max %d -- %s",
                        basename(file), line, anchor_line, max_line, url)
              }
            }
          )
          cli::cli_abort(c(
            "x" = "Stale #L<n> anchors in {nrow(hits)} place(s):",
            "i" = "Update line numbers in R/diagram_node_links.R.",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }
        cli::cli_inform(c("v" = "qa_anchor_in_range: S6 passed (all anchors in range)"))
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every strategy in strategy_names must appear in the leaderboard (S7)
    #
    # strategy_names$short_name holds the canonical display labels.
    # leaderboard$strategy holds the labels set by add_meta(name = ...).
    # Both sets MUST match; missing strategies indicate a wiring gap in
    # plan_leaderboard.R. (#345)
    targets::tar_target(
      qa_leaderboard_coverage,
      command = {
        check_leaderboard_coverage(strategy_names, leaderboard)
        cli::cli_inform(c(
          "v" = paste0(
            "qa_leaderboard_coverage: S7 passed — all ",
            length(strategy_names$short_name), " strategies present in leaderboard"
          )
        ))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every vignette has a Related Vignettes section (S8)
    #
    # Ensures inter-vignette navigation is present in all published .qmd files.
    # Scans docs/*.qmd for a '## Related vignettes' or '#### Related Vignettes'
    # section marker. Skips index.qmd (homepage has site-level navigation).
    # See issue #339 for convention details.
    targets::tar_target(
      qa_vignette_cross_refs,
      command = {
        check_vignette_cross_refs(here::here("docs"))
        cli::cli_inform(c("v" = "qa_vignette_cross_refs: S8 passed (all vignettes have Related Vignettes section)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: leaderboard cagr/vol/max_dd are within a plausible fractional
    # range (S9) — guards against the #637 percent-vs-fraction unit defect
    # class where a strategy's source metrics target stores cagr/vol/max_dd
    # as PERCENT (x * 100) but its .norm_* helper in R/plan_leaderboard.R
    # forgets to convert to the leaderboard's canonical FRACTION convention.
    targets::tar_target(
      qa_leaderboard_metric_ranges,
      command = {
        check_leaderboard_metric_ranges(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_metric_ranges: S9 passed (all cagr/vol/max_dd within fractional range)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: leaderboard period labels are canonical (S10) — guards against
    # the #643 defect class where a strategy's source metrics target uses a
    # non-canonical period label (e.g. "Full" instead of "Full Period") that
    # silently drops the strategy from every period == "Full Period" filter.
    targets::tar_target(
      qa_leaderboard_period_vocab,
      command = {
        check_leaderboard_period_vocab(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_period_vocab: S10 passed (canonical period vocabulary, all strategies have a Full Period row)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: port_returns has no calendar-month gaps, thin-coverage months
    # are flagged (#641) — guards against the #641 defect class where a
    # 4-way inner_join chain in R/plan_portfolio_opt.R silently deleted any
    # month missing from ONE constituent strategy for ALL FOUR (128 of an
    # expected ~190+ rows, including every March). port_returns is now built
    # from a calendar-complete spine with everything left-joined onto it, so
    # a missing constituent surfaces as an explicit NA rather than a deleted
    # row; this gate asserts that guarantee holds.
    targets::tar_target(
      qa_portfolio_join_coverage,
      command = {
        check_portfolio_join_coverage(port_returns)
        cli::cli_inform(c("v" = "qa_portfolio_join_coverage: passed (no calendar-month gaps in port_returns)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    )
  )
}
