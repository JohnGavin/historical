# Tests for hd_risk_contribution() — Euler risk decomposition (#624, #626)
#
# Test structure:
#   1. Euler identity: sum(cr) == sigma_p (the correctness anchor)
#   2. sum(pct_contribution) == 1
#   3. ERC sanity: diagonal cov, inverse-vol weights -> equal pct_contribution
#      (the property the #626 equal-risk-contribution allocator depends on)
#   4. Uncorrelated equal-variance assets, equal weights -> pct 1/n each
#   5. Correlated pair shows higher total risk than the same weights with
#      zero correlation (the property weight-HHI misses)
#   6. Negative weight (short leg) yields a negative contribution
#   7. Rank-deficient covariance still returns finite values
#   8-12. Error snapshots: non-square, asymmetric, dimension mismatch,
#         name disagreement, NA
#   13. Function signature stability snapshot
#
# Snapshot count: 6 snapshots (error msgs x5 + args x1) out of 13 blocks
# => ratio 6/13 ~= 46% >= 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Test 1: Euler identity ----------------------------------------------
test_that("Euler identity: sum(cr) equals portfolio volatility", {
  Sigma <- matrix(
    c(0.04, 0.01, 0.00,
      0.01, 0.09, 0.02,
      0.00, 0.02, 0.01),
    nrow = 3
  )
  w <- c(0.5, 0.3, 0.2)
  sigma_p <- sqrt(as.numeric(t(w) %*% Sigma %*% w))

  res <- hd_risk_contribution(w, Sigma)
  expect_equal(sum(res$cr), sigma_p, tolerance = 1e-10)
})

# ---- Test 2: pct_contribution sums to 1 -----------------------------------
test_that("pct_contribution sums to 1", {
  Sigma <- matrix(
    c(0.04, 0.01, 0.00,
      0.01, 0.09, 0.02,
      0.00, 0.02, 0.01),
    nrow = 3
  )
  w <- c(0.5, 0.3, 0.2)
  res <- hd_risk_contribution(w, Sigma)
  expect_equal(sum(res$pct_contribution), 1, tolerance = 1e-10)
})

# ---- Test 3: ERC sanity — inverse-vol weights equalise pct_contribution ---
test_that("diagonal cov + inverse-vol weights give equal pct_contribution (ERC property)", {
  sds   <- c(0.1, 0.2, 0.3)
  Sigma <- diag(sds^2)
  w_raw <- 1 / sds
  w     <- w_raw / sum(w_raw)

  res <- hd_risk_contribution(w, Sigma)
  expect_equal(res$pct_contribution, rep(1 / 3, 3), tolerance = 1e-10)
})

# ---- Test 4: uncorrelated equal-variance, equal weight -> pct 1/n each ---
test_that("uncorrelated equal-variance assets with equal weights give pct 1/n", {
  Sigma <- diag(rep(0.04, 3))
  w <- rep(1 / 3, 3)
  res <- hd_risk_contribution(w, Sigma)
  expect_equal(res$pct_contribution, rep(1 / 3, 3), tolerance = 1e-10)
})

# ---- Test 5: correlation raises combined risk vs. same weights, zero corr ---
test_that("correlated pair has higher portfolio vol than same weights uncorrelated", {
  w <- c(0.5, 0.5)

  Sigma_corr <- matrix(c(0.04, 0.02, 0.02, 0.04), nrow = 2)
  Sigma_unc  <- matrix(c(0.04, 0.00, 0.00, 0.04), nrow = 2)

  res_corr <- hd_risk_contribution(w, Sigma_corr)
  res_unc  <- hd_risk_contribution(w, Sigma_unc)

  sigma_p_corr <- sum(res_corr$cr)
  sigma_p_unc  <- sum(res_unc$cr)

  expect_gt(sigma_p_corr, sigma_p_unc)
})

# ---- Test 6: negative weight yields negative contribution -----------------
test_that("a short position can show a negative pct_contribution (hedge)", {
  Sigma <- matrix(c(0.04, 0.03, 0.03, 0.04), nrow = 2)
  w <- c(1, -0.5)
  res <- hd_risk_contribution(w, Sigma)

  expect_lt(res$cr[2], 0)
  expect_lt(res$pct_contribution[2], 0)
  expect_equal(sum(res$pct_contribution), 1, tolerance = 1e-10)
})

# ---- Test 7: rank-deficient covariance still returns finite values --------
test_that("rank-deficient (singular) covariance returns finite results", {
  v <- c(0.2, 0.3, 0.1)
  Sigma <- outer(v, v) # rank-1 PSD matrix
  w <- c(0.3, 0.3, 0.4)

  res <- hd_risk_contribution(w, Sigma)
  expect_true(all(is.finite(res$mcr)))
  expect_true(all(is.finite(res$cr)))
  expect_true(all(is.finite(res$pct_contribution)))
})

# ---- Test 7b: zero portfolio volatility returns NA, not an error ----------
test_that("all-zero weights return NA_real_ for mcr/cr/pct_contribution", {
  Sigma <- diag(rep(0.04, 2))
  w <- c(0, 0)
  res <- hd_risk_contribution(w, Sigma)
  expect_true(all(is.na(res$mcr)))
  expect_true(all(is.na(res$cr)))
  expect_true(all(is.na(res$pct_contribution)))
})

# ---- Test 8: non-square cov_mat aborts with snapshot -----------------------
test_that("non-square cov_mat aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_risk_contribution(c(0.5, 0.5), matrix(1:6, nrow = 2))
  )
})

# ---- Test 9: asymmetric cov_mat aborts with snapshot -----------------------
test_that("asymmetric cov_mat aborts with informative error", {
  Sigma <- matrix(c(0.04, 0.02, 0.05, 0.04), nrow = 2)
  expect_snapshot(
    error = TRUE,
    hd_risk_contribution(c(0.5, 0.5), Sigma)
  )
})

# ---- Test 10: dimension mismatch aborts with snapshot ----------------------
test_that("dimension mismatch between w and cov_mat aborts with informative error", {
  Sigma <- diag(rep(0.04, 2))
  expect_snapshot(
    error = TRUE,
    hd_risk_contribution(c(0.5, 0.3, 0.2), Sigma)
  )
})

# ---- Test 11: name disagreement aborts with snapshot ------------------------
test_that("disagreeing names between w and cov_mat abort with informative error", {
  Sigma <- diag(rep(0.04, 2))
  dimnames(Sigma) <- list(c("A", "B"), c("A", "B"))
  w <- c(X = 0.5, Y = 0.5)
  expect_snapshot(
    error = TRUE,
    hd_risk_contribution(w, Sigma)
  )
})

# ---- Test 12: NA in w aborts with snapshot ----------------------------------
test_that("NA in w aborts with informative error", {
  Sigma <- diag(rep(0.04, 2))
  expect_snapshot(
    error = TRUE,
    hd_risk_contribution(c(0.5, NA_real_), Sigma)
  )
})

# ---- Test 13: function signature stability ----------------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_risk_contribution))
})
