testthat::local_edition(3)
# #657: two joins that silently dropped periods now report the count.
#   1. R/plan_ecb.R  .ecb_spread_join()  -- ecb_yield_spread lost 1054 of 5663
#      yield-curve dates (2004-09-06..2008-10-14) because the ECB refi-rate
#      series has no observation before 2008-10-15. See
#      docs/inner-join-audit-657.md "Measured 2026-11-09".
#   2. R/plan_strategy_correlation.R  .inform_family_na_drop() -- the
#      4-strategy family's complete-case filter removed 2 trailing months
#      (2026-03, 2026-04) before strat_corr_matrix with no trace.
# Neither changes a published number: the join result is unchanged, only the
# dropped count is reported.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_ecb.R"))
source(here::here("R/plan_strategy_correlation.R"))

# -- .ecb_spread_join() ------------------------------------------------------

test_that(".ecb_spread_join reports how many yield-curve dates the refi series cannot match", {
  yc <- tibble::tibble(
    date = as.Date("2008-10-10") + 0:5,
    yield_10y = c(4.0, 4.1, 4.2, 4.3, 4.4, 4.5)
  )
  refi <- tibble::tibble(
    date = as.Date("2008-10-12") + 0:5,
    refi_rate = 3.25
  )
  expect_message(
    out <- .ecb_spread_join(yc, refi),
    regexp = "2 of 6"
  )
  # The join itself is unchanged: only the 4 shared dates survive.
  expect_equal(nrow(out), 4L)
  expect_equal(attr(out, "n_dropped_yc_dates"), 2L)
  expect_equal(out$spread_bps, round((c(4.2, 4.3, 4.4, 4.5) - 3.25) * 100, 1))
})

test_that(".ecb_spread_join names the first and last dropped date", {
  yc <- tibble::tibble(date = as.Date("2008-10-10") + 0:3, yield_10y = 4)
  refi <- tibble::tibble(date = as.Date("2008-10-12") + 0:3, refi_rate = 3)
  expect_message(.ecb_spread_join(yc, refi), regexp = "2008-10-10")
  expect_message(.ecb_spread_join(yc, refi), regexp = "2008-10-11")
})

test_that(".ecb_spread_join is silent and reports 0 when every yield-curve date matches", {
  yc <- tibble::tibble(date = as.Date("2020-01-01") + 0:2, yield_10y = 1)
  refi <- tibble::tibble(date = as.Date("2019-12-30") + 0:5, refi_rate = 0)
  expect_no_message(out <- .ecb_spread_join(yc, refi))
  expect_equal(nrow(out), 3L)
  expect_equal(attr(out, "n_dropped_yc_dates"), 0L)
})

test_that(".ecb_spread_join does not count refi-only dates (weekends) as dropped", {
  yc <- tibble::tibble(date = as.Date(c("2020-01-03", "2020-01-06")), yield_10y = 1)
  refi <- tibble::tibble(date = as.Date("2020-01-03") + 0:3, refi_rate = 0)  # includes Sat/Sun
  expect_no_message(out <- .ecb_spread_join(yc, refi))
  expect_equal(attr(out, "n_dropped_yc_dates"), 0L)
})

# -- .inform_family_na_drop() ------------------------------------------------

test_that(".inform_family_na_drop reports the months removed by the complete-case filter", {
  expect_message(
    dropped <- .inform_family_na_drop(
      ym_all  = c("2026-01", "2026-02", "2026-03", "2026-04"),
      ym_kept = c("2026-01", "2026-02")
    ),
    regexp = "2 of 4"
  )
  expect_equal(dropped, c("2026-03", "2026-04"))
})

test_that(".inform_family_na_drop is silent when no month is removed", {
  expect_no_message(
    dropped <- .inform_family_na_drop(c("2026-01", "2026-02"), c("2026-01", "2026-02"))
  )
  expect_equal(dropped, character(0))
})
