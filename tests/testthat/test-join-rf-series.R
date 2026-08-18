testthat::local_edition(3)
# Unit tests for .join_rf_series() (#677 slice 3b) -- the canonical
# THREE-CASE risk-free coverage policy shared by .ltr_join_rf()
# (R/plan_ltr_momentum.R), .tom_join_rf_daily() (R/plan_turn_of_month.R),
# .mom_prepeak_join_rf() (R/plan_mom_prepeak.R), .cmr_join_rf()
# (R/plan_commodities_mean_reversion.R), and .olmar_join_rf()
# (R/plan_olmar.R).
#
# Pure and unit-testable per this function's own roxygen: PR #678's guard
# shipped untested because it lived inside a target reading a gitignored
# parquet, and that is exactly how main broke twice (#678, then again via
# the LEADING gap #684 found and left as a follow-up). These tests cover
# the gap #684 flagged: LEADING coverage must abort saying "leading",
# never "hole" -- unlike an INTERIOR hole, which still says "HOLE".

source(here::here("R/utils_metrics.R"))

# ── Fixtures: monthly (ym, character "YYYY-MM") ──────────────────────────

.mk_df_ym <- function(yms) tibble::tibble(ym = yms, ret = seq_along(yms) / 1000)
.mk_rf_ym <- function(yms) tibble::tibble(ym = yms, rf_ret = rep(0.001, length(yms)))

.args_ym <- list(
  key = "ym", label = ".test_join", rf_label = "test_rf",
  rf_source = "test source", df_label = "test_df",
  strategy_label = "TEST", period_noun = "month"
)

# ── Fixtures: daily (date, Date) ──────────────────────────────────────────

.mk_df_date <- function(dates) tibble::tibble(date = as.Date(dates), ret = seq_along(dates) / 1000)
.mk_rf_date <- function(dates) tibble::tibble(date = as.Date(dates), rf_ret = rep(0.0001, length(dates)))

.args_date <- list(
  key = "date", label = ".test_join_daily", rf_label = "test_daily_rf",
  rf_source = "test daily source", df_label = "test_daily_df",
  strategy_label = "TEST-DAILY", period_noun = "date"
)

.call_join <- function(df, rf, args, ...) {
  do.call(.join_rf_series, c(list(df = df, rf = rf), args, list(...)))
}

# ── Complete coverage: no gaps, either key type ───────────────────────────

