testthat::local_edition(3)
# #1061: momentum leg sizing must follow CMR's rule (#751 items C/D): per date
# each leg holds floor(n_avail * frac) names, equal weight 1 / n_leg, legs
# disjoint by construction, flat below ceiling(min_leg_names / frac) names.
#
# The fixed n_long = n_short = 10 headcount overlapped the legs on every date
# once the pool shrank to 17 series; overlapping names were long-only, so the
# book was net long, not long-short.
#
# Dollar-neutrality is checked from RETURNS, not from a column the code under
# test reports: with the same next-bar return c on every name, a dollar-neutral
# book earns exactly 0 and a net-long book earns > 0.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/commodities_momentum.R"))

.toy_universe <- function(n_names, n_dates = 4L, ret = 0.01) {
  dates <- as.Date("2020-01-31") + 0:(n_dates - 1L)
  ids <- sprintf("S%02d", seq_len(n_names))
  grid <- tidyr::expand_grid(date = dates, series_id = ids)
  # distinct, date-invariant signal: S01 highest ... last lowest
  sig <- setNames(rev(seq_len(n_names)) / n_names, ids)
  list(
    returns = transform(grid, monthly_ret = ret),
    signals = transform(grid,
      mom_12d = sig[series_id], mom_3d = sig[series_id], mom_9d = sig[series_id],
      volatility_roll = 0.1, trend_strength = 0.5
    )
  )
}

.run <- function(n_names, ...) {
  u <- .toy_universe(n_names)
  backtest_commodity_momentum(u$signals, u$returns, cost_bps = 0, ...)
}

test_that("legs are disjoint and the book is dollar-neutral at 17 and 5 names", {
  for (n in c(17L, 5L)) {
    bt <- .run(n) |> filter(strategy == "baseline")
    held <- bt |> filter(n_positions > 0L)
    if (n == 17L) {
      n_leg <- floor(n * .HD_CMR_DEFAULT_FRAC)
      # held names = 2 * n_leg proves the legs do not overlap (a headcount of
      # 10 on 17 names held all 17 with 3 names double-counted as long-only)
      expect_true(all(bt$n_positions == 2L * n_leg))
      expect_true(all(bt$n_long == n_leg & bt$n_short == n_leg))
    }
    # same return c on every name: dollar-neutral => gross return exactly 0
    expect_equal(bt$portfolio_ret, rep(0, nrow(bt)), tolerance = 1e-12)
    expect_true(all(abs(held$net_weight) < 1e-12))
  }
})

test_that("a date with too few names is flat, and is still returned (CMR rule)", {
  too_few <- ceiling(.HD_CMR_MIN_LEG_NAMES / .HD_CMR_DEFAULT_FRAC) - 1L
  bt <- .run(too_few) |> filter(strategy == "baseline")
  expect_gt(nrow(bt), 0L)
  expect_true(all(bt$n_positions == 0L))
  expect_true(all(bt$portfolio_ret == 0))
  expect_true(all(bt$turnover == 0))

  enough <- too_few + 1L
  bt2 <- .run(enough) |> filter(strategy == "baseline")
  expect_true(all(bt2$n_positions > 0L))
})

test_that("legs hold floor(n * frac) names each, weight 1 / n_leg", {
  u <- .toy_universe(9L, n_dates = 2L, ret = 0.01)
  # make the top-ranked names earn +1% and the bottom-ranked -1%
  ids <- sprintf("S%02d", 1:9)
  u$returns$monthly_ret <- ifelse(u$returns$series_id %in% ids[1:3], 0.01,
                           ifelse(u$returns$series_id %in% ids[7:9], -0.01, 0))
  bt <- backtest_commodity_momentum(u$signals, u$returns, cost_bps = 0,
                                    frac = 1 / 3) |>
    filter(strategy == "baseline")
  # n_leg = 3, weight 1/3: long +1% on 3 names, short -1% => 1/3*3*0.01*2
  expect_equal(bt$n_long, rep(3L, nrow(bt)))
  expect_equal(bt$portfolio_ret, rep(0.02, nrow(bt)))
})

test_that("frac outside (0, 0.5) is rejected", {
  u <- .toy_universe(9L)
  expect_error(backtest_commodity_momentum(u$signals, u$returns, frac = 0.5),
               "frac")
})
