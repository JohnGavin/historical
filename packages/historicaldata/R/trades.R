# Trade extraction and metrics
#
# hd_monthly_trades() — for fixed-frequency strategies (DRIF, Factor MAX, LTR)
# hd_event_trades()   — for event-driven strategies (Avoid Worst, RSC)
# hd_trade_metrics()  — 17 trade-level metrics from a trades tibble

#' Extract trades from monthly return series
#'
#' Each month = one trade. Entry at month start, exit at month end.
#'
#' @param monthly_ret Tibble with date and strategy_ret columns (monthly frequency).
#' @return Tibble with: trade_id, entry_date, exit_date, duration_days, return, is_win
#' @family trades
#' @export
hd_monthly_trades <- function(monthly_ret) {
  monthly_ret <- monthly_ret[!is.na(monthly_ret$strategy_ret), ]
  if (nrow(monthly_ret) == 0L) return(dplyr::tibble())

  dates <- as.Date(monthly_ret$date)
  rets <- monthly_ret$strategy_ret

  tibble::tibble(
    trade_id = seq_along(rets),
    entry_date = dates,
    exit_date = dplyr::lead(dates, default = dates[length(dates)] + 30L),
    duration_days = as.integer(difftime(
      dplyr::lead(dates, default = dates[length(dates)] + 30L), dates, units = "days"
    )),
    return = rets,
    is_win = rets > 0
  )
}

#' Extract trades from event-driven strategy (in_market flag)
#'
#' A trade = contiguous period where in_market is TRUE or FALSE.
#' Returns one row per market-entry event (in_market = TRUE block).
#'
#' @param daily_ret Tibble with date, strategy_ret, in_market columns.
#' @return Tibble with: trade_id, entry_date, exit_date, duration_days, return, is_win
#' @family trades
#' @export
hd_event_trades <- function(daily_ret) {
  daily_ret <- daily_ret[!is.na(daily_ret$strategy_ret), ]
  if (nrow(daily_ret) == 0L || !"in_market" %in% names(daily_ret)) {
    return(dplyr::tibble())
  }

  dates <- as.Date(daily_ret$date)
  rets <- daily_ret$strategy_ret
  in_mkt <- daily_ret$in_market

  # Run-length encoding to find contiguous blocks
  rle_res <- rle(in_mkt)
  n_runs <- length(rle_res$lengths)

  trades <- list()
  trade_id <- 0L
  idx <- 1L

  for (i in seq_len(n_runs)) {
    run_len <- rle_res$lengths[i]
    run_val <- rle_res$values[i]
    run_idx <- idx:(idx + run_len - 1L)

    if (isTRUE(run_val)) {
      trade_id <- trade_id + 1L
      run_rets <- rets[run_idx]
      cum_ret <- prod(1 + run_rets) - 1

      trades[[trade_id]] <- tibble::tibble(
        trade_id = trade_id,
        entry_date = dates[run_idx[1]],
        exit_date = dates[run_idx[length(run_idx)]],
        duration_days = as.integer(difftime(
          dates[run_idx[length(run_idx)]], dates[run_idx[1]], units = "days"
        )) + 1L,
        return = cum_ret,
        is_win = cum_ret > 0
      )
    }
    idx <- idx + run_len
  }

  dplyr::bind_rows(trades)
}

#' Compute 17 trade-level metrics from a trades tibble
#'
#' @param trades Tibble from [hd_monthly_trades()] or [hd_event_trades()].
#' @param ann_factor Annualisation factor: 12 (monthly) or 252 (daily).
#' @param n_years Number of years in the backtest (for per-year metrics).
#' @return Named list of 17 metrics matching the results database schema.
#' @family trades
#' @export
hd_trade_metrics <- function(trades, ann_factor = 12L, n_years = NA_real_) {
  if (nrow(trades) == 0L) {
    return(list(
      n_trades = NA_integer_, n_trades_per_year = NA_real_,
      n_wins = NA_integer_, n_losses = NA_integer_,
      win_rate = NA_real_, avg_return_per_trade = NA_real_,
      best_trade = NA_real_, worst_trade = NA_real_,
      max_trade_duration_days = NA_integer_,
      avg_trade_duration_days = NA_integer_,
      profit_factor = NA_real_, win_loss_ratio = NA_real_,
      payoff_ratio = NA_real_, cpc_index = NA_real_,
      expectancy = NA_real_,
      max_consecutive_wins = NA_integer_,
      max_consecutive_losses = NA_integer_
    ))
  }

  n <- nrow(trades)
  wins <- trades$return[trades$is_win]
  losses <- trades$return[!trades$is_win]
  n_wins <- length(wins)
  n_losses <- length(losses)

  win_rate <- n_wins / n
  avg_win <- if (n_wins > 0) mean(wins) else 0
  avg_loss <- if (n_losses > 0) mean(losses) else 0

  # Profit factor: gross profit / gross loss
  gross_profit <- if (n_wins > 0) sum(wins) else 0
  gross_loss <- if (n_losses > 0) abs(sum(losses)) else 0
  profit_factor <- if (gross_loss > 0) gross_profit / gross_loss else NA_real_

  # Win/loss ratio
  win_loss_ratio <- if (n_losses > 0) n_wins / n_losses else NA_real_


  # Payoff ratio: avg win / avg loss
  payoff_ratio <- if (n_losses > 0 && abs(avg_loss) > 0) {
    avg_win / abs(avg_loss)
  } else NA_real_

  # CPC index: profit factor * win_rate * payoff_ratio
  cpc_index <- if (!is.na(profit_factor) && !is.na(payoff_ratio)) {
    profit_factor * win_rate * payoff_ratio
  } else NA_real_

  # Expectancy: win_rate * avg_win + (1 - win_rate) * avg_loss
  expectancy <- win_rate * avg_win + (1 - win_rate) * avg_loss

  # Consecutive wins/losses
  rle_wins <- rle(trades$is_win)
  max_cons_wins <- if (any(rle_wins$values)) {
    max(rle_wins$lengths[rle_wins$values])
  } else 0L
  max_cons_losses <- if (any(!rle_wins$values)) {
    max(rle_wins$lengths[!rle_wins$values])
  } else 0L

  list(
    n_trades = as.integer(n),
    n_trades_per_year = if (!is.na(n_years) && n_years > 0) n / n_years else NA_real_,
    n_wins = as.integer(n_wins),
    n_losses = as.integer(n_losses),
    win_rate = win_rate,
    avg_return_per_trade = mean(trades$return),
    best_trade = max(trades$return),
    worst_trade = min(trades$return),
    max_trade_duration_days = as.integer(max(trades$duration_days)),
    avg_trade_duration_days = as.integer(round(mean(trades$duration_days))),
    profit_factor = profit_factor,
    win_loss_ratio = win_loss_ratio,
    payoff_ratio = payoff_ratio,
    cpc_index = cpc_index,
    expectancy = expectancy,
    max_consecutive_wins = as.integer(max_cons_wins),
    max_consecutive_losses = as.integer(max_cons_losses)
  )
}
