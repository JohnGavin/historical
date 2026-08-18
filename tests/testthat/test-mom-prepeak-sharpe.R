# Tests for .mom_prepeak_join_rf() and .mom_prepeak_sharpe() (#677 slice 3)
#
# .mom_prepeak_compute_metrics() (packages/historicaldata) can no longer call
# sharpe_ratio_rf() -- that canonical rf-adjusted geometric Sharpe helper
# lives at the pipeline layer (R/utils_metrics.R), not inside the
# historicaldata package -- so it returns sharpe = NA_real_ as a placeholder
# and R/plan_mom_prepeak.R::.mom_prepeak_sharpe() computes the real value.
# These tests cover that split: the rf join (trailing-trim / interior-abort,
# mirroring .ltr_join_rf()) and the Sharpe computation itself (geometric
# numerator, rf-deducted, pre-bankruptcy slice when blown_up).
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_mom_prepeak.R"))

# ── Fixtures ──────────────────────────────────────────────────────────────

make_exec_dates <- function(n) {
  seq.Date(as.Date("2020-01-01"), by = "month", length.out = n)
}

make_returns_tbl_exec <- function(r) {
  n <- length(r)
  tibble::tibble(exec_date = make_exec_dates(n), ret_ls = r)
}

make_stk_rf <- function(n, rf_ret = 0.0016) {
  tibble::tibble(
    ym     = format(make_exec_dates(n), "%Y-%m"),
    rf_ret = rep(rf_ret, n)
  )
}

# ── .mom_prepeak_join_rf(): coverage handling ───────────────────────────────

test_that(".mom_prepeak_join_rf joins rf_ret by ym from exec_date", {
  r    <- rep(0.01, 24)
  rets <- make_returns_tbl_exec(r)
  rf   <- make_stk_rf(24)

  joined <- .mom_prepeak_join_rf(rets, rf)

  expect_true("rf_ret" %in% names(joined))
  expect_equal(nrow(joined), 24L)
  expect_false(any(is.na(joined$rf_ret)))
})

test_that(".mom_prepeak_join_rf trims trailing months with no rf coverage (warns)", {
  r    <- rep(0.01, 24)
  rets <- make_returns_tbl_exec(r)
  rf   <- make_stk_rf(24)[1:20, ]  # rf ends 4 months before returns_tbl

  expect_warning(
    joined <- .mom_prepeak_join_rf(rets, rf),
    regexp = "Dropped"
  )
  expect_equal(nrow(joined), 20L)
  expect_false(any(is.na(joined$rf_ret)))
})

test_that(".mom_prepeak_join_rf aborts on an INTERIOR gap (not a publication lag)", {
  r    <- rep(0.01, 24)
  rets <- make_returns_tbl_exec(r)
  rf   <- make_stk_rf(24)
  rf   <- rf[-10, ]  # remove a month from the middle of rf's own span

  expect_snapshot(error = TRUE, .mom_prepeak_join_rf(rets, rf))
})

test_that(".mom_prepeak_join_rf aborts when stk_rf is missing required columns", {
  rets <- make_returns_tbl_exec(rep(0.01, 12))
  bad_rf <- tibble::tibble(ym = format(make_exec_dates(12), "%Y-%m"))

  expect_snapshot(error = TRUE, .mom_prepeak_join_rf(rets, bad_rf))
})

test_that(".mom_prepeak_join_rf aborts when returns_tbl has no exec_date column", {
  bad_rets <- tibble::tibble(ret_ls = rep(0.01, 12))
  rf       <- make_stk_rf(12)

  expect_snapshot(error = TRUE, .mom_prepeak_join_rf(bad_rets, rf))
})

# ── .mom_prepeak_sharpe(): geometric numerator, rf-deducted ─────────────────

test_that(".mom_prepeak_sharpe matches sharpe_ratio_rf() directly (normal case)", {
  set.seed(1)
  r    <- rnorm(36, mean = 0.01, sd = 0.06)  # deliberately volatile fixture
  rets <- .mom_prepeak_join_rf(make_returns_tbl_exec(r), make_stk_rf(36))
  metrics_row <- historicaldata:::.mom_prepeak_compute_metrics(rets, strategy = "test")

  result   <- .mom_prepeak_sharpe(rets, metrics_row)
  expected <- sharpe_ratio_rf(rets$ret_ls, rets$rf_ret, periods_per_year = 12L)$sharpe

  expect_equal(result, expected)
})

test_that(".mom_prepeak_sharpe differs from the old arithmetic formula on a volatile fixture", {
  set.seed(2)
  r    <- rnorm(36, mean = 0.01, sd = 0.08)  # high vol -> arithmetic/geometric gap is large
  rets <- .mom_prepeak_join_rf(make_returns_tbl_exec(r), make_stk_rf(36))
  metrics_row <- historicaldata:::.mom_prepeak_compute_metrics(rets, strategy = "test")

  new_sharpe <- .mom_prepeak_sharpe(rets, metrics_row)

  # Old (pre-#677) formula: arithmetic mean numerator, hardcoded 2%/yr rf.
  monthly_rf_old <- (1.02)^(1 / 12) - 1
  old_sharpe <- (mean(r) - monthly_rf_old) / sd(r) * sqrt(12)

  expect_false(isTRUE(all.equal(new_sharpe, old_sharpe)))
})

test_that(".mom_prepeak_sharpe stays finite when blown_up (pre-bankruptcy slice)", {
  r <- rep(c(0.02, -0.01), 12)  # varying returns -- a constant series has zero variance
  r[13] <- -1.2   # bankruptcy at month 13
  rets <- .mom_prepeak_join_rf(make_returns_tbl_exec(r), make_stk_rf(24))
  metrics_row <- historicaldata:::.mom_prepeak_compute_metrics(rets, strategy = "test")

  expect_true(metrics_row$blown_up)
  result <- .mom_prepeak_sharpe(rets, metrics_row)

  expect_false(is.na(result))
  expect_true(is.finite(result))

  # Must match sharpe_ratio_rf() on the pre-bankruptcy slice only (months 1-12).
  expected <- sharpe_ratio_rf(
    rets$ret_ls[1:12], rets$rf_ret[1:12], periods_per_year = 12L
  )$sharpe
  expect_equal(result, expected)
})

test_that(".mom_prepeak_sharpe aborts when rf_ret column is missing", {
  rets <- make_returns_tbl_exec(rep(0.01, 24))  # no rf_ret column -- not joined
  metrics_row <- tibble::tibble(blown_up = FALSE, bankrupt_month = NA_integer_)

  expect_snapshot(error = TRUE, .mom_prepeak_sharpe(rets, metrics_row))
})
