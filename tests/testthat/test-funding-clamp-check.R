testthat::local_edition(3)
source(here::here("R/funding_clamp_check.R"))

# R/funding_clamp_check.R (#1072). Synthetic frames with a known answer; no
# file, no network.

.ts <- function(x) as.POSIXct(x, tz = "UTC")

.row <- function(time, premium, rate, dex = "", coin = "BTC", interval_hours = 1) {
  data.frame(
    dex = dex, coin = coin, time = .ts(time), premium = premium,
    interval_hours = interval_hours, rate_per_hour = rate,
    stringsAsFactors = FALSE
  )
}

# BTC hourly, from 2024: pinned inside [-0.0004, 0.0006] (edges included),
# tracking premium/8 outside it.
.btc_2024 <- rbind(
  .row("2024-01-10 00:00:00", -0.0004, FC_BASE_RATE),   # lower edge, pinned
  .row("2024-01-10 01:00:00", 0, FC_BASE_RATE),
  .row("2024-01-10 02:00:00", 0.0003, FC_BASE_RATE),
  .row("2024-01-10 03:00:00", 0.0006, FC_BASE_RATE),    # upper edge, pinned
  .row("2024-01-10 04:00:00", 0.001, 0.001 / 8),        # above band, tracks
  .row("2024-01-10 05:00:00", -0.001, -0.001 / 8)       # below band, tracks
)
# 2023Q3: band not yet fixed, three in-band rows NOT pinned, one pinned.
.btc_2023 <- rbind(
  .row("2023-08-01 00:00:00", 0.0002, 0.0002 / 8),
  .row("2023-08-01 01:00:00", 0.00015, 0.00015 / 8),  # NOT 0.0001: that / 8 is the base
  .row("2023-08-01 02:00:00", 0.0003, 0.0003 / 8),
  .row("2023-08-01 03:00:00", 0, FC_BASE_RATE)
)
# Rows that must be ignored: other coin, other dex, 8-hourly era.
.noise <- rbind(
  .row("2024-01-10 00:00:00", 0.0002, 0.5, coin = "ETH"),
  .row("2024-01-10 00:00:00", 0.0002, 0.5, dex = "xyz"),
  .row("2024-01-10 00:00:00", 0.0002, 0.5, interval_hours = 8)
)
.btc <- rbind(.btc_2023, .btc_2024, .noise)

test_that("fc_is_pinned and fc_in_band use the named base and closed band", {
  expect_equal(fc_is_pinned(c(FC_BASE_RATE, 2e-5, NA)), c(TRUE, FALSE, NA))
  expect_equal(fc_in_band(c(FC_BAND_LO, FC_BAND_HI, 0.00061, -0.00041)),
               c(TRUE, TRUE, FALSE, FALSE))
})

test_that("fc_quarter labels UTC calendar quarters", {
  expect_equal(fc_quarter(.ts(c("2023-06-30 23:00:00", "2023-07-01 00:00:00"))),
               c("2023Q2", "2023Q3"))
})

test_that("fc_band_by_quarter counts the mismatches per quarter", {
  q <- fc_band_by_quarter(.btc)
  expect_equal(q$quarter, c("2023Q3", "2024Q1"))
  expect_equal(q$n, c(4L, 6L))
  expect_equal(q$inband_not_pinned, c(3L, 0L))
  expect_equal(q$pinned_out_band, c(0L, 0L))
  expect_equal(q$pmin_pinned, c(0, FC_BAND_LO))
  expect_equal(q$pmax_pinned, c(0, FC_BAND_HI))
})

test_that("a pinned row outside the band is counted in pinned_out_band", {
  d <- rbind(.btc_2024, .row("2024-01-10 06:00:00", 0.002, FC_BASE_RATE))
  q <- fc_band_by_quarter(d)
  expect_equal(q$pinned_out_band, 1L)
})

test_that("band edges swapped goes red", {
  # Swapped edges: the guard refuses, so a caller cannot get a silent zero.
  expect_error(fc_band_by_quarter(.btc, band_lo = FC_BAND_HI, band_hi = FC_BAND_LO),
               "inverted")
  # And the membership test itself would put no row in the band, so the
  # in-band-not-pinned count of 3 asserted above could not be reproduced.
  expect_false(any(fc_in_band(c(0, 0.0003), lo = FC_BAND_HI, hi = FC_BAND_LO)))
  expect_true(all(fc_in_band(c(0, 0.0003))))
})

test_that("fc_btc_summary reports share pinned, unexplained and SS share", {
  s <- fc_btc_summary(.btc, year = 2024L)
  expect_equal(s$period, c("all", "2024"))
  expect_equal(s$n, c(10L, 6L))
  expect_equal(s$pct_pinned, c(50, 4 / 6 * 100))
  # Pinned share of SS about the mean is the pinned rows' squared deviations.
  p <- .btc_2024$premium
  expect_equal(s$pct_ss_pinned[2], 100 * sum((p[1:4] - mean(p))^2) / sum((p - mean(p))^2))
  expect_equal(s$pct_unexplained[2], 100 * (1 - cor(p, .btc_2024$rate_per_hour)^2))
  expect_true(all(s$pct_unexplained > 0 & s$pct_unexplained < 100))
})

test_that("fc_xyz_summary finds per-market modal bases among big-enough markets", {
  a <- data.frame(dex = "xyz", coin = "A", time = .ts("2025-01-01 00:00:00") + 3600 * 0:5,
                  premium = c(0, 0.0001, 0.0002, 0.0003, 0.001, 0.002),
                  interval_hours = 1,
                  rate_per_hour = c(0, 0, 0, 0, 1e-4, 2e-4))
  b <- data.frame(dex = "xyz", coin = "B", time = .ts("2025-01-01 00:00:00") + 3600 * 0:4,
                  premium = c(0, 0.0001, 0.0002, 0.001, 0.002),
                  interval_hours = 1,
                  rate_per_hour = c(6.25e-06, 6.25e-06, 6.25e-06, 1e-4, 2e-4))
  small <- data.frame(dex = "xyz", coin = "C", time = .ts("2025-01-01 00:00:00") + 3600 * 0:1,
                      premium = c(0, 1), interval_hours = 1, rate_per_hour = c(0, 1))
  s <- fc_xyz_summary(rbind(a, b, small, .btc), min_rows = 5L)
  expect_equal(s$markets, 2L)
  expect_equal(s$med_pct_pinned, mean(c(4 / 6, 3 / 5)) * 100)
  expect_equal(s$n_distinct_base, 2L)
  expect_equal(s$min_base, 0)
  expect_equal(s$max_base, 6.25e-06)
  expect_true(s$med_r2 > 0 && s$med_r2 <= 1)
})

test_that("missing columns abort with a message naming them", {
  expect_error(fc_btc_summary(.btc[, c("dex", "coin")]), "missing column")
})

test_that("fc_md_table prints counts exactly", {
  tab <- fc_md_table(data.frame(n = 30162L, x = 0.123456))
  expect_equal(tab[3], "| 30162 | 0.1235 |")
})
