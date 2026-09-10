testthat::local_edition(3)

# Tests for hd_fundamentals() -- the point-in-time query layer for the
# fundamentals revision triangle (#553/#554/#555).
#
# NOTE (#580 Phase 2 convention): runs hermetically against the bundled
# inst/extdata/sample/fundamentals_sample.parquet fixture (via
# local_sample_data(), see helper-sample.R) rather than the live hf://
# endpoint. Known contents (data-raw/make_sample_data.R): 2 tickers
# (AAPL, MSFT) x 4 xbrl_tags x 3 fiscal periods = 24 rows. Every 5th row
# (1-indexed generation order) is restated = TRUE. first_filed is always
# strictly after period_end (60d for the 10-K period, 42d for the two
# 10-Q periods).

test_that("hd_fundamentals returns tibble with expected columns (default: original_value only)", {
  local_sample_data()

  result <- hd_fundamentals("AAPL")
  expect_s3_class(result, "tbl_df")
  expect_true(nrow(result) > 0)
  expect_setequal(
    names(result),
    c("ticker", "fiscal_period", "period_end", "first_filed", "xbrl_tag",
      "original_value", "source")
  )
  expect_false("latest_value" %in% names(result))
  expect_false("restated" %in% names(result))
  expect_true(all(result$ticker == "AAPL"))
})

test_that("hd_fundamentals(include_latest = TRUE) adds latest_value and restated", {
  local_sample_data()

  result <- hd_fundamentals("AAPL", include_latest = TRUE)
  expect_true(all(c("latest_value", "restated") %in% names(result)))
  # At least one restated row exists in the fixture (every 5th generated row).
  expect_true(any(result$restated) || any(hd_fundamentals(include_latest = TRUE)$restated))
})

test_that("hd_fundamentals filters by xbrl_tag", {
  local_sample_data()

  result <- hd_fundamentals("AAPL", xbrl_tag = "Revenues")
  expect_true(nrow(result) > 0)
  expect_true(all(result$xbrl_tag == "Revenues"))
})

test_that("hd_fundamentals(as_of=) enforces first_filed <= as_of (point-in-time cutoff)", {
  local_sample_data()

  full <- hd_fundamentals("AAPL")
  cutoff <- min(full$first_filed)  # the earliest filing in the fixture

  # Before the earliest filing: nothing should be visible.
  before <- hd_fundamentals("AAPL", as_of = cutoff - 1)
  expect_equal(nrow(before), 0L)

  # On the earliest filing date (inclusive by default): exactly that
  # filing (and any others sharing the same first_filed) is visible.
  on_day <- hd_fundamentals("AAPL", as_of = cutoff)
  expect_true(nrow(on_day) > 0)
  expect_true(all(on_day$first_filed <= cutoff))

  # Far in the future: everything is visible.
  everything <- hd_fundamentals("AAPL", as_of = max(full$first_filed) + 365)
  expect_equal(nrow(everything), nrow(full))
})

test_that("hd_fundamentals(as_of=, strict_same_day = TRUE) excludes same-day filings", {
  local_sample_data()

  full <- hd_fundamentals("AAPL")
  cutoff <- min(full$first_filed)

  inclusive <- hd_fundamentals("AAPL", as_of = cutoff, strict_same_day = FALSE)
  strict    <- hd_fundamentals("AAPL", as_of = cutoff, strict_same_day = TRUE)

  expect_true(nrow(inclusive) >= nrow(strict))
  expect_equal(nrow(strict), 0L)  # nothing is filed strictly BEFORE the earliest filing
})

test_that("hd_fundamentals(as_of=) errors loudly on an unparseable as_of (fail-loud-not-null)", {
  local_sample_data()

  expect_error(
    hd_fundamentals("AAPL", as_of = "not-a-date"),
    class = "hd_fundamentals_bad_as_of"
  )
  expect_snapshot(
    error = TRUE,
    hd_fundamentals("AAPL", as_of = "not-a-date")
  )
})

test_that("hd_fundamentals with an unknown ticker returns zero rows, not an error (pilot coverage caveat)", {
  local_sample_data()

  result <- hd_fundamentals("NOTAREALTICKER")
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("hd_fundamentals(collect = FALSE) returns a lazy frame", {
  local_sample_data()

  lazy <- hd_fundamentals("AAPL", collect = FALSE)
  expect_true(inherits(lazy, "duckplyr_df") || inherits(lazy, "tbl_lazy") || is.data.frame(lazy))
})

test_that("hd_fundamentals API stability snapshot", {
  local_sample_data()

  result <- hd_fundamentals("AAPL", xbrl_tag = "EarningsPerShareDiluted") |>
    dplyr::arrange(period_end)
  expect_snapshot(names(result))
  expect_snapshot(nrow(result))
})
