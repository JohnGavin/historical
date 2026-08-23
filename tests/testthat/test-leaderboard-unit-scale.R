testthat::local_edition(3)
# Tests for the #637 leaderboard unit-scale fix:
#   1. check_leaderboard_metric_ranges() — QA gate S9 (R/plan_qa_gates.R)
#   2. The percent-to-fraction conversion applied inside the .norm_* helpers
#      of R/plan_leaderboard.R (duplicated here as test fixtures, following
#      the pattern established in test-leaderboard-coverage.R, since the
#      real helpers are private closures inside the `leaderboard` tar_target
#      body and cannot be sourced directly without running targets).
#
# See R/plan_leaderboard.R:1-27 (module-level "Unit convention (#637)" note)
# for the canonical-unit contract these tests enforce.

source(here::here("R/plan_qa_gates.R"))

# ── check_leaderboard_metric_ranges() (S9) ────────────────────────────────

good_leaderboard <- tibble::tibble(
  strategy = c("Factor MAX", "LTR", "PSO Optimal"),
  period   = "Full Period",
  cagr     = c(0.0349, 0.0770, 0.0079),
  vol      = c(0.0892, 0.1720, 0.0682),
  max_dd   = c(-0.4047, -0.3630, -0.0994)
)

test_that("check_leaderboard_metric_ranges passes when all metrics are fractional", {
  expect_true(check_leaderboard_metric_ranges(good_leaderboard))
})

test_that("check_leaderboard_metric_ranges throws when required columns are missing", {
  bad <- dplyr::select(good_leaderboard, -max_dd)
  expect_error(
    check_leaderboard_metric_ranges(bad),
    regexp = "max_dd"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_metric_ranges(bad)
  )
})

test_that("check_leaderboard_metric_ranges catches a percent-scale cagr (#637 regression)", {
  # LTR's cagr left un-converted, i.e. 7.70 instead of 0.0770 -- exactly the
  # #637 defect: a strategy's .norm_* helper forgot to divide by 100.
  bad <- good_leaderboard
  bad$cagr[bad$strategy == "LTR"] <- 7.70
  expect_error(
    check_leaderboard_metric_ranges(bad),
    regexp = "LTR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_metric_ranges(bad)
  )
})

test_that("check_leaderboard_metric_ranges catches a percent-scale vol", {
  bad <- good_leaderboard
  bad$vol[bad$strategy == "LTR"] <- 17.20
  expect_error(
    check_leaderboard_metric_ranges(bad),
    regexp = "vol"
  )
})

test_that("check_leaderboard_metric_ranges catches a percent-scale max_dd", {
  bad <- good_leaderboard
  bad$max_dd[bad$strategy == "LTR"] <- -36.30
  expect_error(
    check_leaderboard_metric_ranges(bad),
    regexp = "max_dd"
  )
})

test_that("check_leaderboard_metric_ranges ignores NA values", {
  na_ok <- good_leaderboard
  na_ok$cagr[1] <- NA_real_
  expect_true(check_leaderboard_metric_ranges(na_ok))
})

test_that("check_leaderboard_metric_ranges allows the mom_prepeak bankruptcy floor (max_dd == -1)", {
  floor_ok <- good_leaderboard
  floor_ok$max_dd[1] <- -1.0
  expect_true(check_leaderboard_metric_ranges(floor_ok))
})

test_that("check_leaderboard_metric_ranges rejects max_dd beyond -100%", {
  bad <- good_leaderboard
  bad$max_dd[1] <- -1.5
  expect_error(
    check_leaderboard_metric_ranges(bad),
    regexp = "max_dd"
  )
})

# ── Percent-to-fraction conversion in .norm_* helpers ──────────────────────
# Mirrors the conversion logic added to R/plan_leaderboard.R's .norm_ltr,
# .norm_olmar, .norm_tom, .norm_rsc, .norm_mom_sibling, .norm_aw, .norm_mf,
# and .norm_value helpers. Any change to the real conversion factor MUST be
# reflected here and vice-versa.

.norm_ltr_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |>
    dplyr::rename(sharpe = hac_sharpe) |>
    dplyr::mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100)
}

synthetic_ltr_metrics <- tibble::tibble(
  period     = "Full Period",
  months     = 120L,
  cagr       = 7.70,
  vol        = 17.20,
  max_dd     = -36.30,
  hac_sharpe = 0.45
)

test_that(".norm_ltr converts percent-native source metrics to fraction", {
  res <- .norm_ltr_test(synthetic_ltr_metrics)
  expect_equal(res$cagr, 0.0770, tolerance = 1e-8)
  expect_equal(res$vol, 0.1720, tolerance = 1e-8)
  expect_equal(res$max_dd, -0.3630, tolerance = 1e-8)
  expect_true("sharpe" %in% names(res))
  expect_false("hac_sharpe" %in% names(res))
})

.norm_tom_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |> dplyr::transmute(
    period = period,
    months = n_days,
    cagr   = cagr_tom / 100,
    vol    = vol_tom / 100,
    sharpe = sharpe_tom,
    max_dd = max_dd_tom / 100
  )
}

synthetic_tom_metrics <- tibble::tibble(
  period     = "Full Period",
  n_days     = 250L,
  cagr_tom   = 2.24,
  vol_tom    = 8.01,
  sharpe_tom = 0.28,
  max_dd_tom = -19.27
)

