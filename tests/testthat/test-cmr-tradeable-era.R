# Tests for the #751 item 1 tradeable-era truncation helpers
# (.cmr_tradeable_cutoff_date() / .cmr_truncate_to_tradeable_era(),
# R/plan_commodities_mean_reversion.R).
#
# Decision (#751, 2026-08-24): CMR excludes the pre-tradeable-era observations
# on INVESTABILITY grounds -- the pre-cutoff-only names are IMF Primary
# Commodity Price System indexes served via FRED, which are statistical price
# indexes, not securities. These tests pin: (a) the cutoff is derived from the
# data (earliest non-FRED/IMF date), never hardcoded; (b) truncation removes
# dates, not series -- FRED/IMF rows on/after the cutoff survive; (c) the
# fail-loud-not-null contract for a missing `source` column or an all-FRED
# universe.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

# ── Fixtures ────────────────────────────────────────────────────────────────

# A mixed universe: two FRED/IMF series starting well before any tradeable
# series, plus two tradeable (Yahoo) series starting later, with the
# tradeable series themselves staggered so the cutoff is not the same as
# either series' own start date in isolation.
mixed_universe <- function() {
  # #751 finding 3: the FRED/IMF series do not stop at 2000 -- they keep
  # printing monthly for decades after the tradeable era begins. length.out
  # is chosen so both series extend well past the yahoo cutoff below.
  fred_a <- tibble::tibble(
    date = seq.Date(as.Date("1992-01-01"), by = "month", length.out = 300),
    series_id = "POILWTIUSDM", source = "fred_imf", monthly_ret = 0.01
  )
  fred_b <- tibble::tibble(
    date = seq.Date(as.Date("1992-06-01"), by = "month", length.out = 300),
    series_id = "PCOPPUSDM", source = "fred_imf", monthly_ret = 0.01
  )
  yahoo_a <- tibble::tibble(
    date = seq.Date(as.Date("2000-03-15"), by = "day", length.out = 200),
    series_id = "CC=F", source = "yahoo", monthly_ret = 0.001
  )
  yahoo_b <- tibble::tibble(
    date = seq.Date(as.Date("2000-08-30"), by = "day", length.out = 200),
    series_id = "GC=F", source = "yahoo", monthly_ret = 0.001
  )
  dplyr::bind_rows(fred_a, fred_b, yahoo_a, yahoo_b)
}

# ── .cmr_tradeable_cutoff_date() ─────────────────────────────────────────────

test_that("cutoff is the earliest TRADEABLE date, not the earliest date overall", {
  tbl <- mixed_universe()
  cutoff <- .cmr_tradeable_cutoff_date(tbl)
  expect_equal(cutoff, as.Date("2000-03-15"))
  # Sanity: the FRED series start much earlier, so a naive min(date) over the
  # whole universe would have given the wrong (untradeable) answer.
  expect_true(min(tbl$date) < cutoff)
})

test_that("cutoff ignores which series is earliest among FRED names -- only source matters", {
  # Swap which FRED series starts first; the cutoff (driven entirely by the
  # yahoo rows) must be unchanged.
  tbl <- mixed_universe()
  tbl$date[tbl$series_id == "PCOPPUSDM"][1] <- as.Date("1980-01-01")
  cutoff <- .cmr_tradeable_cutoff_date(tbl)
  expect_equal(cutoff, as.Date("2000-03-15"))
})

test_that("missing source column aborts with an informative error", {
  bad_tbl <- tibble::tibble(date = Sys.Date(), series_id = "X", monthly_ret = 0.01)
  expect_snapshot(error = TRUE, .cmr_tradeable_cutoff_date(bad_tbl))
})

test_that("an all-FRED/IMF universe (no tradeable rows) aborts rather than returning NA/Inf", {
  all_fred <- tibble::tibble(
    date = seq.Date(as.Date("1992-01-01"), by = "month", length.out = 12),
    series_id = "POILWTIUSDM", source = "fred_imf", monthly_ret = 0.01
  )
  expect_snapshot(error = TRUE, .cmr_tradeable_cutoff_date(all_fred))
})

# ── .cmr_truncate_to_tradeable_era() ─────────────────────────────────────────

test_that("truncation drops every pre-cutoff row of BOTH sources, keeps post-cutoff rows of BOTH sources", {
  tbl <- mixed_universe()
  out <- suppressMessages(.cmr_truncate_to_tradeable_era(tbl))

  expect_true(all(out$date >= as.Date("2000-03-15")))
  # FRED/IMF rows are not removed as a SERIES -- rows that fall on/after the
  # cutoff survive.
  expect_true(any(out$source == "fred_imf"))
  expect_true(any(out$source == "yahoo"))
  # Every pre-cutoff FRED row (the bulk of the universe) is gone.
  expect_equal(sum(out$date < as.Date("2000-03-15")), 0L)
})

test_that("truncation does not remove any series id present on/after the cutoff", {
  tbl <- mixed_universe()
  out <- suppressMessages(.cmr_truncate_to_tradeable_era(tbl))
  # Both FRED series print monthly well past the cutoff in this fixture, so
  # neither series_id is dropped entirely -- only its early rows are.
  expect_setequal(unique(out$series_id), unique(tbl$series_id))
})

test_that("truncation is a no-op when the tradeable era already covers the full universe", {
  tbl <- tibble::tibble(
    date = seq.Date(as.Date("2010-01-01"), by = "day", length.out = 30),
    series_id = "CC=F", source = "yahoo", monthly_ret = 0.001
  )
  out <- suppressMessages(.cmr_truncate_to_tradeable_era(tbl))
  expect_equal(nrow(out), nrow(tbl))
  expect_equal(out$date, tbl$date)
})

test_that("truncation reports what it did via cli_inform (not silent)", {
  tbl <- mixed_universe()
  msgs <- testthat::capture_messages(.cmr_truncate_to_tradeable_era(tbl))
  full <- paste(msgs, collapse = " ")
  expect_match(full, "tradeable era")
  expect_match(full, "2000-03-15")
  expect_match(full, "Dropped \\d+ pre-cutoff observation")
})

test_that("truncated output feeds hd_commodity_mr_signal without introducing NAs from the boundary", {
  # Integration-flavoured: the truncated tibble must still be a valid input
  # to the exported CMR functions this file's targets actually call.
  tbl <- mixed_universe()
  out <- suppressMessages(.cmr_truncate_to_tradeable_era(tbl))
  sig <- hd_commodity_mr_signal(out, lookback_months = 1L)
  expect_false(any(is.na(sig$mr_signal)))
  # Every signal date is on/after the cutoff -- no pre-cutoff leakage through
  # the lookback window's lag.
  expect_true(all(sig$date >= as.Date("2000-03-15")))
})
