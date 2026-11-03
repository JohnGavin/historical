# Plan: Shadow Trade Analysis — Entry/Exit Timing Sensitivity
#
# For the avoid_worst (VIX protection) event-driven strategy, tests whether
# the measured alpha is sensitive to precise entry/exit timing.
# Shifts entry by 0–3 business days forward and exit by -5 to +5 business
# days, re-computes trade returns for each combination, and summarises
# the per-trade ratio, win rate, and mean return across the grid.
#
# The per-trade ratio is mean/sd of the individual trade returns: NOT
# annualised and with NO risk-free rate deducted (not excess), so it is not a
# Sharpe and must not be compared with an annual Sharpe (#937 item 4).
#
# Interpretation: if the offset (0,0) ratio is significantly higher than
# neighbouring offsets, the strategy may depend on lucky timing rather than
# a genuine edge.

plan_shadow_trades <- function() {
  list(
    # ── Parameters ────────────────────────────────────────────────
    targets::tar_target(shadow_params, {
      list(
        entry_offsets = c(0L, 1L, 2L, 3L),
        exit_offsets  = c(-5L, -2L, 0L, 2L, 5L)
      )
    }),

    # ── Avoid Worst: shadow trades ────────────────────────────────
    # Uses aw_practical_backtest (has in_market flag) to detect trades,
    # and aw_daily_returns$SPY as the underlying daily return series.
    targets::tar_target(shadow_avoid_worst, {
      library(dplyr)

      # SPY daily returns (underlying for the avoid_worst strategy)
      spy <- aw_daily_returns |>
        dplyr::filter(ticker == "SPY") |>
        dplyr::mutate(date = as.Date(date)) |>
        dplyr::arrange(date) |>
        dplyr::select(date, ret)

      # Reconstruct in_market from aw_practical_backtest
      aw <- aw_practical_backtest |>
        dplyr::mutate(
          date      = as.Date(date),
          # strategy_ret is 0 when out of market; in_market tracks actual flag
          in_market = in_market
        ) |>
        dplyr::select(date, strategy_ret = ret_strategy, in_market) |>
        dplyr::arrange(date)

      # Extract event-based trades (in_market blocks)
      trades <- hd_event_trades(aw)

      if (nrow(trades) < 5L) {
        cli::cli_warn("shadow_avoid_worst: fewer than 5 trades detected — returning NULL.")
        return(NULL)
      }

      hd_shadow_trades(
        trades,
        spy,
        entry_offsets = shadow_params$entry_offsets,
        exit_offsets  = shadow_params$exit_offsets
      )
    }),

    # ── Summary: per-trade ratio / win-rate across the offset grid ─
    targets::tar_target(shadow_summary, {
      library(dplyr)

      if (is.null(shadow_avoid_worst)) return(NULL)

      shadow_avoid_worst |>
        dplyr::group_by(entry_offset, exit_offset) |>
        dplyr::summarise(
          n_trades     = dplyr::n(),
          mean_return  = round(mean(return_pct, na.rm = TRUE) * 100, 2),
          median_return = round(median(return_pct, na.rm = TRUE) * 100, 2),
          win_rate     = round(mean(is_win, na.rm = TRUE) * 100, 1),
          # per-trade ratio, not annualised, not excess (no rf): not a Sharpe
          per_trade_ratio = round(
            mean(return_pct, na.rm = TRUE) /
              sd(return_pct, na.rm = TRUE),
            2
          ),
          .groups = "drop"
        ) |>
        dplyr::arrange(entry_offset, exit_offset)
    }),

    # ── Optimal offset vs actual (0,0) ────────────────────────────
    targets::tar_target(shadow_optimal, {
      library(dplyr)

      if (is.null(shadow_summary)) return(NULL)

      actual <- shadow_summary |>
        dplyr::filter(entry_offset == 0L, exit_offset == 0L)

      best <- shadow_summary |>
        dplyr::slice_max(per_trade_ratio, n = 1L, with_ties = FALSE)

      list(
        actual_ratio = actual$per_trade_ratio,
        best_entry   = best$entry_offset,
        best_exit    = best$exit_offset,
        best_ratio   = best$per_trade_ratio,
        improvement  = best$per_trade_ratio - actual$per_trade_ratio
      )
    }),

    # ── Dynamic caption ───────────────────────────────────────────
    targets::tar_target(shadow_caption, {
      if (is.null(shadow_optimal)) {
        return("Shadow trade analysis: insufficient trades for analysis.")
      }

      paste0(
        "Shadow trade analysis for Avoid Worst Days strategy. ",
        "Entry offsets: 0\u20133 business days forward; ",
        "exit offsets: \u22125 to +5 business days. ",
        "Ratios are mean/sd of individual trade returns ",
        "(per-trade ratio, not annualised, not excess). ",
        "Actual timing (0,0) per-trade ratio: ", shadow_optimal$actual_ratio, ". ",
        "Best offset (",
        shadow_optimal$best_entry, ", ",
        shadow_optimal$best_exit,
        ") per-trade ratio: ", shadow_optimal$best_ratio, ". ",
        if (shadow_optimal$improvement > 0.05) {
          paste0(
            "Signal timing may be suboptimal \u2014 ",
            round(shadow_optimal$improvement, 2),
            " per-trade-ratio improvement available from alternative offsets."
          )
        } else {
          "Signal timing is well-calibrated: no meaningful improvement from neighbouring offsets."
        }
      )
    })
  )
}
