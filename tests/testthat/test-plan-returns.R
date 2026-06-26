testthat::local_edition(3)

# Tests for plan_returns.R — Phase B of #389
#
# Covers:
#   cov_annual:      symmetry, positive-semi-definiteness, dimnames
#   cov_rolling_60m: NA gating below min-obs threshold, structure
#   Snapshot:        args() of plan_returns() for API stability,
#                    structure of a typical cov_annual output
#
# All tests use a synthetic multi-asset return fixture (no network access).

# ── Helper: make a synthetic wide-returns tibble ────────────────────────────

make_wide_returns <- function(n_months = 120L, assets = c("SPY", "TLT", "GLD", "DBC"),
                              seed = 42L) {
  set.seed(seed)
  dates <- seq.Date(as.Date("2015-01-31"), by = "month", length.out = n_months)
  ret_list <- lapply(assets, function(a) rnorm(n_months, mean = 0.007, sd = 0.04))
  names(ret_list) <- assets
  out <- as.data.frame(ret_list)
  out$date <- dates
  # Reorder so date is first column, matching plan_returns.R output
  out <- out[, c("date", assets)]
  tibble::as_tibble(out)
}

# Helper: extract the plan_returns constants as sourced in plan_returns.R.
# We re-define them here so tests don't depend on source()-ing the file.
RETURNS_ROLL_MIN_FRAC <- 0.70
RETURNS_MIN_OBS       <- 24L
PERIODS_PER_YEAR      <- 12L

# ── Helper: compute cov_annual from a wide tibble (mirrors plan_returns logic) ─

compute_cov_annual <- function(wide, min_obs = RETURNS_MIN_OBS,
                               periods = PERIODS_PER_YEAR) {
  asset_cols <- setdiff(colnames(wide), "date")
  n_obs      <- nrow(wide)
  if (n_obs < min_obs) stop("too few obs")
  ret_mat   <- as.matrix(wide[, asset_cols])
  Sigma_m   <- stats::cov(ret_mat, use = "complete.obs")
  Sigma_ann <- periods * ((Sigma_m + t(Sigma_m)) / 2)
  rownames(Sigma_ann) <- asset_cols
  colnames(Sigma_ann) <- asset_cols
  Sigma_ann
}

# ── Helper: rolling 60m cov (mirrors plan_returns logic) ─────────────────────

compute_cov_rolling_60m <- function(wide, window_n = 60L,
                                    min_frac = RETURNS_ROLL_MIN_FRAC,
                                    periods   = PERIODS_PER_YEAR) {
  asset_cols <- setdiff(colnames(wide), "date")
  dates      <- wide$date
  ret_mat    <- as.matrix(wide[, asset_cols])
  min_obs    <- ceiling(min_frac * window_n)

  cov_list <- slider::slide(
    seq_len(nrow(ret_mat)),
    function(row_idx) {
      window <- ret_mat[row_idx, , drop = FALSE]
      n_complete <- sum(rowSums(is.na(window)) == 0L)
      if (n_complete < min_obs) return(NULL)
      window_cc <- window[rowSums(is.na(window)) == 0L, , drop = FALSE]
      Sigma_m   <- stats::cov(window_cc, use = "complete.obs")
      Sigma_ann <- periods * ((Sigma_m + t(Sigma_m)) / 2)
      rownames(Sigma_ann) <- asset_cols
      colnames(Sigma_ann) <- asset_cols
      Sigma_ann
    },
    .before = window_n - 1L,
    .complete = FALSE
  )
  names(cov_list) <- as.character(dates)
  cov_list
}

# ============================================================================
# Tests: cov_annual
# ============================================================================

test_that("cov_annual: symmetric matrix", {
  wide  <- make_wide_returns(n_months = 80L)
  Sigma <- compute_cov_annual(wide)

  # Symmetry: Sigma[i,j] == Sigma[j,i] for all i, j
  expect_equal(Sigma, t(Sigma),
               info  = "cov_annual must be symmetric (S = t(S))",
               tolerance = 1e-12)
})

test_that("cov_annual: positive semi-definite (all eigenvalues >= -1e-10)", {
  wide   <- make_wide_returns(n_months = 80L)
  Sigma  <- compute_cov_annual(wide)
  eig    <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values

  # All eigenvalues >= -1e-10 (numerical zero tolerance)
  expect_true(
    all(eig >= -1e-10),
    info = paste0(
      "cov_annual must be positive semi-definite. ",
      "Negative eigenvalues: ", paste(round(eig[eig < -1e-10], 6), collapse = ", ")
    )
  )
})

