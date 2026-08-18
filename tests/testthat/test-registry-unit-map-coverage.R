testthat::local_edition(3)

# Regression test for #691: `ann_rf` was added to 11 metrics targets
# (#677 slice 4, #686) without being added to the corresponding
# hand-maintained `<prefix>_units` maps the registry writers pass to
# historicaldata::hd_metric_record(). Because hd_metric_record() aborts on
# any column with no declared unit (#640), every one of those writers began
# erroring -- hidden by `error = "continue"` in docs/_targets.R (see #691).
#
# The units maps are locals inside each writer's helper function, so they
# cannot be imported and inspected directly. This test statically parses
# each plan file's AST (parse(), no evaluation of target bodies, no store
# build -- a worktree must not build the store, see .claude/CLAUDE.md
# "Verifying a change") to extract the literal `<prefix>_units <- c(...)`
# assignment, and compares its names against the metrics-computing
# function's own tibble() column list (also read from source and hardcoded
# below, with a citation to the exact lines verified for #691's PR).
#
# `hd_metric_record()`'s wide-form path
# (.normalise_metric_long(), packages/historicaldata/R/registry_metrics.R:
# 408-431) only requires a unit for NUMERIC, non-NA columns of the selected
# metric_cols -- character columns (e.g. `strategy`) and Date columns (e.g.
# `window_start`) are auto-skipped regardless of whether the map covers
# them. The "required" sets below are therefore the numeric subset of each
# target's own columns, not literally every column name.

# ── AST-based extractor for a local `<varname> <- c(...)` assignment ──────
# Walks the parsed (unevaluated) expression tree of `file` looking for an
# assignment whose LHS is the symbol `varname` and whose RHS is a call
# (almost always `c(...)`). Returns the evaluated RHS -- safe here because
# every `<prefix>_units` map in this repo is a literal named character
# vector with no external references (verified by inspection for all 11
# call sites this test covers).
.extract_units_map <- function(file, varname) {
  exprs <- parse(file, keep.source = FALSE)
  found <- NULL
  # Calls like `full_row[, metric_cols, drop = FALSE]` leave an empty
  # (missing) argument slot in their parse tree; as.list() surfaces it as
  # R's internal missing-arg sentinel, and merely referencing that binding
  # (even to test its class) raises "argument is missing, with no default".
  # tryCatch() around every touch of a list element guards against it.
  is_call_safe <- function(x) tryCatch(is.call(x), error = function(err) FALSE)
  walk <- function(e) {
    if (!is.null(found) || !is_call_safe(e)) {
      return(invisible())
    }
    if (identical(e[[1]], as.symbol("<-")) &&
      is.symbol(e[[2]]) && identical(as.character(e[[2]]), varname)) {
      found <<- eval(e[[3]])
      return(invisible())
    }
    for (part in as.list(e)) {
      if (!is.null(found)) break
      if (is_call_safe(part)) walk(part)
    }
  }
  for (e in exprs) {
    if (!is.null(found)) break
    walk(e)
  }
  if (is.null(found)) {
    # basename(), not the full path -- keeps the abort message (and its
    # snapshot) portable across checkouts/CI per portable-build-artifacts.
    cli::cli_abort(c(
      "x" = "Could not find {.code {varname} <- c(...)} in {.file {basename(file)}}.",
      "i" = "The unit map may have been renamed or restructured."
    ))
  }
  found
}

plan_dir <- here::here("R")

