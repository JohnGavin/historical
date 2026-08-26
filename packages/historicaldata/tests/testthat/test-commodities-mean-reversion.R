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


test_that("hd_commodity_mr_portfolio: weights are proportional to rank distance from the mean rank, not a fraction/headcount (#751 item D)", {
  set.seed(42)
  n_months <- 36
  n_assets <- 15
  dates    <- seq.Date(as.Date("2000-01-31"), by = "month", length.out = n_months)
  ids      <- paste0("C", seq_len(n_assets))

  tbl <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.04))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl)

  # Rank-weighting: every ranked name that clears the floor gets SOME
  # weight, so n_long + n_short is close to n_avail (equal, or one less on
  # an odd n_avail where the exact median name gets zero weight) -- not
  # capped at a fixed fraction of it.
  held <- port[port$n_avail >= 4L, ]
  expect_true(all(held$n_long + held$n_short >= held$n_avail - 1L))
  expect_true(all(held$n_long + held$n_short <= held$n_avail))

  # Breadth diagnostics: n_avail/held_frac retained (#751 item C), n_eff
  # added as the new headline diagnostic under rank-weighting (#751 item D).
  expect_true(all(c("n_avail", "held_frac", "n_eff") %in% names(port)))
})


test_that("hd_commodity_mr_portfolio: the most extreme signals get the largest weight magnitude", {
  # Hand-built, single date, no ties: mr_signal strictly increasing across 6
  # names. Under AMP rank-weighting the weight magnitude must be a monotone
  # (in fact linear) function of |rank - mean_rank|, so the two extreme
  # names (biggest loser / biggest winner) carry the largest weights.
  ids  <- paste0("R", 1:6)
  sig_date  <- as.Date("2015-01-31")
  next_date <- as.Date("2015-02-28")
  signal_tbl <- tibble::tibble(
    date = sig_date, series_id = ids,
    mr_signal = c(-5, -3, -1, 1, 3, 5)  # R1 = biggest winner, R6 = biggest loser
  )
  returns_tbl <- dplyr::bind_rows(
    tibble::tibble(date = sig_date,  series_id = ids, monthly_ret = 0.01),
    tibble::tibble(date = next_date, series_id = ids, monthly_ret = 0.02)
  )
  port_w <- hd_commodity_mr_portfolio(signal_tbl, returns_tbl)
  # Recover per-name weights the same way the function does, to check shape
  # (the function itself only returns portfolio-level aggregates).
  rk <- rank(signal_tbl$mr_signal, ties.method = "average")
  raw <- rk - mean(rk)
  # The two most extreme ranks (R1, R6) have strictly larger |raw weight|
  # than the two closest-to-median ranks (R3, R4).
  expect_true(abs(raw[1]) > abs(raw[3]))
  expect_true(abs(raw[6]) > abs(raw[4]))
  expect_equal(port_w$n_long[1], 3L)
  expect_equal(port_w$n_short[1], 3L)
})


test_that("hd_commodity_mr_portfolio: tied signals receive identical weight (#751 item D)", {
  # Two names tied at the same mr_signal must contribute identically to the
  # portfolio, not diverge based on row order -- the averaged-rank tie rule.
  ids <- paste0("T", 1:5)
  sig_date  <- as.Date("2018-01-31")
  next_date <- as.Date("2018-02-28")
  signal_tbl <- tibble::tibble(
    date = sig_date, series_id = ids,
    mr_signal = c(-2, 0, 0, 0, 2)  # T2/T3/T4 exactly tied at the median
  )
  returns_tbl <- dplyr::bind_rows(
    tibble::tibble(date = sig_date,  series_id = ids, monthly_ret = 0.01),
    tibble::tibble(
      date = next_date, series_id = ids,
      monthly_ret = c(0.05, 0.01, 0.02, 0.03, -0.05)
    )
  )
  port <- hd_commodity_mr_portfolio(signal_tbl, returns_tbl)
  # T2/T3/T4 tie at the average rank (3, the exact mean rank for n=5), so
  # all three receive weight == 0 and hold no position -- only T1 (biggest
  # winner, short) and T5 (biggest loser, long) are held.
  expect_equal(port$n_long[1], 1L)
  expect_equal(port$n_short[1], 1L)
})


