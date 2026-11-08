# Tests for hd_trim_symbol_reuse() (#1041).
#
# A ticker can belong to an earlier, different company (an old firm delisted,
# the symbol reused years later). Bars before the LAST calendar gap longer than
# `max_gap_days` are dropped. All data is SYNTHETIC. testthat edition 3.

testthat::local_edition(3)

.tr_bars <- function(sym, dates, volume = 1000, close = 10) {
  tibble::tibble(symbol = sym, date = as.Date(dates), close = close,
                 volume = volume)
}

test_that("a gap longer than max_gap_days drops the bars before the last gap", {
  old <- seq(as.Date("2016-01-04"), by = "day", length.out = 10L)
  new <- seq(as.Date("2025-06-02"), by = "day", length.out = 5L)
  b <- .tr_bars("SNDK", c(old, new))
  out <- hd_trim_symbol_reuse(b)
  expect_equal(out$date, new)
  tr <- attr(out, "trimmed")
  expect_named(tr, c("symbol", "dropped_from", "dropped_to", "n_dropped"))
  expect_equal(tr$symbol, "SNDK")
  expect_equal(tr$dropped_from, min(old))
  expect_equal(tr$dropped_to, max(old))
  expect_equal(tr$n_dropped, 10L)
})

test_that("only the LAST long gap counts when there are several", {
  a <- as.Date("2016-01-04") + 0:2
  b <- as.Date("2018-01-04") + 0:2
  c <- as.Date("2020-01-04") + 0:2
  out <- hd_trim_symbol_reuse(.tr_bars("X", c(a, b, c)))
  expect_equal(out$date, c)
  expect_equal(attr(out, "trimmed")$n_dropped, 6L)
})

test_that("no long gap: bars unchanged and the trimmed table is empty", {
  d <- seq(as.Date("2020-01-01"), by = "day", length.out = 100L)
  b <- .tr_bars("AAA", d)
  out <- hd_trim_symbol_reuse(b)
  expect_equal(as.data.frame(out), as.data.frame(b), ignore_attr = TRUE)
  tr <- attr(out, "trimmed")
  expect_equal(nrow(tr), 0L)
  expect_named(tr, c("symbol", "dropped_from", "dropped_to", "n_dropped"))
})

test_that("a gap of exactly max_gap_days is not a gap; one day more is", {
  d1 <- as.Date("2020-01-01")
  keep <- hd_trim_symbol_reuse(.tr_bars("A", c(d1, d1 + 30L)))
  expect_equal(nrow(keep), 2L)
  trim <- hd_trim_symbol_reuse(.tr_bars("A", c(d1, d1 + 31L)))
  expect_equal(nrow(trim), 1L)
  wide <- hd_trim_symbol_reuse(.tr_bars("A", c(d1, d1 + 31L)), max_gap_days = 60L)
  expect_equal(nrow(wide), 2L)
})

test_that("zero-volume bars do not bridge a gap", {
  # Flat zero-volume bars fill the hole but are not trades: the gap stands.
  old <- as.Date("2016-01-04") + 0:2
  hole <- seq(as.Date("2016-06-01"), by = "day", length.out = 5L)
  new <- as.Date("2025-06-02") + 0:2
  b <- dplyr::bind_rows(
    .tr_bars("S", old),
    .tr_bars("S", hole, volume = 0),
    .tr_bars("S", new)
  )
  out <- hd_trim_symbol_reuse(b)
  expect_equal(out$date, new)
})

test_that("symbols are trimmed independently; a rename A -> B is unaffected", {
  # A ends at the rename (no internal gap); B starts at the rename.
  a <- seq(as.Date("2020-01-01"), by = "day", length.out = 60L)
  b <- seq(as.Date("2020-03-01"), by = "day", length.out = 60L)
  reused <- c(as.Date("2016-01-04") + 0:2, as.Date("2025-06-02") + 0:2)
  bars <- dplyr::bind_rows(.tr_bars("A", a), .tr_bars("B", b), .tr_bars("R", reused))
  out <- hd_trim_symbol_reuse(bars)
  expect_equal(sum(out$symbol == "A"), 60L)
  expect_equal(sum(out$symbol == "B"), 60L)
  expect_equal(sum(out$symbol == "R"), 3L)
  expect_equal(attr(out, "trimmed")$symbol, "R")
  # The rename still splices: the series of the one security is continuous.
  ex <- tibble::tibble(
    ticker = "A", index_exit_date = as.Date("2020-03-01"), exit_type = "ticker_change",
    new_ticker = "B", last_trade_date = as.Date(NA), last_close = NA_real_,
    exit_price_upper = NA_real_, exit_price_lower = NA_real_, has_bars = TRUE
  )
  s <- hd_pit_price_series(out[out$symbol %in% c("A", "B"), ], ex)
  expect_equal(unique(s$ticker), "B")
  expect_equal(nrow(s), nrow(unique(s["date"])))
})

test_that("input is validated", {
  expect_error(hd_trim_symbol_reuse(data.frame(a = 1)), "must be a data frame")
  b <- .tr_bars("A", as.Date("2020-01-01"))
  expect_error(hd_trim_symbol_reuse(b, max_gap_days = 0), "max_gap_days")
  expect_error(hd_trim_symbol_reuse(b, max_gap_days = NA_real_), "max_gap_days")
  expect_error(hd_trim_symbol_reuse(b, max_gap_days = c(1, 2)), "max_gap_days")
})

test_that("zero-row bars come back with an empty trimmed table", {
  out <- hd_trim_symbol_reuse(.tr_bars("A", as.Date("2020-01-01"))[0L, ])
  expect_equal(nrow(out), 0L)
  expect_equal(nrow(attr(out, "trimmed")), 0L)
})
