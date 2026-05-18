# Unified vignette targets: pre-compute all data and plots
#
# Covers: examples.qmd (66 targets) + macro-defense-rotation.qmd (15 targets)
# + QA validation (1 target). Total: 82 targets in one pipeline.
#
# Usage:
#   cd docs/
#   Rscript -e 'targets::tar_make()'

library(targets)

# Ensure project nix shell packages are on .libPaths
# (Claude's dev shell may not include all project deps)
for (pkg in c("duckplyr", "glmnet", "xgboost", "slider", "RcppRoll")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    pkg_paths <- Sys.glob(sprintf("/nix/store/*-r-%s-*/library", pkg))
    pkg_paths <- pkg_paths[file.exists(file.path(pkg_paths, pkg))]
    if (length(pkg_paths) > 0) {
      # Add full closure (transitive deps) not just the package itself
      closure <- system2("nix-store", c("-qR", dirname(pkg_paths[[1]])),
                         stdout = TRUE, stderr = FALSE)
      r_libs <- closure[file.exists(file.path(closure, "library"))]
      r_libs <- r_libs[vapply(r_libs, function(p) {
        any(file.exists(list.files(file.path(p, "library"), full.names = TRUE,
                                   pattern = "DESCRIPTION", recursive = TRUE)))
      }, logical(1))]
      .libPaths(c(.libPaths(), file.path(r_libs, "library")))
    }
  }
}

tar_option_set(
  packages = c("dplyr", "duckplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli", "RcppRoll"),
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
# TODO: create liquidity.R, tracking_error.R, regime_correlations.R, tail_keff.R
# source(here::here("R/liquidity.R"))
# source(here::here("R/tracking_error.R"))
# source(here::here("R/regime_correlations.R"))
# source(here::here("R/tail_keff.R"))
source(here::here("R/vvix_analysis.R"))

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

# Source plans (strategy_names FIRST — may be referenced by any plan)
source(here::here("R/plan_strategy_names.R"))
# Source plans (partitions FIRST — all backtests depend on it)
source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_vignette.R"))
source(here::here("R/plan_backtest.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_drif.R"))
source(here::here("R/plan_stock_backtest.R"))
source(here::here("R/plan_xgb_signal.R"))
source(here::here("R/plan_portfolio_opt.R"))
source(here::here("R/plan_etf_replication.R"))
source(here::here("R/plan_kelly.R"))
source(here::here("R/plan_bootstrap_ci.R"))
source(here::here("R/plan_regime.R"))
source(here::here("R/plan_alpha_decay.R"))
source(here::here("R/plan_kelly_variants.R"))
source(here::here("R/plan_leaderboard.R"))
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
source(here::here("R/plan_forecast_eval.R"))
source(here::here("R/plan_kalshi.R"))
source(here::here("R/plan_nyt_sentiment.R"))
source(here::here("R/plan_circuit_breaker.R"))
source(here::here("R/plan_causal_graph.R"))
source(here::here("R/plan_ecb.R"))
source(here::here("R/plan_guardian.R"))
source(here::here("R/plan_jst.R"))
source(here::here("R/plan_momentum_decomposition.R"))
source(here::here("R/plan_volatility_spikes.R"))
source(here::here("R/plan_regime_momentum.R"))
source(here::here("R/plan_zakamulin_allocation.R"))
source(here::here("R/plan_commodities_momentum.R"))
source(here::here("R/plan_crypto_momentum.R"))

# Combine: strategy_names FIRST, then partitions, strategies, portfolio, ETF replication, leaderboard, QA
c(plan_strategy_names(),
  plan_partitions(), plan_vignette(), plan_backtest(), plan_factormax(), plan_drif(),
  plan_stock_backtest(), plan_xgb_signal(), plan_portfolio_opt(),
  plan_etf_replication(), plan_kelly(), plan_bootstrap_ci(),
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
  plan_forecast_eval(),
  plan_leaderboard(), plan_qa_vignette(),
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
  plan_momentum_decomposition(),
  plan_volatility_spikes(),
  plan_regime_momentum(),
  plan_zakamulin_allocation(),
  plan_commodities_momentum(),
  plan_crypto_momentum(),

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
  )
)
