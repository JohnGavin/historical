# Tests for .cmr_select_pre_oos_lookback() -- S41/#910 item 1 fix (#917)
#
# S41 (qa_selection_before_oos, R/plan_qa_gates.R) found CMR's best-lookback
# selection (cmr_summary -> .norm_cmr() / borrow_sensitivity_sweep /
# strat_returns_daily_native) picked the max-Sharpe lookback over the FULL,
# unsplit cmr_portfolio_{1m,3m,6m} series -- a genuine instance of the
# "full-sample selection trap" (look-ahead-bias-prevention.md). Owner
# decision 2026-09-27: pick the lookback using ONLY data strictly before the
# project's canonical OOS start (bt_partitions$macro$test_start,
# R/plan_partitions.R). .cmr_select_pre_oos_lookback() is the ONE shared
# selection function every consumer (.norm_cmr()/.norm_cmr_conditioned() in
# R/plan_leaderboard.R, borrow_sensitivity_sweep in R/plan_cost_convention.R,
# strat_returns_daily_native in R/plan_strategy_correlation.R) now reads,
# replacing four independent `which.max(cmr_summary$sharpe)`-style
# re-derivations.
testthat::local_edition(3)

# Path-checked pkgload -- .compute_cmr_metrics() (called internally) needs
# hd_dd_duration() from the historicaldata package. Mirrors test-cmr-units.R.
pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

# ── Fixtures ────────────────────────────────────────────────────────────────
# 24 pre-OOS months (2019-01 .. 2020-12) + 12 post-OOS months (2021-01 ..
# 2021-12), oos_start = 2021-01-01. Deliberately constructed so the
# FULL-SAMPLE winner ("6m") differs from the PRE-OOS winner ("3m") --
# verified empirically (not asserted from theory): 1m has a strong post-OOS
# run that would only be visible to a full-sample selector; 6m has a modest
# but STEADY return in both windows that (wrongly) wins full-sample once the
# strong 1m post-OOS run is folded in, while 3m's markedly higher, low-vol
# pre-OOS return is the correct pre-OOS winner.

.oos_start <- as.Date("2021-01-01")

.mk_cmr_fixture <- function(pre_vals, post_vals) {
  tibble::tibble(
    date = c(
      seq.Date(as.Date("2019-01-01"), by = "month", length.out = 24L),
      seq.Date(as.Date("2021-01-01"), by = "month", length.out = 12L)
    ),
    net_ret = c(pre_vals, post_vals)
  )
}

.cmr_fixture_1m <- .mk_cmr_fixture(rep(c(0.011, -0.009), 12L), rep(0.05, 12L))
.cmr_fixture_3m <- .mk_cmr_fixture(rep(c(0.021,  0.019), 12L), rep(0.00, 12L))
.cmr_fixture_6m <- .mk_cmr_fixture(rep(c(0.006,  0.004), 12L), rep(0.005, 12L))

.cmr_fixture_daily_rf <- tibble::tibble(
  date   = seq.Date(as.Date("2019-01-01"), by = "month", length.out = 36L),
  rf_ret = rep((1.02)^(1 / 12) - 1, 36L)
)

.cmr_fixture_portfolios <- list(
  `1m` = .cmr_fixture_1m, `3m` = .cmr_fixture_3m, `6m` = .cmr_fixture_6m
)

# ── RED: full-sample selection must be rejected ─────────────────────────────

test_that(".cmr_select_pre_oos_lookback picks the PRE-OOS winner, not the full-sample winner (#910/#917/S41)", {
  # Sanity check on the fixture itself: confirm the full-sample winner really
  # does differ from the pre-OOS winner, so this test is not vacuously true.
  full_metrics <- dplyr::bind_rows(lapply(names(.cmr_fixture_portfolios), function(lb) {
    .compute_cmr_metrics(.cmr_fixture_portfolios[[lb]], lookback = lb,
                         daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L,
                         periodicity_check = "warn")
  }))
  full_sample_winner <- full_metrics$lookback[which.max(full_metrics$sharpe)]
  expect_identical(full_sample_winner, "6m")

  result <- .cmr_select_pre_oos_lookback(
    portfolios = .cmr_fixture_portfolios, oos_start = .oos_start,
    daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
  )

  expect_identical(result$chosen, "3m")
  expect_false(identical(result$chosen, full_sample_winner))
})