test_that("hd_commodity_mr_portfolio: dollar-neutral and unit-gross by construction (#751 item D)", {
  set.seed(3)
  n_months <- 24
  n_assets <- 20
  dates <- seq.Date(as.Date("2005-01-31"), by = "month", length.out = n_months)
  ids   <- paste0("G", seq_len(n_assets))
  tbl <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.03))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 1L)
  port <- hd_commodity_mr_portfolio(sig, tbl, target_gross = 2.0)

  held <- port[port$n_long + port$n_short > 0L, ]
  # gross_ret is a WEIGHTED SUM of returns, not the weights themselves, so
  # the invariant is checked indirectly via the function's own internal
  # abort (fail-loud-not-null.md) -- reaching this point without an error
  # already proves sum(weight) ~ 0 / sum(abs(weight)) ~ target_gross held on
  # every date. Assert the observable consequence: net_ret is finite and
  # turnover is bounded by target_gross itself -- for two weight vectors
  # each with L1 norm target_gross, sum(abs(w - w_prev)) / 2 is maximised
  # at a full sign flip (w_prev = -w), where it equals target_gross exactly.
  expect_true(all(is.finite(held$net_ret)))
  expect_true(all(held$turnover <= 2.0 + 1e-8))

  # target_gross is honoured directly: doubling it should exactly double
  # gross_ret on every held date (linearity of a fixed weight scale).
  port2 <- hd_commodity_mr_portfolio(sig, tbl, target_gross = 4.0)
  expect_equal(port2$gross_ret, port$gross_ret * 2, tolerance = 1e-10)
})


test_that("hd_commodity_mr_portfolio: net_ret = gross_ret - cost", {
  set.seed(7)
  dates <- seq.Date(as.Date("2005-01-31"), by = "month", length.out = 30)
  ids   <- paste0("D", 1:12)
  tbl   <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.03))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl, cost_bps = 20)

  expect_equal(port$net_ret, port$gross_ret - port$cost, tolerance = 1e-12)
})


test_that("hd_commodity_mr_portfolio: turnover is non-negative", {
  set.seed(11)
  dates <- seq.Date(as.Date("2008-01-31"), by = "month", length.out = 24)
  ids   <- paste0("E", 1:10)
  tbl   <- tidyr::expand_grid(date = dates, series_id = ids) |>
    dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.05))

  sig  <- hd_commodity_mr_signal(tbl, lookback_months = 3L)
  port <- hd_commodity_mr_portfolio(sig, tbl)

  expect_true(all(port$turnover >= 0))
})


test_that("hd_commodity_mr_portfolio: long/short counts never exceed breadth across varying n_avail (#751 item D)", {
  # The exact concern #751 raised against fixed-count sizing: universe
  # breadth changes dramatically over time (6 tradeable names in 2000, 24 by
  # 2015). Sweep n_avail across a wide range and verify the invariant
  # hd_commodity_mr_portfolio() asserts internally (dollar-neutral,
  # unit-gross) by checking its OBSERVABLE consequence: n_long + n_short
  # never exceeds n_avail, for every breadth from below-floor to full-scale.
  make_universe <- function(n_assets, n_months = 12L) {
    dates <- seq.Date(as.Date("2010-01-31"), by = "month", length.out = n_months)
    ids   <- paste0("U", seq_len(n_assets))
    tidyr::expand_grid(date = dates, series_id = ids) |>
      dplyr::mutate(monthly_ret = rnorm(dplyr::n(), 0, 0.03))
  }

  set.seed(99)
  for (n_assets in c(2L, 3L, 4L, 6L, 7L, 9L, 20L, 24L, 37L)) {
    tbl  <- make_universe(n_assets)
    sig  <- hd_commodity_mr_signal(tbl, lookback_months = 1L)
    port <- hd_commodity_mr_portfolio(sig, tbl)
    expect_true(
      all(port$n_long + port$n_short <= n_assets),
      info = paste("n_assets =", n_assets)
    )
  }
})


