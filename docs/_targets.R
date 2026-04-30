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
for (pkg in c("duckplyr", "glmnet", "xgboost", "slider")) {
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
  packages = c("dplyr", "duckplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli"),
  memory = "transient",
  garbage_collection = TRUE,
  error = "continue",  # Don't let one broken target block all others
  format = "rds"
)

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

# Combine: strategy_names FIRST, then partitions, strategies, portfolio, ETF replication, leaderboard, QA
c(plan_strategy_names(),
  plan_partitions(), plan_vignette(), plan_backtest(), plan_factormax(), plan_drif(),
  plan_stock_backtest(), plan_xgb_signal(), plan_portfolio_opt(),
  plan_etf_replication(), plan_kelly(), plan_bootstrap_ci(),
  plan_regime(), plan_alpha_decay(),
  plan_avoid_worst(),
  plan_risk_state(),
  plan_mean_reversion(),
  plan_marginal_contribution(),
  plan_strategy_decay(),
  plan_interpretability(),
  plan_leaderboard(), plan_qa_vignette(),
  plan_falsification(),
  plan_falsification_vignette(),
  plan_ltr_momentum(),
  plan_quiz())
