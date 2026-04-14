# Shared backtesting partitions: train / test / validation
#
# Single source of truth for date boundaries across all strategies.
# Validation data is LOCKED — not computed automatically.
#
# Training:   model fitting, expanding window signal estimation
# Testing:    calibration, hyperparameter tuning, strategy comparison
# Validation: final one-shot evaluation (sealed envelope)

plan_partitions <- function() {
  list(
    targets::tar_target(bt_partitions, {
      list(
        # Equity / stock-level strategies (data from ~2005)
        equity = list(
          train_start = as.Date("2005-01-01"),
          train_end   = as.Date("2019-12-31"),
          test_start  = as.Date("2020-01-01"),
          test_end    = as.Date("2022-12-31"),
          val_start   = as.Date("2023-01-01"),
          val_end     = as.Date("2026-12-31")
        ),
        # Factor-level strategies (data from 1963)
        factor = list(
          train_start = as.Date("1968-01-01"),  # 60-month min window from 1963
          train_end   = as.Date("2019-12-31"),
          test_start  = as.Date("2020-01-01"),
          test_end    = as.Date("2022-12-31"),
          val_start   = as.Date("2023-01-01"),
          val_end     = as.Date("2026-12-31")
        ),
        # Macro defense rotation (data from 2007)
        macro = list(
          train_start = as.Date("2007-04-01"),
          train_end   = as.Date("2019-12-31"),
          test_start  = as.Date("2020-01-01"),
          test_end    = as.Date("2022-12-31"),
          val_start   = as.Date("2023-01-01"),
          val_end     = as.Date("2026-12-31")
        )
      )
    })
  )
}
