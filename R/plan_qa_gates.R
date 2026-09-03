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
#' Deliberately one-directional: every declared `strategy_names` row must
#' appear on the leaderboard, but the leaderboard MAY carry extra rows with
#' no `strategy_names` entry (e.g. benchmark rows) -- see
#' `packages/historicaldata/tests/testthat/test-leaderboard-coverage.R::
#' "returns TRUE when leaderboard has extra strategies"`, which documents
#' this as intentional. A stricter, bidirectional (reverse-setdiff) version
#' was tried while closing out #629 (OLMAR-1 was ranked on the leaderboard
#' with no `strategy_names` row) and reverted after it broke that documented
#' contract -- the missing-`olmar` bug itself is closed by #747's added row,
#' not by tightening this gate.
#'
#' Also asserts that the `ssr` and `top5pct_share` columns are PRESENT in the
#' leaderboard tibble (added in #400, PR 4/6). Whether they hold at least one
#' non-NA value is no longer checked HERE -- that assertion generalised into
#' QA gate S26 (`check_leaderboard_no_all_na_metric()` below, #668), which
#' checks every numeric leaderboard column, not just these two by name.
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

  # Assert SSR column present (#400). All-NA is checked by S26, not here.
  if (!"ssr" %in% names(leaderboard)) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing required column {.field ssr}.",
      "i" = "Add the SSR computation block to R/plan_leaderboard.R (#400)."
    ))
  }

  # Assert top5pct_share column present (#400). All-NA is checked by S26.
  if (!"top5pct_share" %in% names(leaderboard)) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing required column {.field top5pct_share}.",
      "i" = "Add the top5pct computation block to R/plan_leaderboard.R (#400)."
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
#'      "Holdout" (#660) is accepted the same way "OOS" is: a strategy MAY
#'      report a Holdout row or not -- assertion 1 only requires "Full
#'      Period", never "Holdout" -- so a strategy without one still passes.
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


#' Assert no automatically-computed metric window extends past `test_end`
#' unless its partition is explicitly "Validation" (S11)
#'
#' Guards against the #645 defect class: a strategy's source metrics target
#' (e.g. `mf_metrics` in R/plan_managed_futures.R, `ev_metrics` in
#' R/plan_ev_ebit.R) computes a bespoke period window that is unbounded above
#' and therefore silently includes the sealed Validation partition
#' (R/plan_partitions.R `bt_partitions`, `backtest-partitions` rule) on every
#' `tar_make()`.
#'
#' Three period labels are exempt from the `test_end` bound, all by design of
#' `backtest-partitions.md`:
#'   - `"Validation"` -- the sealed partition itself; its whole purpose is to
#'     extend past `test_end`.
#'   - `"Holdout"` -- the observed-but-unsealed tier added in #660
#'     (2024-01-01..2026-04-30). `test_end` moved back to 2023-12-31 as part
#'     of the same change (absorbing the burned 2023 into Testing), so
#'     Holdout's `window_end` legitimately sits past `test_end` on every
#'     `tar_make()` -- that is the entire point of the tier, not a #645-style
#'     leak. Unlike Validation, Holdout IS computed automatically; see
#'     `.claude/rules/backtest-partitions.md`'s Holdout subsection for why
#'     that is by design rather than a seal breach.
#'   - `"Full"` / `"Full Period"` -- the rule's own canonical reference
#'     implementation lists `calc_metrics(all_data, "Full Period")` alongside
#'     Training/Testing/Validation as an accepted, full-sample summary that is
#'     *expected* to span the whole series (including Validation) by
#'     definition -- it is not a bespoke evaluation/test window like `"OOS"`.
#'     Every other strategy on the leaderboard already reports a Full Period
#'     row this way; only a genuinely bespoke window (not itself the sealed
#'     partition, the Holdout tier, or the full-sample summary) is what #645
#'     is about.
#'
#' @param metrics A tibble with at least `strategy`, `period`, `window_end`
#'   columns (the output of a strategy metrics target, e.g. `mf_metrics` or
#'   `ev_metrics`).
#' @param test_end A single Date -- the canonical test-partition upper bound
#'   for this metrics target's asset class (from `bt_partitions`,
#'   R/plan_partitions.R).
#' @param source_label A short string identifying the metrics target being
#'   checked (used in error messages), e.g. `"mf_metrics"`.
#' @return `TRUE` invisibly on success.
#'
#' @section Scope note (#648):
#' This function is scoped to window BOUNDS on `mf_metrics`/`ev_metrics`
#' only. #648 identified a systematic, wider version of the same seal-breach
#' pattern: `slice_portfolio()` in R/plan_leaderboard.R computed an explicit
#' `Validation` slice on every `tar_make()` for several strategies -- not a
#' bounds violation (those rows were correctly labelled `"Validation"`), but
#' an automatic-computation violation (`backtest-partitions.md`: "Validation
#' metrics are NOT computed automatically by tar_make()"). That was a
#' different check -- "no row may be automatically labelled Validation at
#' all" -- from this function's "no window may silently extend past
#' test_end".
#'
#' #648 was fixed as a SIBLING gate, `check_leaderboard_no_validation_rows()`
#' (S14), rather than folded into this function, because the two operate on
#' different shapes: this function takes a single source metrics target
#' (`mf_metrics`/`ev_metrics`) with a `window_end` column and asserts a
#' bound; S14 takes the assembled, multi-strategy `leaderboard` target
#' (same shape as S9/S10) and asserts a label is entirely absent. Forcing
#' both checks through one function signature would have required either a
#' new optional `window_end`-less mode or a second call convention -- a
#' same-shape sibling next to S9/S10 was the smaller change. See S14's own
#' roxygen block below for the fix.
#' @noRd

#' Registry of metrics targets checked by S11 (`check_metric_window_bounds()`)
#'
#' @section #667 -- widening S11 beyond an enumerated pair:
#' Before #667, S11 was called on exactly two hardcoded targets
#' (`mf_metrics`, `ev_metrics`) -- the same "scope drawn around the known
#' instances" failure the `backtest-partitions.md` rule's `paths:` glob had.
#' This registry is the fix: every metrics target with `strategy`/`period`/
#' `window_end` columns is listed here ONCE, mapped to the `bt_partitions`
#' class whose `test_end` bounds it, and the `qa_metric_window_bounds` gate
#' below iterates the registry instead of repeating one hardcoded call per
#' target. Adding a new metrics target now costs one list entry, not a new
#' `check_metric_window_bounds()` call to remember to write.
#'
#' @section Why this is NOT full auto-discovery:
#' The issue asked for the gate to `cli_abort()` when a target carrying a
#' `period` column exists but is absent from this registry -- i.e. omission
#' should be an error, not silent non-coverage. That is infeasible from
#' *inside* this target's command: targets' dependency graph is built by
#' static analysis of symbols literally referenced in each target's command
#' expression, so `qa_metric_window_bounds` can only "see" targets named
#' here -- it has no way to enumerate "every other target in the pipeline"
#' at runtime. `R/utils_validation.R`'s `.make_store_reader()` documents the
#' same constraint for `dv_join_key_types`: "`tar_read_raw()` is forbidden
#' inside a targets pipeline (nested store access)", and its workaround
#' (reading RDS objects directly from the store by name) still requires the
#' names to be registered up front -- it decouples the *dependency edge*
#' from the registry, not the *registration requirement* itself. Adopting
#' that pattern here would trade a real problem (the gate wouldn't be
#' tracked as depending on its metrics targets, so it could go stale
#' without rerunning) for a cosmetic one (avoiding the literal symbol list
#' below), which is a worse trade for a QA gate. A genuinely automatic
#' omission check would need a source-level lint (grep `R/plan_*.R` for a
#' `tibble::tibble(...)` block containing both `strategy =`/`period =` and
#' `window_end = max(`, then diff the target names found against this
#' registry) -- that is a `scripts/` check, not a targets target, and is
#' flagged as a follow-up rather than built here.
#' @noRd
S11_METRICS_REGISTRY <- list(
  mf_metrics       = "macro",   # #645 original
  ev_metrics       = "factor",  # #645 original
  rsc_metrics      = "macro",   # #667
  aw_metrics       = "equity",  # #667
  mr_metrics       = "equity",  # #667
  rafi_metrics     = "factor",  # #667
  fip_comparison   = "equity",  # #667
  eur_results      = "macro",   # #667
  eur_comparison   = "macro",   # #667
  eur_ciss_results = "macro"    # #667
)

#' Assert `S11_METRICS_REGISTRY` and the `metrics_by_name` list literal the
#' `qa_metric_window_bounds` target actually fetched agree EXACTLY (#667, #673)
#'
#' Extracted out of the target's command (rather than left inline) so it is
#' unit-testable directly, per `fail-loud-not-null.md` and
#' `snapshot-test-policy.md` -- see tests/testthat/test-metric-window-bounds.R.
#'
#' #673 made this bidirectional. It originally checked only
#' `setdiff(registry, fetched)` -- a registry entry never fetched. The mirror
#' case was silent: a target added to the `metrics_by_name` literal but
#' forgotten in the registry is simply never iterated, so S11 skips it and the
#' gate still reports PASS. That is the `fail-loud-not-null.md` shape applied
#' to the guard itself -- an omission producing a plausible pass rather than an
#' error, which is precisely what S11 exists to prevent one level down.
#' @noRd
check_s11_registry_consistency <- function(registry_names, metrics_by_name_names) {
  missing_from_metrics <- setdiff(registry_names, metrics_by_name_names)
  if (length(missing_from_metrics) > 0L) {
    cli::cli_abort(c(
      "x" = "S11_METRICS_REGISTRY names {length(missing_from_metrics)} target(s) qa_metric_window_bounds never fetched:",
      "i" = paste(missing_from_metrics, collapse = ", "),
      "i" = "Add the target to the metrics_by_name list literal in R/plan_qa_gates.R (S11)."
    ))
  }

  missing_from_registry <- setdiff(metrics_by_name_names, registry_names)
  if (length(missing_from_registry) > 0L) {
    cli::cli_abort(c(
      "x" = "qa_metric_window_bounds fetched {length(missing_from_registry)} target(s) absent from S11_METRICS_REGISTRY, so S11 never checked them:",
      "i" = paste(missing_from_registry, collapse = ", "),
      "i" = "Add each to S11_METRICS_REGISTRY in R/plan_qa_gates.R, mapped to its bt_partitions class (equity/macro/factor)."
    ))
  }

  invisible(TRUE)
}

check_metric_window_bounds <- function(metrics, test_end, source_label) {
  required_cols <- c("strategy", "period", "window_end")
  missing_cols <- setdiff(required_cols, names(metrics))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{source_label} is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_metric_window_bounds() (S11) requires strategy, period, window_end."
    ))
  }

  exempt_periods <- c("Validation", "Holdout", "Full", "Full Period")

  is_offender <- !is.na(metrics$window_end) &
    !(metrics$period %in% exempt_periods) &
    metrics$window_end > test_end
  offenders <- metrics[is_offender, c("strategy", "period", "window_end"), drop = FALSE]

  if (nrow(offenders) > 0L) {
    msgs <- purrr::pmap_chr(
      offenders,
      function(strategy, period, window_end) {
        sprintf("  %s / %s -- window_end %s exceeds test_end %s",
                strategy, period, window_end, test_end)
      }
    )
    cli::cli_abort(c(
      "x" = paste0(
        source_label, " has ", nrow(offenders),
        " row(s) whose computed window extends past the sealed Validation ",
        "partition boundary (test_end = ", test_end, "), #645:"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "Bound the window at test_end in the source metrics target, or ",
        "relabel the period \"Validation\" if the window is intentionally sealed."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert the leaderboard target never emits an automatically-computed
#' "Validation" row (S14)
#'
#' Guards against the #648 defect class: `backtest-partitions.md` requires
#' Validation metrics to never be computed automatically by `tar_make()` --
#' only via an explicit manual target or script, exactly once, as a sealed
#' one-shot evaluation. Two independent sources fed Validation rows into the
#' `leaderboard` target before #648:
#'   1. `slice_portfolio()` in R/plan_leaderboard.R computed a `Validation`
#'      cost-metric slice on every `tar_make()` for six strategies.
#'   2. Several source metrics targets (fm_metrics, drif_metrics,
#'      stk_max_metrics, stk_drif_metrics, xgb_drif_metrics, ltr_metrics,
#'      port_metrics) independently compute a `Validation` row in their own
#'      plan file, which flowed into `all_metrics` completely unfiltered.
#' Both are addressed at #648 by dropping every `period == "Validation"` row
#' the moment `all_metrics` is assembled in R/plan_leaderboard.R -- this gate
#' is the belt-and-braces check that the `leaderboard` target itself never
#' re-exposes one, regardless of which upstream source (existing or future)
#' reintroduces it.
#'
#' This is a distinct check from S11 (`check_metric_window_bounds()`): S11
#' asserts a per-strategy source metrics target's own bespoke window never
#' extends past `test_end` UNLESS it is correctly labelled "Validation" (a
#' bounds check on a single source target with a `window_end` column). This
#' gate asserts the opposite direction on the assembled, multi-strategy
#' `leaderboard` target: no row may be labelled "Validation" at all, because
#' that target's whole path is automatic. See S11's `@section Scope note
#' (#648)` for why these are two gates rather than one.
#'
#' Note: the source metrics targets listed above (fm_metrics et al.) still
#' compute Validation rows for their OWN purposes -- that is out of #648's
#' scope (those targets are not modified here) and several also surface
#' Validation values directly in vignette prose (e.g. docs/stock-backtest.qmd),
#' which is a separate, wider display-side leak not covered by this gate.
#' This gate only guarantees the `leaderboard` target's own output.
#'
#' @section Holdout is deliberately unaffected (#660):
#' This gate checks ONLY for `period == "Validation"`. The `"Holdout"` label
#' added in #660 (R/plan_partitions.R, 2024-01-01..2026-04-30) is an
#' automatically-computed, observed-but-unsealed tier -- it is EXPECTED to
#' reach the `leaderboard` target and must never be rejected here. Widening
#' this gate to reject Holdout would misapply the Validation seal to a
#' partition that was never sealed in the first place; see
#' `.claude/rules/backtest-partitions.md`'s Holdout subsection.
#'
#' @param leaderboard Tibble with at least `strategy`, `period` columns (the
#'   output of the `leaderboard` targets pipeline target).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_no_validation_rows <- function(leaderboard) {
  required_cols <- c("strategy", "period")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_no_validation_rows() (S14) requires strategy, period."
    ))
  }

  offenders <- unique(leaderboard$strategy[leaderboard$period == "Validation"])

  if (length(offenders) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(offenders),
        " strategy/strategies with an automatically-computed {.val Validation} row, #648:"
      ),
      setNames(sprintf("  %s", offenders), rep("i", length(offenders))),
      "i" = paste0(
        "Validation metrics must NOT be computed automatically by tar_make() ",
        "(.claude/rules/backtest-partitions.md). Drop the Validation row at ",
        "the point it enters R/plan_leaderboard.R's `all_metrics`, or use ",
        "scripts/evaluate_validation.R for a one-shot manual evaluation."
      )
    ))
  }

  invisible(TRUE)
}


#' Scan published documents for reads of the sealed Validation partition (S15)
#'
#' Guards against the #660 defect class: `docs/stock-backtest.qmd` read
#' `period == "Validation"` directly from upstream source-metrics targets
#' (`stk_drif_metrics`, `stk_max_metrics`, `fm_metrics`, `drif_metrics`,
#' `etf_a_metrics`, `etf_b_metrics`) in inline R expressions and in
#' unfiltered metrics tables -- publishing sealed one-shot evaluation
#' figures in prose and table cells, and in one case (the Stock DRIF Cons
#' cell) drawing a strategy conclusion from them. This entirely bypassed
#' the `leaderboard` target and its S14 gate (`check_leaderboard_no_validation_rows()`),
#' because these reads went straight to the source metrics targets, which
#' still legitimately compute a Validation row for other consumers (that
#' computation is out of scope here and is not touched by this gate).
#'
#' `.claude/rules/backtest-partitions.md` requires Validation to stay sealed
#' everywhere it could leak -- not only in automatic computation --
#' S14's scope was the assembled `leaderboard` target only. This gate
#' extends the seal to every published document by scanning for the
#' literal `period == "Validation"` (or `period=="Validation"`) comparison,
#' the idiom every #660 offending site shared.
#'
#' Known limitation (documented, not silently accepted): this is a lexical
#' scan, like S1-S4 (`check_no_lead_ym()` et al.). A comparison built from a
#' variable (e.g. `m$period == per` where `per` is later passed the string
#' `"Validation"` at a call site) will NOT be caught by this pattern -- the
#' #660 fix removed the one site in this codebase that did this (the
#' `get_val()` helper in `docs/stock-backtest.qmd`'s headline callout) in
#' favour of the literal idiom used everywhere else in the file, so no such
#' site currently exists to miss.
#'
#' Exclusions (both required for the scan to be usable at all):
#'   - `R/plan_qa_gates.R` itself -- this function's own roxygen block and
#'     `check_leaderboard_no_validation_rows()` (S14) both name the literal
#'     pattern `period == "Validation"` in comments/code; same
#'     self-exclusion convention as `qa_look_ahead_bias` (S1-S4).
#'   - `scripts/evaluate_validation.R` -- the sanctioned one-shot manual
#'     evaluation route (#648). It does not currently use a `period ==`
#'     comparison (it *assigns* `period = "Validation"` when building its
#'     result rows), so today this exclusion is defensive rather than
#'     load-bearing -- but the script's whole purpose is to read the
#'     Validation partition, so it must never be flagged if its
#'     implementation changes to filter its own output by period.
#'
#' Opt-out: append `# validation-read-safe` to a line reading Validation
#' for a purpose that is not a published display of the metric (rare;
#' document why in the comment).
#'
#' @param files Character vector of absolute file paths to scan (.qmd, .R).
#' @return A tibble with columns file, line, code. Zero rows = no hits.
#' @noRd
check_no_published_validation_reads <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("period\\s*==\\s*[\"']Validation[\"']", lines)
    m <- m[!grepl("# validation-read-safe", lines[m], fixed = TRUE)]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}


