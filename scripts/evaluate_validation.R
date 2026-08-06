# Manual, one-shot Validation-partition evaluation (#648, boundary moved #660)
#
# ============================================================================
# READ THIS BEFORE RUNNING
# ============================================================================
#
# #660 re-cut the partitions: `val_start` (R/plan_partitions.R bt_partitions)
# moved from 2023-01-01 to 2026-05-01 -- the 2024-2026 span that used to open
# Validation was burned (docs/stock-backtest.qmd published figures from it
# and drew a strategy conclusion; see #660) and is now the `Holdout` tier
# instead (observed, NOT sealed -- see .claude/rules/backtest-partitions.md).
# 2026-05-01 is the first month past the current data boundary (2026-04-15
# equity, 2026-02-27 factor as of #660), so THIS SCRIPT WILL PRINT AN EMPTY
# (all-NA) Validation table until new data arrives past that boundary. That
# is expected, not a bug -- do not treat an empty run as "nothing to
# report"; it means the seal is intact because there is nothing yet to seal.
#
# `.claude/rules/backtest-partitions.md` requires that Validation metrics are
# NEVER computed automatically by `tar_make()` — only via an explicit manual
# target or script, run ONCE, as a final one-shot evaluation before a
# production decision:
#
#   "Once you look at validation results and change the strategy, the
#    validation partition becomes another test set — the seal is broken."
#
# This script IS that sanctioned manual route. It is intentionally NOT
# sourced by docs/_targets.R and is NEVER invoked by `tar_make()` — running
# it is a deliberate act, not a pipeline side-effect. Confirm before running:
#
#   1. You are making (or directly informing) a production go/no-go decision
#      for the strategies below — not idle curiosity, not "just checking".
#   2. You have NOT already seen these Validation numbers this cycle (if you
#      have, e.g. from a scratch `tar_read()`, the seal for THAT cycle is
#      already broken — see JohnGavin/historical#648's own disclosure).
#   3. You will NOT tune, reselect, or otherwise change the strategy after
#      seeing these numbers. If you do, this is no longer a Validation
#      partition — it has become another Testing partition, and any future
#      claim of "sealed one-shot evaluation" for these strategies is false.
#
# If any of the above is not true, STOP. Do not run this script.
#
# Usage:
#   Rscript scripts/evaluate_validation.R
#
# Requires a built targets store (docs/_targets or _targets) containing
# bt_partitions, fm_portfolio, drif_portfolio, stk_max_portfolio,
# stk_drif_portfolio, xgb_drif_portfolio, port_returns, port_optimal_weights.
# It only READS the store — it never calls tar_make().
# ============================================================================

library(targets)
library(dplyr)
library(cli)

source(here::here("R/utils_metrics.R"))

store <- if (dir.exists("docs/_targets")) "docs/_targets" else "_targets"

cli_h1("Manual Validation Evaluation (#648) — SEALED PARTITION")
cli_alert_warning(paste0(
  "Running this script consumes the one-shot Validation seal for every ",
  "strategy below, per .claude/rules/backtest-partitions.md. If you have ",
  "not read the header comment in this file, stop and read it now."
))
cat("Store:", store, "\n\n")

bt_partitions <- tar_read_raw("bt_partitions", store = store)

# COST_PER_MONTH mirrors R/plan_leaderboard.R's calc_cost_metrics() — kept
# in sync manually since that function is a private closure inside the
# `leaderboard` target and not exported. If the convention there changes,
# update this value too.
COST_PER_MONTH <- 0.002

calc_cost_metrics <- function(ret) {
  ret <- ret[!is.na(ret)]
  n <- length(ret)
  if (n == 0L) {
    return(tibble(net_cagr = NA_real_, cum_pnl = NA_real_, cvar_95 = NA_real_))
  }
  net_ret <- ret * (1 - COST_PER_MONTH)
  net_cagr <- prod(1 + net_ret)^(12 / n) - 1
  cum_pnl_net <- prod(1 + net_ret) - 1
  q05 <- quantile(ret, 0.05)
  cvar_95 <- mean(ret[ret <= q05])
  tibble(net_cagr = net_cagr, cum_pnl = cum_pnl_net, cvar_95 = cvar_95)
}

