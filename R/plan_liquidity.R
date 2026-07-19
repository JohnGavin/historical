# Liquidity metrics targets
# Addresses gap from #105: volume data not used for liquidity analysis
#
# Wired into the root pipeline (#569): consolidated_equity (_targets.R) carries
# date, close, volume, ticker — the schema calculate_adv() expects.
#
# calculate_turnover() (R/liquidity.R) is intentionally NOT wired here. It
# compares realized turnover to a hardcoded 0.80 assumption that is itself
# under review in #567 — wiring it in this PR would collide with that fix.

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
