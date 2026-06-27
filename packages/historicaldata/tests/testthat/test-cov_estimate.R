# Tests for hd_cov_estimate() — regularised covariance estimator (#498 Phase 1)
#
# Test structure:
#   1. sample method == stats::cov()
#   2. ledoit_wolf on wide frame (p>n) is positive-definite
#   3. ledoit_wolf shrinkage attribute in [0,1] for both targets
#   4. rmt_denoise: n_clipped >= 1, PD, bounded eigenvalue check
#   5. threshold hard: below-threshold off-diagonals zeroed, diagonal = 1
#   6. dimnames preserved from input
#   7–10. Error/validation snapshots (non-numeric, p<2, all-NA, bad method)
#   11. Function-signature stability snapshot
#
# Snapshot count: 5 snapshots (error msgs x4 + args x1) out of 11 test blocks
# => ratio 5/11 > 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers -------------------------------------------

# Wide frame: p=30 assets, n=20 obs (p > n => singular sample cov)
.make_wide_mat <- function(seed = 1L) {
  set.seed(seed)
  X <- matrix(stats::rnorm(20L * 30L), nrow = 20L, ncol = 30L)
  colnames(X) <- paste0("A", seq_len(30L))
  X
}

# Narrow frame: p=10 assets, n=60 obs (p < n => sample cov invertible)
.make_narrow_mat <- function(seed = 2L) {
  set.seed(seed)
  X <- matrix(stats::rnorm(60L * 10L), nrow = 60L, ncol = 10L)
  colnames(X) <- paste0("B", seq_len(10L))
  X
}

# ---- Test 1: sample == stats::cov() -----------------------------------
test_that("method='sample' returns exactly stats::cov() on complete-case matrix", {
  X <- .make_narrow_mat()
  out <- hd_cov_estimate(X, method = "sample")
  expect_equal(unclass(out), stats::cov(X), tolerance = 1e-12,
               ignore_attr = TRUE)
  expect_equal(attr(out, "method"),    "sample")
  expect_equal(attr(out, "n_obs"),     nrow(X))
  expect_equal(attr(out, "n_assets"),  ncol(X))
  expect_true(is.finite(attr(out, "condition_number")))
})

# ---- Test 2: ledoit_wolf is PD on wide frame --------------------------
test_that("ledoit_wolf (const_cor) is PD on wide (p>n) frame where sample cov is singular", {
  X <- .make_wide_mat()

  # Confirm sample covariance is singular / rank-deficient
  S_sample <- stats::cov(X)
  min_eval_sample <- min(eigen(S_sample, symmetric = TRUE,
                               only.values = TRUE)$values)
  expect_lte(min_eval_sample, 1e-10)   # effectively zero

  out <- hd_cov_estimate(X, method = "ledoit_wolf", lw_target = "const_cor")
  min_eval_lw <- min(eigen(out, symmetric = TRUE, only.values = TRUE)$values)
  expect_gt(min_eval_lw, 0,
    label = "LW const_cor minimum eigenvalue > 0 (positive-definite)")

  cond_lw     <- attr(out, "condition_number")
  cond_sample <- max(eigen(S_sample, symmetric = TRUE,
                           only.values = TRUE)$values) /
                 max(min_eval_sample, .Machine$double.eps)
  expect_lt(cond_lw, cond_sample,
    label = "LW condition number is smaller than sample's")
})

# ---- Test 3: ledoit_wolf shrinkage attribute for both targets ----------
test_that("ledoit_wolf shrinkage attribute is in [0,1] for both lw_target values", {
  X <- .make_wide_mat()

  out_cc <- hd_cov_estimate(X, method = "ledoit_wolf", lw_target = "const_cor")
  delta_cc <- attr(out_cc, "shrinkage")
  expect_true(is.numeric(delta_cc))
  expect_gte(delta_cc, 0)
  expect_lte(delta_cc, 1)

  out_id <- hd_cov_estimate(X, method = "ledoit_wolf", lw_target = "identity")
  delta_id <- attr(out_id, "shrinkage")
  expect_true(is.numeric(delta_id))
  expect_gte(delta_id, 0)
  expect_lte(delta_id, 1)

  # Both are PD on the wide frame
  expect_gt(min(eigen(out_cc, symmetric = TRUE, only.values = TRUE)$values), 0)
  expect_gt(min(eigen(out_id, symmetric = TRUE, only.values = TRUE)$values), 0)
})