test_that("complete coverage returns all rows with no NA rf_ret (monthly)", {
  out <- .call_join(.mk_df_ym(c("2026-01", "2026-02")), .mk_rf_ym(c("2026-01", "2026-02")), .args_ym)
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

test_that("complete coverage returns all rows with no NA rf_ret (daily)", {
  out <- .call_join(
    .mk_df_date(c("2026-01-05", "2026-01-06")),
    .mk_rf_date(c("2026-01-05", "2026-01-06")),
    .args_date
  )
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

# ── TRAILING: trim + warn (Fama-French publication lag) ──────────────────

test_that("trailing gap (monthly) is trimmed and warns, naming the dropped period", {
  df <- .mk_df_ym(c("2026-01", "2026-02", "2026-03"))
  rf <- .mk_rf_ym(c("2026-01", "2026-02"))
  expect_warning(out <- .call_join(df, rf, .args_ym), regexp = "2026-03")
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
  expect_false("2026-03" %in% out$ym)
})

test_that("trailing gap (daily) is trimmed and warns, naming the dropped period", {
  df <- .mk_df_date(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf <- .mk_rf_date(c("2026-01-05", "2026-01-06"))
  expect_warning(out <- .call_join(df, rf, .args_date), regexp = "2026-01-07")
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
  expect_false(as.Date("2026-01-07") %in% out$date)
})

# ── INTERIOR: abort, correctly described as a HOLE ────────────────────────

test_that("interior gap (monthly) aborts, naming the missing month and 'HOLE'", {
  df <- .mk_df_ym(c("2026-01", "2026-02", "2026-03"))
  rf <- .mk_rf_ym(c("2026-01", "2026-03"))  # 2026-02 missing, inside rf's own span
  expect_error(.call_join(df, rf, .args_ym), regexp = "2026-02")
  expect_error(.call_join(df, rf, .args_ym), regexp = "HOLE")
})

test_that("interior gap (daily) aborts, naming the missing date and 'HOLE'", {
  df <- .mk_df_date(c("2026-01-05", "2026-01-06", "2026-01-07"))
  rf <- .mk_rf_date(c("2026-01-05", "2026-01-07"))  # 2026-01-06 missing, inside rf's own span
  expect_error(.call_join(df, rf, .args_date), regexp = "2026-01-06")
  expect_error(.call_join(df, rf, .args_date), regexp = "HOLE")
})

# ── LEADING: abort, says "leading", NEVER "hole" -- the wording bug #684 ──
# flagged (PR #679/#683/#684 reported this case as "a HOLE in the series",
# sending a reader hunting for a gap that does not exist).

test_that("leading gap (monthly) aborts, says LEADING and never 'hole'", {
  df <- .mk_df_ym(c("2025-11", "2025-12", "2026-01"))
  rf <- .mk_rf_ym(c("2025-12", "2026-01"))  # rf starts after df -- 2025-11 is LEADING
  err <- tryCatch(.call_join(df, rf, .args_ym), error = function(e) e)
  expect_s3_class(err, "rlang_error")
  msg <- conditionMessage(err)
  expect_match(msg, "2025-11", fixed = TRUE)
  expect_match(msg, "LEADING", fixed = TRUE)
  expect_false(grepl("hole", msg, ignore.case = TRUE))
})

test_that("leading gap (daily) aborts, says LEADING and never 'hole'", {
  df <- .mk_df_date(c("2026-01-03", "2026-01-04", "2026-01-05"))
  rf <- .mk_rf_date(c("2026-01-04", "2026-01-05"))  # 2026-01-03 is LEADING
  err <- tryCatch(.call_join(df, rf, .args_date), error = function(e) e)
  msg <- conditionMessage(err)
  expect_match(msg, "2026-01-03", fixed = TRUE)
  expect_match(msg, "LEADING", fixed = TRUE)
  expect_false(grepl("hole", msg, ignore.case = TRUE))
})

test_that("leading takes priority when a leading AND an interior gap both exist", {
  # 2025-11 is LEADING (before rf starts); 2026-01 is INTERIOR (inside rf's span).
  df <- .mk_df_ym(c("2025-11", "2025-12", "2026-01", "2026-02"))
  rf <- .mk_rf_ym(c("2025-12", "2026-02"))
  err <- tryCatch(.call_join(df, rf, .args_ym), error = function(e) e)
  msg <- conditionMessage(err)
  expect_match(msg, "LEADING", fixed = TRUE)
  expect_match(msg, "2025-11", fixed = TRUE)
})

# ── Missing columns / missing key column ──────────────────────────────────

test_that("aborts when rf lacks required columns", {
  expect_error(
    .call_join(.mk_df_ym("2026-01"), tibble::tibble(ym = "2026-01"), .args_ym),
    regexp = "rf_ret"
  )
})

test_that("aborts when df has no key column and check_key_col is TRUE (default)", {
  bad_df <- tibble::tibble(not_ym = "2026-01", ret = 1)
  expect_error(
    .call_join(bad_df, .mk_rf_ym("2026-01"), .args_ym),
    regexp = "ym"
  )
})

test_that("check_key_col = FALSE skips the key-column presence check", {
  # df already has ym present -- FALSE just skips the defensive check, so
  # behaviour is identical to the default when the column IS present (this
  # is how CMR / mom_prepeak use it: they guarantee `ym` by construction
  # before calling, mirroring their pre-#677-slice-3b behaviour of never
  # checking for it at all).
  out <- .call_join(
    .mk_df_ym(c("2026-01", "2026-02")), .mk_rf_ym(c("2026-01", "2026-02")),
    .args_ym, check_key_col = FALSE
  )
  expect_equal(nrow(out), 2L)
})

# ── Snapshot coverage for the abort messages themselves ───────────────────

test_that(".join_rf_series abort messages are stable (monthly)", {
  expect_snapshot(
    error = TRUE,
    .call_join(
      .mk_df_ym(c("2026-01", "2026-02", "2026-03")),
      .mk_rf_ym(c("2026-01", "2026-03")),
      .args_ym
    )
  )
  expect_snapshot(
    error = TRUE,
    .call_join(
      .mk_df_ym(c("2025-11", "2025-12", "2026-01")),
      .mk_rf_ym(c("2025-12", "2026-01")),
      .args_ym
    )
  )
  expect_snapshot(
    error = TRUE,
    .call_join(.mk_df_ym("2026-01"), tibble::tibble(ym = "2026-01"), .args_ym)
  )
})

test_that(".join_rf_series abort messages are stable (daily)", {
  expect_snapshot(
    error = TRUE,
    .call_join(
      .mk_df_date(c("2026-01-05", "2026-01-06", "2026-01-07")),
      .mk_rf_date(c("2026-01-05", "2026-01-07")),
      .args_date
    )
  )
})
