# Tests for cmr_summary unit convention — #336
# Tests for the #677 slice-3 rf migration (arithmetic -> geometric, real rf)
#
# .compute_cmr_metrics() in R/plan_commodities_mean_reversion.R produces
# the per-lookback metric row that flows into the cmr_summary target and
# from there to the leaderboard, cmr_vs_mom_compare, and bt.run registry.
#
# Before #336: cagr, vol, max_dd were stored as percent (e.g., -100 = -100%).
# After  #336: stored as decimal fractions (e.g., -1.0 = -100%), matching
# plan_factormax.R, plan_drif.R, commodities_momentum.R, and the leaderboard
# normalizers.
#
# Before #677: sharpe used an arithmetic-mean numerator and a hardcoded
# "MANUAL: no source" 2%/yr risk-free assumption. After #677: geometric
# numerator (sharpe_ratio_rf(), R/utils_metrics.R) and a real Fama-French rf.
#
# #722: #677 joined the real rf, but on the wrong frequency -- the MONTHLY
# stk_rf target against CMR's own DAILY portfolios (#717), producing a
# physically-impossible ~41% annualised risk-free rate. Fixed by joining the
# DAILY daily_rf target on `date` instead of stk_rf on `ym`. These fixture
# names below use `daily_rf`/`date` throughout -- ann_factor = 12L in most
# tests here is retained only as a convenient toy-fixture annualisation
# constant (the toy portfolio has monthly-spaced dates), not because CMR
# itself is monthly; CMR's production ann_factor is 252L (see #717).
testthat::local_edition(3)

# Path-checked pkgload — .compute_cmr_metrics() calls hd_dd_duration() from
# the historicaldata package, so the package must be loaded before sourcing
# the plan file. Mirrors the pattern used in vignette setup chunks.
pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

# Minimal toy portfolio: 24 monthly net returns in a tibble shape that
# .compute_cmr_metrics() consumes. Returns drawn so that max_dd lands well
# inside the (-1, 0] decimal band — under the old percent convention this
# would be ~−45 instead of ~−0.45.
toy_portfolio <- tibble::tibble(
  date    = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 24L),
  net_ret = c(rep(-0.05, 12L), rep(0.02, 12L))  # 12mo drawdown then recovery
)

toy_daily_rf <- tibble::tibble(
  date   = seq.Date(as.Date("2020-01-01"), by = "month", length.out = 24L),
  rf_ret = rep((1.02)^(1 / 12) - 1, 24L)  # ~2%/yr monthly-equivalent rf -- matches the old hardcoded constant
)

test_that(".compute_cmr_metrics returns max_dd as decimal fraction (#336)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", daily_rf = toy_daily_rf, ann_factor = 12L)
  expect_true(is.finite(metrics$max_dd))
  expect_gte(metrics$max_dd, -1)    # canonical decimal: in [-1, 0]
  expect_lte(metrics$max_dd, 0)
})

test_that(".compute_cmr_metrics returns cagr/vol as decimal fractions (#336)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", daily_rf = toy_daily_rf, ann_factor = 12L)
  # Decimal CAGR for monthly returns near ±5% sits in (-1, 1); under the old
  # percent convention this would land in the (-100, 100) band.
  expect_gt(metrics$cagr, -1)
  expect_lt(metrics$cagr,  1)
  # Annualised vol of a 5% / 2% monthly series is well below 1 in decimal.
  expect_gt(metrics$vol, 0)
  expect_lt(metrics$vol, 1)
})

test_that(".compute_cmr_metrics never returns the old percent magnitude (#336 regression)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", daily_rf = toy_daily_rf, ann_factor = 12L)
  # Specific anti-regression: -100 was the old percent output for this kind
  # of monotone-loss path; the decimal equivalent is around -0.45.
  expect_false(metrics$max_dd < -1.0)
  expect_false(abs(metrics$cagr) > 1.0)
  expect_false(metrics$vol > 1.0)
})

# ── #677: geometric numerator, rf-deducted ──────────────────────────────────

test_that(".compute_cmr_metrics sharpe matches sharpe_ratio_rf() exactly", {
  metrics  <- .compute_cmr_metrics(toy_portfolio, lookback = "test", daily_rf = toy_daily_rf, ann_factor = 12L)
  expected <- round(
    sharpe_ratio_rf(toy_portfolio$net_ret, toy_daily_rf$rf_ret, periods_per_year = 12L)$sharpe,
    3
  )
  expect_equal(metrics$sharpe, expected)
})

test_that(".compute_cmr_metrics sharpe differs from the old arithmetic/hardcoded-rf formula on a volatile fixture", {
  set.seed(3)
  vol_ret <- rnorm(30, mean = -0.005, sd = 0.10)  # deliberately volatile
  vol_portfolio <- tibble::tibble(
    date    = seq.Date(as.Date("2018-01-01"), by = "month", length.out = 30L),
    net_ret = vol_ret
  )
  vol_daily_rf <- tibble::tibble(
    date   = seq.Date(as.Date("2018-01-01"), by = "month", length.out = 30L),
    rf_ret = rep((1.02)^(1 / 12) - 1, 30L)
  )

  new_sharpe <- .compute_cmr_metrics(vol_portfolio, lookback = "test", daily_rf = vol_daily_rf, ann_factor = 12L)$sharpe

  monthly_rf_old <- (1.02)^(1 / 12) - 1
  old_sharpe <- round((mean(vol_ret) - monthly_rf_old) / sd(vol_ret) * sqrt(12), 3)

  expect_false(isTRUE(all.equal(new_sharpe, old_sharpe)))
})

test_that(".cmr_join_rf trims a trailing uncovered date and warns (Fama-French publication lag)", {
  short_rf <- toy_daily_rf[1:20, ]  # rf ends 4 periods before the portfolio
  df <- toy_portfolio |> dplyr::mutate(date = as.Date(date))

  expect_warning(joined <- .cmr_join_rf(df, short_rf, lookback = "test"), regexp = "Dropped")
  expect_equal(nrow(joined), 20L)
  expect_false(any(is.na(joined$rf_ret)))
})

test_that(".cmr_join_rf aborts on an INTERIOR gap (not a publication lag)", {
  gapped_rf <- toy_daily_rf[-10, ]  # remove a period from the middle of rf's own span
  df <- toy_portfolio |> dplyr::mutate(date = as.Date(date))

  expect_snapshot(error = TRUE, .cmr_join_rf(df, gapped_rf, lookback = "test"))
})

test_that(".cmr_join_rf aborts when daily_rf lacks required columns", {
  df <- toy_portfolio |> dplyr::mutate(date = as.Date(date))
  bad_rf <- tibble::tibble(date = toy_daily_rf$date)

  expect_snapshot(error = TRUE, .cmr_join_rf(df, bad_rf, lookback = "test"))
})