# One Validation row for a strategy's portfolio-return series, bounded at
# val_start with no upper bound — matches R/plan_leaderboard.R's
# `slice_portfolio()` convention (`date >= params$val_start`).
validation_row <- function(strategy, port_df, ret_col_name, val_start) {
  if (is.null(port_df) || !ret_col_name %in% names(port_df)) {
    cli_alert_danger("{strategy}: source portfolio target missing or lacks column {.field {ret_col_name}} — skipped.")
    return(NULL)
  }
  val_data <- port_df[port_df$date >= val_start, ]
  ret <- val_data[[ret_col_name]]
  ann <- annualise_returns(ret, periods_per_year = 12L)
  cost <- calc_cost_metrics(ret)
  tibble(
    strategy = strategy,
    period = "Validation",
    months = ann$n,
    cagr = ann$cagr, vol = ann$vol, sharpe = ann$sharpe, max_dd = ann$max_dd,
    net_cagr = cost$net_cagr, cum_pnl = cost$cum_pnl, cvar_95 = cost$cvar_95
  )
}

fm_portfolio       <- tryCatch(tar_read_raw("fm_portfolio", store = store), error = function(e) NULL)
drif_portfolio     <- tryCatch(tar_read_raw("drif_portfolio", store = store), error = function(e) NULL)
stk_max_portfolio  <- tryCatch(tar_read_raw("stk_max_portfolio", store = store), error = function(e) NULL)
stk_drif_portfolio <- tryCatch(tar_read_raw("stk_drif_portfolio", store = store), error = function(e) NULL)
xgb_drif_portfolio <- tryCatch(tar_read_raw("xgb_drif_portfolio", store = store), error = function(e) NULL)
port_returns          <- tryCatch(tar_read_raw("port_returns", store = store), error = function(e) NULL)
port_optimal_weights  <- tryCatch(tar_read_raw("port_optimal_weights", store = store), error = function(e) NULL)

val_start_factor <- bt_partitions$factor$val_start
val_start_equity <- bt_partitions$equity$val_start

rows <- list(
  validation_row("Factor MAX",  fm_portfolio,       "portfolio_ret", val_start_factor),
  validation_row("Factor DRIF", drif_portfolio,     "portfolio_ret", val_start_factor),
  validation_row("Stock MAX",   stk_max_portfolio,  "port_ret",      val_start_equity),
  validation_row("Stock DRIF",  stk_drif_portfolio, "port_ret",      val_start_equity),
  validation_row("XGB DRIF",    xgb_drif_portfolio, "port_ret",      val_start_equity)
)

# PSO Optimal — derive from port_returns + the optimal weights, mirroring
# R/plan_leaderboard.R's own PSO Optimal cost-slice construction.
if (!is.null(port_returns) && !is.null(port_optimal_weights)) {
  w <- port_optimal_weights
  strat_cols <- names(w)
  opt_returns_df <- port_returns |>
    filter(if_all(all_of(strat_cols), ~ !is.na(.x))) |>
    mutate(opt_ret = as.numeric(as.matrix(pick(all_of(strat_cols))) %*% w))
  rows[[length(rows) + 1L]] <- validation_row(
    "PSO Optimal", opt_returns_df, "opt_ret", val_start_equity
  )
} else {
  cli_alert_warning("PSO Optimal: port_returns or port_optimal_weights missing from store — skipped.")
}

validation_metrics <- bind_rows(rows)

# #660: val_start (2026-05-01) is the first month past the current data
# boundary, so this window is expected to be empty today -- warn explicitly
# rather than letting an all-NA table look like "nothing to report" or a
# silent failure. `validation_row()` always returns a row (months = 0, all
# other columns NA) even for a zero-observation slice, so check `months`
# rather than `nrow()`.
if (nrow(validation_metrics) > 0L &&
    all(is.na(validation_metrics$months) | validation_metrics$months == 0L)) {
  cli_alert_warning(paste0(
    "Validation window (", format(val_start_equity), " onwards) has ZERO ",
    "observations for every strategy -- this is EXPECTED, not an error. ",
    "2026-05-01 is the first month past the current data boundary ",
    "(equity/factor data currently ends ~2026-04-15 / ~2026-02-27, #660). ",
    "The all-NA table below reflects that, not a broken query. Re-run this ",
    "script once new data extends past the Validation boundary."
  ))
}

cli_h2("Validation partition results — SEALED, one-shot")
print(validation_metrics)

cli_alert_warning(paste0(
  "These numbers now count as SEEN. Do not tune, reselect, or otherwise ",
  "change any of the strategies above based on this output — doing so ",
  "breaks the seal (.claude/rules/backtest-partitions.md)."
))

invisible(validation_metrics)
