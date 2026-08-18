# Canonical backtest annualisation metrics
#
# Single source of truth for leaderboard metrics so all plans produce
# comparable Sharpe, CAGR, vol, max drawdown, and Calmar values.
# Uses compound (geometric) annualisation — what investors actually earn.
#
# Formula:
#   CAGR   = cumprod(1 + r)[n] ^ (periods_per_year / n) - 1
#   vol    = sd(r) * sqrt(periods_per_year)
#   Sharpe = CAGR / vol

#' Annualise periodic returns — canonical helper
#'
#' Annualises a vector of periodic returns (monthly assumed by default).
#' Returns include CAGR (geometric), annual vol, Sharpe (CAGR / vol),
#' max drawdown, and Calmar.
#'
#' Uses compound (geometric) annualisation throughout so results from
#' different plans are directly comparable on the leaderboard.
#'
#' @param ret Numeric vector of periodic returns (e.g., monthly).
#' @param periods_per_year Integer. Default 12L (monthly). Use 252L for
#'   daily or 4L for quarterly returns.
#' @param na.rm Logical. If \code{TRUE} (default), NA values are dropped
#'   before computation.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{cagr}{Compound annual growth rate (decimal, not percent).}
#'     \item{vol}{Annualised volatility (sd * sqrt(periods_per_year)).}
#'     \item{sharpe}{Sharpe ratio (CAGR / vol); NA when vol is zero.}
#'     \item{max_dd}{Maximum drawdown (negative number, e.g. -0.12 = -12\%).}
#'     \item{calmar}{Calmar ratio (CAGR / abs(max_dd)); NA when max_dd is zero.}
#'     \item{n}{Number of non-NA observations used.}
#'   }
#'
#' @family backtest
#' @export
annualise_returns <- function(ret, periods_per_year = 12L, na.rm = TRUE) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      periods_per_year <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a single positive number.",
      "i" = "Got {periods_per_year}."
    ))
  }

  if (isTRUE(na.rm)) ret <- ret[!is.na(ret)]

  n <- length(ret)
  if (n < 2L) {
    return(list(
      cagr   = NA_real_,
      vol    = NA_real_,
      sharpe = NA_real_,
      max_dd = NA_real_,
      calmar = NA_real_,
      n      = n
    ))
  }

  equity <- cumprod(1 + ret)
  cagr   <- equity[n]^(periods_per_year / n) - 1
  vol    <- stats::sd(ret) * sqrt(periods_per_year)
  sharpe <- if (vol > 0) cagr / vol else NA_real_
  max_dd <- min(equity / cummax(equity) - 1)
  calmar <- if (max_dd < 0) cagr / abs(max_dd) else NA_real_

  list(
    cagr   = cagr,
    vol    = vol,
    sharpe = sharpe,
    max_dd = max_dd,
    calmar = calmar,
    n      = n
  )
}

