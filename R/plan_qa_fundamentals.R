# Plan: Fundamentals QA gates (#553/#554/#555)
#
# #553 ratified the fundamentals schema (revision triangle, one row per
# (ticker, xbrl_tag, fiscal_period) -- see packages/historicaldata/R/
# fundamentals.R and R/registry.R's `fundamentals` entry) and unblocked
# two sub-issues:
#
#   #554 (G4) -- CHECK 6: fundamentals filing-lag shift. The decisive
#   fundamentals-bias test: re-run the backtest with every fundamental
#   input delayed to period_end + FUNDAMENTAL_MAX_LAG_DAYS; if the
#   headline metric degrades materially, the edge was the peek, not alpha.
#
#   #555 (G5) -- join-date audit. A structural always-on guard:
#   leaked_pct = mean(visible_date < first_filed), which must be ~0.
#
# CURRENT STATUS (as of this file's introduction): no strategy in this
# repo yet consumes hd_fundamentals() -- the #553 schema work was
# explicitly deferred until a fundamental signal was scoped, and this PR
# builds the infrastructure ahead of that, per the issue's own acceptance
# criteria. Both gates below are therefore GUARDED: they grep R/ for any
# call site of hd_fundamentals() and no-op (fast, correct today) when none
# is found. The two pure comparison functions
# (check_fundamentals_lag_shift, check_fundamentals_join_dates) are fully
# implemented and unit-tested against synthetic data now, so the moment a
# real fundamentals-consuming strategy exists, that strategy's own QA
# target calls them directly with its real as-used/lag-shifted metrics or
# its real assembled feature frame -- the same pattern S9/S10/S20 already
# use for check_leaderboard_*(). Auto-locating WHICH target's return
# series to compare for an as-yet-nonexistent strategy is not something a
# static guard can do; when a call site does appear, the gate aborts with
# an explicit instruction to wire it, rather than silently passing
# (fail-loud-not-null.md).

# Silence R CMD check NOTEs for dplyr NSE
utils::globalVariables(c("form"))

# ---- Constants ---------------------------------------------------------

#' Worst-case SEC filing lag used for the CHECK 6 lag-shift test (#554)
#'
#' SEC deadlines: 60 calendar days for large-accelerated filers, 75 for
#' accelerated filers, 90 for all others. 120 is the documented worst-case
#' ceiling used by the source article's own adversarial test (#553 G4).
#' Calibrate per data vintage if a future fundamentals source has
#' different disclosure timing.
FUNDAMENTAL_MAX_LAG_DAYS <- 120L

# ---- Pure check functions ------------------------------------------------

#' Scan files for hd_fundamentals() call sites (guard for CHECK 6 / #555)
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no
#'   fundamentals-consuming code found.
#' @noRd
check_hd_fundamentals_usage <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("\\bhd_fundamentals\\s*\\(", lines)
    m <- m[!grepl("^\\s*#", lines[m])]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Assert a fundamentals-consuming strategy survives its filing-lag shift