test_that(".norm_tom converts percent-native source metrics to fraction", {
  res <- .norm_tom_test(synthetic_tom_metrics)
  expect_equal(res$cagr, 0.0224, tolerance = 1e-8)
  expect_equal(res$vol, 0.0801, tolerance = 1e-8)
  expect_equal(res$max_dd, -0.1927, tolerance = 1e-8)
  expect_equal(res$sharpe, 0.28)  # sharpe is scale-free, never converted
})

.norm_rsc_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |>
    dplyr::filter(strategy == "SPY_overlay") |>
    dplyr::select(-strategy) |>
    dplyr::rename(months = n_obs) |>
    dplyr::mutate(cagr = cagr / 100, vol = vol / 100, max_dd = max_dd / 100,
                  ann_rf = ann_rf / 100)
}

# n_obs (#726 item 3): rsc_metrics' calc_metrics() (R/plan_risk_state.R) now
# publishes a raw observation count -- previously absent entirely, which is
# why the real .norm_rsc()'s `months` column was always NA (see the
# STRATEGY_OBS_ANN_FACTOR comment in R/plan_leaderboard.R and QA gate S20,
# test-leaderboard-detection-power-values.R).
synthetic_rsc_metrics <- tibble::tibble(
  strategy   = c("SPY_buyhold", "SPY_overlay"),
  period     = c("Full Period", "Full Period"),
  cagr       = c(9.80, 11.30),
  vol        = c(16.00, 13.20),
  sharpe     = c(0.40, 0.55),
  ann_rf     = c(1.80, 1.80),
  max_dd     = c(-30.00, -22.00),
  hac_tstat  = c(1.9, 2.5),
  hac_sharpe = c(0.59, 0.83),
  n_obs      = c(4000L, 4000L)
)

test_that(".norm_rsc converts percent-native source metrics to fraction and renames n_obs to months (#726 item 3)", {
  res <- .norm_rsc_test(synthetic_rsc_metrics)
  expect_equal(nrow(res), 1L)
  expect_equal(res$cagr, 0.1130, tolerance = 1e-8)
  expect_equal(res$vol, 0.1320, tolerance = 1e-8)
  expect_equal(res$max_dd, -0.2200, tolerance = 1e-8)
  expect_equal(res$ann_rf, 0.0180, tolerance = 1e-8)
  expect_true("months" %in% names(res))
  expect_false("n_obs" %in% names(res))
  expect_equal(res$months, 4000L)
})

.norm_mom_sibling_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  m |>
    dplyr::select(-dplyr::any_of("strategy")) |>
    dplyr::transmute(
      period = "Full Period",
      months = n_months,
      cagr   = cagr / 100,
      vol    = vol / 100,
      sharpe = sharpe,
      max_dd = max_dd / 100
    )
}

synthetic_mom_metrics <- tibble::tibble(
  strategy = "mom_prepeak",
  n_months = 200L,
  sharpe   = 0.55,
  cagr     = 9.50,
  vol      = 19.80,
  max_dd   = -68.20
)

test_that(".norm_mom_sibling converts percent-native source metrics to fraction", {
  res <- .norm_mom_sibling_test(synthetic_mom_metrics)
  expect_equal(res$cagr, 0.0950, tolerance = 1e-8)
  expect_equal(res$vol, 0.1980, tolerance = 1e-8)
  expect_equal(res$max_dd, -0.6820, tolerance = 1e-8)
})

test_that(".norm_mom_sibling preserves NA cagr on bankruptcy (max_dd floor -100%)", {
  bankrupt <- synthetic_mom_metrics
  bankrupt$cagr <- NA_real_
  bankrupt$max_dd <- -100.0  # bankruptcy floor stored as percent (-100)
  res <- .norm_mom_sibling_test(bankrupt)
  expect_true(is.na(res$cagr))
  expect_equal(res$max_dd, -1.0, tolerance = 1e-8)
})

# ── cmr_summary is already fractional -- confirm no double-conversion ─────

.norm_cmr_test <- function(m) {
  if (is.null(m) || nrow(m) == 0) return(NULL)
  best <- m |> dplyr::filter(!is.na(sharpe)) |> dplyr::arrange(dplyr::desc(sharpe)) |> dplyr::slice(1)
  if (nrow(best) == 0L) return(NULL)
  best |> dplyr::transmute(
    period = "Full Period",
    months = n_months,
    cagr   = cagr,
    vol    = vol,
    sharpe = sharpe,
    max_dd = max_dd,
    cmr_lookback = lookback
  )
}

synthetic_cmr_summary <- tibble::tibble(
  lookback = c("1m", "3m", "6m"),
  n_months = c(240L, 240L, 240L),
  sharpe   = c(0.20, 0.55, 0.10),
  cagr     = c(-0.02, -0.0079, 0.01),
  vol      = c(0.05, 0.0504, 0.06),
  max_dd   = c(-0.90, -0.9956, -0.80)
)

test_that(".norm_cmr does not rescale already-fractional source metrics", {
  res <- .norm_cmr_test(synthetic_cmr_summary)
  # Best sharpe row is lookback = "3m"
  expect_equal(res$cagr, -0.0079, tolerance = 1e-8)
  expect_equal(res$vol, 0.0504, tolerance = 1e-8)
  expect_equal(res$max_dd, -0.9956, tolerance = 1e-8)
})