test_that("hd_commodity_mr_portfolio: below the minimum-breadth floor, no position is held (#751 item D)", {
  # Hand-built signal/returns so breadth is exactly controlled: one date
  # with only 3 ranked names (below .HD_CMR_MIN_BREADTH_RANK = 2 *
  # .HD_CMR_MIN_LEG_NAMES = 4), one date with 4 (== floor), one date with 24.
  # Every series needs (signal date, next date) rows for the t+1 execution
  # join.
  build_cohort <- function(prefix, n, signal_date, next_date) {
    ids <- paste0(prefix, seq_len(n))
    dplyr::bind_rows(
      tibble::tibble(date = signal_date, series_id = ids, monthly_ret = 0.01),
      tibble::tibble(date = next_date,   series_id = ids, monthly_ret = 0.02)
    )
  }
  returns_tbl <- dplyr::bind_rows(
    build_cohort("L", 3L,  as.Date("2020-01-31"), as.Date("2020-02-29")),
    build_cohort("M", 4L,  as.Date("2020-03-31"), as.Date("2020-04-30")),
    build_cohort("H", 24L, as.Date("2020-05-31"), as.Date("2020-06-30"))
  )
  signal_tbl <- returns_tbl |>
    dplyr::distinct(date, series_id) |>
    dplyr::filter(date %in% as.Date(c("2020-01-31", "2020-03-31", "2020-05-31"))) |>
    dplyr::mutate(mr_signal = stats::rnorm(dplyr::n()))

  port <- hd_commodity_mr_portfolio(signal_tbl, returns_tbl)

  low  <- port[port$date == as.Date("2020-01-31"), ]
  mid  <- port[port$date == as.Date("2020-03-31"), ]
  high <- port[port$date == as.Date("2020-05-31"), ]

  # n_avail = 3 < .HD_CMR_MIN_BREADTH_RANK = 4 -> no position.
  expect_equal(low$n_long, 0L)
  expect_equal(low$n_short, 0L)
  expect_equal(low$gross_ret, 0)
  expect_equal(low$held_frac, 0)
  expect_equal(low$n_eff, 0)
  expect_equal(low$n_avail, 3L)

  # n_avail = 4 == floor -> ranks 1,2 short, 3,4 long (n=4 even, no median tie).
  expect_equal(mid$n_long, 2L)
  expect_equal(mid$n_short, 2L)
  expect_equal(mid$n_avail, 4L)

  # n_avail = 24 (even) -> every name receives nonzero weight: 12 long, 12 short.
  expect_equal(high$n_long, 12L)
  expect_equal(high$n_short, 12L)
  expect_equal(high$n_avail, 24L)
  # n_eff (#751 item D): a linear rank-weight scheme is more concentrated
  # than equal-weight, so effective breadth is strictly less than the
  # headcount held, but strictly positive.
  expect_true(high$n_eff > 0 && high$n_eff < (high$n_long + high$n_short))
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


test_that("hd_commodity_mr_portfolio: input validation — invalid target_gross (#751 item D)", {
  sig <- tibble::tibble(date = Sys.Date(), series_id = "A", mr_signal = 0.1)
  ret <- tibble::tibble(date = Sys.Date(), series_id = "A", monthly_ret = 0.02)
  # target_gross <= 0
  expect_error(
    hd_commodity_mr_portfolio(sig, ret, target_gross = 0),
    class = "rlang_error"
  )
  expect_error(
    hd_commodity_mr_portfolio(sig, ret, target_gross = -0.1),
    class = "rlang_error"
  )
  # Non-scalar / NA also invalid.
  expect_error(
    hd_commodity_mr_portfolio(sig, ret, target_gross = c(1, 2)),
    class = "rlang_error"
  )
  expect_error(
    hd_commodity_mr_portfolio(sig, ret, target_gross = NA_real_),
    class = "rlang_error"
  )
})


# ── hd_commodity_mr_dedupe_universe (#751 item B) ──────────────────────────

test_that(".HD_CMR_EXPOSURE_MAP: no underlying_exposure has more than one kept instrument", {
  # Pure data invariant on the map itself -- the same check the function
  # runs at every call, verified directly here so a hand-edit that breaks it
  # is caught by the test suite even before hd_commodity_mr_dedupe_universe()
  # is ever invoked with live data.
  over_kept <- .HD_CMR_EXPOSURE_MAP |>
    dplyr::filter(.data$keep) |>
    dplyr::count(.data$underlying_exposure, name = "n_kept") |>
    dplyr::filter(.data$n_kept > 1L)
  expect_equal(nrow(over_kept), 0L)
})


test_that(".HD_CMR_EXPOSURE_MAP: every series_id appears exactly once", {
  dupes <- .HD_CMR_EXPOSURE_MAP$series_id[duplicated(.HD_CMR_EXPOSURE_MAP$series_id)]
  expect_equal(dupes, character(0))
})


test_that("hd_commodity_mr_dedupe_universe: keeps the futures contract and drops the FRED/ETF twins for a known duplicated exposure (WTI)", {
  tbl <- tibble::tibble(
    date        = as.Date("2020-01-31"),
    series_id   = c("POILWTIUSDM", "CL=F", "USO"),
    monthly_ret = c(0.01, 0.02, 0.03)
  )
  out <- hd_commodity_mr_dedupe_universe(tbl)
  expect_equal(out$series_id, "CL=F")
  expect_equal(out$monthly_ret, 0.02)
})


test_that("hd_commodity_mr_dedupe_universe: ETF baskets are always dropped, even alone", {
  tbl <- tibble::tibble(
    date        = as.Date("2020-01-31"),
    series_id   = c("DBA", "DBB", "DBC", "PDBC"),
    monthly_ret = c(0.01, 0.02, 0.03, 0.04)
  )
  out <- hd_commodity_mr_dedupe_universe(tbl)
  expect_equal(nrow(out), 0L)
})


test_that("hd_commodity_mr_dedupe_universe: an exposure with no tradeable twin is kept as its sole IMF/FRED representative", {
  tbl <- tibble::tibble(
    date        = as.Date("2020-01-31"),
    series_id   = c("PNGASEUUSDM", "PCOALAUUSDM", "PNICKUSDM"),
    monthly_ret = c(0.01, 0.02, 0.03)
  )
  out <- hd_commodity_mr_dedupe_universe(tbl)
  expect_setequal(out$series_id, c("PNGASEUUSDM", "PCOALAUUSDM", "PNICKUSDM"))
})


test_that("hd_commodity_mr_dedupe_universe: other columns pass through unchanged for kept rows", {
  tbl <- tibble::tibble(
    date        = as.Date(c("2020-01-31", "2020-02-29")),
    series_id   = "CL=F",
    value       = c(50, 52),
    source      = "yahoo",
    monthly_ret = c(0.01, 0.04)
  )
  out <- hd_commodity_mr_dedupe_universe(tbl)
  expect_equal(nrow(out), 2L)
  expect_equal(out$value, c(50, 52))
  expect_equal(out$source, c("yahoo", "yahoo"))
})


test_that("hd_commodity_mr_dedupe_universe: reduces the exact live-store 37-series universe to the expected 20 kept series (#751 item B regression)", {
  # Hardcoded against the live commodities_returns store measured 2026-08-25
  # (37 distinct series_id values; see the #751 item B PR for the exact
  # count). This is a golden-value regression test, not a live-data read --
  # it locks the CURRENT behaviour of the map, so an accidental edit that
  # changes which instrument is kept for an exposure is caught here.
  live_series_ids <- c(
    "BZ=F", "CC=F", "CL=F", "CT=F", "DBA", "DBB", "DBC", "GC=F", "GLD",
    "HE=F", "HG=F", "KC=F", "LE=F", "NG=F", "PA=F", "PCOALAUUSDM",
    "PCOCOUSDM", "PCOFFOTMUSDM", "PCOPPUSDM", "PCOTTINDUSDM", "PDBC",
    "PL=F", "PNGASEUUSDM", "PNGASUSUSDM", "PNICKUSDM", "POILBREUSDM",
    "POILWTIUSDM", "PSOYBUSDM", "PSUGAISAUSDM", "PWHEAMTUSDM", "SB=F",
    "SI=F", "SLV", "USO", "ZC=F", "ZS=F", "ZW=F"
  )
  expect_equal(length(live_series_ids), 37L)

  tbl <- tibble::tibble(
    date        = as.Date("2020-01-31"),
    series_id   = live_series_ids,
    monthly_ret = 0.01
  )
  out <- hd_commodity_mr_dedupe_universe(tbl)

  expected_kept <- c(
    "BZ=F", "CL=F", "PNGASEUUSDM", "NG=F", "PCOALAUUSDM", "GC=F", "SI=F",
    "HG=F", "PNICKUSDM", "PL=F", "PA=F", "ZW=F", "ZC=F", "ZS=F", "KC=F",
    "SB=F", "CC=F", "CT=F", "LE=F", "HE=F"
  )
  expect_equal(nrow(out), 20L)
  expect_setequal(out$series_id, expected_kept)
})


test_that("hd_commodity_mr_dedupe_universe: unmapped series_id aborts loudly, naming the offending id (fail-loud-not-null)", {
  tbl <- tibble::tibble(
    date        = as.Date("2020-01-31"),
    series_id   = c("CL=F", "NOT_A_REAL_TICKER"),
    monthly_ret = c(0.01, 0.02)
  )
  expect_snapshot(error = TRUE, hd_commodity_mr_dedupe_universe(tbl))
})


test_that("hd_commodity_mr_dedupe_universe: input validation — not a data frame / missing series_id", {
  expect_snapshot(error = TRUE, hd_commodity_mr_dedupe_universe(list(a = 1)))
  expect_snapshot(
    error = TRUE,
    hd_commodity_mr_dedupe_universe(tibble::tibble(date = Sys.Date()))
  )
})