#' Canonical risk-free-adjusted Sharpe ratio — shared helper (#677)
#'
#' Computes \code{sharpe = (ann_ret - ann_rf) / ann_vol}, using geometric
#' (compound) annualisation for the return -- the majority convention already
#' used by \code{R/plan_factormax.R}, \code{R/plan_drif.R}, and
#' \code{R/plan_alpha_decay.R}. This is a DIFFERENT basis from
#' \code{annualise_returns()$sharpe} above, which is \code{cagr / vol} with
#' NO risk-free deduction -- that is the deliberately separate "no-rf family"
#' basis (\code{plan_managed_futures.R}, \code{plan_ev_ebit.R},
#' \code{bootstrap_ci()}; see issue #677 slice 2). Do not conflate the two;
#' migrating the no-rf family onto this helper is out of scope for #677
#' slice 1 and is tracked separately.
#'
#' Per \code{.claude/rules/fail-loud-not-null.md}, this function ABORTS
#' rather than silently treating a missing/absent risk-free input as zero:
#' issue #677 defect B was exactly this failure mode --
#' \code{mean(df$rf_ret, na.rm = TRUE)} against a column that did not exist
#' returned \code{NA} silently, and every downstream Sharpe was \code{NA}
#' from the day the target was written, discovered only by accident.
#'
#' @param ret Numeric vector of periodic returns (e.g., monthly).
#' @param rf Numeric vector of periodic risk-free returns, position-aligned
#'   with \code{ret} (same length, same periods, both already filtered to
#'   the same observations by the caller). Must not be \code{NULL}.
#' @param periods_per_year Integer. Default 12L (monthly). Use 252L for
#'   daily returns.
#' @param na.rm Logical. If \code{TRUE} (default), positions where either
#'   \code{ret} or \code{rf} is \code{NA} are dropped (pairwise) before
#'   computation.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{ann_ret}{Annualised return (geometric/compound).}
#'     \item{ann_rf}{Annualised risk-free rate (arithmetic mean * periods_per_year).}
#'     \item{ann_vol}{Annualised volatility (sd * sqrt(periods_per_year)).}
#'     \item{sharpe}{(ann_ret - ann_rf) / ann_vol; NA when vol is zero or
#'       fewer than 2 observations remain.}
#'     \item{n}{Number of paired non-NA observations used.}
#'   }
#'
#' @family backtest
#' @export
sharpe_ratio_rf <- function(ret, rf, periods_per_year = 12L, na.rm = TRUE) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (is.null(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg rf} must not be NULL.",
      "i" = "A missing risk-free series must never be treated as zero -- see fail-loud-not-null.md (#677 defect B).",
      "i" = "Join a risk-free series (e.g. the {.code stk_rf} target: ym, rf_ret) onto your data before calling {.fn sharpe_ratio_rf}."
    ))
  }
  if (!is.numeric(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg rf} must be a numeric vector.",
      "i" = "Got {.cls {class(rf)}}."
    ))
  }
  if (length(ret) != length(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} and {.arg rf} must be the same length.",
      "i" = "Got length {length(ret)} and {length(rf)}."
    ))
  }
  if (!is.numeric(periods_per_year) || length(periods_per_year) != 1L ||
      periods_per_year <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg periods_per_year} must be a single positive number.",
      "i" = "Got {periods_per_year}."
    ))
  }

  if (isTRUE(na.rm)) {
    keep <- !is.na(ret) & !is.na(rf)
    ret  <- ret[keep]
    rf   <- rf[keep]
  }

  n <- length(ret)
  if (n < 2L) {
    return(list(
      ann_ret = NA_real_,
      ann_rf  = NA_real_,
      ann_vol = NA_real_,
      sharpe  = NA_real_,
      n       = n
    ))
  }

  equity  <- cumprod(1 + ret)
  ann_ret <- equity[n]^(periods_per_year / n) - 1
  ann_vol <- stats::sd(ret) * sqrt(periods_per_year)
  ann_rf  <- mean(rf) * periods_per_year

  if (!is.finite(ann_vol)) {
    cli::cli_abort(c(
      "x" = "Computed annualised volatility is not finite.",
      "i" = "Got {ann_vol}.",
      "i" = "Check {.arg ret} for Inf/-Inf values before calling {.fn sharpe_ratio_rf}."
    ))
  }

  sharpe <- if (ann_vol > 0) (ann_ret - ann_rf) / ann_vol else NA_real_

  list(
    ann_ret = ann_ret,
    ann_rf  = ann_rf,
    ann_vol = ann_vol,
    sharpe  = sharpe,
    n       = n
  )
}

