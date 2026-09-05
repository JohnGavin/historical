# Liquidity metrics targets
# Addresses gap from #105: volume data not used for liquidity analysis
#
# Wired into the root pipeline (#569): consolidated_equity (_targets.R) carries
# date, close, volume, ticker — the schema calculate_adv() expects.
#
# calculate_turnover() (R/liquidity.R) is intentionally NOT wired here. It
# compares realized turnover to a hardcoded 0.80 assumption that is itself
# under review in #567 — wiring it in this PR would collide with that fix.
#
# ── Two unreconciled ADV thresholds (#625) ─────────────────────────────────
# There are two different minimum-ADV thresholds in this codebase, and they
# are NOT the same number for the same reason:
#
#   - min_adv_threshold = $1M (this file, and filter_liquidity()'s default
#     in R/liquidity.R) — a UNIVERSE-WIDE liquidity flag. It answers "is this
#     name tradeable at all", governs `volume_stats`/`liquidity_summary_tbl`
#     below, and runs in filter_mode="warn": it FLAGS illiquid rows but does
#     NOT remove them (see the module docstring above and the dashboard-tab
#     prose in docs/falsification.qmd#liquidity for the consequence).
#
#   - stk_params$adv_threshold = $5M (R/plan_stock_backtest.R:399) — a
#     stricter INVESTABILITY GATE used only inside decile-construction for
#     the Factor MAX / DRIF stock backtests (#312). It is deliberately higher
#     because a long-short decile book concentrates capital in far fewer
#     names than the full universe and needs more headroom against
#     price-impact than a simple presence/absence flag does.
#
# Neither value governs the other. The $1M universe-wide summary surfaced by
# this plan's targets does NOT mean "stocks below $5M are excluded from
# backtests" — `stk_universe` (R/plan_stock_backtest.R:421) does not depend
# on `equity_liquidity_filtered`, so illiquid names are never actually
# dropped from backtest portfolios today. Do not change either value here;
# that is a modelling decision tracked separately, not a bug to silently fix.

plan_liquidity <- function() {
  list(
    # === Liquidity metrics for equity data ===
    targets::tar_target(
      equity_with_adv,
      {
        consolidated_equity |>
          calculate_adv(window_days = 20)
      }
    ),

    targets::tar_target(
      equity_liquidity_filtered,
      {
        equity_with_adv |>
          filter_liquidity(min_adv_usd = 1e6, filter_mode = "warn")
      }
    ),

    targets::tar_target(
      liquidity_summary_tbl,
      {
        equity_liquidity_filtered |>
          liquidity_summary()
      }
    ),

    # === Volume statistics for vignettes ===
    targets::tar_target(
      volume_stats,
      {
        equity_liquidity_filtered |>
          dplyr::summarise(
            total_tickers = dplyr::n_distinct(ticker),
            total_observations = dplyr::n(),
            median_adv_all = median(adv_usd, na.rm = TRUE),
            pct_liquid = 100 * mean(liquidity_flag == "liquid", na.rm = TRUE),
            pct_illiquid = 100 * mean(liquidity_flag == "illiquid", na.rm = TRUE),
            min_adv_threshold = 1e6
          )
      }
    )
  )
}

