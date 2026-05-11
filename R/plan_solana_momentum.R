# Solana-Only Momentum Decomposition Targets Plan
#
# Proof-of-concept using available crypto_all.parquet data.
# Universe: SOL, RAY, BONK, HNT (+ BTC as reference).
# Three signal variants x two rebalance frequencies = 6 backtest targets.
#
# Reuses helpers from R/crypto_momentum_helpers.R:
#   calculate_crypto_returns(), calculate_btc_beta(),
#   build_crypto_signals(), backtest_crypto_momentum(),
#   backtest_weekly_momentum()
#
# Does NOT use Birdeye / Drift API — uses existing parquet only.

plan_solana_momentum <- function() {

  # --------------------------------------------------------------------------
  # Parameters
  # --------------------------------------------------------------------------
  SOLANA_UNIVERSE  <- c("SOL", "RAY", "BONK", "HNT")
  BETA_WINDOW      <- 252L   # rolling window for BTC beta (configurable)
  LOOKBACK_DAYS    <- 252L   # momentum lookback (configurable)
  LEVERAGE         <- 1.0    # unleveraged (configurable)
  COST_BPS         <- 30L    # 0.3% per trade
  N_LONG           <- 2L     # longs in 4-token universe
  N_SHORT          <- 2L     # shorts in 4-token universe
  PARQUET_PATH     <- "/Users/johngavin/docs_gh/proj/finance/data/historical-crypto/data/raw/crypto_all.parquet"
  VOL_WINDOW       <- 63L    # 63-day vol for position sizing

  list(

    # 1. Load raw parquet (Solana universe + BTC reference)
    tar_target(
      sol_raw_data,
      {
        arrow::read_parquet(PARQUET_PATH) |>
          dplyr::filter(ticker %in% c(SOLANA_UNIVERSE, "BTC")) |>
          dplyr::select(date, ticker, close) |>
          dplyr::arrange(ticker, date)
      }
    ),

    # 2. Compute log returns
    tar_target(
      sol_returns,
      calculate_crypto_returns(sol_raw_data)
    ),

    # 3. Separate BTC reference returns (used for beta estimation)
    tar_target(
      sol_btc_returns,
      sol_returns |>
        dplyr::filter(ticker == "BTC") |>
        dplyr::select(date, ret)
    ),

    # 4. Compute rolling BTC beta per Solana token
    tar_target(
      sol_btc_betas,
      {
        sol_rets_universe <- sol_returns |>
          dplyr::filter(ticker %in% SOLANA_UNIVERSE)
        calculate_btc_beta(sol_rets_universe, sol_btc_returns, lookback = BETA_WINDOW)
      }
    ),

    # 5. Build the three signal variants
    #    Inputs include BTC returns (for btc_mom) so filter to full dataset
    tar_target(
      sol_signals_raw,
      {
        # build_crypto_signals expects BTC in returns for btc_mom calc
        build_crypto_signals(sol_returns, sol_btc_betas, lookback = LOOKBACK_DAYS)
      }
    ),

    # 6. Volatility-adjusted position sizing
    #    weight = (1/vol_63d) / sum(1/vol_63d) per long/short leg
    #    Fall back to equal-weight if vol is NA
    tar_target(
      sol_vol_weights,
      {
        sol_universe_rets <- sol_returns |>
          dplyr::filter(ticker %in% SOLANA_UNIVERSE)

        vol_63d <- sol_universe_rets |>
          dplyr::group_by(ticker) |>
          dplyr::arrange(date) |>
          dplyr::mutate(
            vol_63d = RcppRoll::roll_sd(ret, n = VOL_WINDOW, fill = NA, align = "right")
          ) |>
          dplyr::select(date, ticker, vol_63d) |>
          dplyr::filter(!is.na(vol_63d)) |>
          dplyr::ungroup()

        vol_63d
      }
    ),

    # 7. Apply vol-adjusted weights to signals
    #    For each signal × date: compute inv-vol weight normalised within leg
    tar_target(
      sol_signals,
      {
        sol_signals_raw |>
          dplyr::filter(ticker %in% SOLANA_UNIVERSE) |>
          dplyr::left_join(sol_vol_weights, by = c("date", "ticker")) |>
          dplyr::group_by(date) |>
          dplyr::mutate(
            inv_vol = dplyr::if_else(is.na(vol_63d) | vol_63d == 0, NA_real_, 1 / vol_63d),
            sum_inv_vol = sum(inv_vol, na.rm = TRUE),
            vol_weight = dplyr::if_else(
              is.na(inv_vol) | sum_inv_vol == 0,
              1 / dplyr::n(),        # equal-weight fallback
              inv_vol / sum_inv_vol
            )
          ) |>
          dplyr::ungroup() |>
          dplyr::select(date, ticker, mom_total, mom_btc_adj, mom_residual, vol_weight)
      }
    ),

    # -------------------------------------------------------------------------
    # Backtest targets: 3 signals x 2 frequencies = 6 targets
    # -------------------------------------------------------------------------

    # 8. Monthly: Baseline (total) momentum
    tar_target(
      sol_bt_monthly_baseline,
      backtest_crypto_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_total),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # 9. Monthly: BTC-adjusted momentum
    tar_target(
      sol_bt_monthly_btc_adj,
      backtest_crypto_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_btc_adj),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # 10. Monthly: Residual-only momentum
    tar_target(
      sol_bt_monthly_residual,
      backtest_crypto_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_residual),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # 11. Weekly: Baseline (total) momentum
    tar_target(
      sol_bt_weekly_baseline,
      backtest_weekly_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_total),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # 12. Weekly: BTC-adjusted momentum
    tar_target(
      sol_bt_weekly_btc_adj,
      backtest_weekly_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_btc_adj),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # 13. Weekly: Residual-only momentum
    tar_target(
      sol_bt_weekly_residual,
      backtest_weekly_momentum(
        signals = sol_signals |>
          dplyr::select(date, ticker, signal = mom_residual),
        returns = sol_returns |> dplyr::filter(ticker %in% SOLANA_UNIVERSE),
        cost_bps = COST_BPS,
        n_long = N_LONG,
        n_short = N_SHORT
      )
    ),

    # -------------------------------------------------------------------------
    # Summary and diagnostic targets
    # -------------------------------------------------------------------------

    # 14. Performance summary table: strategy x freq -> metrics
    tar_target(
      sol_performance_summary,
      {
        extract_summary <- function(bt, strategy, freq) {
          s <- bt$summary
          dplyr::tibble(
            strategy   = strategy,
            freq       = freq,
            gross_sharpe   = s$gross_sharpe,
            net_sharpe     = s$net_sharpe,
            annual_ret     = s$net_annual_ret,
            max_drawdown   = s$max_drawdown,
            avg_turnover   = s$avg_turnover,
            n_years        = s$n_years
          )
        }

        dplyr::bind_rows(
          extract_summary(sol_bt_monthly_baseline,  "Baseline",   "monthly"),
          extract_summary(sol_bt_monthly_btc_adj,   "BTC-Adj",    "monthly"),
          extract_summary(sol_bt_monthly_residual,  "Residual",   "monthly"),
          extract_summary(sol_bt_weekly_baseline,   "Baseline",   "weekly"),
          extract_summary(sol_bt_weekly_btc_adj,    "BTC-Adj",    "weekly"),
          extract_summary(sol_bt_weekly_residual,   "Residual",   "weekly")
        )
      }
    ),

    # 15. BTC beta stats per Solana token
    tar_target(
      sol_btc_beta_stats,
      sol_btc_betas |>
        dplyr::group_by(ticker) |>
        dplyr::summarise(
          mean_beta   = mean(btc_beta, na.rm = TRUE),
          median_beta = stats::median(btc_beta, na.rm = TRUE),
          sd_beta     = stats::sd(btc_beta, na.rm = TRUE),
          beta_25     = stats::quantile(btc_beta, 0.25, na.rm = TRUE),
          beta_75     = stats::quantile(btc_beta, 0.75, na.rm = TRUE),
          n_obs       = dplyr::n(),
          .groups = "drop"
        ) |>
        dplyr::arrange(dplyr::desc(median_beta))
    ),

    # 16. Cumulative returns plot (all 6 series)
    tar_target(
      sol_cumulative_plot,
      {
        extract_cumret <- function(bt, strategy, freq) {
          bt$performance |>
            dplyr::select(date, cum_ret_net) |>
            dplyr::mutate(
              strategy = strategy,
              freq     = freq,
              series   = paste0(strategy, " (", freq, ")")
            )
        }

        combined <- dplyr::bind_rows(
          extract_cumret(sol_bt_monthly_baseline,  "Baseline",  "monthly"),
          extract_cumret(sol_bt_monthly_btc_adj,   "BTC-Adj",   "monthly"),
          extract_cumret(sol_bt_monthly_residual,  "Residual",  "monthly"),
          extract_cumret(sol_bt_weekly_baseline,   "Baseline",  "weekly"),
          extract_cumret(sol_bt_weekly_btc_adj,    "BTC-Adj",   "weekly"),
          extract_cumret(sol_bt_weekly_residual,   "Residual",  "weekly")
        )

        ggplot2::ggplot(
          combined,
          ggplot2::aes(x = date, y = cum_ret_net, color = series, linetype = freq)
        ) +
          ggplot2::geom_line(linewidth = 0.9) +
          ggplot2::scale_color_manual(
            values = c(
              "Baseline (monthly)"  = "#2c3e50",
              "BTC-Adj (monthly)"   = "#e67e22",
              "Residual (monthly)"  = "#c0392b",
              "Baseline (weekly)"   = "#7f8c8d",
              "BTC-Adj (weekly)"    = "#f39c12",
              "Residual (weekly)"   = "#e74c3c"
            )
          ) +
          ggplot2::scale_linetype_manual(
            values = c("monthly" = "solid", "weekly" = "dashed")
          ) +
          ggplot2::labs(
            title = paste0(
              "Solana Momentum Decomposition: Cumulative Net Returns\n",
              "Universe: ", paste(SOLANA_UNIVERSE, collapse = ", "),
              " | Cost: ", COST_BPS, "bps | Lookback: ", LOOKBACK_DAYS, "d"
            ),
            x    = NULL,
            y    = "Cumulative Return (net of costs)",
            color = "Strategy",
            linetype = "Frequency"
          ) +
          ggplot2::theme_minimal(base_size = 11) +
          ggplot2::theme(legend.position = "right")
      }
    )

  )
}
