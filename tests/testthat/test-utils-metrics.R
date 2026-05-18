test_that("calc_backtest_metrics: all-zero returns produce CAGR 0, vol 0, sharpe NA, max_dd 0", {
  ret <- rep(0, 24)
  m <- calc_backtest_metrics(ret)
  expect_equal(m$cagr,   0, tolerance = 1e-10)
  expect_equal(m$vol,    0, tolerance = 1e-10)
  expect_true(is.na(m$sharpe))
  expect_equal(m$max_dd, 0, tolerance = 1e-10)
  expect_equal(m$n, 24L)
})

test_that("calc_backtest_metrics: 1% monthly for 12 months gives CAGR ~12.68%", {
  ret <- rep(0.01, 12)
  m <- calc_backtest_metrics(ret, periods_per_year = 12L)
  expected_cagr <- 1.01^12 - 1   # 0.126825...
  expect_equal(m$cagr, expected_cagr, tolerance = 1e-8)
  expect_equal(m$n, 12L)
})

test_that("calc_backtest_metrics: known toy series gives expected Sharpe to 2 dp", {
  # Alternating +5%, -3% monthly for 24 months
  # Mean = 0.01, var ≈ 0.0016, so we can work out expected values analytically
  ret <- rep(c(0.05, -0.03), 12)   # 24 months
  m <- calc_backtest_metrics(ret, periods_per_year = 12L)

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

test_that("calc_backtest_metrics: second toy series — constant positive returns", {
  # 36 months of exactly 0.5% (low vol, positive CAGR)
  ret <- rep(0.005, 36)
  m <- calc_backtest_metrics(ret, periods_per_year = 12L)

  expected_cagr <- 1.005^12 - 1
  expect_equal(m$cagr, expected_cagr, tolerance = 1e-8)
  # vol should be 0 (constant), so sharpe NA
  expect_equal(m$vol, 0, tolerance = 1e-10)
  expect_true(is.na(m$sharpe))
  # No drawdown on constant positive returns
  expect_equal(m$max_dd, 0, tolerance = 1e-10)
  expect_true(is.na(m$calmar))  # max_dd = 0, calmar undefined
})

test_that("calc_backtest_metrics: fewer than 2 observations returns all NA", {
  expect_equal(calc_backtest_metrics(numeric(0))$n, 0L)
  expect_true(is.na(calc_backtest_metrics(numeric(0))$cagr))
  expect_equal(calc_backtest_metrics(0.1)$n, 1L)
  expect_true(is.na(calc_backtest_metrics(0.1)$sharpe))
})

test_that("calc_backtest_metrics: NA values are dropped by default", {
  ret_with_na <- c(0.01, NA, 0.02, NA, 0.03)
  ret_clean   <- c(0.01, 0.02, 0.03)
  m_na    <- calc_backtest_metrics(ret_with_na)
  m_clean <- calc_backtest_metrics(ret_clean)
  expect_equal(m_na$cagr,   m_clean$cagr,   tolerance = 1e-10)
  expect_equal(m_na$sharpe, m_clean$sharpe, tolerance = 1e-10)
  expect_equal(m_na$n, 3L)
})

test_that("calc_backtest_metrics: daily periods_per_year = 252 changes output", {
  set.seed(42L)
  ret <- rnorm(252, mean = 0.0003, sd = 0.01)
  m_d <- calc_backtest_metrics(ret, periods_per_year = 252L)
  m_m <- calc_backtest_metrics(ret, periods_per_year = 12L)
  # Annual vol with daily scaling should be larger than with monthly scaling
  expect_true(m_d$vol > m_m$vol)
})

test_that("calc_backtest_metrics: non-numeric ret aborts with cli_abort", {
  expect_error(
    calc_backtest_metrics(c("a", "b", "c")),
    class = "rlang_error"
  )
})

test_that("calc_backtest_metrics: invalid periods_per_year aborts", {
  expect_error(
    calc_backtest_metrics(c(0.01, 0.02), periods_per_year = -1),
    class = "rlang_error"
  )
})
