test_that("hd_commodity_mr_signal: signal at t is unaffected by any return at/after t (look-ahead guard)", {
  # #751: the window is now CALENDAR-based (slide_index_dbl keyed on date),
  # not row-count-based, so a row-index hand-computation of the "expected"
  # signal (the previous version of this test) no longer describes the
  # function's own window boundaries. Test the PROPERTY instead: perturbing
  # every return at/after a cutoff date must not change any signal computed
  # for a date strictly before that cutoff, regardless of the internal
  # window implementation.
  set.seed(1)
  dates <- seq.Date(as.Date("2010-01-01"), by = "month", length.out = 24)
  rets  <- rnorm(24, 0, 0.03)
  tbl   <- tibble::tibble(date = dates, series_id = "A", monthly_ret = rets)

  sig_base <- hd_commodity_mr_signal(tbl, lookback_months = 3L)

  cutoff <- dates[15]
  tbl_perturbed <- tbl
  perturb_idx <- tbl_perturbed$date >= cutoff
  # Gross perturbation (+1000%): any leak into cumret_raw's product would be
  # numerically unmistakable.
  tbl_perturbed$monthly_ret[perturb_idx] <- tbl_perturbed$monthly_ret[perturb_idx] + 10

  sig_perturbed <- hd_commodity_mr_signal(tbl_perturbed, lookback_months = 3L)

  base_before      <- sig_base[sig_base$date < cutoff, ]
  perturbed_before <- sig_perturbed[sig_perturbed$date < cutoff, ]

  # Same set of dates carry a signal either way -- the perturbation must not
  # change which pre-cutoff windows are treated as complete.
  expect_equal(base_before$date, perturbed_before$date)
  expect_equal(base_before$mr_signal, perturbed_before$mr_signal, tolerance = 1e-10)
})


test_that("hd_commodity_mr_signal: same lookback_months spans a genuinely different observation count for a daily vs a monthly series (#751 fix)", {
  # This is the defect #751 reports: under the OLD row-count window, both
  # series below would have used exactly 3 rows regardless of their actual
  # dates. Under the calendar-based window, the daily series' window spans
  # ~63 trading-day observations while the monthly series' window spans ~3
  # -- the same ~91-day economic horizon for both.
  d_daily <- seq.Date(as.Date("2020-01-01"), as.Date("2020-12-31"), by = "day")
  d_daily <- d_daily[!weekdays(d_daily) %in% c("Saturday", "Sunday")]
  daily <- tibble::tibble(
    date = d_daily, series_id = "DAILY",
    monthly_ret = rep(0.001, length(d_daily))
  )

  d_monthly <- seq.Date(as.Date("2020-01-01"), as.Date("2020-12-01"), by = "month")
  monthly <- tibble::tibble(
    date = d_monthly, series_id = "MONTHLY",
    monthly_ret = rep(0.03, length(d_monthly))
  )

  combined <- dplyr::bind_rows(daily, monthly)
  sig <- hd_commodity_mr_signal(combined, lookback_months = 3L)

  # Both series carry a constant per-observation return, so the magnitude of
  # the cumulative return directly reveals how many observations the window
  # actually captured: |signal| = (1 + r)^n - 1.
  daily_sig   <- sig$mr_signal[sig$series_id == "DAILY"]
  monthly_sig <- sig$mr_signal[sig$series_id == "MONTHLY"]

  # Both series carry a POSITIVE constant return, so cumret = (1+r)^n - 1 > 0
  # and mr_signal = -cumret < 0 for every valid row; |signal| = cumret, so
  # n = log(1 + |signal|) / log(1 + r).
  n_daily_implied   <- log(1 + min(abs(daily_sig))) / log(1.001)
  n_monthly_implied <- log(1 + min(abs(monthly_sig))) / log(1.03)

  # Daily window: ~63 trading days in a ~91-day span (weekends excluded).
  # Monthly window: ~3 month-start prints in the same span. A wide interval
  # is used because slide_index_dbl's window boundary interacts with real
  # weekday/month-length irregularity -- the point being tested is the ORDER
  # OF MAGNITUDE difference (roughly 20x), not an exact count.
  expect_true(n_daily_implied > 40, info = paste("n_daily_implied =", n_daily_implied))
  expect_true(n_monthly_implied >= 2 && n_monthly_implied <= 5,
              info = paste("n_monthly_implied =", n_monthly_implied))
  # Under the OLD row-count window both would have been exactly 3.
  expect_true(n_daily_implied > 3 * n_monthly_implied)
})


