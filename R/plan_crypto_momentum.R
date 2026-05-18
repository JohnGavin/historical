# Crypto Momentum Decomposition Pipeline (Issue #135)
#
# Tests momentum decomposition in the SIMPLEST case: crypto with NO industries,
# NO style factors, just BTC beta. If decomposition fails here, equity failure
# (Issue #121) is not due to over-complication — the method itself is broken.
#
# Phase 1: Spot data only (2017-2026, liquid era post-ICO bubble)
# Phase 2 (if Sharpe > 0): Add perps + funding rates
#
# Success criterion: Net Sharpe > 0 for at least one decomposed variant.

plan_crypto_momentum <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────────
    targets::tar_target(crypto_mom_params, {
      list(
        lookback = 252L,          # 12 months momentum
        beta_window = 252L,       # 12 months beta estimation
        cost_bps = 30,            # 0.3% per trade (crypto spreads wider)
        n_long = 5,               # Top 5 coins
        n_short = 5,              # Bottom 5 coins
        sample_start = as.Date("2017-01-01"),  # Post-ICO bubble
        sample_end = as.Date("2026-12-31")     # Through present
      )
    }),


    # ── Universe: All crypto tickers from local parquet ──────────────────────
    targets::tar_target(crypto_universe, {
      library(dplyr)
      library(arrow)

      # Read crypto data from local parquet file
      crypto_data <- arrow::read_parquet(here::here("data/raw/crypto_all.parquet")) |>
        filter(
          date >= crypto_mom_params$sample_start,
          date <= crypto_mom_params$sample_end
        ) |>
        select(date, ticker, close, volume) |>
        arrange(ticker, date)

      # Filter to tickers with sufficient history (at least lookback + beta_window days)
      min_days <- crypto_mom_params$lookback + crypto_mom_params$beta_window
      ticker_counts <- crypto_data |>
        group_by(ticker) |>
        summarise(n_days = n(), .groups = "drop") |>
        filter(n_days >= min_days)

      cli::cli_inform(c(
        "i" = "Crypto universe: {nrow(ticker_counts)} tickers with >= {min_days} days"
      ))

      crypto_data |>
        filter(ticker %in% ticker_counts$ticker)
    }),


    # ── Returns: Daily log returns ────────────────────────────────────
    targets::tar_target(crypto_returns, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))
      calculate_crypto_returns(crypto_universe)
    }),


    # ── BTC Beta: Rolling 252-day regression ──────────────────────────
    targets::tar_target(crypto_btc_beta, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))

      # Extract BTC returns
      btc_returns <- crypto_returns |>
        filter(ticker == "BTC") |>
        select(date, ret)

      # Compute betas for all coins
      calculate_btc_beta(crypto_returns, btc_returns, lookback = crypto_mom_params$beta_window)
    }),


    # ── Signals: Three momentum variants ──────────────────────────────
    targets::tar_target(crypto_signals, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))

      build_crypto_signals(crypto_returns, crypto_btc_beta, lookback = crypto_mom_params$lookback)
    }),


    # ── Backtest: Baseline (total momentum) ───────────────────────────
    targets::tar_target(crypto_bt_baseline, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))

      signals_baseline <- crypto_signals |>
        select(date, ticker, signal = mom_total)

      backtest_crypto_momentum(
        signals_baseline,
        crypto_returns,
        cost_bps = crypto_mom_params$cost_bps,
        n_long = crypto_mom_params$n_long,
        n_short = crypto_mom_params$n_short
      )
    }),


    # ── Backtest: BTC-adjusted momentum ───────────────────────────────
    targets::tar_target(crypto_bt_btc_adj, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))

      signals_btc_adj <- crypto_signals |>
        select(date, ticker, signal = mom_btc_adj)

      backtest_crypto_momentum(
        signals_btc_adj,
        crypto_returns,
        cost_bps = crypto_mom_params$cost_bps,
        n_long = crypto_mom_params$n_long,
        n_short = crypto_mom_params$n_short
      )
    }),


    # ── Backtest: Residual-only momentum ──────────────────────────────
    targets::tar_target(crypto_bt_residual, {
      library(dplyr)
      source(here::here("R/crypto_momentum.R"))

      signals_residual <- crypto_signals |>
        select(date, ticker, signal = mom_residual)

      backtest_crypto_momentum(
        signals_residual,
        crypto_returns,
        cost_bps = crypto_mom_params$cost_bps,
        n_long = crypto_mom_params$n_long,
        n_short = crypto_mom_params$n_short
      )
    }),


    # ── Summary Table: Performance by strategy ────────────────────────
    targets::tar_target(crypto_performance_summary, {
      library(dplyr)

      tibble::tibble(
        strategy = c("Baseline (Total Mom)", "BTC-Adjusted", "Residual-Only"),
        gross_sharpe = c(
          crypto_bt_baseline$summary$gross_sharpe,
          crypto_bt_btc_adj$summary$gross_sharpe,
          crypto_bt_residual$summary$gross_sharpe
        ),
        net_sharpe = c(
          crypto_bt_baseline$summary$net_sharpe,
          crypto_bt_btc_adj$summary$net_sharpe,
          crypto_bt_residual$summary$net_sharpe
        ),
        gross_annual_ret = c(
          crypto_bt_baseline$summary$gross_annual_ret,
          crypto_bt_btc_adj$summary$gross_annual_ret,
          crypto_bt_residual$summary$gross_annual_ret
        ),
        net_annual_ret = c(
          crypto_bt_baseline$summary$net_annual_ret,
          crypto_bt_btc_adj$summary$net_annual_ret,
          crypto_bt_residual$summary$net_annual_ret
        ),
        max_drawdown = c(
          crypto_bt_baseline$summary$max_drawdown,
          crypto_bt_btc_adj$summary$max_drawdown,
          crypto_bt_residual$summary$max_drawdown
        ),
        avg_turnover = c(
          crypto_bt_baseline$summary$avg_turnover,
          crypto_bt_btc_adj$summary$avg_turnover,
          crypto_bt_residual$summary$avg_turnover
        )
      ) |>
        mutate(across(where(is.numeric), ~ round(.x, 3)))
    }),


    # ── Plot: Cumulative Returns ──────────────────────────────────────
    targets::tar_target(crypto_cumulative_plot, {
      library(dplyr)
      library(ggplot2)
      library(scales)

      # Combine all three backtests
      combined <- bind_rows(
        crypto_bt_baseline$performance |>
          mutate(strategy = "Baseline (Total Mom)"),
        crypto_bt_btc_adj$performance |>
          mutate(strategy = "BTC-Adjusted"),
        crypto_bt_residual$performance |>
          mutate(strategy = "Residual-Only")
      ) |>
        select(date, strategy, cum_ret_net)


      ggplot(combined, aes(date, cum_ret_net, color = strategy)) +
        geom_line(linewidth = 0.7) +
        geom_hline(yintercept = 1, color = "grey50", linetype = "dashed") +
        scale_y_continuous(labels = scales::comma) +
        scale_color_manual(values = hd_palette(3)) +
        labs(
          x = NULL,
          y = "Cumulative return (net of costs)",
          color = NULL,
          title = "Crypto Momentum Decomposition: Cumulative Returns",
          subtitle = paste0(
            "Long top 5, short bottom 5 by 12m momentum | ",
            "30bps costs | 2017-2026"
          )
        ) +
        hd_theme() +
        theme(legend.position = "bottom")
    }),


    # ── Plot: Rolling Sharpe (36-month windows) ───────────────────────
    targets::tar_target(crypto_rolling_sharpe_plot, {
      library(dplyr)
      library(ggplot2)
      library(scales)

      # Function to compute rolling Sharpe
      rolling_sharpe <- function(df, window_days = 756) {  # 36 months ≈ 756 trading days
        df |>
          arrange(date) |>
          mutate(
            roll_mean = RcppRoll::roll_mean(net_ret, n = window_days, fill = NA, align = "right"),
            roll_sd = RcppRoll::roll_sd(net_ret, n = window_days, fill = NA, align = "right"),
            roll_sharpe = roll_mean / roll_sd * sqrt(252)
          ) |>
          filter(!is.na(roll_sharpe))
      }

      # Compute for all three strategies
      combined <- bind_rows(
        rolling_sharpe(crypto_bt_baseline$performance) |>
          mutate(strategy = "Baseline (Total Mom)"),
        rolling_sharpe(crypto_bt_btc_adj$performance) |>
          mutate(strategy = "BTC-Adjusted"),
        rolling_sharpe(crypto_bt_residual$performance) |>
          mutate(strategy = "Residual-Only")
      ) |>
        select(date, strategy, roll_sharpe)


      ggplot(combined, aes(date, roll_sharpe, color = strategy)) +
        geom_line(linewidth = 0.7) +
        geom_hline(yintercept = 0, color = "grey50", linetype = "dashed") +
        scale_color_manual(values = hd_palette(3)) +
        labs(
          x = NULL,
          y = "Rolling Sharpe ratio (36-month windows)",
          color = NULL,
          title = "Crypto Momentum Decomposition: Rolling Sharpe Ratios",
          subtitle = "Positive Sharpe indicates strategy adds value over random"
        ) +
        hd_theme() +
        theme(legend.position = "bottom")
    }),


    # ── Key Finding: Rescue Test ──────────────────────────────────────
    targets::tar_target(crypto_rescue_test, {
      library(dplyr)

      # Check if ANY decomposed variant has positive net Sharpe
      any_positive <- any(c(
        crypto_bt_btc_adj$summary$net_sharpe > 0,
        crypto_bt_residual$summary$net_sharpe > 0
      ))

      best_sharpe <- max(c(
        crypto_bt_baseline$summary$net_sharpe,
        crypto_bt_btc_adj$summary$net_sharpe,
        crypto_bt_residual$summary$net_sharpe
      ), na.rm = TRUE)

      best_strategy <- c("Baseline (Total Mom)", "BTC-Adjusted", "Residual-Only")[
        which.max(c(
          crypto_bt_baseline$summary$net_sharpe,
          crypto_bt_btc_adj$summary$net_sharpe,
          crypto_bt_residual$summary$net_sharpe
        ))
      ]

      list(
        rescue_success = any_positive,
        best_strategy = best_strategy,
        best_sharpe = best_sharpe,
        interpretation = if (any_positive) {
          "SUCCESS: At least one decomposed variant has positive Sharpe. Recommend Phase 2 (perps + funding rates)."
        } else if (best_sharpe > 0) {
          "PARTIAL: Baseline positive but decomposed variants fail. Decomposition does not help in crypto."
        } else {
          "FAILURE: All variants have negative Sharpe. If commodities also fail (Issue #134), GLOBAL ABANDON justified."
        }
      )
    })

  )
}
