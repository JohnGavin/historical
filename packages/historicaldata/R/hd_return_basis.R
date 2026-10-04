# Return-basis registry (#919)
#
# ONE home for "is this strategy's return series a TOTAL return (contains a
# cash / risk-free component) or an EXCESS return (a dollar-neutral spread)?".
# Every Sharpe in the repo -- the leaderboard's sharpe_ratio_rf() path AND
# strat_deflated_sharpe()'s hd_deflated_sharpe() path -- reads it from here
# instead of deciding independently (the divergence #919 found: leaderboard
# rf-deducted, DSR raw, so HML's DSR input was RF + HML - cost).
#
# fail-loud-not-null.md: an unregistered strategy is an error, never a silent
# default. A silent default of "total" (deduct rf) or "excess" (do not) would
# both produce a plausible-looking Sharpe on the wrong basis.

#' Allowed values of the \code{basis} column of \code{hd_return_basis()}
#' @noRd
.HD_RETURN_BASIS_VOCAB <- c("total", "excess", "indeterminate")

#' Return basis of every leaderboard strategy (#919)
#'
#' The single source of truth for whether a strategy's published return
#' series is on a \emph{total}-return or an \emph{excess}-return basis.
#'
#' \strong{The rule.} A strategy's Sharpe ratio is on an EXCESS-return basis.
#' The risk-free rate is deducted if and only if the series is a TOTAL return
#' (it contains a cash / risk-free component, e.g. \code{RF + HML - cost}, or
#' SPY-with-cash). A dollar-neutral long-short spread
#' (\code{ret_long - ret_short - costs}) is already an excess return and must
#' have NO risk-free rate deducted.
#'
#' \strong{Approximation.} Treating a long-short spread as excess assumes the
#' long-leg funding rate and the short-leg rebate rate cancel. They are
#' different rates and can diverge under stress; the residual is the
#' funding/rebate spread, which this repo models only through a constant
#' (e.g. \code{borrow_rate_annual = 0.005}, R/plan_mom_prepeak.R, marked
#' MANUAL). That residual is NOT modelled here.
#'
#' \strong{Values of \code{basis}.}
#' \describe{
#'   \item{\code{"total"}}{Series contains a cash / risk-free component;
#'     deduct rf before computing a Sharpe.}
#'   \item{\code{"excess"}}{Dollar-neutral spread; deduct NO rf.}
#'   \item{\code{"indeterminate"}}{The constructing code could not be
#'     classified under the rule (see \code{evidence}). Behaviour is left
#'     UNCHANGED on both paths: the leaderboard path keeps deducting rf, the
#'     deflated-Sharpe path keeps using the raw series. Flagged, never
#'     guessed.}
#' }
#'
#' @return A tibble with columns \code{strategy} (leaderboard label),
#'   \code{basis} (one of \code{"total"}, \code{"excess"},
#'   \code{"indeterminate"}) and \code{evidence} (file:line of the
#'   constructing code that justifies the classification).
#' @family backtest
#' @export
#' @examples
#' hd_return_basis()
#' hd_return_basis_of("Value (HML)")
hd_return_basis <- function() {
  tibble::tribble(
    ~strategy, ~basis, ~evidence,
    "Value (HML)", "total",
    "R/plan_ev_ebit.R:79 ret_value_hml = RF + HML - cost (RF is a component)",
    "Managed Futures", "total",
    "R/plan_managed_futures.R:157 ret_ls = RF + (...) (RF is a component)",
    "Risk State", "total",
    "R/plan_risk_state.R:209 exposure * spy_ret + (1 - exposure) * rf_daily (SPY plus cash)",
    "Avoid Worst", "total",
    "R/plan_avoid_worst.R:723 ifelse(in_market, SPY ret, 0) (SPY or cash)",
    "TOM", "total",
    "R/plan_turn_of_month.R ret_gross = if_else(in_tom, SPY ret, cash_rf_daily) (SPY or cash)",
    "OLMAR-1", "total",
    "R/plan_olmar.R olmar_backtest() long-only ETF weights, no short leg (net_ret total)",
    "Mom Pre-Peak", "excess",
    "R/plan_mom_prepeak.R:390 ret_ls = ret_long - ret_short - 2*cost - borrow/12 (dollar-neutral)",
    "Mom Post-Peak", "excess",
    "R/plan_mom_prepeak.R:390 ret_ls = ret_long - ret_short - 2*cost - borrow/12 (dollar-neutral)",
    "Mom 12-2", "excess",
    "R/plan_mom_prepeak.R:390 ret_ls = ret_long - ret_short - 2*cost - borrow/12 (dollar-neutral)",
    "LTR", "excess",
    "scripts/compute_ltr_model.R:152-158 ls_ret_net = long_ret - short_ret - cost - borrow (decile L/S)",
    "CMR", "excess",
    "packages/historicaldata/R/commodities_mean_reversion.R:834 weight = +/-1/n_leg (dollar-neutral terciles)",
    "CMR Conditioned", "indeterminate",
    "R/plan_commodities_mean_reversion.R:976 exposure_mult*net_ret + (1-exposure_mult)*rf: an excess spread blended with cash is neither total nor excess",
    "Stock MAX", "excess",
    "R/plan_stock_backtest.R:172,494 port_ret = long_ret - short_ret - total_cost (decile L/S)",
    "Stock DRIF", "excess",
    "R/plan_stock_backtest.R:172,494 port_ret = long_ret - short_ret - total_cost (decile L/S)",
    "XGB DRIF", "excess",
    "R/plan_xgb_signal.R:144 portfolio_longshort(short_decile = 10L) (decile L/S)",
    "Factor MAX", "excess",
    "R/plan_factormax.R:142 equal-weight of Fama-French HML/SMB/RMW/CMA/Mom spreads (no Mkt-RF, no RF)",
    "Factor DRIF", "excess",
    "R/plan_drif.R:243 equal-weight of Fama-French factor spreads (no Mkt-RF, no RF)",
    "PSO Optimal", "excess",
    "R/plan_portfolio_opt.R:226-241 normalised weighted average of the four excess series stk_max/stk_drif/fac_max/fac_drif"
  )
}

