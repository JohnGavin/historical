# Crypto Momentum Decomposition Functions
#
# Issue #135: Test momentum decomposition in the SIMPLEST case — crypto with NO
# industries, NO style factors, just BTC beta. If decomposition fails here, the
# equity failure (Issue #121) is not due to over-complication.
#
# Hypothesis: Total momentum underperforms because it mixes systematic (BTC beta)
# and idiosyncratic (coin-specific) components. Separating them may rescue the
# strategy.
#
# Three Signal Variants:
#   1. Baseline: Total 12m return (long top 5, short bottom 5)
#   2. BTC-adjusted: Momentum AFTER removing BTC beta component
#   3. Residual-only: Pure idiosyncratic momentum
#
# Success criterion: Net Sharpe > 0 for at least one decomposed variant.

#' Calculate Crypto Returns
#'
#' Compute log returns from adjusted close prices.
#'
#' @param crypto_data Tibble with columns: date, ticker, adjusted
#' @return Tibble with columns: date, ticker, ret (daily log return)
#'
#' @examples
#' \dontrun{
#' returns <- calculate_crypto_returns(crypto_data)
#' }
calculate_crypto_returns <- function(crypto_data) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required")
  }

  crypto_data |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      ret = log(adjusted / dplyr::lag(adjusted))
    ) |>
    dplyr::filter(!is.na(ret)) |>
    dplyr::ungroup()
}


#' Calculate BTC Beta
#'
#' Regress each coin's returns on BTC returns to estimate beta (systematic risk).
#' Uses rolling 252-day windows.
#'
#' @param returns Tibble with columns: date, ticker, ret
#' @param btc_returns Tibble with columns: date, ret (BTC returns)
#' @param lookback Integer. Rolling window size (default 252 = 1 year)
#' @return Tibble with columns: date, ticker, btc_beta
#'
#' @examples
#' \dontrun{
#' btc_rets <- returns |> filter(ticker == "BTC-USD") |> select(date, ret)
#' betas <- calculate_btc_beta(returns, btc_rets, lookback = 252)
#' }
calculate_btc_beta <- function(returns, btc_returns, lookback = 252) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required")
  }
  if (!requireNamespace("RcppRoll", quietly = TRUE)) {
    stop("Package 'RcppRoll' is required")
  }

  # Rename BTC returns for clarity
  btc_rets <- btc_returns |>
    dplyr::select(date, btc_ret = ret)

  # Join and compute rolling betas
  returns |>
    dplyr::left_join(btc_rets, by = "date") |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      # Rolling covariance / rolling variance
      cov_btc = RcppRoll::roll_cov(ret, btc_ret, n = lookback, fill = NA, align = "right"),
      var_btc = RcppRoll::roll_var(btc_ret, n = lookback, fill = NA, align = "right"),
      btc_beta = cov_btc / var_btc
    ) |>
    dplyr::select(date, ticker, btc_beta) |>
    dplyr::filter(!is.na(btc_beta)) |>
    dplyr::ungroup()
}


#' Build Crypto Signals
#'
#' Construct three momentum signal variants: baseline (total return), BTC-adjusted
#' (residual momentum), and residual-only.
#'
#' @param returns Tibble with columns: date, ticker, ret
#' @param btc_betas Tibble with columns: date, ticker, btc_beta
#' @param lookback Integer. Momentum lookback window (default 252 = 12 months)
#' @return Tibble with columns: date, ticker, mom_total, mom_btc_adj, mom_residual
#'
#' @details
#' - mom_total: Raw 12m cumulative return
#' - mom_btc_adj: 12m return minus (beta * BTC_12m_return)
#' - mom_residual: Same as mom_btc_adj but used for pure residual-only strategy
#'
#' @examples
#' \dontrun{
#' signals <- build_crypto_signals(returns, btc_betas, lookback = 252)
#' }
build_crypto_signals <- function(returns, btc_betas, lookback = 252) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required")
  }
  if (!requireNamespace("RcppRoll", quietly = TRUE)) {
    stop("Package 'RcppRoll' is required")
  }

  # Compute total momentum (raw cumulative return)
  mom_total <- returns |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      mom_total = RcppRoll::roll_sum(ret, n = lookback, fill = NA, align = "right")
    ) |>
    dplyr::select(date, ticker, mom_total) |>
    dplyr::filter(!is.na(mom_total)) |>
    dplyr::ungroup()

  # Compute BTC momentum
  btc_mom <- returns |>
    dplyr::filter(ticker == "BTC-USD") |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      btc_mom = RcppRoll::roll_sum(ret, n = lookback, fill = NA, align = "right")
    ) |>
    dplyr::select(date, btc_mom) |>
    dplyr::filter(!is.na(btc_mom)) |>
    dplyr::ungroup()

  # Join everything and compute adjusted signals
  mom_total |>
    dplyr::left_join(btc_betas, by = c("date", "ticker")) |>
    dplyr::left_join(btc_mom, by = "date") |>
    dplyr::mutate(
      # BTC-adjusted momentum: total - (beta * BTC momentum)
      mom_btc_adj = mom_total - (btc_beta * btc_mom),
      # Residual-only: same calculation
      mom_residual = mom_btc_adj
    ) |>
    dplyr::select(date, ticker, mom_total, mom_btc_adj, mom_residual) |>
    dplyr::filter(!is.na(mom_btc_adj))
}


