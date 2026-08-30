testthat::local_edition(3)
# Tests for check_cmr_effective_breadth() — QA gate S24 (#751 item F)
#
# n_eff (hd_commodity_mr_portfolio(), packages/historicaldata/R/
# commodities_mean_reversion.R) is the inverse Herfindahl index of
# normalised absolute weight -- "how many independent bets is this
# portfolio effectively making". Under the live equal-weight tercile
# construction, n_eff == n_long + n_short whenever a position is held. This
# gate asserts n_eff never falls below CMR_MIN_EFFECTIVE_BREADTH (4) on any
# date holding a position, across all three CMR lookback partitions.
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

good_1m <- tibble::tibble(
  date    = as.Date(c("2020-01-31", "2020-02-29", "2020-03-31")),
  n_long  = c(0L, 4L, 6L),
  n_short = c(0L, 4L, 6L),
  n_eff   = c(0,  8,  12)
)
good_3m <- tibble::tibble(
  date    = as.Date(c("2020-01-31", "2020-02-29")),
  n_long  = c(5L, 5L),
  n_short = c(5L, 5L),
  n_eff   = c(10,  10)
)

# ── Tests: passing cases ─────────────────────────────────────────────────

test_that("check_cmr_effective_breadth passes when n_eff is always >= the floor on held dates", {
  expect_true(check_cmr_effective_breadth(list(`1m` = good_1m, `3m` = good_3m)))
})

test_that("check_cmr_effective_breadth ignores n_eff on dates holding no position", {
  # A flat date with n_eff = 0 (below the floor) must NOT trip the gate --
  # it is not "holding a position", so the floor does not apply.
  flat_below_floor <- tibble::tibble(
    date = as.Date("2020-04-30"), n_long = 0L, n_short = 0L, n_eff = 0
  )
  combined <- dplyr::bind_rows(good_1m, flat_below_floor)
  expect_true(check_cmr_effective_breadth(list(`1m` = combined)))
})

# ── Tests: failing cases ─────────────────────────────────────────────────

test_that("check_cmr_effective_breadth throws and names the worst offender when n_eff falls below the floor on a held date", {
  bad_3m <- tibble::tibble(
    date    = as.Date(c("2020-01-31", "2020-02-29")),
    n_long  = c(2L, 5L),
    n_short = c(1L, 5L),   # n_eff = 3 < CMR_MIN_EFFECTIVE_BREADTH = 4, held (n_long+n_short=3>0)
    n_eff   = c(3,  10)
  )
  expect_error(
    check_cmr_effective_breadth(list(`1m` = good_1m, `3m` = bad_3m)),
    regexp = "effective breadth"
  )
  expect_snapshot(
    error = TRUE,
    check_cmr_effective_breadth(list(`1m` = good_1m, `3m` = bad_3m))
  )
})

test_that("check_cmr_effective_breadth throws when a CMR portfolio is missing required columns", {
  bad <- dplyr::select(good_1m, -n_eff)
  expect_error(
    check_cmr_effective_breadth(list(`1m` = bad)),
    regexp = "n_eff"
  )
  expect_snapshot(
    error = TRUE,
    check_cmr_effective_breadth(list(`1m` = bad))
  )
})