#' Look up one strategy's return basis (#919)
#'
#' @param strategy Single string; a leaderboard strategy label as listed in
#'   \code{\link{hd_return_basis}}.
#' @return Single string: \code{"total"}, \code{"excess"} or
#'   \code{"indeterminate"}.
#' @seealso \code{\link{hd_return_basis}}
#' @family backtest
#' @export
hd_return_basis_of <- function(strategy) {
  if (!is.character(strategy) || length(strategy) != 1L || is.na(strategy)) {
    cli::cli_abort(c(
      "x" = "{.arg strategy} must be a single non-NA string.",
      "i" = "Got {.cls {class(strategy)}} of length {length(strategy)}."
    ))
  }
  reg <- hd_return_basis()
  hit <- reg$basis[reg$strategy == strategy]
  if (length(hit) != 1L) {
    cli::cli_abort(c(
      "x" = "Strategy {.val {strategy}} is not registered in {.fn hd_return_basis}.",
      "i" = "Registered strategies: {.val {reg$strategy}}.",
      "i" = "Add it to {.file packages/historicaldata/R/hd_return_basis.R} with a file:line evidence string; a silent default would put its Sharpe on an unknown basis."
    ))
  }
  if (!hit %in% .HD_RETURN_BASIS_VOCAB) {
    cli::cli_abort(c(
      "x" = "Registry basis {.val {hit}} for {.val {strategy}} is outside the allowed set.",
      "i" = "Allowed: {.val {.HD_RETURN_BASIS_VOCAB}}."
    ))
  }
  hit
}

#' Risk-free series to deduct for a strategy's Sharpe (#919)
#'
#' Returns \code{rf} unchanged for a \code{"total"} (or \code{"indeterminate"},
#' legacy behaviour) strategy and an all-zero vector of the same length for an
#' \code{"excess"} one. Pass the result as the \code{rf} argument of a Sharpe
#' helper such as \code{sharpe_ratio_rf()}, so \code{ann_rf} is \code{0} and
#' \code{sharpe == (cagr - ann_rf) / vol} still holds.
#'
#' @param rf Numeric vector of periodic risk-free returns. NAs are preserved
#'   (they propagate as NA, not as zero, for total-basis strategies; for an
#'   excess strategy the zero vector is NA-free by design).
#' @param strategy Single string; see \code{\link{hd_return_basis_of}}.
#' @return Numeric vector, same length as \code{rf}.
#' @seealso \code{\link{hd_return_basis}}
#' @family backtest
#' @export
hd_rf_for_basis <- function(rf, strategy) {
  if (!is.numeric(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg rf} must be a numeric vector.",
      "i" = "Got {.cls {class(rf)}}."
    ))
  }
  if (identical(hd_return_basis_of(strategy), "excess")) {
    return(rep(0, length(rf)))
  }
  rf
}

#' Excess-return series for a strategy (#919)
#'
#' The series a deflated-Sharpe (or any other arithmetic) statistic must be
#' computed on. \code{"total"}: \code{ret - rf}. \code{"excess"}: \code{ret}
#' unchanged. \code{"indeterminate"}: \code{ret} unchanged (legacy raw-series
#' behaviour, see \code{\link{hd_return_basis}}).
#'
#' @param ret Numeric vector of periodic strategy returns.
#' @param rf Numeric vector of periodic risk-free returns, position-aligned
#'   with \code{ret} (same length). Must not be \code{NULL}.
#' @param strategy Single string; see \code{\link{hd_return_basis_of}}.
#' @return Numeric vector, same length as \code{ret}.
#' @seealso \code{\link{hd_return_basis}}
#' @family backtest
#' @export
hd_excess_returns <- function(ret, rf, strategy) {
  if (!is.numeric(ret)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} must be a numeric vector.",
      "i" = "Got {.cls {class(ret)}}."
    ))
  }
  if (is.null(rf) || !is.numeric(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg rf} must be a numeric vector (never NULL -- a missing rf is not zero).",
      "i" = "Got {.cls {class(rf)}}."
    ))
  }
  if (length(ret) != length(rf)) {
    cli::cli_abort(c(
      "x" = "{.arg ret} and {.arg rf} must be the same length.",
      "i" = "Got length {length(ret)} and {length(rf)}."
    ))
  }
  if (identical(hd_return_basis_of(strategy), "total")) {
    return(ret - rf)
  }
  ret
}