#' Join a risk-free series onto a return series by a shared key (#677 slice 3b)
#'
#' Canonical THREE-CASE risk-free coverage policy, shared by every strategy
#' that left-joins a Fama-French risk-free series onto its own return
#' series. Before this helper existed, the same ~40-line policy was
#' duplicated near-verbatim across four call sites -- \code{.ltr_join_rf()}
#' (\code{R/plan_ltr_momentum.R}), \code{.tom_join_rf_daily()}
#' (\code{R/plan_turn_of_month.R}), \code{.mom_prepeak_join_rf()}
#' (\code{R/plan_mom_prepeak.R}), and CMR's own
#' (\code{R/plan_commodities_mean_reversion.R}) -- see issue #677.
#'
#' Consolidating also fixes the gap PR #684 found: none of the four
#' distinguished a LEADING gap (the return series starts before the
#' risk-free series does) from an INTERIOR one (a real hole inside the
#' risk-free series' own span). A leading gap was reported as "a HOLE in
#' the series", sending a reader hunting for a gap that does not exist.
#'
#' Per \code{fail-loud-not-null.md}, a missing risk-free rate must NEVER be
#' silently coerced to \code{NA}/zero/a dropped row without comment. The
#' three cases:
#'   \describe{
#'     \item{LEADING}{\code{key < min(rf[[key]])}. The risk-free series
#'       simply does not go back this far -- by construction, not because
#'       of a gap in its own coverage. \strong{Aborts}, naming it
#'       "leading", never "hole".}
#'     \item{TRAILING}{\code{key > max(rf[[key]])}. A Fama-French
#'       publication lag -- expected, not a bug. TRIMMED with a loud,
#'       counted \code{cli_warn} naming the dropped periods and the
#'       effective end date (per fail-loud-not-null.md's "Make the drop
#'       observable").}
#'     \item{INTERIOR}{\code{min(rf[[key]]) <= key <= max(rf[[key]])} but
#'       missing. A real hole inside the risk-free series' own span.
#'       \strong{Aborts.}}
#'   }
#' If a return series has both leading and interior gaps, leading is
#' reported first -- it is the more fundamental "no risk-free rate exists
#' for this period at all" case.
#'
#' This is a pure function (no target/database access), so it is
#' unit-testable directly -- see \code{tests/testthat/test-join-rf-series.R}.
#' PR #678's guard shipped untested because it lived inside a target
#' reading a gitignored parquet, which is exactly how it broke `main` twice.
#'
#' @param df Tibble to join `rf` onto. Must already have the `key` column
#'   (or pass \code{check_key_col = FALSE} when the caller derives it
#'   itself immediately before calling).
#' @param rf Tibble with columns `key`, `rf_ret`.
#' @param key Character. Name of the shared join column: \code{"ym"}
#'   (monthly, character \code{"YYYY-MM"}) or \code{"date"} (daily, a
#'   `Date` column).
#' @param label Character. Function identity used in error/warning message
#'   prefixes, e.g. \code{".ltr_join_rf"}.
#' @param rf_label Character. How the risk-free series is named in prose,
#'   e.g. \code{"stk_rf"} or \code{"daily_rf"}.
#' @param rf_source Character. Where `rf` comes from, cited in the
#'   missing-columns message and the interior-gap investigate line, e.g.
#'   \code{"R/plan_stock_backtest.R"}.
#' @param df_label Character. Name of `df` for warning/abort text, e.g.
#'   \code{"ltr_portfolio"} or \code{"CMR 1m portfolio"}.
#' @param strategy_label Character. Strategy name for the
#'   trust-this-Sharpe line, e.g. \code{"LTR"} or \code{"CMR 1m"}.
#' @param period_noun Character. \code{"month"} or \code{"date"} -- used
#'   for cli's pluralisation (\code{{period_noun}{?s}}).
#' @param check_key_col Logical. If \code{TRUE} (default), abort when `df`
#'   has no `key` column. Callers that derive `key` themselves just before
#'   calling (e.g. mom_prepeak deriving `ym` from `exec_date`), or that
#'   already guarantee it by construction (e.g. CMR), pass `FALSE`.
#' @param df_arg_name Character. Word used for `df` in the
#'   missing-key-column message, e.g. \code{"port"}.
#'
#' @return `df` with `rf_ret` joined; trailing uncovered periods removed.
#' @noRd
.join_rf_series <- function(df, rf, key,
                             label, rf_label, rf_source, df_label,
                             strategy_label, period_noun = "month",
                             check_key_col = TRUE, df_arg_name = "df") {
  required <- c(key, "rf_ret")
  missing_cols <- setdiff(required, names(rf))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{label}(): {rf_label} is missing {length(missing_cols)} required column{?s}: {.field {missing_cols}}.",
      "i" = "Expected a tibble with {key} and rf_ret ({rf_source})."
    ))
  }
  if (isTRUE(check_key_col) && !key %in% names(df)) {
    cli::cli_abort(c(
      "x" = "{label}(): {df_arg_name} has no {.field {key}} column to join on."
    ))
  }

  fmt <- function(x) if (inherits(x, "Date")) format(x) else x

  df_key_range <- range(df[[key]])
  joined <- dplyr::left_join(df, rf, by = key)

  missing_key <- sort(joined[[key]][is.na(joined$rf_ret)])
  if (length(missing_key) == 0L) return(joined)

  rf_min <- min(rf[[key]])
  rf_max <- max(rf[[key]])

  leading  <- missing_key[missing_key < rf_min]
  interior <- missing_key[missing_key >= rf_min & missing_key <= rf_max]

  if (length(leading) > 0L) {
    cli::cli_abort(c(
      "x" = "{length(leading)} {period_noun}{?s} come before {rf_label} even starts ({strategy_label}).",
      "i" = "Missing {period_noun}{?s}: {.val {fmt(leading)}}.",
      "i" = "{rf_label} starts {fmt(rf_min)}; {df_label} starts {fmt(df_key_range[1])}.",
      "i" = "This is LEADING coverage: the risk-free series simply does not reach this far back yet -- a different situation from a gap inside its own span.",
      "i" = "Trim {df_label} to start no earlier than {fmt(rf_min)}, or source an earlier {rf_label}."
    ))
  }

  if (length(interior) > 0L) {
    cli::cli_abort(c(
      "x" = "{length(interior)} {period_noun}{?s} inside {rf_label}'s own span have no risk-free rate ({strategy_label}).",
      "i" = "Missing {period_noun}{?s}: {.val {fmt(interior)}}.",
      "i" = "{rf_label} spans {fmt(rf_min)}..{fmt(rf_max)}, so this is a HOLE in the series, not a publication lag.",
      "i" = "Investigate the FF3 source ({rf_source}) before trusting any {strategy_label} Sharpe figure."
    ))
  }

  # trailing -- Fama-French publication lag; trim + loud, counted warn
  n_before <- nrow(joined)
  joined <- dplyr::filter(joined, !is.na(.data$rf_ret))
  cli::cli_warn(c(
    "!" = "Dropped {n_before - nrow(joined)} trailing {period_noun}{?s} from {df_label} with no risk-free rate yet.",
    "i" = "Dropped {period_noun}{?s}: {.val {fmt(missing_key)}}.",
    "i" = "{df_label} spans {fmt(df_key_range[1])}..{fmt(df_key_range[2])}; {rf_label} ends {fmt(rf_max)} (Fama-French publication lag).",
    "i" = "Every {strategy_label} metric is therefore computed through {fmt(rf_max)}, not {fmt(df_key_range[2])}."
  ))
  joined
}
