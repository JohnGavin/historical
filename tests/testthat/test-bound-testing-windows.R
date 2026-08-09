testthat::local_edition(3)
# Regression tests for #667: Risk State's (and five siblings') unbounded
# "Testing"/"OOS" metric window.
#
# Background (#667): R/plan_risk_state.R's `rsc_metrics` computed its
# "Testing" row from `port$date >= oos_start` with NO upper bound, so the
# canonical `Testing` label silently spanned the entire post-2020 series --
# swallowing Holdout AND (once populated) the sealed Validation partition.
# R/plan_avoid_worst.R (`aw_metrics`) had the identical shape. Both are fixed
# by wiring `test_end` from `bt_partitions` into the strategy's params target
# and bounding the window at `date <= test_end` (the pattern PR #649
# established for `mf_metrics`/`ev_metrics`, #645).
#
# The issue asks for a regression test that perturbs `test_end` and asserts
# every Testing window moves with it. Two complementary checks below:
#
#   1. Params-wiring: for every #667-touched params target, `test_end` in the
#      returned list must track `bt_partitions[[<class>]]$test_end` rather
#      than being a literal -- evaluated directly against two different mock
#      `bt_partitions` objects, without running tar_make().
#   2. Behavioural: for the three targets that read `test_end` most directly
#      (`rsc_metrics`, `aw_metrics`, `fip_comparison`), the target's own
#      command expression is extracted from its plan_*() function and
#      eval()'d against synthetic upstream data across two different
#      `test_end` values -- the emitted Testing/OOS row's `window_end` must
#      equal the perturbed `test_end` (not the data's own max date), and must
#      differ between the two perturbations.
#
# `mr_metrics`, `rafi_metrics`, `eur_results`, `eur_comparison`, and
# `eur_ciss_results` follow the identical bounded pattern (see #667 PR
# report) and are covered by check 1 (params-wiring) here plus the
# S11_METRICS_REGISTRY gate itself (test-metric-window-bounds.R), which
# aborts tar_make() if ANY registered target's window extends past
# test_end -- full behavioural re-derivation for all eight targets was
# judged not to add proportionate signal over these two layers together.

source(here::here("R/plan_qa_gates.R"))
source(here::here("R/plan_risk_state.R"))
source(here::here("R/plan_avoid_worst.R"))
source(here::here("R/plan_fip_screen.R"))
source(here::here("R/plan_mean_reversion.R"))
source(here::here("R/plan_rafi.R"))
source(here::here("R/plan_european_overlay.R"))

# ── Helpers ────────────────────────────────────────────────────────────────

# Extract a target's raw (unevaluated) command call from a plan_*() target
# list, by target name -- lets us exercise the exact shipped command against
# synthetic data without running tar_make()/needing a materialised store.
.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) {
    stop("target '", name, "' not found (or not unique) in this plan's target list")
  }
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# Minimal stand-in for historicaldata::hd_hac_sharpe() -- rsc_metrics calls
# it for hac_tstat/hac_sharpe columns this test does not assert on. Real HAC
# math is out of scope here; only the window bound is under test.
.mock_hac_sharpe <- function(ret_vec) {
  list(hac_tstat = 0, naive_sharpe = mean(ret_vec) / stats::sd(ret_vec) * sqrt(252))
}

# ── 1. Params-wiring: test_end tracks bt_partitions, not a literal ─────────

test_that("rsc_params$test_end tracks bt_partitions$macro$test_end", {
  cmd <- .target_command(plan_risk_state(), "rsc_params")
  p_a <- .eval_command(cmd, bt_partitions = list(macro = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2023-12-31")
  )))
  p_b <- .eval_command(cmd, bt_partitions = list(macro = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2021-06-30")
  )))
  expect_equal(p_a$test_end, as.Date("2023-12-31"))
  expect_equal(p_b$test_end, as.Date("2021-06-30"))
  expect_false(identical(p_a$test_end, p_b$test_end))
})

test_that("aw_params$test_end tracks bt_partitions$equity$test_end", {
  cmd <- .target_command(plan_avoid_worst(), "aw_params")
  p_a <- .eval_command(cmd, bt_partitions = list(equity = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2023-12-31")
  )))
  p_b <- .eval_command(cmd, bt_partitions = list(equity = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2021-06-30")
  )))
  expect_equal(p_a$test_end, as.Date("2023-12-31"))
  expect_equal(p_b$test_end, as.Date("2021-06-30"))
  expect_false(identical(p_a$test_end, p_b$test_end))
})

test_that("mr_params$test_end tracks bt_partitions$equity$test_end", {
  cmd <- .target_command(plan_mean_reversion(), "mr_params")
  mock_partitions <- function(test_end) {
    list(equity = list(
      train_end = as.Date("2019-12-31"), test_start = as.Date("2020-01-01"),
      test_end = test_end, val_start = as.Date("2026-05-01")
    ))
  }
  p_a <- .eval_command(cmd, bt_partitions = mock_partitions(as.Date("2023-12-31")))
  p_b <- .eval_command(cmd, bt_partitions = mock_partitions(as.Date("2021-06-30")))
  expect_equal(p_a$test_end, as.Date("2023-12-31"))
  expect_equal(p_b$test_end, as.Date("2021-06-30"))
})

