# Capacity estimation: market-impact cost as a function of order size,
# and a resulting net-Sharpe/net-CAGR-vs-AUM curve.
#
# Origin: issues #508 and #794. Both diagnose the SAME gap from opposite
# directions -- #508 is the feature request (a market-impact model -> AUM
# ceiling / net-Sharpe-vs-AUM curve, citing the Concretum Group "I-Star"
# capacity write-up), #794 is the underlying diagnosis ("capacity is never
# modelled: every leaderboard Sharpe is implicitly a zero-AUM Sharpe").
# Every leaderboard metric in this package is computed on realised RETURNS
# -- none of them are conditioned on the capital that would have to be
# deployed to earn those returns, and market impact grows worse exactly
# where a strategy's signal is strongest (thin liquidity), not linearly.
#
# ── What this file implements (and what it deliberately does NOT) ──────────
#
# hd_market_impact() implements the SQUARE-ROOT LAW of market impact -- a
# long-standing, PUBLICLY documented model (Almgren, Thum, Hauptmann & Li,
# 2005, "Direct Estimation of Equity Market Impact"; also Barra/MSCI's
# published impact model uses the same functional form). This is the
# "documented default" #508's checklist explicitly asks for, and is cited
# to a PUBLIC source, independent of the paywalled Concretum article.
#
# The Concretum article's own "I-Star" model (disclosed constants a1=708,
# a2=0.55, a3=0.71 in its PUBLIC preview) is NOT implemented here. #508's
# checklist item explicitly requires re-implementing it "from the disclosed
# form" without copying paywalled code -- but the preview discloses only
# the three calibration CONSTANTS, not the combining formula itself (which
# power each constant enters at, how sigma and ADV combine with them). Per
# `external-code-zero-trust.md`, guessing a formula and labelling it
# "I-Star" would misattribute a fabricated model to a named third-party
# source -- worse than declining to implement it. This is an EXPLICIT,
# DEFERRED scope cut, not an oversight: see the roxygen "Deferred" section
# on hd_market_impact() below, and the #508/#794 PR report.
#
# hd_capacity_curve() also deliberately does NOT implement:
#   - the AUM-normalised cost helper `tcosts^norm = AUM_{t-1} *
#     tcosts(AUM_ref)/AUM_ref` from #508's checklist (a distinct
#     accounting convenience for reporting a curve already computed here
#     under a different capital base -- not needed for the underlying
#     Sharpe/CAGR-vs-AUM curve itself);
#   - order-slicing (n_slices) capacity extension;
#   - a wired `strategy_capacity` pipeline target. Wiring a NEW target into
#     docs/_targets.R cannot be verified from a worktree session --
#     `scripts/build.sh` (the only check that actually runs a target body
#     against the real store) is documented (.claude/CLAUDE.md "Verifying a
#     change") as MAIN-CHECKOUT ONLY, to avoid two processes racing the
#     same docs/_targets store. Shipping an unwired, unverified target
#     would violate `verification-before-completion`. These two functions
#     are therefore pure, dependency-free, and fully unit-tested instead --
#     see packages/historicaldata/tests/testthat/test-capacity.R -- ready
#     to be wired into a `strategy_capacity` target (using stk_monthly_adv,
#     R/plan_stock_backtest.R:654, and strategy_names$turnover_pct_per_
#     period_avg as inputs) by a follow-up session with main-checkout
#     access.