#' (CHECK 6, #554)
#'
#' Compares a headline metric (Sharpe or CAGR) computed two ways: (a) as
#' the strategy actually used its fundamental inputs, and (b) with every
#' fundamental input delayed to its worst-case public-availability date
#' (`period_end + FUNDAMENTAL_MAX_LAG_DAYS`). If the metric collapses under
#' the fair, delayed condition, the edge was a filing-lag peek, not alpha.
#'
#' @param metric_as_used Numeric scalar. Headline metric computed with
#'   fundamentals as the strategy actually joined them (first_filed
#'   as-reported).
#' @param metric_lag_shifted Numeric scalar. Same metric recomputed with
#'   every fundamental input's availability date shifted to
#'   `period_end + FUNDAMENTAL_MAX_LAG_DAYS`.
#' @param metric_name Character scalar used in messages (default `"Sharpe"`).
#' @return Invisibly, a list with `metric_as_used`, `metric_lag_shifted`,
#'   `degradation_pct` (clamped at 0 -- an IMPROVEMENT under the shift is
#'   reported as 0% degradation, not a negative number), and `verdict`
#'   (one of `"ok"`, `"warn"`). Aborts (does not return) when degradation
#'   exceeds the FAIL threshold.
#' @family quality-audit
#' @noRd
check_fundamentals_lag_shift <- function(metric_as_used, metric_lag_shifted,
                                          metric_name = "Sharpe") {
  bad_scalar <- function(x) {
    !is.numeric(x) || length(x) != 1L || is.na(x)
  }
  if (bad_scalar(metric_as_used) || bad_scalar(metric_lag_shifted)) {
    cli::cli_abort(
      c(
        "x" = "{.arg metric_as_used} and {.arg metric_lag_shifted} must each be a single non-NA numeric.",
        "i" = "Got metric_as_used = {.val {metric_as_used}}, metric_lag_shifted = {.val {metric_lag_shifted}}."
      ),
      class = "hd_fundamentals_lag_shift_bad_input"
    )
  }
  if (abs(metric_as_used) < 1e-8) {
    cli::cli_abort(
      c(
        "x" = "{.arg metric_as_used} ({metric_name}) is ~0 -- relative degradation is undefined.",
        "i" = "check_fundamentals_lag_shift() (CHECK 6, #554) requires a non-zero baseline metric."
      ),
      class = "hd_fundamentals_lag_shift_zero_baseline"
    )
  }

  raw_degradation <- (metric_as_used - metric_lag_shifted) / abs(metric_as_used)
  degradation <- max(0, raw_degradation)
  degradation_pct <- degradation * 100

  if (degradation >= 0.40) {
    cli::cli_abort(
      c(
        "x" = paste0(
          "CHECK 6 (#554): {metric_name} degrades by {round(degradation_pct, 1)}% ",
          "when fundamentals are shifted to their worst-case public-availability ",
          "date (period_end + {FUNDAMENTAL_MAX_LAG_DAYS}d) -- above the 40% FAIL threshold."
        ),
        "i" = "{metric_name} as-used: {round(metric_as_used, 4)}; lag-shifted: {round(metric_lag_shifted, 4)}.",
        "i" = "The difference was never alpha -- it was the filing-lag peek. See #553/#554.",
        ">" = "Delay every fundamental input's availability date to period_end + FUNDAMENTAL_MAX_LAG_DAYS before joining, or drop the fundamental feature."
      ),
      class = "hd_fundamentals_lag_shift_fail"
    )
  }

  if (degradation >= 0.15) {
    cli::cli_warn(
      c(
        "!" = paste0(
          "CHECK 6 (#554): {metric_name} degrades by {round(degradation_pct, 1)}% ",
          "under the filing-lag shift -- in the 15-40% investigate band."
        ),
        "i" = "{metric_name} as-used: {round(metric_as_used, 4)}; lag-shifted: {round(metric_lag_shifted, 4)}.",
        "i" = "Log this gap in the strategy's experiment commit message."
      ),
      class = "hd_fundamentals_lag_shift_warn"
    )
    return(invisible(list(
      metric_as_used = metric_as_used, metric_lag_shifted = metric_lag_shifted,
      degradation_pct = degradation_pct, verdict = "warn"
    )))
  }

  cli::cli_alert_success(
    "CHECK 6 (#554): {metric_name} degrades only {round(degradation_pct, 1)}% under the filing-lag shift -- OK."
  )
  invisible(list(
    metric_as_used = metric_as_used, metric_lag_shifted = metric_lag_shifted,
    degradation_pct = degradation_pct, verdict = "ok"
  ))
}

#' Assert no fundamental row was visible before its filing date (#555)
#'
#' `leaked_pct = mean(visible_date < first_filed)` over an assembled
#' fundamentals-feature frame -- any row a strategy could "see" before it
#' was publicly filed is look-ahead by construction. Fails the pipeline on
#' any leak (strict; `first_filed <= as_of` is the article's inclusive
#' same-day-tradable convention -- pass `strict_same_day = TRUE` to require
#' `first_filed < visible_date` instead).
#'
#' @param df Data frame / tibble exposing `visible_col` and `filed_col`.
#' @param visible_col Column name holding the date/time a row entered a
#'   feature (default `"visible_date"`).
#' @param filed_col Column name holding the public-availability date
#'   (default `"first_filed"`).
#' @param strict_same_day If `TRUE`, a same-day visible/filed pair also
#'   counts as leaked (`visible_date <= first_filed`). Default `FALSE`
#'   treats same-day as OK (`visible_date < first_filed` is the leak
#'   condition).
#' @param sample_n Max number of offending rows to include in the failure
#'   message. Default 10.
#' @return Invisibly, a list with `leaked_pct`, `n_leaked`, `n_total`.
#'   Aborts (does not return) on any leaked row.
#' @family quality-audit
#' @noRd
check_fundamentals_join_dates <- function(df, visible_col = "visible_date",
                                           filed_col = "first_filed",
                                           strict_same_day = FALSE,
                                           sample_n = 10L) {
  required_cols <- c(visible_col, filed_col)
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(
      c(
        "x" = "Fundamentals feature frame is missing {length(missing_cols)} required column(s): {missing_cols}.",
        "i" = "check_fundamentals_join_dates() (#555) requires {visible_col} and {filed_col}."
      ),
      class = "hd_fundamentals_join_dates_missing_cols"
    )
  }

  visible <- df[[visible_col]]
  filed   <- df[[filed_col]]

  leaked <- if (isTRUE(strict_same_day)) visible <= filed else visible < filed
  leaked[is.na(leaked)] <- TRUE  # an unresolvable comparison is a leak, not a pass (fail-loud-not-null)

  n_total  <- length(leaked)
  n_leaked <- sum(leaked)
  leaked_pct <- if (n_total == 0L) 0 else 100 * n_leaked / n_total

  if (n_leaked > 0L) {
    offenders <- df[leaked, , drop = FALSE]
    offenders <- utils::head(offenders, sample_n)
    id_cols <- intersect(c("ticker", "fiscal_period", "xbrl_tag"), names(offenders))
    sample_lines <- if (length(id_cols) > 0L) {
      apply(offenders[id_cols], 1L, function(r) paste(r, collapse = " / "))
    } else {
      as.character(seq_len(nrow(offenders)))
    }
    cli::cli_abort(
      c(
        "x" = "Join-date audit (#555): {round(leaked_pct, 3)}% of rows ({n_leaked}/{n_total}) are visible before their filing date.",
        "i" = "Sample offending row(s): {sample_lines}",
        ">" = "Any row where {visible_col} < {filed_col} is look-ahead by construction -- fix the join, not the threshold."
      ),
      class = "hd_fundamentals_join_dates_leak"
    )
  }

  cli::cli_alert_success("Join-date audit (#555): leaked_pct = {round(leaked_pct, 3)}% ({n_leaked}/{n_total}) -- OK.")
  invisible(list(leaked_pct = leaked_pct, n_leaked = n_leaked, n_total = n_total))
}

