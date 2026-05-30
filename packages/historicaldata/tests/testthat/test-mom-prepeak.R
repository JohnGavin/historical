# Tests for hd_mom_prepeak_signal() — Büsing et al. (2022) pre-peak / post-peak
# 12-2 momentum decomposition.
#
# Fixtures are self-contained (no parquet files, no ltr_universe dependency).
# All dates and price series are manufactured analytically.

# ---- Shared fixture builder --------------------------------------------------

# Build a minimal daily_prices tibble for N tickers over a common date range.
# price_fn(ticker, date_index) -> numeric adjusted price.
make_prices <- function(tickers, dates, price_fn) {
  rows <- lapply(tickers, function(tk) {
    tibble::tibble(
      ticker   = tk,
      date     = dates,
      adjusted = price_fn(tk, seq_along(dates))
    )
  })
  dplyr::bind_rows(rows)
}

# ---- 1. Input validation: non-data.frame -----------------------------------------

test_that("hd_mom_prepeak_signal rejects non-data.frame input", {
  expect_snapshot(
    error = TRUE,
    hd_mom_prepeak_signal("not a data frame", as_of_dates = as.Date("2026-01-31"))
  )
})

# ---- 2. Input validation: missing columns ----------------------------------------

test_that("hd_mom_prepeak_signal rejects missing columns", {
  expect_snapshot(
    error = TRUE,
    hd_mom_prepeak_signal(
      tibble::tibble(ticker = "X"),
      as_of_dates = as.Date("2026-01-31")
    )
  )
})

# ---- 3. Decomposition identity: (1+pre)(1+post) == (1+total) --------------------

test_that("decomposition identity holds: (1+pre)(1+post) == (1+total)", {
  # 252 daily observations across a single 12-month formation window.
  # Prices: start at 100, peak at day 180 (price 150), end at 120.
  # Formation window ends 2 months before as_of_date.
  set.seed(42)
  n_days <- 252L

  # as_of_date is 2 months after the last formation day, so the window is
  # [as_of - 12mo, as_of - 2mo].  We set as_of = 2026-01-31 so
  # formation_end = 2025-11-30 and formation_start = 2025-01-31.
  dates   <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  # Spike at day 180
  prices  <- c(
    seq(100, 150, length.out = 180),
    seq(150, 120, length.out = n_days - 180 + 1L)[-1L]
  )
  dp <- tibble::tibble(ticker = "A", date = dates, adjusted = prices)

  res <- hd_mom_prepeak_signal(
    dp,
    as_of_dates           = as.Date("2026-01-31"),
    lookback_months_start = 12L,
    lookback_months_end   = 2L,
    min_obs_days          = 100L
  )

  expect_equal(nrow(res), 1L)
  # Identity: (1 + pre) * (1 + post) == (1 + total)
  lhs <- (1 + res$pre_peak_return) * (1 + res$post_peak_return)
  rhs <- 1 + res$total_return
  expect_equal(lhs, rhs, tolerance = 1e-10)
})

# ---- 4. Peak on formation-start -> pre_peak == 0 ----------------------------------

test_that("peak on formation-start gives pre_peak_return == 0", {
  # Monotone-decreasing prices: first day is the highest.
  n_days <- 200L
  dates  <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  prices <- seq(200, 100, length.out = n_days)
  dp <- tibble::tibble(ticker = "B", date = dates, adjusted = prices)

  res <- hd_mom_prepeak_signal(
    dp,
    as_of_dates           = as.Date("2026-01-31"),
    lookback_months_start = 12L,
    lookback_months_end   = 2L,
    min_obs_days          = 100L
  )

  expect_equal(nrow(res), 1L)
  expect_equal(res$pre_peak_return, 0, tolerance = 1e-10)
  expect_equal(res$post_peak_return, res$total_return, tolerance = 1e-10)
  expect_equal(res$peak_position, 0, tolerance = 1e-10)
})

# ---- 5. Peak on formation-end -> post_peak == 0 ----------------------------------

test_that("peak on formation-end gives post_peak_return == 0", {
  # Monotone-increasing prices: last day is the highest.
  n_days <- 200L
  dates  <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  prices <- seq(100, 200, length.out = n_days)
  dp <- tibble::tibble(ticker = "C", date = dates, adjusted = prices)

  res <- hd_mom_prepeak_signal(
    dp,
    as_of_dates           = as.Date("2026-01-31"),
    lookback_months_start = 12L,
    lookback_months_end   = 2L,
    min_obs_days          = 100L
  )

  expect_equal(nrow(res), 1L)
  expect_equal(res$post_peak_return, 0, tolerance = 1e-10)
  expect_equal(res$pre_peak_return, res$total_return, tolerance = 1e-10)
  expect_equal(res$peak_position, 1, tolerance = 1e-10)
})

