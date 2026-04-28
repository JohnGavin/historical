# Plan: Strategy Names — single source of truth
#
# Provides a unified tibble of all strategies in the project.
# All downstream plans (falsification vignette, leaderboard, etc.)
# should filter this target rather than defining their own name tables.

plan_strategy_names <- function() {
  list(
    targets::tar_target(strategy_names, {
      tibble::tibble(
        code_name = c(
          "avoid_worst", "drif", "fac_max", "rsc", "ltr",
          "stk_max", "stk_drif", "xgb_drif", "pso_optimal"
        ),
        short_name = c(
          "Avoid Worst", "DRIF", "Factor MAX", "Risk State", "LTR",
          "Stock MAX", "Stock DRIF", "XGB DRIF", "PSO Optimal"
        ),
        long_name = c(
          "Avoid Worst Days (VIX Protection)",
          "DRIF (Factor Rotation)",
          "Factor MAX (Factor Momentum)",
          "Risk State (VIX Overlay)",
          "LTR (Cross-Sectional Momentum)",
          "Stock MAX (Daily Return Sorting)",
          "Stock DRIF (Elastic Net Stock Selection)",
          "XGB DRIF (XGBoost Stock Selection)",
          "PSO Optimal (Portfolio Optimisation)"
        ),
        asset_class = c(
          "overlay", "factor", "factor", "overlay", "equity",
          "equity", "equity", "equity", "combined"
        ),
        frequency = c(
          "daily", "monthly", "monthly", "daily", "monthly",
          "monthly", "monthly", "monthly", "monthly"
        ),
        ann_factor = c(252L, 12L, 12L, 252L, 12L, 12L, 12L, 12L, 12L),
        vignette_url = c(
          "avoid-worst-days.html", "drif.html", "factor-max.html",
          "leaderboard.html", "leaderboard.html",
          "stock-backtest.html", "stock-backtest.html",
          "stock-backtest.html", "leaderboard.html"
        )
      )
    })
  )
}
