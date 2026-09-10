# Plan: Strategy Gross-Exposure Convention Registry (#626)
#
# Measurement only. No target here changes any strategy's construction,
# weights, or returns -- this plan documents, as data, the gross exposure
# each strategy's own portfolio-construction code already implements. See
# packages/historicaldata/R/exposure.R (hd_exposure_metrics()) for the
# general-purpose sum(abs(w)) / sum(w) / cash-borrow calculator this
# registry complements.
#
# `strategy` values below match the display labels used by the `leaderboard`
# target's own `strategy` column (see R/plan_leaderboard.R, `add_meta()`
# calls) -- NOT `strategy_names$code_name`. Joins onto `leaderboard` use
# `by = "strategy"`, matching the existing pattern used for
# `strat_corr_augment`, `wfc_all_summary`, and `add_crowding` in
# R/plan_leaderboard.R. (`strategy_names` was missing an `olmar` row when
# this file was authored -- #626/#629 -- but that gap was closed in #747;
# the `by = "strategy"` choice here is retained for consistency with the
# rest of R/plan_leaderboard.R's joins, not because of any remaining gap.)
#
# `gross_convention`: the gross exposure (`sum(abs(w))`) implemented by the
#   strategy's own weight-construction code, verified against source at the
#   commit this file was authored against. NA where the strategy's return is
#   assembled from a pre-computed factor series (no explicit weight vector
#   exists to measure) or is itself a meta-portfolio blend of other rows.
# `is_cap`: TRUE when `gross_convention` is a ceiling the strategy can reach
#   but does not realise on every period (e.g. Managed Futures' 3.0x
#   vol-target cap; the overlays' binary/graduated 1.0x "fully invested"
#   state), FALSE when the value is the strategy's fixed, always-realised
#   construction gross.
# `source_ref`: "file:line" of the code this claim was verified against.

plan_exposure <- function() {
  list(
    targets::tar_target(strategy_gross_convention, {
      tibble::tibble(
        strategy = c(
          "Factor MAX", "Factor DRIF",
          "Stock MAX", "Stock DRIF", "XGB DRIF",
          "LTR", "OLMAR-1", "TOM", "CMR", "Risk State", "Avoid Worst",
          "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
          "Value (HML)", "Managed Futures", "PSO Optimal"
        ),
        gross_convention = c(
          1.0, 1.0,
          2.0, 2.0, 2.0,
          2.0, 1.0, 1.0, 2.0, 1.0, 1.0,
          2.0, 2.0, 2.0,
          NA_real_, 3.0, NA_real_
        ),
        is_cap = c(
          FALSE, FALSE,
          FALSE, FALSE, FALSE,
          FALSE, FALSE, TRUE, FALSE, TRUE, TRUE,
          FALSE, FALSE, FALSE,
          FALSE, TRUE, FALSE
        ),
        source_ref = c(
          "R/plan_factormax.R:139 (gross_ret <- mean(factor_rets$monthly_ret); equal-weight long-only top-N factor selection)",
          "R/plan_drif.R:240 (gross_ret <- mean(selected$actual_ret); equal-weight long-only selection)",
          "R/plan_stock_backtest.R:56-98 (portfolio_longshort() helper: port_ret = long_ret - short_ret - total_cost, each leg equal-weight 1/n summing to 1.0)",
          "R/plan_stock_backtest.R:56-98 (portfolio_longshort(), same shared helper as Stock MAX)",
          "R/plan_xgb_signal.R:100 calls R/plan_stock_backtest.R:56-98 portfolio_longshort() (same shared helper)",
          "scripts/compute_ltr_model.R:135-144 (long_ret/short_ret each equal-weight 1/n_decile; ls_ret_gross = long_ret - short_ret)",
          "packages/historicaldata/R/olmar.R:26-38 (olmar_simplex_project(): sum(w)=1, w>=0); R/plan_olmar.R:29 (leverage tilt within simplex)",
          "R/plan_turn_of_month.R:105 (ret_gross = if_else(in_tom, ret, rf_daily); binary 100%/0% SPY exposure, ceiling 1.0)",
          "packages/historicaldata/R/commodities_mean_reversion.R:185 (weight = if_else(leg==\"long\", 1/n_long, -1/n_short))",
          "R/plan_risk_state.R:195 (gross_ret_strategy = exposure * spy_ret + (1-exposure) * rf_daily; exposure in {0.10, 0.50, 1.00}, ceiling 1.0)",
          "R/plan_avoid_worst.R:451 (100% SPY return series with worst-N days excluded; never levered or short, ceiling 1.0)",
          "R/plan_mom_prepeak.R:224-228 (weight = case_when(decile==n_quantiles ~ 1/n_long, decile==1 ~ -1/n_short))",
          "R/plan_mom_prepeak.R:224-228 (same shared weighting scheme as Mom Pre-Peak)",
          "R/plan_mom_prepeak.R:224-228 (same shared weighting scheme as Mom Pre-Peak)",
          "R/plan_ev_ebit.R:79 (ret_value_hml = RF + HML - cost; a pre-computed Fama-French factor-return series, not an explicit weight vector -- gross exposure not directly measurable; strategy_names$directionality tags it long_only)",
          "R/plan_managed_futures.R:47,100 (max_leverage = 3; vol-targeting scales each position, capped at max_leverage -- 3.0 is a ceiling, rarely fully realised)",
          "R/plan_portfolio_opt.R:68,107,145 (w <- w/sum(w); meta-portfolio blend of Stock MAX/DRIF/Factor MAX/DRIF -- effective gross depends on the realised blend weights, not a fixed convention)"
        )
      )
    })
  )
}