# ---- 6. Look-ahead safety -------------------------------------------------------

test_that("look-ahead safety: signal at t uses no data at or after t", {
  # Fixture: prices are normal through the formation window, then CRASH TO ZERO
  # on as_of_date and beyond.
  # The decomposition must be identical whether or not the crash rows are present.
  n_form <- 220L
  dates_form <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_form)

  prices_form <- c(
    seq(100, 150, length.out = 110),
    seq(150, 120, length.out = n_form - 110 + 1L)[-1L]
  )

  dp_without_crash <- tibble::tibble(
    ticker   = "D",
    date     = dates_form,
    adjusted = prices_form
  )

  # Add crash rows at and after as_of_date
  crash_dates  <- seq.Date(as.Date("2026-01-31"), by = "day", length.out = 30L)
  crash_prices <- rep(0.0001, 30L)
  dp_with_crash <- dplyr::bind_rows(
    dp_without_crash,
    tibble::tibble(ticker = "D", date = crash_dates, adjusted = crash_prices)
  )

  res_no  <- hd_mom_prepeak_signal(dp_without_crash, as.Date("2026-01-31"),
                                   min_obs_days = 100L)
  res_yes <- hd_mom_prepeak_signal(dp_with_crash,    as.Date("2026-01-31"),
                                   min_obs_days = 100L)

  # Decompositions must be identical regardless of the crash rows
  expect_equal(res_no$pre_peak_return,  res_yes$pre_peak_return,  tolerance = 1e-10)
  expect_equal(res_no$post_peak_return, res_yes$post_peak_return, tolerance = 1e-10)
  expect_equal(res_no$total_return,     res_yes$total_return,     tolerance = 1e-10)
  expect_equal(res_no$peak_date,        res_yes$peak_date)
})

# ---- 7. Ties in peak resolve to first occurrence ----------------------------------

test_that("ties in peak resolve to first occurrence (which.max semantics)", {
  # Two days with the same maximum price, earlier date should win.
  n_days  <- 200L
  dates   <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  prices  <- rep(100, n_days)
  prices[50L]  <- 200  # first peak
  prices[100L] <- 200  # identical second peak

  dp <- tibble::tibble(ticker = "E", date = dates, adjusted = prices)

  res <- hd_mom_prepeak_signal(
    dp,
    as_of_dates   = as.Date("2026-01-31"),
    min_obs_days  = 100L
  )

  expect_equal(nrow(res), 1L)
  expect_equal(res$peak_date, dates[50L])
})

# ---- 8. Rows below min_obs_days are dropped, not NA ------------------------------

test_that("rows below min_obs_days are dropped, not returned as NA", {
  # Only 10 trading days in the formation window — far below any sensible min_obs.
  dates  <- seq.Date(as.Date("2025-12-01"), by = "day", length.out = 10L)
  dp <- tibble::tibble(ticker = "F", date = dates, adjusted = seq(100, 110, length.out = 10L))

  res <- hd_mom_prepeak_signal(
    dp,
    as_of_dates   = as.Date("2026-01-31"),
    min_obs_days  = 100L
  )

  expect_equal(nrow(res), 0L)
  # No NA rows — the data frame is simply empty
  expect_true(all(!is.na(res$pre_peak_return)))
})

# ---- 9. Snapshot: output structure is stable ------------------------------------

test_that("output structure is stable", {
  set.seed(7)
  n_days <- 220L
  dates  <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  dp <- tibble::tibble(
    ticker   = rep(c("G", "H"), each = n_days),
    date     = rep(dates, times = 2L),
    adjusted = c(
      seq(100, 130, length.out = n_days),
      seq(130, 100, length.out = n_days)
    )
  )

  res <- hd_mom_prepeak_signal(dp, as_of_dates = as.Date("2026-01-31"),
                               min_obs_days = 100L)
  expect_snapshot(str(res))
})

# ---- 10. Snapshot: monotone-increasing series -> peak_position == 1 everywhere --

test_that("peak_position is 1 for all tickers on a monotone-increasing series", {
  # Monotone increase: peak is always on the last window day.
  n_days  <- 200L
  dates   <- seq.Date(as.Date("2025-01-31"), by = "day", length.out = n_days)
  tickers <- paste0("T", 1:4)

  dp <- make_prices(tickers, dates, price_fn = function(tk, idx) 100 + idx)

  as_of <- as.Date("2026-01-31")
  res   <- hd_mom_prepeak_signal(dp, as_of_dates = as_of, min_obs_days = 100L)

  expect_true(nrow(res) > 0L)
  # All peaks on last day of window
  expect_true(all(abs(res$peak_position - 1) < 1e-10),
              info = paste("peak_positions:", paste(res$peak_position, collapse = ", ")))

  expect_snapshot(
    summary(res$peak_position)
  )
})
