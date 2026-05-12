testthat::local_edition(3)
source(here::here("R/utils_align.R"))

# ── Helper builders ───────────────────────────────────────────────────────────

make_daily <- function(start = "2025-01-01", n = 60, seed = 1L,
                       col = "strategy_ret") {
  set.seed(seed)
  dates <- seq(as.Date(start), by = "day", length.out = n)
  # keep weekdays only to mimic trading calendars
  dates <- dates[lubridate::wday(dates, week_start = 1) <= 5]
  tibble::tibble(date = dates, !!col := rnorm(length(dates), 0, 0.01))
}

make_monthly_eom <- function(start = "2024-01-31", n = 24L, seed = 2L,
                              col = "strategy_ret") {
  set.seed(seed)
  dates <- seq(as.Date(start), by = "month", length.out = n)
  tibble::tibble(date = dates, !!col := rnorm(n, 0, 0.03))
}

make_monthly_mid <- function(start = "2024-01-15", n = 24L, seed = 3L,
                              col = "strategy_ret") {
  set.seed(seed)
  dates <- seq(as.Date(start), by = "month", length.out = n)
  tibble::tibble(date = dates, !!col := rnorm(n, 0, 0.03))
}

make_monthly_bizday_end <- function(start_year = 2024L, n = 24L, seed = 4L,
                                     col = "strategy_ret") {
  set.seed(seed)
  # Generate last-business-day of each month (Mon-Fri only) for n months
  months <- seq(as.Date(paste0(start_year, "-01-01")), by = "month", length.out = n)
  bizday_ends <- purrr::map_vec(months, function(m) {
    last_cal <- lubridate::ceiling_date(m, "month") - 1L
    wd <- lubridate::wday(last_cal, week_start = 1L)
    last_cal - dplyr::case_when(wd == 6L ~ 1L, wd == 7L ~ 2L, TRUE ~ 0L)
  })
  tibble::tibble(date = bizday_ends, !!col := rnorm(n, 0, 0.03))
}

# ── Test 1: Mixed daily + monthly with mismatched conventions (issue #146) ───

test_that("mixed daily and monthly series align to the same monthly anchors", {
  # Two daily + three monthly with three different month-day stamps
  daily_aw  <- make_daily("2025-01-01", n = 100)
  daily_rsc <- make_daily("2025-01-01", n = 100, seed = 10L)
  monthly_drif    <- make_monthly_mid("2025-01-15", n = 6L)         # mid-month
  monthly_fac_max <- make_monthly_bizday_end(start_year = 2025L, n = 6L) # end-bizday
  monthly_ltr     <- make_monthly_eom("2025-01-31", n = 6L)         # end-of-month

  result <- align_period(
    series = list(
      avoid_worst = daily_aw,
      rsc         = daily_rsc,
      drif        = monthly_drif,
      fac_max     = monthly_fac_max,
      ltr         = monthly_ltr
    ),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "compound"
  )

  # All five strategies should now share the same date column
  expect_s3_class(result, "tbl_df")
  expect_named(result, c("date", "avoid_worst", "rsc", "drif", "fac_max", "ltr"),
               ignore.order = FALSE)

  # No row should have ALL five columns NA (the #146 symptom)
  all_na_rows <- rowSums(is.na(result[, c("avoid_worst", "rsc", "drif", "fac_max", "ltr")])) == 5L
  expect_false(any(all_na_rows), info = "No row should have all five strategies NA")

  # The overlap period should have rows with non-NA entries for all five
  overlap <- dplyr::filter(result, !is.na(avoid_worst) & !is.na(drif) & !is.na(ltr))
  expect_gt(nrow(overlap), 0L)
})

# ── Test 2: Compound-return correctness ───────────────────────────────────────

test_that("compound method returns prod(1+r) - 1 for all daily obs in a month", {
  # Construct a clean single-month daily series
  days <- seq(as.Date("2025-02-03"), as.Date("2025-02-28"), by = "day")
  days <- days[lubridate::wday(days, week_start = 1L) <= 5L]
  rets <- seq(0.001, 0.001 * length(days), by = 0.001)

  s <- tibble::tibble(date = days, strategy_ret = rets)

  result <- align_period(
    series    = list(x = s),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "compound"
  )

  # Should have exactly one row (February)
  expect_equal(nrow(result), 1L)
  expected_compound <- prod(1 + rets) - 1
  expect_equal(result$x[[1L]], expected_compound, tolerance = 1e-10)
})

# ── Test 3: method = "last" for levels ───────────────────────────────────────

test_that('method = "last" emits the last observation in each period', {
  dates <- seq(as.Date("2025-01-01"), by = "month", length.out = 5L)
  # Build a daily series where we know the last daily value per month
  s <- tibble::tibble(
    date         = dates,
    strategy_ret = c(10, 20, 30, 40, 50)
  )

  result <- align_period(
    series    = list(x = s),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "last"
  )

  expect_equal(nrow(result), 5L)
  expect_equal(result$x, c(10, 20, 30, 40, 50))
})

# ── Test 4: min_obs gate ──────────────────────────────────────────────────────

test_that("min_obs gate returns NA for periods with too few observations", {
  # Build two months: Jan has 5 obs (fixed dates within Jan), Feb has 2 obs
  jan_dates <- as.Date(c("2025-01-06", "2025-01-13", "2025-01-20", "2025-01-24", "2025-01-27"))
  feb_dates <- as.Date(c("2025-02-03", "2025-02-10"))
  dates <- c(jan_dates, feb_dates)
  rets  <- c(rep(0.01, 5L), rep(0.02, 2L))

  s <- tibble::tibble(date = dates, strategy_ret = rets)

  result <- align_period(
    series    = list(x = s),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "compound",
    min_obs   = 5L           # require >= 5 obs per period
  )

  jan_row <- dplyr::filter(result, lubridate::month(date) == 1L)
  feb_row <- dplyr::filter(result, lubridate::month(date) == 2L)

  # January has 5 obs — should be non-NA
  expect_false(is.na(jan_row$x))

  # February has 2 obs (< min_obs = 5) — should be NA
  expect_true(is.na(feb_row$x))
})

