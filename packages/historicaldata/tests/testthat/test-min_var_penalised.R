# Tests for hd_min_var_weights_penalised() — penalised GMV (#507 Phase 3)
#
# Test structure:
#   1.  lambda=0, lambda_turn=0 → identical to hd_min_var_weights() (normalize=TRUE)
#   2.  lambda=0, lambda_turn=0 → identical to hd_min_var_weights() (normalize=FALSE)
#   3.  Weights sum to 1 when normalize = TRUE
#   4.  Ridge penalty lowers condition number
#   5.  Turnover penalty pulls weights toward w_prev (turnover decreases as lambda_turnover increases)
#   6.  Names preserved from Sigma dimnames
#   7.  Turnover attribute is sum(|w - w_prev|)
#   8.  Validation: non-square Sigma (snapshot)
#   9.  Validation: negative lambda_ridge (snapshot)
#   10. Validation: negative lambda_turnover (snapshot)
#   11. Validation: lambda_turnover > 0 with w_prev = NULL (snapshot)
#   12. Validation: wrong-length w_prev (snapshot)
#   13. Function signature stability (snapshot)
#
# Snapshot count: 6 snapshots (5 error + 1 args) out of 13 blocks
# => ratio 6/13 >= 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers -------------------------------------------

.make_3asset_sigma_pen <- function() {
  matrix(c(0.04, 0.01, 0.00,
           0.01, 0.09, 0.02,
           0.00, 0.02, 0.16),
         nrow = 3, ncol = 3,
         dimnames = list(c("A", "B", "C"), c("A", "B", "C")))
}

.make_4asset_diag_pen <- function() {
  vars <- c(0.04, 0.09, 0.16, 0.25)
  S    <- diag(vars)
  dimnames(S) <- list(c("A", "B", "C", "D"), c("A", "B", "C", "D"))
  S
}

# ---- Test 1: lambda=0, lambda_turn=0 → same as hd_min_var_weights (norm=TRUE) ----
test_that("lambda=0, lambda_turn=0 matches hd_min_var_weights() with normalize=TRUE", {
  S    <- .make_3asset_sigma_pen()
  w_pl <- hd_min_var_weights_penalised(S, lambda_ridge = 0, lambda_turnover = 0,
                                        normalize = TRUE)
  w_gm <- hd_min_var_weights(S, normalize = TRUE)
  expect_equal(as.numeric(w_pl), as.numeric(w_gm), tolerance = 1e-12)
  expect_equal(sum(w_pl), 1, tolerance = 1e-12)
})

# ---- Test 2: lambda=0, lambda_turn=0 → same as hd_min_var_weights (norm=FALSE) ---
test_that("lambda=0, lambda_turn=0 matches hd_min_var_weights() with normalize=FALSE", {
  S    <- .make_3asset_sigma_pen()
  w_pl <- hd_min_var_weights_penalised(S, lambda_ridge = 0, lambda_turnover = 0,
                                        normalize = FALSE)
  w_gm <- hd_min_var_weights(S, normalize = FALSE)
  expect_equal(as.numeric(w_pl), as.numeric(w_gm), tolerance = 1e-12)
})

# ---- Test 3: Weights sum to 1 when normalize = TRUE -----------------------
test_that("weights sum to exactly 1 when normalize = TRUE (ridge penalty)", {
  S <- .make_4asset_diag_pen()
  w <- hd_min_var_weights_penalised(S, lambda_ridge = 0.05, normalize = TRUE)
  expect_equal(sum(w), 1, tolerance = 1e-12)
  expect_length(w, 4L)
})

test_that("weights sum to exactly 1 when normalize = TRUE (turnover penalty)", {
  S      <- .make_3asset_sigma_pen()
  w_prev <- c(A = 0.5, B = 0.3, C = 0.2)
  w      <- hd_min_var_weights_penalised(S, w_prev = w_prev,
                                          lambda_turnover = 0.1, normalize = TRUE)
  expect_equal(sum(w), 1, tolerance = 1e-12)
})