# One entry per registry writer's unit map. `required` is the verified
# numeric-column set of the metrics target that feeds this writer -- see
# the cited source lines for each.
unit_map_cases <- list(
  list(
    plan_file = "plan_ltr_momentum.R", varname = "ltr_units",
    # compute_ltr_metrics(), R/plan_ltr_momentum.R:198-214
    required = c(
      "months", "cagr", "vol", "max_dd", "sharpe", "ann_rf",
      "hac_sharpe", "hac_tstat", "avg_long", "avg_short"
    )
  ),
  list(
    plan_file = "plan_avoid_worst.R", varname = "aw_units",
    # metrics_for(), R/plan_avoid_worst.R:551-569 -- strategy (character)
    # and window_start/window_end (Date) are auto-skipped by
    # hd_metric_record()'s numeric-only wide-form path; period/scenario are
    # excluded from metric_cols by setdiff() before this point.
    required = c("years", "n_days", "cagr", "vol", "max_dd", "sharpe", "ann_rf")
  ),
  list(
    plan_file = "plan_turn_of_month.R", varname = "tom_units",
    # calc(), R/plan_turn_of_month.R:173-198
    required = c(
      "n_days", "years", "cagr_tom", "vol_tom", "sharpe_tom",
      "ann_rf_tom", "max_dd_tom", "cagr_bh", "vol_bh", "sharpe_bh",
      "max_dd_bh", "n_tom_days", "pct_in_tom"
    )
  ),
  list(
    plan_file = "plan_risk_state.R", varname = "rsc_units",
    # calc_metrics(), R/plan_risk_state.R:335-352 -- strategy (character)
    # and window_start/window_end (Date) are auto-skipped.
    required = c("cagr", "vol", "sharpe", "ann_rf", "max_dd", "hac_tstat", "hac_sharpe")
  ),
  list(
    plan_file = "plan_mom_prepeak.R", varname = "mom_prepeak_units",
    # .mom_prepeak_compute_metrics(), packages/historicaldata/R/
    # utils_mom_prepeak_metrics.R:124-138, plus `m$ann_rf <- ...` at
    # R/plan_mom_prepeak.R:157/165/173 -- blown_up/loss_clustered (logical)
    # are auto-skipped.
    required = c(
      "n_months", "sharpe", "cagr", "vol", "max_dd",
      "bankrupt_month", "avg_dd_days", "max_dd_days",
      "max_cons_losses", "ann_rf"
    )
  ),
  list(
    plan_file = "plan_commodities_mean_reversion.R", varname = "cmr_units",
    # .compute_cmr_metrics(), R/plan_commodities_mean_reversion.R:251-265
    required = c(
      "n_months", "sharpe", "cagr", "vol", "ann_rf", "max_dd",
      "avg_dd_duration", "max_dd_duration"
    )
  ),
  list(
    plan_file = "plan_factormax.R", varname = "fm_units",
    # calc_metrics(), R/plan_factormax.R:202-209
    required = c(
      "months", "cagr", "vol", "sharpe", "ann_rf", "max_dd",
      "hit_rate", "bench_cagr", "bench_vol", "bench_sharpe"
    )
  ),
  list(
    plan_file = "plan_drif.R", varname = "drif_units",
    # calc_metrics(), R/plan_drif.R:307-313
    required = c(
      "months", "cagr", "vol", "sharpe", "ann_rf", "max_dd",
      "hit_rate", "bench_cagr", "bench_vol", "bench_sharpe"
    )
  ),
  list(
    plan_file = "plan_stock_backtest.R", varname = "stk_units",
    # calc_backtest_metrics(), R/plan_stock_backtest.R:431-449 (shared by
    # stk_max and stk_drif via .stk_register_runs())
    required = c("months", "cagr", "vol", "sharpe", "ann_rf", "max_dd", "avg_long", "avg_short")
  ),
  list(
    plan_file = "plan_xgb_signal.R", varname = "xgb_units",
    # calc_backtest_metrics(), R/plan_stock_backtest.R:431-449 (shared)
    required = c("months", "cagr", "vol", "sharpe", "ann_rf", "max_dd", "avg_long", "avg_short")
  ),
  list(
    plan_file = "plan_portfolio_opt.R", varname = "pso_units",
    # calc_port_metrics(), R/plan_portfolio_opt.R:287-316 -- `ann_rf` exists
    # on port_metrics but `pso_cols` (an explicit intersect() allow-list,
    # unlike the setdiff()-based exclusion every other writer here uses)
    # never selects it, so this writer does not currently attempt to write
    # ann_rf. Required set reflects only what pso_cols actually selects.
    required = c("months", "opt_cagr", "opt_vol", "opt_sharpe", "opt_maxdd")
  )
)

for (case in unit_map_cases) {
  local({
    this_case <- case
    test_that(
      sprintf("%s covers its metrics target's numeric columns (#691)", this_case$varname),
      {
        file <- file.path(plan_dir, this_case$plan_file)
        units_map <- .extract_units_map(file, this_case$varname)
        missing <- setdiff(this_case$required, names(units_map))
        expect_equal(
          missing, character(0),
          info = sprintf(
            "%s (%s) is missing unit declarations for: %s",
            this_case$varname, this_case$plan_file, paste(missing, collapse = ", ")
          )
        )
      }
    )
  })
}

test_that("mom_prepeak_units declares cagr/vol/max_dd as percent, not fraction (#691)", {
  # .mom_prepeak_compute_metrics() (packages/historicaldata/R/
  # utils_mom_prepeak_metrics.R:128-130) returns round(cagr * 100, 1) etc --
  # PERCENT -- and R/plan_leaderboard.R's .norm_mom_sibling() independently
  # confirms this by dividing cagr/vol/max_dd/ann_rf by 100. The unit map
  # previously declared these three as "fraction", writing values 100x too
  # large into bt.metric under a unit that claimed otherwise (#691's second
  # defect).
  file <- file.path(plan_dir, "plan_mom_prepeak.R")
  units_map <- .extract_units_map(file, "mom_prepeak_units")
  expect_equal(unname(units_map["cagr"]), "percent")
  expect_equal(unname(units_map["vol"]), "percent")
  expect_equal(unname(units_map["max_dd"]), "percent")
})

test_that(".extract_units_map aborts informatively when the variable is not found", {
  file <- file.path(plan_dir, "plan_ltr_momentum.R")
  expect_snapshot(error = TRUE, .extract_units_map(file, "nonexistent_units"))
})