#' Assert a monthly portfolio target has complete calendar-month coverage (S12)
#'
#' Guards against the #641 defect class: a systematic construction bug (a
#' lookback/rebalance window confined to a single calendar month) can
#' silently drop an entire calendar month -- month 3/March in the #641
#' case -- from EVERY year of a monthly strategy target, with no error and
#' no warning anywhere else in the pipeline. `stk_max_portfolio` (255 rows,
#' all 12 months) was the healthy sibling that exposed `stk_drif_portfolio`
#' (129 rows, month 3 entirely absent) as broken.
#'
#' Two assertions:
#'   1. Every calendar month 1-12 is represented by at least one row.
#'   2. The number of distinct `ym` values covers a minimum fraction of the
#'      target's own [min(ym), max(ym)] calendar-month span (default 60%) --
#'      catches broader coverage collapse even when no single calendar
#'      month is entirely absent.
#'
#' @param portfolio Tibble with a `ym` column ("YYYY-MM").
#' @param target_name Character scalar, the target's name, used in messages.
#' @param min_span_coverage Numeric in (0, 1]. Minimum fraction of the
#'   target's own calendar-month span that must be present.
#' @return `TRUE` invisibly on success.
#' @noRd
check_month_coverage <- function(portfolio, target_name, min_span_coverage = 0.6) {
  if (!"ym" %in% names(portfolio)) {
    cli::cli_abort(c(
      "x" = "{target_name} is missing the required {.field ym} column.",
      "i" = "check_month_coverage() (S12) requires a ym (\"YYYY-MM\") column."
    ))
  }

  yms <- sort(unique(portfolio$ym))
  if (length(yms) == 0L) {
    cli::cli_abort(c("x" = "{target_name} has zero rows -- cannot assess month coverage."))
  }

  observed_month_nums <- sort(unique(as.integer(substr(yms, 6, 7))))
  missing_month_nums <- setdiff(1:12, observed_month_nums)

  if (length(missing_month_nums) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        target_name, ": calendar month(s) ", paste(missing_month_nums, collapse = ", "),
        " {.strong entirely absent} across the whole sample (", length(yms),
        " month(s), ", min(yms), " to ", max(yms), ")."
      ),
      "i" = "A whole calendar month missing every year is a systematic construction bug, not sampling noise (#641).",
      "i" = "Check for a lookback/rebalance window confined to a single calendar month, or a silent NA/join drop upstream."
    ))
  }

  full_span <- seq.Date(as.Date(paste0(min(yms), "-01")), as.Date(paste0(max(yms), "-01")), by = "month")
  full_span_ym <- format(full_span, "%Y-%m")
  span_coverage <- length(yms) / length(full_span_ym)

  if (span_coverage < min_span_coverage) {
    cli::cli_abort(c(
      "x" = paste0(
        target_name, ": only ", length(yms), "/", length(full_span_ym), " (",
        sprintf("%.0f%%", span_coverage * 100), ") of its own [", min(yms), ", ",
        max(yms), "] calendar-month span is present -- below the ",
        sprintf("%.0f%%", min_span_coverage * 100), " minimum."
      ),
      "i" = "This may indicate systematic month loss upstream (#641) even though no single calendar month is entirely absent."
    ))
  }

  invisible(TRUE)
}


#' Assert port_returns has no calendar-month gaps and flag thin-coverage
#' months (S13)
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
      "i" = "check_portfolio_join_coverage() (S13) requires date, stk_max, stk_drif, fac_max, fac_drif."
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


#' Assert stk_all_comparison has no calendar-month gaps and flag
#' thin-coverage months (S24)
#'
#' Guards against the #656 defect class: `stk_all_comparison`
#' (R/plan_stock_backtest.R) used to chain four `inner_join()`s across its
#' constituent strategies (`stk_max`, `stk_drif`, `fac_max`, `fac_drif`) --
#' the SAME four constituents and the SAME hazard as the #641 `port_returns`
#' defect (S13) -- so any month missing from ONE constituent silently
#' deleted that month for ALL FOUR. Unlike `port_returns`, this target had
#' ZERO instrumentation before #656 and feeds `stk_all_comparison_plot`,
#' published on BOTH `leaderboard.qmd` and `stock-backtest.qmd`.
#' `stk_all_comparison` is now built from a calendar-complete monthly spine
#' (bounded to the stock-level overlap window) with everything LEFT-joined
#' onto it -- a missing constituent surfaces as an explicit NA in its own
#' column, never a deleted row.
#'
#' Two assertions, mirroring `check_portfolio_join_coverage()` (S13):
#'   1. `cli_abort()` if the `ym` column has ANY calendar-month gap between
#'      its min and max -- structurally this should be impossible given the
#'      spine-based join described above, so a gap here means the spine
#'      construction was changed back to using literal `ym` values, or
#'      `stk_max_portfolio`/`stk_drif_portfolio` no longer overlap at all.
#'   2. `cli_warn()` (deliberately NOT abort) for any row where fewer than
#'      all 4 constituents report a value -- the equity-growth columns hold
#'      flat (no compounding) across such a gap rather than propagating NA
#'      forward (see `cumgrowth_na_safe()` in the `stk_all_comparison`
#'      target), so a gap here degrades one curve's fidelity rather than
#'      breaking the pipeline; still worth surfacing if it grows.
#'
#' @param stk_all_comparison Tibble from the `stk_all_comparison` target;
#'   must have `ym`, `stk_max`, `stk_drif`, `fac_max`, `fac_drif`.
#' @return `TRUE` invisibly (assertion 1 always holds on return; assertion 2
#'   may have warned).
#' @noRd
check_stk_all_comparison_coverage <- function(stk_all_comparison) {
  required_cols <- c("ym", "stk_max", "stk_drif", "fac_max", "fac_drif")
  missing_cols <- setdiff(required_cols, names(stk_all_comparison))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "stk_all_comparison is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_stk_all_comparison_coverage() (S24) requires ym, stk_max, stk_drif, fac_max, fac_drif."
    ))
  }

  # ── Assertion 1: no calendar-month gap in the ym sequence ───────────────
  yms <- sort(unique(stk_all_comparison$ym))
  expected_ym <- format(
    seq(as.Date(paste0(min(yms), "-01")), as.Date(paste0(max(yms), "-01")), by = "month"),
    "%Y-%m"
  )
  missing_months <- setdiff(expected_ym, yms)

  if (length(missing_months) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "stk_all_comparison has ", length(missing_months),
        " calendar-month gap(s) in its ym sequence:"
      ),
      setNames(sprintf("  %s", missing_months), rep("i", length(missing_months))),
      "i" = paste0(
        "stk_all_comparison builds a calendar-complete spine specifically ",
        "so this cannot happen (#656) -- check for a changed spine/join in ",
        "R/plan_stock_backtest.R or a new gap in stk_max_portfolio / ",
        "stk_drif_portfolio."
      )
    ))
  }

  # ── Assertion 2: flag (warn, don't abort) thin-coverage months ──────────
  strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
  avail <- rowSums(!is.na(as.matrix(stk_all_comparison[, strat_cols])))
  thin <- stk_all_comparison[avail < length(strat_cols), , drop = FALSE]

  if (nrow(thin) > 0L) {
    thin_msgs <- vapply(seq_len(nrow(thin)), function(i) {
      row <- thin[i, ]
      missing_strats <- strat_cols[is.na(row[strat_cols])]
      sprintf("  %s -- missing: %s", row$ym, paste(missing_strats, collapse = ", "))
    }, character(1L))
    cli::cli_warn(c(
      "!" = paste0(
        length(thin_msgs), " month(s) in stk_all_comparison have at least ",
        "one missing constituent strategy (#656):"
      ),
      setNames(thin_msgs, rep("i", length(thin_msgs))),
      "i" = "Usually the benign live-edge lag between stock-level and factor-level data feeds."
    ))
  }

  invisible(TRUE)
}


#' Assert boot_monthly_returns has no calendar-month gaps and flag
#' thin-coverage months (S25)
#'
#' Guards against the #603 defect class: `boot_monthly_returns`
#' (R/plan_bootstrap_ci.R) used to chain four `inner_join()`s across the
#' same four constituent strategies as S13/S24 (`stk_max`, `stk_drif`,
#' `fac_max`, `fac_drif`), silently deleting ~128 of an expected ~190+
#' months. Worse than S13/S24: the block bootstrap in `boot_draws` resamples
#' CONTIGUOUS row-index blocks to preserve serial dependence, so a
#' non-contiguous join let a "3-month block" splice non-adjacent calendar
#' months together, defeating the point of block resampling. These
#' intervals feed `boot_ci_summary`'s `ci_crosses_zero` flag, joined onto
#' the published leaderboard. `boot_monthly_returns` is now built from a
#' calendar-complete monthly spine (bounded to the stock-level overlap
#' window) with everything LEFT-joined onto it.
#'
#' Two assertions, mirroring `check_portfolio_join_coverage()` (S13) and
#' `check_stk_all_comparison_coverage()` (S24):
#'   1. `cli_abort()` if the `ym` column has ANY calendar-month gap --
#'      structurally impossible given the spine-based join.
#'   2. `cli_warn()` (deliberately NOT abort) for any row where fewer than
#'      all 4 constituents report a value -- `calc_boot_metrics()` (the
#'      `boot_metrics` target) drops NA pairwise per strategy/rf pair, so
#'      this degrades that strategy's effective bootstrap sample size for
#'      that block rather than breaking the pipeline.
#'
#' @param boot_monthly_returns Tibble from the `boot_monthly_returns`
#'   target; must have `ym`, `stk_max`, `stk_drif`, `fac_max`, `fac_drif`
#'   (the `_rf` columns are not required for this check).
#' @return `TRUE` invisibly (assertion 1 always holds on return; assertion 2
#'   may have warned).
#' @noRd
check_boot_monthly_returns_coverage <- function(boot_monthly_returns) {
  required_cols <- c("ym", "stk_max", "stk_drif", "fac_max", "fac_drif")
  missing_cols <- setdiff(required_cols, names(boot_monthly_returns))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "boot_monthly_returns is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_boot_monthly_returns_coverage() (S25) requires ym, stk_max, stk_drif, fac_max, fac_drif."
    ))
  }

  # ── Assertion 1: no calendar-month gap in the ym sequence ───────────────
  yms <- sort(unique(boot_monthly_returns$ym))
  expected_ym <- format(
    seq(as.Date(paste0(min(yms), "-01")), as.Date(paste0(max(yms), "-01")), by = "month"),
    "%Y-%m"
  )
  missing_months <- setdiff(expected_ym, yms)

  if (length(missing_months) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "boot_monthly_returns has ", length(missing_months),
        " calendar-month gap(s) in its ym sequence:"
      ),
      setNames(sprintf("  %s", missing_months), rep("i", length(missing_months))),
      "i" = paste0(
        "boot_monthly_returns builds a calendar-complete spine specifically ",
        "so this cannot happen (#603/#656) -- check for a changed spine/join ",
        "in R/plan_bootstrap_ci.R or a new gap in stk_max_portfolio / ",
        "stk_drif_portfolio. A gap here also means the block bootstrap in ",
        "boot_draws would splice non-adjacent calendar months (the original ",
        "#603 defect)."
      )
    ))
  }

  # ── Assertion 2: flag (warn, don't abort) thin-coverage months ──────────
  strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
  avail <- rowSums(!is.na(as.matrix(boot_monthly_returns[, strat_cols])))
  thin <- boot_monthly_returns[avail < length(strat_cols), , drop = FALSE]

  if (nrow(thin) > 0L) {
    thin_msgs <- vapply(seq_len(nrow(thin)), function(i) {
      row <- thin[i, ]
      missing_strats <- strat_cols[is.na(row[strat_cols])]
      sprintf("  %s -- missing: %s", row$ym, paste(missing_strats, collapse = ", "))
    }, character(1L))
    cli::cli_warn(c(
      "!" = paste0(
        length(thin_msgs), " month(s) in boot_monthly_returns have at ",
        "least one missing constituent strategy (#603/#656):"
      ),
      setNames(thin_msgs, rep("i", length(thin_msgs))),
      "i" = "calc_boot_metrics() drops NA pairwise per strategy, so this cannot poison another strategy's bootstrap draws."
    ))
  }

  invisible(TRUE)
}


