# Plan: Strategy Transaction-Cost Convention Registry (#624)
#
# Measurement only. No target here changes any strategy's construction,
# weights, or returns -- this plan documents, as data, the transaction-cost
# assumption each strategy's own code already applies (or, in several rows,
# does not apply).
#
# Origin: `audits/cost-assumptions-2026-06-04.md` flagged `drif` and
# `fac_max` as CRITICAL (0% cost, apples-to-oranges against cost-charging
# rows) and `rsc` as MAJOR (0% cost on regime switches). Issue #425 closed
# those three gaps after the audit was written -- every value below was
# re-verified against current code on 2026-08-04 and several entries in
# this registry therefore DIFFER from the 2026-06-04 audit. The audit
# document is left unmodified as a historical record; this registry is the
# current source of truth.
#
# `strategy` values match the display labels used by the `leaderboard`
# target's own `strategy` column (see R/plan_leaderboard.R, `add_meta()`
# calls) -- the same join key used by `strategy_gross_convention`
# (R/plan_exposure.R), including the "OLMAR-1" naming gap documented there
# (#626, #629: `strategy_names` is missing an `olmar` row).
#
# `cost_per_trade_bps`: the transaction-cost figure the strategy's own code
#   deducts, in basis points, verified against source at the commit this
#   file was authored against. This is NOT always a per-trade, round-trip
#   figure -- `cost_convention` (below) states the actual unit and timing,
#   because the underlying strategies charge cost in three genuinely
#   different ways (per-trade on turnover, per calendar month regardless of
#   turnover, per discrete regime/state switch). Treating the number alone
#   as directly comparable across rows would be exactly the kind of
#   apples-to-oranges error #624 exists to prevent. NA only where no cost
#   figure exists in the strategy's own code (never a substituted default).
# `cost_convention`: short description of how `cost_per_trade_bps` is
#   applied -- unit + timing + which legs it covers.
# `borrow_rate_annual`: annualised borrow-cost fraction charged on short
#   positions, where the strategy's own code applies one. NA where the
#   strategy is long-only (no short leg exists) OR where a short leg exists
#   but no borrow cost is modelled for it (`cost_source_ref` states which).
# `cost_source_ref`: "file:line" of the code this claim was verified
#   against.

