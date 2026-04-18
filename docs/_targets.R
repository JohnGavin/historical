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
for (pkg in c("duckplyr", "glmnet")) {
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

# Source plans (partitions FIRST — all backtests depend on it)
source(here::here("R/plan_partitions.R"))
source(here::here("R/plan_vignette.R"))
source(here::here("R/plan_backtest.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_drif.R"))
source(here::here("R/plan_stock_backtest.R"))
source(here::here("R/plan_xgb_signal.R"))
source(here::here("R/plan_qa_vignette.R"))

# Combine: partitions first, then all strategies, then QA
c(plan_partitions(), plan_vignette(), plan_backtest(), plan_factormax(), plan_drif(),
  plan_stock_backtest(), plan_xgb_signal(), plan_qa_vignette())