#' Assert every strategy's borrow_status is derivable, in the allowed
#' vocabulary, and consistent with borrow_rate_annual (S16)
#'
#' Guards against the #664 defect class: `strategy_cost_convention`'s
#' `borrow_rate_annual` column conflated "no short leg -- borrow correctly
#' N/A" with "short leg exists, borrow genuinely unmodelled" as a single NA
#' value, with the distinction recorded only as free prose in
#' `cost_source_ref` that nothing could filter, sort, count, or gate on
#' (fail-loud-not-null.md). `borrow_status` (derived by
#' `derive_borrow_status()`, R/plan_cost_convention.R) makes the distinction
#' machine-readable; this gate is the belt-and-braces check that the
#' derivation actually held for every row -- no NA status, no status outside
#' `BORROW_STATUS_ALLOWED`, and no row where the derived status contradicts
#' whether a `borrow_rate_annual` is actually present (a `"modelled"` row
#' with no rate, or a non-`"modelled"` row WITH a rate, is a contradiction
#' and must abort).
#'
#' @param strategy_cost_convention Tibble with at least `strategy`,
#'   `borrow_status`, `borrow_rate_annual` columns (the output of the
#'   `strategy_cost_convention` target, R/plan_cost_convention.R).
#' @return `TRUE` invisibly on success.
#' @noRd
check_borrow_status_registry <- function(strategy_cost_convention) {
  required_cols <- c("strategy", "borrow_status", "borrow_rate_annual")
  missing_cols <- setdiff(required_cols, names(strategy_cost_convention))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "strategy_cost_convention is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_borrow_status_registry() (S16) requires strategy, borrow_status, borrow_rate_annual."
    ))
  }

  # ── Assertion 1: no NA borrow_status ─────────────────────────────────────
  na_status <- strategy_cost_convention$strategy[is.na(strategy_cost_convention$borrow_status)]
  if (length(na_status) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "strategy_cost_convention has ", length(na_status),
        " strategy/strategies with NA borrow_status (#664):"
      ),
      setNames(sprintf("  %s", na_status), rep("i", length(na_status))),
      "i" = "Every strategy must resolve to a status in BORROW_STATUS_ALLOWED (R/plan_cost_convention.R) -- never NA."
    ))
  }

  # ── Assertion 2: no out-of-vocabulary borrow_status ──────────────────────
  bad_vocab <- unique(setdiff(strategy_cost_convention$borrow_status, BORROW_STATUS_ALLOWED))
  if (length(bad_vocab) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "strategy_cost_convention has borrow_status value(s) outside the allowed vocabulary: ",
        paste(bad_vocab, collapse = ", ")
      ),
      "i" = paste0("Allowed values: ", paste(BORROW_STATUS_ALLOWED, collapse = ", "), ".")
    ))
  }

  # ── Assertion 3: status must agree with whether a rate is recorded ──────
  is_modelled   <- strategy_cost_convention$borrow_status == "modelled"
  has_rate      <- !is.na(strategy_cost_convention$borrow_rate_annual)
  contradiction <- is_modelled != has_rate
  offenders <- strategy_cost_convention[contradiction,
    c("strategy", "borrow_status", "borrow_rate_annual"), drop = FALSE]

  if (nrow(offenders) > 0L) {
    msgs <- purrr::pmap_chr(
      offenders,
      function(strategy, borrow_status, borrow_rate_annual) {
        sprintf(
          "  %s -- borrow_status = %s, borrow_rate_annual = %s",
          strategy, borrow_status,
          if (is.na(borrow_rate_annual)) "NA" else format(borrow_rate_annual)
        )
      }
    )
    cli::cli_abort(c(
      "x" = paste0(
        "strategy_cost_convention has ", nrow(offenders),
        " row(s) where borrow_status contradicts borrow_rate_annual (#664):"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "A \"modelled\" row must have a non-NA borrow_rate_annual; every ",
        "other status must have NA -- fix the registry row or the ",
        "derivation in R/plan_cost_convention.R."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert every strategy's `lending_status` is derivable and in the allowed
#' vocabulary (S18)
#'
#' Sibling to `check_borrow_status_registry()` (S16), not an extension of it
#' -- deliberately a separate gate rather than folded into S16, for three
#' reasons: (1) S16's docstring, tests, and error messages are scoped
#' specifically to `borrow_status` vs `borrow_rate_annual` consistency, and
#' widening it to also reason about lending would make one function assert
#' two independent claims about two independently-derived columns; (2)
#' `lending_status` has no numeric counterpart to cross-check for
#' contradiction the way S16 checks `borrow_status` against
#' `borrow_rate_annual` -- the #665 decision is qualitative-only (a
#' materiality judgement, not a rate), so a "contradiction" assertion would
#' have nothing to compare against; (3) keeping the gates separate keeps the
#' failure message unambiguous -- a `borrow_status` regression and a
#' `lending_status` regression are different defects with different fixes,
#' and a shared gate would force a reader to work out which one actually
#' broke from a single generic message.
#'
#' Guards against the #665 defect class: securities-lending income was
#' previously modelled NOWHERE, with no decision recorded either way
#' (fail-loud-not-null.md: an absence nobody decided on is indistinguishable
#' from a deliberate zero unless the decision itself is machine-readable).
#' `lending_status` (derived by `derive_lending_status()`,
#' R/plan_cost_convention.R) makes that decision explicit; this gate is the
#' belt-and-braces check that the derivation actually held for every row --
#' no NA status and no status outside `LENDING_STATUS_ALLOWED`.
#'
#' @param strategy_cost_convention Tibble with at least `strategy`,
#'   `lending_status` columns (the output of the `strategy_cost_convention`
#'   target, R/plan_cost_convention.R).
#' @return `TRUE` invisibly on success.
#' @noRd
check_lending_status_registry <- function(strategy_cost_convention) {
  required_cols <- c("strategy", "lending_status")
  missing_cols <- setdiff(required_cols, names(strategy_cost_convention))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "strategy_cost_convention is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_lending_status_registry() (S18) requires strategy, lending_status."
    ))
  }

  # ── Assertion 1: no NA lending_status ────────────────────────────────────
  na_status <- strategy_cost_convention$strategy[is.na(strategy_cost_convention$lending_status)]
  if (length(na_status) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "strategy_cost_convention has ", length(na_status),
        " strategy/strategies with NA lending_status (#665):"
      ),
      setNames(sprintf("  %s", na_status), rep("i", length(na_status))),
      "i" = "Every strategy must resolve to a status in LENDING_STATUS_ALLOWED (R/plan_cost_convention.R) -- never NA."
    ))
  }

  # ── Assertion 2: no out-of-vocabulary lending_status ─────────────────────
  bad_vocab <- unique(setdiff(strategy_cost_convention$lending_status, LENDING_STATUS_ALLOWED))
  if (length(bad_vocab) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        "strategy_cost_convention has lending_status value(s) outside the allowed vocabulary: ",
        paste(bad_vocab, collapse = ", ")
      ),
      "i" = paste0("Allowed values: ", paste(LENDING_STATUS_ALLOWED, collapse = ", "), ".")
    ))
  }

  invisible(TRUE)
}


#' Assert leaderboard `sharpe` is coherent with `cagr`, `vol`, and `ann_rf`
#' published beside it (S17)
#'
#' Guards against the #677 defect class: `sharpe` on the `leaderboard`
#' target was computed by at least FOUR distinct mathematical bases across
#' ~13 source metrics targets (geometric vs arithmetic numerator; risk-free
#' deducted or not), so strategies were ranked against each other on a
#' statistic that was not actually comparable -- LTR's implied risk-free
#' rate of -32.89% (a \code{hac_sharpe} value renamed into \code{sharpe},
#' pre-#677 \code{R/plan_leaderboard.R}) was the sharpest symptom, but three
#' further strategies (TOM, Value (HML), Managed Futures) deducted NO
#' risk-free rate at all -- an implied rf of exactly 0.00%, a formula
#' signature, not a coincidence.
#'
#' #677 slices 1-3b migrated every leaderboard-feeding source metrics target
#' onto the canonical, risk-free-adjusted \code{sharpe_ratio_rf()}
#' (R/utils_metrics.R) and required every one of them to ALSO publish the
#' \code{ann_rf} it used (see the module-level "ann_rf (#677 slice 4)"
#' comment in R/plan_leaderboard.R). This gate is the belt-and-braces check
#' that the migration held EXACTLY, not approximately: rather than a
#' "plausible band" on the implied risk-free rate -- which cannot distinguish
#' a strategy whose sample genuinely spans a near-zero-rate era from one that
#' silently deducted no risk-free rate at all, see
#' \code{.claude/rules/fail-loud-not-null.md} -- it recomputes
#' \code{(cagr - ann_rf) / vol} from the published columns and asserts it
#' equals the published \code{sharpe} to within a rounding tolerance.
#'
#' Three assertions, per \code{fail-loud-not-null.md}'s "a row that cannot be
#' checked must fail, not pass silently" -- an uncheckable row is NEVER
#' skipped, only ever aborted:
#'   \enumerate{
#'     \item \code{ann_rf} must be present (non-NA) on EVERY row. A missing
#'       \code{ann_rf} is exactly #677 defect B's failure mode one level up
#'       the stack: a source metrics target computing \code{sharpe} without
#'       ever publishing the risk-free rate it used to compute it.
#'     \item \code{vol} must be a positive, non-NA number on every row -- the
#'       coherence formula divides by it, and a zero/NA \code{vol} makes the
#'       published \code{sharpe} itself unverifiable.
#'     \item \code{abs(sharpe - (cagr - ann_rf) / vol) < tol} for every row.
#'       A \code{sharpe} that is \code{NA} while \code{cagr}/\code{vol}/
#'       \code{ann_rf} are all present and checkable is treated as an
#'       INFINITE discrepancy (a genuine incoherence), never silently
#'       excluded from the check.
#'   }
#'
#' @section Tolerance:
#' \code{tol} defaults to 0.02 (2 Sharpe-ratio "points"). This is not a slack
#' number picked to make the check pass -- it is sized to the single
#' coarsest ACTUAL rounding combination among the ~13 source metrics targets
#' that feed this gate: \code{aw_metrics} (R/plan_avoid_worst.R) and
#' \code{ltr_metrics} (R/plan_ltr_momentum.R) both round
#' \code{cagr}/\code{vol}/\code{ann_rf} to ONE decimal place of PERCENT (a
#' rounding half-width of 0.05 percentage points = 0.0005 as a fraction,
#' applied independently to \code{cagr}, \code{vol}, AND \code{ann_rf}) and
#' round \code{sharpe} itself to only TWO decimal places (a rounding
#' half-width of 0.005). Propagating those three independent 0.0005-fraction
#' errors through \code{(cagr - ann_rf) / vol} at their smallest observed
#' \code{vol} (Avoid Worst's ~0.18, LTR's ~0.17) bounds the coherence gap at
#' ~0.012 in the worst case; \code{tol = 0.02} keeps a margin above that
#' bound. Every other source target
#' (fm_metrics/drif_metrics/stk_max_metrics/stk_drif_metrics/xgb_drif_metrics:
#' unrounded floats; cmr_summary: 4-decimal fractions;
#' tom_metrics/rsc_metrics/mf_metrics/ev_metrics/mom_prepeak siblings:
#' 2-decimal-percent + 3-decimal sharpe; port_metrics: unrounded floats) is
#' comfortably tighter than this bound, so \code{tol} is NOT tuned
#' per-strategy -- one shared tolerance, sized to the worst case, keeps the
#' gate from ever needing a strategy-specific carve-out (the exact
#' anti-pattern \code{fail-loud-not-null.md} warns against: "Widening tol to
#' accommodate a real incoherence would defeat the entire purpose of this
#' slice").
#'
#' @param leaderboard Tibble with at least \code{strategy}, \code{period},
#'   \code{cagr}, \code{vol}, \code{sharpe}, \code{ann_rf} columns (the
#'   output of the \code{leaderboard} targets pipeline target).
#' @param tol Numeric. Coherence tolerance on \code{sharpe}. See the
#'   Tolerance section.
#' @return \code{TRUE} invisibly on success.
#' @noRd
check_leaderboard_sharpe_coherence <- function(leaderboard, tol = 0.02) {
  required_cols <- c("strategy", "period", "cagr", "vol", "sharpe", "ann_rf")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_sharpe_coherence() (S17) requires strategy, period, cagr, vol, sharpe, ann_rf."
    ))
  }

  # ── Assertion 1: ann_rf must never be NA -- fail-loud-not-null.md ────────
  # A row whose Sharpe coherence cannot be verified must ABORT, never pass
  # silently (#677 defect B: a missing risk-free rate was previously
  # indistinguishable from "legitimately zero").
  na_rf <- is.na(leaderboard$ann_rf)
  if (any(na_rf)) {
    offenders <- unique(paste(leaderboard$strategy[na_rf], leaderboard$period[na_rf], sep = " / "))
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(offenders),
        " row(s) with NA ann_rf -- Sharpe coherence cannot be verified (#677):"
      ),
      setNames(sprintf("  %s", offenders), rep("i", length(offenders))),
      "i" = paste0(
        "Every source metrics target that computes sharpe MUST also publish ",
        "the ann_rf it used -- see R/utils_metrics.R::sharpe_ratio_rf() and ",
        "the module-level 'ann_rf (#677 slice 4)' comment in R/plan_leaderboard.R."
      )
    ))
  }

  # ── Assertion 2: vol must be a checkable (positive, non-NA) denominator ──
  bad_vol <- is.na(leaderboard$vol) | leaderboard$vol <= 0
  if (any(bad_vol)) {
    offenders <- unique(paste(leaderboard$strategy[bad_vol], leaderboard$period[bad_vol], sep = " / "))
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(offenders),
        " row(s) with a non-positive or NA vol -- Sharpe coherence cannot be verified:"
      ),
      setNames(sprintf("  %s", offenders), rep("i", length(offenders))),
      "i" = "(cagr - ann_rf) / vol is undefined when vol is 0 or NA."
    ))
  }

  # ── Assertion 3: sharpe == (cagr - ann_rf) / vol, within rounding tol ────
  computed <- (leaderboard$cagr - leaderboard$ann_rf) / leaderboard$vol
  diff <- abs(leaderboard$sharpe - computed)
  # An NA sharpe alongside checkable cagr/vol/ann_rf is itself an
  # incoherence -- Inf so it is caught below, never silently excluded.
  diff[is.na(leaderboard$sharpe)] <- Inf

  bad <- diff > tol
  if (any(bad)) {
    msgs <- sprintf(
      "  %s / %s -- sharpe = %s, (cagr - ann_rf) / vol = %s, diff = %s",
      leaderboard$strategy[bad], leaderboard$period[bad],
      format(leaderboard$sharpe[bad], digits = 4),
      format(computed[bad], digits = 4),
      format(diff[bad], digits = 3)
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard sharpe is incoherent with cagr/vol/ann_rf in ",
        sum(bad), " place(s) (tol = ", tol, "), #677:"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "sharpe must equal (cagr - ann_rf) / vol -- check the offending ",
        "strategy's source metrics target and its .norm_* helper in ",
        "R/plan_leaderboard.R for a formula or unit-conversion bug."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert every leaderboard strategy has a declared observation periodicity
#' for the detection-power diagnostic (S19)
#'
#' Guards against a NEW instance of the fail-loud-not-null.md defect class
#' (#637/#640/#641/#643): `STRATEGY_OBS_ANN_FACTOR` (R/plan_leaderboard.R)
#' declares each strategy's native return periodicity (12 = monthly,
#' 252 = daily) so `historicaldata::hd_detection_power()` converts each
#' row's annualised `sharpe` into the correct per-period effect size. If a
#' new strategy is added to the leaderboard without a matching row in
#' `STRATEGY_OBS_ANN_FACTOR`, the join in the `leaderboard` target would
#' silently produce NA `detection_min_n_years`/`detection_underpowered`
#' forever -- indistinguishable from "checked, adequately powered" unless
#' this gate catches the gap at pipeline time.
#'
#' @param leaderboard Tibble with a `strategy` column (the output of the
#'   `leaderboard` target).
#' @param obs_ann_factor_tbl Tibble with a `strategy` column --
#'   `STRATEGY_OBS_ANN_FACTOR` (R/plan_leaderboard.R).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_detection_power_coverage <- function(leaderboard, obs_ann_factor_tbl) {
  if (!"strategy" %in% names(leaderboard)) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing required column: strategy.",
      "i" = "check_leaderboard_detection_power_coverage() (S19) requires a strategy column."
    ))
  }
  if (!"strategy" %in% names(obs_ann_factor_tbl)) {
    cli::cli_abort(c(
      "x" = "obs_ann_factor_tbl is missing required column: strategy.",
      "i" = "check_leaderboard_detection_power_coverage() (S19) requires STRATEGY_OBS_ANN_FACTOR's strategy column."
    ))
  }

  all_strategies <- unique(leaderboard$strategy)
  missing <- setdiff(all_strategies, obs_ann_factor_tbl$strategy)

  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        length(missing), " leaderboard strategy/strategies have no declared ",
        "observation periodicity for the detection-power diagnostic (#711):"
      ),
      setNames(sprintf("  %s", missing), rep("i", length(missing))),
      "i" = paste0(
        "Add a row to STRATEGY_OBS_ANN_FACTOR (R/plan_leaderboard.R) with ",
        "the strategy's true periods-per-year (12 = monthly, 252 = daily) ",
        "and a source citation, verified against its calc_metrics()/",
        "compute_*() annualisation."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert every positive-Sharpe leaderboard row has a detection-power verdict
#' (S20)
#'
#' Closes the NA hole #726 found in the detection-power diagnostic
#' (\code{.detection_diag_row()}, R/plan_leaderboard.R, #711 Gap 1): that
#' function returns NA for \code{detection_min_n_years}/
#' \code{detection_underpowered} through THREE distinct paths -- (a)
#' \code{sharpe} is NA or non-positive (the one-sided test has no positive
#' effect to detect -- excluded from this gate by construction, since it
#' only inspects rows with \code{sharpe > 0}), (b) \code{months} is NA or
#' \code{< 2} (an unusable sample length), or (c)
#' \code{historicaldata::hd_detection_power()} itself errors inside the
#' \code{tryCatch}. \code{check_leaderboard_detection_power_coverage()} (S19,
#' above) only guards the INPUT to this diagnostic -- that every strategy has
#' a declared row in \code{STRATEGY_OBS_ANN_FACTOR} -- not that the
#' diagnostic actually produced a value. Risk State passed S19 (it IS in
#' \code{STRATEGY_OBS_ANN_FACTOR}, declared 252) while still landing on path
#' (b) forever, because \code{rsc_metrics} never carried a \code{months}
#' column at all until #726 item 3's fix to \code{calc_metrics()}
#' (R/plan_risk_state.R) -- exactly the \code{fail-loud-not-null.md} pattern
#' of a guard scoped to the input that failed last time rather than to the
#' property actually wanted: "every positive-Sharpe row has a detection
#' verdict."
#'
#' A second, independent assertion (per #726 item 4, widened by #728 items
#' 1+2) covers the multiple-testing-corrected columns
#' \code{detection_min_n_years_mt}/\code{detection_underpowered_mt}
#' (alpha = 0.05 / \code{k_eff_leaderboard} instead of the single-test
#' alpha = 0.05): this is only checked for rows where
#' \code{k_eff_leaderboard} is itself usable (non-NA and >= 1) -- see the
#' \code{.detection_diag_row()} comment in R/plan_leaderboard.R for why
#' \code{k_eff_leaderboard} is deliberately NA for some strategies today (it
#' is populated for the 16 strategies in
#' \code{STRAT_RETURNS_WIDE_CODES}, R/plan_strategy_correlation.R -- up from
#' 11 after #728 and 4 before it (#733 folded in the five daily-frequency
#' strategies via monthly resampling) -- and NA for the one remaining
#' genuine, documented exclusion on that constant: PSO Optimal, a linear
#' combination of already-included series), which is an explicit, documented
#' default per
#' fail-loud-not-null.md's Required Pattern item 2, not something this gate
#' treats as a defect. This column was named \code{k_eff_strat} before
#' #728; it was renamed alongside the scope widening so the family-scoped
#' and leaderboard-wide counts cannot be confused (see
#' \code{k_eff_family}/\code{k_eff_leaderboard} in
#' R/plan_leaderboard.R's \code{strat_deflated_sharpe}).
#'
#' Both assertions name the offending \code{strategy}/\code{period} pairs and
#' state which NA path applies, per fail-loud-not-null.md's requirement that
#' an aborting message name the offending value and the field it came from --
#' "some rows are NA" is not an acceptable message on its own.
#'
#' @param leaderboard Tibble with at least \code{strategy}, \code{period},
#'   \code{sharpe}, \code{months}, \code{detection_min_n_years},
#'   \code{detection_underpowered}, \code{detection_min_n_years_mt},
#'   \code{detection_underpowered_mt}, \code{k_eff_leaderboard} columns (the
#'   output of the \code{leaderboard} target).
#' @return \code{TRUE} invisibly on success.
#' @noRd
check_leaderboard_detection_power_values <- function(leaderboard) {
  required_cols <- c(
    "strategy", "period", "sharpe", "months",
    "detection_min_n_years", "detection_underpowered",
    "detection_min_n_years_mt", "detection_underpowered_mt", "k_eff_leaderboard"
  )
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = paste0(
        "check_leaderboard_detection_power_values() (S20) requires strategy, ",
        "period, sharpe, months, detection_min_n_years, detection_underpowered, ",
        "detection_min_n_years_mt, detection_underpowered_mt, k_eff_leaderboard."
      )
    ))
  }

  positive <- !is.na(leaderboard$sharpe) & leaderboard$sharpe > 0

  # ── Assertion 1: single-test verdict must be non-NA for every positive-
  # Sharpe row -- the property #726 actually wants, not merely the S19 input
  # check. Names which of paths (b)/(c) is responsible for each offender.
  single_missing <- positive &
    (is.na(leaderboard$detection_min_n_years) | is.na(leaderboard$detection_underpowered))

  if (any(single_missing)) {
    idx <- which(single_missing)
    months_bad <- is.na(leaderboard$months[idx]) | leaderboard$months[idx] < 2
    reason <- ifelse(
      months_bad,
      "months is NA or < 2 (path b: unusable sample length)",
      paste0(
        "hd_detection_power() produced no value despite a usable months (path c: ",
        "the tryCatch in R/plan_leaderboard.R's .detection_diag_row() caught an error)"
      )
    )
    offenders <- sprintf(
      "  %s / %s -- sharpe = %s, months = %s -- %s",
      leaderboard$strategy[idx], leaderboard$period[idx],
      format(leaderboard$sharpe[idx], digits = 3),
      ifelse(is.na(leaderboard$months[idx]), "NA", format(leaderboard$months[idx], digits = 4)),
      reason
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(idx),
        " row(s) with sharpe > 0 but no detection-power verdict (#726):"
      ),
      setNames(offenders, rep("i", length(offenders))),
      "i" = paste0(
        "check_leaderboard_detection_power_values() (S20) requires every ",
        "positive-Sharpe row to have a non-NA detection_min_n_years/",
        "detection_underpowered -- fix the offending strategy's source ",
        "metrics target (path b: publish a real months/n_days/n_obs column) ",
        "or investigate the hd_detection_power() error (path c)."
      )
    ))
  }

  # ── Assertion 2: multiple-testing-corrected verdict must be non-NA
  # wherever k_eff_leaderboard is itself usable (#726 item 4, #728 items 1+2).
  mt_applicable <- positive & !is.na(leaderboard$k_eff_leaderboard) & leaderboard$k_eff_leaderboard >= 1
  mt_missing <- mt_applicable &
    (is.na(leaderboard$detection_min_n_years_mt) | is.na(leaderboard$detection_underpowered_mt))

  if (any(mt_missing)) {
    idx <- which(mt_missing)
    offenders <- sprintf(
      "  %s / %s -- sharpe = %s, k_eff_leaderboard = %s",
      leaderboard$strategy[idx], leaderboard$period[idx],
      format(leaderboard$sharpe[idx], digits = 3),
      format(leaderboard$k_eff_leaderboard[idx], digits = 4)
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(idx),
        " row(s) with sharpe > 0 and a usable k_eff_leaderboard but no ",
        "multiple-testing-corrected detection-power verdict (#726 item 4):"
      ),
      setNames(offenders, rep("i", length(offenders))),
      "i" = paste0(
        "check_leaderboard_detection_power_values() (S20) requires ",
        "detection_min_n_years_mt/detection_underpowered_mt to be non-NA ",
        "whenever k_eff_leaderboard is non-NA and >= 1 -- see the ",
        "alpha = 0.05 / keff tryCatch in R/plan_leaderboard.R's ",
        ".detection_diag_row()."
      )
    ))
  }

  invisible(TRUE)
}