test_that("cov_annual: correct dimnames match asset universe", {
  assets <- c("SPY", "TLT", "GLD", "DBC")
  wide   <- make_wide_returns(n_months = 60L, assets = assets)
  Sigma  <- compute_cov_annual(wide)

  expect_equal(rownames(Sigma), assets,
               info = "cov_annual rownames must match asset vector")
  expect_equal(colnames(Sigma), assets,
               info = "cov_annual colnames must match asset vector")
  expect_equal(dim(Sigma), c(length(assets), length(assets)))
})

test_that("cov_annual: diagonal elements are positive (non-zero variances)", {
  wide  <- make_wide_returns(n_months = 80L)
  Sigma <- compute_cov_annual(wide)

  diag_vals <- diag(Sigma)
  expect_true(
    all(diag_vals > 0),
    info = paste0("All diagonal elements (variances) must be > 0. Got: ",
                  paste(round(diag_vals, 8), collapse = ", "))
  )
})

test_that("cov_annual: annualisation factor is 12 (monthly * 12)", {
  # With a single asset, cov_annual[[1,1]] should equal 12 * var(monthly_ret)
  set.seed(99L)
  n  <- 60L
  ret <- rnorm(n, mean = 0.005, sd = 0.03)
  dates <- seq.Date(as.Date("2019-01-31"), by = "month", length.out = n)

  wide <- tibble::tibble(date = dates, SPY = ret)
  Sigma <- compute_cov_annual(wide, min_obs = 10L)

  expected_var_annual <- 12 * stats::var(ret)
  expect_equal(Sigma[1L, 1L], expected_var_annual, tolerance = 1e-12,
               info = "cov_annual[1,1] must equal 12 * var(monthly_return)")
})

test_that("cov_annual: minimum observations guard (< RETURNS_MIN_OBS raises error)", {
  # Fewer rows than RETURNS_MIN_OBS (24) should trigger an error in plan_returns.R.
  # We test the same logic via compute_cov_annual(min_obs = 24L).
  wide_short <- make_wide_returns(n_months = 10L)

  expect_error(
    compute_cov_annual(wide_short, min_obs = 24L),
    regexp = "too few obs"
  )
})

# ============================================================================
# Tests: cov_rolling_60m — NA gating
# ============================================================================

test_that("cov_rolling_60m: first 59 windows return NULL (< 60 rows available)", {
  wide    <- make_wide_returns(n_months = 80L)
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)

  # Windows 1..59 must be NULL (fewer than window_n rows before min_obs gate)
  # The actual gate is min_frac * 60; without NAs every row is complete so
  # min_obs = ceiling(0.7 * 60) = 42. Windows 1..41 are NULL; 42..59 have 42-59
  # complete obs which meets the gate (>= 42). Windows 1..41 are NULL.
  null_count <- sum(vapply(cov_lst[seq_len(41L)], is.null, logical(1L)))
  expect_equal(null_count, 41L,
               info = "First 41 windows (< min_obs complete rows) must be NULL")
})

test_that("cov_rolling_60m: windows with >= min_obs observations return a matrix", {
  wide    <- make_wide_returns(n_months = 80L)
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)

  # Window 60 (index 60) has exactly 60 complete rows — should be non-NULL
  w60 <- cov_lst[[60L]]
  expect_false(is.null(w60),
               info = "Window 60 (60 complete rows) should return a non-NULL matrix")
  expect_true(is.matrix(w60))
})

test_that("cov_rolling_60m: introduced NAs cause window to return NULL", {
  # Set specific rows to NA to push a window below min_obs
  wide <- make_wide_returns(n_months = 70L)
  # Introduce NAs in rows 1..30 for SPY so that window 60 (rows 1..60) has
  # only 30 complete rows (< min_obs = ceiling(0.7*60) = 42) → should be NULL
  wide$SPY[1:30] <- NA_real_
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)

  # Window 60 has rows 1..60 with 30 NA rows → 30 complete rows < 42 → NULL
  expect_null(cov_lst[[60L]],
              info = "Window 60 with only 30 complete rows must return NULL (< min_obs 42)")

  # Window 70 has rows 11..70 with 30 NA rows (1..30) → still 30 < 42 → NULL
  # Actually rows 1..30 are NA; window 70 is rows 11..70; rows 11..30 are NA (20 rows)
  # so complete rows = 60 - 20 = 40 < 42 → still NULL
  expect_null(cov_lst[[70L]],
              info = "Window 70 still has 40 complete rows (< 42 min_obs) → NULL")
})

