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
