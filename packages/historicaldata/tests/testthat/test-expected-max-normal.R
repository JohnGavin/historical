# Tests for hd_expected_max_normal() -- exact E[max of K iid N(0,1)]
# Refs #931
testthat::local_edition(3)

# Independent reference: plain quadrature over a wide fixed range, written
# separately from the package implementation (different limits, no log-space).
ref_emax <- function(K) {
  stats::integrate(
    function(x) K * x * stats::dnorm(x) * stats::pnorm(x)^(K - 1),
    lower = -40, upper = 40, rel.tol = 1e-12, subdivisions = 2000L
  )$value
}

test_that("K = 1 returns exactly 0", {
  expect_identical(hd_expected_max_normal(1), 0)
  expect_identical(hd_expected_max_normal(1L), 0)
})

test_that("K = 2 equals 1/sqrt(pi) (worked check)", {
  expect_equal(hd_expected_max_normal(2), 1 / sqrt(pi), tolerance = 1e-10)
})

test_that("K = 10 matches the value tabulated in #931", {
  expect_equal(hd_expected_max_normal(10), 1.53875, tolerance = 1e-5)
})

test_that("the #931 table of 8 K values matches the reference within 1e-6", {
  K_grid <- c(2, 5, 10, 50, 100, 500, 1000, 5000)
  # Exact values as printed in the issue (5 decimals) -- the absolute error
  # of a 5-decimal rounding is <= 5e-6, so 1e-5 relative here.
  issue <- c(0.56419, 1.16296, 1.53875, 2.24907, 2.50759, 3.03670,
             3.24144, 3.67756)
  got <- vapply(K_grid, hd_expected_max_normal, numeric(1))
  expect_equal(got, issue, tolerance = 1e-5)
  expect_equal(got, vapply(K_grid, ref_emax, numeric(1)), tolerance = 1e-6)
})

test_that("monotone increasing in K", {
  K_grid <- c(1, 1.5, 2, 3, 5, 10, 50, 100, 1000, 1e5)
  got <- vapply(K_grid, hd_expected_max_normal, numeric(1))
  expect_true(all(diff(got) > 0))
})

test_that("a non-integer K lies strictly between its integer neighbours", {
  lo <- hd_expected_max_normal(2)
  hi <- hd_expected_max_normal(3)
  mid <- hd_expected_max_normal(2.5)
  expect_gt(mid, lo)
  expect_lt(mid, hi)
  expect_equal(mid, ref_emax(2.5), tolerance = 1e-6)
})

test_that("large K is correct, not merely finite", {
  # Compared with the Bailey-Lopez de Prado quantile interpolation
  # (independent of the quadrature) at 1%, and with the value 4.8629 found
  # by recentred quadrature when this was written.
  big <- hd_expected_max_normal(1e6)
  bldp <- (1 - 0.5772156649) * stats::qnorm(1 - 1 / 1e6) +
    0.5772156649 * stats::qnorm(1 - 1 / (1e6 * exp(1)))
  expect_true(is.finite(big))
  expect_lt(abs(big / bldp - 1), 0.01)
  expect_equal(big, 4.8629, tolerance = 1e-4)
  expect_gt(hd_expected_max_normal(1e8), big)
})

test_that("agrees with a deterministic simulation (generous tolerance)", {
  # Monte Carlo, set.seed: SE of the mean ~ 0.59/sqrt(2e4) ~ 0.004, so a 3%
  # relative tolerance (~0.046) is roughly 10 SE -- generous by design.
  set.seed(931)
  sim <- mean(replicate(20000L, max(stats::rnorm(10L))))
  expect_equal(hd_expected_max_normal(10), sim, tolerance = 0.03)
})

test_that("tolerance can fail: a deliberately wrong value is rejected", {
  # The old closed-form approximation for K = 2 (31% high) must NOT pass.
  old <- sqrt(2 * log(2)) - (0.5772156649 + log(pi / 2)) / (2 * sqrt(2 * log(2)))
  expect_false(isTRUE(all.equal(old, hd_expected_max_normal(2),
                                tolerance = 0.05)))
})

test_that("invalid K aborts with an informative message", {
  expect_snapshot(error = TRUE, hd_expected_max_normal(0.5))
  expect_snapshot(error = TRUE, hd_expected_max_normal(0))
  expect_snapshot(error = TRUE, hd_expected_max_normal(NA_real_))
  expect_snapshot(error = TRUE, hd_expected_max_normal(Inf))
  expect_snapshot(error = TRUE, hd_expected_max_normal("10"))
  expect_snapshot(error = TRUE, hd_expected_max_normal(c(2, 3)))
})

test_that("function signature is stable", {
  expect_snapshot(args(hd_expected_max_normal))
})
