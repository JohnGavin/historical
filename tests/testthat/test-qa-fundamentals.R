testthat::local_edition(3)
# Tests for the fundamentals QA gate functions (#553/#554/#555) --
# check_fundamentals_lag_shift() (CHECK 6, #554) and
# check_fundamentals_join_dates() (join-date audit, #555).
#
# The functions are defined in R/plan_qa_fundamentals.R and exercised
# directly with synthetic data, same pattern as
# test-leaderboard-period-vocab.R for check_leaderboard_period_vocab()
# (S10) -- no tar_make() required.

source(here::here("R/plan_qa_fundamentals.R"))

# ── FUNDAMENTAL_MAX_LAG_DAYS ────────────────────────────────────────────────

test_that("FUNDAMENTAL_MAX_LAG_DAYS is the documented 120-day SEC worst-case ceiling", {
  expect_equal(FUNDAMENTAL_MAX_LAG_DAYS, 120L)
})

# ── check_hd_fundamentals_usage() ───────────────────────────────────────────

test_that("check_hd_fundamentals_usage detects a bare hd_fundamentals() call", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "foo <- function() {",
    "  hd_fundamentals(\"AAPL\", as_of = Sys.Date())",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  hits <- check_hd_fundamentals_usage(tmp)
  expect_equal(nrow(hits), 1L)
  expect_equal(hits$line, 2L)
})