#' Declared exemptions from deflated-Sharpe / K_eff coverage (S21, #728 item
#' 4, narrowed by #733)
#'
#' Per \code{.claude/rules/fail-loud-not-null.md}: "the absence of a reason
#' is what fails". A leaderboard strategy with a positive Full-Period Sharpe
#' but no \code{deflated_sharpe}/\code{dsr_pvalue}/\code{k_eff_leaderboard}
#' is either a genuine, documented data-coverage limit (declared here, with
#' a written reason) or a bug that \code{check_leaderboard_deflated_sharpe_coverage()}
#' (S21, below) must abort on -- never a silent NA that looks identical to
#' the exempted case.
#'
#' #728 items 1+2 widened \code{STRAT_RETURNS_WIDE_CODES} to 11 of 17
#' strategies, leaving six exemptions here: the five daily-frequency
#' strategies (CMR, OLMAR-1, TOM, Risk State, Avoid Worst) plus PSO Optimal.
#' #733 folds the five daily strategies INTO \code{STRAT_RETURNS_WIDE_CODES}
#' by monthly-resampling their return series (see
#' \code{.resample_daily_to_monthly()}, R/plan_strategy_correlation.R) --
#' they now have real \code{deflated_sharpe}/\code{dsr_pvalue}/
#' \code{k_eff_leaderboard} verdicts (computed at their own native
#' ann_factor = 252, see R/plan_leaderboard.R's \code{strat_deflated_sharpe}),
#' so they are removed from this table. PSO Optimal is the ONE remaining
#' exemption -- exactly \code{STRAT_RETURNS_WIDE_CODES}'s complement
#' (R/plan_strategy_correlation.R) among the 17 leaderboard strategies -- see
#' that constant's comment for the underlying reasoning; the \code{reason}
#' column here restates it so this table is self-contained without a second
#' file open.
#' @noRd
DEFLATED_SHARPE_EXEMPTIONS <- tibble::tibble(
  strategy = c("PSO Optimal"),
  reason = c(
    paste0(
      "PSO Optimal is not an independent data source: it is ",
      "port_optimal_weights %*% c(stk_max, stk_drif, fac_max, fac_drif) (the ",
      "'PSO Optimal' block in R/plan_leaderboard.R's leaderboard target) -- a ",
      "linear combination of four series already covered. Including a ",
      "near-collinear combination alongside its own components adds no ",
      "independent information and risks a near-singular correlation matrix ",
      "in hd_strat_keff_vertox()'s Cholesky step."
    )
  )
)


#' Assert deflated-Sharpe / K_eff coverage for every positive-Sharpe
#' leaderboard strategy, or a documented exemption (S21, #728 item 4)
#'
#' Follows the same shape as \code{check_leaderboard_detection_power_values()}
#' (S20) above: a positive Full-Period Sharpe with no
#' \code{deflated_sharpe}/\code{dsr_pvalue}/\code{k_eff_leaderboard} verdict
#' either has a written reason in \code{DEFLATED_SHARPE_EXEMPTIONS} above, or
#' the gate aborts naming the offending strategy and column. #728 found that
#' \code{deflated_sharpe} covered only 4 of 17 strategies and, of the 8
#' strategies claiming a positive Full-Period Sharpe, only 1 (Factor DRIF)
#' had any multiple-testing correction at all -- the wrong seven were
#' missing (the ones a reader is most likely to act on). #728 items 1+2
#' widened coverage to 11 of 17, and #733 widened it further to 16 of 17 by
#' folding in the five daily-frequency strategies via monthly resampling
#' (R/plan_strategy_correlation.R's STRAT_RETURNS_WIDE_CODES); this gate is
#' what keeps that count from silently regressing back down.
#'
#' Scoped to \code{period == "Full Period"}: \code{deflated_sharpe} is a
#' full-sample statistic broadcast to every period row (see the "Deflated
#' Sharpe" join comment in R/plan_leaderboard.R's \code{leaderboard} target),
#' so checking every period row would just re-check the same value once per
#' partition and produce misleading per-period "offenders" for what is
#' actually a single per-strategy gap.
#'
#' Deliberately scoped to the \code{deflated_sharpe}/\code{dsr_pvalue}/
#' \code{k_eff_leaderboard} family -- the columns #728 items 1+2 directly
#' fix -- not the full set of "rigour columns" named in #728's issue text
#' (\code{hac_sharpe}, \code{wf_corr}, \code{sharpe_ci_lo}/\code{_hi},
#' \code{incremental_sharpe}, \code{ssr} each have their own, different
#' coverage story and would need their own exemption audit; out of scope
#' for this gate, flagged as follow-up work in the #728 PR report).
#'
#' @param leaderboard Tibble with at least \code{strategy}, \code{period},
#'   \code{sharpe}, \code{deflated_sharpe}, \code{dsr_pvalue},
#'   \code{k_eff_leaderboard} columns (the output of the \code{leaderboard}
#'   target).
#' @param exemptions Tibble with \code{strategy}/\code{reason} columns --
#'   \code{DEFLATED_SHARPE_EXEMPTIONS} above.
#' @return \code{TRUE} invisibly on success.
#' @noRd
check_leaderboard_deflated_sharpe_coverage <- function(leaderboard, exemptions = DEFLATED_SHARPE_EXEMPTIONS) {
  required_cols <- c("strategy", "period", "sharpe", "deflated_sharpe", "dsr_pvalue", "k_eff_leaderboard")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = paste0(
        "check_leaderboard_deflated_sharpe_coverage() (S21) requires strategy, ",
        "period, sharpe, deflated_sharpe, dsr_pvalue, k_eff_leaderboard."
      )
    ))
  }
  if (!all(c("strategy", "reason") %in% names(exemptions))) {
    cli::cli_abort(c(
      "x" = "exemptions table is missing required column(s): strategy, reason.",
      "i" = "check_leaderboard_deflated_sharpe_coverage() (S21) requires DEFLATED_SHARPE_EXEMPTIONS' strategy/reason columns."
    ))
  }

  full_period <- leaderboard$period == "Full Period"
  positive <- full_period & !is.na(leaderboard$sharpe) & leaderboard$sharpe > 0

  missing_dsr <- positive &
    (is.na(leaderboard$deflated_sharpe) | is.na(leaderboard$dsr_pvalue) | is.na(leaderboard$k_eff_leaderboard))

  if (any(missing_dsr)) {
    idx <- which(missing_dsr)
    exempted <- leaderboard$strategy[idx] %in% exemptions$strategy
    offender_idx <- idx[!exempted]

    if (length(offender_idx) > 0L) {
      offenders <- sprintf(
        "  %s / %s -- sharpe = %s (no declared exemption in DEFLATED_SHARPE_EXEMPTIONS)",
        leaderboard$strategy[offender_idx], leaderboard$period[offender_idx],
        format(leaderboard$sharpe[offender_idx], digits = 3)
      )
      cli::cli_abort(c(
        "x" = paste0(
          "Leaderboard has ", length(offender_idx),
          " Full Period row(s) with sharpe > 0 but no deflated_sharpe/",
          "dsr_pvalue/k_eff_leaderboard verdict AND no declared exemption (#728 item 4):"
        ),
        setNames(offenders, rep("i", length(offenders))),
        "i" = paste0(
          "check_leaderboard_deflated_sharpe_coverage() (S21) requires every ",
          "positive-Sharpe Full Period row to have a non-NA deflated_sharpe/",
          "dsr_pvalue/k_eff_leaderboard verdict, or a written reason in ",
          "DEFLATED_SHARPE_EXEMPTIONS (R/plan_qa_gates.R) -- fix the offending ",
          "strategy's coverage in STRAT_RETURNS_WIDE_CODES ",
          "(R/plan_strategy_correlation.R) or add a documented exemption. ",
          "Per fail-loud-not-null.md, the absence of a reason is what fails, ",
          "not the NA itself."
        )
      ))
    }
  }

  invisible(TRUE)
}