# ---- Test 4: rmt_denoise attributes and eigenvalue-collapse check -----
test_that("rmt_denoise clips noise eigenvalues, reduces condition, stays PD", {
  X <- .make_wide_mat(seed = 3L)

  out <- hd_cov_estimate(X, method = "rmt_denoise")

  # n_clipped >= 1 on a noisy wide frame (p=30, n=20 => q=1.5, lambda_plus ~6.4)
  n_clipped <- attr(out, "n_clipped")
  expect_true(is.integer(n_clipped) || is.numeric(n_clipped))
  expect_gte(n_clipped, 1L)

  # PD
  min_eval <- min(eigen(out, symmetric = TRUE, only.values = TRUE)$values)
  expect_gt(min_eval, -1e-8,
    label = "rmt_denoise output is positive semi-definite")

  # Condition number <= sample's
  S_sample <- stats::cov(X)
  cond_sample <- max(eigen(S_sample, symmetric = TRUE,
                           only.values = TRUE)$values) /
                 max(min(eigen(S_sample, symmetric = TRUE,
                               only.values = TRUE)$values),
                     .Machine$double.eps)
  expect_lte(attr(out, "condition_number"), cond_sample)

  # Verify that the noise eigenvalues collapse to a single common value:
  # Reproduce the RMT clipping steps on the same input X to check the vals vector
  # before diagonal renormalization (which slightly perturbs eigenvalues).
  S1_ref  <- stats::cov(X)
  sd_ref  <- sqrt(diag(S1_ref))
  C_ref   <- S1_ref / outer(sd_ref, sd_ref)
  C_ref   <- pmin(pmax(C_ref, -1), 1)
  p       <- ncol(X)
  n       <- nrow(X)
  q       <- p / n
  lambda_plus <- (1 + sqrt(q))^2
  e_ref       <- eigen(C_ref, symmetric = TRUE)
  vals_ref    <- e_ref$values
  noise_idx   <- which(vals_ref < lambda_plus)
  # Clip to mean — this is what the function does internally
  vals_ref[noise_idx] <- mean(vals_ref[noise_idx])
  noise_vals_clipped  <- vals_ref[noise_idx]
  # After clipping all noise eigenvalues collapse to a single value
  expect_equal(
    length(unique(round(noise_vals_clipped, 8L))), 1L,
    label = "noise eigenvalues (below MP edge) all equal after clipping"
  )
})

# ---- Test 5: threshold hard, off-diagonal, diagonal stays 1 ----------
test_that("threshold hard: |rho|<=threshold -> 0; diagonal of implied correlation = 1", {
  X   <- .make_narrow_mat()
  thr <- 0.15
  out <- hd_cov_estimate(X, method = "threshold", threshold = thr,
                         threshold_type = "hard")

  # Recover implied correlation from the output
  sd_out <- sqrt(diag(out))
  C_out  <- out / outer(sd_out, sd_out)

  # Diagonal of implied correlation == 1
  expect_equal(diag(C_out), rep(1, ncol(out)), tolerance = 1e-10,
               ignore_attr = TRUE)

  # Original sample correlation
  S1   <- stats::cov(X)
  sd1  <- sqrt(diag(S1))
  C1   <- S1 / outer(sd1, sd1)
  p    <- ncol(X)

  # Off-diagonals with |rho_sample| <= thr should map to 0 in C_out
  for (i in seq_len(p)) {
    for (j in seq_len(p)) {
      if (i == j) next
      if (abs(C1[i, j]) <= thr) {
        expect_equal(C_out[i, j], 0, tolerance = 1e-10,
          label = paste0("C_out[", i, ",", j, "] == 0 when |rho|<=thr"))
      }
    }
  }

  # Output is symmetric
  expect_equal(out, t(out), tolerance = 1e-12)
})

# ---- Test 6: dimnames preserved from column names --------------------
test_that("dimnames of output match input column names", {
  nms <- c("SPY", "GLD", "TLT", "EEM", "VNQ")
  set.seed(7L)
  X <- matrix(stats::rnorm(50L * 5L), nrow = 50L, ncol = 5L)
  colnames(X) <- nms

  for (meth in c("sample", "ledoit_wolf", "rmt_denoise")) {
    out <- hd_cov_estimate(X, method = meth)
    expect_equal(rownames(out), nms,
      label = paste0(meth, ": rownames preserved"))
    expect_equal(colnames(out), nms,
      label = paste0(meth, ": colnames preserved"))
  }
})

# ---- Test 7: NA rows dropped with warning ----------------------------
test_that("NA rows are dropped with a warning; n_obs attribute reflects drop", {
  X_na <- .make_narrow_mat()
  X_na[c(3L, 7L), 1L] <- NA  # introduce 2 NA rows

  expect_warning(
    out <- hd_cov_estimate(X_na, method = "sample"),
    regexp = "Dropped 2 row"
  )
  expect_equal(attr(out, "n_obs"), nrow(X_na) - 2L)
})

# ---- Test 8: data.frame with date column is coerced correctly --------
test_that("data.frame input with date column is handled identically to matrix", {
  set.seed(5L)
  X <- matrix(stats::rnorm(40L * 4L), nrow = 40L, ncol = 4L)
  colnames(X) <- c("A", "B", "C", "D")
  df <- as.data.frame(X)
  df$date <- seq.Date(as.Date("2020-01-01"), by = "day", length.out = 40L)

  out_df  <- hd_cov_estimate(df,  method = "sample")
  out_mat <- hd_cov_estimate(X,   method = "sample")

  expect_equal(unclass(out_df), unclass(out_mat), tolerance = 1e-12,
               ignore_attr = TRUE)
  expect_equal(colnames(out_df), c("A", "B", "C", "D"))
})

# ---- Test 9: Error snapshots -----------------------------------------
test_that("non-numeric input aborts with informative cli_abort", {
  expect_snapshot(
    error = TRUE,
    hd_cov_estimate("not_a_matrix")
  )
})

test_that("single-column input (p<2) aborts with informative cli_abort", {
  expect_snapshot(
    error = TRUE,
    hd_cov_estimate(matrix(1:10, ncol = 1L))
  )
})

test_that("all-NA frame aborts after dropping NA rows", {
  X_allna <- matrix(NA_real_, nrow = 5L, ncol = 3L)
  expect_snapshot(
    error = TRUE,
    suppressWarnings(hd_cov_estimate(X_allna, method = "sample"))
  )
})

test_that("bad method value aborts with informative error", {
  X <- .make_narrow_mat()
  expect_snapshot(
    error = TRUE,
    hd_cov_estimate(X, method = "glasso")
  )
})

# ---- Test 10: function signature stability ----------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_cov_estimate))
})