plan_cost_convention <- function() {
  list(
    targets::tar_target(strategy_cost_convention, {
      tibble::tibble(
        strategy = c(
          "Factor MAX", "Factor DRIF",
          "Stock MAX", "Stock DRIF", "XGB DRIF",
          "LTR", "OLMAR-1", "TOM", "CMR", "Risk State", "Avoid Worst",
          "Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2",
          "Value (HML)", "Managed Futures", "PSO Optimal"
        ),
        cost_per_trade_bps = c(
          10, 10,
          50, 50, 50,
          10, 10, 5, 20, 5, 0,
          10, 10, 10,
          20, 10, NA_real_
        ),
        cost_convention = c(
          "per-trade bps, round-trip (turnover x2)",
          "per-trade bps, round-trip (turnover x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip both legs (turnover x2 x2)",
          "per-trade bps, round-trip (2x cost_per_trade)",
          "per-trade bps, applied to turnover directly",
          "per-switch bps, round-trip (only on month-end switch days)",
          "per-trade bps, one-way",
          "per-trade bps, one-way (only on regime-switch days)",
          "none -- no cost model implemented in code",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-trade bps, round-trip (2x cost_per_trade, both legs)",
          "per-calendar-month bps, NOT per-trade (charged regardless of turnover)",
          "per-calendar-month bps, NOT per-trade (ETF proxy; comment notes real futures ~20bps)",
          "meta-portfolio -- no separate cost applied at blend level; inherits constituents' already-net returns"
        ),
        borrow_rate_annual = c(
          NA_real_, NA_real_,
          0.03, 0.03, 0.03,
          0.03, NA_real_, NA_real_, NA_real_, NA_real_, NA_real_,
          NA_real_, NA_real_, NA_real_,
          NA_real_, NA_real_, NA_real_
        ),
        cost_source_ref = c(
          "R/plan_factormax.R:27 (cost_per_trade = 0.001), R/plan_factormax.R:134 (cost <- fm_params$cost_per_trade * turnover * 2.0); no short leg -- borrow NA",
          "R/plan_drif.R:30 (cost_per_trade = 0.001), R/plan_drif.R:238 (cost <- drif_params$cost_per_trade * turnover * 2.0); no short leg -- borrow NA",
          "R/plan_stock_backtest.R:392-393 (stk_params: cost_per_trade = 0.005, borrow_rate_annual = 0.03), R/plan_stock_backtest.R:56-98 (portfolio_longshort(): trade_cost = turnover*cost_per_trade*2*2; borrow_cost = borrow_rate_annual/12)",
          "R/plan_stock_backtest.R:392-393 (stk_params, shared with Stock MAX), R/plan_stock_backtest.R:56-98 (portfolio_longshort(), same shared helper)",
          "R/plan_xgb_signal.R:129-130 (passes stk_params$cost_per_trade / borrow_rate_annual into the shared helper), R/plan_stock_backtest.R:56-98 portfolio_longshort()",
          "R/plan_ltr_momentum.R:27-28 (cost_per_trade = 0.0010, borrow_rate_annual = 0.03), scripts/compute_ltr_model.R:146-150 (cost = 2*cost_per_trade; borrow = borrow_cost_annual/12)",
          "R/plan_olmar.R:30 (cost_bps = 10), R/plan_olmar.R:277 (net_ret = gross_ret - (cost_bps/1e4) * turnover); long-only simplex projection -- borrow NA",
          "R/plan_turn_of_month.R:31 (cost_bps = 5L), R/plan_turn_of_month.R:222 (cost_daily = if_else(is_switch, cost_bps/1e4, 0)); SPY/cash only -- borrow NA",
          "R/plan_commodities_mean_reversion.R:51,61,71 (cost_bps = 20 for all 3 lookback variants); 10-long/10-short construction has no borrow cost modelled for the short leg -- verified absent, not a long-only NA",
          "R/plan_risk_state.R:38 (cost_per_trade = 0.0005, comment: '5 bps one-way ... applied only on regime-switch days'), R/plan_risk_state.R:194 (trade_cost = rsc_params$cost_per_trade * exposure_change * 2.0); exposure in [0.10, 1.00], never short -- borrow NA",
          "R/plan_avoid_worst.R:5 (comment: 'NOT a tradeable strategy'); no cost_per_trade/cost_bps field exists anywhere in this file -- zero is a verified absence, not a default",
          "R/plan_mom_prepeak.R:31 (cost_per_trade = 0.0010, comment: 'matches ltr_params'), R/plan_mom_prepeak.R:338 (ret_ls = ret_long - ret_short - 2*cost_per_trade); 100% short leg exists but no borrow cost is modelled -- verified absent, not a long-only NA",
          "R/plan_mom_prepeak.R:31,338 (same shared param + formula as Mom Pre-Peak); same unmodelled-borrow gap on its 100% short leg",
          "R/plan_mom_prepeak.R:31,338 (same shared param + formula as Mom Pre-Peak); same unmodelled-borrow gap on its 100% short leg",
          "R/plan_ev_ebit.R:33 (cost_per_rebalance = 0.002), R/plan_ev_ebit.R:79 (ret_value_hml = RF + HML - cost); pre-computed FF factor-return series, no explicit short-borrow leg -- borrow NA",
          "R/plan_managed_futures.R:48 (cost_monthly = 0.001, comment: '10 bps/month: ETF proxy (real futures ~20bps)'); no borrow cost field found in this file -- borrow NA",
          "R/plan_portfolio_opt.R (no cost_per_trade/cost_bps field found; w <- w/sum(w) blends already cost-net constituent returns; see R/plan_exposure.R source_ref for the same meta-portfolio caveat on gross exposure)"
        )
      )
    })
  )
}
