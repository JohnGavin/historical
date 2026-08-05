testthat::local_edition(3)

# .port_weighted_return() is a genuine top-level (non-tar_target) function in
# R/plan_portfolio_opt.R (#641) -- source the real file rather than
# reproducing it, unlike calc_port_metrics() below which is still locked
# inside the port_metrics tar_target() body.
source(here::here("R/plan_portfolio_opt.R"))

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
  # #641: optimal_ret/hrp_ret/equalwt_ret can now contain NA (fewer than 2
  # of the 4 constituents reported that month -- see .port_weighted_return()
  # in R/plan_portfolio_opt.R). Reproduces the NA-dropping helpers added to
  # calc_port_metrics() alongside the original opt_vol fix (#2748).
  cagr_of <- function(r) {
    r <- r[!is.na(r)]
    if (length(r) < 1) return(NA_real_)
    prod(1 + r)^(12 / length(r)) - 1
  }
  vol_of <- function(r) {
    r <- r[!is.na(r)]
    if (length(r) < 2) return(NA_real_)
    sd(r) * sqrt(12)
  }
  sharpe_of <- function(r, rf_ann) {
    r <- r[!is.na(r)]
    if (length(r) < 2) return(NA_real_)
    ann <- prod(1 + r)^(12 / length(r)) - 1
    v <- sd(r) * sqrt(12)
    if (v < 1e-8) NA_real_ else (ann - rf_ann) / v
  }
  maxdd_of <- function(r) {
    r <- r[!is.na(r)]
    if (length(r) < 1) return(NA_real_)
    cum <- cumprod(1 + r)
    min(cum / cummax(cum) - 1)
  }
  function(df, label) {
    n <- nrow(df)
    if (n < 12L) return(NULL)
    tibble::tibble(
      period    = label, months = n,
      opt_cagr   = cagr_of(df$optimal_ret),
      opt_vol    = vol_of(df$optimal_ret),          # fix: was absent (#2748)
      opt_sharpe = sharpe_of(df$optimal_ret, rf_ann),
      opt_maxdd  = maxdd_of(df$optimal_ret),
      hrp_cagr   = cagr_of(df$hrp_ret),
      hrp_sharpe = sharpe_of(df$hrp_ret, rf_ann),
      hrp_maxdd  = maxdd_of(df$hrp_ret),
      eq_cagr    = cagr_of(df$equalwt_ret),
      eq_sharpe  = sharpe_of(df$equalwt_ret, rf_ann),
      eq_maxdd   = maxdd_of(df$equalwt_ret)
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

# ── F4: calc_port_metrics is NA-aware (#641) ───────────────────────────────
# A month with fewer than 2 constituents can now surface as NA in
# optimal_ret/hrp_ret/equalwt_ret instead of the row being deleted. Without
# NA-dropping, cumprod() would propagate that NA to every subsequent element
# and cagr_of()/vol_of()/sharpe_of()/maxdd_of() would silently return NA for
# the whole period from the first gap onward.

test_that("calc_port_metrics: a single NA return does not poison the whole-period metrics (#641)", {
  set.seed(11L)
  n <- 24L
  full_ret <- rnorm(n, mean = 0.008, sd = 0.03)
  gapped_ret <- full_ret
  gapped_ret[12] <- NA_real_  # mid-series gap, mirrors a thin-coverage month

  df_full <- data.frame(
    date        = seq.Date(as.Date("2020-01-31"), by = "month", length.out = n),
    optimal_ret = full_ret, hrp_ret = full_ret, equalwt_ret = full_ret,
    rf_ret      = rep(0.001, n)
  )
  df_gapped <- df_full
  df_gapped$optimal_ret <- gapped_ret
  df_gapped$hrp_ret     <- gapped_ret
  df_gapped$equalwt_ret <- gapped_ret

  calc_port_metrics <- make_calc_port_metrics(rf_ann = 0.012)
  result_full   <- calc_port_metrics(df_full,   "Full Period")
  result_gapped <- calc_port_metrics(df_gapped, "Full Period")

  # The pre-#641 (naive) implementation would make every one of these NA.
  expect_false(is.na(result_gapped$opt_cagr))
  expect_false(is.na(result_gapped$opt_vol))
  expect_false(is.na(result_gapped$opt_sharpe))
  expect_false(is.na(result_gapped$opt_maxdd))

  # `months` (calendar span) is unchanged; the metrics quietly used one
  # fewer observation.
  expect_equal(result_gapped$months, n)

  # Excluding one near-zero-magnitude-neutral draw should not move the
  # CAGR/vol dramatically -- both should stay in the same ballpark.
  expect_equal(result_gapped$opt_cagr, result_full$opt_cagr, tolerance = 0.05)
})

test_that("calc_port_metrics: opt_vol/opt_sharpe are NA (not NaN) when fewer than 2 non-NA months", {
  df <- data.frame(
    date        = seq.Date(as.Date("2020-01-31"), by = "month", length.out = 13L),
    optimal_ret = c(rep(NA_real_, 12L), 0.01),
    hrp_ret     = c(rep(NA_real_, 12L), 0.01),
    equalwt_ret = c(rep(NA_real_, 12L), 0.01),
    rf_ret      = rep(0.001, 13L)
  )
  calc_port_metrics <- make_calc_port_metrics(rf_ann = 0.012)
  result <- calc_port_metrics(df, "Thin")

  expect_true(is.na(result$opt_vol))
  expect_true(is.na(result$opt_sharpe))
  expect_false(is.nan(result$opt_vol))
  expect_false(is.nan(result$opt_sharpe))
  # A single non-NA return still yields a (degenerate) cagr/maxdd, not NA.
  expect_false(is.na(result$opt_cagr))
})

# ── Join fix: calendar-complete spine preserves a month missing one
# constituent (#641) ────────────────────────────────────────────────────
# Reproduces the port_returns spine-building logic (still inside a
# tar_target() body, so not directly sourceable) with synthetic
# constituents. Two things are asserted: (1) a missing-constituent month
# survives as an explicit NA row instead of being deleted by the old 4-way
# inner_join chain, and (2) the spine is bounded to the OVERLAP of the two
# stock-level series' own ranges, not a plain union -- a month outside that
# overlap (where only a factor-level series has data) must NOT appear.

.build_test_spine <- function(s1, s2, s3, s4) {
  spine_start <- max(min(s1$ym), min(s2$ym))
  spine_end   <- min(max(s1$ym), max(s2$ym))
  spine <- tibble::tibble(
    ym = format(
      seq(as.Date(paste0(spine_start, "-01")),
          as.Date(paste0(spine_end, "-01")),
          by = "month"),
      "%Y-%m"
    )
  )
  spine |>
    dplyr::left_join(s1, by = "ym") |>
    dplyr::left_join(s2, by = "ym") |>
    dplyr::left_join(s3, by = "ym") |>
    dplyr::left_join(s4, by = "ym")
}

test_that("port_returns spine: a month missing from stk_drif is kept with stk_drif = NA, not deleted (#641)", {
  s1 <- tibble::tibble(ym = sprintf("2021-%02d", 1:12), stk_max = seq(0.01, 0.12, length.out = 12))
  # stk_drif has no March row at all -- mirrors the #641 symptom
  s2 <- tibble::tibble(ym = setdiff(sprintf("2021-%02d", 1:12), "2021-03"),
                        stk_drif = seq(0.02, 0.12, length.out = 11))
  s3 <- tibble::tibble(ym = sprintf("2021-%02d", 1:12), fac_max = seq(0.005, 0.06, length.out = 12))
  s4 <- tibble::tibble(ym = sprintf("2021-%02d", 1:12), fac_drif = seq(0.003, 0.05, length.out = 12))

  combined <- .build_test_spine(s1, s2, s3, s4)

  # All 12 months survive -- the old inner_join chain would have dropped March.
  expect_equal(nrow(combined), 12L)
  expect_true("2021-03" %in% combined$ym)

  march_row <- combined[combined$ym == "2021-03", ]
  expect_true(is.na(march_row$stk_drif))
  expect_false(is.na(march_row$stk_max))
  expect_false(is.na(march_row$fac_max))
  expect_false(is.na(march_row$fac_drif))
})

test_that("port_returns spine: bounded to the stock-level overlap, not the factor-level union (#641)", {
  # fac_max/fac_drif have a much longer history (mirrors fm_portfolio /
  # drif_portfolio going back to the 1960s) than the stock-level series.
  # The spine must NOT extend back to cover it.
  s1 <- tibble::tibble(ym = sprintf("2020-%02d", 6:12), stk_max = seq(0.01, 0.07, length.out = 7))
  s2 <- tibble::tibble(ym = sprintf("2020-%02d", 6:12), stk_drif = seq(0.02, 0.08, length.out = 7))
  s3 <- tibble::tibble(ym = c(sprintf("2015-%02d", 1:12), sprintf("2020-%02d", 6:12)),
                        fac_max = seq(0.001, 0.02, length.out = 19))
  s4 <- tibble::tibble(ym = c(sprintf("2015-%02d", 1:12), sprintf("2020-%02d", 6:12)),
                        fac_drif = seq(0.001, 0.02, length.out = 19))

  combined <- .build_test_spine(s1, s2, s3, s4)

  # Bounded to the stk_max/stk_drif overlap: 2020-06 .. 2020-12 (7 months),
  # NOT expanded back to 2015 where only fac_max/fac_drif have data.
  expect_equal(nrow(combined), 7L)
  expect_false(any(grepl("^2015", combined$ym)))
  expect_setequal(combined$ym, sprintf("2020-%02d", 6:12))
})

# ── .port_weighted_return() (#641) ──────────────────────────────────────────
# Sourced from the real R/plan_portfolio_opt.R (top of this file) -- not
# reproduced, since it is a genuine top-level function.

test_that(".port_weighted_return: matches plain matrix multiplication when no NA is present", {
  ret_matrix <- matrix(
    c(0.01, 0.02, 0.03, 0.04, 0.02, 0.01, -0.01, 0.00),
    nrow = 4L, ncol = 2L,
    dimnames = list(NULL, c("a", "b"))
  )
  w <- c(a = 0.6, b = 0.4)

  got <- .port_weighted_return(ret_matrix, w)
  want <- as.numeric(ret_matrix %*% w)

  expect_equal(got, want, tolerance = 1e-12)
})

test_that(".port_weighted_return: renormalises weights over available strategies (#641)", {
  # 3 strategies (a, b, c) so a 2-of-3 renormalisation can be shown without
  # tripping the <2-available floor (covered by a dedicated test below).
  # Row 1: all three present. Row 2: b is missing -> a and c's weights
  # (0.5, 0.2) are rescaled to sum to 1, preserving their *relative* split.
  # Row 3: only a present -> below the floor -> NA.
  ret_matrix <- matrix(
    c(0.05, 0.10, 0.20,          # a
      0.02, NA_real_, NA_real_,  # b
      0.01, 0.03, NA_real_),     # c
    nrow = 3L, ncol = 3L,
    dimnames = list(NULL, c("a", "b", "c"))
  )
  w <- c(a = 0.5, b = 0.3, c = 0.2)

  got <- .port_weighted_return(ret_matrix, w)

  expect_equal(got[1], 0.05 * 0.5 + 0.02 * 0.3 + 0.01 * 0.2, tolerance = 1e-12)
  expect_equal(got[2], (0.10 * 0.5 + 0.03 * 0.2) / 0.7, tolerance = 1e-12)
  expect_true(is.na(got[3]))  # only a present -> below the 2-strategy floor
})

test_that(".port_weighted_return: a single available strategy returns NA (guard against a 1-strategy bet, #641)", {
  # 4-strategy case mirroring port_combined: only stk_max reports.
  ret_matrix <- matrix(
    c(0.03, NA_real_, NA_real_, NA_real_),
    nrow = 1L, ncol = 4L,
    dimnames = list(NULL, c("stk_max", "stk_drif", "fac_max", "fac_drif"))
  )
  w <- c(stk_max = 0.25, stk_drif = 0.25, fac_max = 0.25, fac_drif = 0.25)

  got <- .port_weighted_return(ret_matrix, w)

  expect_true(is.na(got))
  expect_false(identical(got, 0.03))  # must not silently become a 100% stk_max bet
})

test_that(".port_weighted_return: two available strategies is the minimum renormalised case (#641)", {
  ret_matrix <- matrix(
    c(0.03, 0.05, NA_real_, NA_real_),
    nrow = 1L, ncol = 4L,
    dimnames = list(NULL, c("stk_max", "stk_drif", "fac_max", "fac_drif"))
  )
  w <- c(stk_max = 0.25, stk_drif = 0.25, fac_max = 0.25, fac_drif = 0.25)

  got <- .port_weighted_return(ret_matrix, w)

  # Equal weights among the two available strategies (0.25/0.25 renormalised to 0.5/0.5)
  expect_equal(got, mean(c(0.03, 0.05)), tolerance = 1e-12)
})

test_that(".port_weighted_return: zero available weight mass returns NA, not NaN (#641)", {
  ret_matrix <- matrix(
    c(0.03, 0.05, NA_real_, NA_real_),
    nrow = 1L, ncol = 4L,
    dimnames = list(NULL, c("stk_max", "stk_drif", "fac_max", "fac_drif"))
  )
  # Only the two MISSING strategies carry any weight -- the two available
  # ones are weighted zero, so renormalising would divide by zero.
  w <- c(stk_max = 0, stk_drif = 0, fac_max = 0.5, fac_drif = 0.5)

  got <- .port_weighted_return(ret_matrix, w)

  expect_true(is.na(got))
  expect_false(is.nan(got))
})