#' Assert leaderboard `net_cagr`, `cvar_95`, and `credible` are jointly NA or
#' jointly non-NA per row (S23, fail-loud-not-null.md)
#'
#' \code{net_cagr}, \code{cvar_95}, and \code{credible} are all produced in a
#' single pass by \code{calc_cost_metrics()} (R/plan_leaderboard.R) from the
#' SAME \code{cost_rows} join -- one matching \code{cost_rows} row (built by
#' \code{slice_portfolio()} for the 5 core strategies plus PSO Optimal)
#' produces all three columns at once; a strategy/period \code{cost_rows}
#' never covers leaves all three NA together via the
#' \code{all_metrics |> left_join(cost_rows, by = c("strategy", "period"))}
#' join. \code{docs/leaderboard.qmd}'s Rankings table renders exactly this
#' shared NA-ness as a single "not computed" verdict across all three
#' columns (the "#637 follow-up" comment there) -- this gate is what keeps
#' that assumption from silently going stale.
#'
#' Guards the \code{.claude/rules/fail-loud-not-null.md} defect class
#' (#637/#640/#641/#643): a future change that extends \code{cost_rows} (or
#' adds a second source) to populate ONE of these three columns for a new
#' strategy/period without the other two would let
#' \code{docs/leaderboard.qmd} render an internally inconsistent row -- e.g.
#' a "Credible: yes" verdict with no Net CAGR value to have been judged
#' credible about, or a Net CAGR figure with no CVaR 95% alongside it. The
#' rule's Required Pattern item 5 ("Add a QA gate, not just a test") is what
#' this target answers; the joint-presence check itself is exercised
#' directly against synthetic fixtures in
#' tests/testthat/test-leaderboard-cost-metrics-coverage.R, mirroring
#' check_leaderboard_sharpe_coherence() (S17)'s shape.
#'
#' Unlike S17/S20/S21, this check is deliberately NOT scoped to
#' \code{period == "Full Period"}: \code{cost_rows} produces a row per
#' Training/Testing/Holdout/Full Period slice for every strategy it covers
#' (\code{slice_portfolio()}), so the joint-presence property must hold on
#' every period row, not just the full-sample one.
#'
#' @param leaderboard Tibble with at least \code{strategy}, \code{period},
#'   \code{net_cagr}, \code{cvar_95}, \code{credible} columns (the output of
#'   the \code{leaderboard} target).
#' @return \code{TRUE} invisibly on success.
#' @noRd
check_leaderboard_cost_metrics_joint_presence <- function(leaderboard) {
  required_cols <- c("strategy", "period", "net_cagr", "cvar_95", "credible")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_cost_metrics_joint_presence() (S23) requires strategy, period, net_cagr, cvar_95, credible."
    ))
  }

  has_net_cagr <- !is.na(leaderboard$net_cagr)
  has_cvar_95  <- !is.na(leaderboard$cvar_95)
  has_credible <- !is.na(leaderboard$credible)

  disagree <- !(has_net_cagr == has_cvar_95 & has_cvar_95 == has_credible)

  if (any(disagree)) {
    idx <- which(disagree)
    offenders <- sprintf(
      "  %s / %s -- net_cagr %s, cvar_95 %s, credible %s",
      leaderboard$strategy[idx], leaderboard$period[idx],
      ifelse(has_net_cagr[idx], "present", "NA"),
      ifelse(has_cvar_95[idx],  "present", "NA"),
      ifelse(has_credible[idx], "present", "NA")
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has ", length(idx),
        " row(s) where net_cagr/cvar_95/credible disagree on presence -- ",
        "these three columns come from the SAME cost_rows join and must be ",
        "jointly NA or jointly non-NA:"
      ),
      setNames(offenders, rep("i", length(offenders))),
      "i" = paste0(
        "check_leaderboard_cost_metrics_joint_presence() (S23) guards the ",
        "fail-loud-not-null.md defect class (#637/#640/#641/#643): if one of ",
        "these three columns is populated for a strategy/period without the ",
        "other two, docs/leaderboard.qmd's single 'not computed' verdict for ",
        "Credible/Net CAGR/CVaR 95% no longer matches the underlying data. ",
        "Check calc_cost_metrics() and the cost_rows join in ",
        "R/plan_leaderboard.R's leaderboard target."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert the package-source digest mechanism is actually tracking something
#' (S22, #753)
#'
#' `pkg_source_files`/`pkg_source_digest` (docs/_targets.R) are the tracked
#' foundation the #753 fix rests on: `pkg_source_files` is a
#' \code{format = "file"} target, so `targets` invalidates it on real
#' content changes under `packages/historicaldata/R` -- independent of
#' `pkgload::load_all()`, which is exactly the mechanism the original defect
#' slipped past. This gate does NOT (cannot -- see below) detect cross-run
#' staleness in OTHER targets; it only guards against the digest mechanism
#' itself going quietly vacuous, e.g. a future refactor renames or moves
#' `packages/historicaldata/R` and `pkg_source_files` silently returns
#' `character(0)` -- a digest of nothing is still "a digest", and every
#' target that references it would keep passing without ever being told the
#' floor moved.
#'
#' The REAL cross-run staleness check -- "did a known package-consuming
#' target get skipped in a run where the package source actually changed" --
#' cannot be expressed as a `targets` pipeline gate at all: `tar_meta()` and
#' `tar_progress()` are BOTH documented (and confirmed empirically, 2026-08-25
#' scratch pipeline) as unsupported when called on the store belonging to
#' the pipeline currently running --
#' \verb{Error: target <name> attempted to run targets::tar_meta() to during
#' a pipeline, which is unsupported...}. A gate in THIS file physically
#' cannot read "was some other target skipped this run" about its own
#' store. That check lives in scripts/check_pkg_staleness.R instead (run as
#' a build.sh step, after tar_make() has exited and the store is no longer
#' "the pipeline currently running") -- see that script's header comment for
#' the full design and the same empirical finding, with the exact error text.
#'
#' @param pkg_source_files Character vector -- the `pkg_source_files` target
#'   value (paths to every tracked package source file).
#' @param pkg_source_digest Character scalar -- the `pkg_source_digest`
#'   target value (a single hash string).
#' @param min_files Integer, minimum number of files expected. Default 10L
#'   is well under this package's actual R/ file count (62 at the time this
#'   gate was written) but well above zero -- catches "the file list came
#'   back empty or nearly so" without being brittle to normal file-count
#'   drift as the package grows.
#' @return `TRUE` invisibly on success.
#' @noRd
check_pkg_source_tracked <- function(pkg_source_files, pkg_source_digest, min_files = 10L) {
  if (!is.character(pkg_source_files) || length(pkg_source_files) < min_files) {
    cli::cli_abort(c(
      "x" = paste0(
        "pkg_source_files returned only ", length(pkg_source_files),
        " file(s) -- expected at least ", min_files, "."
      ),
      "i" = paste0(
        "check_pkg_source_tracked() (S22) guards the #753 staleness-detection ",
        "mechanism itself: if pkg_source_files ever silently returns few/no ",
        "files (e.g. packages/historicaldata/R was renamed or moved), ",
        "pkg_source_digest keeps producing A digest, just not one that ",
        "means anything -- and every downstream check built on it would ",
        "keep passing for the wrong reason. Confirm the ",
        "packages/historicaldata/R path in docs/_targets.R's pkg_source_files ",
        "target still points at the real package source directory."
      )
    ))
  }
  if (!is.character(pkg_source_digest) || length(pkg_source_digest) != 1L ||
      is.na(pkg_source_digest) || !nzchar(pkg_source_digest)) {
    cli::cli_abort(c(
      "x" = "pkg_source_digest is not a single non-empty string.",
      "i" = "check_pkg_source_tracked() (S22) requires a well-formed digest -- see R/plan_qa_gates.R for what this guards against."
    ))
  }
  invisible(TRUE)
}


#' Assert no numeric column in a published metrics tibble is entirely NA
#' (S26, #668)
#'
#' The property-based generalisation of the two hardcoded all-NA checks that
#' used to live in `check_leaderboard_coverage()` (`ssr`, `top5pct_share`,
#' #400) -- see #668 for the running tally of why per-instance gates keep
#' missing the NEXT column with the same defect: `ltr_subperiod$sharpe` was
#' `NA, NA, NA` since the target's inception (#677 defect B) because
#' `compute_sp_metrics()` referenced a `rf_ret` column `ltr_portfolio` never
#' had -- `df$missing` returns `NULL` in R, and `mean(NULL, na.rm = TRUE)`
#' returns `NA`, so the whole column silently became `NA`. The check that
#' would have caught it already existed (the two hardcoded blocks this
#' function replaces); it was scoped to two column NAMES rather than to the
#' PROPERTY "no published metric column has zero non-NA values", so it
#' could not see the third column on a target it had never heard of.
#'
#' Checks every column for which `is.numeric()` is `TRUE`. Character,
#' logical, and Date/POSIXct columns are excluded -- they carry
#' vocabularies, flags, and calendar values, not metrics, and "entirely NA"
#' is not a meaningful defect signal for a column that is allowed to be
#' entirely `FALSE`, entirely one label, or entirely absent by design (a
#' logical flag column being all-`FALSE` is a legitimate state; an all-NA
#' NUMERIC column, by contrast, means its source computation never actually
#' ran for any row).
#'
#' A column present in `exempt` is skipped entirely -- see the caller's own
#' exemption constant (e.g. `LEADERBOARD_ALL_NA_EXEMPT` below) for the
#' documented, narrow set of columns known to be legitimately all-NA under
#' some pipeline states. An empty or `NULL` `tbl` returns `TRUE` without
#' checking anything -- this mirrors the other S* gates' treatment of an
#' unpopulated upstream target as "nothing to check yet" rather than a
#' defect in its own right (that is a separate property, guarded elsewhere
#' e.g. by S7's strategy-coverage assertion).
#'
#' @param tbl A tibble; the published target being checked.
#' @param target_label Character scalar; the target's name, used verbatim
#'   in the abort message.
#' @param exempt Character vector of column names to skip. Default: none.
#' @return `TRUE` invisibly on success.
#' @noRd
check_no_all_na_numeric_columns <- function(tbl, target_label, exempt = character(0)) {
  if (is.null(tbl) || nrow(tbl) == 0L) {
    return(invisible(TRUE))
  }

  numeric_cols <- names(tbl)[vapply(tbl, is.numeric, logical(1L))]
  numeric_cols <- setdiff(numeric_cols, exempt)

  offenders <- Filter(function(col) all(is.na(tbl[[col]])), numeric_cols)

  if (length(offenders) > 0L) {
    msgs <- sprintf("  %s", offenders)
    cli::cli_abort(c(
      "x" = paste0(
        target_label, " has ", length(offenders),
        " numeric column(s) that are entirely NA:"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "A column with zero non-NA values across the whole ", target_label,
        " usually means its source computation never ran, or its output ",
        "was never actually wired into this target (#668 -- the ",
        "ltr_subperiod$sharpe all-NA-since-inception class, #677 defect B)."
      ),
      "i" = paste0(
        "If a column is legitimately expected to be all-NA under some ",
        "pipeline states, add it to this gate's exemption constant in ",
        "R/plan_qa_gates.R, with a documented reason -- do not silence the ",
        "gate by removing the check."
      )
    ))
  }

  invisible(TRUE)
}

#' Columns exempt from the leaderboard's S26 all-NA check
#'
#' Empty by design: every current leaderboard column that reaches
#' `is.numeric()` should have a real, non-NA value for at least one row once
#' the pipeline has actually run (a column that is genuinely 100% NA today
#' is exactly the defect class #668 targets). Add an entry here ONLY with a
#' documented, specific reason -- an undocumented addition defeats the
#' point of the gate the same way a per-instance check did.
#' @noRd
LEADERBOARD_ALL_NA_EXEMPT <- character(0)

#' Assert no numeric column in `leaderboard` is entirely NA (S26, #668)
#'
#' Thin wrapper around `check_no_all_na_numeric_columns()` -- see that
#' function's roxygen for the full rationale this gate replaces.
#'
#' @param leaderboard Tibble; the `leaderboard` target.
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_no_all_na_metric <- function(leaderboard) {
  check_no_all_na_numeric_columns(leaderboard, "leaderboard", LEADERBOARD_ALL_NA_EXEMPT)
}


#' Minimum effective breadth (n_eff) tolerated on any CMR date holding a
#' position (S27, #751 item F)
#'
#' Derived the same way \code{.HD_CMR_MIN_LEG_NAMES} (2, packages/
#' historicaldata/R/commodities_mean_reversion.R) already bounds the
#' TERCILE construction's leg size: a leg of fewer than 2 names is not a
#' diversified bet, it is a single name's return relabelled as a leg
#' return. Under \code{hd_commodity_mr_portfolio()}'s equal-weight tercile
#' legs, \code{n_eff == n_long + n_short} exactly whenever a position is
#' held (every held name carries identical \code{|weight|}, so the inverse
#' Herfindahl index collapses to a plain count) -- so the floor here is
#' \code{2 * .HD_CMR_MIN_LEG_NAMES = 4}, the same "2 names per side"
#' guarantee \code{hd_commodity_mr_portfolio()}'s own \code{min_total_names}
#' check already enforces via the position-count path. This gate checks the
#' SAME property independently, through the \code{n_eff} DIAGNOSTIC column
#' rather than the \code{n_long}/\code{n_short} construction path -- a
#' future change to the weighting scheme (e.g. a return to rank-weighting,
#' #751 item D, closed unmerged on #765 but not permanently foreclosed)
#' would make \code{n_eff} diverge from a plain headcount, at which point
#' this gate would be doing real, non-redundant work without any call-site
#' change.
#'
#' Numbered S27, not S24 or S26: this gate was originally added as S24, then
#' renumbered to S26 when #806/#668 landed S24 (check_stk_all_comparison_coverage)
#' and S25 (check_boot_monthly_returns_coverage) on \code{main} first. A
#' SECOND main-branch commit (#806/#668's own final landing, after a
#' concurrent renumber against #798) then independently took S26 for
#' \code{check_leaderboard_no_all_na_metric()} above -- so this gate is
#' renumbered again, to S27, rather than overwriting that one.
#'
#' @noRd
CMR_MIN_EFFECTIVE_BREADTH <- 4

#' Assert CMR effective breadth (n_eff) never falls below the minimum floor
#' on any date holding a position (S27, #751 item F)
#'
#' \code{n_eff} (the inverse Herfindahl index of normalised absolute
#' weight, \code{hd_commodity_mr_portfolio()}, packages/historicaldata/R/
#' commodities_mean_reversion.R) answers "how many independent bets is this
#' portfolio effectively making" -- the fundamental-law quantity #751's
#' body argues is closer to what matters than \code{held_frac} or a raw
#' position count (Grinold & Kahn; Ding & Martin 2017, cited in #751). This
#' gate salvages the diagnostic that was built (and its rank-weighted
#' rationale) on the now-closed #765 branch, wired here against the LIVE
#' tercile construction -- #751 item D (rank-weighting) was decided AGAINST
#' on #765; terciles remain the production construction.
#'
#' Checked on every date any of the three CMR lookback partitions
#' (\code{cmr_portfolio_1m}/\code{_3m}/\code{_6m}) holds a position
#' (\code{n_long + n_short > 0}): \code{n_eff} must be at least
#' \code{\link{CMR_MIN_EFFECTIVE_BREADTH}}. See that constant's roxygen for
#' the floor's derivation.
#'
#' @param cmr_portfolios Named list of CMR portfolio tibbles (one per
#'   lookback partition), each with columns \code{date}, \code{n_long},
#'   \code{n_short}, \code{n_eff}.
#' @return \code{TRUE} invisibly on success.
#' @noRd
check_cmr_effective_breadth <- function(cmr_portfolios) {
  required_cols <- c("date", "n_long", "n_short", "n_eff")
  combined <- purrr::map2(
    cmr_portfolios, names(cmr_portfolios),
    function(port, lookback) {
      missing_cols <- setdiff(required_cols, names(port))
      if (length(missing_cols) > 0L) {
        cli::cli_abort(c(
          "x" = paste0(
            "CMR portfolio {.val {lookback}} is missing ",
            "{length(missing_cols)} required column(s): {missing_cols}."
          ),
          "i" = "check_cmr_effective_breadth() (S27) requires date, n_long, n_short, n_eff."
        ))
      }
      dplyr::mutate(port[, required_cols], lookback = lookback)
    }
  ) |>
    dplyr::bind_rows()

  held      <- combined |> dplyr::filter(.data$n_long + .data$n_short > 0L)
  offenders <- held |> dplyr::filter(.data$n_eff < CMR_MIN_EFFECTIVE_BREADTH)

  if (nrow(offenders) > 0L) {
    worst <- offenders[order(offenders$n_eff), , drop = FALSE][1L, ]
    cli::cli_abort(c(
      "x" = paste0(
        "CMR effective breadth (n_eff) fell below the minimum floor (",
        CMR_MIN_EFFECTIVE_BREADTH, ") on ", nrow(offenders),
        " date(s) holding a position."
      ),
      "i" = paste0(
        "Worst offender: ", worst$lookback, " ", format(worst$date),
        " -- n_eff=", round(worst$n_eff, 3),
        ", n_long=", worst$n_long, ", n_short=", worst$n_short, "."
      ),
      "i" = paste0(
        "check_cmr_effective_breadth() (S27, #751 item F) guards the ",
        "fundamental-law breadth floor -- see CMR_MIN_EFFECTIVE_BREADTH's ",
        "roxygen (R/plan_qa_gates.R) for the derivation."
      )
    ))
  }

  invisible(TRUE)
}


#' Mapping from strat_returns_daily_native's code_names to STRATEGY_OBS_
#' ANN_FACTOR's display `strategy` labels (S28, #719 Layer 3)
#'
#' `strat_returns_daily_native` (R/plan_strategy_correlation.R) keys its
#' list by the STRAT_RETURNS_WIDE_CODES code_name vocabulary ("cmr",
#' "olmar_1", "tom", "risk_state", "avoid_worst" -- note "olmar_1" there,
#' matching that file's own documented vocabulary, vs "olmar" in
#' `hd_strategy_names_tbl()`). `STRATEGY_OBS_ANN_FACTOR`
#' (R/plan_leaderboard.R) keys by the display `strategy` column
#' (`short_name`). This table bridges the two so `check_strategy_
#' periodicity_reconciliation()` below can look up each series' declared
#' `ann_factor` without a third hand-maintained copy of the strategy roster.
#'
#' @noRd
PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY <- c(
  cmr         = "CMR",
  olmar_1     = "OLMAR-1",
  tom         = "TOM",
  risk_state  = "Risk State",
  avoid_worst = "Avoid Worst"
)

#' Known, documented periodicity exceptions for the S28 coverage gate
#'
#' #738 found `cmr_portfolio_1m`/`_3m`/`_6m` (the source of
#' `strat_returns_daily_native`'s `cmr` entry) mixes ~12 obs/year before
#' 2000 with ~255 obs/year after, declared daily throughout -- the SAME
#' defect class this gate exists to catch, already discovered, already
#' tracked on #738, and already staged to `"warn"` at CMR's own production
#' call sites (`.compute_cmr_metrics()`'s `periodicity_check` argument,
#' R/plan_commodities_mean_reversion.R). Re-aborting the pipeline on a
#' known, open issue here would not surface new information -- it would
#' just block every build until #738 is separately resolved.
#'
#' Per fail-loud-not-null.md Required Pattern 2 (an explicit, documented
#' default, with a test asserting it holds -- see
#' tests/testthat/test-strategy-periodicity-reconciliation.R), this table
#' lists every `code_name` allowed to run in `"warn"` mode instead of
#' `"abort"`, with the issue tracking its resolution. Any `code_name` NOT
#' listed here runs in full `"abort"` mode -- this is an exemption list, not
#' a default, and adding a row to it requires a cited, open issue.
#'
#' @noRd
PERIODICITY_RECONCILIATION_EXEMPT <- tibble::tibble(
  code_name = c("cmr"),
  reason = c(paste(
    "Mixed-frequency series (12 obs/yr pre-2000, ~255 obs/yr after),",
    "declared daily throughout -- tracked and staged to warn-mode at",
    "source (#738); re-aborting here duplicates a known, open issue",
    "rather than catching a new one."
  ))
)

#' Reconcile each daily-native strategy's declared ann_factor against its
#' own observed date frequency (S28, #719 Layer 3)
#'
#' The pipeline-wide coverage backstop #719 Layer 3 option (a) asks for:
#' "A QA target comparing each strategy's declared ann_factor against the
#' median gap between its own observation dates ... covers everything at
#' once." `.assert_cmr_ann_factor()` (R/plan_commodities_mean_reversion.R,
#' #717/#720/#738) already does this for CMR, at the point CMR's own
#' `.compute_cmr_metrics()` receives `ann_factor` -- but that guard fires
#' only if a new call site remembers to call it, exactly the "guard scoped
#' to the known path" gap fail-loud-not-null.md Required Pattern 5 warns
#' about. This gate is the backstop: it does not rely on any individual
#' strategy's own code calling anything, it reconciles the DATA independent
#' of whether a guard was wired in.
#'
#' Scope: the five DAILY-native strategies (CMR, OLMAR-1, TOM, Risk State,
#' Avoid Worst) collected in one place by `strat_returns_daily_native`
#' (R/plan_strategy_correlation.R, #733) -- this is the one existing target
#' where a strategy's own per-observation dates are available centrally.
#' The eleven MONTHLY-native strategies are NOT covered by this gate: each
#' is built inside its own plan file and collapses onto a monthly `ym`
#' spine (`format(date, "%Y-%m")`) before reaching any shared target, which
#' structurally forecloses the specific defect shape CMR hit (a `nrow()` of
#' daily rows fed straight into `ann_factor = 12`) -- there is no `ym`-spine
#' analogue of "6852 rows silently treated as 6852 months". A monthly
#' strategy could still in principle carry a genuine periodicity error (its
#' own upstream date derivation is wrong), but that is a different defect
#' shape this gate does not claim to catch; extending centralised raw-date
#' collection to the monthly cohort is a documented follow-up, not silently
#' assumed to be covered here.
#'
#' Uses `PERIODICITY_RECONCILIATION_EXEMPT` to run known, already-tracked
#' issues (currently only CMR/#738) in `"warn"` mode instead of `"abort"` --
#' see that table's roxygen. Every other strategy runs in full `"abort"`
#' mode: a NEW mismatch here is a NEW defect, not a known one.
#'
#' @param daily_native Named list of tibbles, one per daily-native strategy,
#'   each with `date` and `ret` columns -- `strat_returns_daily_native`
#'   (R/plan_strategy_correlation.R).
#' @param obs_ann_factor_tbl Tibble with `strategy`, `obs_ann_factor`
#'   columns -- `STRATEGY_OBS_ANN_FACTOR` (R/plan_leaderboard.R).
#' @param code_to_strategy Named character vector mapping
#'   `names(daily_native)` to `obs_ann_factor_tbl$strategy`. Defaults to
#'   `PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY`.
#' @param exempt_tbl Tibble with `code_name`, `reason` columns naming known,
#'   documented exceptions run in `"warn"` mode instead of `"abort"`.
#'   Defaults to `PERIODICITY_RECONCILIATION_EXEMPT`.
#' @return `TRUE` invisibly on success (including when the only failures
#'   were exempted down to warnings).
#' @noRd
check_strategy_periodicity_reconciliation <- function(
    daily_native, obs_ann_factor_tbl,
    code_to_strategy = PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY,
    exempt_tbl = PERIODICITY_RECONCILIATION_EXEMPT) {

  required_obs_cols <- c("strategy", "obs_ann_factor")
  missing_obs_cols <- setdiff(required_obs_cols, names(obs_ann_factor_tbl))
  if (length(missing_obs_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "obs_ann_factor_tbl is missing {length(missing_obs_cols)} required column(s): {missing_obs_cols}.",
      "i" = "check_strategy_periodicity_reconciliation() (S28) requires STRATEGY_OBS_ANN_FACTOR's strategy, obs_ann_factor columns."
    ))
  }

  code_names <- names(daily_native)
  unmapped <- setdiff(code_names, names(code_to_strategy))
  if (length(unmapped) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        length(unmapped), " strat_returns_daily_native entr",
        if (length(unmapped) == 1L) "y has" else "ies have",
        " no PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY mapping:"
      ),
      setNames(sprintf("  %s", unmapped), rep("i", length(unmapped))),
      "i" = "Add a row to PERIODICITY_RECONCILIATION_CODE_TO_STRATEGY (R/plan_qa_gates.R)."
    ))
  }

  errors  <- character(0)
  exempt_used <- character(0)

  for (cn in code_names) {
    strategy <- code_to_strategy[[cn]]
    declared_row <- obs_ann_factor_tbl[obs_ann_factor_tbl$strategy == strategy, , drop = FALSE]
    if (nrow(declared_row) != 1L) {
      errors <- c(errors, sprintf(
        "%s (code_name %s): no matching row in STRATEGY_OBS_ANN_FACTOR for strategy %s",
        strategy, cn, strategy
      ))
      next
    }
    declared <- declared_row$obs_ann_factor[[1]]

    is_exempt <- cn %in% exempt_tbl$code_name
    mode <- if (is_exempt) "warn" else "abort"

    caught <- tryCatch({
      .assert_periodicity_reconciles(
        dates = daily_native[[cn]]$date,
        ann_factor = declared,
        label = strategy,
        on_violation = mode
      )
      NULL
    }, error = function(e) conditionMessage(e))

    if (!is.null(caught)) {
      errors <- c(errors, sprintf("%s (code_name %s): %s", strategy, cn, caught))
    } else if (is_exempt) {
      exempt_used <- c(exempt_used, strategy)
    }
  }

  if (length(errors) > 0L) {
    cli::cli_abort(c(
      "x" = paste0(
        length(errors), " strategy/strategies failed periodicity reconciliation ",
        "(S28, #719 Layer 3):"
      ),
      setNames(sprintf("  %s", errors), rep("i", length(errors))),
      "i" = paste0(
        "A declared ann_factor must match the OBSERVED frequency of the ",
        "series it annualises -- see .claude/rules/fail-loud-not-null.md ",
        "Required Pattern 5 and issue #719. Known, documented exceptions go ",
        "in PERIODICITY_RECONCILIATION_EXEMPT (R/plan_qa_gates.R), not a ",
        "code change here."
      )
    ))
  }

  invisible(TRUE)
}


