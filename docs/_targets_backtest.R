# Backtesting targets: Defense First rotation strategy
#
# Separate targets project from the main vignette targets.
# Run: cd docs && Rscript -e 'targets::tar_make(store = "_targets_backtest")'

library(targets)

tar_option_set(
  packages = c("dplyr", "tidyr", "ggplot2", "scales", "DT", "rlang", "cli"),
  memory = "transient",
  garbage_collection = TRUE,
  format = "rds"
)

source(here::here("R/plan_backtest.R"))

plan_backtest()