# ── Test 5: end_bizday snaps weekends to Friday ───────────────────────────────

test_that("end_bizday anchor snaps Saturday to Friday and Sunday to Friday", {
  # Find a month whose last calendar day is a Saturday
  # 2025-02: last cal day = 2025-02-28 (Friday) — good anchor for end test
  # Need months ending on Sat or Sun. Let's compute and pick.
  months_2025 <- seq(as.Date("2025-01-01"), as.Date("2025-12-01"), by = "month")
  sat_months  <- months_2025[lubridate::wday(lubridate::ceiling_date(months_2025, "month") - 1L, week_start = 1L) == 6L]
  sun_months  <- months_2025[lubridate::wday(lubridate::ceiling_date(months_2025, "month") - 1L, week_start = 1L) == 7L]

  # Use the first Saturday-ending and Sunday-ending months if they exist
  skip_if(length(sat_months) == 0L || length(sun_months) == 0L,
          "No Saturday- or Sunday-ending months found in 2025 — adjust test range")

  sat_month <- sat_months[[1L]]
  sun_month <- sun_months[[1L]]

  make_obs <- function(m) {
    tibble::tibble(date = m + 1L, strategy_ret = 0.01)
  }

  sat_result <- align_period(list(x = make_obs(sat_month)), to_period = "month", anchor = "end_bizday")
  sun_result <- align_period(list(x = make_obs(sun_month)), to_period = "month", anchor = "end_bizday")

  # Saturday last-cal-day → anchor must be Saturday - 1 = Friday
  sat_last_cal <- lubridate::ceiling_date(sat_month, "month") - 1L
  expect_equal(lubridate::wday(sat_result$date, week_start = 1L), 5L,
               info = paste("Saturday-ending month anchor:", sat_result$date))

  # Sunday last-cal-day → anchor must be Sunday - 2 = Friday
  expect_equal(lubridate::wday(sun_result$date, week_start = 1L), 5L,
               info = paste("Sunday-ending month anchor:", sun_result$date))
})

# ── Test 6: Empty input series doesn't error ──────────────────────────────────

test_that("empty series element produces all-NA column without error", {
  non_empty <- make_monthly_eom("2025-01-31", n = 3L)
  empty_s   <- tibble::tibble(date = as.Date(character(0)), strategy_ret = numeric(0))

  result <- align_period(
    series    = list(full = non_empty, empty_s = empty_s),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "compound"
  )

  expect_s3_class(result, "tbl_df")
  # All full rows should have non-empty values; empty_s column all NA
  expect_true(all(is.na(result$empty_s)))
  expect_false(all(is.na(result$full)))
})

# ── Test 7: Causal order guarantee (no look-ahead) ───────────────────────────

test_that("output anchor date >= every input date used for that period", {
  # Build a daily series for Jan 2025 and Feb 2025.
  jan_days <- seq(as.Date("2025-01-02"), as.Date("2025-01-31"), by = "day")
  jan_days <- jan_days[lubridate::wday(jan_days, week_start = 1L) <= 5L]
  feb_days <- seq(as.Date("2025-02-03"), as.Date("2025-02-28"), by = "day")
  feb_days <- feb_days[lubridate::wday(feb_days, week_start = 1L) <= 5L]

  all_days <- c(jan_days, feb_days)
  s <- tibble::tibble(date = all_days,
                      strategy_ret = seq_along(all_days) * 0.001)

  result <- align_period(
    series    = list(x = s),
    to_period = "month",
    anchor    = "end_bizday",
    method    = "compound"
  )

  # For each output row, verify anchor >= all input dates in that month
  for (i in seq_len(nrow(result))) {
    anchor_date <- result$date[[i]]
    period_start <- lubridate::floor_date(anchor_date, "month")
    period_inputs <- s$date[s$date >= period_start & s$date <= anchor_date]
    expect_true(
      all(period_inputs <= anchor_date),
      info = paste("Period", anchor_date, ": all input dates should be <= anchor")
    )
  }

  # Confirm February's anchor is NOT using any January data
  feb_anchor <- result$date[[2L]]
  jan_dates_in_feb_period <- s$date[s$date < as.Date("2025-02-01") &
                                      s$date > feb_anchor]
  expect_equal(length(jan_dates_in_feb_period), 0L)
})

# ── Test 8: Validation errors ─────────────────────────────────────────────────

test_that("non-list series triggers cli_abort", {
  expect_snapshot(
    error = TRUE,
    align_period(series = "not_a_list")
  )
})

test_that("bad to_period triggers cli_abort", {
  s <- list(x = make_monthly_eom())
  expect_snapshot(
    error = TRUE,
    align_period(series = s, to_period = "fortnight")
  )
})

test_that("bad anchor triggers cli_abort", {
  s <- list(x = make_monthly_eom())
  expect_snapshot(
    error = TRUE,
    align_period(series = s, anchor = "mid")
  )
})

test_that("missing value_col in series element triggers cli_abort", {
  # Tibble with wrong column name
  bad <- tibble::tibble(date = as.Date("2025-01-31"), wrong_col = 0.01)
  expect_snapshot(
    error = TRUE,
    align_period(series = list(x = bad), value_col = "strategy_ret")
  )
})