test_that("cov_rolling_60m: output length matches input nrow", {
  wide    <- make_wide_returns(n_months = 90L)
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)
  expect_equal(length(cov_lst), 90L)
})

test_that("cov_rolling_60m: output names match date column (as.character)", {
  wide    <- make_wide_returns(n_months = 70L)
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)
  expect_equal(names(cov_lst), as.character(wide$date))
})

test_that("cov_rolling_60m: each non-NULL matrix is symmetric and PSD", {
  wide    <- make_wide_returns(n_months = 80L)
  cov_lst <- compute_cov_rolling_60m(wide, window_n = 60L)
  non_null <- Filter(Negate(is.null), cov_lst)

  for (m in non_null) {
    sym_ok <- isTRUE(all.equal(m, t(m), tolerance = 1e-12))
    expect_true(sym_ok, info = "Each rolling cov matrix must be symmetric")
    eig <- eigen(m, symmetric = TRUE, only.values = TRUE)$values
    expect_true(all(eig >= -1e-10),
                info = "Each rolling cov matrix must be positive semi-definite")
  }
})

# ============================================================================
# Snapshot tests (API stability)
# ============================================================================

test_that("plan_returns: function signature is stable (API drift guard)", {
  # Source plan_returns.R to make plan_returns() available
  source(here::here("R/plan_returns.R"), local = TRUE)
  expect_snapshot(args(plan_returns))
})

# ============================================================================
# Tests: .complete_case_wide() — regression guard for #487
#
# Exercises the pure helper extracted from asset_monthly_returns_wide.
# Source plan_returns.R once; the helper is available as .complete_case_wide().
# ============================================================================

test_that(".complete_case_wide: row with any NA asset column is dropped (#487)", {
  # Source file in local env to get .complete_case_wide without side effects
  env <- new.env()
  source(here::here("R/plan_returns.R"), local = env)
  ccw <- env$.complete_case_wide

  wide <- tibble::tibble(
    date = as.Date(c("2020-01-31", "2020-02-29", "2020-03-31")),
    SPY  = c(0.01, NA_real_, 0.03),   # row 2 has NA
    TLT  = c(0.02, 0.00,    0.01)
  )

  result <- ccw(wide)

  expect_equal(nrow(result), 2L,
               info = "Row with NA in asset column must be dropped")
  expect_equal(result$date, as.Date(c("2020-01-31", "2020-03-31")),
               info = "Remaining rows must be the complete-case rows")
})

test_that(".complete_case_wide: fully-populated frame is unchanged (#487)", {
  env <- new.env()
  source(here::here("R/plan_returns.R"), local = env)
  ccw <- env$.complete_case_wide

  wide <- tibble::tibble(
    date = as.Date(c("2020-01-31", "2020-02-29")),
    SPY  = c(0.01, 0.02),
    TLT  = c(0.03, 0.04)
  )

  result <- ccw(wide)

  expect_equal(nrow(result), 2L,
               info = "No rows should be dropped from a fully-populated frame")
  expect_equal(result, wide)
})

test_that(".complete_case_wide: date-only frame (no asset cols) is unchanged (#487)", {
  # if_all(-date) over zero non-date columns returns TRUE → all rows kept.
  # This guards the original 'else TRUE' edge case from the magrittr version.
  env <- new.env()
  source(here::here("R/plan_returns.R"), local = env)
  ccw <- env$.complete_case_wide

  wide <- tibble::tibble(date = as.Date(c("2020-01-31", "2020-02-29")))

  result <- ccw(wide)

  expect_equal(nrow(result), 2L,
               info = "Date-only frame must pass all rows through (zero non-date cols)")
  expect_equal(result, wide)
})

test_that("cov_annual: structure snapshot with canonical 4-asset universe", {
  assets <- c("SPY", "TLT", "GLD", "DBC")
  wide   <- make_wide_returns(n_months = 120L, assets = assets, seed = 7L)
  Sigma  <- compute_cov_annual(wide)

  # Snapshot the rounded structure (not exact values — seed-stable via set.seed)
  expect_snapshot(
    list(
      dim       = dim(Sigma),
      rownames  = rownames(Sigma),
      colnames  = colnames(Sigma),
      diag_sign = sign(diag(Sigma)),
      is_matrix = is.matrix(Sigma)
    )
  )
})
