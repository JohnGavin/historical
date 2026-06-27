testthat::local_edition(3)

# ── Fix 4 (#489 Cluster D): complete month grid before pivot_wider ────────────
# When port_combined is missing a calendar month (e.g. month 3 = March) the
# hardcoded rename(Mar = `3`, ...) used to fail with
# "Column `3` doesn't exist".  The fix inserts tidyr::complete(year, month = 1:12)
# before pivot_wider so all 12 month columns are always present.

test_that("port_monthly_returns: missing month still yields all 12 renamed columns (#489 Cluster D)", {
  # Synthetic data missing March (month 3) — mirrors the live failure
  raw <- tibble::tibble(
    year        = c(2020L, 2020L, 2020L, 2020L, 2020L,
                    2020L, 2020L, 2020L, 2020L, 2020L, 2020L),   # 11 months
    month       = c(1L, 2L,          4L, 5L, 6L,
                    7L, 8L, 9L, 10L, 11L, 12L),                   # no 3
    return_pct  = c(1.1, -0.5,       0.8, 1.2, -0.3,
                    0.4,  0.7, -0.1,  0.9,  1.5, -0.2)
  )

  # Apply the fix: complete then pivot
  wide <- raw |>
    tidyr::complete(year, month = 1:12) |>
    tidyr::pivot_wider(
      names_from  = month,
      values_from = return_pct,
      names_sort  = TRUE
    )

  # All 12 month columns must exist (names are integers as characters)
  month_cols <- as.character(1:12)
  missing_cols <- setdiff(month_cols, names(wide))
  expect_equal(
    length(missing_cols), 0L,
    info = paste("After complete(), these month columns are still absent:", paste(missing_cols, collapse = ", "))
  )

  # Month 3 column should be NA (completed but no data)
  expect_true(is.na(wide[["3"]]),
              info = "Completed month 3 must be NA when no data existed for it")

  # The rename step that used to fail should now succeed
  result <- wide |>
    dplyr::rename(
      Year = year,
      Jan = `1`,  Feb = `2`,  Mar = `3`,  Apr = `4`,
      May = `5`,  Jun = `6`,  Jul = `7`,  Aug = `8`,
      Sep = `9`,  Oct = `10`, Nov = `11`, Dec = `12`
    )

  expect_true("Mar" %in% names(result),
              info = "rename(Mar = `3`) must succeed after complete()")
  expect_equal(ncol(result), 13L,  # year + 12 month columns
               info = "Wide table should have exactly 13 columns (year + 12 months)")
})

# Regression test for fix in commit 159e3b9:
# calc_port_metrics() was missing opt_vol column, causing NA in the PSO
# Optimal leaderboard row. Test that the output tibble contains all four
# expected opt_* columns (opt_cagr, opt_vol, opt_sharpe, opt_maxdd) and
# that none are NA for a representative input.

# ── Inline the calc_port_metrics logic from plan_portfolio_opt.R ───────────
# The function is defined inside a tar_target() body and is not exported.
# We reproduce the exact definition to regression-test the column set.

make_calc_port_metrics <- function(rf_ann = 0) {
  function(df, label) {
    n <- nrow(df)
    if (n < 12L) return(NULL)
    sharpe <- function(r) {
      ann <- prod(1 + r)^(12 / n) - 1
      vol <- sd(r) * sqrt(12)
      if (vol < 1e-8) NA_real_ else (ann - rf_ann) / vol
    }
    maxdd <- function(r) {
      cum <- cumprod(1 + r)
      min(cum / cummax(cum) - 1)
    }
    tibble::tibble(
      period    = label, months = n,
      opt_cagr   = prod(1 + df$optimal_ret)^(12 / n) - 1,
      opt_vol    = sd(df$optimal_ret) * sqrt(12),          # fix: was absent
      opt_sharpe = sharpe(df$optimal_ret),
      opt_maxdd  = maxdd(df$optimal_ret),
      hrp_cagr   = prod(1 + df$hrp_ret)^(12 / n) - 1,
      hrp_sharpe = sharpe(df$hrp_ret),
      hrp_maxdd  = maxdd(df$hrp_ret),
      eq_cagr    = prod(1 + df$equalwt_ret)^(12 / n) - 1,
      eq_sharpe  = sharpe(df$equalwt_ret),
      eq_maxdd   = maxdd(df$equalwt_ret)
    )
  }
}

# ── F1: opt_vol column is present and non-NA ──────────────────────────────

test_that("calc_port_metrics: output contains opt_vol and it is non-NA (regression #2748)", {
  # Synthetic 24-month portfolio with modest positive returns
  set.seed(42L)
  n <- 24L
  df <- data.frame(
    date        = seq.Date(as.Date("2020-01-31"), by = "month", length.out = n),
    optimal_ret = rnorm(n, mean = 0.008, sd = 0.04),
    hrp_ret     = rnorm(n, mean = 0.007, sd = 0.035),
    equalwt_ret = rnorm(n, mean = 0.006, sd = 0.03),
    rf_ret      = rep(0.002, n)
  )

  calc_port_metrics <- make_calc_port_metrics(rf_ann = mean(df$rf_ret) * 12)
  result <- calc_port_metrics(df, "Full Period")

  # Column presence
  expect_true("opt_vol" %in% names(result),
              info = "opt_vol column must exist in port_metrics output")
  expect_true("opt_cagr" %in% names(result))
  expect_true("opt_sharpe" %in% names(result))
  expect_true("opt_maxdd" %in% names(result))

  # Non-NA check — the original bug produced NA here
  expect_false(is.na(result$opt_vol),
               info = "opt_vol must not be NA for a representative input (regression #2748)")

  # Numeric sanity: annualised vol for monthly returns should be a small positive number
  expect_true(result$opt_vol > 0)
  expect_true(result$opt_vol < 2)   # sanity: not astronomically large
})

# ── F2: opt_vol formula matches sd(r) * sqrt(12) ─────────────────────────

test_that("calc_port_metrics: opt_vol equals sd(returns) * sqrt(12)", {
  set.seed(7L)
  n <- 36L
  df <- data.frame(
    date        = seq.Date(as.Date("2019-01-31"), by = "month", length.out = n),
    optimal_ret = rnorm(n, 0.01, 0.03),
    hrp_ret     = rnorm(n, 0.009, 0.025),
    equalwt_ret = rnorm(n, 0.008, 0.02),
    rf_ret      = rep(0.001, n)
  )

  calc_port_metrics <- make_calc_port_metrics(rf_ann = mean(df$rf_ret) * 12)
  result <- calc_port_metrics(df, "Full Period")

  expected_vol <- sd(df$optimal_ret) * sqrt(12)
  expect_equal(result$opt_vol, expected_vol, tolerance = 1e-12)
})

# ── F3: returns NULL when fewer than 12 months ────────────────────────────

test_that("calc_port_metrics: returns NULL when n < 12", {
  df_short <- data.frame(
    date        = seq.Date(as.Date("2023-01-31"), by = "month", length.out = 10L),
    optimal_ret = rep(0.01, 10L),
    hrp_ret     = rep(0.01, 10L),
    equalwt_ret = rep(0.01, 10L),
    rf_ret      = rep(0.002, 10L)
  )
  calc_port_metrics <- make_calc_port_metrics()
  expect_null(calc_port_metrics(df_short, "Short"))
})
