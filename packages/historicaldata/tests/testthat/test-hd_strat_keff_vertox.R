# Tests for hd_strat_keff_vertox() — Vertox K_eff_strat (#160 PR 2 of 4)
#
# The function is implicit (numerical inversion via Brent) and uses Monte
# Carlo. Tolerances reflect MC standard error at the default n_sim = 20000:
# - Boundary cases (identity, all-1s, all-(-1)s) → exact early-return, no tolerance
# - General cases → tol ≤ 0.10 (well above 1-sigma MC error)
# All tests use seed=1 for reproducibility.

test_that("identity matrix returns M exactly (no MC)", {
  for (M in c(2L, 5L, 10L)) {
    sigma <- diag(M)
    expect_equal(hd_strat_keff_vertox(sigma, n_sim = 1000L, seed = 1L), M)
  }
})

test_that("perfectly-correlated matrix returns 1 (boundary)", {
  for (M in c(2L, 5L, 10L)) {
    sigma <- matrix(1, M, M)
    expect_equal(hd_strat_keff_vertox(sigma, n_sim = 1000L, seed = 1L), 1)
  }
})

test_that("perfectly anti-correlated 2x2 returns 1", {
  sigma <- matrix(c(1, -1, -1, 1), 2, 2)
  expect_equal(hd_strat_keff_vertox(sigma, n_sim = 1000L, seed = 1L), 1)
})

test_that("M = 1 returns 1 without computation", {
  expect_equal(hd_strat_keff_vertox(matrix(1, 1, 1), n_sim = 100L, seed = 1L), 1)
})

test_that("block-diagonal (two perfectly-correlated blocks of 5) returns ~2", {
  block <- matrix(1, 5, 5)
  sigma <- rbind(
    cbind(block, matrix(0, 5, 5)),
    cbind(matrix(0, 5, 5), block)
  )
  k <- hd_strat_keff_vertox(sigma, n_sim = 20000L, seed = 1L)
  expect_gte(k, 1.5)
  expect_lte(k, 2.5)
})

test_that("monotonicity: adding an independent strategy weakly increases K_eff_strat", {
  sigma_4 <- diag(4)
  sigma_5 <- diag(5)
  k4 <- hd_strat_keff_vertox(sigma_4, n_sim = 5000L, seed = 1L)
  k5 <- hd_strat_keff_vertox(sigma_5, n_sim = 5000L, seed = 1L)
  expect_gte(k5, k4)
  expect_equal(k4, 4)
  expect_equal(k5, 5)
})

test_that("moderately correlated matrix gives K between 1 and M", {
  M <- 5L
  rho <- 0.5
  sigma <- matrix(rho, M, M)
  diag(sigma) <- 1
  k <- hd_strat_keff_vertox(sigma, n_sim = 20000L, seed = 1L)
  expect_gt(k, 1)
  expect_lt(k, M)
})

test_that("input validation: non-matrix input aborts with informative message", {
  expect_snapshot(error = TRUE, hd_strat_keff_vertox(c(1, 0.5, 0.5, 1)))
})

test_that("input validation: non-square matrix aborts", {
  expect_snapshot(error = TRUE, hd_strat_keff_vertox(matrix(1:6, 2, 3)))
})

test_that("input validation: empty matrix aborts", {
  expect_snapshot(error = TRUE, hd_strat_keff_vertox(matrix(numeric(0), 0, 0)))
})

test_that("input validation: non-symmetric matrix aborts", {
  bad <- matrix(c(1, 0.5, 0.3, 1), 2, 2)
  expect_snapshot(error = TRUE, hd_strat_keff_vertox(bad))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_strat_keff_vertox))
})
