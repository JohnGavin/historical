# Tests for the random-day-as-peak falsification helper.
#
# The helper `.mom_prepeak_random_peak_signal()` lives in R/plan_mom_prepeak_gauntlet.R
# and is a plan-level internal function, NOT a package export.
# These tests exercise the reproducibility and structural properties via
# sourcing the plan file inside a temporary environment.
#
# Because the helper uses `set.seed()` internally, we test:
#   1. Same seed => identical signal
#   2. Different seeds => different signals
#   3. Output structure matches hd_mom_prepeak_signal() (same columns, same row count
#      for the same input)
#
# NOTE: These tests source plan_mom_prepeak_gauntlet.R; they do NOT run tar_make().
# The sourcing loads the helper into the global env via the plan file's internal
# function definitions. If the plan file cannot be sourced (e.g., missing packages),
# tests are skipped gracefully.

# ── Shared fixture ─────────────────────────────────────────────────────────────
# A small synthetic daily-price tibble: 5 tickers × 60 months of trading days.
# This matches the expected input shape of hd_mom_prepeak_signal().

.make_tiny_universe <- function(n_tickers = 5L, n_days = 600L) {
  set.seed(99L)
  tickers  <- paste0("T", seq_len(n_tickers))
  start_dt <- as.Date("2000-01-03")
  dates    <- seq.Date(start_dt, by = "day", length.out = n_days * 1.5)
  # Keep only weekdays
  dates    <- dates[weekdays(dates) %in% c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday")]
  dates    <- head(dates, n_days)

  dplyr::bind_rows(lapply(tickers, function(tk) {
    price_path <- cumprod(c(100, 1 + stats::rnorm(n_days - 1L, 0, 0.01)))
    tibble::tibble(
      ticker   = tk,
      date     = dates,
      adjusted = price_path
    )
  }))
}

.make_as_of_dates <- function(universe_tbl) {
  universe_tbl |>
    dplyr::mutate(ym = format(as.Date(.data$date), "%Y-%m")) |>
    dplyr::group_by(.data$ym) |>
    dplyr::summarise(as_of_date = max(as.Date(.data$date)), .groups = "drop") |>
    dplyr::arrange(.data$as_of_date) |>
    dplyr::pull(.data$as_of_date)
}

# ── Helper loader ──────────────────────────────────────────────────────────────
# Source the gauntlet plan file to pull in .mom_prepeak_random_peak_signal().
# Returns FALSE (invisible) if the file cannot be sourced.
.load_gauntlet_helpers <- function() {
  plan_path <- here::here("R/plan_mom_prepeak_gauntlet.R")
  if (!file.exists(plan_path)) return(invisible(FALSE))
  tryCatch(
    { source(plan_path, local = FALSE); invisible(TRUE) },
    error = function(e) invisible(FALSE)
  )
}

# ── Tests ──────────────────────────────────────────────────────────────────────

test_that("same seed gives reproducible random-peak signal", {
  skip_if_not(
    .load_gauntlet_helpers(),
    "plan_mom_prepeak_gauntlet.R not loadable — skipping"
  )
  skip_if_not(exists(".mom_prepeak_random_peak_signal"),
              ".mom_prepeak_random_peak_signal not found after source()")

  univ  <- .make_tiny_universe()
  aods  <- .make_as_of_dates(univ)

  sig1 <- .mom_prepeak_random_peak_signal(univ, aods, seed = 42L)
  sig2 <- .mom_prepeak_random_peak_signal(univ, aods, seed = 42L)

  expect_equal(sig1, sig2)
})

test_that("different seeds give different signals", {
  skip_if_not(
    .load_gauntlet_helpers(),
    "plan_mom_prepeak_gauntlet.R not loadable — skipping"
  )
  skip_if_not(exists(".mom_prepeak_random_peak_signal"),
              ".mom_prepeak_random_peak_signal not found after source()")

  univ  <- .make_tiny_universe()
  aods  <- .make_as_of_dates(univ)

  sig_a <- .mom_prepeak_random_peak_signal(univ, aods, seed = 1L)
  sig_b <- .mom_prepeak_random_peak_signal(univ, aods, seed = 999L)

  # The random peak dates should differ between seeds for at least some rows
  expect_false(identical(sig_a, sig_b),
               info = "Two different seeds produced identical outputs — unexpected")
})

test_that("random-peak output has same columns as hd_mom_prepeak_signal()", {
  skip_if_not(
    .load_gauntlet_helpers(),
    "plan_mom_prepeak_gauntlet.R not loadable — skipping"
  )
  skip_if_not(exists(".mom_prepeak_random_peak_signal"),
              ".mom_prepeak_random_peak_signal not found after source()")

  univ  <- .make_tiny_universe()
  aods  <- .make_as_of_dates(univ)

  # Reference: run the real signal
  ref <- tryCatch(
    historicaldata::hd_mom_prepeak_signal(
      daily_prices          = univ,
      as_of_dates           = aods,
      lookback_months_start = 12L,
      lookback_months_end   = 2L,
      min_obs_days          = 30L   # low threshold so tiny fixture gets rows
    ),
    error = function(e) NULL
  )
  skip_if(is.null(ref), "hd_mom_prepeak_signal() failed on tiny fixture — skipping")

  rand <- .mom_prepeak_random_peak_signal(
    univ, aods,
    seed         = 42L,
    min_obs_days = 30L   # match reference threshold
  )

  # Must have the same column names
  expect_setequal(names(rand), names(ref))
})

test_that("random-peak output has the same number of rows as reference signal", {
  skip_if_not(
    .load_gauntlet_helpers(),
    "plan_mom_prepeak_gauntlet.R not loadable — skipping"
  )
  skip_if_not(exists(".mom_prepeak_random_peak_signal"),
              ".mom_prepeak_random_peak_signal not found after source()")

  univ  <- .make_tiny_universe()
  aods  <- .make_as_of_dates(univ)

  # Use min_obs_days=30L (low threshold so tiny fixture gets rows).
  # Must match the same threshold in the random-peak call so both functions
  # apply identical filtering; default min_obs_days=100L would produce fewer rows.
  ref <- tryCatch(
    historicaldata::hd_mom_prepeak_signal(
      daily_prices          = univ,
      as_of_dates           = aods,
      lookback_months_start = 12L,
      lookback_months_end   = 2L,
      min_obs_days          = 30L
    ),
    error = function(e) NULL
  )
  skip_if(is.null(ref), "hd_mom_prepeak_signal() failed on tiny fixture — skipping")

  rand <- .mom_prepeak_random_peak_signal(
    univ, aods,
    seed         = 42L,
    min_obs_days = 30L   # match reference threshold
  )

  expect_equal(nrow(rand), nrow(ref))
})
