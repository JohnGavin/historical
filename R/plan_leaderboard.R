# DEPRECATED: This plan assembles a hand-coded leaderboard from individual
# strategy metric targets. The registry-backed replacement is:
#
#   historicaldata::hd_leaderboard_from_registry()
#
# Once the registry covers all strategies, this target can be retired.
# Monitor parity via the `qa_legacy_leaderboard_sentinel` target in
# R/plan_artefact_registry.R.
#
# Model leaderboard: collects metrics from all strategies into one table
#
# Transposed format: metrics as rows, strategies as columns
# (fewer strategies than metrics, at least for now)
#
# ── Unit convention (#637) ─────────────────────────────────────────────────
# `cagr`, `vol`, and `max_dd` are stored as DECIMAL FRACTIONS throughout this
# target (e.g. -0.21 == -21% drawdown), matching the convention documented in
# R/plan_commodities_mean_reversion.R:210-214 and used natively by
# R/plan_factormax.R, R/plan_drif.R, R/plan_stock_backtest.R, and
# R/plan_portfolio_opt.R. Several source metrics targets (ltr_metrics,
# olmar_metrics, tom_metrics, rsc_metrics, aw_metrics, mom_prepeak_metrics /
# mom_postpeak_metrics / mom_combined_metrics, mf_metrics, ev_metrics) store
# these columns as PERCENT (x * 100) natively -- their `.norm_*` helpers below
# divide by 100 at the point where the source convention is known, so every
# row entering `all_metrics` is already a fraction. `sharpe` is scale-free and
# is never converted. Any NEW strategy wired into this target MUST follow the
# same rule: check the source metrics target's own convention (grep for
# `* 100` in its calc/metrics function) and convert to fraction in its own
# `.norm_*` helper -- never infer the unit from the output magnitude
# (magnitude heuristics misclassify genuine >150% vol or <1% vol strategies).
# Display-time formatting (x 100, "%") belongs to the consumer
# (docs/leaderboard.qmd, DT::datatable(), plot labels), not this target.
# See also: R/plan_qa_gates.R `qa_leaderboard_metric_ranges` -- the range gate
# that asserts every row here is within a plausible fractional range.
#
# ── ann_rf (#677 slice 4) ───────────────────────────────────────────────────
# `ann_rf` is the annualised risk-free rate each source metrics target
# actually deducted when computing `sharpe`. It follows the EXACT SAME
# fraction/percent convention as `cagr` in its own source target -- every
# `.norm_*` helper below divides `ann_rf` by 100 in lockstep with `cagr`, and
# the direct add_meta() targets (fm_metrics, drif_metrics, stk_max_metrics,
# stk_drif_metrics, xgb_drif_metrics, port_metrics) already
# carry it as a fraction, same as their `cagr`. It is REQUIRED (never NA) --
# see R/plan_qa_gates.R `check_leaderboard_sharpe_coherence()` (S17), which
# asserts `sharpe == (cagr - ann_rf) / vol` for every leaderboard row.
#
# ── Period vocabulary (#643) ────────────────────────────────────────────────
# The `period` column MUST only contain values from `PERIOD_LABELS_ALLOWED`
# (R/plan_partitions.R). Two source targets (mf_metrics, ev_metrics) used
# "Full" for the full-sample row where every other strategy uses "Full
# Period" -- their `.norm_mf()` / `.norm_value()` helpers below rename it at
# this boundary, same pattern as the unit conversion above. Their "OOS" label
# is intentionally NOT renamed to "Testing" -- see the `.norm_mf()` comment
# and R/plan_partitions.R for why the two windows differ. See also:
# R/plan_qa_gates.R `qa_leaderboard_period_vocab` -- the vocabulary gate that
# asserts every row here uses an allowed label.

