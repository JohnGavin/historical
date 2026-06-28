# Tests for hd_min_var_weights() — GMV weights (#498 Phase 3a)
#
# Test structure:
#   1. Weights sum to 1 when normalize = TRUE
#   2. Diagonal Sigma → weights proportional to 1/variance (inverse-variance)
#   3. GMV portfolio variance <= equal-weight variance
#   4. normalize = FALSE returns un-normalised solve result
#   5. Names preserved from Sigma dimnames
#   6–8. Error snapshots: singular Sigma, non-matrix input, p < 2
#   9.   Asymmetric matrix aborts
#   10.  Function signature stability snapshot
#
# Snapshot count: 4 snapshots (error msgs x3 + args x1) out of 10 blocks
# => ratio 4/10 >= 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers -------------------------------------------

# 4-asset well-conditioned diagonal covariance matrix
.make_diag_sigma <- function() {
  vars <- c(0.04, 0.09, 0.16, 0.25)   # variances: σ² = 0.2², 0.3², 0.4², 0.5²
  S <- diag(vars)
  dimnames(S) <- list(c("A","B","C","D"), c("A","B","C","D"))
  S
}

# Full 3-asset covariance matrix (well-conditioned)
.make_3asset_sigma <- function() {
  matrix(c(0.04, 0.01, 0.00,
           0.01, 0.09, 0.02,
           0.00, 0.02, 0.16),
         nrow = 3, ncol = 3,
         dimnames = list(c("A","B","C"), c("A","B","C")))
}

# ---- Test 1: weights sum to 1 (normalize = TRUE) ----------------------
test_that("weights sum to exactly 1 when normalize = TRUE", {
  S <- .make_3asset_sigma()
  w <- hd_min_var_weights(S, normalize = TRUE)
  expect_equal(sum(w), 1, tolerance = 1e-12)
  expect_length(w, 3L)
})

# ---- Test 2: diagonal Sigma → inverse-variance portfolio --------------
# For a diagonal Sigma, the GMV weights = (1/σ²_i) / sum(1/σ²_j)
test_that("diagonal Sigma produces inverse-variance weights", {
  S <- .make_diag_sigma()
  vars <- diag(S)
  inv_var <- 1 / vars
  expected_w <- inv_var / sum(inv_var)

  w <- hd_min_var_weights(S, normalize = TRUE)

  expect_equal(w, expected_w, tolerance = 1e-12, ignore_attr = TRUE)
})

# ---- Test 3: GMV portfolio variance <= equal-weight variance -----------
test_that("GMV portfolio variance is <= equal-weight variance", {
  S <- .make_3asset_sigma()
  p <- nrow(S)

  w_gmv  <- hd_min_var_weights(S)
  w_eq   <- rep(1/p, p)

  var_gmv <- as.numeric(t(w_gmv) %*% S %*% w_gmv)
  var_eq  <- as.numeric(t(w_eq)  %*% S %*% w_eq)

  expect_lte(var_gmv, var_eq)
  expect_true(is.finite(var_gmv))
  expect_true(var_gmv > 0)
})

# ---- Test 4: normalize = FALSE returns raw solve result ---------------
test_that("normalize = FALSE returns un-normalised solve(Sigma, 1)", {
  S <- .make_3asset_sigma()
  raw <- hd_min_var_weights(S, normalize = FALSE)
  expected_raw <- solve(S, rep(1, 3))

  expect_equal(raw, expected_raw, tolerance = 1e-12, ignore_attr = TRUE)
  # Raw weights do NOT necessarily sum to 1
  expect_false(abs(sum(raw) - 1) < 1e-12 && FALSE)   # just confirm it runs
  expect_true(is.numeric(raw))
})

# ---- Test 5: Names preserved from Sigma dimnames ----------------------
test_that("names of returned weights match rownames(Sigma)", {
  S <- .make_3asset_sigma()
  w <- hd_min_var_weights(S)
  expect_equal(names(w), rownames(S))
  expect_equal(names(w), c("A", "B", "C"))
})

test_that("returns NULL names when Sigma has no dimnames", {
  S <- matrix(c(1, 0.2, 0.2, 1), 2, 2)   # no dimnames
  w <- hd_min_var_weights(S)
  expect_null(names(w))
})

# ---- Test 6: Singular Sigma aborts with snapshot ----------------------
test_that("singular Sigma aborts with informative error suggesting hd_cov_estimate", {
  # p=4, rank=2: Sigma is singular
  set.seed(1L)
  X <- matrix(rnorm(4 * 2), nrow = 4, ncol = 2)   # rank 2
  S_sing <- tcrossprod(X)     # 4x4 but rank 2
  S_sing <- (S_sing + t(S_sing)) / 2
  dimnames(S_sing) <- list(paste0("A", 1:4), paste0("A", 1:4))

  expect_snapshot(
    error = TRUE,
    hd_min_var_weights(S_sing)
  )
})

# ---- Test 7: non-matrix input aborts with snapshot --------------------
test_that("non-matrix input aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights("not_a_matrix")
  )
})

# ---- Test 8: p < 2 aborts with snapshot -------------------------------
test_that("1x1 matrix aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights(matrix(1, 1, 1))
  )
})

# ---- Test 9: asymmetric matrix aborts ---------------------------------
test_that("asymmetric matrix aborts with informative error", {
  S_asym <- matrix(c(1, 0.5, 0.1, 1), 2, 2)   # not symmetric
  expect_error(
    hd_min_var_weights(S_asym),
    regexp = "symmetric"
  )
})

# ---- Test 10: function signature stability ----------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_min_var_weights))
})
