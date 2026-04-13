# Unified vignette targets: pre-compute all data and plots
#
# Covers: examples.qmd (66 targets) + macro-defense-rotation.qmd (15 targets)
# + QA validation (1 target). Total: 82 targets in one pipeline.
#
# Usage:
#   cd docs/
#   Rscript -e 'targets::tar_make()'

library(targets)

# Ensure duckplyr is available (may not be on default .libPaths in some nix shells)
if (!requireNamespace("duckplyr", quietly = TRUE)) {
  duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
  duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
  if (length(duckplyr_path) > 0) {
    .libPaths(c(.libPaths(), duckplyr_path[[1]]))
  }
}

tar_option_set(
  packages = c("dplyr", "duckplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli"),
  memory = "transient",
  garbage_collection = TRUE,
  error = "continue",  # Don't let one broken target block all others
  format = "rds"
)

# Source plans
source(here::here("R/plan_vignette.R"))
source(here::here("R/plan_backtest.R"))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_qa_vignette.R"))

# Combine: all vignette + backtest + factor max + QA
c(plan_vignette(), plan_backtest(), plan_factormax(), plan_qa_vignette())