plan_leaderboard <- function() {
  list(
    # Explicit deps — targets must be named as function args
    # strat_corr_augment from plan_strategy_correlation.R provides:
    #   correlation_max, redundant, incremental_sharpe (joined by strategy_label)
    targets::tar_target(leaderboard, {
      library(dplyr)

      add_meta <- function(m, name, level, signal, url) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |> mutate(strategy = name, level = level, signal = signal, definition = url)
      }

      # ── Schema-normalisation helpers for strategies with non-standard schemas ──
      # Each helper returns a tibble with at minimum: period, months, cagr, vol,
      # sharpe, max_dd. Extra columns are preserved so the final bind_rows()
      # fills NA for columns absent in some strategies.
      # Canonical unit for cagr/vol/max_dd is FRACTION -- see the module-level
      # comment above. Each helper below converts from its source's native
      # unit (fraction or percent) at this boundary.

      # ltr_metrics carries its own canonical `sharpe` (#677: (ann_ret -
      # ann_rf) / ann_vol, via R/utils_metrics.R::sharpe_ratio_rf()) AS
      # WELL AS `hac_sharpe` (a separate, HAC-adjusted statistic) -- no
      # longer renamed/substituted, see plan_ltr_momentum.R:compute_ltr_metrics().
      # Source: R/plan_ltr_momentum.R:167-169 (compute_ltr_metrics) stores
      # cagr/vol/max_dd as PERCENT (round(x * 100, 1)) -- convert to fraction.
      .norm_ltr <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
                 ann_rf = ann_rf / 100)
      }

      # olmar_metrics has `days` instead of `months`; daily ann_factor.
      # Source: R/plan_olmar.R:138-141 (calc) stores cagr/vol/max_dd as
      # PERCENT (round(x * 100, 2)) -- convert to fraction.
      .norm_olmar <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          rename(months = days) |>
          mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
                 ann_rf = ann_rf / 100)
      }

      # tom_metrics uses cagr_tom, vol_tom, sharpe_tom, max_dd_tom.
      # Drop benchmark columns; keep TOM strategy row only.
      # Source: R/plan_turn_of_month.R:162-165 stores cagr_tom/vol_tom/max_dd_tom
      # as PERCENT (round(x * 100, 2); confirmed by the target's own comment at
      # line 317: "tom_metrics stores cagr/vol/max_dd in percentage units (x 100)")
      # -- convert to fraction.
      .norm_tom <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |> transmute(
          period = period,
          months = n_days,
          cagr   = cagr_tom / 100,
          vol    = vol_tom / 100,
          sharpe = sharpe_tom,
          ann_rf = ann_rf_tom / 100,
          max_dd = max_dd_tom / 100
        )
      }

      # cmr_summary has lookback (1m/3m/6m) instead of period; no period column.
      # Pick the best-Sharpe lookback for the leaderboard row.
      # We create one synthetic "Full Period" row = the best lookback.
      # Source: R/plan_commodities_mean_reversion.R:210-221 already stores
      # cagr/vol/max_dd as FRACTION (documented convention, #336) -- no
      # conversion needed here.
      .norm_cmr <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        best <- m |> filter(!is.na(sharpe)) |> arrange(desc(sharpe)) |> slice(1)
        if (nrow(best) == 0L) return(NULL)
        best |> transmute(
          period = "Full Period",
          months = n_months,
          cagr   = cagr,
          vol    = vol,
          sharpe = sharpe,
          ann_rf = ann_rf,
          max_dd = max_dd,
          cmr_lookback = lookback  # preserve for inspection
        )
      }

      # rsc_metrics contains multiple internal strategy variants (SPY_overlay,
      # DRIF_overlay, etc.). Pick only the SPY_overlay rows which represent the
      # strategy's own performance. Those rows now carry a canonical `sharpe`
      # (#677: (ann_ret - ann_rf) / ann_vol, via
      # R/utils_metrics.R::sharpe_ratio_rf(), rf = rsc_portfolio$rf_daily) AS
      # WELL AS `hac_sharpe` -- no longer renamed/substituted, see
      # plan_risk_state.R:calc_metrics().
      # Source: R/plan_risk_state.R:270-273 stores cagr/vol/max_dd as PERCENT
      # (round(x * 100, 2)) -- convert to fraction.
      .norm_rsc <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          filter(strategy == "SPY_overlay") |>
          select(-strategy) |>
          mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
                 ann_rf = ann_rf / 100)
      }

      # mom_prepeak_metrics / siblings have no period column (one row per
      # strategy); column n_months not months; no period. Synthesise
      # "Full Period" as the single row.
      # Source: packages/historicaldata/R/utils_mom_prepeak_metrics.R:111-113
      # (.mom_prepeak_compute_metrics) stores cagr/vol/max_dd as PERCENT
      # (round(x * 100, 1)) -- convert to fraction.
      .norm_mom_sibling <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          select(-any_of("strategy")) |>  # strategy is set by add_meta name=
          transmute(
            period = "Full Period",
            months = n_months,
            cagr   = cagr / 100,
            vol    = vol / 100,
            sharpe = sharpe,
            ann_rf = ann_rf / 100,
            max_dd = max_dd / 100
          )
      }

      # aw_metrics has scenario × period; keep the "Remove 10 Worst" rows
      # (the protection scenario) and drop the extra scenario column.
      # Source: R/plan_avoid_worst.R:440-444 (metrics_for) stores
      # cagr/vol/max_dd as PERCENT (round(x * 100, 1)) -- convert to fraction.
      .norm_aw <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          filter(scenario == "Remove 10 Worst") |>
          select(-scenario) |>
          rename(months = n_days) |>
          mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
                 ann_rf = ann_rf / 100)
      }

      # mf_metrics has multiple internal strategies (Long-Only, Long-Short, EW benchmark)
      # and columns: strategy, period, n_months, cagr, vol, sharpe, max_dd, calmar.
      # Keep only the canonical MOP 2012 long-short strategy.
      # Source: R/plan_managed_futures.R:187-192 (calc_metrics) stores
      # cagr/vol/max_dd as PERCENT (round(x * 100, 2)) -- convert to fraction.
      # Period-label normalisation (#643): mf_metrics' own vocabulary is
      # "Full"/"Training"/"OOS" -- everywhere else in the leaderboard uses
      # "Full Period" for the same full-sample concept, so "Full" is renamed
      # here at the boundary (same rule as the unit conversion above -- fix
      # at the point where the source convention is known). "OOS" is NOT
      # renamed to "Testing": mf_metrics' OOS window is `dates >= oos_start`
      # (2010-01-01, unbounded), a different span from the canonical Testing
      # partition (2020-01-01..2022-12-31, R/plan_partitions.R) -- see the
      # PERIOD_LABELS_ALLOWED comment in R/plan_partitions.R for the full
      # rationale. Renaming it would misrepresent the wider sample as the
      # shared cross-strategy test partition.
      .norm_mf <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          filter(strategy == "Long-Short TS-Mom (MOP 2012, vol-targeted)") |>
          select(-strategy, -calmar) |>
          rename(months = n_months) |>
          mutate(
            period = ifelse(period == "Full", "Full Period", period),
            cagr   = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
            ann_rf = ann_rf / 100
          )
      }

      # ev_metrics has multiple internal strategies (Pure Value, Value+Quality, Benchmark)
      # and columns: strategy, period, n_months, cagr, vol, sharpe, max_dd, calmar.
      # Keep only the pure HML strategy that represents "Value (HML)".
      # Source: R/plan_ev_ebit.R:109-114 (calc_metrics) stores cagr/vol/max_dd
      # as PERCENT (x * 100, no explicit round until the tibble build) --
      # convert to fraction.
      # Period-label normalisation (#643): see the matching comment in
      # .norm_mf() above -- "Full" -> "Full Period" is a safe rename, "OOS"
      # is intentionally left as-is (ev_metrics' OOS window is `dates >=
      # 2010-01-01`, unbounded, not the canonical bounded Testing partition).
      .norm_value <- function(m) {
        if (is.null(m) || nrow(m) == 0) return(NULL)
        m |>
          filter(strategy == "Pure Value (100% HML, EV/EBIT proxy)") |>
          select(-strategy, -calmar) |>
          rename(months = n_months) |>
          mutate(
            period = ifelse(period == "Full", "Full Period", period),
            cagr   = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
            ann_rf = ann_rf / 100
          )
      }

      all_metrics <- bind_rows(
        add_meta(fm_metrics, "Factor MAX", "Factor", "Max daily return",
                 "factor-max.html"),
        add_meta(drif_metrics, "Factor DRIF", "Factor", "Elastic net (42 feat)",
                 "drif.html"),
        add_meta(stk_max_metrics, "Stock MAX", "Stock", "Max daily return",
                 "stock-backtest.html#stock-max"),
        add_meta(stk_drif_metrics, "Stock DRIF", "Stock", "Elastic net (42 feat)",
                 "stock-backtest.html#stock-drif"),
        add_meta(xgb_drif_metrics, "XGB DRIF", "Stock", "XGBoost monotonic (42 feat)",
                 "stock-backtest.html#stock-drif"),
        # ── Added in #345: wire missing strategies ──
        add_meta(.norm_ltr(ltr_metrics), "LTR", "Equity", "Cross-sectional momentum",
                 "leaderboard.html"),
        add_meta(.norm_olmar(olmar_metrics), "OLMAR-1", "Equity",
                 "Online mean-reversion (Li & Hoi 2012)",
                 "leaderboard.html"),
        add_meta(.norm_tom(tom_metrics), "TOM", "Overlay",
                 "Turn-of-the-month calendar effect",
                 "turn-of-month.html"),
        add_meta(.norm_cmr(cmr_summary), "CMR", "Commodities",
                 "Commodities mean reversion (best lookback)",
                 "commodities-mean-reversion.html"),
        add_meta(.norm_rsc(rsc_metrics), "Risk State", "Overlay",
                 "VIX regime overlay on SPY",
                 "leaderboard.html"),
        add_meta(.norm_aw(aw_metrics), "Avoid Worst", "Overlay",
                 "VIX protection: remove 10 worst days",
                 "avoid-worst-days.html"),
        add_meta(.norm_mom_sibling(mom_prepeak_metrics), "Mom Pre-Peak", "Equity",
                 "Pre-peak 12-2 momentum (Büsing 2022)",
                 "momentum-prepeak.html"),
        add_meta(.norm_mom_sibling(mom_postpeak_metrics), "Mom Post-Peak", "Equity",
                 "Post-peak 12-2 momentum (Büsing 2022)",
                 "momentum-prepeak.html"),
        add_meta(.norm_mom_sibling(mom_combined_metrics), "Mom 12-2", "Equity",
                 "Standard 12-2 momentum (Büsing baseline)",
                 "momentum-prepeak.html"),
        # ── Added in #489 Cluster C: wire missing strategies (S7 coverage) ──
        add_meta(.norm_value(ev_metrics), "Value (HML)", "Factor",
                 "EV/EBIT value sleeve (HML+RMW proxy, v0)",
                 "R/plan_ev_ebit.R"),
        add_meta(.norm_mf(mf_metrics), "Managed Futures", "Multi-Asset",
                 "Cross-asset TS-momentum (MOP 2012, ETF proxies, v0)",
                 "R/plan_managed_futures.R")
      )

      # Add portfolio optimal
      if (!is.null(port_metrics) && nrow(port_metrics) > 0) {
        port_row <- port_metrics |>
          transmute(
            period = period, months = months,
            cagr = opt_cagr, vol = opt_vol, sharpe = opt_sharpe, ann_rf = ann_rf,
            max_dd = opt_maxdd,
            strategy = "PSO Optimal", level = "Combined",
            signal = "Weighted portfolio",
            definition = "stock-backtest.html#comparison"
          )
        all_metrics <- bind_rows(all_metrics, port_row)
      }

      # ── Seal the Validation partition (#648) ──────────────────────────────
      # Several source metrics targets (fm_metrics, drif_metrics,
      # stk_max_metrics, stk_drif_metrics, xgb_drif_metrics, ltr_metrics,
      # port_metrics) compute a "Validation" period row internally, in their
      # OWN plan file, for their own reasons (e.g. R/plan_factormax.R:202
      # `calc_metrics(val_data, "Validation")`). Those rows flow into
      # `all_metrics` above completely unfiltered via `add_meta()`/`bind_rows()`
      # and `port_row` -- this is a wider instance of the same
      # `backtest-partitions.md` seal-breach #648 is about, and those source
      # targets are intentionally NOT modified here (out of #648's scope --
      # flagged as a follow-up; several also surface Validation values
      # directly in vignette prose, e.g. docs/stock-backtest.qmd, which is a
      # separate display-side leak this issue does not touch).
      #
      # This target (`leaderboard`) must not RE-EXPOSE those rows regardless
      # of which upstream source produced them: drop every row labelled
      # "Validation" the moment the base rows are assembled, before any of
      # the cost/join/augmentation logic below runs. Without this, removing
      # the (now redundant) `Validation` slice from `slice_portfolio()` below
      # would only stop the COST columns (net_cagr, cum_pnl, cvar_95) from
      # being computed for Validation -- the base cagr/vol/sharpe/max_dd rows
      # would still leak through from fm_metrics et al.
      all_metrics <- all_metrics |> filter(period != "Validation")

      # ── Cost metrics (net_cagr, cum_pnl, cvar_95) ─────────────────
      # Compute per strategy per period from raw portfolio returns.
      # cost: 0.20% round-trip per month (full turnover assumed).
      COST_PER_MONTH <- 0.002

      calc_cost_metrics <- function(ret) {
        # ret: numeric vector of monthly returns
        ret <- ret[!is.na(ret)]
        n <- length(ret)
        if (n == 0L) {
          return(tibble(net_cagr = NA_real_, cum_pnl = NA_real_, cvar_95 = NA_real_))
        }
        net_ret <- ret * (1 - COST_PER_MONTH)
        net_cagr <- prod(1 + net_ret)^(12 / n) - 1
        cum_pnl_net <- prod(1 + net_ret) - 1  # net of costs, not gross
        q05      <- quantile(ret, 0.05)
        cvar_95  <- mean(ret[ret <= q05])
        # Credibility flag: >20% CAGR or >50x cum P&L is suspect
        credible <- abs(net_cagr) < 0.20 & abs(cum_pnl_net) < 50
        tibble(net_cagr = net_cagr, cum_pnl = cum_pnl_net, cvar_95 = cvar_95,
               credible = credible)
      }

      # Each portfolio target and its return column (as string) and period slicing params
      #
      # NOTE (#648): this function previously also sliced a `Validation`
      # window (`port_df$date >= params$val_start`) and computed cost metrics
      # for it on every `tar_make()` -- an automatic-computation violation of
      # `backtest-partitions.md` ("Validation metrics are NOT computed
      # automatically"). That slice is removed: the automatic path now only
      # ever produces Training / Testing / Holdout / Full Period cost rows. A
      # one-shot Validation evaluation, when authorised, belongs in
      # scripts/evaluate_validation.R (never invoked by tar_make()), not here.
      #
      # NOTE (#660): `Holdout` is added below (2024-01-01..2026-04-30,
      # R/plan_partitions.R `bt_partitions`) -- it is computed automatically
      # by design (observed, not sealed; see backtest-partitions.md's Holdout
      # subsection), unlike Validation above.
      #
      # KNOWN GAP (#660, flagged not fixed -- out of this change's scope):
      # `calc_cost_metrics()` never returns NULL (an empty window yields a
      # row of NAs, not zero rows), so `cost_rows` below always gets a
      # `period == "Holdout"` row per strategy. But the join two blocks down
      # is `all_metrics |> left_join(cost_rows, by = c("strategy", "period"))`
      # -- LEFT-driven by `all_metrics`, whose base rows come from the source
      # metrics targets (stk_max_metrics, stk_drif_metrics, xgb_drif_metrics,
      # fm_metrics, drif_metrics, port_metrics) via `calc_backtest_metrics()`
      # / `calc_metrics()` / `calc_port_metrics()`. None of those functions
      # compute a "Holdout" period today -- only Training/Testing/Validation
      # (filtered)/Full Period. A right-side-only period value is silently
      # dropped by `left_join()`, so the Holdout rows built here currently do
      # NOT surface in the assembled `leaderboard` target or on
      # docs/leaderboard.qmd's "By Partition" table. Making Holdout actually
      # visible requires adding a Holdout slice to those source targets too
      # -- a separate, wider change than this one; see the #660 PR report.
      slice_portfolio <- function(port_df, ret_col_name, params) {
        ret <- list(
          Training     = port_df[port_df$date <= params$is_end, ][[ret_col_name]],
          Testing      = port_df[port_df$date >= params$test_start & port_df$date <= params$test_end, ][[ret_col_name]],
          Holdout      = port_df[port_df$date >= params$holdout_start & port_df$date <= params$holdout_end, ][[ret_col_name]],
          `Full Period` = port_df[[ret_col_name]]
        )
        bind_rows(lapply(names(ret), function(p) {
          calc_cost_metrics(ret[[p]]) |> mutate(period = p)
        }))
      }

      cost_rows <- bind_rows(
        slice_portfolio(fm_portfolio,        "portfolio_ret", fm_params)   |> mutate(strategy = "Factor MAX"),
        slice_portfolio(drif_portfolio,      "portfolio_ret", drif_params) |> mutate(strategy = "Factor DRIF"),
        slice_portfolio(stk_max_portfolio,   "port_ret",      stk_params)  |> mutate(strategy = "Stock MAX"),
        slice_portfolio(stk_drif_portfolio,  "port_ret",      stk_params)  |> mutate(strategy = "Stock DRIF"),
        slice_portfolio(xgb_drif_portfolio,  "port_ret",      stk_params)  |> mutate(strategy = "XGB DRIF")
      )

      # PSO Optimal: derive from port_returns (opt weights applied)
      if (!is.null(port_metrics) && nrow(port_metrics) > 0 &&
          !is.null(port_optimal_weights)) {
        w <- port_optimal_weights
        strat_cols <- names(w)
        # port_returns has columns: ym, stk_max, stk_drif, fac_max, fac_drif, rf_ret, date
        opt_returns_df <- port_returns |>
          filter(if_all(all_of(strat_cols), ~ !is.na(.x))) |>
          mutate(opt_ret = as.numeric(as.matrix(pick(all_of(strat_cols))) %*% w))

        pso_cost <- slice_portfolio(
          opt_returns_df |> rename(portfolio_ret = opt_ret),
          "portfolio_ret",
          stk_params
        ) |> mutate(strategy = "PSO Optimal")
        cost_rows <- bind_rows(cost_rows, pso_cost)
      }

      # Join cost metrics onto all_metrics
      all_metrics <- all_metrics |>
        left_join(cost_rows, by = c("strategy", "period")) |>
        # Mark strategies that draw on stk_universe (survivorship-biased); see #150
        mutate(survivorship_biased = strategy %in% c("Stock MAX", "Stock DRIF", "XGB DRIF"))

      # Join bootstrap CI columns (Sharpe CI, crosses-zero flag)
      if (!is.null(boot_ci_summary) && nrow(boot_ci_summary) > 0) {
        # Map internal names to strategy labels
        boot_join <- boot_ci_summary |>
          transmute(
            strategy = strategy_label,
            sharpe_ci_lo = round(sharpe_lo, 2),
            sharpe_ci_hi = round(sharpe_hi, 2),
            ci_crosses_zero = ci_crosses_zero
          )
        all_metrics <- all_metrics |>
          left_join(boot_join, by = "strategy")
      }

      # ── Correlation augmentation (Pillar 7, #268) ────────────────────────
      # Join correlation_max, redundant, incremental_sharpe from
      # plan_strategy_correlation.R. strat_corr_augment is keyed by strategy_label
      # which matches the display names used in all_metrics$strategy.
      # Only "Full Period" rows get meaningful values; other periods receive NA
      # (incremental Sharpe is a portfolio-level concept, not a sub-period one).
      if (!is.null(strat_corr_augment) && nrow(strat_corr_augment) > 0) {
        corr_join <- strat_corr_augment |>
          select(strategy = strategy_label, correlation_max, redundant, incremental_sharpe)
        all_metrics <- all_metrics |>
          left_join(corr_join, by = "strategy") |>
          # Zero out incremental_sharpe for sub-period rows (it's a Full-Period stat)
          mutate(
            correlation_max    = ifelse(period == "Full Period", correlation_max, NA_real_),
            redundant          = ifelse(period == "Full Period", redundant,       NA),
            incremental_sharpe = ifelse(period == "Full Period", incremental_sharpe, NA_real_)
          )
      }

      # ── Deflated Sharpe (full-sample; K_trials = Vertox K_eff_strat, not raw M) — #160 ──
      # DSR is a full-sample statistic, so it broadcasts to all period rows; the
      # vignette surfaces it only in the Full-Period view.
      if (!is.null(strat_deflated_sharpe) && nrow(strat_deflated_sharpe) > 0) {
        all_metrics <- all_metrics |>
          left_join(
            strat_deflated_sharpe |>
              select(strategy, deflated_sharpe, dsr_pvalue, k_eff_strat),
            by = "strategy"
          )
      }

      # ── Walk-Forward Correlation columns (#318) ────────────────────────────
      # wf_corr:    Pearson IS↔OOS correlation across the full parameter grid.
      # wfc_verdict: 2×2 classification from hd_wf_correlation() —
      #   "structural_edge", "consistently_loss_making", "spurious_luck", "noise".
      #
      # Strategies without a tunable parameter grid (OLMAR, TOM, Stock MAX,
      # Stock DRIF, XGB DRIF, PSO Optimal) receive NA for both columns.
      # XGB DRIF operates at the stock level (stk_drif_features) — no
      # factor-rotation grid exists; factor-level XGB is a follow-up to #318.
      #
      # wfc_all_summary is keyed by strategy (display label).  Only the
      # "Full Period" leaderboard row gets meaningful values; sub-period rows
      # receive NA (WFC is a full-history property, not a sub-period one).
      if (!is.null(wfc_all_summary) && nrow(wfc_all_summary) > 0) {
        wfc_join <- wfc_all_summary |>
          select(strategy, wf_corr = wfc_pearson, wfc_verdict = classification)
        all_metrics <- all_metrics |>
          left_join(wfc_join, by = "strategy") |>
          mutate(
            wf_corr    = ifelse(period == "Full Period", wf_corr,    NA_real_),
            wfc_verdict = ifelse(period == "Full Period", wfc_verdict, NA_character_)
          )
      }

      # ── SSR + top5pct columns (#400) ─────────────────────────────────────────
      # Sharpe Stability Ratio (SSR) and top-5% share for each strategy.
      # Window w = 36 months (3 years) for all monthly strategies; ann_factor = 12.
      # Strategies without an accessible return vector receive NA for both columns.
      # SSR and top5pct_share are full-sample statistics: broadcast to all period
      # rows (the vignette shows them only in the Full-Period view).
      {
        # Build a named list: strategy label -> full-period return vector
        # Each return vector must be numeric, already NA-stripped by the helpers.
        ssr_map <- list()

        safe_ssr <- function(r) {
          r <- r[!is.na(r)]
          if (length(r) < 38L) return(NA_real_)
          tryCatch(
            historicaldata::hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)$ssr,
            error = function(e) NA_real_
          )
        }

        safe_top5 <- function(r) {
          r <- r[!is.na(r)]
          if (length(r) == 0L) return(NA_real_)
          tryCatch(
            historicaldata::hd_top5pct_share(r)$top_share,
            error = function(e) NA_real_
          )
        }

        # Factor MAX and Factor DRIF: monthly portfolio_ret
        if (!is.null(fm_portfolio) && "portfolio_ret" %in% names(fm_portfolio)) {
          r <- fm_portfolio$portfolio_ret
          ssr_map[["Factor MAX"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }
        if (!is.null(drif_portfolio) && "portfolio_ret" %in% names(drif_portfolio)) {
          r <- drif_portfolio$portfolio_ret
          ssr_map[["Factor DRIF"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }

        # Stock MAX, Stock DRIF, XGB DRIF: monthly port_ret
        if (!is.null(stk_max_portfolio) && "port_ret" %in% names(stk_max_portfolio)) {
          r <- stk_max_portfolio$port_ret
          ssr_map[["Stock MAX"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }
        if (!is.null(stk_drif_portfolio) && "port_ret" %in% names(stk_drif_portfolio)) {
          r <- stk_drif_portfolio$port_ret
          ssr_map[["Stock DRIF"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }
        if (!is.null(xgb_drif_portfolio) && "port_ret" %in% names(xgb_drif_portfolio)) {
          r <- xgb_drif_portfolio$port_ret
          ssr_map[["XGB DRIF"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }

        # Mom Pre-Peak, Post-Peak, Combined: monthly ret_ls
        if (!is.null(mom_prepeak_returns) && "ret_ls" %in% names(mom_prepeak_returns)) {
          r <- mom_prepeak_returns$ret_ls
          ssr_map[["Mom Pre-Peak"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }
        if (!is.null(mom_postpeak_returns) && "ret_ls" %in% names(mom_postpeak_returns)) {
          r <- mom_postpeak_returns$ret_ls
          ssr_map[["Mom Post-Peak"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }
        if (!is.null(mom_combined_returns) && "ret_ls" %in% names(mom_combined_returns)) {
          r <- mom_combined_returns$ret_ls
          ssr_map[["Mom 12-2"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }

        # LTR: monthly port_ret
        if (!is.null(ltr_portfolio) && "port_ret" %in% names(ltr_portfolio)) {
          r <- ltr_portfolio$port_ret
          ssr_map[["LTR"]] <- list(ssr = safe_ssr(r), top5 = safe_top5(r))
        }

        # Build lookup tibble for joining
        if (length(ssr_map) > 0L) {
          ssr_tbl <- dplyr::bind_rows(lapply(names(ssr_map), function(nm) {
            tibble::tibble(
              strategy     = nm,
              ssr          = ssr_map[[nm]]$ssr,
              top5pct_share = ssr_map[[nm]]$top5
            )
          }))
          all_metrics <- all_metrics |>
            dplyr::left_join(ssr_tbl, by = "strategy")
        } else {
          all_metrics <- all_metrics |>
            dplyr::mutate(ssr = NA_real_, top5pct_share = NA_real_)
        }
      }

      # ── ADD (Anomaly-Driven Demand) crowding columns (#430) ──────────────────
      # add_corr: Pearson correlation between strategy monthly return and
      #   SPY's first-6-trading-day return in the same month.
      #   High positive correlation = returns concentrated in month-start
      #   rebalancing window → ADD crowding signature.
      # add_flag: TRUE if add_corr > add_params$crowd_corr_threshold (0.40).
      # add_beta: OLS slope; one-unit increase in SPY month-start return maps
      #   to add_beta units change in strategy return.
      # Only "Full Period" rows carry meaningful values; sub-period rows receive NA.
      # Reference: Kjær & Posselt (2025); wiki: anomaly-driven-demand.md
      if (!is.null(add_crowding) && nrow(add_crowding) > 0) {
        add_join <- add_crowding |>
          dplyr::select("strategy", "add_corr", "add_beta", "add_flag")
        all_metrics <- all_metrics |>
          dplyr::left_join(add_join, by = "strategy") |>
          dplyr::mutate(
            add_corr = ifelse(period == "Full Period", add_corr, NA_real_),
            add_beta = ifelse(period == "Full Period", add_beta, NA_real_),
            add_flag = ifelse(period == "Full Period", add_flag, NA)
          )
      }

      # ── Pillar 8: risk-architecture columns (#269, #331) ─────────────────────
      # Join avg_dd_days, max_dd_days, loss_clustered, max_cons_losses from
      # fals_results_db. fals_results_db uses strategy_id (internal code); map
      # to leaderboard labels.
      # Only "Full Period" rows carry meaningful full-history risk values.
      if (!is.null(fals_results_db) && nrow(fals_results_db) > 0) {
        fals_id_to_label <- c(
          fac_max     = "Factor MAX",
          drif        = "Factor DRIF",
          # ── #345: added to leaderboard ──
          avoid_worst = "Avoid Worst",
          rsc         = "Risk State",
          ltr         = "LTR",
          tom         = "TOM"
          # cmr, olmar, mom_prepeak siblings: not yet in fals_results_db
        )
        pillar8_join <- fals_results_db |>
          filter(strategy_id %in% names(fals_id_to_label)) |>
          mutate(strategy = fals_id_to_label[strategy_id]) |>
          select(strategy,
                 avg_dd_days      = avg_dd_duration_days,
                 max_dd_days      = max_dd_duration_days,
                 loss_clustered   = loss_clustered,
                 max_cons_losses  = max_consecutive_losses)
        all_metrics <- all_metrics |>
          left_join(pillar8_join, by = "strategy") |>
          mutate(
            avg_dd_days     = ifelse(period == "Full Period", avg_dd_days,     NA_real_),
            max_dd_days     = ifelse(period == "Full Period", max_dd_days,     NA_real_),
            loss_clustered  = ifelse(period == "Full Period", loss_clustered,  NA),
            max_cons_losses = ifelse(period == "Full Period", max_cons_losses, NA_integer_)
          )
      }

      # ── Gross-exposure convention (#626, measurement only) ────────────────
      # Join gross_convention, is_cap, source_ref from R/plan_exposure.R.
      # strategy_gross_convention is keyed by the same display labels as
      # all_metrics$strategy. Unlike the Full-Period-only joins above, this
      # is a construction-time property of the strategy, not a period
      # statistic, so it broadcasts to every period row unchanged.
      if (!is.null(strategy_gross_convention) && nrow(strategy_gross_convention) > 0) {
        all_metrics <- all_metrics |>
          left_join(strategy_gross_convention, by = "strategy")
      }

      # ── Transaction-cost convention (#624, measurement only) ──────────────
      # Join cost_per_trade_bps, cost_convention, borrow_rate_annual,
      # cost_source_ref from R/plan_cost_convention.R. Same join key and same
      # broadcast-to-every-period-row semantics as strategy_gross_convention
      # above -- this is a construction-time property of the strategy, not a
      # period statistic.
      if (!is.null(strategy_cost_convention) && nrow(strategy_cost_convention) > 0) {
        all_metrics <- all_metrics |>
          left_join(strategy_cost_convention, by = "strategy")
      }

      all_metrics
    }),

    # ── Correlation matrix of monthly returns across strategies ───────
    targets::tar_target(strategy_correlation, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")

      ret_mat <- port_returns |>
        select(all_of(strat_cols)) |>
        filter(if_all(everything(), ~ !is.na(.x)))

      cor_mat <- cor(ret_mat)

      # Return as a tidy tibble: strategy names as both row label and columns
      as.data.frame(cor_mat) |>
        tibble::rownames_to_column("strategy") |>
        as_tibble()
    }),

    # ── Vertox K_eff_strat: correlation-aware effective strategy count ────────
    # Uses strat_corr_matrix from plan_strategy_correlation (available as dep).
    # seed = 160 for reproducibility (issue #160).
    targets::tar_target(strat_keff_vertox, {
      historicaldata::hd_strat_keff_vertox(strat_corr_matrix, n_sim = 20000L, seed = 160L)
    }),

    # ── Deflated Sharpe per strategy (#160) ───────────────────────────────────
    # K_trials = K_eff_strat (Vertox correlation-aware count, rounded to integer),
    # NOT raw M=4: correlated strategies → raw count over-penalises.
    # ann_factor = 12 (monthly returns in port_returns).
    # col_map keys match port_returns column names; values match leaderboard labels.
    targets::tar_target(strat_deflated_sharpe, {
      library(dplyr)
      k_eff <- max(1L, round(strat_keff_vertox))
      col_map <- c(stk_max = "Stock MAX", stk_drif = "Stock DRIF",
                   fac_max = "Factor MAX", fac_drif = "Factor DRIF")
      bind_rows(lapply(names(col_map), function(col) {
        r <- port_returns[[col]]
        r <- r[!is.na(r)]
        d <- historicaldata::hd_deflated_sharpe(r, K_trials = k_eff, ann_factor = 12L)
        tibble::tibble(
          strategy        = unname(col_map[[col]]),
          naive_sharpe    = d$naive_sharpe,
          deflated_sharpe = d$dsr,
          dsr_pvalue      = d$dsr_pvalue,
          dsr_haircut_pct = d$haircut_pct,
          k_eff_strat     = strat_keff_vertox,
          k_raw           = nrow(strat_corr_matrix)
        )
      }))
    })
  )
}
