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
