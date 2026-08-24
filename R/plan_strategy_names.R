# Plan: Strategy Names — single source of truth
#
# Provides a unified tibble of all strategies in the project.
# All downstream plans (falsification vignette, leaderboard, etc.)
# should filter this target rather than defining their own name tables.
#
# Current count: 17 strategies (rows 1-11 original; rows 12-14 mom_prepeak
# siblings added in #365 PR 2/4; row 15 ev_ebit added in #426;
# row 16 mf_tsm added in #427; row 17 olmar added in #629).

plan_strategy_names <- function() {
  list(
    targets::tar_target(strategy_names, hd_strategy_names_tbl())
  )
}

#' Plain (non-target) constructor for the strategy_names tibble (#629)
#'
#' Extracted out of the `strategy_names` tar_target so this single source
#' of truth is callable WITHOUT tar_make()/tar_read(). Sourcing this file
#' is enough -- e.g. R/plan_leaderboard.R derives STRATEGY_OBS_ANN_FACTOR's
#' `strategy`/`obs_ann_factor` columns by calling this function directly
#' at source() time, instead of hand-maintaining a second, drift-prone copy
#' of the same data (see the STRATEGY_OBS_ANN_FACTOR comment in
#' R/plan_leaderboard.R and issue #629 for the two-lists-disagreeing defect
#' this closes). Any new code that needs the full strategy roster outside
#' the targets pipeline (tests, other plan files) should call this function
#' rather than duplicating the tibble.
#' @noRd
hd_strategy_names_tbl <- function() {
  tibble::tibble(
    code_name = c(
      "avoid_worst", "drif", "fac_max", "rsc", "ltr", "tom",
      "stk_max", "stk_drif", "xgb_drif", "pso_optimal",
      "cmr",
      # ── #365: pre-peak / post-peak 12-2 momentum decomposition ──
      "mom_prepeak", "mom_postpeak", "mom_combined",
      # ── #426: EV/EBIT fundamental value sleeve (HML proxy v0) ──
      "ev_ebit",
      # ── #427: cross-asset TS-momentum / managed futures (MOP 2012 v0) ──
      "mf_tsm",
      # ── #629: OLMAR-1 online moving-average reversion (Li & Hoi 2012) --
      # was already ranked on the leaderboard (R/plan_leaderboard.R
      # STRATEGY_OBS_ANN_FACTOR) but missing from this declared list --
      # appended at the end (not inserted mid-vector) to avoid corrupting
      # the alignment of any existing row.
      "olmar"
    ),
    short_name = c(
      "Avoid Worst", "Factor DRIF", "Factor MAX", "Risk State", "LTR", "TOM",
      "Stock MAX", "Stock DRIF", "XGB DRIF", "PSO Optimal",
      "CMR",
      "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
      "Value (HML)",
      "Managed Futures",
      # Must exactly match STRATEGY_OBS_ANN_FACTOR's "OLMAR-1" display key
      # (R/plan_leaderboard.R) -- that is the join key the two now share.
      "OLMAR-1"
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
      "Standard 12-2 Momentum (Büsing baseline)",
      "EV/EBIT Value Sleeve (HML+RMW Proxy, v0)",
      "Cross-Asset TS-Momentum (MOP 2012, ETF Proxies, v0)",
      "OLMAR-1 (Online Moving Average Reversion, Li & Hoi 2012)"
    ),
    asset_class = c(
      "overlay", "factor", "factor", "overlay", "equity", "overlay",
      "equity", "equity", "equity", "combined",
      "commodities",
      "equity", "equity", "equity",
      "factor",
      "multi_asset",
      "equity"
    ),
    frequency = c(
      "daily", "monthly", "monthly", "daily", "monthly", "daily",
      "monthly", "monthly", "monthly", "monthly",
      # #717: cmr (position 11) is daily, not monthly -- the 37-series
      # universe is 96% Yahoo daily futures/ETF rows (see #717/#720).
      "daily",
      "monthly", "monthly", "monthly",
      "monthly",
      "monthly",
      # #629: OLMAR-1 rebalances daily (R/plan_olmar.R weights formed at
      # close of day t, realised on t+1 -- see this file's own comment).
      "daily"
    ),
    ann_factor = c(252L, 12L, 12L, 252L, 12L, 252L, 12L, 12L, 12L, 12L, 252L,
                   12L, 12L, 12L, 12L, 12L,
                   252L),
    vignette_url = c(
      "avoid-worst-days.html", "drif.html", "factor-max.html",
      "leaderboard.html", "leaderboard.html", "turn-of-month.html",
      "stock-backtest.html", "stock-backtest.html",
      "stock-backtest.html", "leaderboard.html",
      "commodities-mean-reversion.html",
      "momentum-prepeak.html", "momentum-prepeak.html", "momentum-prepeak.html",
      "leaderboard.html",
      "leaderboard.html",
      # No dedicated vignette (plan_olmar.R explicitly defers it) --
      # only appears on the leaderboard, same as PSO Optimal.
      "leaderboard.html"
    ),
    # ── #346 strategy registry keywords (rough first-pass; refine after a full tar_make) ──
    # Order matches code_name above (1 avoid_worst .. 11 cmr, 12-14 mom_prepeak siblings,
    # 15 ev_ebit added in #426, 16 mf_tsm added in #427, 17 olmar added in #629).
    time_horizon_days_avg = c(
      1L,  21L, 21L, 1L,  252L, 1L,
      21L, 21L, 21L, 90L,
      21L,
      21L, 21L, 21L,
      252L,
      252L,
      # OLMAR-1's SMA window (R/plan_olmar.R olmar_params$window = 25L).
      25L
    ),
    trades_per_year_avg = c(
      12,  12,  12,  12,  12,  12,
      12,  12,  12,   4,
      12,
      12, 12, 12,
      12,
      12,
      # Same convention as the other daily strategies above (avoid_worst,
      # rsc, tom, cmr) -- rebalance-evaluation frequency, not literal count.
      12
    ),
    liquidity_tier = factor(
      c("high", "high", "high", "high", "med", "high",
        "med",  "med",  "med",  "high",
        "med",
        "med", "med", "med",
        "high",
        "high",
        # 30-ticker large-cap + broad-ETF universe (R/plan_olmar.R
        # olmar_params$tickers) -- highly liquid, same tier as Stock MAX.
        "high"),
      levels = c("high", "med", "low")
    ),
    turnover_pct_per_period_avg = c(
      50, 30, 30, 50, 20, 10,
      100, 100, 100, 10,
      100,
      100, 100, 100,
      20,
      25,
      # Daily online mean-reversion rebalance -- same turnover tier as CMR.
      100
    ),
    directionality = factor(
      c("overlay",    "long_only",  "long_only",  "overlay",    "long_short", "overlay",
        "long_short", "long_short", "long_short", "long_only",
        "long_short",
        "long_short", "long_short", "long_short",
        "long_only",
        "long_short",
        # Tilt fraction around equal weight (R/plan_olmar.R
        # olmar_params$leverage = 0.2) -- no shorting evidence in the code.
        "long_only"),
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
      '["momentum","cross_sectional","baseline"]',
      '["value","fundamental","factor","monthly","quality"]',
      '["managed_futures","time_series_momentum","cross_asset","monthly","trend"]',
      '["mean_reversion","online_portfolio_selection","equity_basket","daily"]'
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
      "10.2139/ssrn.4298538",         # 14 mom_combined (baseline)
      "10.1111/j.1540-6261.1993.tb04741.x", # 15 ev_ebit (Fama & French 1993 three-factor model)
      "10.1111/jofi.12131",                  # 16 mf_tsm (Moskowitz, Ooi & Pedersen 2012)
      NA_character_                   # 17 olmar (Li & Hoi 2012, ICML -- arXiv:1206.4626, no verified formal DOI at this commit)
    )
  )
}
