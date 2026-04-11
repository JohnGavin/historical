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

tar_option_set(
  packages = c("dplyr", "ggplot2", "tidyr", "scales", "DT", "rlang", "cli"),
  memory = "transient",
  garbage_collection = TRUE,
  format = "rds"
)

# Source the vignette plan
source(here::here("R/plan_vignette.R"))

# Combine: all vig_* targets
plan_vignette()
