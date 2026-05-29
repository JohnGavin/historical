# Commodities Mean Reversion Functions (Issue #138)
#
# Counterpart to commodities_momentum.R (Issue #134).
# #134 found momentum in commodities is broken (Sharpe -0.85 baseline,
# -0.89 to -0.91 decomposed). Hypothesis: if momentum doesn't work, mean
# reversion might — commodities have backwardation/contango cycles,
# supply/demand seasonality, and supply shocks that reverse.
#
# Strategy: long-losers / short-winners (opposite of momentum).
# Signal at month t uses returns through t-1 only (look-ahead-safe).
# Execution: signal at t -> trade at t+1 close (t+1 execution discipline).
#
# Data: monthly commodity prices (37 series, 1992-2026, ann_factor=12).
# Universe re-uses commodities_returns from plan_commodities_momentum.R.


#' Commodity Mean Reversion Signal
#'
#' Compute a monthly mean-reversion signal for a commodity universe.
#' The signal is the *negative* of the lookback-period return: commodities
#' that have fallen the most receive the highest (most positive) signal,
#' while those that have risen the most receive the lowest (most negative)
#' signal.
#'
#' Look-ahead safety: the signal at month \code{t} is constructed from
#' cumulative returns over months \code{(t - lookback_months)} through
#' \code{(t - 1)}.  The one-period lag is enforced via
#' \code{dplyr::lag(cumret)} before the negation, so no return at or after
#' month \code{t} ever enters signal formation.
#'
#' @param returns_tbl Tibble with columns \code{date} (Date, month-end),
#'   \code{series_id} (character), and \code{monthly_ret} (numeric monthly
#'   return).  Produced by \code{calculate_commodity_returns()}.
#' @param lookback_months Integer. Number of months used to compute the
#'   mean-reversion signal (default 3).  Typical values: 1, 3, 6.
#'
#' @return Tibble with columns:
#'   \describe{
#'     \item{date}{Month-end date.}
#'     \item{series_id}{Commodity identifier.}
#'     \item{mr_signal}{Mean-reversion signal = negative of cumulative
#'       return over the prior \code{lookback_months} months. Higher values
#'       (bigger recent losers) rank first for the long leg.}
#'   }
#'   Rows with \code{NA} signals (insufficient history) are dropped.
#'
#' @details
#' The cumulative return over a rolling window is computed as
#' \eqn{\prod_{i=1}^{L}(1 + r_{t-i}) - 1}, where \eqn{L} is
#' \code{lookback_months}.  This product is formed using
#' \code{slider::slide_dbl} with \code{.complete = TRUE} so partial windows
#' produce \code{NA}.  The result is then lagged by one period to guarantee
#' look-ahead safety, and the signal is the negation of the lagged cumulative
#' return.
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_signal <- function(returns_tbl, lookback_months = 3L) {
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} must be a data frame, not {.cls {class(returns_tbl)}}."
    ))
  }
  required_cols <- c("date", "series_id", "monthly_ret")
  missing_cols <- setdiff(required_cols, names(returns_tbl))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg returns_tbl} is missing required columns: {.field {missing_cols}}."
    ))
  }
  if (!is.numeric(lookback_months) || length(lookback_months) != 1L ||
      is.na(lookback_months) || lookback_months < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months} must be a positive integer, got {lookback_months}."
    ))
  }
  lookback_months <- as.integer(lookback_months)

  returns_tbl |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(
      # Cumulative return over the lookback window ending at t (inclusive of t).
      # .complete = TRUE ensures NA for partial windows.
      cumret_raw = slider::slide_dbl(
        monthly_ret,
        .f = function(r) prod(1 + r) - 1,
        .before = lookback_months - 1L,
        .after  = 0L,
        .complete = TRUE
      ),
      # Lag by 1: cumret at position t becomes the lookback return through t-1.
      # Signal = negation so recent losers have high (positive) signal.
      mr_signal = -dplyr::lag(cumret_raw, n = 1L)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(date, series_id, mr_signal) |>
    dplyr::filter(!is.na(mr_signal))
}


