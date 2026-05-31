# Plan: Strategy Names — single source of truth
#
# Provides a unified tibble of all strategies in the project.
# All downstream plans (falsification vignette, leaderboard, etc.)
# should filter this target rather than defining their own name tables.
#
# Current count: 14 strategies (rows 1-11 original; rows 12-14 mom_prepeak
# siblings added in #365 PR 2/4).

plan_strategy_names <- function() {
  list(
    targets::tar_target(strategy_names, {
      tibble::tibble(
        code_name = c(
          "avoid_worst", "drif", "fac_max", "rsc", "ltr", "tom",
          "stk_max", "stk_drif", "xgb_drif", "pso_optimal",
          "cmr",
          # ── #365: pre-peak / post-peak 12-2 momentum decomposition ──
          "mom_prepeak", "mom_postpeak", "mom_combined"
        ),
        short_name = c(
          "Avoid Worst", "Factor DRIF", "Factor MAX", "Risk State", "LTR", "TOM",
          "Stock MAX", "Stock DRIF", "XGB DRIF", "PSO Optimal",
          "CMR",
          "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2"
        ),
        long_name = c(
          "Avoid Worst Days (VIX Protection)",
          "Factor DRIF (Factor Rotation)",
          "Factor MAX (Factor Momentum)",
          "Risk State (VIX Overlay)",
          "LTR (Cross-Sectional Momentum)",
          "Turn-of-the-Month (TOM Overlay)",
          "Stock MAX (Daily Return Sorting)",
          "Stock DRIF (Elastic Net Stock Selection)",
          "XGB DRIF (XGBoost Stock Selection)",
          "PSO Optimal (Portfolio Optimisation)",
          "Commodities Mean Reversion",
          "Pre-Peak 12-2 Momentum (Büsing 2022)",
          "Post-Peak 12-2 Momentum (Büsing 2022)",
          "Standard 12-2 Momentum (Büsing baseline)"
        ),
        asset_class = c(
          "overlay", "factor", "factor", "overlay", "equity", "overlay",
          "equity", "equity", "equity", "combined",
          "commodities",
          "equity", "equity", "equity"
        ),
        frequency = c(
          "daily", "monthly", "monthly", "daily", "monthly", "daily",
          "monthly", "monthly", "monthly", "monthly",
          "monthly",
          "monthly", "monthly", "monthly"
        ),
        ann_factor = c(252L, 12L, 12L, 252L, 12L, 252L, 12L, 12L, 12L, 12L, 12L,
                       12L, 12L, 12L),
        vignette_url = c(
          "avoid-worst-days.html", "drif.html", "factor-max.html",
          "leaderboard.html", "leaderboard.html", "turn-of-month.html",
          "stock-backtest.html", "stock-backtest.html",
          "stock-backtest.html", "leaderboard.html",
          "commodities-mean-reversion.html",
          "momentum-prepeak.html", "momentum-prepeak.html", "momentum-prepeak.html"
        ),
        # ── #346 strategy registry keywords (rough first-pass; refine after a full tar_make) ──
        # Order matches code_name above (1 avoid_worst .. 11 cmr, 12-14 mom_prepeak siblings).
        time_horizon_days_avg = c(
          1L,  21L, 21L, 1L,  252L, 1L,
          21L, 21L, 21L, 90L,
          21L,
          21L, 21L, 21L
        ),
        trades_per_year_avg = c(
          12,  12,  12,  12,  12,  12,
          12,  12,  12,   4,
          12,
          12, 12, 12
        ),
        liquidity_tier = factor(
          c("high", "high", "high", "high", "med", "high",
            "med",  "med",  "med",  "high",
            "med",
            "med", "med", "med"),
          levels = c("high", "med", "low")
        ),
        turnover_pct_per_period_avg = c(
          50, 30, 30, 50, 20, 10,
          100, 100, 100, 10,
          100,
          100, 100, 100
        ),
        directionality = factor(
          c("overlay",    "long_only",  "long_only",  "overlay",    "long_short", "overlay",
            "long_short", "long_short", "long_short", "long_only",
            "long_short",
            "long_short", "long_short", "long_short"),
          levels = c("long_only", "long_short", "market_neutral", "overlay")
        ),
        # Tags as JSON-encoded character vectors so duckplyr can pick them
        # up as VARCHAR and a future hd_strategy_tags() helper can parse.
        tags = c(
          '["vix","market_timing","overlay"]',
          '["factor_rotation","elastic_net","monthly"]',
          '["factor_rotation","monthly"]',
          '["vix","market_timing","overlay"]',
          '["momentum","cross_sectional","monthly"]',
          '["calendar","seasonal","overlay"]',
          '["momentum","cross_sectional","stock_level"]',
          '["elastic_net","ml","stock_level"]',
          '["xgboost","ml","stock_level","monotonic"]',
          '["portfolio","pso","optimisation","combined"]',
          '["mean_reversion","commodities"]',
          '["momentum","cross_sectional","decomposition","prepeak"]',
          '["momentum","cross_sectional","decomposition","postpeak"]',
          '["momentum","cross_sectional","baseline"]'
        ),
        research_paper_doi = c(
          NA_character_,                  # 1 avoid_worst (folk wisdom; no single paper)
          "10.2139/ssrn.5520615",         # 2 drif (Cakici et al. 2024 — placeholder)
          "10.2139/ssrn.5520615",         # 3 fac_max
          NA_character_,                  # 4 rsc (VIX overlay variant)
          "10.1016/0304-405X(93)90023-5", # 5 ltr (Jegadeesh & Titman 1993 placeholder)
          NA_character_,                  # 6 tom (TradeQuantix newsletter — no DOI)
          "10.2139/ssrn.5520615",         # 7 stk_max (Cakici family at stock level)
          "10.2139/ssrn.5520615",         # 8 stk_drif
          NA_character_,                  # 9 xgb_drif (no paper)
          NA_character_,                  # 10 pso_optimal (PSO is engineering)
          NA_character_,                  # 11 cmr (internal — #134/#138)
          "10.2139/ssrn.4298538",         # 12 mom_prepeak (Büsing, Mohrschladt & Siedhoff 2022)
          "10.2139/ssrn.4298538",         # 13 mom_postpeak
          "10.2139/ssrn.4298538"          # 14 mom_combined (baseline)
        )
      )
    })
  )
}
