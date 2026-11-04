testthat::local_edition(3)

# #865: ticker is a reusable string; cik is the issuer key. hd_fundamentals()
# must expose cik and accept a cik filter so a recycled ticker can never be
# silently attributed to the wrong issuer.
#
# The recycled-ticker cases write a tiny parquet to a tempdir and route
# hd_dataset_source() to it (no network, no sample-fixture change).

APC_ANADARKO <- "0000773910"
APC_ARKO     <- "0001835022"

.fund_row <- function(ticker, cik, period_end, first_filed, value) {
  tibble::tibble(
    ticker = ticker, cik = cik, fiscal_period = "2018Q4",
    period_end = as.Date(period_end), first_filed = as.Date(first_filed),
    xbrl_tag = "Revenues", original_value = value,
    latest_value = value, restated = FALSE, source = "synthetic test"
  )
}

local_fundamentals_parquet <- function(df, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".parquet", .local_envir = env)
  arrow::write_parquet(df, path)
  testthat::local_mocked_bindings(
    hd_dataset_source = function(...) path,
    .package = "historicaldata", .env = env
  )
  invisible(path)
}

recycled_df <- function() {
  dplyr::bind_rows(
    .fund_row("APC", APC_ANADARKO, "2018-12-31", "2019-02-20", 1e10),
    .fund_row("APC", APC_ARKO,     "2024-12-31", "2025-03-01", 2e9)
  )
}

test_that("hd_fundamentals output carries cik (sample fixture)", {
  local_sample_data()
  result <- hd_fundamentals("AAPL")
  expect_true("cik" %in% names(result))
  expect_true(all(grepl("^[0-9]{10}$", result$cik)))
  expect_equal(length(unique(result$cik)), 1L)
})

test_that("hd_fundamentals(cik=) filters to one issuer (sample fixture)", {
  local_sample_data()
  aapl_cik <- hd_fundamentals("AAPL")$cik[[1]]
  by_cik <- hd_fundamentals(cik = aapl_cik)
  expect_true(nrow(by_cik) > 0)
  expect_true(all(by_cik$cik == aapl_cik))
  expect_true(all(by_cik$ticker == "AAPL"))
  expect_equal(nrow(hd_fundamentals(cik = "0000000001")), 0L)
})

test_that("#865 regression: a recycled ticker is separable by cik", {
  local_fundamentals_parquet(recycled_df())
  anadarko <- suppressWarnings(hd_fundamentals("APC", cik = APC_ANADARKO))
  expect_equal(unique(anadarko$cik), APC_ANADARKO)
  expect_equal(nrow(anadarko), 1L)
  expect_equal(unique(hd_fundamentals(cik = APC_ARKO)$cik), APC_ARKO)
})

test_that("#865: ticker-only query hitting two issuers warns loudly, names both", {
  local_fundamentals_parquet(recycled_df())
  expect_warning(
    res <- hd_fundamentals("APC"),
    class = "hd_fundamentals_ticker_multi_cik"
  )
  expect_equal(sort(unique(res$cik)), sort(c(APC_ANADARKO, APC_ARKO)))
  expect_snapshot(hd_fundamentals("APC"))
})

test_that("#865: a cik-qualified query does not warn", {
  local_fundamentals_parquet(recycled_df())
  expect_no_warning(hd_fundamentals("APC", cik = APC_ARKO))
})

test_that("hd_fundamentals aborts on a malformed cik", {
  local_sample_data()
  expect_error(hd_fundamentals(cik = 320193), class = "hd_fundamentals_bad_cik")
  expect_error(hd_fundamentals(cik = "320193"), class = "hd_fundamentals_bad_cik")
  expect_error(hd_fundamentals(cik = NA_character_), class = "hd_fundamentals_bad_cik")
  expect_snapshot(error = TRUE, hd_fundamentals(cik = "320193"))
})

test_that("hd_fundamentals aborts when the parquet has no cik column", {
  df <- recycled_df()
  df$cik <- NULL
  local_fundamentals_parquet(df)
  expect_error(hd_fundamentals("APC"), class = "hd_fundamentals_no_cik_column")
  expect_snapshot(error = TRUE, hd_fundamentals("APC"))
})
