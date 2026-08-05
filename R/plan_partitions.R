# Shared backtesting partitions: train / test / validation
#
# Single source of truth for date boundaries across all strategies.
# Validation data is LOCKED — not computed automatically.
#
# Training:   model fitting, expanding window signal estimation
# Testing:    calibration, hyperparameter tuning, strategy comparison
# Validation: final one-shot evaluation (sealed envelope)

# ── Canonical period vocabulary (#643) ──────────────────────────────────────
# Single source of truth for every value the `period` column is allowed to
# hold, across every strategy metrics target AND the `leaderboard` target
# that aggregates them. Sourced before plan_leaderboard.R / plan_qa_gates.R /
# plan_ev_ebit.R / plan_managed_futures.R in docs/_targets.R, so this object
# is available wherever those files reference it.
#
# "OOS" is INTENTIONALLY separate from "Testing" — they are not synonyms:
#   - "Testing" is the canonical, bounded window in `bt_partitions` above
#     (currently 2020-01-01..2022-12-31 for every asset class).
#   - "OOS" labels a strategy-local out-of-sample split defined by its own
#     `oos_start` parameter with NO end bound (e.g. R/plan_ev_ebit.R and
#     R/plan_managed_futures.R both use `dates >= 2010-01-01`, which spans
#     the canonical Training tail (2010-2019), all of Testing (2020-2022),
#     and all of Validation (2023+) in one undifferentiated block).
# Renaming "OOS" to "Testing" would misrepresent that wider, strategy-defined
# sample as the shared cross-strategy test partition — so both labels stay
# in the allowed set, and no `.norm_*` helper in R/plan_leaderboard.R may
# rename OOS to Testing. Only "Full" -> "Full Period" is a safe rename
# (pure spelling difference for the same concept — see #643).
#
# "Validation" stays in the allowed set (#648 decision) even though the
# `leaderboard` target's own automatic path may no longer emit a row with
# this label (R/plan_leaderboard.R strips it at `all_metrics` assembly,
# guarded by the S14 gate in R/plan_qa_gates.R). PERIOD_LABELS_ALLOWED names
# the VOCABULARY, not WHERE a label may be computed — those are separate
# concerns. "Validation" remains legitimate vocabulary because:
#   1. Several source metrics targets (fm_metrics, drif_metrics,
#      stk_max_metrics, stk_drif_metrics, xgb_drif_metrics, ltr_metrics,
#      port_metrics) still compute it in their own right for their own
#      consumers (e.g. docs/stock-backtest.qmd prose) — out of #648's scope.
#   2. scripts/evaluate_validation.R, the sanctioned manual one-shot
#      evaluation route required by backtest-partitions.md, produces rows
#      labelled "Validation" by design.
# Removing it from this constant would make both of the above fail S10
# (check_leaderboard_period_vocab) / any future vocab check applied to them.
PERIOD_LABELS_ALLOWED <- c(
  "Training", "Testing", "Validation", "Full Period", "OOS"
)

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
