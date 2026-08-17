testthat::local_edition(3)
# source() is correct here: R/utils_metrics.R is a standalone repo-root script,
# not part of the packages/historicaldata package namespace. Sourcing exercises
# the actual file used by the targets pipeline rather than any package export.
source(here::here("R/utils_metrics.R"))

test_that("annualise_returns: all-zero returns produce CAGR 0, vol 0, sharpe NA, max_dd 0", {
  ret <- rep(0, 24)
  m <- annualise_returns(ret)
  expect_equal(m$cagr,   0, tolerance = 1e-10)
  expect_equal(m$vol,    0, tolerance = 1e-10)
  expect_true(is.na(m$sharpe))
  expect_equal(m$max_dd, 0, tolerance = 1e-10)
  expect_equal(m$n, 24L)
})

test_that("annualise_returns: 1% monthly for 12 months gives CAGR ~12.68%", {
  ret <- rep(0.01, 12)
  m <- annualise_returns(ret, periods_per_year = 12L)
  expected_cagr <- 1.01^12 - 1   # 0.126825...
  expect_equal(m$cagr, expected_cagr, tolerance = 1e-8)
  expect_equal(m$n, 12L)
})

test_that("annualise_returns: known toy series gives expected Sharpe to 2 dp", {
  # Alternating +5%, -3% monthly for 24 months
  # Mean = 0.01, var ≈ 0.0016, so we can work out expected values analytically
  ret <- rep(c(0.05, -0.03), 12)   # 24 months
  m <- annualise_returns(ret, periods_per_year = 12L)

  # CAGR: prod(1+ret)^(12/24) - 1 = (1.05 * 0.97)^12 / 24... let's just verify sign
  # Each pair: 1.05 * 0.97 = 1.0185, so equity grows slowly
  expect_true(m$cagr > 0)
  expect_true(m$sharpe > 0)   # positive Sharpe since CAGR > 0
  expect_true(m$max_dd < 0)   # must have some drawdown
  expect_equal(m$n, 24L)

  # Spot-check Sharpe to 2 decimal places
  equity <- cumprod(1 + ret)
  n <- 24
  cagr_expected <- equity[n]^(12 / n) - 1
  vol_expected  <- stats::sd(ret) * sqrt(12)
  sharpe_expected <- cagr_expected / vol_expected
  expect_equal(m$sharpe, sharpe_expected, tolerance = 1e-10)
})

test_that("annualise_returns: second toy series — constant positive returns", {
  # 36 months of exactly 0.5% (low vol, positive CAGR)
  ret <- rep(0.005, 36)
  m <- annualise_returns(ret, periods_per_year = 12L)

  expected_cagr <- 1.005^12 - 1
  expect_equal(m$cagr, expected_cagr, tolerance = 1e-8)
  # vol should be 0 (constant), so sharpe NA
  expect_equal(m$vol, 0, tolerance = 1e-10)
  expect_true(is.na(m$sharpe))
  # No drawdown on constant positive returns
  expect_equal(m$max_dd, 0, tolerance = 1e-10)
  expect_true(is.na(m$calmar))  # max_dd = 0, calmar undefined
})

test_that("annualise_returns: fewer than 2 observations returns all NA", {
  expect_equal(annualise_returns(numeric(0))$n, 0L)
  expect_true(is.na(annualise_returns(numeric(0))$cagr))
  expect_equal(annualise_returns(0.1)$n, 1L)
  expect_true(is.na(annualise_returns(0.1)$sharpe))
})

test_that("annualise_returns: NA values are dropped by default", {
  ret_with_na <- c(0.01, NA, 0.02, NA, 0.03)
  ret_clean   <- c(0.01, 0.02, 0.03)
  m_na    <- annualise_returns(ret_with_na)
  m_clean <- annualise_returns(ret_clean)
  expect_equal(m_na$cagr,   m_clean$cagr,   tolerance = 1e-10)
  expect_equal(m_na$sharpe, m_clean$sharpe, tolerance = 1e-10)
  expect_equal(m_na$n, 3L)
})

test_that("annualise_returns: daily periods_per_year = 252 changes output", {
  set.seed(42L)
  ret <- rnorm(252, mean = 0.0003, sd = 0.01)
  m_d <- annualise_returns(ret, periods_per_year = 252L)
  m_m <- annualise_returns(ret, periods_per_year = 12L)
  # Annual vol with daily scaling should be larger than with monthly scaling
  expect_true(m_d$vol > m_m$vol)
})

test_that("annualise_returns: non-numeric ret aborts with cli_abort", {
  expect_error(
    annualise_returns(c("a", "b", "c")),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    annualise_returns(c("a", "b", "c"))
  )
})

test_that("annualise_returns: invalid periods_per_year aborts", {
  expect_error(
    annualise_returns(c(0.01, 0.02), periods_per_year = -1),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    annualise_returns(c(0.01, 0.02), periods_per_year = -1)
  )
})

test_that("annualise_returns: function signature is stable (catches API drift)", {
  expect_snapshot(args(annualise_returns))
})

# ── sharpe_ratio_rf() (#677) ─────────────────────────────────────────────

