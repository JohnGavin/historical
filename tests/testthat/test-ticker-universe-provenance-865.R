testthat::local_edition(3)
source(here::here("R/ticker_universe_provenance.R"))

# #865 sites 1/2 (AT-RISK rows): a universe selected from today's metadata
# snapshot is applied to full price history keyed on `ticker` alone. A
# point-in-time universe is #816 and is NOT built here; this helper records
# WHICH snapshot the selection came from so the risk travels with the output.

meta_fixture <- function() {
  tibble::tibble(
    ticker     = c("AAA", "BBB", "CCC"),
    market_cap = c(3e12, 2e12, 1e12),
    end_date   = as.Date(c("2026-10-30", "2026-10-29", "2026-10-30"))
  )
}

test_that("provenance records the as-of proxy, basis, key and size", {
  p <- ticker_universe_provenance(meta_fixture(), c("AAA", "BBB"), top_n = 2L)
  expect_s3_class(p, "tbl_df")
  expect_equal(nrow(p), 1L)
  expect_equal(p$n_selected, 2L)
  expect_equal(p$top_n, 2L)
  expect_equal(p$metadata_as_of_proxy, as.Date("2026-10-30"))
  expect_equal(p$min_selected_market_cap, 2e12)
  expect_equal(p$key, "ticker")
  expect_match(p$basis, "not point-in-time")
  expect_match(p$caveat, "#816")
  expect_match(p$caveat, "#865")
})

test_that("as-of is taken from the SELECTED rows only", {
  p <- ticker_universe_provenance(meta_fixture(), "BBB", top_n = 1L)
  expect_equal(p$metadata_as_of_proxy, as.Date("2026-10-29"))
})

test_that("a selected ticker missing from the metadata aborts and names it", {
  expect_error(
    ticker_universe_provenance(meta_fixture(), c("AAA", "ZZZ"), top_n = 2L),
    class = "ticker_universe_provenance_missing_ticker"
  )
  expect_snapshot(
    error = TRUE,
    ticker_universe_provenance(meta_fixture(), c("AAA", "ZZZ"), top_n = 2L)
  )
})

test_that("a ticker occurring twice in the snapshot warns (recycled-ticker symptom)", {
  m <- dplyr::bind_rows(meta_fixture(), meta_fixture()[1, ])
  expect_warning(
    ticker_universe_provenance(m, c("AAA", "BBB"), top_n = 2L),
    class = "ticker_universe_provenance_duplicate_ticker"
  )
})

test_that("no usable end_date aborts rather than reporting an unknown as-of", {
  m <- meta_fixture()
  m$end_date <- as.Date(NA)
  expect_error(
    ticker_universe_provenance(m, c("AAA", "BBB"), top_n = 2L),
    class = "ticker_universe_provenance_no_asof"
  )
})

test_that("bad inputs abort: missing columns, empty selection", {
  expect_error(
    ticker_universe_provenance(meta_fixture()[, c("ticker", "market_cap")], "AAA", 1L),
    class = "ticker_universe_provenance_bad_input"
  )
  expect_error(
    ticker_universe_provenance(meta_fixture(), character(0), 0L),
    class = "ticker_universe_provenance_bad_input"
  )
})