#' Assert leaderboard metrics are not PHYSICALLY IMPOSSIBLE (S29, #719
#' Layer 1 -- Red tier)
#'
#' #719's "traffic light" plausibility design has three tiers: red
#' (physically impossible -- abort), amber (peer-relative outlier --
#' requires acknowledgement, see `check_leaderboard_plausibility_amber()`
#' below), green (within band -- silent). This is the RED tier, checked
#' exactly as #719 specifies it:
#'
#' \itemize{
#'   \item `vol <= 0` -- a return series with zero or negative annualised
#'     volatility is not a real return series.
#'   \item `max_dd < -1` -- a drawdown cannot exceed -100% of peak equity.
#'   \item `abs(sharpe) > 5` -- an annualised Sharpe this extreme has never
#'     been documented for a real, investable strategy over any meaningful
#'     sample (see #726's detection-power finding that even a 0.62 Sharpe
#'     needs 16 years of data to be distinguishable from zero -- a Sharpe
#'     of 5 implies an effect size no real market has produced).
#'   \item implied years (`months / obs_ann_factor`) `> 100` -- #717's own
#'     defect produced exactly this shape: `n / ann_factor` = 565.75
#'     "years" from a 27-year series wrongly annualised.
#' }
#'
#' Two of these four (`vol <= 0`, `max_dd < -1`) overlap the RANGE already
#' checked by `check_leaderboard_metric_ranges()` (S9) -- deliberately: S9
#' is a wide, generous SCALE-ERROR gate (bounds `vol` in `[0, 2]`, `max_dd`
#' in `[-1, 0]`, built to catch a percent-vs-fraction unit bug, #637) and
#' its `vol` lower bound is INCLUSIVE of zero, which this gate closes. The
#' other two checks (`sharpe`, implied years) are not checked by S9 at all.
#' Both gates are kept side by side rather than merged: they answer
#' different questions ("is this the right scale" vs "is this physically
#' possible at any scale") and a future change to one's bounds should not
#' require reasoning about the other.
#'
#' The implied-years check needs each row's TRUE annualisation factor,
#' joined from `STRATEGY_OBS_ANN_FACTOR` (R/plan_leaderboard.R) the same
#' way S19/S20/S29 (this gate) all do -- `months` alone is ambiguous, since
#' five strategies' `months` column actually holds a DAILY observation
#' count (see the `STRATEGY_OBS_ANN_FACTOR` comment block).
#'
#' @param leaderboard Tibble with `strategy`, `period`, `vol`, `max_dd`,
#'   `sharpe`, `months` columns (the output of the `leaderboard` target).
#' @param obs_ann_factor_tbl Tibble with `strategy`, `obs_ann_factor`
#'   columns -- `STRATEGY_OBS_ANN_FACTOR` (R/plan_leaderboard.R).
#' @return `TRUE` invisibly on success.
#' @noRd
check_leaderboard_plausibility_red <- function(leaderboard, obs_ann_factor_tbl) {
  required_cols <- c("strategy", "period", "vol", "max_dd", "sharpe", "months")
  missing_cols <- setdiff(required_cols, names(leaderboard))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "Leaderboard is missing {length(missing_cols)} required column(s): {missing_cols}.",
      "i" = "check_leaderboard_plausibility_red() (S29) requires strategy, period, vol, max_dd, sharpe, months."
    ))
  }
  if (!all(c("strategy", "obs_ann_factor") %in% names(obs_ann_factor_tbl))) {
    cli::cli_abort(c(
      "x" = "obs_ann_factor_tbl is missing required column(s): strategy, obs_ann_factor.",
      "i" = "check_leaderboard_plausibility_red() (S29) requires STRATEGY_OBS_ANN_FACTOR's strategy, obs_ann_factor columns."
    ))
  }

  joined <- dplyr::left_join(
    leaderboard, obs_ann_factor_tbl[, c("strategy", "obs_ann_factor")],
    by = "strategy"
  )
  implied_years <- joined$months / joined$obs_ann_factor

  flag <- function(bad, metric, value, bound_desc) {
    if (!any(bad, na.rm = TRUE)) return(NULL)
    idx <- which(bad)
    tibble::tibble(
      strategy = joined$strategy[idx], period = joined$period[idx],
      metric = metric, value = value[idx], bound_desc = bound_desc
    )
  }

  offenders <- dplyr::bind_rows(
    flag(!is.na(joined$vol) & joined$vol <= 0, "vol", joined$vol, "> 0"),
    flag(!is.na(joined$max_dd) & joined$max_dd < -1, "max_dd", joined$max_dd, ">= -1"),
    flag(!is.na(joined$sharpe) & abs(joined$sharpe) > 5, "sharpe", joined$sharpe, "abs() <= 5"),
    flag(!is.na(implied_years) & implied_years > 100, "implied_years", implied_years, "<= 100")
  )

  if (nrow(offenders) > 0L) {
    msgs <- purrr::pmap_chr(
      offenders[, c("strategy", "period", "metric", "value", "bound_desc")],
      function(strategy, period, metric, value, bound_desc) {
        sprintf("  %s / %s -- %s = %s (expected %s)",
                strategy, period, metric, format(value, digits = 4), bound_desc)
      }
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Leaderboard has {nrow(offenders)} physically impossible metric ",
        "value(s) (#719 Layer 1 Red tier):"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "These are RED-tier: not a peer-relative outlier judgement, a value ",
        "that cannot be true under any correct computation. See #717 for the ",
        "worked case (566 implied years from a mis-annualised daily series)."
      )
    ))
  }

  invisible(TRUE)
}


#' Documented acknowledgements for peer-relative plausibility AMBER flags
#' (#719 Layer 1)
#'
#' Empty by design at this gate's introduction. #719 explicitly asks for
#' the amber gate to be "run once across the full leaderboard as intended"
#' BEFORE any row is acknowledged here -- populating this table today, from
#' this dispatch, without having seen a real run's output, would be a
#' guess wearing the shape of a decision. See
#' `check_leaderboard_plausibility_amber()`'s roxygen for the staging plan
#' this leaves for the next run against real data.
#'
#' Schema, once populated: `strategy`, `metric`, `reason` -- e.g. exactly
#' #719's own worked example, `strategy = "Managed Futures", metric =
#' "vol", reason = "vol-targeted at 6%, by construction"`.
#'
#' @noRd
LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED <- tibble::tibble(
  strategy = character(0),
  metric   = character(0),
  reason   = character(0)
)

#' Modified z-score threshold for the AMBER tier (Iglewicz & Hoya 1993)
#'
#' `0.6745 * (x - median(x)) / mad(x)`, flagged when its absolute value
#' exceeds this threshold. 3.5 is the standard citable choice for this
#' statistic (Iglewicz, B. & Hoya, D. C. (1993), "How to Detect and Handle
#' Outliers", ASQC), not a value invented for this gate -- a defensible,
#' peer-reviewed default in place of an arbitrary "k standard deviations"
#' pick, and consistent with this project's own `robust-statistics` skill
#' (median/MAD over mean/SD for outlier-prone financial return data).
#'
#' @noRd
PLAUSIBILITY_AMBER_Z_THRESHOLD <- 3.5

#' Compute peer-relative modified-z outlier flags for one or more leaderboard
#' metrics, scoped to Full Period rows (#719 Layer 1 -- Amber tier)
#'
#' For each metric, computes the cross-sectional median and MAD across every
#' strategy's `period == "Full Period"` value (scoped the same way S21's
#' `check_leaderboard_deflated_sharpe_coverage()` scopes deflated_sharpe --
#' a full-sample statistic should be compared against full-sample peers, not
#' mixed with sub-period rows), then flags any strategy whose modified
#' z-score exceeds `PLAUSIBILITY_AMBER_Z_THRESHOLD` in either direction.
#' `mad() == 0` (every peer identical) is treated as "no flags possible for
#' this metric" rather than a division-by-zero Inf, since a modified z-score
#' is undefined, not infinite, when the reference distribution has zero
#' spread.
#'
#' Split out as a plain, unit-testable function (rather than left inline in
#' `check_leaderboard_plausibility_amber()` below) for the same reason as
#' `.build_wide_corr_matrix()` (R/plan_strategy_correlation.R) -- the
#' peer-statistic computation is the part most likely to need independent
#' verification against a hand-computed example.
#'
#' @param leaderboard Tibble with `strategy`, `period`, plus each column
#'   named in `metrics`.
#' @param metrics Character vector of leaderboard column names to check.
#'   Defaults to `c("vol", "sharpe")` -- `vol` is #719's own worked example
#'   (CMR's understated vol was "the second-lowest of seventeen" against
#'   peer median); `sharpe` is the other headline ranking metric.
#' @param period Character. Which `period` value to scope the peer
#'   comparison to. Default `"Full Period"`.
#' @param z_threshold Numeric. Defaults to `PLAUSIBILITY_AMBER_Z_THRESHOLD`.
#' @return Tibble with `strategy`, `metric`, `value`, `peer_median`,
#'   `peer_mad`, `modified_z` -- one row per flagged (strategy, metric)
#'   pair. Zero rows (not an error) if nothing is flagged.
#' @noRd
.leaderboard_peer_amber_flags <- function(leaderboard, metrics = c("vol", "sharpe"),
                                           period = "Full Period",
                                           z_threshold = PLAUSIBILITY_AMBER_Z_THRESHOLD) {
  scoped <- leaderboard[leaderboard$period == period, , drop = FALSE]

  dplyr::bind_rows(lapply(metrics, function(m) {
    vals <- scoped[[m]]
    peer_median <- stats::median(vals, na.rm = TRUE)
    # constant = 1: Iglewicz & Hoya's 0.6745 below already IS the
    # normal-consistency scaling factor (1/1.4826); stats::mad()'s default
    # constant = 1.4826 would double-apply it (historical#9941 / #726 roborev).
    peer_mad    <- stats::mad(vals, na.rm = TRUE, constant = 1)

    if (is.na(peer_mad) || peer_mad == 0) {
      return(tibble::tibble(
        strategy = character(0), metric = character(0), value = double(0),
        peer_median = double(0), peer_mad = double(0), modified_z = double(0)
      ))
    }

    modified_z <- 0.6745 * (vals - peer_median) / peer_mad
    flagged <- !is.na(modified_z) & abs(modified_z) > z_threshold

    tibble::tibble(
      strategy = scoped$strategy[flagged], metric = m, value = vals[flagged],
      peer_median = peer_median, peer_mad = peer_mad,
      modified_z = modified_z[flagged]
    )
  }))
}