#' Market impact cost under the square-root law
#'
#' Estimates the one-way market-impact cost of trading a dollar order size
#' against a given average daily volume (ADV), as a FRACTION of the order's
#' notional value. Implements the square-root law of market impact: impact
#' cost grows with the SQUARE ROOT of participation rate (order size / ADV),
#' not linearly -- the mechanism #794 names as "turnover and slippage grow
#' faster than linearly exactly when liquidity thins".
#'
#' @section Formula:
#' \deqn{impact\_frac = \eta \cdot \sigma \cdot \sqrt{Q / ADV}}
#' where \eqn{\sigma} is the return volatility of the traded instrument over
#' the SAME period as \code{adv_usd} (e.g. daily volatility if \code{adv_usd}
#' is a daily ADV figure), \eqn{Q} is the order's dollar notional, and
#' \eqn{\eta} (\code{eta}) is a dimensionless calibration constant (order 1
#' for liquid large-cap equities in the published literature; this function
#' defaults to \code{eta = 1} and makes no claim beyond "order of magnitude"
#' without asset-class-specific calibration -- see Deferred, below).
#'
#' @section Deferred (NOT implemented here):
#' The Concretum Group "I-Star" market-impact model (disclosed constants
#' a1=708, a2=0.55, a3=0.71 in its public preview;
#' \url{https://concretumgroup.substack.com/p/estimating-the-capacity-of-a-trading})
#' is NOT implemented. The public preview discloses only the three
#' calibration constants, not the formula that combines them with sigma and
#' ADV -- the combining formula itself is behind the paywall. Per
#' \code{external-code-zero-trust.md}, this function does not guess a
#' formula and attribute it to a named third party; \code{method = "istar"}
#' is reserved but errors informatively until a from-scratch derivation
#' (from a source we can read in full, not summarised) is available.
#'
#' @param order_usd Numeric vector, must be >= 0. Dollar notional of the
#'   order (one leg -- for a round-trip, call this function once per leg or
#'   double the result; see \code{\link{hd_capacity_curve}} which does the
#'   latter).
#' @param adv_usd Numeric vector, must be > 0 (recycled against
#'   \code{order_usd}). Average daily dollar volume of the traded
#'   instrument(s)/portfolio.
#' @param sigma Numeric vector, must be >= 0 (recycled against
#'   \code{order_usd}). Return volatility (NOT annualised) over the same
#'   period as \code{adv_usd} -- e.g. daily return SD if \code{adv_usd} is a
#'   daily ADV.
#' @param eta Numeric scalar > 0. Calibration constant. Default `1`.
#' @param method Character scalar, currently only `"sqrt"` (the square-root
#'   law, the default and only implemented method). `"istar"` is reserved
#'   and errors -- see Deferred, above.
#'
#' @return Numeric vector (same length as the recycled inputs): one-way
#'   market-impact cost as a FRACTION of \code{order_usd} (e.g. `0.003` ==
#'   30 bps).
#'
#' @references
#' Almgren, R., Thum, C., Hauptmann, E., & Li, H. (2005). "Direct Estimation
#' of Equity Market Impact." \emph{Risk}, 18, 57-62. (Square-root law;
#' publicly available, not the paywalled Concretum source.)
#'
#' @examples
#' # $1M order against $50M ADV, 1.5% daily vol
#' hd_market_impact(order_usd = 1e6, adv_usd = 5e7, sigma = 0.015)
#'
#' @family capacity
#' @export
hd_market_impact <- function(order_usd, adv_usd, sigma, eta = 1, method = "sqrt") {
  if (!is.numeric(order_usd) || length(order_usd) == 0L || anyNA(order_usd) ||
      any(order_usd < 0)) {
    cli::cli_abort(c(
      "x" = "{.arg order_usd} must be a non-empty numeric vector with no NA and no negative values.",
      "i" = "Got {.val {order_usd}}."
    ))
  }
  if (!is.numeric(adv_usd) || length(adv_usd) == 0L || anyNA(adv_usd) ||
      any(adv_usd <= 0)) {
    cli::cli_abort(c(
      "x" = "{.arg adv_usd} must be a non-empty numeric vector with no NA and strictly positive values.",
      "i" = "Got {.val {adv_usd}}."
    ))
  }
  if (!is.numeric(sigma) || length(sigma) == 0L || anyNA(sigma) || any(sigma < 0)) {
    cli::cli_abort(c(
      "x" = "{.arg sigma} must be a non-empty numeric vector with no NA and no negative values.",
      "i" = "Got {.val {sigma}}."
    ))
  }
  if (!is.numeric(eta) || length(eta) != 1L || is.na(eta) || eta <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg eta} must be a single positive number.",
      "i" = "Got {.val {eta}}."
    ))
  }
  if (!identical(method, "sqrt")) {
    if (identical(method, "istar")) {
      cli::cli_abort(c(
        "x" = "{.arg method} = \"istar\" is not implemented.",
        "i" = paste0(
          "The Concretum Group I-Star model's public preview discloses only ",
          "three calibration constants (a1=708, a2=0.55, a3=0.71), not the ",
          "formula combining them with sigma/ADV -- that formula is behind ",
          "the paywall. Guessing it would misattribute a fabricated model ",
          "to a named third party (external-code-zero-trust.md). Use ",
          "method = \"sqrt\" (the square-root law, publicly documented) ",
          "instead, or supply a from-scratch derivation."
        )
      ))
    }
    cli::cli_abort(c(
      "x" = "{.arg method} must be {.val sqrt}.",
      "i" = "Got {.val {method}}."
    ))
  }

  participation <- order_usd / adv_usd
  eta * sigma * sqrt(participation)
}

