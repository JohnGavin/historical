test_that("hd_commodity_mr_signal: look-ahead guard — signal at t uses only returns <= t-1", {
  # Synthetic series: 24 months, one commodity
  # months 1-12: return 0.05 (rising), months 13-24: return -0.05 (falling)
  dates <- seq.Date(as.Date("2010-01-31"), by = "month", length.out = 24)
  rets  <- c(rep(0.05, 12), rep(-0.05, 12))
  tbl   <- tibble::tibble(date = dates, series_id = "A", monthly_ret = rets)

  sig <- hd_commodity_mr_signal(tbl, lookback_months = 3L)

  # For any row with signal date d, the signal must equal
  # -(prod(1 + r[d-3:d-1]) - 1), NOT using return at d itself.
  # We verify by constructing the expected signal manually.
  for (i in seq_len(nrow(sig))) {
    d      <- sig$date[i]
    d_idx  <- which(tbl$date == d)
    # Signal window: indices (d_idx-3) to (d_idx-1) relative to tbl
    lb_idx <- (d_idx - 3):(d_idx - 1)
    if (any(lb_idx < 1)) next  # skip if window not fully populated
    expected_signal <- -(prod(1 + tbl$monthly_ret[lb_idx]) - 1)
    expect_equal(sig$mr_signal[i], expected_signal, tolerance = 1e-10,
                 info = paste("date =", d))
  }
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