#' Assert every peer-relative AMBER outlier is acknowledged, or escalate
#' (S30, #719 Layer 1 -- Amber tier)
#'
#' #719's design point: "Amber must be acknowledged, not displayed. A
#' dashboard column that goes amber and sits there is noise within a
#' fortnight ... amber demands a row in a declaration table ... converts an
#' anomaly into a documented decision, and it means the ABSENCE of a reason
#' is what fails." This gate is that mechanism: it computes every amber
#' flag via `.leaderboard_peer_amber_flags()` above, always reports the
#' full list (never silent -- distinguishes red/amber/green per the parent
#' issue), and treats an unacknowledged flag as a failure once enforcement
#' is turned on.
#'
#' STAGED, not enforcing, by default -- mirroring two precedents already in
#' this codebase for the exact same situation (a new check landing before
#' it has been run against real leaderboard data even once): #738's
#' `.compute_cmr_metrics(periodicity_check = "warn")` staging lever
#' (R/plan_commodities_mean_reversion.R), and
#' `scripts/check_dashboard_freshness.R`'s `HD_FAIL_ON_STALE_DASHBOARDS`
#' escalation env var. #719 itself asks for this gate to be "run once
#' across the full leaderboard as intended" -- that first run is what
#' populates `LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED` (currently empty by
#' design, see that table's roxygen), and only after real amber flags have
#' been reviewed and either acknowledged or fixed does enforcing on every
#' `tar_make()` become the right default. Escalate by setting
#' `HD_ENFORCE_PLAUSIBILITY_AMBER=1` (or passing `enforce = TRUE` directly).
#'
#' @param leaderboard Tibble -- the `leaderboard` target.
#' @param acknowledged_tbl Tibble with `strategy`, `metric`, `reason`
#'   columns -- `LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED` above.
#' @param metrics,period,z_threshold Passed through to
#'   `.leaderboard_peer_amber_flags()`.
#' @param enforce Logical. `TRUE` aborts on any unacknowledged amber flag;
#'   `FALSE` (default) reports them via `cli::cli_warn()` and returns
#'   `TRUE`. Defaults to reading `HD_ENFORCE_PLAUSIBILITY_AMBER` and
#'   comparing it to the literal string `"1"` -- NOT `as.logical()` on the
#'   env var, per `.claude/rules/fail-loud-not-null.md`'s own warning that
#'   `as.logical("1")` returns `NA`, not `TRUE`.
#' @return `TRUE` invisibly.
#' @noRd
check_leaderboard_plausibility_amber <- function(
    leaderboard, acknowledged_tbl = LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED,
    metrics = c("vol", "sharpe"), period = "Full Period",
    z_threshold = PLAUSIBILITY_AMBER_Z_THRESHOLD,
    enforce = Sys.getenv("HD_ENFORCE_PLAUSIBILITY_AMBER", "0") == "1") {

  if (!all(c("strategy", "metric", "reason") %in% names(acknowledged_tbl))) {
    cli::cli_abort(c(
      "x" = "acknowledged_tbl is missing required column(s): strategy, metric, reason.",
      "i" = "check_leaderboard_plausibility_amber() (S30) requires LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED's strategy, metric, reason columns."
    ))
  }

  flags <- .leaderboard_peer_amber_flags(leaderboard, metrics, period, z_threshold)

  if (nrow(flags) > 0L) {
    is_ack <- vapply(seq_len(nrow(flags)), function(i) {
      any(acknowledged_tbl$strategy == flags$strategy[i] & acknowledged_tbl$metric == flags$metric[i])
    }, logical(1))

    flag_msgs <- sprintf(
      "  %s -- %s = %s (peer median %s, modified z = %s)%s",
      flags$strategy, flags$metric, format(flags$value, digits = 4),
      format(flags$peer_median, digits = 4), format(flags$modified_z, digits = 3),
      ifelse(is_ack, " [acknowledged]", " [NOT acknowledged]")
    )
    cli::cli_inform(c(
      "i" = paste0(
        "qa_leaderboard_plausibility_amber: {nrow(flags)} peer-relative amber ",
        "flag(s) (#719 Layer 1):"
      ),
      setNames(flag_msgs, rep("i", length(flag_msgs)))
    ))

    unacked <- flags[!is_ack, , drop = FALSE]
    if (nrow(unacked) > 0L) {
      if (isTRUE(enforce)) {
        msgs <- sprintf(
          "  %s / %s -- value = %s, peer median = %s, modified z = %s",
          unacked$strategy, unacked$metric, format(unacked$value, digits = 4),
          format(unacked$peer_median, digits = 4), format(unacked$modified_z, digits = 3)
        )
        cli::cli_abort(c(
          "x" = paste0(
            "{nrow(unacked)} peer-relative amber outlier(s) have no written ",
            "acknowledgement (#719 Layer 1, S30, HD_ENFORCE_PLAUSIBILITY_AMBER=1):"
          ),
          setNames(msgs, rep("i", length(msgs))),
          "i" = paste0(
            "Add a row to LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED (R/plan_qa_gates.R) ",
            "naming strategy, metric, and a written reason the outlier is genuine -- ",
            "or fix the underlying data if it is not. Per fail-loud-not-null.md, the ",
            "absence of a reason is what fails, not the outlier value itself."
          )
        ))
      } else {
        cli::cli_warn(c(
          "!" = paste0(
            "{nrow(unacked)} peer-relative amber outlier(s) have no written ",
            "acknowledgement (#719 Layer 1, S30) -- STAGED (report-only): set ",
            "HD_ENFORCE_PLAUSIBILITY_AMBER=1 to make this abort the pipeline."
          )
        ))
      }
    }
  }

  invisible(TRUE)
}


#' Assert Markov diagonal dominance: each state's persistence probability
#' exceeds a naive random baseline (S32, #838)
#'
#' A regime/vol-state classifier whose transition matrix is close to
#' uniform (each state persists no better than chance) is not detecting
#' persistence -- it is noise wearing a regime label. This asserts, for
#' every declared state with at least one observed transition FROM it
#' (`n_from > 0`), that its diagonal persistence probability
#' (`P(state_t+1 = i | state_t = i)`, from `hd_markov_transition()`)
#' exceeds the naive random baseline `1 / n_states` -- the persistence a
#' state would show if the next state were drawn uniformly at random,
#' independent of the current one.
#'
#' A state with `n_from == 0` (never observed as an origin -- e.g. an
#' extremely rare "hostile" regime in a short sample) is excluded from the
#' check rather than treated as a failure: `hd_markov_transition()` already
#' reports `NA` for such a row, and per `fail-loud-not-null.md` an
#' unobserved case is a distinct, disclosed condition, not silently folded
#' into either PASS or FAIL.
#'
#' @param state Character or factor vector, in time order -- the classified
#'   state series to check (e.g. `rsc_regime$regime`).
#' @param label Character scalar used in the `cli_abort()` message to name
#'   the series being checked. Defaults to `deparse(substitute(state))`.
#' @return `TRUE` invisibly on success.
#' @noRd
check_markov_diagonal_dominance <- function(state, label = deparse(substitute(state))) {
  mt <- hd_markov_transition(state)
  n_states <- length(mt$states)
  baseline <- 1 / n_states

  checkable <- mt$persistence[mt$persistence$n_from > 0L, , drop = FALSE]
  offenders <- checkable[
    is.na(checkable$p_stay) | checkable$p_stay <= baseline, , drop = FALSE
  ]

  if (nrow(offenders) > 0L) {
    msgs <- sprintf(
      "  %s -- p_stay = %s (baseline = %.3f, n_from = %d)",
      offenders$state,
      ifelse(is.na(offenders$p_stay), "NA", sprintf("%.3f", offenders$p_stay)),
      baseline, offenders$n_from
    )
    cli::cli_abort(c(
      "x" = paste0(
        "{nrow(offenders)} state(s) in ", label, " show no better persistence than a ",
        "1/{n_states} random baseline ({round(baseline, 3)}) -- the classifier is not ",
        "detecting real persistence for these state(s) (S32, #838):"
      ),
      setNames(msgs, rep("i", length(msgs)))
    ))
  }

  invisible(TRUE)
}


#' Declared overrides for the leverage-allocator detection-power gate (S31,
#' #626/#719 Layer 2 narrow slice)
#'
#' Per `.claude/rules/detection-power-required.md`'s allocation-gating rule:
#' "A strategy may not receive gross above 1.0x while
#' `detection_underpowered` is TRUE or NA." This is Layer 2's core rule from
#' #719 -- NOT the full provenance checklist (the remaining Layer 2 items
#' stay separately scoped). Empty by design at this gate's introduction: the
#' backstop LEVEL itself is provisional (#626 D1) and no override has been
#' reviewed against real leaderboard data yet. Schema: `strategy`, `reason`.
#' @noRd
LEVERAGE_GROSS_DETECTION_OVERRIDE <- tibble::tibble(
  strategy = character(0),
  reason   = character(0)
)