test_that("check_hd_fundamentals_usage ignores commented-out calls", {
  tmp <- tempfile(fileext = ".R")
  writeLines("# hd_fundamentals(\"AAPL\")", tmp)
  on.exit(unlink(tmp))
  hits <- check_hd_fundamentals_usage(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_hd_fundamentals_usage finds zero call sites anywhere in root R/ today", {
  # #553's own acceptance criteria: this schema work is deferred until a
  # fundamental signal is actually scoped. This test pins that current
  # state -- when a real fundamentals-consuming strategy is added, this
  # test must be updated (it is the intended trigger to also wire CHECK 6
  # / the join-date audit into that strategy's own QA target, per the
  # header comment in R/plan_qa_fundamentals.R).
  r_files <- list.files(here::here("R"), pattern = "\\.R$",
                         full.names = TRUE, recursive = TRUE)
  r_files <- r_files[basename(r_files) != "plan_qa_fundamentals.R"]
  hits <- check_hd_fundamentals_usage(r_files)
  expect_equal(nrow(hits), 0L)
})

# ── check_fundamentals_lag_shift() (CHECK 6, #554) ──────────────────────────

test_that("check_fundamentals_lag_shift: OK when degradation is under 15%", {
  result <- check_fundamentals_lag_shift(metric_as_used = 1.00, metric_lag_shifted = 0.90, metric_name = "Sharpe")
  expect_equal(result$verdict, "ok")
  expect_lt(result$degradation_pct, 15)
})

test_that("check_fundamentals_lag_shift: an IMPROVEMENT under the shift is 0% degradation, not negative", {
  result <- check_fundamentals_lag_shift(metric_as_used = 1.00, metric_lag_shifted = 1.20, metric_name = "Sharpe")
  expect_equal(result$verdict, "ok")
  expect_equal(result$degradation_pct, 0)
})

test_that("check_fundamentals_lag_shift: warns in the 15-40% band and does not abort", {
  expect_warning(
    result <- check_fundamentals_lag_shift(metric_as_used = 1.00, metric_lag_shifted = 0.75, metric_name = "Sharpe"),
    class = "hd_fundamentals_lag_shift_warn"
  )
  expect_equal(result$verdict, "warn")
  expect_gte(result$degradation_pct, 15)
  expect_lt(result$degradation_pct, 40)
})

test_that("check_fundamentals_lag_shift: aborts above 40% -- the known-peek case", {
  # A synthetic strategy whose Sharpe collapses from 1.20 (as-used) to 0.10
  # (lag-shifted) -- the edge was entirely the filing-lag peek.
  expect_error(
    check_fundamentals_lag_shift(metric_as_used = 1.20, metric_lag_shifted = 0.10, metric_name = "Sharpe"),
    class = "hd_fundamentals_lag_shift_fail"
  )
  expect_snapshot(
    error = TRUE,
    check_fundamentals_lag_shift(metric_as_used = 1.20, metric_lag_shifted = 0.10, metric_name = "Sharpe")
  )
})

test_that("check_fundamentals_lag_shift: rejects non-scalar / NA / non-numeric inputs", {
  expect_error(
    check_fundamentals_lag_shift(metric_as_used = NA_real_, metric_lag_shifted = 0.5),
    class = "hd_fundamentals_lag_shift_bad_input"
  )
  expect_error(
    check_fundamentals_lag_shift(metric_as_used = c(1, 2), metric_lag_shifted = 0.5),
    class = "hd_fundamentals_lag_shift_bad_input"
  )
  expect_error(
    check_fundamentals_lag_shift(metric_as_used = "not-numeric", metric_lag_shifted = 0.5),
    class = "hd_fundamentals_lag_shift_bad_input"
  )
})

test_that("check_fundamentals_lag_shift: rejects a ~0 baseline (relative degradation undefined)", {
  expect_error(
    check_fundamentals_lag_shift(metric_as_used = 0, metric_lag_shifted = 0.5),
    class = "hd_fundamentals_lag_shift_zero_baseline"
  )
})

# ── check_fundamentals_join_dates() (#555) ──────────────────────────────────

clean_frame <- tibble::tibble(
  ticker        = c("AAPL", "AAPL", "MSFT"),
  fiscal_period = c("2024Q1", "2024Q2", "2024Q1"),
  xbrl_tag      = c("Revenues", "Revenues", "Revenues"),
  first_filed   = as.Date(c("2024-02-01", "2024-05-01", "2024-02-05")),
  visible_date  = as.Date(c("2024-02-01", "2024-05-01", "2024-02-05"))  # same-day, inclusive OK
)

leaked_frame <- tibble::tibble(
  ticker        = c("AAPL", "AAPL", "MSFT"),
  fiscal_period = c("2024Q1", "2024Q2", "2024Q1"),
  xbrl_tag      = c("Revenues", "Revenues", "Revenues"),
  first_filed   = as.Date(c("2024-02-01", "2024-05-01", "2024-02-05")),
  # The MSFT row is visible 3 days BEFORE its filing date -- a deliberate
  # leak, the exact scenario this gate exists to catch.
  visible_date  = as.Date(c("2024-02-01", "2024-05-01", "2024-02-02"))
)

test_that("check_fundamentals_join_dates: passes (leaked_pct = 0) on a clean frame", {
  result <- check_fundamentals_join_dates(clean_frame)
  expect_equal(result$leaked_pct, 0)
  expect_equal(result$n_leaked, 0L)
  expect_equal(result$n_total, 3L)
})

test_that("check_fundamentals_join_dates: catches a deliberately-leaked row", {
  expect_error(
    check_fundamentals_join_dates(leaked_frame),
    class = "hd_fundamentals_join_dates_leak"
  )
  expect_snapshot(
    error = TRUE,
    check_fundamentals_join_dates(leaked_frame)
  )
})

test_that("check_fundamentals_join_dates: names the offending ticker/period in the failure message", {
  err <- tryCatch(
    check_fundamentals_join_dates(leaked_frame),
    error = function(e) e
  )
  expect_true(inherits(err, "hd_fundamentals_join_dates_leak"))
  expect_true(grepl("MSFT", conditionMessage(err)))
})

test_that("check_fundamentals_join_dates: strict_same_day = TRUE treats same-day as a leak", {
  # clean_frame is entirely same-day visible/filed -- OK under the default
  # inclusive convention, but a leak under strict_same_day.
  expect_error(
    check_fundamentals_join_dates(clean_frame, strict_same_day = TRUE),
    class = "hd_fundamentals_join_dates_leak"
  )
})

test_that("check_fundamentals_join_dates: errors loudly when required columns are missing", {
  bad <- dplyr::select(clean_frame, -first_filed)
  expect_error(
    check_fundamentals_join_dates(bad),
    class = "hd_fundamentals_join_dates_missing_cols"
  )
  expect_snapshot(
    error = TRUE,
    check_fundamentals_join_dates(bad)
  )
})

test_that("check_fundamentals_join_dates: an NA comparison counts as a leak, not a silent pass (fail-loud-not-null)", {
  na_frame <- clean_frame
  na_frame$visible_date[1] <- NA
  expect_error(
    check_fundamentals_join_dates(na_frame),
    class = "hd_fundamentals_join_dates_leak"
  )
})
