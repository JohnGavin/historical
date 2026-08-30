# Shared backtesting partitions: train / test / holdout / validation
#
# Single source of truth for date boundaries across all strategies.
# Validation data is LOCKED — not computed automatically.
#
# Training:   model fitting, expanding window signal estimation
# Testing:    calibration, hyperparameter tuning, strategy comparison
# Holdout:    observed data retained for evaluation — NOT sealed (#660)
# Validation: final one-shot evaluation (sealed envelope)
#
# ── Four-tier re-cut (#660) ─────────────────────────────────────────────────
# The original two-way Testing/Validation split (test_end = 2022-12-31,
# val_start = 2023-01-01) was burned: #660 found docs/stock-backtest.qmd
# publishing Validation figures in prose and drawing a strategy conclusion
# from them (fixed at #660/PR #662 and #648/PR #659, but the *partition
# itself* stayed observed once it was read and reasoned about — see
# `.claude/rules/backtest-partitions.md` "Reasoning" clause).
#
# Every month from 2024-01 to the data end (2026-04-15 equity, 2026-02-27
# factor as of #660) sits inside the block that was read, so no re-slicing
# of EXISTING data yields a clean window — the entire 2024-2026 span is
# observed. The only genuinely unobserved data is 2026-05-01 onwards: the
# first month past the current data boundary. That is why `val_start` moves
# there rather than to any earlier date.
#
# The re-cut adds a fourth tier, `Holdout`, absorbing the burned 2023-2026
# span:
#   Training  -- unchanged (train_start .. train_end)
#   Testing   -- test_start .. 2023-12-31 (absorbs the burned 2023, which
#                used to be the first year of the old Validation partition)
#   Holdout   -- 2024-01-01 .. 2026-04-30 (observed, computed automatically,
#                usable for evaluation WITH A STATED DISCOUNT because it has
#                been read; NEVER describe it as sealed)
#   Validation -- 2026-05-01 onwards (genuinely untouched; will be EMPTY
#                until new data arrives past the current boundary)
#
# Holdout is NOT a replacement for Validation's sealing guarantee. It exists
# because the four-part seal (computation / storage / display / reasoning,
# `.claude/rules/backtest-partitions.md`) can only be honoured for data that
# has never been observed -- and the 2024-2026 block no longer qualifies.
# Holdout is the honest label for "observed, not sealed, still informative."

# ── Canonical period vocabulary (#643) ──────────────────────────────────────
# Single source of truth for every value the `period` column is allowed to
# hold, across every strategy metrics target AND the `leaderboard` target
# that aggregates them. Sourced before plan_leaderboard.R / plan_qa_gates.R /
# plan_ev_ebit.R / plan_managed_futures.R in docs/_targets.R, so this object
# is available wherever those files reference it.
#
# "OOS" is INTENTIONALLY separate from "Testing" — they are not synonyms:
#   - "Testing" is the canonical, bounded window in `bt_partitions` above
#     (2020-01-01..2023-12-31 for every asset class as of #660 -- widened by
#     one year to absorb the burned 2023 that used to open the old
#     Validation partition; see the "Four-tier re-cut (#660)" comment above).
#   - "OOS" labels a strategy-local out-of-sample split defined by its own
#     `oos_start` parameter with NO end bound (e.g. R/plan_ev_ebit.R and
#     R/plan_managed_futures.R both use `dates >= 2010-01-01`, which spans
#     the canonical Training tail, all of Testing, all of Holdout, and (once
#     any exists) all of Validation in one undifferentiated block). Because
#     "OOS" is bounded above at `test_end` (#645, QA gate S11), moving
#     `test_end` to 2023-12-31 widens every OOS window by one year too --
#     see the #660 PR report for the full list of strategies whose published
#     OOS numbers move as a result.
# Renaming "OOS" to "Testing" would misrepresent that wider, strategy-defined
# sample as the shared cross-strategy test partition — so both labels stay
# in the allowed set, and no `.norm_*` helper in R/plan_leaderboard.R may
# rename OOS to Testing. Only "Full" -> "Full Period" is a safe rename
# (pure spelling difference for the same concept — see #643).
#
# "Holdout" was added in #660 for the new observed-but-unsealed tier
# (2024-01-01..2026-04-30). It is computed automatically by tar_make() --
# unlike Validation, this is by design (see the "Four-tier re-cut (#660)"
# comment above) -- and is exempt from the QA gate S11 `test_end` bound in
# R/plan_qa_gates.R (`check_metric_window_bounds()`) for the same reason
# "Full Period" is: it is a partition whose whole purpose is to extend past
# `test_end`, not a bespoke window that has silently grown to swallow the
# sealed partition. It is NOT required per-strategy (unlike "Full Period",
# which the S10 gate requires); a strategy may report Holdout metrics or
# not, same as OOS/Testing.
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
# As of #660, this window (val_start = 2026-05-01) is EMPTY against the
# current data boundary (2026-04-15 equity, 2026-02-27 factor) -- that is
# expected, not a bug; every `calc_metrics()`/`calc_backtest_metrics()`-style
# helper that feeds a "Validation" row returns NULL below its minimum
# observation count, so an empty window silently contributes zero rows
# rather than erroring or emitting a spurious NA row (verified per source
# target as part of #660; see the PR report for the full list).
#
# ── #668: derived from the glossary, not a second source of truth ──────────
# This constant used to hand-type the same six values that now live in
# data/glossary.yaml's `period_label` entity. Deriving it here (rather than
# maintaining both) is exactly the fix #668 asked for: "PERIOD_LABELS_ALLOWED
# becomes a *consumer* of the registry rather than a second source of
# truth." R/glossary.R is sourced immediately before this file in
# docs/_targets.R for exactly this reason -- see that file's module comment.
PERIOD_LABELS_ALLOWED <- load_glossary()$period_label$values

plan_partitions <- function() {
  list(
    targets::tar_target(bt_partitions, {
      list(
        # Equity / stock-level strategies (data from ~2005)
        equity = list(
          train_start   = as.Date("2005-01-01"),
          train_end     = as.Date("2019-12-31"),
          test_start    = as.Date("2020-01-01"),
          test_end      = as.Date("2023-12-31"),
          holdout_start = as.Date("2024-01-01"),
          holdout_end   = as.Date("2026-04-30"),
          val_start     = as.Date("2026-05-01"),
          val_end       = as.Date("2026-12-31")
        ),
        # Factor-level strategies (data from 1963)
        factor = list(
          train_start   = as.Date("1968-01-01"),  # 60-month min window from 1963
          train_end     = as.Date("2019-12-31"),
          test_start    = as.Date("2020-01-01"),
          test_end      = as.Date("2023-12-31"),
          holdout_start = as.Date("2024-01-01"),
          holdout_end   = as.Date("2026-04-30"),
          val_start     = as.Date("2026-05-01"),
          val_end       = as.Date("2026-12-31")
        ),
        # Macro defense rotation (data from 2007)
        macro = list(
          train_start   = as.Date("2007-04-01"),
          train_end     = as.Date("2019-12-31"),
          test_start    = as.Date("2020-01-01"),
          test_end      = as.Date("2023-12-31"),
          holdout_start = as.Date("2024-01-01"),
          holdout_end   = as.Date("2026-04-30"),
          val_start     = as.Date("2026-05-01"),
          val_end       = as.Date("2026-12-31")
        )
      )
    })
  )
}
