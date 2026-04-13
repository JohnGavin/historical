# Vignette targets: pre-compute all data and plots for examples.qmd
#
# This is a SEPARATE targets project from the main pipeline _targets.R.
# It runs OUTSIDE the T sandbox and uses the historicaldata package API
# to fetch data from HF via DuckDB httpfs.
#
# Usage:
#   cd docs/
#   Rscript -e 'targets::tar_make()'
#
# Or from project root:
#   Rscript -e 'targets::tar_make(store = "docs/_targets")'

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
source(here::here("R/plan_qa_vignette.R"))

# Combine: vignette targets + QA validation targets
c(plan_vignette(), plan_qa_vignette())