test_that("sharpe_ratio_rf: known-value case matches hand computation", {
  ret <- rep(0.01, 12)
  rf  <- rep(0.0002, 12)
  m <- sharpe_ratio_rf(ret, rf, periods_per_year = 12L)

  expected_ann_ret <- 1.01^12 - 1
  expected_ann_vol <- stats::sd(ret) * sqrt(12)
  expected_ann_rf  <- mean(rf) * 12
  expected_sharpe  <- (expected_ann_ret - expected_ann_rf) / expected_ann_vol

  expect_equal(m$ann_ret, expected_ann_ret, tolerance = 1e-10)
  expect_equal(m$ann_rf,  expected_ann_rf,  tolerance = 1e-10)
  expect_equal(m$ann_vol, expected_ann_vol, tolerance = 1e-10)
  # vol is 0 here (constant returns) -> sharpe NA, not Inf
  expect_true(is.na(m$sharpe))
  expect_equal(m$n, 12L)
})

test_that("sharpe_ratio_rf: non-zero-vol toy series gives a finite, rf-deducted Sharpe", {
  ret <- rep(c(0.05, -0.03), 12)   # 24 months, alternating
  rf  <- rep(0.001, 24)
  m <- sharpe_ratio_rf(ret, rf, periods_per_year = 12L)

  equity <- cumprod(1 + ret)
  n <- 24
  ann_ret_expected <- equity[n]^(12 / n) - 1
  ann_vol_expected <- stats::sd(ret) * sqrt(12)
  ann_rf_expected  <- mean(rf) * 12
  sharpe_expected  <- (ann_ret_expected - ann_rf_expected) / ann_vol_expected

  expect_equal(m$sharpe, sharpe_expected, tolerance = 1e-10)
  expect_true(is.finite(m$sharpe))
  expect_equal(m$n, 24L)
})

test_that("sharpe_ratio_rf: rf deduction lowers Sharpe vs a zero risk-free rate", {
  ret <- rep(c(0.05, -0.03), 12)
  rf_zero <- rep(0, 24)
  rf_pos  <- rep(0.005, 24)   # meaningfully positive monthly rf

  sharpe_zero_rf <- sharpe_ratio_rf(ret, rf_zero, periods_per_year = 12L)$sharpe
  sharpe_pos_rf  <- sharpe_ratio_rf(ret, rf_pos,  periods_per_year = 12L)$sharpe

  expect_true(sharpe_pos_rf < sharpe_zero_rf)
})

test_that("sharpe_ratio_rf: NULL rf aborts loud rather than defaulting to zero (#677 defect B)", {
  expect_error(
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), NULL),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), NULL)
  )
})

test_that("sharpe_ratio_rf: non-numeric rf aborts", {
  expect_error(
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), c("a", "b", "c")),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), c("a", "b", "c"))
  )
})

test_that("sharpe_ratio_rf: non-numeric ret aborts", {
  expect_error(
    sharpe_ratio_rf(c("a", "b"), c(0.001, 0.001)),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c("a", "b"), c(0.001, 0.001))
  )
})

test_that("sharpe_ratio_rf: length mismatch between ret and rf aborts", {
  expect_error(
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), c(0.001, 0.001)),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c(0.01, 0.02, 0.03), c(0.001, 0.001))
  )
})

test_that("sharpe_ratio_rf: invalid periods_per_year aborts", {
  expect_error(
    sharpe_ratio_rf(c(0.01, 0.02), c(0.001, 0.001), periods_per_year = 0),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c(0.01, 0.02), c(0.001, 0.001), periods_per_year = 0)
  )
})

test_that("sharpe_ratio_rf: non-finite ret aborts on non-finite volatility", {
  expect_error(
    sharpe_ratio_rf(c(0.01, Inf, 0.02), c(0.001, 0.001, 0.001)),
    class = "rlang_error"
  )
  expect_snapshot(
    error = TRUE,
    sharpe_ratio_rf(c(0.01, Inf, 0.02), c(0.001, 0.001, 0.001))
  )
})

test_that("sharpe_ratio_rf: na.rm drops paired NAs positionally", {
  ret <- c(0.01, NA, 0.02, 0.03, NA)
  rf  <- c(0.001, 0.001, NA, 0.001, 0.001)
  # After pairwise NA removal: positions 1 and 4 survive (ret[2], ret[5] NA
  # in ret; ret[3] paired with NA rf) -- only 2 complete pairs, n < 2 is not
  # true here since n==2, but let's assert the count directly.
  m <- sharpe_ratio_rf(ret, rf, periods_per_year = 12L)
  expect_equal(m$n, 2L)
})

test_that("sharpe_ratio_rf: fewer than 2 paired observations returns all NA (deliberate default)", {
  m <- sharpe_ratio_rf(numeric(0), numeric(0))
  expect_equal(m$n, 0L)
  expect_true(is.na(m$sharpe))

  m1 <- sharpe_ratio_rf(0.01, 0.001)
  expect_equal(m1$n, 1L)
  expect_true(is.na(m1$sharpe))
})

test_that("sharpe_ratio_rf: function signature is stable (catches API drift)", {
  expect_snapshot(args(sharpe_ratio_rf))
})
