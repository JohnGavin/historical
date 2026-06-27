# Regression tests for #489 Cluster D Fix 5:
# summarize_regime_allocation() with distinct lambda arg names (no .env$ pronoun).
#
# Prior to the fix, rlang::.env$scheme inside dplyr filter() inside purrr::pmap_dbl()
# threw "Can't subset .data outside of a data mask context".  The fix renames the
# lambda args to .scheme / .signal_type / .allocation_fn so no pronoun is needed.
testthat::local_edition(3)

source(here::here("R/zakamulin_allocation.R"))

# ── Helpers ──────────────────────────────────────────────────────────────────

# Build a minimal backtest_results tibble: 2 schemes x 1 signal_type x 1 fn.
.make_backtest_results <- function() {
  # 12 monthly rows per scheme so summarize gets enough data
  n_months <- 12L
  dates_a  <- seq.Date(as.Date("2020-01-31"), by = "month", length.out = n_months)
  dates_b  <- dates_a

  rbind(
    data.frame(
      date          = dates_a,
      scheme        = "scheme_A",
      signal_type   = "MA",
      allocation_fn = "linear",
      net_ret       = c(0.05, -0.02, 0.03, 0.01, -0.01, 0.04,
                        0.02, -0.03, 0.01, 0.05, -0.02, 0.03),
      allocated_ret = c(0.04, -0.01, 0.02, 0.01, -0.01, 0.03,
                        0.01, -0.02, 0.01, 0.04, -0.01, 0.02),
      allocation    = rep(0.8, n_months),
      stringsAsFactors = FALSE
    ),
    data.frame(
      date          = dates_b,
      scheme        = "scheme_B",
      signal_type   = "MA",
      allocation_fn = "linear",
      net_ret       = c(-0.01, 0.02, 0.04, -0.03, 0.01, 0.02,
                        0.03, 0.01, -0.01, 0.02, 0.04, -0.02),
      allocated_ret = c(-0.01, 0.02, 0.03, -0.02, 0.01, 0.01,
                        0.02, 0.01, -0.01, 0.02, 0.03, -0.01),
      allocation    = rep(0.75, n_months),
      stringsAsFactors = FALSE
    )
  )
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_that(
  "summarize_regime_allocation() returns one row per group without .env$ error (#489 Cluster D)",
  {
    br     <- .make_backtest_results()
    result <- summarize_regime_allocation(br, annual_rf = 0.02)

    # Should have exactly 2 rows (one per scheme)
    expect_equal(nrow(result), 2L)

    # Required columns present
    expect_true("max_dd"           %in% names(result))
    expect_true("max_dd_allocated" %in% names(result))

    # max_dd and max_dd_allocated must be finite (not NA/NaN) for both schemes
    expect_false(any(is.na(result$max_dd)),
                 info = "max_dd must be finite for all groups (no .env$ pronoun error)")
    expect_false(any(is.na(result$max_dd_allocated)),
                 info = "max_dd_allocated must be finite for all groups")

    # Drawdowns must be <= 0 by definition
    expect_true(all(result$max_dd           <= 0),
                info = "max_dd is a drawdown — must be non-positive")
    expect_true(all(result$max_dd_allocated <= 0),
                info = "max_dd_allocated must be non-positive")
  }
)

test_that(
  "summarize_regime_allocation() max_dd correct for known drawdown (#489 Cluster D)",
  {
    # scheme_C: starts high, then crashes hard so max_dd is easy to predict
    # 1 -> 1.10 -> 1.10*0.80 = 0.88 → drawdown from peak = (0.88-1.10)/1.10 = -0.20
    br_c <- data.frame(
      date          = as.Date(c("2020-01-31", "2020-02-28", "2020-03-31")),
      scheme        = "scheme_C",
      signal_type   = "MA",
      allocation_fn = "linear",
      net_ret       = c(0.10, -0.20, 0.05),  # max drawdown: -0.20 from peak
      allocated_ret = c(0.08, -0.16, 0.04),
      allocation    = c(0.8, 0.8, 0.8),
      stringsAsFactors = FALSE
    )

    result <- summarize_regime_allocation(br_c, annual_rf = 0.02)

    expect_equal(nrow(result), 1L)
    # Peak after month 1: 1.10; valley after month 2: 1.10*0.80 = 0.88
    # max_dd = (0.88 - 1.10) / 1.10 = -0.20 exactly
    expect_equal(result$max_dd, -0.20, tolerance = 1e-8)
  }
)
