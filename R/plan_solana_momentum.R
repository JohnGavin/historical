# Solana-Only Momentum Decomposition Targets Plan
#
# Tests momentum decomposition on Solana ecosystem tokens only
# Uses DeFi data sources (Birdeye spot + Drift perps)
#
# Parameters:
# - beta_window: 252 (configurable)
# - leverage: 1.0 (configurable)
# - vol_adjust: TRUE
# - rebalance_freq: "weekly"

plan_solana_momentum <- function() {
  list(
    # 1. Define Solana token universe (liquid tokens only)
    tar_target(
      solana_universe_raw,
      {
        # Candidate tokens
        candidates <- c("SOL", "RAY", "BONK", "JUP", "PYTH", "ORCA", "JTO", "HNT")

        # NOTE: Will filter by liquidity metrics after fetching data
        candidates
      }
    ),

    # 2. Fetch spot prices from Birdeye (4-hourly for signal, daily for backtest)
    tar_target(
      solana_spot_4h,
      {
        # API key from environment
        if (Sys.getenv("BIRDEYE_API_KEY") == "") {
          cli::cli_abort("BIRDEYE_API_KEY not set. Get free key at https://birdeye.so/")
        }

        fetch_birdeye_spot(
          tokens = solana_universe_raw,
          start_date = as.Date("2021-01-01"),  # Earliest common start for most tokens
          end_date = Sys.Date(),
          interval = "4H"  # 4-hourly for higher frequency signals
        )
      }
    ),

    # 3. Fetch Drift perp prices + funding rates
    tar_target(
      solana_perps_drift,
      {
        # Map tokens to Drift perp markets
        perp_markets <- paste0(solana_universe_raw, "-PERP")

        fetch_drift_perps(
          markets = perp_markets,
          start_date = as.Date("2022-03-01"),  # Drift v2 launch
          end_date = Sys.Date()
        )
      }
    ),

    # 4. Calculate liquidity metrics (filter to liquid tokens only)
    tar_target(
      solana_liquidity_metrics,
      {
        calculate_liquidity_metrics(
          spot_data = solana_spot_4h,
          perp_data = solana_perps_drift,
          min_daily_volume = 1e6  # $1M minimum daily volume
        )
      }
    ),

    # 5. Filter to liquid universe
    tar_target(
      solana_universe_liquid,
      {
        liquid_tokens <- solana_liquidity_metrics |>
          dplyr::filter(is_liquid) |>
          dplyr::pull(ticker)

        if (length(liquid_tokens) < 5) {
          cli::cli_warn("Only {length(liquid_tokens)} liquid tokens found. Minimum recommended: 5")
        }

        cli::cli_alert_success("Liquid Solana universe: {paste(liquid_tokens, collapse=', ')}")

        liquid_tokens
      }
    ),

    # 6. Resample to daily for backtesting (from 4H data)
    tar_target(
      solana_spot_daily,
      {
        solana_spot_4h |>
          dplyr::filter(ticker %in% solana_universe_liquid) |>
          dplyr::mutate(date = as.Date(timestamp)) |>
          dplyr::group_by(ticker, date) |>
          dplyr::summarise(
            open = dplyr::first(open),
            high = max(high),
            low = min(low),
            close = dplyr::last(close),
            volume = sum(volume),
            .groups = "drop"
          )
      }
    ),

    # 7. Calculate daily returns
    tar_target(
      solana_returns_daily,
      {
        solana_spot_daily |>
          dplyr::group_by(ticker) |>
          dplyr::arrange(date) |>
          dplyr::mutate(
            return = log(close / dplyr::lag(close))
          ) |>
          dplyr::filter(!is.na(return)) |>
          dplyr::ungroup() |>
          dplyr::select(ticker, date, return, close)
      }
    ),

    # 8. BTC returns (reference for beta calculation)
    tar_target(
      btc_returns_daily,
      {
        solana_returns_daily |>
          dplyr::filter(ticker == "BTC") |>
          dplyr::select(date, btc_return = return)
      }
    ),

    # 9. Build momentum signals (configurable parameters)
    tar_target(
      solana_signals,
      {
        # Configurable parameters
        LOOKBACK_DAYS <- 252    # 12-month momentum
        BETA_WINDOW <- 252      # 12-month beta estimation
        VOL_ADJUST <- TRUE      # Use volatility-adjusted sizing
        LEVERAGE <- 1.0         # Unleveraged

        build_momentum_signals(
          returns = solana_returns_daily |> dplyr::filter(ticker != "BTC"),
          btc_returns = btc_returns_daily,
          lookback_days = LOOKBACK_DAYS,
          beta_window = BETA_WINDOW,
          vol_adjust = VOL_ADJUST,
          leverage = LEVERAGE
        )
      }
    ),

    # 10. Backtest: Baseline momentum
    tar_target(
      solana_bt_baseline,
      {
        backtest_momentum(
          signals = solana_signals |> dplyr::select(ticker, date, signal = baseline_mom, position_size),
          returns = solana_returns_daily,
          costs = 0.003,  # 0.3% per trade (DeFi slippage)
          rebalance_freq = "weekly"
        )
      }
    ),

    # 11. Backtest: BTC-adjusted momentum
    tar_target(
      solana_bt_btc_adj,
      {
        backtest_momentum(
          signals = solana_signals |> dplyr::select(ticker, date, signal = btc_adj_mom, position_size),
          returns = solana_returns_daily,
          costs = 0.003,
          rebalance_freq = "weekly"
        )
      }
    ),

    # 12. Backtest: Residual-only momentum
    tar_target(
      solana_bt_residual,
      {
        backtest_momentum(
          signals = solana_signals |> dplyr::select(ticker, date, signal = residual_mom, position_size),
          returns = solana_returns_daily,
          costs = 0.003,
          rebalance_freq = "weekly"
        )
      }
    ),

    # 13. Performance summary
    tar_target(
      solana_performance_summary,
      {
        bind_rows(
          solana_bt_baseline |> mutate(strategy = "Baseline (12m)"),
          solana_bt_btc_adj |> mutate(strategy = "BTC-Adjusted"),
          solana_bt_residual |> mutate(strategy = "Residual-Only")
        ) |>
          group_by(strategy) |>
          summarise(
            gross_sharpe = calculate_sharpe(gross_pnl),
            net_sharpe = calculate_sharpe(net_pnl),
            gross_annual_ret = mean(gross_pnl) * 252,
            net_annual_ret = mean(net_pnl) * 252,
            max_drawdown = calculate_max_dd(cumsum(net_pnl)),
            avg_turnover = mean(turnover),
            .groups = "drop"
          )
      }
    ),

    # 14. BTC beta analysis (how much does SOL ecosystem move with BTC?)
    tar_target(
      solana_btc_beta_analysis,
      {
        solana_signals |>
          group_by(ticker) |>
          summarise(
            mean_beta = mean(btc_beta, na.rm = TRUE),
            median_beta = median(btc_beta, na.rm = TRUE),
            sd_beta = sd(btc_beta, na.rm = TRUE),
            beta_25 = quantile(btc_beta, 0.25, na.rm = TRUE),
            beta_75 = quantile(btc_beta, 0.75, na.rm = TRUE),
            .groups = "drop"
          ) |>
          arrange(desc(median_beta))
      }
    ),

    # 15. Funding rate carry analysis (for Phase 2)
    tar_target(
      solana_funding_rate_stats,
      {
        solana_perps_drift |>
          mutate(ticker = sub("-PERP", "", market)) |>
          filter(ticker %in% solana_universe_liquid) |>
          group_by(ticker) |>
          summarise(
            mean_funding_rate = mean(funding_rate, na.rm = TRUE) * 24 * 365,  # Annualized
            sd_funding_rate = sd(funding_rate, na.rm = TRUE) * sqrt(24 * 365),
            positive_pct = mean(funding_rate > 0, na.rm = TRUE),
            .groups = "drop"
          ) |>
          arrange(desc(mean_funding_rate))
      }
    ),

    # 16. Cumulative returns plot
    tar_target(
      solana_cumulative_plot,
      {
        combined <- bind_rows(
          solana_bt_baseline |> mutate(strategy = "Baseline"),
          solana_bt_btc_adj |> mutate(strategy = "BTC-Adjusted"),
          solana_bt_residual |> mutate(strategy = "Residual-Only")
        )

        ggplot(combined, aes(x = date, y = cumsum(net_pnl), color = strategy)) +
          geom_line(linewidth = 1) +
          scale_color_manual(values = c("Baseline" = "#999", "BTC-Adjusted" = "#0066CC", "Residual-Only" = "#CC0000")) +
          labs(
            title = "Solana Momentum Decomposition: Cumulative Returns",
            subtitle = paste0(
              "Universe: ", paste(solana_universe_liquid, collapse = ", "),
              " | Weekly rebalance | 0.3% costs"
            ),
            x = NULL,
            y = "Cumulative Return",
            color = "Strategy"
          ) +
          theme_minimal() +
          theme(legend.position = "top")
      }
    ),

    # 17. Rolling Sharpe plot
    tar_target(
      solana_rolling_sharpe_plot,
      {
        combined <- bind_rows(
          solana_bt_baseline |> mutate(strategy = "Baseline"),
          solana_bt_btc_adj |> mutate(strategy = "BTC-Adjusted"),
          solana_bt_residual |> mutate(strategy = "Residual-Only")
        )

        combined |>
          group_by(strategy) |>
          arrange(date) |>
          mutate(
            rolling_sharpe = RcppRoll::roll_meanr(net_pnl, n = 63) /
                            RcppRoll::roll_sdr(net_pnl, n = 63) * sqrt(252)
          ) |>
          ungroup() |>
          filter(!is.na(rolling_sharpe)) |>
          ggplot(aes(x = date, y = rolling_sharpe, color = strategy)) +
          geom_line(linewidth = 0.8) +
          geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
          scale_color_manual(values = c("Baseline" = "#999", "BTC-Adjusted" = "#0066CC", "Residual-Only" = "#CC0000")) +
          labs(
            title = "Solana Momentum: 63-Day Rolling Sharpe Ratio",
            x = NULL,
            y = "Rolling Sharpe (63d)",
            color = "Strategy"
          ) +
          theme_minimal() +
          theme(legend.position = "top")
      }
    ),

    # 18. Performance table (display)
    tar_target(
      solana_performance_table,
      {
        solana_performance_summary |>
          mutate(
            gross_sharpe = round(gross_sharpe, 3),
            net_sharpe = round(net_sharpe, 3),
            gross_annual_ret = scales::percent(gross_annual_ret, accuracy = 0.1),
            net_annual_ret = scales::percent(net_annual_ret, accuracy = 0.1),
            max_drawdown = scales::percent(max_drawdown, accuracy = 0.1),
            avg_turnover = scales::percent(avg_turnover, accuracy = 0.1)
          )
      }
    )
  )
}