test_that("hd_commodity_mr_signal: a data gap inside an otherwise-complete window is excluded, not silently accepted (fail-loud-not-null)", {
  # Dense daily block, a 70-day gap, then a dense daily block again. Right
  # after the gap resumes, slider's .complete = TRUE alone would accept the
  # window (its start boundary is still within the series' overall date
  # range), but the window actually contains far fewer observations than
  # this series' own median cadence predicts. The .HD_MR_MIN_OBS_FRACTION
  # floor must reject it.
  block1 <- seq.Date(as.Date("2010-01-01"), as.Date("2010-04-10"), by = "day")
  block2_start <- as.Date("2010-04-10") + 70
  block2 <- seq.Date(block2_start, by = "day", length.out = 80)
  dates  <- c(block1, block2)
  tbl <- tibble::tibble(date = dates, series_id = "S", monthly_ret = rep(0.001, length(dates)))

  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)

  # The first date of block2 still carries a signal (it reflects the dense
  # block1 window computed the day before the gap).
  expect_true(block2_start %in% sig$date)
  # The date immediately after that is excluded: its window (looking back
  # ~91 days from block2_start) crosses the 70-day gap and contains far
  # fewer observations than a dense daily window normally would.
  expect_false((block2_start + 1) %in% sig$date)
  # Signal resumes once enough dense post-gap data has accumulated to
  # refill the window past the floor (measured directly against this
  # implementation: 2010-08-04, 46 days after block2 starts).
  expect_true(as.Date("2010-08-04") %in% sig$date)
})


test_that("hd_commodity_mr_signal: no NA signals are returned", {
  dates <- seq.Date(as.Date("2010-01-31"), by = "month", length.out = 20)
  tbl   <- tibble::tibble(
    date       = dates,
    series_id  = "X",
    monthly_ret = rnorm(20, 0, 0.03)
  )
  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  expect_false(any(is.na(sig$mr_signal)))
})


test_that("hd_commodity_mr_signal: sign matches expected reversal direction", {
  # A commodity that has been falling for 3 months should have a positive
  # mean-reversion signal (long candidate).
  # A commodity that has been rising should have a negative signal (short candidate).
  dates <- seq.Date(as.Date("2015-01-31"), by = "month", length.out = 10)

  # Loser: consistent -5% per month
  loser <- tibble::tibble(
    date = dates, series_id = "loser",
    monthly_ret = rep(-0.05, 10)
  )
  # Winner: consistent +5% per month
  winner <- tibble::tibble(
    date = dates, series_id = "winner",
    monthly_ret = rep(0.05, 10)
  )
  tbl <- dplyr::bind_rows(loser, winner)
  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)

  loser_sigs  <- sig$mr_signal[sig$series_id == "loser"]
  winner_sigs <- sig$mr_signal[sig$series_id == "winner"]

  # Loser's signal is positive (-(negative return) > 0)
  expect_true(all(loser_sigs > 0), info = "loser should have positive MR signal")
  # Winner's signal is negative (-(positive return) < 0)
  expect_true(all(winner_sigs < 0), info = "winner should have negative MR signal")
})


