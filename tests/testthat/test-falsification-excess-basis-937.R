testthat::local_edition(3)
# #937 Phase 1 (Refs #919): HAC / DSR / structural-break / stop-rule evidence for
# the three TOTAL-basis daily strategies (Avoid Worst, Risk State, TOM) must be
# computed on the registry's EXCESS series (hd_excess_returns()), never on the
# raw total-return series. Excess-spread strategies (drif, fac_max, ltr, CMR)
# are already excess and must NOT move.
#
# CONVENTIONS (stated per #937): HAC / DSR / structural-break Sharpes use the
# ARITHMETIC per-period mean/sd of the excess series; the stop-rule engine's
# Sharpe is cagr/vol (GEOMETRIC cagr) of the realised series, unchanged.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/plan_falsification.R"))
source(here::here("R/plan_structural_breaks.R"))
source(here::here("R/plan_stop_rule_test.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}
.run_target <- function(plan, name, env_list) {
  cmd <- .target_command(plan, name)
  env <- list2env(env_list, envir = new.env(parent = globalenv()))
  env$library <- function(...) invisible(NULL)  # packages are load_all()'d above
  eval(cmd, envir = env)
}

.rf <- 0.0004
.toy <- function(n = 600L, seed = 937L) {
  set.seed(seed)
  dts <- seq(as.Date("2018-01-01"), by = "day", length.out = n)
  tibble::tibble(date = dts, strategy_ret = stats::rnorm(n, 0.0007, 0.01))
}
.rf_tbl <- function(dts, rf = .rf) tibble::tibble(date = dts, rf = rf)

# ── helper: fals_excess_input() ─────────────────────────────────────────────
test_that("a TOTAL-basis label has rf deducted per observation", {
  inp <- .toy()
  out <- fals_excess_input(inp, .rf_tbl(inp$date), "Avoid Worst")
  expect_equal(out$strategy_ret, inp$strategy_ret - .rf)
  expect_equal(out$date, inp$date)
})

test_that("FALSIFICATION: an EXCESS-basis label is returned unchanged even if rf is large", {
  inp <- .toy()
  out <- fals_excess_input(inp, .rf_tbl(inp$date, rf = 0.01), "LTR")
  expect_equal(out$strategy_ret, inp$strategy_ret)
})

test_that("rf is not 0-filled: unmatched observations are dropped AND counted", {
  inp <- .toy()
  rf  <- .rf_tbl(inp$date)[1:500, ]
  expect_warning(out <- fals_excess_input(inp, rf, "Risk State"),
                 regexp = "dropped 100 of 600")
  expect_equal(nrow(out), 500L)
  expect_false(anyNA(out$strategy_ret))
})

test_that("an unregistered label aborts (fail-loud-not-null)", {
  inp <- .toy()
  # message text is the registry's own (snapshotted in its tests); not duplicated
  # here because it embeds the full, growing registry list.
  expect_error(fals_excess_input(inp, .rf_tbl(inp$date), "No Such Strategy"),
               regexp = "not registered")
})

test_that("a blend label aborts rather than guessing a cash weight", {
  inp <- .toy()
  expect_snapshot(error = TRUE,
                  fals_excess_input(inp, .rf_tbl(inp$date), "CMR Conditioned"))
})

test_that("a malformed rf table aborts naming the missing columns", {
  inp <- .toy()
  expect_snapshot(error = TRUE,
                  fals_excess_input(inp, tibble::tibble(date = inp$date), "TOM"))
})

# ── HAC / DSR targets read the excess series ────────────────────────────────
.pf <- plan_falsification()

test_that("HAC + DSR for avoid_worst / rsc / tom are computed on the excess series", {
  excess <- .toy()
  raw    <- excess; raw$strategy_ret <- raw$strategy_ret + .rf
  cases <- list(
    avoid_worst = list(ex = "fals_avoid_worst_excess", raw = "fals_avoid_worst_input", K = 5L),
    rsc         = list(ex = "fals_rsc_excess",         raw = "fals_rsc_input",         K = 5L),
    tom         = list(ex = "fals_tom_excess",         raw = "fals_tom_input",         K = 6L)
  )
  for (nm in names(cases)) {
    cs <- cases[[nm]]
    # ONLY the excess target exists in the env: a body that still reads the raw
    # input would error with "object not found" (falsification of the wiring).
    env <- stats::setNames(list(excess), cs$ex)
    hac <- .run_target(.pf, paste0("fals_hac_", nm), env)
    dsr <- .run_target(.pf, paste0("fals_dsr_", nm), env)
    expect_equal(hac$hac_tstat,
                 hd_hac_sharpe(excess$strategy_ret)$hac_tstat, info = nm)
    expect_equal(dsr$naive_sharpe,
                 hd_deflated_sharpe(excess$strategy_ret, K_trials = cs$K,
                                    ann_factor = 252L)$naive_sharpe, info = nm)
    # direction: the raw (rf-inclusive) series is strictly more flattering
    raw_hac <- hd_hac_sharpe(raw$strategy_ret)
    expect_lt(hac$hac_tstat, raw_hac$hac_tstat)
  }
})

test_that("excess-spread strategies' HAC / DSR targets are untouched (still read their raw input)", {
  inp <- .toy()
  hac <- .run_target(.pf, "fals_hac_ltr", list(fals_ltr_input = inp))
  expect_equal(hac$hac_tstat, hd_hac_sharpe(inp$strategy_ret)$hac_tstat)
  dsr <- .run_target(.pf, "fals_dsr_drif", list(fals_drif_input = inp))
  expect_equal(dsr$naive_sharpe,
               hd_deflated_sharpe(inp$strategy_ret, K_trials = 5L, ann_factor = 12L)$naive_sharpe)
})

test_that("the three excess bridge targets deduct their OWN strategy's rf (one home)", {
  inp <- .toy()
  rfv <- stats::runif(nrow(inp), 0.0001, 0.0006)
  aw  <- .run_target(.pf, "fals_avoid_worst_excess", list(
    fals_avoid_worst_input = inp,
    aw_daily_rf = tibble::tibble(date = inp$date, rf_ret = rfv)))
  rsc <- .run_target(.pf, "fals_rsc_excess", list(
    fals_rsc_input = inp,
    rsc_portfolio = tibble::tibble(date = inp$date, rf_daily = rfv)))
  tom <- .run_target(.pf, "fals_tom_excess", list(
    fals_tom_input = inp,
    tom_portfolio = tibble::tibble(date = inp$date, rf_ret = rfv)))
  for (o in list(aw, rsc, tom)) expect_equal(o$strategy_ret, inp$strategy_ret - rfv)
})

# ── structural breaks ───────────────────────────────────────────────────────
test_that("sb_strategy_returns: only Avoid Worst / Risk State / TOM are on the excess series", {
  excess <- .toy(); raw <- .toy(seed = 1L)
  env <- list(
    port_returns = NULL, xgb_drif_portfolio = NULL, olmar_portfolio = NULL,
    fals_ltr_input = raw, fals_cmr_input = NULL,
    mom_prepeak_returns = NULL, mom_postpeak_returns = NULL, mom_combined_returns = NULL,
    fals_avoid_worst_excess = excess, fals_rsc_excess = excess, fals_tom_excess = excess
  )
  out <- .run_target(plan_structural_breaks(), "sb_strategy_returns", env)
  expect_equal(out[["Avoid Worst"]]$returns, excess$strategy_ret)
  expect_equal(out[["Risk State"]]$returns, excess$strategy_ret)
  expect_equal(out[["TOM"]]$returns, excess$strategy_ret)
  expect_equal(out[["LTR"]]$returns, raw$strategy_ret)  # excess spread: untouched
})

# ── stop rule ───────────────────────────────────────────────────────────────
test_that("stop_arms_avoid_worst / rsc run on the excess series; ltr still on raw", {
  excess <- .toy(); excess$strategy_ret <- excess$strategy_ret - 0.0006
  ps <- plan_stop_rule_test()
  sp <- .run_target(ps, "stop_params", list())
  expected <- hd_stop_rule_compare_arms(
    excess$strategy_ret, regime = NULL,
    static_thresholds = sp$static_thresholds, cost_bps = sp$cost_bps,
    periods_per_year = 252L, reentry_periods = sp$reentry_periods,
    run_regime_arm = "never")$results
  for (nm in c("avoid_worst", "rsc")) {
    env <- list(stop_params = sp)
    env[[paste0("fals_", nm, "_excess")]] <- excess
    out <- .run_target(ps, paste0("stop_arms_", nm), env)
    expect_equal(out$results$sharpe, expected$sharpe, info = nm)
    expect_equal(out$results$strategy[1], nm)
  }
  ltr_vars <- all.vars(.target_command(ps, "stop_arms_ltr"))
  expect_true("fals_ltr_input" %in% ltr_vars)
})