test_that(".cmr_select_pre_oos_lookback's choice is unaffected by ANY change to post-OOS data (selection uses only pre-OOS rows)", {
  baseline <- .cmr_select_pre_oos_lookback(
    portfolios = .cmr_fixture_portfolios, oos_start = .oos_start,
    daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
  )

  # Wildly different post-OOS returns for every lookback -- if the selection
  # used ANY post-OOS row, this would change the outcome.
  mutated <- lapply(.cmr_fixture_portfolios, function(p) {
    n <- nrow(p)
    p$net_ret[p$date >= .oos_start] <- -0.99  # catastrophic post-OOS crash
    p
  })

  mutated_result <- .cmr_select_pre_oos_lookback(
    portfolios = mutated, oos_start = .oos_start,
    daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
  )

  expect_identical(mutated_result$chosen, baseline$chosen)
  expect_equal(mutated_result$pre_oos_sharpe, baseline$pre_oos_sharpe)
})

# ── Diagnostics never hide the losers ───────────────────────────────────────

test_that(".cmr_select_pre_oos_lookback's diagnostics report all 3 candidates, not just the winner", {
  result <- .cmr_select_pre_oos_lookback(
    portfolios = .cmr_fixture_portfolios, oos_start = .oos_start,
    daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
  )

  expect_identical(nrow(result$diagnostics), 3L)
  expect_setequal(result$diagnostics$lookback, c("1m", "3m", "6m"))
  expect_true(all(result$diagnostics$scored))
})

test_that(".cmr_select_pre_oos_lookback reports (but excludes) a lookback with too little pre-OOS data", {
  # Truncate 1m's pre-OOS history to 8 rows (< 12, .compute_cmr_metrics()'s
  # own minimum) while leaving 3m/6m with the full 24-row pre-OOS window.
  thin_1m <- .cmr_fixture_1m[.cmr_fixture_1m$date >= as.Date("2020-05-01"), ]
  portfolios_thin <- list(`1m` = thin_1m, `3m` = .cmr_fixture_3m, `6m` = .cmr_fixture_6m)

  expect_message(
    result <- .cmr_select_pre_oos_lookback(
      portfolios = portfolios_thin, oos_start = .oos_start,
      daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
    ),
    "could not be scored"
  )

  expect_identical(result$chosen, "3m")
  expect_identical(nrow(result$diagnostics), 3L)  # loser (1m) still reported
  expect_false(result$diagnostics$scored[result$diagnostics$lookback == "1m"])
})

# ── Fail loud, never fall back to full-sample selection ─────────────────────

test_that(".cmr_select_pre_oos_lookback aborts when NO lookback can be scored pre-OOS, never falling back to full-sample selection", {
  # All three candidates have < 12 pre-OOS rows.
  starved <- lapply(.cmr_fixture_portfolios, function(p) {
    p[p$date >= as.Date("2020-10-01") & p$date < .oos_start, ]
  })

  expect_snapshot(
    error = TRUE,
    .cmr_select_pre_oos_lookback(
      portfolios = starved, oos_start = .oos_start,
      daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
    )
  )
})

# ── cutoff_date / first_oos_date feed the S41 gate directly ────────────────

test_that(".cmr_select_pre_oos_lookback's cutoff_date is strictly before first_oos_date, by construction", {
  result <- .cmr_select_pre_oos_lookback(
    portfolios = .cmr_fixture_portfolios, oos_start = .oos_start,
    daily_rf = .cmr_fixture_daily_rf, ann_factor = 12L, label = "CMR"
  )

  expect_identical(result$first_oos_date, .oos_start)
  expect_true(result$cutoff_date < result$first_oos_date)
  # The max date actually used is the last pre-OOS observation (2020-12-01).
  expect_identical(result$cutoff_date, as.Date("2020-12-01"))
})
