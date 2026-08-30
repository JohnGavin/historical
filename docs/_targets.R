# Unified vignette targets: pre-compute all data and plots
#
# Covers: examples.qmd (66 targets) + macro-defense-rotation.qmd (15 targets)
# + QA validation (1 target). Total: 82 targets in one pipeline.
#
# Usage:
#   cd docs/
#   Rscript -e 'targets::tar_make()'

library(targets)

tar_option_set(
  packages = c("dplyr", "duckplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli", "RcppRoll"),
  # `imports` (#753): tell `targets` to treat every object in the
  # historicaldata namespace as trackable, the same way it already tracks
  # functions defined via the source() calls below. Do NOT add
  # "historicaldata" to `packages` above -- that makes targets call
  # library(historicaldata) in every target's subprocess, which fails
  # because the package is only load_all()'d, never installed (see the
  # comment on pkgload::load_all() just below). `imports` needs no such
  # install: it inspects the namespace already attached by load_all() in
  # THIS session, at pipeline-parse time, and hashes every function body it
  # finds there.
  #
  # Empirically confirmed (scratch pipeline, 2026-08-25, mirroring #753's
  # exact defect): with `imports = "historicaldata"` set, a target calling
  # a package function by BARE name (e.g. `hd_commodity_mr_signal(...)`,
  # the actual #752 call site) correctly rebuilds when that function's body
  # changes. A target calling the SAME kind of function via an explicit
  # `historicaldata::fn()` namespaced call does NOT -- `targets`' own
  # documentation for `imports` states this limitation outright:
  # "Namespaced calls ... are ignored because of limitations in
  # codetools::findGlobals()". 22 files / ~135 lines in this repo's R/
  # currently call `historicaldata::` this way (confirmed via grep), so
  # this option closes the BARE-call share of #753's defect automatically,
  # with zero per-target edits, but does NOT close the namespaced-call
  # share on its own. See `pkg_source_files`/`pkg_source_digest` below and
  # scripts/check_pkg_staleness.R for the mechanism that covers the rest.
  #
  # STEADY-STATE BUILD COST (#753 / PR #757 review): a first build against
  # the REAL store after adding this option showed a mass reinvalidation
  # (89+ targets dispatched against a normal ~50) -- expected, since every
  # target `imports` newly tracks was, from `targets`' point of view,
  # previously undeclared and is now seeing its first-ever dependency edge.
  # The open question was whether a SECOND consecutive build (no source
  # changes) returns to the pre-#753 baseline or keeps re-invalidating
  # every time. OBSERVED (2026-08-25, throwaway store, NOT the real one --
  # `pkgload::load_all()` of this SAME real packages/historicaldata
  # directory, `imports = "historicaldata"`, 3 targets exercising a bare
  # call, a namespaced call, and a plain-R target): build 1 completed all 3
  # targets; builds 2 and 3, run back to back with zero source changes,
  # BOTH reported "skipped pipeline ... 3 skipped" -- 0 targets rebuilt,
  # internal tar_make() timing stable across all three runs (593ms / 547ms
  # / 557ms). This confirms the mechanism: `imports` hashes are a pure
  # function of the (unchanged) source text, so build-to-build comparison
  # against the stored hash finds no difference and correctly skips.
  # PREDICTED, not directly observed (this repo's worktree-isolation rule
  # forbids building the real 778-target docs/_targets store from a
  # worktree): applying this same mechanism to the real store predicts a
  # SECOND real build returns to something close to the pre-#753 baseline
  # (~30s, per the PR #757 review) -- the mass reinvalidation was a
  # one-time consequence of `imports` newly attaching real dependency
  # edges that did not previously exist, not a recurring per-build cost.
  imports = "historicaldata",
  memory = "transient",
  garbage_collection = TRUE,
  error = "continue",  # Don't let one broken target block all others
  format = "rds"
)

# Load local historicaldata package once at pipeline parse time.
# historicaldata is not installed in the nix env — pkgload::load_all() is
# the correct mechanism. Running it here (once) replaces 135 per-target
# pkgload::load_all() calls that were wasteful and side-effectful.
# See namespace-discipline rule and roborev PR-T.
pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)

