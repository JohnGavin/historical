# Model leaderboard: collects metrics from all strategies into one table
#
# Transposed format: metrics as rows, strategies as columns
# (fewer strategies than metrics, at least for now)

plan_leaderboard <- function() {
  list(
    # Explicit deps — targets must be named as function args
    targets::tar_target(leaderboard, {
      library(dplyr)

      add_meta <- function(m, name, level, signal, url) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |> mutate(strategy = name, level = level, signal = signal, definition = url)
      }

      all_metrics <- bind_rows(
        add_meta(fm_metrics, "Factor MAX", "Factor", "Max daily return",
                 "factor-max.html"),
        add_meta(drif_metrics, "Factor DRIF", "Factor", "Elastic net (42 feat)",
                 "drif.html"),
        add_meta(stk_max_metrics, "Stock MAX", "Stock", "Max daily return",
                 "stock-backtest.html#stock-max"),
        add_meta(stk_drif_metrics, "Stock DRIF", "Stock", "Elastic net (42 feat)",
                 "stock-backtest.html#stock-drif"),
        add_meta(xgb_drif_metrics, "XGB DRIF", "Stock", "XGBoost monotonic (42 feat)",
                 "stock-backtest.html#stock-drif")
      )

      # Add portfolio optimal
      if (!is.null(port_metrics) && nrow(port_metrics) > 0) {
        port_row <- port_metrics |>
          transmute(
            period = period, months = months,
            cagr = opt_cagr, vol = opt_vol, sharpe = opt_sharpe, max_dd = opt_maxdd,
            strategy = "PSO Optimal", level = "Combined",
            signal = "Weighted portfolio",
            definition = "stock-backtest.html#comparison"
          )
        all_metrics <- bind_rows(all_metrics, port_row)
      }

      all_metrics
    })
  )
}
