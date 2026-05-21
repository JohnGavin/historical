testthat::local_edition(3)

# Regression tests for fix in commit 159e3b9:
# date_lookup was built with distinct(ym, date), which produced >1 row per ym
# when different ETF tickers have different month-end dates (holiday calendars).
# This fan-out caused the left_join back to `combined` to multiply rows.
# Fix: slice_max(date, n=1L, with_ties=FALSE) guarantees exactly one row per ym.

# ── Helper: build_date_lookup (extracted from plan_factormax.R target body) ──
# The fix is in an inline expression, not an exported function. We reproduce it
# to regression-test the cardinality guarantee.

build_date_lookup <- function(etf_m, plot_tickers = c("VLUE", "MTUM")) {
  etf_m |>
    dplyr::filter(ticker %in% plot_tickers) |>
    dplyr::group_by(ym) |>
    dplyr::slice_max(date, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(ym, date)
}

# ── Synthetic data builder ─────────────────────────────────────────────────
# Two tickers with the same ym values but different month-end dates (simulating
# holiday-calendar differences between tickers).

make_etf_m_with_fanout <- function() {
  # Jan 2024: VLUE month-end on 2024-01-31, MTUM on 2024-01-30 (one day diff)
  # Feb 2024: both same date
  # Mar 2024: VLUE on 2024-03-28, MTUM on 2024-03-29 (one day diff)
  tibble::tibble(
    ticker = c("VLUE", "VLUE", "VLUE",
               "MTUM", "MTUM", "MTUM"),
    ym     = c("2024-01", "2024-02", "2024-03",
               "2024-01", "2024-02", "2024-03"),
    date   = as.Date(c(
      "2024-01-31", "2024-02-29", "2024-03-28",
      "2024-01-30", "2024-02-29", "2024-03-29"
    )),
    ret    = c(0.01, 0.02, 0.03, 0.011, 0.021, 0.031)
  )
}

# ── F1: date_lookup has exactly one row per ym ────────────────────────────

test_that("date_lookup: unique ym after slice_max fix (regression #2747)", {
  etf_m <- make_etf_m_with_fanout()
  dl <- build_date_lookup(etf_m)

  # One row per ym is the core guarantee of the fix
  expect_equal(anyDuplicated(dl$ym), 0L,
               info = "date_lookup must have exactly one row per ym after slice_max fix")
  expect_equal(nrow(dl), dplyr::n_distinct(etf_m$ym))
})

# ── F2: fan-out is prevented — left_join preserves pre-join row count ────

test_that("date_lookup: left_join to combined preserves row count (regression #2747)", {
  etf_m <- make_etf_m_with_fanout()
  dl <- build_date_lookup(etf_m)

  # Simulate combined (one row per ym per strategy, 3 months × 2 strategies)
  combined <- tibble::tibble(
    ym       = rep(c("2024-01", "2024-02", "2024-03"), 2),
    strategy = rep(c("A", "B"), each = 3),
    ret      = rnorm(6)
  )
  pre_join_nrow <- nrow(combined)

  combined_joined <- combined |> dplyr::left_join(dl, by = "ym")

  # The key regression check: no row multiplication
  expect_equal(nrow(combined_joined), pre_join_nrow,
               info = "left_join with date_lookup must not multiply rows (regression #2747)")
})

# ── F3: distinct(ym, date) would have produced duplicates ─────────────────
# This documents the pre-fix behavior to confirm the synthetic data triggers it.

test_that("distinct(ym, date) DOES produce duplicates — confirming the bug reproduced", {
  etf_m <- make_etf_m_with_fanout()

  # The old (buggy) code path
  old_date_lookup <- etf_m |>
    dplyr::filter(ticker %in% c("VLUE", "MTUM")) |>
    dplyr::distinct(ym, date)

  # Months with different month-end dates across tickers get >1 row
  expect_true(anyDuplicated(old_date_lookup$ym) > 0,
              info = "distinct(ym, date) should produce ym duplicates when ETFs have different month-end dates")
})

# ── F4: slice_max selects the latest date within each ym ─────────────────

test_that("date_lookup: slice_max selects max date per ym", {
  etf_m <- make_etf_m_with_fanout()
  dl <- build_date_lookup(etf_m)

  # For Jan 2024: VLUE=2024-01-31, MTUM=2024-01-30 → expect 2024-01-31
  # For Feb 2024: both=2024-02-29 → expect 2024-02-29
  # For Mar 2024: VLUE=2024-03-28, MTUM=2024-03-29 → expect 2024-03-29
  expected <- tibble::tibble(
    ym   = c("2024-01", "2024-02", "2024-03"),
    date = as.Date(c("2024-01-31", "2024-02-29", "2024-03-29"))
  )

  result <- dl |> dplyr::arrange(ym)
  expect_equal(result$date, expected$date,
               info = "slice_max should select the maximum date per ym")
})