test_that("rafi_params$test_end tracks bt_partitions$factor$test_end (oos_start stays fixed)", {
  cmd <- .target_command(plan_rafi(), "rafi_params")
  p_a <- .eval_command(cmd, bt_partitions = list(factor = list(test_end = as.Date("2023-12-31"))))
  p_b <- .eval_command(cmd, bt_partitions = list(factor = list(test_end = as.Date("2021-06-30"))))
  expect_equal(p_a$test_end, as.Date("2023-12-31"))
  expect_equal(p_b$test_end, as.Date("2021-06-30"))
  # oos_start is a deliberate fixed constant (2010-01-01, "RAFI products
  # widely known by then"), not derived from bt_partitions -- must NOT move.
  expect_equal(p_a$oos_start, as.Date("2010-01-01"))
  expect_equal(p_b$oos_start, as.Date("2010-01-01"))
})

test_that("eur_params$test_end tracks bt_partitions$macro$test_end", {
  cmd <- .target_command(plan_european_overlay(), "eur_params")
  p_a <- .eval_command(cmd, bt_partitions = list(macro = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2023-12-31")
  )))
  p_b <- .eval_command(cmd, bt_partitions = list(macro = list(
    test_start = as.Date("2020-01-01"), test_end = as.Date("2021-06-30")
  )))
  expect_equal(p_a$test_end, as.Date("2023-12-31"))
  expect_equal(p_b$test_end, as.Date("2021-06-30"))
})

# ── 2. Behavioural: perturbing test_end moves the emitted Testing window ───

test_that("rsc_metrics' Testing window_end moves when rsc_params$test_end is perturbed", {
  cmd <- .target_command(plan_risk_state(), "rsc_metrics")

  dates <- seq(as.Date("2018-01-01"), as.Date("2026-06-30"), by = "day")
  set.seed(667)
  port <- tibble::tibble(
    date = dates,
    ret_buyhold  = stats::rnorm(length(dates), 0.0003, 0.01),
    ret_strategy = stats::rnorm(length(dates), 0.0003, 0.01)
  )
  overlay <- tibble::tibble(
    date = dates,
    ret_raw     = stats::rnorm(length(dates), 0.0003, 0.01),
    ret_overlay = stats::rnorm(length(dates), 0.0003, 0.01)
  )

  run <- function(test_end) {
    result <- .eval_command(
      cmd,
      hd_hac_sharpe        = .mock_hac_sharpe,
      rsc_params            = list(oos_start = as.Date("2020-01-01"), test_end = test_end),
      rsc_portfolio          = port,
      rsc_overlay_drif       = overlay,
      rsc_overlay_fac_max    = overlay
    )
    result[result$strategy == "SPY_buyhold" & result$period == "Testing", ]
  }

  test_a <- run(as.Date("2023-12-31"))
  test_b <- run(as.Date("2021-06-30"))

  expect_equal(nrow(test_a), 1L)
  expect_equal(nrow(test_b), 1L)
  expect_equal(test_a$window_end, as.Date("2023-12-31"))
  expect_equal(test_b$window_end, as.Date("2021-06-30"))
  expect_false(identical(test_a$window_end, test_b$window_end))
  # Never leaks past the perturbed test_end even though synthetic data
  # extends to 2026-06-30 -- the #667 defect this test guards against.
  expect_lte(test_a$window_end, as.Date("2023-12-31"))
  expect_lte(test_b$window_end, as.Date("2021-06-30"))
})

test_that("aw_metrics' Testing window_end moves when aw_params$test_end is perturbed", {
  cmd <- .target_command(plan_avoid_worst(), "aw_metrics")

  dates <- seq(as.Date("2018-01-01"), as.Date("2026-06-30"), by = "day")
  set.seed(667)
  aw_daily_returns <- tibble::tibble(
    ticker = "SPY",
    date   = dates,
    ret    = stats::rnorm(length(dates), 0.0003, 0.01)
  )

  run <- function(test_end) {
    result <- .eval_command(
      cmd,
      aw_daily_returns = aw_daily_returns,
      aw_params        = list(oos_start = as.Date("2020-01-01"), test_end = test_end)
    )
    result[result$period == "Testing" & result$scenario == "All Days", ]
  }

  test_a <- run(as.Date("2023-12-31"))
  test_b <- run(as.Date("2021-06-30"))

  expect_equal(nrow(test_a), 1L)
  expect_equal(nrow(test_b), 1L)
  expect_equal(test_a$window_end, as.Date("2023-12-31"))
  expect_equal(test_b$window_end, as.Date("2021-06-30"))
  expect_false(identical(test_a$window_end, test_b$window_end))
})

test_that("fip_comparison's OOS window_end moves when bt_partitions$equity$test_end is perturbed", {
  cmd <- .target_command(plan_fip_screen(), "fip_comparison")

  months <- seq(as.Date("2015-01-01"), as.Date("2026-06-01"), by = "month")
  set.seed(667)
  fip_returns <- tibble::tibble(
    exec_date = months,
    ret_ls    = stats::rnorm(length(months), 0.005, 0.02)
  )
  mom_combined_returns <- tibble::tibble(
    exec_date = months,
    ret_ls    = stats::rnorm(length(months), 0.004, 0.02)
  )

  run <- function(test_end) {
    result <- .eval_command(
      cmd,
      bt_partitions = list(equity = list(
        test_start = as.Date("2020-01-01"), test_end = test_end
      )),
      fip_returns           = fip_returns,
      mom_combined_returns  = mom_combined_returns
    )
    result[result$period == "OOS", ]
  }

  test_a <- run(as.Date("2023-12-31"))
  test_b <- run(as.Date("2021-06-30"))

  expect_true(all(test_a$window_end <= as.Date("2023-12-31")))
  expect_true(all(test_b$window_end <= as.Date("2021-06-30")))
  expect_false(identical(sort(test_a$window_end), sort(test_b$window_end)))
})
