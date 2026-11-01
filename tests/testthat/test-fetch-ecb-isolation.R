testthat::local_edition(3)
source(here::here("scripts", "fetch_ecb.R"))

# Per-series isolation in scripts/fetch_ecb.R. On 2026-10-31 one ECB timeout
# aborted the poll after 24/29 series and discarded them. NO network: the
# fetch function is injected.

.reg <- list(
  a = list(key = "K/A", description = "series a", unit = "u"),
  b = list(key = "K/B", description = "series b", unit = "u"),
  c = list(key = "K/C", description = "series c", unit = "u")
)

.ok_df <- function(key) {
  tibble::tibble(date = as.Date("2024-01-02"), value = 1, series_key = key,
                 frequency = "daily")
}

test_that("a series that errors does not discard the others", {
  fetch <- function(key, start) {
    if (key == "K/B") stop("Timeout was reached")
    .ok_df(key)
  }
  out <- suppressMessages(fetch_ecb_series(.reg, fetch_fn = fetch))
  expect_equal(names(out$results), c("a", "c"))
  expect_equal(out$failed$series, "b")
  expect_match(out$failed$reason, "Timeout was reached")
  expect_equal(out$results$a$series_name, "a")
})

test_that("a series that returns NULL is recorded as failed", {
  fetch <- function(key, start) if (key == "K/C") NULL else .ok_df(key)
  out <- suppressMessages(fetch_ecb_series(.reg, fetch_fn = fetch))
  expect_equal(names(out$results), c("a", "b"))
  expect_equal(out$failed$series, "c")
  expect_equal(out$failed$reason, "returned NULL")
})

test_that("all-success run reports no failures and no summary", {
  out <- suppressMessages(
    fetch_ecb_series(.reg, fetch_fn = function(key, start) .ok_df(key))
  )
  expect_equal(nrow(out$failed), 0L)
  expect_true(is.na(ecb_failure_summary(out$failed)))
})

test_that("failure summary is one line naming every failed series", {
  fetch <- function(key, start) if (key == "K/A") NULL else stop("boom")
  out <- suppressMessages(fetch_ecb_series(.reg, fetch_fn = fetch))
  s <- ecb_failure_summary(out$failed)
  expect_equal(s, "3 ECB series failed: a, b, c")
  expect_false(grepl("\n", s, fixed = TRUE))
})
