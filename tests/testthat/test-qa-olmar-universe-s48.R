testthat::local_edition(3)
# Tests for S48 (OLMAR-1 declared universe == tested universe), Refs #976, #977.
#
# #976: the hypothesis declared 30 tickers; the price matrix held 20, because
# a ticker that returns no rows is dropped silently by olmar_prices. S48 fails
# whenever the declared list and the price-matrix columns differ in EITHER
# direction. Three outcomes, never collapsed: PASS / FAIL (qa_s48_fail) /
# INDETERMINATE (qa_s48_indeterminate).

source(here::here("R/plan_qa_gates.R"))

run <- function(declared, tested) {
  check_olmar_universe(build_olmar_universe_table(declared, tested))
}

test_that("PASS when declared and tested universes are identical (any order)", {
  out <- run(c("SPY", "QQQ", "AAPL"), c("AAPL", "SPY", "QQQ"))
  s <- attr(out, "summary")
  expect_identical(s[["fail"]], 0L)
  expect_identical(s[["examined"]], 3L)
})

test_that("FAIL when a declared ticker is absent from the tested matrix (#976 shape)", {
  declared <- c("SPY", "XLF", "XLRE", "AAPL")
  tested   <- c("SPY", "AAPL")
  expect_error(run(declared, tested), class = "qa_s48_fail")
  tbl <- build_olmar_universe_table(declared, tested)
  expect_setequal(tbl$ticker[tbl$verdict == "FAIL"], c("XLF", "XLRE"))
})

test_that("FAIL when a tested ticker was never declared", {
  expect_error(run(c("SPY"), c("SPY", "AAPL")), class = "qa_s48_fail")
})

test_that("INDETERMINATE (not PASS, not FAIL) on NULL or empty input", {
  expect_error(run(NULL, c("SPY")), class = "qa_s48_indeterminate")
  expect_error(run(c("SPY"), NULL), class = "qa_s48_indeterminate")
  expect_error(run(character(0), character(0)), class = "qa_s48_indeterminate")
})

test_that("a duplicated or NA declared ticker is a FAIL, not silently deduplicated", {
  expect_error(run(c("SPY", "SPY"), c("SPY")), class = "qa_s48_fail")
  expect_error(run(c("SPY", NA), c("SPY")), class = "qa_s48_fail")
})

test_that("the real plan: declared olmar_params$tickers is the 20 tested tickers", {
  source(here::here("R/plan_olmar.R"))
  bt_partitions <- list(equity = list(train_end = as.Date("2019-12-31"),
                                      test_start = as.Date("2020-01-01"),
                                      test_end = as.Date("2024-12-31"),
                                      val_start = as.Date("2025-01-01")))
  tgt <- Filter(function(t) identical(t$settings$name, "olmar_params"), plan_olmar())[[1]]
  params <- eval(tgt$command$expr, list(bt_partitions = bt_partitions))
  expect_length(params$tickers, 20L)
  expect_false(anyDuplicated(params$tickers) > 0L)
  sector_spdrs <- c("XLF", "XLE", "XLV", "XLK", "XLI", "XLP", "XLU", "XLB", "XLY", "XLRE")
  expect_length(intersect(params$tickers, sector_spdrs), 0L)
})
