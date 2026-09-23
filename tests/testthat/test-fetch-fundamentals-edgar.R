testthat::local_edition(3)
source(here::here("scripts", "fetch_fundamentals_edgar.R"))

# Regression tests for scripts/fetch_fundamentals_edgar.R (#865).
#
# scripts/fetch_fundamentals_edgar.R defines its CIK-resolution logic as
# ordinary functions (resolve_ticker_cik(), filing_date_range_from_facts(),
# validate_cik_filing_overlap()) and wraps the network-fetching driver in
# .ffe_main(), which only runs when this file is the Rscript entry point
# (sys.nframe() == 0) -- same pattern as test-check-pkg-staleness.R uses for
# scripts/check_pkg_staleness.R. source()'ing it here (sys.nframe() > 0)
# loads the functions without triggering a live SEC EDGAR fetch.
#
# NO LIVE SEC DATA: these tests use a small synthetic/mocked SEC companyfacts
# payload (see make_synthetic_facts() below), not a live fetch, so the suite
# is deterministic and network-independent -- consistent with how the
# package's own live-endpoint tests are gated behind HD_TEST_LIVE
# (see tests/testthat/helper-skip.R) rather than run unconditionally. The
# fixture reproduces the SHAPE of the #865 defect (two CIKs registered
# against the ticker "APC", with non-overlapping 10-K filing windows) --
# Anadarko Petroleum's 2010-2019 filings vs. a later company's post-2020
# filings under the same recycled ticker -- not literal live filing dates.

# Build a companyfacts-shaped list carrying only the fields
# filing_date_range_from_facts() reads (form/filed under one us-gaap tag).
.make_synthetic_facts <- function(filed_dates, forms) {
  entries <- Map(function(fd, fm) {
    list(form = fm, filed = fd, end = fd, val = 1, fy = 2015L, fp = "FY")
  }, filed_dates, forms)
  names(entries) <- NULL
  list(facts = list(`us-gaap` = list(Revenues = list(units = list(USD = entries)))))
}

# Anadarko Petroleum: real historical filer for "APC" 2010-2019 (acquired by
# Occidental in 2019). ARKO: a later, unrelated company sharing the fixture's
# synthetic CIK/ticker row -- SYNTHETIC filing dates chosen only to be
# clearly non-overlapping with Anadarko's, not researched live data.
.anadarko_facts <- .make_synthetic_facts(
  filed_dates = c("2011-02-15", "2015-02-20", "2019-02-25"),
  forms = c("10-K", "10-K", "10-K")
)
.arko_facts <- .make_synthetic_facts(
  filed_dates = c("2021-03-10", "2022-03-08"),
  forms = c("10-K", "10-K")
)

test_that("resolve_ticker_cik returns one row per ticker when no collisions", {
  cik_map <- tibble::tibble(
    ticker = c("APC", "AAPL"),
    cik = c("0001835022", "0000320193"),
    title = c("ARKO CORP", "APPLE INC")
  )
  res <- resolve_ticker_cik(cik_map, c("APC", "AAPL"))
  expect_equal(nrow(res), 2L)
  expect_setequal(res$ticker, c("APC", "AAPL"))
})

test_that("resolve_ticker_cik aborts (does not silently keep first) on a duplicate ticker", {
  cik_map <- tibble::tibble(
    ticker = c("APC", "APC", "AAPL"),
    cik = c("0000773910", "0001835022", "0000320193"),
    title = c("ANADARKO PETROLEUM CORP", "ARKO CORP", "APPLE INC")
  )
  expect_snapshot(error = TRUE, resolve_ticker_cik(cik_map, c("APC", "AAPL")))
})

test_that("filing_date_range_from_facts extracts the 10-K/10-Q filed-date range", {
  rng <- filing_date_range_from_facts(.anadarko_facts)
  expect_equal(rng$min_filed, as.Date("2011-02-15"))
  expect_equal(rng$max_filed, as.Date("2019-02-25"))
})

test_that("filing_date_range_from_facts returns NA range when no KEEP_FORMS filing exists", {
  only_8k <- .make_synthetic_facts(filed_dates = c("2021-01-05"), forms = c("8-K"))
  rng <- filing_date_range_from_facts(only_8k)
  expect_true(is.na(rng$min_filed))
  expect_true(is.na(rng$max_filed))
})

test_that("#865 regression: validate_cik_filing_overlap accepts Anadarko for a pre-2019 APC window", {
  rng <- filing_date_range_from_facts(.anadarko_facts)
  result <- validate_cik_filing_overlap(
    "APC", "0000773910", "ANADARKO PETROLEUM CORP", rng,
    data_start = as.Date("2010-01-01"), data_end = as.Date("2018-12-31")
  )
  expect_true(result)
})

test_that("#865 regression: validate_cik_filing_overlap rejects ARKO's CIK for a pre-2019 APC window", {
  # This is the article's worked example (#865): SEC's *current* ticker map
  # would resolve "APC" to a later, unrelated company (here, ARKO's fixture
  # CIK/facts), not to Anadarko Petroleum, the real historical holder of
  # "APC" through its 2019 acquisition. Before this fix, nothing checked
  # this at all -- this assertion would have failed (no error thrown) on
  # the OLD code path, which had no filing-overlap check whatsoever.
  rng <- filing_date_range_from_facts(.arko_facts)
  expect_snapshot(error = TRUE, validate_cik_filing_overlap(
    "APC", "0001835022", "ARKO CORP", rng,
    data_start = as.Date("2010-01-01"), data_end = as.Date("2018-12-31")
  ))
})

test_that("validate_cik_filing_overlap aborts when the candidate has no KEEP_FORMS filings", {
  na_range <- list(min_filed = as.Date(NA), max_filed = as.Date(NA))
  expect_snapshot(error = TRUE, validate_cik_filing_overlap(
    "ZZZZ", "0000000001", "GHOST CORP", na_range
  ))
})
