# Tests for cmr_summary unit convention — #336
#
# .compute_cmr_metrics() in R/plan_commodities_mean_reversion.R produces
# the per-lookback metric row that flows into the cmr_summary target and
# from there to the leaderboard, cmr_vs_mom_compare, and bt.run registry.
#
# Before #336: cagr, vol, max_dd were stored as percent (e.g., -100 = -100%).
# After  #336: stored as decimal fractions (e.g., -1.0 = -100%), matching
# plan_factormax.R, plan_drif.R, commodities_momentum.R, and the leaderboard
# normalizers.

# Path-checked pkgload — .compute_cmr_metrics() calls hd_dd_duration() from
# the historicaldata package, so the package must be loaded before sourcing
# the plan file. Mirrors the pattern used in vignette setup chunks.
pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/plan_commodities_mean_reversion.R"))

# Minimal toy portfolio: 24 monthly net returns in a tibble shape that
# .compute_cmr_metrics() consumes. Returns drawn so that max_dd lands well
# inside the (-1, 0] decimal band — under the old percent convention this
# would be ~−45 instead of ~−0.45.
toy_portfolio <- tibble::tibble(
  date    = seq.Date(as.Date("2020-01-31"), by = "month", length.out = 24L),
  net_ret = c(rep(-0.05, 12L), rep(0.02, 12L))  # 12mo drawdown then recovery
)

test_that(".compute_cmr_metrics returns max_dd as decimal fraction (#336)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", ann_factor = 12L)
  expect_true(is.finite(metrics$max_dd))
  expect_gte(metrics$max_dd, -1)    # canonical decimal: in [-1, 0]
  expect_lte(metrics$max_dd, 0)
})

test_that(".compute_cmr_metrics returns cagr/vol as decimal fractions (#336)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", ann_factor = 12L)
  # Decimal CAGR for monthly returns near ±5% sits in (-1, 1); under the old
  # percent convention this would land in the (-100, 100) band.
  expect_gt(metrics$cagr, -1)
  expect_lt(metrics$cagr,  1)
  # Annualised vol of a 5% / 2% monthly series is well below 1 in decimal.
  expect_gt(metrics$vol, 0)
  expect_lt(metrics$vol, 1)
})

test_that(".compute_cmr_metrics never returns the old percent magnitude (#336 regression)", {
  metrics <- .compute_cmr_metrics(toy_portfolio, lookback = "test", ann_factor = 12L)
  # Specific anti-regression: -100 was the old percent output for this kind
  # of monotone-loss path; the decimal equivalent is around -0.45.
  expect_false(metrics$max_dd < -1.0)
  expect_false(abs(metrics$cagr) > 1.0)
  expect_false(metrics$vol > 1.0)
})
