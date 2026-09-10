# Plan: Retrospective drawdown stop-rule test (#588 G2/G3)
#
# Applies the three-arm stop-rule comparison (hd_stop_rule_backtest() /
# hd_stop_rule_compare_arms(), packages/historicaldata/R/stop_rule.R) to
# EXISTING strategy return series -- no new data, purely retrospective, per
# the issue's own scoping ("Cheap and genuinely informative: apply a fixed
# -X% stop to each existing strategy's realised return series").
#
# Reuses, rather than invents, both inputs:
#   - Strategy return series: the fals_*_input bridge targets already
#     extracted for the falsification framework (R/plan_falsification.R) --
#     avoid_worst, drif, fac_max, rsc, ltr.
#   - Regime label (Arm C only): regime_classification$regime
#     (R/plan_regime.R) -- low/medium/high risk, training-quantile
#     classified, monthly. Documented reasoning for THIS choice over the
#     alternatives named in the issue (VVIX hostile/cautious from
#     plan_risk_state.R, #543's composite 0-3 filter, #539's Student-t tail
#     classifier): regime_classification is monthly and joins cleanly by
#     `ym` onto the three MONTHLY strategy series below with no additional
#     alignment machinery; the other three candidates are either daily-only
#     (VVIX) or would need their own bridge target built first. Using a
#     second regime definition as a robustness check is future work, not
#     this dispatch (#588 is scoped to G2/G3 only).
#
# Arm C (regime-stop) therefore only runs for the three MONTHLY series
# (drif, fac_max, ltr) that align on `ym` with regime_classification without
# extra plumbing. avoid_worst and rsc are DAILY and would need a
# daily-to-monthly regime broadcast (join by date -> ym -> regime) that is
# out of scope for this dispatch -- Arms A/B (no regime needed) still run
# for all five series. This asymmetry is intentional and documented, not an
# oversight (fail-loud-not-null.md: a documented limitation, not a silent
# gap).
#
# rf = NULL throughout (cash while stopped out) -- an explicit, documented
# simplifying assumption (see hd_stop_rule_backtest()'s @param rf), not a
# silent default. Using each strategy's own risk-free series would require
# joining stk_rf per date/ym onto each of the five series; deferred as
# follow-up since it does not change the ARM COMPARISON (all three arms use
# the same rf convention, so the comparison's conclusion is robust to this
# choice even though absolute Sharpe levels would shift slightly).
#
# Consumes: fals_avoid_worst_input, fals_drif_input, fals_fac_max_input,
#           fals_rsc_input, fals_ltr_input (R/plan_falsification.R),
#           regime_classification (R/plan_regime.R)
# Produces: stop_params, stop_arms_avoid_worst, stop_arms_drif,
#           stop_arms_fac_max, stop_arms_rsc, stop_arms_ltr,
#           stop_arms_summary

plan_stop_rule_test <- function() {
  list(
    targets::tar_target(stop_params, {
      list(
        static_thresholds  = c(-0.08, -0.10, -0.15, -0.20),
        regime_percentile  = 0.05,
        reentry_periods    = 1L,
        cost_bps           = 5,     # matches R/plan_turn_of_month.R's binary switch convention
        min_train_obs      = 12L
      )
    }),

    # ── Daily strategies: Arms A/B only (no daily regime bridge yet) ───────

    targets::tar_target(stop_arms_avoid_worst, {
      library(historicaldata)
      ret <- fals_avoid_worst_input$strategy_ret
      ret <- ret[!is.na(ret)]
      out <- hd_stop_rule_compare_arms(
        ret,
        regime             = NULL,
        static_thresholds  = stop_params$static_thresholds,
        cost_bps           = stop_params$cost_bps,
        periods_per_year   = 252L,
        reentry_periods    = stop_params$reentry_periods,
        run_regime_arm     = "never"
      )
      out$results$strategy <- "avoid_worst"
      out
    }),

    targets::tar_target(stop_arms_rsc, {
      library(historicaldata)
      ret <- fals_rsc_input$strategy_ret
      ret <- ret[!is.na(ret)]
      out <- hd_stop_rule_compare_arms(
        ret,
        regime             = NULL,
        static_thresholds  = stop_params$static_thresholds,
        cost_bps           = stop_params$cost_bps,
        periods_per_year   = 252L,
        reentry_periods    = stop_params$reentry_periods,
        run_regime_arm     = "never"
      )
      out$results$strategy <- "rsc"
      out
    }),

    # ── Monthly strategies: full A/B/C, reusing regime_classification$regime ─

    targets::tar_target(stop_arms_drif, {
      library(dplyr)
      library(historicaldata)
      series <- fals_drif_input |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::left_join(
          regime_classification |> dplyr::select(ym, regime),
          by = "ym"
        ) |>
        dplyr::filter(!is.na(strategy_ret))
      out <- hd_stop_rule_compare_arms(
        series$strategy_ret,
        regime             = as.character(series$regime),
        static_thresholds  = stop_params$static_thresholds,
        regime_percentile  = stop_params$regime_percentile,
        cost_bps           = stop_params$cost_bps,
        periods_per_year   = 12L,
        reentry_periods    = stop_params$reentry_periods,
        run_regime_arm     = "auto"
      )
      out$results$strategy <- "drif"
      out
    }),

    targets::tar_target(stop_arms_fac_max, {
      library(dplyr)
      library(historicaldata)
      series <- fals_fac_max_input |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::left_join(
          regime_classification |> dplyr::select(ym, regime),
          by = "ym"
        ) |>
        dplyr::filter(!is.na(strategy_ret))
      out <- hd_stop_rule_compare_arms(
        series$strategy_ret,
        regime             = as.character(series$regime),
        static_thresholds  = stop_params$static_thresholds,
        regime_percentile  = stop_params$regime_percentile,
        cost_bps           = stop_params$cost_bps,
        periods_per_year   = 12L,
        reentry_periods    = stop_params$reentry_periods,
        run_regime_arm     = "auto"
      )
      out$results$strategy <- "fac_max"
      out
    }),

    targets::tar_target(stop_arms_ltr, {
      library(dplyr)
      library(historicaldata)
      series <- fals_ltr_input |>
        dplyr::mutate(ym = format(date, "%Y-%m")) |>
        dplyr::left_join(
          regime_classification |> dplyr::select(ym, regime),
          by = "ym"
        ) |>
        dplyr::filter(!is.na(strategy_ret))
      out <- hd_stop_rule_compare_arms(
        series$strategy_ret,
        regime             = as.character(series$regime),
        static_thresholds  = stop_params$static_thresholds,
        regime_percentile  = stop_params$regime_percentile,
        cost_bps           = stop_params$cost_bps,
        periods_per_year   = 12L,
        reentry_periods    = stop_params$reentry_periods,
        run_regime_arm     = "auto"
      )
      out$results$strategy <- "ltr"
      out
    }),

    # ── Combined summary across all five strategies ────────────────────────

    targets::tar_target(stop_arms_summary, {
      library(dplyr)
      dplyr::bind_rows(
        stop_arms_avoid_worst$results,
        stop_arms_drif$results,
        stop_arms_fac_max$results,
        stop_arms_rsc$results,
        stop_arms_ltr$results
      )
    })
  )
}