#' Commodity Mean Reversion Portfolio
#'
#' Convert a mean-reversion signal tibble into monthly long/short portfolio
#' weights with t+1 execution.
#'
#' Execution discipline: the signal from month \code{t} (formed from returns
#' through \code{t-1}) drives trades that are executed at month \code{t+1}
#' closing prices.  This is enforced by joining the signal at date \code{t}
#' to the return realised at date \code{t+1} via \code{dplyr::lead()}.
#'
#' @param signal_tbl Tibble returned by \code{\link{hd_commodity_mr_signal}},
#'   with columns \code{date}, \code{series_id}, \code{mr_signal}.
#' @param returns_tbl Tibble with columns \code{date}, \code{series_id},
#'   \code{monthly_ret}.  Must overlap in date range with \code{signal_tbl}.
#' @param n_long Integer. Number of top-ranked (biggest losers) commodities
#'   to hold long (default 10).
#' @param n_short Integer. Number of bottom-ranked (biggest winners) commodities
#'   to sell short (default 10).
#' @param cost_bps Numeric. One-way transaction cost in basis points
#'   (default 20 = 0.2\%).  The same 0.2\% used in commodity momentum (#134).
#'
#' @return Tibble with one row per month and columns:
#'   \describe{
#'     \item{date}{Month-end date (the execution month, i.e. t+1).}
#'     \item{gross_ret}{Gross portfolio return for the month.}
#'     \item{turnover}{One-way turnover fraction.}
#'     \item{cost}{Transaction cost deducted (= turnover * cost_bps/10000).}
#'     \item{net_ret}{Net return after transaction costs.}
#'     \item{n_long}{Number of long positions held.}
#'     \item{n_short}{Number of short positions held.}
#'   }
#'   Months where fewer than \code{n_long + n_short} commodities have valid
#'   signals are silently included with actual position counts; months with
#'   zero valid signals produce \code{gross_ret = 0}.
#'
#' @family commodities_mr
#' @export
hd_commodity_mr_portfolio <- function(signal_tbl,
                                       returns_tbl,
                                       n_long  = 10L,
                                       n_short = 10L,
                                       cost_bps = 20) {
  if (!is.data.frame(signal_tbl)) {
    cli::cli_abort(c("x" = "{.arg signal_tbl} must be a data frame."))
  }
  if (!is.data.frame(returns_tbl)) {
    cli::cli_abort(c("x" = "{.arg returns_tbl} must be a data frame."))
  }
  n_long  <- as.integer(n_long)
  n_short <- as.integer(n_short)
  if (n_long < 1L || n_short < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg n_long} and {.arg n_short} must each be >= 1."
    ))
  }

  cost_per_unit <- cost_bps / 10000

  # t+1 execution: for each commodity build (signal_date -> next_ret) pairs.
  # signal at t -> realised return at t+1 (lead by 1 within each series).
  ret_with_lead <- returns_tbl |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(next_ret = dplyr::lead(monthly_ret, n = 1L)) |>
    dplyr::ungroup() |>
    dplyr::filter(!is.na(next_ret)) |>
    dplyr::select(series_id, signal_date = date, next_ret)

  # Join signal (at t) to execution return (at t+1).
  combined <- signal_tbl |>
    dplyr::inner_join(ret_with_lead, by = c("date" = "signal_date", "series_id"))

  # Rank within each signal date; assign long/short weights.
  ranked <- combined |>
    dplyr::group_by(date) |>
    dplyr::mutate(
      rk = dplyr::row_number(dplyr::desc(mr_signal)),  # rank 1 = highest signal = biggest loser
      n_avail = dplyr::n()
    ) |>
    dplyr::filter(rk <= n_long | rk > (n_avail - n_short)) |>
    dplyr::mutate(
      leg    = dplyr::if_else(rk <= n_long, "long", "short"),
      n_leg  = dplyr::if_else(rk <= n_long, n_long, n_short),
      weight = dplyr::if_else(leg == "long", 1 / n_long, -1 / n_short)
    ) |>
    dplyr::ungroup()

  # Monthly gross returns and position counts.
  monthly <- ranked |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      gross_ret = sum(weight * next_ret, na.rm = TRUE),
      n_long_pos  = sum(leg == "long",  na.rm = TRUE),
      n_short_pos = sum(leg == "short", na.rm = TRUE),
      .groups = "drop"
    )

  # Turnover: sum of absolute weight changes relative to prior month.
  # Use series_id-level lag of weight within the ranked dataset.
  weight_tbl <- ranked |>
    dplyr::select(date, series_id, weight) |>
    dplyr::arrange(series_id, date) |>
    dplyr::group_by(series_id) |>
    dplyr::mutate(prev_weight = dplyr::lag(weight, default = 0)) |>
    dplyr::ungroup()

  turnover_tbl <- weight_tbl |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      turnover = sum(abs(weight - prev_weight), na.rm = TRUE) / 2,
      .groups = "drop"
    )

  monthly |>
    dplyr::left_join(turnover_tbl, by = "date") |>
    dplyr::mutate(
      turnover = dplyr::if_else(is.na(turnover), 0, turnover),
      cost     = turnover * cost_per_unit,
      net_ret  = gross_ret - cost,
      n_long   = n_long_pos,
      n_short  = n_short_pos
    ) |>
    dplyr::select(date, gross_ret, turnover, cost, net_ret, n_long, n_short)
}
