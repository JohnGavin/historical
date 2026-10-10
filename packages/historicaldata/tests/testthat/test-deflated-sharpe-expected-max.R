# Tests for the expected-max benchmark inside hd_deflated_sharpe()
# Refs #931 -- g(K) = z - (gamma + log(pi/2)) / (2 z) overstates
# E[max of K iid N(0,1)] by roughly 9-31% for K in 2..5000.
#
# DELIBERATE RED TEST: this file fails until #931 is fixed in
# R/falsification.R. It is the specification for the fix.
testthat::local_edition(3)

# Exact E[max of K iid N(0,1)] = K * int x phi(x) Phi(x)^(K-1) dx.
# Deterministic quadrature, no Monte Carlo noise.
exact_emax <- function(K) {
  stats::integrate(
    function(x) K * x * stats::dnorm(x) * stats::pnorm(x)^(K - 1),
    lower = -40, upper = 40, rel.tol = 1e-12, subdivisions = 2000L
  )$value
}

# The benchmark is not exposed as a function, so recover SR0 (in units of
# sqrt(V), V = 1) from hd_deflated_sharpe()'s observable output. With
#   dsr = ((sr - e / sqrt(T)) / se) * sqrt(ann / T)
# we get e = sqrt(T) * (sr - stat * se), where sr and se are recomputed here
# from the same r using the documented Lo (2002) variance. No R/ source is
# touched.
implied_emax <- function(r, K, ann = 252L) {
  res <- hd_deflated_sharpe(r, K_trials = K, ann_factor = ann,
                            trial_sharpe_var = 1)
  n  <- length(r)
  mu <- mean(r)
  s  <- stats::sd(r)
  sr <- mu / s
  m3 <- sum((r - mu)^3) / n / s^3
  m4 <- sum((r - mu)^4) / n / s^4
  se <- sqrt(max((1 - m3 * sr + (m4 - 1) / 4 * sr^2) / n,
                 .Machine$double.eps))
  stat <- res$dsr / sqrt(ann / n)
  sqrt(n) * (sr - stat * se)
}

set.seed(931)
r_fixture <- stats::rnorm(500L, mean = 0.0005, sd = 0.01)
K_grid <- c(2, 5, 10, 50, 100, 500, 1000, 5000)
tol_rel <- 0.05

test_that("implied SR0 benchmark is within 5% of exact E[max of K normals]", {
  for (K in K_grid) {
    ex  <- exact_emax(K)
    imp <- implied_emax(r_fixture, K)
    rel <- abs(imp / ex - 1)
    expect_lt(rel, tol_rel, label = sprintf("K=%g rel.err=%.3f", K, rel))
  }
})

test_that("the tolerance is able to fail: a deliberately wrong value is caught", {
  # Falsification of the check itself: 31% too high at K = 2 must exceed tol.
  expect_gt(abs(1.31 * exact_emax(2) / exact_emax(2) - 1), tol_rel)
  # Sanity on the reference: E[max of 2 N(0,1)] = 1/sqrt(pi).
  expect_equal(exact_emax(2), 1 / sqrt(pi), tolerance = 1e-8)
  # And the recovery helper returns 0 at K = 1 (no hurdle), so it is not
  # vacuously returning a constant.
  expect_equal(implied_emax(r_fixture, 1L), 0, tolerance = 1e-8)
})