# ── equity_daily-sourced variant (#625 Option A, decided 2026-08-04) ───────
#
# plan_liquidity() above cannot run inside docs/_targets.R: consolidated_equity
# only exists in the ROOT ingestion pipeline (_targets.R:58). This second plan
# function re-expresses the same three-step liquidity computation
# (calculate_adv -> filter_liquidity -> liquidity_summary) against
# `stk_universe` (R/plan_stock_backtest.R:421) instead — the equity source the
# dashboard's own backtests actually trade — so it can be wired into
# docs/_targets.R. It is a SEPARATE function, not an extension of
# plan_liquidity(), because plan_liquidity()'s targets are combined into the
# root pipeline (_targets.R:61) where `stk_universe` does not exist; keeping
# them apart lets both sets of targets build in their respective pipelines
# without either referencing an undefined symbol.
#
# Column-shape note: stk_universe already carries date, ticker, close, volume
# (plus adjusted) -- exactly the schema calculate_adv() expects. No adaptation
# of calculate_adv()/filter_liquidity()/liquidity_summary() themselves was
# needed or made.
#
# Volume-corruption guard note: stk_universe's own comment says its universe
# is "S&P 500 + STOXX 600 majors, excluding LSE ETFs" (R/plan_stock_backtest.R:4)
# -- i.e. it DOES contain non-US (European) tickers. stk_universe excludes
# `.L` (LSE) tickers via a hardcoded regex (R/plan_stock_backtest.R:432), but
# that is a narrower, DIFFERENT filter than the yfinance non-US
# volume-corruption guard (hd_unreliable_volume_ticker(), packages/
# historicaldata/R/volume_reliability.R) -- .DE/.PA/.AS/.SW/.MC/.MI/.ST/.CO
# tickers pass through stk_universe with their raw (unreliable) volume
# intact. hd_ohlcv_single() (packages/historicaldata/R/query.R:227-237)
# applies hd_unreliable_volume_ticker() automatically when data is fetched
# through hd_ohlcv()/hd_lazy(), but stk_universe bypasses those wrappers --
# it queries hd_datasets()[["equity_daily"]]$url directly via
# duckplyr::read_parquet_duckdb(). The guard is therefore applied explicitly
# below, before calculate_adv() ever sees the volume column.
#
# ── Provenance divergence risk (flagged here per #625; not resolved here) ──
# The ingestion-side liquidity_summary_tbl/volume_stats above are computed
# from consolidated_equity (ALL ingested equity tickers). The dashboard-side
# equity_daily_liquidity_summary_tbl/equity_daily_volume_stats below are
# computed from stk_universe, which is restricted to the top
# stk_params$top_n_market_cap (100) tickers by current market cap
# (R/plan_stock_backtest.R:405-418) with >= stk_params$min_history_days of
# history. Nothing asserts these two equity sources agree, and now that the
# dashboard computes liquidity from a DIFFERENT (narrower, cap-weighted)
# ticker set than ingestion's full universe, the two liquidity views can
# diverge silently -- e.g. the dashboard's median ADV will structurally run
# higher because it excludes the long tail of small/illiquid names ingestion
# still reports on. This is flagged as a follow-up, not built here: no
# reconciliation check is added by this change.
plan_liquidity_dashboard <- function() {
  list(
    targets::tar_target(
      equity_daily_with_adv,
      {
        stk_universe |>
          dplyr::mutate(
            volume = dplyr::if_else(
              hd_unreliable_volume_ticker(ticker),
              NA_real_,
              as.numeric(volume)
            )
          ) |>
          calculate_adv(window_days = 20)
      }
    ),

    targets::tar_target(
      equity_daily_liquidity_filtered,
      {
        equity_daily_with_adv |>
          filter_liquidity(min_adv_usd = 1e6, filter_mode = "warn")
      }
    ),

    targets::tar_target(
      equity_daily_liquidity_summary_tbl,
      {
        equity_daily_liquidity_filtered |>
          liquidity_summary()
      }
    ),

    # === Volume statistics for the dashboard ===
    targets::tar_target(
      equity_daily_volume_stats,
      {
        equity_daily_liquidity_filtered |>
          dplyr::summarise(
            total_tickers = dplyr::n_distinct(ticker),
            total_observations = dplyr::n(),
            median_adv_all = median(adv_usd, na.rm = TRUE),
            pct_liquid = 100 * mean(liquidity_flag == "liquid", na.rm = TRUE),
            pct_illiquid = 100 * mean(liquidity_flag == "illiquid", na.rm = TRUE),
            min_adv_threshold = 1e6
          )
      }
    ),

    # ── Percentile-indexed threshold variant (#625 "principled fix") ──────
    #
    # The nominal $1M cut above is a fixed dollar figure applied across the
    # full sample. As market-wide ADV grows over a multi-decade span, $1M
    # sits at a different liquidity percentile in 2005 than in 2025, so the
    # nominal gate silently tightens or loosens over time (#625, "A real
    # modelling concern" section). This variant recomputes the cutoff from
    # the current day's cross-section instead: it flags the bottom
    # min_adv_percentile (30%) of names by ADV each day, which is invariant
    # to the absolute dollar level and comparable across liquidity regimes
    # (e.g. 2008, 2020).
    #
    # Deliberately scoped to this dashboard-visible, informational flag only
    # (filter_mode stays "warn" -- nothing is removed from any backtest by
    # this target, same as the nominal-threshold targets above). The other
    # nominal ADV gate in this codebase, stk_params$adv_threshold ($5M,
    # R/plan_stock_backtest.R:483), is a production INVESTABILITY gate that
    # is filtered into directly during Factor MAX / DRIF decile construction
    # (R/plan_stock_backtest.R:1141, R/plan_xgb_signal.R:133) -- switching
    # that one to a percentile basis would change published backtest
    # returns and needs its own before/after comparison, exactly like the
    # filter_mode flip this issue explicitly keeps out of scope. Not done
    # here; see the #625 follow-up issue.
    targets::tar_target(
      equity_daily_liquidity_filtered_pctile,
      {
        equity_daily_with_adv |>
          filter_liquidity(
            threshold_mode = "percentile",
            min_adv_percentile = 0.30,
            by = "date",
            filter_mode = "warn"
          )
      }
    ),

    targets::tar_target(
      equity_daily_volume_stats_pctile,
      {
        equity_daily_liquidity_filtered_pctile |>
          dplyr::summarise(
            total_tickers = dplyr::n_distinct(ticker),
            total_observations = dplyr::n(),
            median_adv_all = median(adv_usd, na.rm = TRUE),
            pct_liquid = 100 * mean(liquidity_flag == "liquid", na.rm = TRUE),
            pct_illiquid = 100 * mean(liquidity_flag == "illiquid", na.rm = TRUE),
            min_adv_percentile = 0.30
          )
      }
    )
  )
}