# Source Tier 1 & 2 gap functions
# TODO: create tracking_error.R (tail_keff.R tracked under #624)
#
# liquidity.R (R/liquidity.R, #105/#569) provides calculate_adv() /
# filter_liquidity() / liquidity_summary(). plan_liquidity() (the
# consolidated_equity-based targets) still cannot run here — consolidated_equity
# only exists in the ROOT ingestion pipeline's _targets.R. Resolved by #625
# (decided 2026-08-04): plan_liquidity_dashboard() (also in R/plan_liquidity.R)
# re-expresses the same three-step computation against stk_universe
# (R/plan_stock_backtest.R:421), which IS available in this pipeline. See
# R/plan_liquidity.R for the full rationale and the flagged provenance-
# divergence risk between the two equity sources.
source(here::here("R/liquidity.R"))
# source(here::here("R/tracking_error.R"))
# source(here::here("R/tail_keff.R"))
# Phase B of #389: regime_correlations.R functions used by plan_cross_asset_corr.R
source(here::here("R/regime_correlations.R"))
source(here::here("R/vvix_analysis.R"))
source(here::here("R/crypto_momentum_helpers.R"))

# Source canonical backtest annualisation helper (annualise_returns()) — used by plan_kelly_variants + plan_etf_replication
source(here::here("R/utils_metrics.R"))

# Source rolling utility helpers (must load before any analysis file that calls roll_mean_safe)
source(here::here("R/utils_rolling.R"))

# Source period-alignment helper (must load before plan_falsification uses align_period)
source(here::here("R/utils_align.R"))

# Source disclosure strings — single source of truth for survivorship-bias caveats (#150)
source(here::here("R/disclosures.R"))

# Source date helpers — to_month_end_bizday() etc. (issue #147)
source(here::here("R/utils_dates.R"))

# Source dataset registry and validation helpers (phase 1 of #149)
source(here::here("R/dataset_registry.R"))
source(here::here("R/utils_validation.R"))

# Source momentum decomposition functions (issue #121)
source(here::here("R/momentum_decomposition.R"))

# Source volatility spike analysis functions (issue #119 Phase 1)
source(here::here("R/volatility_spike_analysis.R"))

# Source regime-dependent momentum functions (issue #123)
source(here::here("R/regime_momentum.R"))

# Source Zakamulin continuous allocation functions (issue #123 follow-up)
source(here::here("R/zakamulin_allocation.R"))

# Source commodities momentum functions (issue #134)
source(here::here("R/commodities_momentum.R"))

# Source crypto momentum functions (issue #135)
source(here::here("R/crypto_momentum.R"))

# Source covariance-estimator configuration (#498).
# Constants (COV_METHOD, COV_LW_TARGET) are evaluated at source() time;
# must precede any plan file that calls hd_cov_estimate().
source(here::here("R/cov_config.R"))

