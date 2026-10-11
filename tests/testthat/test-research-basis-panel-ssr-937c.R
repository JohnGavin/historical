testthat::local_edition(3)
# #937 phase 2, group C (part 2): asset-panel diagnostics and the Sharpe
# Stability Ratio (SSR).
#
#  * cov_diag_4asset / cov_diag_wide / ws_diag_raw hand a matrix of TOTAL
#    (adjusted-close) asset returns to hd_cov_oos_diagnostic() /
#    hd_weight_stability_diagnostic(), whose oos_sharpe is mean/sd*sqrt(12) of
#    whatever it is given. The callers must pass EXCESS returns. For the
#    tangency-style methods (raw_mvo, shrunk_mu) the WEIGHTS depend on mu, so
#    rf changes more than the level of the Sharpe.
#  * SSR = mean(rolling Sharpe) / HAC se. A rolling Sharpe of a TOTAL series
#    carries the cash return, so the numerator is inflated. top5pct_share is a
#    concentration of compounded return, not a Sharpe, and is left on the
#    published series.
# All data are synthetic (hermetic).

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/cov_config.R"))
source(here::here("R/plan_cov_diagnostic.R"))
source(here::here("R/plan_weight_stability_vignette.R"))
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_strategy_correlation.R"))
source(here::here("R/plan_leaderboard.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}
.run <- function(cmd, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

PANEL_LABEL <- "Research: asset panel (adjusted-close returns)"

# ── Toy asset panel: 4 assets, 100 months, a time-varying rf ────────────────
.panel_toy <- function(n = 100L) {
  set.seed(9376)
  dates <- seq(as.Date("2005-02-01"), by = "month", length.out = n) - 1  # month ends
  ym <- format(dates, "%Y-%m")
  rf <- 0.002 + 0.0015 * sin(seq_len(n) / 6)
  mu <- c(0.006, 0.004, 0.003, 0.005)
  wide <- tibble::tibble(
    date = dates,
    SPY = rf + stats::rnorm(n, mu[1], 0.04),
    TLT = rf + stats::rnorm(n, mu[2], 0.03),
    GLD = rf + stats::rnorm(n, mu[3], 0.05),
    DBC = rf + stats::rnorm(n, mu[4], 0.05)
  )
  # rf published for the panel's months plus a margin on both sides
  rf_ym <- format(seq(as.Date("2004-01-01"), by = "month", length.out = n + 24L), "%Y-%m")
  rf_tbl <- tibble::tibble(ym = rf_ym, rf_ret = c(rep(0.002, 12L), rf, rep(0.002, 12L)))
  list(wide = wide, rf_tbl = rf_tbl, rf = rf, ym = ym)
}
.manual_excess <- function(toy) {
  m <- as.matrix(toy$wide[, c("SPY", "TLT", "GLD", "DBC")])
  m - toy$rf
}
.quiet <- function(expr) suppressMessages(suppressWarnings(expr))

test_that(".excess_asset_panel subtracts the month's rf from every asset column, keeps date", {
  toy <- .panel_toy()
  out <- .excess_asset_panel(toy$wide, toy$rf_tbl, PANEL_LABEL, "toy panel")
  expect_named(out, c("date", "SPY", "TLT", "GLD", "DBC"))
  expect_equal(out$date, toy$wide$date)
  expect_equal(as.matrix(out[, -1]), .manual_excess(toy), ignore_attr = TRUE)
  expect_false(isTRUE(all.equal(out$SPY, toy$wide$SPY)))   # FALSIFICATION: not a no-op
})

test_that(".excess_asset_panel trims (with a counted warning) months with no rf yet, never 0-fills", {
  toy <- .panel_toy()
  rf_short <- toy$rf_tbl[toy$rf_tbl$ym <= toy$ym[length(toy$ym) - 2L], ]
  expect_warning(
    out <- .excess_asset_panel(toy$wide, rf_short, PANEL_LABEL, "toy panel"),
    "trailing"
  )
  expect_equal(nrow(out), nrow(toy$wide) - 2L)
})

test_that(".excess_asset_panel aborts on an unregistered label and on a missing date column", {
  toy <- .panel_toy()
  expect_snapshot(error = TRUE, .excess_asset_panel(toy$wide, toy$rf_tbl, "Not Registered", "toy panel"))
  expect_snapshot(error = TRUE, .excess_asset_panel(toy$wide[, -1], toy$rf_tbl, PANEL_LABEL, "toy panel"))
})

test_that("cov_diag_4asset diagnoses the EXCESS panel, not the total-return panel", {
  toy <- .panel_toy()
  out <- .quiet(.run(.target_command(plan_cov_diagnostic(), "cov_diag_4asset"),
                     asset_monthly_returns_wide = toy$wide, stk_rf = toy$rf_tbl))
  exp_ex  <- .quiet(hd_cov_oos_diagnostic(.manual_excess(toy), train_window = 60L,
                                           lw_target = COV_LW_TARGET))
  exp_raw <- .quiet(hd_cov_oos_diagnostic(as.matrix(toy$wide[, -1]), train_window = 60L,
                                           lw_target = COV_LW_TARGET))
  expect_equal(out$oos_sharpe, exp_ex$oos_sharpe)
  expect_equal(out$oos_mean, exp_ex$oos_mean)
  expect_gt(max(abs(out$oos_sharpe - exp_raw$oos_sharpe)), 0.05)   # FALSIFICATION
})

test_that("cov_diag_wide diagnoses the EXCESS wide panel", {
  toy <- .panel_toy()
  out <- .quiet(.run(.target_command(plan_cov_diagnostic(), "cov_diag_wide"),
                     cov_diag_wide_panel = toy$wide, stk_rf = toy$rf_tbl))
  exp_ex <- .quiet(hd_cov_oos_diagnostic(.manual_excess(toy), train_window = 60L,
                                          lw_target = COV_LW_TARGET))
  expect_equal(out$oos_sharpe, exp_ex$oos_sharpe)
})

test_that("ws_diag_raw runs the weight-stability diagnostic on the EXCESS panel (weights too)", {
  toy <- .panel_toy()
  out <- .quiet(.run(.target_command(plan_weight_stability_vignette(), "ws_diag_raw"),
                     asset_monthly_returns_wide = toy$wide, stk_rf = toy$rf_tbl))
  exp_ex  <- .quiet(hd_weight_stability_diagnostic(.manual_excess(toy), train_window = 60L))
  exp_raw <- .quiet(hd_weight_stability_diagnostic(as.matrix(toy$wide[, -1]), train_window = 60L))
  expect_equal(out$oos_sharpe, exp_ex$oos_sharpe)
  expect_equal(out$avg_turnover, exp_ex$avg_turnover)
  expect_gt(max(abs(out$oos_sharpe - exp_raw$oos_sharpe)), 0.05)   # FALSIFICATION
  # raw_mvo is mu-driven: its WEIGHTS (turnover) differ once rf is removed, so
  # "the level only changes" would be the wrong description of this fix.
  expect_false(isTRUE(all.equal(
    out$avg_turnover[out$method == "raw_mvo"], exp_raw$avg_turnover[exp_raw$method == "raw_mvo"]
  )))
})

# ── .ssr_excess_returns (registry recorders) ────────────────────────────────
test_that(".ssr_excess_returns deducts rf for a TOTAL label and not for an EXCESS label", {
  ret <- c(0.010, 0.020, -0.010, 0.005)
  rf  <- c(0.003, 0.004,  0.002, 0.003)
  expect_equal(.ssr_excess_returns(ret, rf, "Value (HML)", "t"), ret - rf)
  expect_identical(.ssr_excess_returns(ret, rf, "Mom Pre-Peak", "t"), ret)
})

test_that(".ssr_excess_returns warns (counted) when rf is missing for a return, never 0-fills", {
  ret <- c(0.010, 0.020, -0.010, 0.005)
  rf  <- c(0.003, NA, 0.002, NA)
  expect_warning(out <- .ssr_excess_returns(ret, rf, "Value (HML)", "t"), "2 observation")
  expect_equal(out, c(0.007, NA, -0.012, NA))
})

test_that(".ssr_excess_returns aborts on an unregistered label and a length mismatch", {
  expect_snapshot(error = TRUE, .ssr_excess_returns(c(1, 2), c(1, 2), "Not Registered", "t"))
  expect_snapshot(error = TRUE, .ssr_excess_returns(c(1, 2, 3), c(1, 2), "Value (HML)", "t"))
  expect_snapshot(error = TRUE, .ssr_excess_returns(c(1, 2), NULL, "Value (HML)", "t"))
})

test_that("the six total-basis registry recorders feed SSR an EXCESS series", {
  # Each recorder must build `rets` through .ssr_excess_returns() with its own
  # registered label and pass THAT to hd_record_stability_metrics().
  want <- list(
    list(file = "R/plan_ev_ebit.R",         fn = ".ev_register_runs",          label = "Value (HML)"),
    list(file = "R/plan_managed_futures.R", fn = ".mf_register_runs",          label = "Managed Futures"),
    list(file = "R/plan_olmar.R",           fn = ".olmar_register_runs",       label = "OLMAR-1"),
    list(file = "R/plan_turn_of_month.R",   fn = ".tom_register_runs",         label = "TOM"),
    list(file = "R/plan_avoid_worst.R",     fn = ".avoid_worst_register_runs", label = "Avoid Worst"),
    list(file = "R/plan_risk_state.R",      fn = ".rsc_register_runs",         label = "Risk State")
  )
  find_calls <- function(expr, name, acc = list()) {
    if (is.call(expr)) {
      if (identical(expr[[1]], as.name(name))) acc <- c(acc, list(expr))
      parts <- as.list(expr)
      for (i in seq_along(parts)) {
        if (identical(parts[[i]], quote(expr = ))) next   # empty arg, e.g. x[, 1]
        acc <- find_calls(parts[[i]], name, acc)
      }
    }
    acc
  }
  for (w in want) {
    exprs <- parse(here::here(w$file), keep.source = FALSE)
    defs <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) &&
                     identical(as.character(e[[2]]), w$fn), as.list(exprs))
    expect_length(defs, 1L)
    body_expr <- defs[[1]][[3]]
    ex_calls <- find_calls(body_expr, ".ssr_excess_returns")
    expect_length(ex_calls, 1L)
    expect_true(w$label %in% vapply(ex_calls[[1]], function(a) if (is.character(a)) a else "", ""),
                info = paste(w$fn, "must use its own label", w$label))
    rec <- find_calls(body_expr, "hd_record_stability_metrics")
    expect_length(rec, 1L)
    expect_identical(rec[[1]]$returns, as.name("rets"), info = w$fn)
  }
})

# ── Leaderboard SSR: excess for the SSR numerator, published series for top5 ─
test_that(".ssr_ext_entries scores SSR and top5 on the excess column (one basis, like the registry writer)", {
  set.seed(9377)
  n <- 120L
  rf <- rep(0.003, n)
  wide <- tibble::tibble(ym = format(seq(as.Date("2010-01-15"), by = "month", length.out = n), "%Y-%m"),
                         value_hml = rf + stats::rnorm(n, 0.002, 0.03),
                         cmr = stats::rnorm(n, 0.002, 0.03))
  wide_ex <- wide
  wide_ex$value_hml <- wide$value_hml - rf
  ssr   <- function(r, label) hd_sharpe_stability_ratio(r[!is.na(r)], w = 36L, ann_factor = 12L)$ssr
  top5  <- function(r) hd_top5pct_share(r[!is.na(r)])$top_share
  out <- .ssr_ext_entries(wide, wide_ex, c(value_hml = "Value (HML)", cmr = "CMR"), ssr, top5)
  expect_named(out, c("Value (HML)", "CMR"))
  expect_equal(out[["Value (HML)"]]$ssr, ssr(wide_ex$value_hml))
  expect_equal(out[["Value (HML)"]]$top5, top5(wide_ex$value_hml))
  expect_gt(abs(out[["Value (HML)"]]$ssr - ssr(wide$value_hml)), 0.05)  # FALSIFICATION
  expect_false(isTRUE(all.equal(out[["Value (HML)"]]$top5, top5(wide$value_hml))))
  expect_equal(out[["CMR"]]$ssr, ssr(wide$cmr))                         # excess spread: unchanged
})

test_that(".ssr_ext_entries aborts if the excess table lacks a column the wide table has", {
  wide <- tibble::tibble(ym = "2010-01", value_hml = 0.01)
  wide_ex <- tibble::tibble(ym = "2010-01")
  expect_snapshot(
    error = TRUE,
    .ssr_ext_entries(wide, wide_ex, c(value_hml = "Value (HML)"), function(r, l) 1, function(r) 1)
  )
})

test_that("strat_returns_wide_excess puts total-basis columns on the excess basis", {
  set.seed(9378)
  n <- 120L
  rf <- 0.004
  yms <- format(seq(as.Date("2010-01-15"), by = "month", length.out = n), "%Y-%m")
  s <- stats::rnorm(n, 0.004, 0.03)
  dts <- seq(as.Date("2010-01-01"), by = "day", length.out = 400L)
  toy <- list(
    STRAT_RETURNS_WIDE_CODES = c("stk_max", "value_hml"),
    strat_returns_wide = tibble::tibble(ym = yms, stk_max = s, value_hml = rf + s - 0.002),
    strat_returns_daily_native = list(
      cmr_conditioned = tibble::tibble(date = dts, ret = 0, cash_weight = 0.5, rf_ret = rf / 20)
    ),
    ev_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf),
    mf_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf),
    olmar_portfolio = tibble::tibble(date = dts, rf_ret = rf / 20),
    tom_portfolio = tibble::tibble(date = dts, rf_ret = rf / 20),
    rsc_portfolio = tibble::tibble(date = dts, rf_daily = rf / 20),
    aw_daily_rf = tibble::tibble(date = dts, rf_ret = rf / 20)
  )
  cmd <- .target_command(plan_strategy_correlation(), "strat_returns_wide_excess")
  out <- eval(cmd, envir = list2env(toy, envir = new.env(parent = globalenv())))
  expect_equal(out$stk_max, s)                      # excess spread: unchanged
  expect_equal(out$value_hml, s - 0.002)            # total: rf removed
  expect_equal(out$ym, yms)
})

test_that("STRAT_CODE_LABELS is the one code_name -> registry label map and every label is registered", {
  expect_true(all(STRAT_RETURNS_WIDE_CODES %in% names(STRAT_CODE_LABELS)))
  for (lab in STRAT_CODE_LABELS) expect_no_error(hd_return_basis_of(lab))
})