#' Assert no strategy receives allocator gross above 1.0x while its
#' detection-power verdict is underpowered or missing (S31, #626/#719 Layer
#' 2 narrow slice, detection-power-required.md)
#'
#' A strategy whose own sample cannot distinguish its Sharpe from zero
#' (`detection_underpowered == TRUE`) -- or whose verdict was never computed
#' at all (`NA`, which S20 already treats as a defect on the leaderboard
#' itself) -- must not be handed MORE than 1.0x gross by the allocator,
#' however the vol-normalised arithmetic alone would size it.
#' `detection_underpowered = NA` is deliberately treated the SAME as `TRUE`
#' here (`fail-loud-not-null.md`: an unknown verdict must not silently
#' permit what a known-bad verdict would forbid) -- distinct from S20's own
#' handling of NA, which requires every positive-Sharpe leaderboard row to
#' HAVE a verdict in the first place; this gate additionally refuses to
#' lever on the absence of one.
#'
#' `G_capped`, not `G_implied`, is the column checked: the backstop-capped
#' figure is what the allocator would actually assign. `G_implied` may
#' exceed 1.0x for a strategy the backstop itself brings back under it, and
#' that case is not an offence.
#'
#' @param allocator_gross Tibble -- the `leverage_allocator_gross` target
#'   (needs `strategy`, `G_capped`).
#' @param leaderboard Tibble -- the `leaderboard` target (needs `strategy`,
#'   `period`, `detection_underpowered`).
#' @param override_tbl Tibble with `strategy`, `reason` columns --
#'   `LEVERAGE_GROSS_DETECTION_OVERRIDE` above.
#' @return `TRUE` invisibly on success.
#' @noRd
check_leverage_gross_detection_gate <- function(allocator_gross, leaderboard,
                                                 override_tbl = LEVERAGE_GROSS_DETECTION_OVERRIDE) {
  required_alloc_cols <- c("strategy", "G_capped")
  missing_alloc <- setdiff(required_alloc_cols, names(allocator_gross))
  if (length(missing_alloc) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg allocator_gross} is missing required column{?s}: {.field {missing_alloc}}.",
      "i" = "check_leverage_gross_detection_gate() (S31) needs {.field {required_alloc_cols}} (see compute_allocator_gross())."
    ))
  }
  required_lb_cols <- c("strategy", "period", "detection_underpowered")
  missing_lb <- setdiff(required_lb_cols, names(leaderboard))
  if (length(missing_lb) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg leaderboard} is missing required column{?s}: {.field {missing_lb}}.",
      "i" = "check_leverage_gross_detection_gate() (S31) needs {.field {required_lb_cols}}."
    ))
  }
  if (!all(c("strategy", "reason") %in% names(override_tbl))) {
    cli::cli_abort(c(
      "x" = "{.arg override_tbl} is missing required column(s): strategy, reason.",
      "i" = "check_leverage_gross_detection_gate() (S31) requires LEVERAGE_GROSS_DETECTION_OVERRIDE's strategy, reason columns."
    ))
  }

  det_full <- leaderboard[leaderboard$period == "Full Period",
                           c("strategy", "detection_underpowered"), drop = FALSE]
  joined <- dplyr::left_join(allocator_gross, det_full, by = "strategy")

  # NA detection_underpowered is treated the same as TRUE -- see roxygen.
  blocked <- is.na(joined$detection_underpowered) | (joined$detection_underpowered %in% TRUE)

  offenders <- joined[
    !is.na(joined$G_capped) & joined$G_capped > 1.0 & blocked &
      !(joined$strategy %in% override_tbl$strategy),
    , drop = FALSE
  ]

  if (nrow(offenders) > 0L) {
    msgs <- sprintf(
      "  %s -- G_capped = %.2fx, detection_underpowered = %s",
      offenders$strategy, offenders$G_capped,
      ifelse(is.na(offenders$detection_underpowered), "NA (not computed)",
             as.character(offenders$detection_underpowered))
    )
    cli::cli_abort(c(
      "x" = paste0(
        "{nrow(offenders)} strategy/strategies would receive allocator gross ",
        "above 1.0x while detection-underpowered or unverified (#626/#719 ",
        "Layer 2, detection-power-required.md):"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "A strategy that cannot be distinguished from a zero Sharpe (or has ",
        "no verdict at all) must not be levered above 1.0x gross. Either fix ",
        "the underlying detection verdict, lower the strategy's allocator ",
        "input (leverage_gross_backstop / HD_LEVERAGE_GROSS_BACKSTOP), or add ",
        "a written row to LEVERAGE_GROSS_DETECTION_OVERRIDE (R/plan_qa_gates.R) ",
        "with an explicit reason."
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

    # QA gate: no automatically-computed metric window extends past
    # `test_end` unless its partition is explicitly "Validation" (S11) --
    # guards against the #645 defect class where a strategy's bespoke OOS
    # window is unbounded above and silently includes the sealed Validation
    # partition on every tar_make(). #667 widened this from an enumerated
    # pair (mf_metrics, ev_metrics) to the S11_METRICS_REGISTRY list above
    # -- every metrics target with strategy/period/window_end columns is
    # checked. The literal `list(mf_metrics = mf_metrics, ...)` below is
    # required (not `get(nm)` in a loop over the registry's names) so
    # targets' static dependency analysis can see each metrics target as a
    # real dependency edge -- see S11_METRICS_REGISTRY's roxygen for why a
    # fully dynamic lookup can't do this from inside a target's command.
    targets::tar_target(
      qa_metric_window_bounds,
      command = {
        metrics_by_name <- list(
          mf_metrics       = mf_metrics,
          ev_metrics       = ev_metrics,
          rsc_metrics      = rsc_metrics,
          aw_metrics       = aw_metrics,
          mr_metrics       = mr_metrics,
          rafi_metrics     = rafi_metrics,
          fip_comparison   = fip_comparison,
          eur_results      = eur_results,
          eur_comparison   = eur_comparison,
          eur_ciss_results = eur_ciss_results
        )

        check_s11_registry_consistency(names(S11_METRICS_REGISTRY), names(metrics_by_name))

        for (nm in names(S11_METRICS_REGISTRY)) {
          partition <- S11_METRICS_REGISTRY[[nm]]
          check_metric_window_bounds(
            metrics_by_name[[nm]],
            bt_partitions[[partition]]$test_end,
            nm
          )
        }

        cli::cli_inform(c("v" = paste0(
          "qa_metric_window_bounds: S11 passed (", length(S11_METRICS_REGISTRY),
          " registered targets, no non-Validation window extends past test_end)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: stk_drif_portfolio has complete calendar-month coverage (S12) —
    # guards against the #641 defect class where a lookback/rebalance window
    # confined to a single calendar month silently drops an entire month
    # (March, fed by a structurally-short February) from every year.
    targets::tar_target(
      qa_stk_drif_month_coverage,
      command = {
        check_month_coverage(stk_drif_portfolio, "stk_drif_portfolio")
        cli::cli_inform(c("v" = "qa_stk_drif_month_coverage: S12 passed (all 12 calendar months present in stk_drif_portfolio)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: port_returns has no calendar-month gaps, thin-coverage months
    # are flagged (S13) — guards against the #641 defect class where a
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
        cli::cli_inform(c("v" = "qa_portfolio_join_coverage: S13 passed (no calendar-month gaps in port_returns)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: leaderboard never emits an automatically-computed Validation
    # row (S14) — guards against the #648 defect class where
    # `slice_portfolio()` in R/plan_leaderboard.R and several source metrics
    # targets (fm_metrics, drif_metrics, stk_max_metrics, stk_drif_metrics,
    # xgb_drif_metrics, ltr_metrics, port_metrics) fed a "Validation" period
    # row into the leaderboard on every tar_make() — an automatic-computation
    # violation of the sealed-partition rule (backtest-partitions.md).
    targets::tar_target(
      qa_leaderboard_no_validation,
      command = {
        check_leaderboard_no_validation_rows(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_no_validation: S14 passed (no automatically-computed Validation row in leaderboard)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: no published document reads the sealed Validation partition
    # (S15) — guards against the #660 defect class where docs/stock-backtest.qmd
    # read `period == "Validation"` directly from source-metrics targets in
    # prose and unfiltered metrics tables, bypassing the leaderboard target
    # (and its S14 gate) entirely. Extends S14's leaderboard-only scope to
    # every published .qmd/.R, per the sealed-Validation requirement in
    # backtest-partitions.md. See check_no_published_validation_reads()
    # roxygen for the two required exclusions (this file; scripts/evaluate_validation.R).
    targets::tar_target(
      qa_no_published_validation_reads,
      command = {
        scan_dirs <- c(here::here("docs"), here::here("R"), here::here("scripts"))
        scan_dirs <- scan_dirs[dir.exists(scan_dirs)]
        files <- unlist(lapply(scan_dirs, function(d) {
          list.files(d, pattern = "\\.(qmd|R)$", full.names = TRUE, recursive = TRUE)
        }))
        files <- files[basename(files) != "plan_qa_gates.R"]
        files <- files[basename(files) != "evaluate_validation.R"]

        hits <- check_no_published_validation_reads(files)
        if (nrow(hits) > 0L) {
          msgs <- purrr::pmap_chr(
            hits[, c("file", "line", "code")],
            function(file, line, code) {
              sprintf("  %s:%d -- %s", basename(file), line, trimws(code))
            }
          )
          cli::cli_abort(c(
            "x" = paste0(
              "Published document(s) read the sealed Validation partition in ",
              nrow(hits), " place(s), #660:"
            ),
            setNames(msgs, rep("i", length(msgs))),
            "i" = paste0(
              "Validation is sealed for display AND reasoning ",
              "(.claude/rules/backtest-partitions.md) -- remove the read, or use ",
              "scripts/evaluate_validation.R for the sanctioned one-shot evaluation."
            )
          ))
        }
        cli::cli_inform(c("v" = "qa_no_published_validation_reads: S15 passed (no published document reads Validation)"))
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: strategy_cost_convention's borrow_status is derivable, in the
    # allowed vocabulary, and consistent with borrow_rate_annual (S16) --
    # guards against the #664 defect class where borrow_rate_annual == NA
    # conflated "no short leg" with "short leg exists, borrow genuinely
    # unmodelled" into a single value that nothing could filter, sort,
    # count, or gate on.
    targets::tar_target(
      qa_borrow_status_registry,
      command = {
        check_borrow_status_registry(strategy_cost_convention)
        cli::cli_inform(c("v" = "qa_borrow_status_registry: S16 passed (all borrow_status values derivable, in vocabulary, and consistent with borrow_rate_annual)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: strategy_cost_convention's lending_status is derivable and in
    # the allowed vocabulary (S18) -- sibling to S16, not an extension of it
    # (see check_lending_status_registry() roxygen for why). Guards against
    # the #665 defect class where securities-lending income was modelled
    # nowhere, with no decision recorded either way.
    targets::tar_target(
      qa_lending_status_registry,
      command = {
        check_lending_status_registry(strategy_cost_convention)
        cli::cli_inform(c("v" = "qa_lending_status_registry: S18 passed (all lending_status values derivable and in vocabulary)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: leaderboard sharpe is coherent with cagr/vol/ann_rf (S17) --
    # guards against the #677 defect class where sharpe was computed by at
    # least FOUR distinct mathematical bases across ~13 source metrics
    # targets (geometric vs arithmetic numerator; risk-free deducted or
    # not), so strategies were ranked against each other on a statistic
    # that was not actually comparable. #677 slices 1-3b migrated every
    # leaderboard-feeding source metrics target onto the canonical
    # sharpe_ratio_rf() (R/utils_metrics.R) and required each to publish
    # the ann_rf it used; this gate asserts
    # sharpe == (cagr - ann_rf) / vol exactly (within a documented
    # rounding tolerance), never a "plausible band" -- see
    # check_leaderboard_sharpe_coherence() roxygen for the full rationale
    # and tolerance derivation.
    targets::tar_target(
      qa_leaderboard_sharpe_coherence,
      command = {
        check_leaderboard_sharpe_coherence(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_sharpe_coherence: S17 passed (sharpe coherent with cagr/vol/ann_rf for every row)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every leaderboard strategy has a declared observation
    # periodicity for the detection-power diagnostic (S19) -- guards against
    # a new strategy silently getting NA detection_min_n_years/
    # detection_underpowered forever if STRATEGY_OBS_ANN_FACTOR
    # (R/plan_leaderboard.R) isn't updated alongside it. #711 Gap 1.
    targets::tar_target(
      qa_leaderboard_detection_power_coverage,
      command = {
        check_leaderboard_detection_power_coverage(leaderboard, STRATEGY_OBS_ANN_FACTOR)
        cli::cli_inform(c("v" = "qa_leaderboard_detection_power_coverage: S19 passed (all strategies have a declared periodicity)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every positive-Sharpe leaderboard row has a non-NA
    # detection-power verdict, both single-test and (where k_eff_leaderboard
    # is usable) multiple-testing-corrected (S20, #726 items 3+4). S19 above
    # only guards the diagnostic's INPUT (a declared periodicity); this gate
    # asserts the property actually wanted -- that the diagnostic produced a
    # value -- and names which of the diagnostic's three NA paths applies.
    # See check_leaderboard_detection_power_values() roxygen for the full
    # rationale, including why Risk State passed S19 while still landing on
    # NA forever until #726 item 3's calc_metrics() fix.
    targets::tar_target(
      qa_leaderboard_detection_power_values,
      command = {
        check_leaderboard_detection_power_values(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_detection_power_values: S20 passed (every positive-Sharpe row has a detection-power verdict)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every positive-Sharpe Full Period leaderboard strategy has a
    # non-NA deflated_sharpe/dsr_pvalue/k_eff_leaderboard verdict, or a
    # written reason in DEFLATED_SHARPE_EXEMPTIONS (S21, #728 item 4).
    # #728 found deflated_sharpe covered only 4 of 17 strategies -- and of
    # the 8 strategies claiming a positive Full-Period Sharpe, only 1
    # (Factor DRIF) had any multiple-testing correction. #728 items 1+2
    # widened coverage to 11 of 17; #733 widened it further to 16 of 17 by
    # folding the five daily-frequency strategies into the correlation
    # spine via monthly resampling. This gate is what keeps that count from
    # silently regressing. Expected to fail on the current, unrebuilt store
    # until a fresh tar_make() picks up the widened strat_deflated_sharpe --
    # see check_leaderboard_deflated_sharpe_coverage() roxygen for the full
    # rationale and scoping notes.
    targets::tar_target(
      qa_leaderboard_deflated_sharpe_coverage,
      command = {
        check_leaderboard_deflated_sharpe_coverage(leaderboard, DEFLATED_SHARPE_EXEMPTIONS)
        cli::cli_inform(c("v" = "qa_leaderboard_deflated_sharpe_coverage: S21 passed (every positive-Sharpe Full Period strategy has a deflated-Sharpe verdict or a declared exemption)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: the #753 package-source digest mechanism itself is tracking
    # real files (S22). This is a "guard the guard" sanity check, NOT the
    # cross-run staleness detector -- see check_pkg_source_tracked()
    # roxygen above for why that detector cannot live in this pipeline at
    # all (tar_meta()/tar_progress() are unsupported against the store of
    # the pipeline currently running) and instead lives in
    # scripts/check_pkg_staleness.R, run as a scripts/build.sh step.
    targets::tar_target(
      qa_pkg_source_tracked,
      command = {
        check_pkg_source_tracked(pkg_source_files, pkg_source_digest)
        cli::cli_inform(c("v" = sprintf(
          "qa_pkg_source_tracked: S22 passed (%d package source file(s) tracked, digest %s)",
          length(pkg_source_files), substr(pkg_source_digest, 1, 12)
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: net_cagr/cvar_95/credible are jointly present or jointly NA
    # per row (S23, fail-loud-not-null.md) -- see
    # check_leaderboard_cost_metrics_joint_presence() roxygen above for the
    # #637/#640/#641/#643 defect class this closes.
    targets::tar_target(
      qa_leaderboard_cost_metrics_coverage,
      command = {
        check_leaderboard_cost_metrics_joint_presence(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_cost_metrics_coverage: S23 passed (net_cagr/cvar_95/credible jointly present or jointly NA on every row)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: stk_all_comparison has no calendar-month gaps, thin-coverage
    # months are flagged (S24, #656) -- guards against the #656 defect class
    # where a 4-way inner_join chain (the SAME constituents as the #641
    # port_returns defect, S13) silently deleted any month missing from ONE
    # constituent strategy for ALL FOUR. stk_all_comparison feeds
    # stk_all_comparison_plot, published on BOTH leaderboard.qmd and
    # stock-backtest.qmd, and previously had zero instrumentation.
    targets::tar_target(
      qa_stk_all_comparison_coverage,
      command = {
        check_stk_all_comparison_coverage(stk_all_comparison)
        cli::cli_inform(c("v" = "qa_stk_all_comparison_coverage: S24 passed (no calendar-month gaps in stk_all_comparison)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: boot_monthly_returns has no calendar-month gaps, thin-coverage
    # months are flagged (S25, #603/#656) -- guards against the #603 defect
    # class where a 4-way inner_join chain dropped ~1/3 of months AND let
    # the block bootstrap in boot_draws splice non-adjacent calendar months
    # together, defeating serial-dependence-preserving resampling. These
    # intervals feed boot_ci_summary's ci_crosses_zero flag, published on
    # the leaderboard.
    targets::tar_target(
      qa_boot_monthly_returns_coverage,
      command = {
        check_boot_monthly_returns_coverage(boot_monthly_returns)
        cli::cli_inform(c("v" = "qa_boot_monthly_returns_coverage: S25 passed (no calendar-month gaps in boot_monthly_returns)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: no numeric leaderboard column is entirely NA (S26, #668) --
    # renumbered from S24 to S26 when merging with #798's independently
    # added S24 (qa_stk_all_comparison_coverage) / S25
    # (qa_boot_monthly_returns_coverage) -- the property-based
    # generalisation of the two hardcoded all-NA checks that used to live
    # inside check_leaderboard_coverage() (S7): `ssr` and `top5pct_share` by
    # name (#400). #668 found that scoping the check to two column NAMES
    # rather than the PROPERTY "no published metric column has zero non-NA
    # values" left every OTHER numeric column, and every OTHER target,
    # uncovered -- exactly how `ltr_subperiod$sharpe` sat all-NA since
    # inception (#677 defect B) without any gate ever firing. See
    # check_leaderboard_no_all_na_metric() / check_no_all_na_numeric_
    # columns() roxygen above for the full rationale, and
    # LEADERBOARD_ALL_NA_EXEMPT for the (currently empty, documented-only-
    # on-addition) exemption mechanism.
    targets::tar_target(
      qa_leaderboard_no_all_na_metric,
      command = {
        check_leaderboard_no_all_na_metric(leaderboard)
        cli::cli_inform(c("v" = "qa_leaderboard_no_all_na_metric: S26 passed (no numeric leaderboard column is entirely NA)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: CMR effective breadth (n_eff) never falls below the minimum
    # floor on any date holding a position (S27, #751 item F; renumbered
    # twice -- originally S24, then S26 when #806/#668 first landed S24/S25
    # on main, then S27 once #806/#668's OWN final landing independently
    # took S26 for qa_leaderboard_no_all_na_metric above). n_eff is
    # salvaged from the closed #765 branch (see hd_commodity_mr_portfolio()
    # roxygen, packages/historicaldata/R/commodities_mean_reversion.R) and
    # wired here against the LIVE tercile construction, not the
    # rank-weighted one #765 proposed (that item was decided against on
    # #765 -- see the #751 comment thread).
    targets::tar_target(
      qa_cmr_effective_breadth,
      command = {
        check_cmr_effective_breadth(list(
          `1m` = cmr_portfolio_1m,
          `3m` = cmr_portfolio_3m,
          `6m` = cmr_portfolio_6m
        ))
        cli::cli_inform(c("v" = "qa_cmr_effective_breadth: S27 passed (n_eff >= floor on every date holding a position, all 3 CMR lookback partitions)"))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: each daily-native strategy's declared ann_factor reconciles
    # against its own observed date frequency (S28, #719 Layer 3) --
    # pipeline-wide backstop, independent of whether any individual
    # strategy's own metrics code calls a periodicity guard. Scoped to the
    # five daily-native strategies collected in strat_returns_daily_native
    # (R/plan_strategy_correlation.R, #733); see
    # check_strategy_periodicity_reconciliation()'s roxygen above for why
    # the eleven monthly-native strategies are not (yet) in scope.
    targets::tar_target(
      qa_strategy_periodicity_reconciliation,
      command = {
        check_strategy_periodicity_reconciliation(
          strat_returns_daily_native,
          STRATEGY_OBS_ANN_FACTOR
        )
        cli::cli_inform(c("v" = paste0(
          "qa_strategy_periodicity_reconciliation: S28 passed (declared ",
          "ann_factor reconciles with observed date frequency for all ",
          "daily-native strategies; known exceptions in ",
          "PERIODICITY_RECONCILIATION_EXEMPT run in warn-mode)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: leaderboard metrics are not physically impossible (S29,
    # #719 Layer 1 -- Red tier). vol <= 0, max_dd < -100%, |sharpe| > 5, or
    # implied years (months / obs_ann_factor) > 100 -- see #717 for the
    # worked case that motivated the last of these (566 implied years from
    # a mis-annualised daily series).
    targets::tar_target(
      qa_leaderboard_plausibility_red,
      command = {
        check_leaderboard_plausibility_red(leaderboard, STRATEGY_OBS_ANN_FACTOR)
        cli::cli_inform(c("v" = paste0(
          "qa_leaderboard_plausibility_red: S29 passed (no physically ",
          "impossible vol/max_dd/sharpe/implied-years values, #719 Layer 1)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: peer-relative plausibility AMBER outliers are acknowledged,
    # or this gate stays in STAGED report-only mode (S30, #719 Layer 1 --
    # Amber tier). See check_leaderboard_plausibility_amber()'s roxygen for
    # the staging rationale and the HD_ENFORCE_PLAUSIBILITY_AMBER escalation
    # switch. Deliberately does NOT fail the pipeline by default: #719 asks
    # for this gate to be run once against the full, real leaderboard
    # before anything is acknowledged, and this repo has two existing
    # precedents (#738's CMR periodicity_check warn-mode,
    # scripts/check_dashboard_freshness.R's HD_FAIL_ON_STALE_DASHBOARDS) for
    # staging a new check exactly this way.
    targets::tar_target(
      qa_leaderboard_plausibility_amber,
      command = {
        check_leaderboard_plausibility_amber(leaderboard, LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED)
        cli::cli_inform(c("v" = paste0(
          "qa_leaderboard_plausibility_amber: S30 ran (STAGED report-only ",
          "unless HD_ENFORCE_PLAUSIBILITY_AMBER=1 -- see cli_inform/cli_warn ",
          "output above for any flags, #719 Layer 1)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: no strategy receives allocator gross above 1.0x while
    # detection-underpowered or unverified (S31, #626/#719 Layer 2 narrow
    # slice, detection-power-required.md's allocation-gating rule). This is
    # NOT the full Layer 2 provenance checklist (#719) -- only the
    # detection-power slice of it; the remaining provenance facts remain
    # separately scoped and are not enforced here.
    targets::tar_target(
      qa_leverage_gross_detection_gate,
      command = {
        check_leverage_gross_detection_gate(leverage_allocator_gross, leaderboard)
        cli::cli_inform(c("v" = paste0(
          "qa_leverage_gross_detection_gate: S31 passed (no detection-",
          "underpowered/unverified strategy above 1.0x allocator gross, ",
          "#626/#719 Layer 2 narrow slice)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: Markov transition-matrix diagonal dominance for the risk-state
    # classifier (S32, #838, detection-power-required.md-style persistence
    # check). Asserts each observed state's P(stay) exceeds the naive
    # 1/n_states random baseline -- a classifier whose transition matrix is
    # ~uniform is not detecting persistence, it's noise. Checked against
    # rsc_regime$regime (R/plan_risk_state.R, #51, benign/cautious/hostile).
    # regime_classification$regime (R/plan_regime.R, #34) is left for a
    # follow-up -- see #838 PR body deferred items.
    targets::tar_target(
      qa_markov_diagonal_dominance,
      command = {
        check_markov_diagonal_dominance(rsc_regime$regime, label = "rsc_regime$regime")
        cli::cli_inform(c("v" = paste0(
          "qa_markov_diagonal_dominance: S32 passed (every observed state's ",
          "persistence exceeds the 1/n_states random baseline, #838)"
        )))
        TRUE
      },
      cue = targets::tar_cue(mode = "always")
    )
  )
}