#' Net-Sharpe / net-CAGR-vs-AUM capacity curve
#'
#' Sweeps a grid of assumed asset-under-management (AUM) levels and, for
#' each, estimates the round-trip market-impact cost a strategy would incur
#' rebalancing that AUM at its historical turnover, deducts it from the
#' strategy's REALISED monthly return series, and reports the resulting net
#' Sharpe and net CAGR. This is the diagnostic #794 asks for: "at least one
#' size-conditioned metric... so the degradation is legible rather than
#' asserted."
#'
#' Every leaderboard Sharpe elsewhere in this package (and in the
#' \code{leaderboard} target, R/plan_leaderboard.R) is implicitly the
#' \code{aum = 0} row of this curve -- the point at which market impact
#' vanishes and only the strategy's OWN cost model (if any) applies.
#'
#' @param monthly_ret Numeric vector of monthly strategy returns (already
#'   net of the strategy's own internal cost model, if it has one -- this
#'   function adds an ADDITIONAL, AUM-conditioned impact-cost layer on top,
#'   the same "layer atop the strategy's own model" convention used
#'   elsewhere in this package's cost handling; see
#'   \code{.claude/rules/fail-loud-not-null.md}-adjacent comments in
#'   R/plan_leaderboard.R's `STRATEGY_COST_BASIS` for the precedent).
#' @param aum_grid Numeric vector of AUM levels to sweep, must be >= 0 and
#'   strictly increasing.
#' @param adv_usd Numeric scalar > 0. Average daily dollar volume the
#'   strategy trades against (e.g. the strategy's portfolio-weighted ADV --
#'   see \code{R/plan_stock_backtest.R}'s \code{stk_monthly_adv} target for
#'   a per-ticker source to aggregate from).
#' @param turnover_frac Numeric scalar in `(0, 1]`. Fraction of AUM traded
#'   per rebalance period (one leg) -- e.g. `1.0` for a strategy that fully
#'   turns over every month. Round-trip order size per rebalance is assumed
#'   to be `aum * turnover_frac` traded away and the same traded back in.
#' @param eta Numeric scalar > 0, passed to \code{\link{hd_market_impact}}.
#'   Default `1`.
#' @param ann_factor Numeric scalar > 0. Periods per year for
#'   \code{monthly_ret} (default `12`).
#'
#' @return A tibble with one row per \code{aum_grid} element:
#'   \describe{
#'     \item{aum}{The AUM level.}
#'     \item{participation}{\code{aum * turnover_frac / adv_usd} -- the
#'       fraction of ADV this AUM's rebalance would need to trade.}
#'     \item{impact_cost_frac}{Round-trip (both legs) market-impact cost,
#'       as a fraction of AUM, per rebalance period.}
#'     \item{net_sharpe}{Annualised Sharpe of \code{monthly_ret} after
#'       deducting \code{impact_cost_frac} from every period.}
#'     \item{net_cagr}{Annualised compound growth rate after the same
#'       deduction.}
#'     \item{gross_sharpe}{Annualised Sharpe of \code{monthly_ret} with NO
#'       impact-cost deduction (the \code{aum = 0} reference point; constant
#'       across every row).}
#'   }
#'   Attribute \code{capacity_aum_ceiling}: the smallest \code{aum_grid}
#'   value at which \code{net_sharpe <= 0}, or \code{NA_real_} if
#'   \code{net_sharpe} stays positive across the entire grid (in which case
#'   the ceiling is ABOVE the grid's range, not "no ceiling" -- widen
#'   \code{aum_grid} to find it).
#'
#' @examples
#' set.seed(1)
#' rets <- rnorm(60, mean = 0.01, sd = 0.04)
#' curve <- hd_capacity_curve(
#'   monthly_ret = rets, aum_grid = c(1e6, 1e7, 1e8, 1e9),
#'   adv_usd = 5e7, turnover_frac = 1.0
#' )
#' curve
#' attr(curve, "capacity_aum_ceiling")
#'
#' @family capacity
#' @export
hd_capacity_curve <- function(monthly_ret, aum_grid, adv_usd, turnover_frac,
                               eta = 1, ann_factor = 12) {
  if (!is.numeric(monthly_ret) || length(monthly_ret) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg monthly_ret} must be a numeric vector with at least 2 observations.",
      "i" = "Got length {length(monthly_ret)}."
    ))
  }
  ret <- monthly_ret[!is.na(monthly_ret)]
  if (length(ret) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg monthly_ret} has fewer than 2 non-NA observations after removing NAs.",
      "i" = "Got {length(ret)} non-NA of {length(monthly_ret)} total."
    ))
  }
  if (!is.numeric(aum_grid) || length(aum_grid) == 0L || anyNA(aum_grid) ||
      any(aum_grid < 0) || is.unsorted(aum_grid, strictly = TRUE)) {
    cli::cli_abort(c(
      "x" = "{.arg aum_grid} must be a non-empty, strictly increasing numeric vector with no NA and no negative values.",
      "i" = "Got {.val {aum_grid}}."
    ))
  }
  if (!is.numeric(adv_usd) || length(adv_usd) != 1L || is.na(adv_usd) || adv_usd <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg adv_usd} must be a single positive number.",
      "i" = "Got {.val {adv_usd}}."
    ))
  }
  if (!is.numeric(turnover_frac) || length(turnover_frac) != 1L ||
      is.na(turnover_frac) || turnover_frac <= 0 || turnover_frac > 1) {
    cli::cli_abort(c(
      "x" = "{.arg turnover_frac} must be a single number in (0, 1].",
      "i" = "Got {.val {turnover_frac}}."
    ))
  }
  if (!is.numeric(ann_factor) || length(ann_factor) != 1L || is.na(ann_factor) ||
      ann_factor <= 0) {
    cli::cli_abort(c(
      "x" = "{.arg ann_factor} must be a single positive number.",
      "i" = "Got {.val {ann_factor}}."
    ))
  }

  n <- length(ret)
  sigma_period <- stats::sd(ret)

  gross_sharpe <- (mean(ret) / sigma_period) * sqrt(ann_factor)

  rows <- lapply(aum_grid, function(aum) {
    order_usd <- aum * turnover_frac
    if (order_usd <= 0) {
      impact_one_leg <- 0
      participation <- 0
    } else {
      impact_one_leg <- hd_market_impact(order_usd, adv_usd, sigma_period, eta = eta)
      participation <- order_usd / adv_usd
    }
    # Round-trip: cost incurred entering AND exiting the position each period.
    impact_cost_frac <- 2 * impact_one_leg

    net_ret <- ret - impact_cost_frac
    sigma_net <- stats::sd(net_ret)
    net_sharpe <- if (sigma_net > 0) (mean(net_ret) / sigma_net) * sqrt(ann_factor) else NA_real_
    net_cagr <- prod(1 + net_ret)^(ann_factor / n) - 1

    tibble::tibble(
      aum = aum,
      participation = participation,
      impact_cost_frac = impact_cost_frac,
      net_sharpe = net_sharpe,
      net_cagr = net_cagr,
      gross_sharpe = gross_sharpe
    )
  })

  out <- dplyr::bind_rows(rows)

  below_zero <- which(out$net_sharpe <= 0)
  capacity_aum_ceiling <- if (length(below_zero) > 0L) {
    out$aum[min(below_zero)]
  } else {
    NA_real_
  }
  attr(out, "capacity_aum_ceiling") <- capacity_aum_ceiling

  out
}