#' Backtest Crypto Momentum
#'
#' Long-short portfolio: long top 5, short bottom 5 by signal. Monthly rebalancing.
#' Transaction costs of 30bps per trade (crypto spreads wider than equities).
#'
#' @param signals Tibble with columns: date, ticker, signal (one of mom_total,
#'   mom_btc_adj, mom_residual)
#' @param returns Tibble with columns: date, ticker, ret (daily returns)
#' @param cost_bps Numeric. Transaction cost in basis points (default 30 = 0.3%)
#' @param n_long Integer. Number of coins to long (default 5)
#' @param n_short Integer. Number of coins to short (default 5)
#' @return List with elements: performance (tibble), cumulative (tibble), summary (list)
#'
#' @details
#' Performance metrics computed:
#' - Sharpe ratio (annualized)
#' - Annual return
#' - Max drawdown
#' - Turnover (fraction rebalanced per month)
#'
#' @examples
#' \dontrun{
#' baseline <- backtest_crypto_momentum(signals |> select(date, ticker, signal = mom_total),
#'                                       returns, cost_bps = 30)
#' }
backtest_crypto_momentum <- function(signals, returns, cost_bps = 30,
                                     n_long = 5, n_short = 5) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required")
  }
  if (!requireNamespace("tidyr", quietly = TRUE)) {
    stop("Package 'tidyr' is required")
  }

  # Ensure signal column exists
  if (!"signal" %in% names(signals)) {
    stop("signals must have a 'signal' column")
  }

  # Monthly rebalancing dates (use month-end)
  rebalance_dates <- signals |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::group_by(ym) |>
    dplyr::filter(date == max(date)) |>
    dplyr::ungroup() |>
    dplyr::pull(date) |>
    unique() |>
    sort()

  # For each rebalance date, rank by signal and assign positions
  positions <- lapply(rebalance_dates, function(reb_date) {
    signals |>
      dplyr::filter(date == reb_date) |>
      dplyr::arrange(dplyr::desc(signal)) |>
      dplyr::mutate(
        rank = dplyr::row_number(),
        position = dplyr::case_when(
          rank <= n_long ~ 1 / n_long,           # Long top N
          rank > dplyr::n() - n_short ~ -1 / n_short,  # Short bottom N
          TRUE ~ 0
        ),
        rebalance_date = reb_date
      ) |>
      dplyr::select(ticker, rebalance_date, position, rank)
  }) |>
    dplyr::bind_rows()

  # Expand positions to daily (forward-fill until next rebalance)
  daily_positions <- returns |>
    dplyr::select(date, ticker) |>
    dplyr::left_join(positions, by = "ticker") |>
    dplyr::filter(rebalance_date <= date) |>
    dplyr::group_by(ticker, date) |>
    dplyr::filter(rebalance_date == max(rebalance_date)) |>
    dplyr::ungroup()

  # Calculate daily portfolio returns
  portfolio_rets <- daily_positions |>
    dplyr::left_join(returns, by = c("date", "ticker")) |>
    dplyr::group_by(date) |>
    dplyr::summarise(
      port_ret = sum(position * ret, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(date)

  # Calculate turnover (fraction of portfolio changed at each rebalance)
  turnover_calc <- positions |>
    dplyr::arrange(ticker, rebalance_date) |>
    dplyr::group_by(ticker) |>
    dplyr::mutate(
      prev_position = dplyr::lag(position, default = 0),
      turnover_contrib = abs(position - prev_position)
    ) |>
    dplyr::ungroup() |>
    dplyr::group_by(rebalance_date) |>
    dplyr::summarise(
      turnover = sum(turnover_contrib) / 2,  # Divide by 2 (long+short both counted)
      .groups = "drop"
    )

  avg_turnover <- mean(turnover_calc$turnover, na.rm = TRUE)

  # Apply transaction costs at each rebalance
  portfolio_rets <- portfolio_rets |>
    dplyr::left_join(
      turnover_calc |> dplyr::select(date = rebalance_date, turnover),
      by = "date"
    ) |>
    dplyr::mutate(
      cost = dplyr::if_else(is.na(turnover), 0, turnover * cost_bps / 10000),
      net_ret = port_ret - cost
    )

  # Compute cumulative returns
  portfolio_rets <- portfolio_rets |>
    dplyr::mutate(
      cum_ret_gross = cumprod(1 + port_ret),
      cum_ret_net = cumprod(1 + net_ret)
    )

  # Compute drawdown
  portfolio_rets <- portfolio_rets |>
    dplyr::mutate(
      running_max = cummax(cum_ret_net),
      drawdown = (cum_ret_net / running_max) - 1
    )

  # Summary statistics
  n_days <- nrow(portfolio_rets)
  n_years <- n_days / 252

  gross_sharpe <- if (n_days > 1) {
    mean(portfolio_rets$port_ret, na.rm = TRUE) /
      sd(portfolio_rets$port_ret, na.rm = TRUE) * sqrt(252)
  } else { NA_real_ }

  net_sharpe <- if (n_days > 1) {
    mean(portfolio_rets$net_ret, na.rm = TRUE) /
      sd(portfolio_rets$net_ret, na.rm = TRUE) * sqrt(252)
  } else { NA_real_ }

  gross_annual_ret <- if (n_years > 0) {
    (tail(portfolio_rets$cum_ret_gross, 1) ^ (1 / n_years)) - 1
  } else { NA_real_ }

  net_annual_ret <- if (n_years > 0) {
    (tail(portfolio_rets$cum_ret_net, 1) ^ (1 / n_years)) - 1
  } else { NA_real_ }

  max_dd <- min(portfolio_rets$drawdown, na.rm = TRUE)

  list(
    performance = portfolio_rets,
    summary = list(
      gross_sharpe = gross_sharpe,
      net_sharpe = net_sharpe,
      gross_annual_ret = gross_annual_ret,
      net_annual_ret = net_annual_ret,
      max_drawdown = max_dd,
      avg_turnover = avg_turnover,
      n_days = n_days,
      n_years = n_years
    )
  )
}