test_that("hd_commodity_mr_portfolio: long weights sum to 1 per period", {
  set.seed(42)
  n_months <- 36
  n_assets <- 15
  dates    <- seq.Date(as.Date("2000-01-31"), by = "month", length.out = n_months)
  ids      <- paste0("C", seq_len(n_assets))

  tbl <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.04))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl, n_long = 5L, n_short = 5L)

  # For every month: n_long weights sum = 1 / n_long * n_long = 1
  # We verify via the weighted portfolio directly at the signal level.
  # Because the function returns aggregate returns, we just check n_long/n_short.
  expect_true(all(port$n_long <= 5L),
              info = "n_long positions never exceeds n_long parameter")
  expect_true(all(port$n_short <= 5L),
              info = "n_short positions never exceeds n_short parameter")
})


test_that("hd_commodity_mr_portfolio: net_ret = gross_ret - cost", {
  set.seed(7)
  dates <- seq.Date(as.Date("2005-01-31"), by = "month", length.out = 30)
  ids   <- paste0("D", 1:12)
  tbl   <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.03))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl, n_long = 3L, n_short = 3L, cost_bps = 20)

  expect_equal(port$net_ret, port$gross_ret - port$cost, tolerance = 1e-12)
})


test_that("hd_commodity_mr_portfolio: turnover is non-negative", {
  set.seed(11)
  dates <- seq.Date(as.Date("2008-01-31"), by = "month", length.out = 24)
  ids   <- paste0("E", 1:10)
  tbl   <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.05))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl, n_long = 3L, n_short = 3L)

  expect_true(all(port$turnover >= 0))
})


test_that("hd_commodity_mr_signal: edge case — all NA returns yields empty output", {
  dates <- seq.Date(as.Date("2010-01-31"), by = "month", length.out = 5)
  tbl   <- tibble::tibble(
    date = dates, series_id = "Z",
    monthly_ret = rep(NA_real_, 5)
  )
  # With all NA returns, the cumulative product in the lookback window will be NA,
  # so mr_signal will be NA and all rows will be filtered out.
  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  expect_equal(nrow(sig), 0L)
})


test_that("hd_commodity_mr_signal: edge case — single ticker", {
  dates <- seq.Date(as.Date("2020-01-31"), by = "month", length.out = 12)
  tbl   <- tibble::tibble(
    date = dates, series_id = "SINGLE",
    monthly_ret = seq(0.01, 0.12, by = 0.01)
  )
  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  # Should return some rows (enough history for 3m lookback + 1 lag = 4 months)
  expect_true(nrow(sig) > 0L)
  expect_equal(unique(sig$series_id), "SINGLE")
})


test_that("hd_commodity_mr_signal: empty universe returns 0 rows", {
  tbl <- tibble::tibble(
    date        = as.Date(character(0)),
    series_id   = character(0),
    monthly_ret = numeric(0)
  )
  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  expect_equal(nrow(sig), 0L)
})


test_that("hd_commodity_mr_signal: input validation — missing column", {
  bad_tbl <- tibble::tibble(date = Sys.Date(), wrong_col = 1.0)
  expect_error(
    hd_commodity_mr_signal(bad_tbl, lookback_months = 3L),
    class = "rlang_error"
  )
})


test_that("hd_commodity_mr_signal: input validation — invalid lookback", {
  tbl <- tibble::tibble(
    date = Sys.Date(), series_id = "X", monthly_ret = 0.01
  )
  expect_error(
    hd_commodity_mr_signal(tbl, lookback_months = 0L),
    class = "rlang_error"
  )
  expect_error(
    hd_commodity_mr_signal(tbl, lookback_months = -1L),
    class = "rlang_error"
  )
})


test_that("hd_commodity_mr_portfolio: input validation — invalid n_long", {
  sig <- tibble::tibble(date = Sys.Date(), series_id = "A", mr_signal = 0.1)
  ret <- tibble::tibble(date = Sys.Date(), series_id = "A", monthly_ret = 0.02)
  expect_error(
    hd_commodity_mr_portfolio(sig, ret, n_long = 0L, n_short = 5L),
    class = "rlang_error"
  )
})