# ---- QA gate plan ---------------------------------------------------------

#' Fundamentals QA gates (#554 CHECK 6, #555 join-date audit)
#'
#' Both targets are guarded on the presence of an `hd_fundamentals()` call
#' site anywhere in R/ (excluding this file). No fundamentals-consuming
#' strategy exists yet, so both currently no-op with an info message on
#' every real `tar_make()` -- see this file's header comment for why that
#' is the correct, honest behaviour today, and what activates them.
#' @return List of two `targets::tar_target()` definitions.
plan_qa_fundamentals <- function() {
  list(
    targets::tar_target(
      qa_fundamentals_lag_shift,
      command = {
        r_files <- list.files(here::here("R"), pattern = "\\.R$",
                               full.names = TRUE, recursive = TRUE)
        r_files <- r_files[basename(r_files) != "plan_qa_fundamentals.R"]
        hits <- check_hd_fundamentals_usage(r_files)

        if (nrow(hits) == 0L) {
          cli::cli_inform(c(
            "i" = "qa_fundamentals_lag_shift: no hd_fundamentals() call site found -- skipping CHECK 6 (guard, #554)."
          ))
        } else {
          locs <- sprintf("%s:%d", basename(hits$file), hits$line)
          cli::cli_abort(
            c(
              "x" = "{nrow(hits)} call site(s) of hd_fundamentals() found, but no CHECK 6 lag-shift comparison is wired for them: {locs}",
              "i" = "A fundamentals-consuming strategy now exists. Its own QA target must call check_fundamentals_lag_shift(metric_as_used, metric_lag_shifted) with the real headline metric computed both ways -- see #554 and R/plan_qa_fundamentals.R.",
              ">" = "This gate cannot auto-locate which target's returns to compare; wiring is deliberate, not automatic."
            ),
            class = "hd_fundamentals_lag_shift_unwired"
          )
        }
        nrow(hits)  # 0 on the no-op path; downstream gates can depend on this value target
      },
      cue = targets::tar_cue(mode = "always")
    ),
    targets::tar_target(
      qa_fundamentals_join_dates,
      command = {
        r_files <- list.files(here::here("R"), pattern = "\\.R$",
                               full.names = TRUE, recursive = TRUE)
        r_files <- r_files[basename(r_files) != "plan_qa_fundamentals.R"]
        hits <- check_hd_fundamentals_usage(r_files)

        if (nrow(hits) == 0L) {
          cli::cli_inform(c(
            "i" = "qa_fundamentals_join_dates: no hd_fundamentals() call site found -- skipping join-date audit (guard, #555)."
          ))
        } else {
          locs <- sprintf("%s:%d", basename(hits$file), hits$line)
          cli::cli_abort(
            c(
              "x" = "{nrow(hits)} call site(s) of hd_fundamentals() found, but no join-date audit is wired for them: {locs}",
              "i" = "A fundamentals-consuming strategy now exists. Its own QA target must call check_fundamentals_join_dates(feature_frame) on the assembled fundamentals-feature frame -- see #555 and R/plan_qa_fundamentals.R.",
              ">" = "This gate cannot auto-locate the assembled feature frame; wiring is deliberate, not automatic."
            ),
            class = "hd_fundamentals_join_dates_unwired"
          )
        }
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    )
  )
}