# ---- Test 4: Ridge penalty lowers condition number -------------------------
test_that("lambda_ridge > 0 lowers condition number relative to lambda_ridge = 0", {
  S    <- .make_4asset_diag_pen()
  w0   <- hd_min_var_weights_penalised(S, lambda_ridge = 0)
  w_r  <- hd_min_var_weights_penalised(S, lambda_ridge = 0.1)
  kappa0 <- attr(w0,  "condition_number")
  kappa_r <- attr(w_r, "condition_number")
  expect_lt(kappa_r, kappa0)
  # Both condition numbers must be finite and positive
  expect_true(is.finite(kappa0))
  expect_true(is.finite(kappa_r))
  expect_gt(kappa_r, 0)
})

# ---- Test 5: Turnover penalty pulls weights toward w_prev -----------------
test_that("higher lambda_turnover strictly reduces turnover toward w_prev", {
  S      <- .make_3asset_sigma_pen()
  w_prev <- c(A = 0.5, B = 0.3, C = 0.2)

  w_small <- hd_min_var_weights_penalised(S, w_prev = w_prev,
                                           lambda_turnover = 0.01)
  w_large <- hd_min_var_weights_penalised(S, w_prev = w_prev,
                                           lambda_turnover = 5.0)

  turn_small <- attr(w_small, "turnover")
  turn_large <- attr(w_large, "turnover")

  # Larger penalty → weights closer to w_prev → smaller turnover
  expect_lt(turn_large, turn_small)
  expect_true(is.finite(turn_small))
  expect_true(is.finite(turn_large))
})

# ---- Test 6: Names preserved -------------------------------------------
test_that("names of returned weights match rownames(Sigma)", {
  S <- .make_3asset_sigma_pen()
  w <- hd_min_var_weights_penalised(S)
  expect_equal(names(w), rownames(S))
  expect_equal(names(w), c("A", "B", "C"))
})

test_that("returns NULL names when Sigma has no dimnames", {
  S <- matrix(c(1, 0.2, 0.2, 1), 2, 2)
  w <- hd_min_var_weights_penalised(S)
  expect_null(names(w))
})

# ---- Test 7: Turnover attribute ------------------------------------------
test_that("turnover attribute equals sum(|w - w_prev|) when w_prev supplied", {
  S      <- .make_3asset_sigma_pen()
  w_prev <- c(A = 0.5, B = 0.3, C = 0.2)
  w      <- hd_min_var_weights_penalised(S, w_prev = w_prev,
                                          lambda_turnover = 0.2)
  expected_turnover <- sum(abs(w - w_prev))
  expect_equal(attr(w, "turnover"), expected_turnover, tolerance = 1e-12)
  # Turnover is non-negative
  expect_gte(attr(w, "turnover"), 0)
})

test_that("turnover attribute is absent when w_prev is NULL", {
  S <- .make_3asset_sigma_pen()
  w <- hd_min_var_weights_penalised(S, lambda_ridge = 0.01)
  expect_null(attr(w, "turnover"))
})

# ---- Test 8: non-square Sigma aborts (snapshot) -------------------------
test_that("non-square Sigma aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights_penalised(matrix(1:6, 2, 3))
  )
})

# ---- Test 9: negative lambda_ridge aborts (snapshot) --------------------
test_that("negative lambda_ridge aborts with informative error", {
  S <- .make_3asset_sigma_pen()
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights_penalised(S, lambda_ridge = -0.1)
  )
})

# ---- Test 10: negative lambda_turnover aborts (snapshot) ----------------
test_that("negative lambda_turnover aborts with informative error", {
  S <- .make_3asset_sigma_pen()
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights_penalised(S, lambda_turnover = -1)
  )
})

# ---- Test 11: lambda_turnover > 0 with w_prev = NULL aborts (snapshot) --
test_that("lambda_turnover > 0 without w_prev aborts with informative error", {
  S <- .make_3asset_sigma_pen()
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights_penalised(S, lambda_turnover = 0.5)
  )
})

# ---- Test 12: wrong-length w_prev aborts (snapshot) ---------------------
test_that("w_prev of wrong length aborts with informative error", {
  S <- .make_3asset_sigma_pen()
  expect_snapshot(
    error = TRUE,
    hd_min_var_weights_penalised(S, w_prev = c(0.5, 0.5),
                                  lambda_turnover = 0.1)
  )
})

# ---- Test 13: function signature stability (snapshot) -------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_min_var_weights_penalised))
})