# Source plans (strategy_names FIRST — may be referenced by any plan)
source(here::here("R/plan_strategy_names.R"))
# Source plans (partitions FIRST — all backtests depend on it)
source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_vignette.R"))
source(here::here("R/plan_backtest.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_drif.R"))
source(here::here("R/plan_drif_v2.R"))
source(here::here("R/plan_stock_backtest.R"))
# #625: dashboard-side liquidity targets (plan_liquidity_dashboard()), sourced
# after plan_stock_backtest.R because its targets reference stk_universe.
# Source-file order does not affect DAG resolution (targets are matched by
# name at build time, not by source() order) but is kept adjacent for
# readability.
source(here::here("R/plan_liquidity.R"))
source(here::here("R/plan_xgb_signal.R"))
source(here::here("R/plan_portfolio_opt.R"))
source(here::here("R/plan_etf_replication.R"))
source(here::here("R/plan_kelly.R"))
source(here::here("R/plan_bootstrap_ci.R"))
source(here::here("R/plan_interval_coverage.R"))
source(here::here("R/plan_regime.R"))
source(here::here("R/plan_alpha_decay.R"))
source(here::here("R/plan_kelly_variants.R"))
source(here::here("R/plan_leaderboard.R"))
source(here::here("R/plan_strategy_correlation.R"))
# #626: gross/net exposure convention registry (measurement only)
source(here::here("R/plan_exposure.R"))
# #624: per-strategy transaction-cost convention registry (measurement only)
source(here::here("R/plan_cost_convention.R"))
source(here::here("R/plan_avoid_worst.R"))
source(here::here("R/plan_risk_state.R"))
source(here::here("R/plan_qa_vignette.R"))
source(here::here("R/plan_falsification.R"))
source(here::here("R/plan_falsification_vignette.R"))
source(here::here("R/plan_ltr_momentum.R"))
source(here::here("R/plan_quiz.R"))
source(here::here("R/plan_mean_reversion.R"))
source(here::here("R/plan_marginal_contribution.R"))
source(here::here("R/plan_strategy_decay.R"))
source(here::here("R/plan_interpretability.R"))
source(here::here("R/plan_shadow_trades.R"))
source(here::here("R/plan_multi_strategy.R"))
source(here::here("R/plan_vix_macro_overlay.R"))
source(here::here("R/plan_vvix.R"))
# source(here::here("R/plan_integration.R"))  # TODO: create plan_integration.R
source(here::here("R/plan_european_overlay.R"))
source(here::here("R/plan_rafi.R"))
source(here::here("R/plan_ev_ebit.R"))
source(here::here("R/plan_managed_futures.R"))
source(here::here("R/plan_forecast_eval.R"))
source(here::here("R/plan_kalshi.R"))
source(here::here("R/plan_nyt_sentiment.R"))
source(here::here("R/plan_circuit_breaker.R"))
source(here::here("R/plan_causal_graph.R"))
source(here::here("R/plan_ecb.R"))
source(here::here("R/plan_guardian.R"))
source(here::here("R/plan_jst.R"))
source(here::here("R/plan_jst_trend.R"))
source(here::here("R/plan_momentum_decomposition.R"))
source(here::here("R/plan_volatility_spikes.R"))
source(here::here("R/plan_regime_momentum.R"))
source(here::here("R/plan_zakamulin_allocation.R"))
source(here::here("R/plan_commodities_momentum.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))
source(here::here("R/plan_mom_prepeak.R"))
source(here::here("R/plan_mom_prepeak_gauntlet.R"))
source(here::here("R/plan_fip_screen.R"))
source(here::here("R/plan_add_crowding.R"))
source(here::here("R/plan_crypto_momentum.R"))
source(here::here("R/plan_solana_momentum.R"))
source(here::here("R/plan_olmar.R"))
source(here::here("R/plan_bdbb_sol.R"))
source(here::here("R/plan_turn_of_month.R"))
source(here::here("R/plan_wf_correlation.R"))
source(here::here("R/plan_structural_breaks.R"))
source(here::here("R/plan_artefact_registry.R"))
# #617: dv_pairwise_alignment_matrix — previously written but never sourced
# here, so plan_data_validation() was unreachable and the target unwired.
# Wired now rather than deleted: tests/testthat/test-pairwise-alignment.R
# already asserts plan_data_validation() returns a list containing this
# target, and its two probed dimensions (date_class, freq) are a genuine
# pairwise cross-check distinct from dv_join_key_types' n-way comparison.
source(here::here("R/plan_data_validation.R"))
source(here::here("R/plan_qa_gates.R"))
# #553/#554/#555: fundamentals revision-triangle QA gates (guarded no-op
# until a fundamentals-consuming strategy exists -- see file header)
source(here::here("R/plan_qa_fundamentals.R"))
# Phase B of #389: covariance infrastructure + fixed cross-asset correlation plan
source(here::here("R/plan_returns.R"))
source(here::here("R/plan_cross_asset_corr.R"))
# Phase 3a of #498: OOS min-variance / conditioning diagnostic
source(here::here("R/plan_cov_diagnostic.R"))
# Phase 3b of #498: covariance diagnostic vignette targets (falsification.qmd section)
source(here::here("R/plan_cov_diagnostic_vignette.R"))
# Phase 4b of #507: weight-stability vignette targets (falsification.qmd #wstab section)
source(here::here("R/plan_weight_stability_vignette.R"))
# #482 Slice 1: strategy digest (leaderboard deltas + blastula email-to-file)
source(here::here("R/plan_strategy_digest.R"))

# Combine: strategy_names FIRST, then partitions, strategies, portfolio, ETF replication, leaderboard, QA
c(plan_strategy_names(),
  plan_partitions(), plan_vignette(), plan_backtest(), plan_factormax(), plan_drif(), plan_drif_v2(),
  plan_stock_backtest(), plan_liquidity_dashboard(), plan_xgb_signal(), plan_portfolio_opt(),
  plan_etf_replication(), plan_kelly(), plan_bootstrap_ci(),
  plan_interval_coverage(),
  plan_regime(), plan_alpha_decay(),
  plan_kelly_variants(),
  plan_avoid_worst(),
  plan_risk_state(),
  plan_mean_reversion(),
  plan_marginal_contribution(),
  plan_strategy_decay(),
  plan_interpretability(),
  plan_shadow_trades(),
  plan_multi_strategy(),
  plan_vix_macro_overlay(),
  plan_vvix(),
  # plan_integration(),  # TODO: create plan_integration.R
  plan_european_overlay(),
  plan_rafi(),
  plan_ev_ebit(),
  plan_managed_futures(),
  plan_forecast_eval(),
  plan_strategy_correlation(),
  plan_exposure(),
  plan_cost_convention(),
  plan_leaderboard(), plan_strategy_digest(), plan_qa_vignette(),
  plan_falsification(),
  plan_falsification_vignette(),
  plan_ltr_momentum(),
  plan_quiz(),
  plan_kalshi(),
  plan_nyt_sentiment(),
  plan_circuit_breaker(),
  plan_causal_graph(),
  plan_ecb(),
  plan_guardian(),
  plan_jst(),
  plan_jst_trend(),
  plan_momentum_decomposition(),
  plan_volatility_spikes(),
  plan_regime_momentum(),
  plan_zakamulin_allocation(),
  plan_commodities_momentum(),
  plan_commodities_mean_reversion(),
  plan_mom_prepeak(),
  plan_mom_prepeak_gauntlet(),
  plan_fip_screen(),
  plan_add_crowding(),
  plan_crypto_momentum(),
  plan_solana_momentum(),
  plan_olmar(),
  plan_bdbb_sol(),
  plan_turn_of_month(),
  plan_wf_correlation(),
  plan_structural_breaks(),
  plan_artefact_registry(),

  # #753 mechanism (2): track packages/historicaldata/R source content as a
  # normal `targets` dependency, using the file-hash cue `targets` already
  # trusts for `format = "file"` targets -- NOT via pkgload::load_all(),
  # which is exactly what the defect this issue is about slips past (see the
  # tar_option_set(imports = ...) comment above for the bare-call half of
  # the fix; this pair of targets is the digest half, and the ONLY reliable
  # foundation for scripts/check_pkg_staleness.R's cross-run check, since
  # calling tar_meta()/tar_progress() from WITHIN a target of the pipeline
  # they belong to is unsupported -- confirmed empirically, see that
  # script's header comment).
  #
  # `pkg_source_files` also includes DESCRIPTION and NAMESPACE: DESCRIPTION's
  # Imports/Depends and Collate order affect what pkgload::load_all() puts
  # in the namespace, and NAMESPACE's export list affects what
  # `historicaldata::fn()` call sites can even resolve to (a function moved
  # out of NAMESPACE without touching its own .R file would otherwise be
  # invisible to this digest). No compiled code exists under
  # packages/historicaldata (no src/), so nothing else load_all() reads is
  # missing from this list.
  targets::tar_target(
    pkg_source_files,
    sort(c(
      list.files(
        here::here("packages/historicaldata/R"),
        pattern = "\\.R$", full.names = TRUE, recursive = TRUE
      ),
      here::here("packages/historicaldata/DESCRIPTION"),
      here::here("packages/historicaldata/NAMESPACE")
    )),
    format = "file"
  ),
  targets::tar_target(
    pkg_source_digest,
    {
      hashes <- tools::md5sum(pkg_source_files)
      digest::digest(paste(names(hashes), unname(hashes), sep = "=", collapse = "|"))
    }
  ),

  plan_qa_gates(),
  plan_qa_fundamentals(),
  # Phase B of #389: covariance targets + fixed cross-asset correlation plan
  plan_returns(),
  plan_cross_asset_corr(),
  # Phase 3a of #498: OOS min-variance / conditioning diagnostic compute core
  plan_cov_diagnostic(),
  # Phase 3b of #498: vignette targets for falsification.qmd covariance section
  plan_cov_diagnostic_vignette(),
  # Phase 4b of #507: weight-stability vignette targets for falsification.qmd #wstab
  plan_weight_stability_vignette(),

  # Phase 1 of #149: date-type consistency across all registered datasets.
  # tar_target_raw + explicit deps so targets schedules dv_join_key_types
  # AFTER all registered producers rebuild (fixes #152 Bug 1).
  # check_date_key_types() uses readRDS() internally — no tar_read_raw().
  # cb_data and cb_regime are excluded from deps because they are broken
  # pending #145 — the validation function marks them "missing" gracefully.
  targets::tar_target_raw(
    "dv_join_key_types",
    command = quote(check_date_key_types(dataset_registry())),
    deps = setdiff(dataset_registry()$target_name, c("cb_data", "cb_regime")),
    cue = targets::tar_cue(mode = "always")
  ),

  # Layer 1 of #147: validate that monthly-return targets use month-end-bizday
  # date stamps.  cli_warn (not cli_abort) — informational pending the drif
  # migration in layer 2.
  # tar_target_raw + explicit deps so this runs AFTER the three monthly
  # targets rebuild (fixes #152 Bug 2).  readRDS replaces tar_read_raw()
  # which is forbidden inside a target body (silently errors in tryCatch).
  targets::tar_target_raw(
    "dv_monthly_convention",
    command = quote(
      check_monthly_convention(
        c("fals_drif_input", "fals_fac_max_input", "fals_ltr_input")
      )
    ),
    deps = c("fals_drif_input", "fals_fac_max_input", "fals_ltr_input"),
    cue = targets::tar_cue(mode = "always")
  ),

  # #148 Phase 3: validate sampling-frequency alignment for all registered datasets.
  # Warns (does not abort) when a series's observed median interval exceeds
  # 2× the registry-declared frequency. This catches mis-registered freq values
  # and data sources that changed cadence silently.
  # tar_target_raw + explicit deps (matches #152 pattern) so this runs AFTER
  # all registered producers. cb_data and cb_regime excluded pending #145.
  targets::tar_target_raw(
    "dv_frequency_alignment",
    command = quote(check_frequency_alignment(dataset_registry())),
    deps = setdiff(dataset_registry()$target_name, c("cb_data", "cb_regime")),
    cue = targets::tar_cue(mode = "always")
  ),

  # #617: two of the nine data-validation-timeseries rule's mandated targets.
  # The other 7 stay explicitly backlogged (see the rule + issue #617) until
  # these two prove their keep — building all nine at once was rejected in
  # the issue in favour of the pair that pays for itself on data we hold.
  #
  # dv_temporal_coverage — expected-vs-actual trading-day observations per
  # daily-freq target (Mon-Fri, no holiday calendar). Aborts < 30% coverage,
  # warns < 80% (rule #1 thresholds). This is what would have caught the
  # VIXCLS 302-NA gap named in #617 had it existed at the time.
  # tar_target_raw + explicit deps, matching the #152 scheduling fix used by
  # dv_join_key_types/dv_frequency_alignment above. cb_data/cb_regime
  # excluded pending #145.
  targets::tar_target_raw(
    "dv_temporal_coverage",
    command = quote(check_temporal_coverage(dataset_registry())),
    deps = setdiff(dataset_registry()$target_name, c("cb_data", "cb_regime")),
    cue = targets::tar_cue(mode = "always")
  ),

  # dv_freshness — latest observation vs today, threshold scaled by the
  # registry's declared freq. Warns (does not abort): a stale upstream fetch
  # (#613 was exactly this) is a signal to investigate, not a hard pipeline
  # failure, since a warning alone should not block unrelated targets.
  targets::tar_target_raw(
    "dv_freshness",
    command = quote(check_freshness(dataset_registry())),
    deps = setdiff(dataset_registry()$target_name, c("cb_data", "cb_regime")),
    cue = targets::tar_cue(mode = "always")
  ),

  plan_data_validation()
)
