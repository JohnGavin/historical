# Targets Plan: Regime-Dependent Momentum Analysis
# Issue #123: Test if momentum decomposition works conditionally by VIX regime
#
# Context: Issue #121 showed all decomposed momentum strategies have negative
# Sharpe ratios. This plan tests if they work better in specific volatility regimes.
#
# Note: Depends on vix_daily from plan_volatility_spikes (avoid duplicate target)

plan_regime_momentum <- function() {
  list(
    # 1. Classify VIX regimes (calm/elevated/spike)
    # Uses vix_daily from plan_volatility_spikes to avoid duplication
    tar_target(
      vix_regimes,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        classify_vix_regimes(vix_daily)
      }
    ),

    # 2. Add regime information to momentum backtest results
    tar_target(
      momentum_by_regime,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        # Use backtest_results from plan_momentum_decomposition.R
        partition_returns_by_regime(backtest_results, vix_regimes)
      }
    ),

    # 3. Baseline (total 12m momentum) performance by regime
    tar_target(
      baseline_regime_performance,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        regime_conditional_performance(
          momentum_by_regime |> filter(scheme == "baseline"),
          regime_filter = "all"
        )
      }
    ),

    # 4. Decomposed strategies performance by regime
    tar_target(
      decomposed_regime_performance,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        regime_conditional_performance(
          momentum_by_regime |> filter(scheme != "baseline"),
          regime_filter = "all"
        )
      }
    ),

    # 5. Combined regime comparison table (all strategies × all regimes)
    tar_target(
      regime_comparison_table,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        # Compute performance for all strategies across all regimes
        all_performance <- regime_conditional_performance(
          momentum_by_regime,
          regime_filter = "all"
        )

        # Format for display
        all_performance |>
          mutate(
            scheme_label = recode(
              scheme,
              baseline = "Baseline (Total 12m)",
              paper = "Paper (Style + Industry)",
              data_driven = "Data-Driven (Industry + Stock)",
              conservative = "Conservative (Industry Only)"
            )
          ) |>
          select(
            Strategy = scheme_label,
            Regime = regime,
            `N Months` = n_months,
            `Mean VIX` = mean_vix,
            `Sharpe` = sharpe,
            `Annual Ret %` = annual_ret,
            `Max DD %` = max_dd,
            `Mean Turnover` = mean_turnover
          ) |>
          mutate(
            `Mean VIX` = round(`Mean VIX`, 1),
            `Sharpe` = round(`Sharpe`, 2),
            `Annual Ret %` = round(`Annual Ret %` * 100, 1),
            `Max DD %` = round(`Max DD %` * 100, 1),
            `Mean Turnover` = round(`Mean Turnover`, 3)
          ) |>
          arrange(Regime, desc(Sharpe))
      }
    ),

    # 6. Regime allocation comparison (binary vs continuous)
    tar_target(
      regime_allocation_comparison,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        # Test both allocation approaches
        compare_regime_allocation(
          momentum_by_regime,
          regimes = c("calm"),        # Binary: 100% in calm, 0% otherwise
          vix_min = 15,               # Continuous: 100% at VIX=15
          vix_max = 40                # Continuous: 0% at VIX=40
        ) |>
          mutate(
            scheme_label = recode(
              scheme,
              baseline = "Baseline (Total 12m)",
              paper = "Paper (Style + Industry)",
              data_driven = "Data-Driven (Industry + Stock)",
              conservative = "Conservative (Industry Only)"
            )
          ) |>
          select(
            Strategy = scheme_label,
            `Allocation Type` = allocation_type,
            `Months Invested` = n_months_invested,
            `% Time Invested` = pct_time_invested,
            `Mean Exposure` = mean_exposure,
            `Sharpe` = sharpe,
            `Annual Ret %` = annual_ret,
            `Max DD %` = max_dd
          ) |>
          mutate(
            `% Time Invested` = round(`% Time Invested`, 1),
            `Mean Exposure` = round(`Mean Exposure`, 2),
            `Sharpe` = round(`Sharpe`, 2),
            `Annual Ret %` = round(`Annual Ret %` * 100, 1),
            `Max DD %` = round(`Max DD %` * 100, 1)
          ) |>
          arrange(Strategy, `Allocation Type`)
      }
    ),

    # 7. Sharpe ratio plot by regime
    tar_target(
      regime_allocation_plot,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        # Get all performance metrics
        all_performance <- regime_conditional_performance(
          momentum_by_regime,
          regime_filter = "all"
        )

        plot_regime_sharpe(all_performance)
      }
    ),

    # 8. Cumulative returns with regime shading
    tar_target(
      regime_cumulative_plot,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        plot_regime_cumulative(momentum_by_regime, highlight_scheme = "paper")
      }
    ),

    # 9. Regime statistics summary
    tar_target(
      regime_stats,
      {
        library(dplyr)

        vix_regimes |>
          filter(!is.na(regime)) |>
          group_by(regime) |>
          summarise(
            n_days = n(),
            mean_vix = mean(vix, na.rm = TRUE),
            median_vix = median(vix, na.rm = TRUE),
            min_vix = min(vix, na.rm = TRUE),
            max_vix = max(vix, na.rm = TRUE),
            .groups = "drop"
          ) |>
          mutate(
            pct_days = n_days / sum(n_days) * 100,
            across(c(mean_vix, median_vix, min_vix, max_vix), ~round(.x, 1)),
            pct_days = round(pct_days, 1)
          )
      }
    ),

    # 10. Best/worst regime for each strategy
    tar_target(
      best_regime_by_strategy,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        all_performance <- regime_conditional_performance(
          momentum_by_regime,
          regime_filter = "all"
        )

        # For each strategy, find best and worst regime
        all_performance |>
          group_by(scheme) |>
          arrange(desc(sharpe)) |>
          slice(c(1, n())) |>
          mutate(
            rank = if_else(row_number() == 1, "Best", "Worst"),
            scheme_label = recode(
              scheme,
              baseline = "Baseline (Total 12m)",
              paper = "Paper (Style + Industry)",
              data_driven = "Data-Driven (Industry + Stock)",
              conservative = "Conservative (Industry Only)"
            )
          ) |>
          ungroup() |>
          select(
            Strategy = scheme_label,
            Rank = rank,
            Regime = regime,
            Sharpe = sharpe,
            `Annual Ret %` = annual_ret,
            `N Months` = n_months
          ) |>
          mutate(
            Sharpe = round(Sharpe, 2),
            `Annual Ret %` = round(`Annual Ret %` * 100, 1)
          )
      }
    ),

    # 11. Key finding: Do ANY decomposed strategies have positive Sharpe in ANY regime?
    tar_target(
      regime_rescue_test,
      {
        library(dplyr)
        source(here::here("R/regime_momentum.R"))

        all_performance <- regime_conditional_performance(
          momentum_by_regime,
          regime_filter = "all"
        )

        # Test: Are there any positive Sharpes in decomposed strategies?
        decomposed <- all_performance |>
          filter(scheme != "baseline")

        positive_sharpe <- decomposed |>
          filter(!is.na(sharpe), sharpe > 0)

        list(
          any_positive = nrow(positive_sharpe) > 0,
          n_positive = nrow(positive_sharpe),
          n_total = nrow(decomposed),
          positive_cases = if (nrow(positive_sharpe) > 0) {
            positive_sharpe |>
              select(scheme, regime, sharpe, n_months) |>
              arrange(desc(sharpe))
          } else {
            NULL
          },
          recommendation = if (nrow(positive_sharpe) == 0) {
            "ABANDON: No regime rescues decomposed momentum. All Sharpe ratios negative or NA."
          } else {
            paste0(
              "CONDITIONAL: ", nrow(positive_sharpe), " regime-strategy pairs show positive Sharpe. ",
              "Consider regime-conditional allocation."
            )
          }
        )
      }
    ),

    # 12. Summary caption for display
    tar_target(
      regime_momentum_caption,
      {
        library(dplyr)

        rescue <- regime_rescue_test

        baseline_perf <- baseline_regime_performance |>
          filter(regime == "calm") |>
          pull(sharpe) |>
          round(2)

        paste0(
          "Regime-dependent momentum analysis (Issue #123). ",
          "Baseline (total 12m) Sharpe in calm regime: ", baseline_perf, ". ",
          rescue$recommendation, " ",
          if (rescue$any_positive) {
            top_case <- rescue$positive_cases[1, ]
            paste0(
              "Best decomposed: ", top_case$scheme, " in ", top_case$regime,
              " regime (Sharpe = ", round(top_case$sharpe, 2), ", ",
              top_case$n_months, " months)."
            )
          } else {
            "All decomposed strategies (Paper, Data-Driven, Conservative) have negative Sharpe in all regimes."
          }
        )
      }
    )
  )
}
