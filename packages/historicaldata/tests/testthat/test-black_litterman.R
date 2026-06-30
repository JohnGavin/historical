# Tests for hd_black_litterman() — Black-Litterman posterior expected returns
# (#507 Phase 2)
#
# Test structure:
#   1.  No-views collapse: P=NULL ⇒ posterior_mu == prior Π exactly
#   2.  No-views: posterior_sigma == (1+tau)*sigma
#   3.  Single view equal to prior (diagonal sigma) → posterior_mu == prior_mu
#   4.  Bullish view pushes posterior_mu[i] above Π[i]
#   5.  Bearish view pushes posterior_mu[i] below Π[i]
#   6.  Shapes: posterior_mu length N with names; posterior_sigma N×N symmetric
#   7.  Default Ω = diag(P (τΣ) Pᵀ) verified against hand-computed example
#   8.  Default risk_aversion (2.5) is used when risk_aversion = NULL
#   9.  prior_mu attribute matches the CAPM reverse-optimisation formula
#   10. Error snapshot: non-square sigma
#   11. Error snapshot: w_mkt length mismatch
#   12. Error snapshot: P ncol != N
#   13. Error snapshot: Q length != nrow(P)
#   14. Error snapshot: tau <= 0
#   15. Error snapshot: risk_aversion <= 0
#   16. Error snapshot: omega wrong size
#   17. Function signature stability snapshot
#
# Snapshot count: 8 snapshots (errors × 7 + args × 1) out of 17 blocks
# => ratio 8/17 ≈ 47% > 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers -------------------------------------------

# 5-asset positive-definite covariance matrix (Wishart draw, fixed seed)
.make_sigma_5_bl <- function(seed = 42L) {
  set.seed(seed)
  X  <- matrix(stats::rnorm(80L * 5L), nrow = 80L, ncol = 5L)
  S  <- stats::cov(X)
  dimnames(S) <- list(paste0("A", seq_len(5L)), paste0("A", seq_len(5L)))
  S
}

# Market-cap weights for 5 assets (sum to 1)
.make_wmkt_5_bl <- function() {
  w <- c(A1 = 0.30, A2 = 0.20, A3 = 0.25, A4 = 0.15, A5 = 0.10)
  w
}

# Simple 3-asset diagonal covariance for hand-computed tests
.make_sigma_diag3 <- function() {
  S <- diag(c(0.04, 0.09, 0.01))
  dimnames(S) <- list(c("X", "Y", "Z"), c("X", "Y", "Z"))
  S
}

.make_wmkt_diag3 <- function() {
  c(X = 1/3, Y = 1/3, Z = 1/3)
}

# ---- Test 1: No-views collapse — posterior_mu == prior Π exactly ---------
test_that("P=NULL: posterior_mu collapses exactly to equilibrium prior Π", {
  sigma         <- .make_sigma_5_bl()
  w_mkt         <- .make_wmkt_5_bl()
  risk_aversion <- 2.5

  out    <- hd_black_litterman(sigma, w_mkt, risk_aversion = risk_aversion)
  Pi_exp <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi_exp) <- paste0("A", seq_len(5L))

  expect_equal(out$posterior_mu, Pi_exp, tolerance = 1e-12,
    label = "posterior_mu == Π when no views given")
})

# ---- Test 2: No-views — posterior_sigma == (1+tau)*sigma -----------------
test_that("P=NULL: posterior_sigma equals (1+tau)*sigma", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  tau   <- 0.05

  out      <- hd_black_litterman(sigma, w_mkt, tau = tau,
                                 risk_aversion = 2.5)
  expected <- (1 + tau) * sigma
  dimnames(expected) <- dimnames(sigma)

  expect_equal(out$posterior_sigma, expected, tolerance = 1e-12,
    label = "posterior_sigma == (1+tau)*sigma in no-views case")
})

# ---- Test 3: Single view equal to prior → posterior_mu == Π -------------
# With diagonal sigma, a single absolute view Q[1] = Π[1] using default Ω
# leaves posterior_mu identical to Π (provable algebraically for diagonal Σ).
test_that("single view equal to prior leaves posterior_mu unchanged (diagonal sigma)", {
  sigma         <- .make_sigma_diag3()
  w_mkt         <- .make_wmkt_diag3()
  risk_aversion <- 2.0
  tau           <- 0.05

  Pi <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi) <- c("X", "Y", "Z")

  # One view: view on asset X, view return = Π["X"]
  P <- matrix(c(1, 0, 0), nrow = 1L, ncol = 3L)
  colnames(P) <- c("X", "Y", "Z")
  Q <- Pi["X"]

  out <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                            tau = tau, risk_aversion = risk_aversion)

  expect_equal(out$posterior_mu, Pi, tolerance = 1e-10,
    label = "view equal to prior: posterior unchanged for diagonal sigma")
})

# ---- Test 4: Bullish view pushes posterior_mu[i] above Π[i] -------------
test_that("bullish view (Q > Π[i]) increases posterior_mu[i] above prior", {
  sigma         <- .make_sigma_5_bl()
  w_mkt         <- .make_wmkt_5_bl()
  risk_aversion <- 2.5
  tau           <- 0.05

  Pi <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi) <- paste0("A", seq_len(5L))

  # View on asset A1: bullish (50 bps above prior)
  P <- matrix(c(1, 0, 0, 0, 0), nrow = 1L, ncol = 5L)
  colnames(P) <- paste0("A", seq_len(5L))
  Q <- Pi["A1"] + 0.005

  out <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                            tau = tau, risk_aversion = risk_aversion)

  expect_gt(out$posterior_mu["A1"], Pi["A1"],
    label = "bullish view increases posterior_mu for the target asset")
})

# ---- Test 5: Bearish view pushes posterior_mu[i] below Π[i] -------------
test_that("bearish view (Q < Π[i]) decreases posterior_mu[i] below prior", {
  sigma         <- .make_sigma_5_bl()
  w_mkt         <- .make_wmkt_5_bl()
  risk_aversion <- 2.5
  tau           <- 0.05

  Pi <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi) <- paste0("A", seq_len(5L))

  # View on asset A2: bearish (50 bps below prior)
  P <- matrix(c(0, 1, 0, 0, 0), nrow = 1L, ncol = 5L)
  colnames(P) <- paste0("A", seq_len(5L))
  Q <- Pi["A2"] - 0.005

  out <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                            tau = tau, risk_aversion = risk_aversion)

  expect_lt(out$posterior_mu["A2"], Pi["A2"],
    label = "bearish view decreases posterior_mu for the target asset")
})

# ---- Test 6: Shapes — posterior_mu has length N; posterior_sigma is N×N sym ---
test_that("output shapes are correct: length-N posterior_mu, N×N symmetric sigma", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()

  P <- matrix(c(1, -1, 0, 0, 0,
                0,  0, 1,  0, -1), nrow = 2L, ncol = 5L, byrow = TRUE)
  colnames(P) <- paste0("A", seq_len(5L))
  Q <- c(0.02, 0.01)

  out <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q, risk_aversion = 2.5)

  expect_length(out$posterior_mu, 5L)
  expect_equal(names(out$posterior_mu), paste0("A", seq_len(5L)))

  expect_equal(dim(out$posterior_sigma), c(5L, 5L))
  # Check symmetry
  expect_equal(out$posterior_sigma, t(out$posterior_sigma), tolerance = 1e-12,
    label = "posterior_sigma is symmetric")
})

# ---- Test 7: Default Ω = diag(P (τΣ) Pᵀ) matches explicit omega call ----
test_that("default omega = diag(P tau_sigma t(P)) agrees with explicit supply", {
  sigma <- .make_sigma_diag3()
  w_mkt <- .make_wmkt_diag3()
  tau   <- 0.05
  risk_aversion <- 2.5

  # Two views, each selecting one asset
  P <- matrix(c(1, 0, 0,
                0, 1, 0), nrow = 2L, ncol = 3L, byrow = TRUE)
  colnames(P) <- c("X", "Y", "Z")
  Q <- c(0.05, 0.08)

  # Compute the expected default Ω by hand:
  # sigma is diag(0.04, 0.09, 0.01), tau=0.05
  # tau_sigma = diag(0.002, 0.0045, 0.0005)
  # P %*% tau_sigma %*% t(P) = diag(0.002, 0.0045)
  omega_expected <- diag(c(0.002, 0.0045))

  out_default  <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                                     tau = tau, risk_aversion = risk_aversion)
  out_explicit <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                                     tau = tau, omega = omega_expected,
                                     risk_aversion = risk_aversion)

  expect_equal(out_default$posterior_mu, out_explicit$posterior_mu,
    tolerance = 1e-12,
    label = "default omega matches hand-computed diag(P tau_sigma t(P))")
  expect_equal(out_default$posterior_sigma, out_explicit$posterior_sigma,
    tolerance = 1e-12,
    label = "posterior_sigma same for default and explicit omega")
})

# ---- Test 8: Default risk_aversion = 2.5 when NULL ----------------------
test_that("risk_aversion = NULL uses documented default of 2.5", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()

  out_null    <- hd_black_litterman(sigma, w_mkt, risk_aversion = NULL)
  out_explicit <- hd_black_litterman(sigma, w_mkt, risk_aversion = 2.5)

  expect_equal(out_null$posterior_mu, out_explicit$posterior_mu,
    tolerance = 1e-12,
    label = "NULL risk_aversion behaves identically to 2.5")
})

# ---- Test 9: prior_mu attribute matches CAPM reverse-optimisation formula ---
test_that("prior_mu == risk_aversion * sigma %*% w_mkt", {
  sigma         <- .make_sigma_5_bl()
  w_mkt         <- .make_wmkt_5_bl()
  risk_aversion <- 3.0
  tau           <- 0.07

  P <- matrix(c(1, 0, 0, 0, 0), nrow = 1L, ncol = 5L)
  colnames(P) <- paste0("A", seq_len(5L))
  Q <- c(0.03)

  out    <- hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                               tau = tau, risk_aversion = risk_aversion)
  Pi_exp <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(Pi_exp) <- paste0("A", seq_len(5L))

  expect_equal(out$prior_mu, Pi_exp, tolerance = 1e-12,
    label = "prior_mu == lambda * sigma %*% w_mkt")
})

# ---- Test 10: Error — non-square sigma -----------------------------------
test_that("non-square sigma aborts with informative error", {
  w_mkt <- c(A1 = 0.5, A2 = 0.5)
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(matrix(1:6, nrow = 2L, ncol = 3L), w_mkt)
  )
})

# ---- Test 11: Error — w_mkt length mismatch ------------------------------
test_that("w_mkt length != ncol(sigma) aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt = c(A1 = 0.5, A2 = 0.5),
                       risk_aversion = 2.5)
  )
})

# ---- Test 12: Error — P ncol != N ----------------------------------------
test_that("P with wrong number of columns aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  # P has 3 columns but N = 5
  P_bad <- matrix(c(1, 0, 0), nrow = 1L, ncol = 3L)
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt, P = P_bad, Q = 0.03,
                       risk_aversion = 2.5)
  )
})

# ---- Test 13: Error — Q length != nrow(P) --------------------------------
test_that("Q length != nrow(P) aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  P     <- matrix(c(1, 0, 0, 0, 0), nrow = 1L, ncol = 5L)
  # Q has 2 elements but P has 1 row
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt, P = P, Q = c(0.03, 0.05),
                       risk_aversion = 2.5)
  )
})

# ---- Test 14: Error — tau <= 0 -------------------------------------------
test_that("tau <= 0 aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt, tau = -0.01, risk_aversion = 2.5)
  )
})

# ---- Test 15: Error — risk_aversion <= 0 ---------------------------------
test_that("risk_aversion <= 0 aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt, risk_aversion = 0)
  )
})

# ---- Test 16: Error — omega wrong dimensions ----------------------------
test_that("omega with wrong dimensions aborts with informative error", {
  sigma <- .make_sigma_5_bl()
  w_mkt <- .make_wmkt_5_bl()
  P     <- matrix(c(1, 0, 0, 0, 0), nrow = 1L, ncol = 5L)
  Q     <- 0.03
  # omega should be 1×1 for 1 view, but we supply 2×2
  omega_bad <- diag(2)
  expect_snapshot(
    error = TRUE,
    hd_black_litterman(sigma, w_mkt, P = P, Q = Q,
                       omega = omega_bad, risk_aversion = 2.5)
  )
})

# ---- Test 17: function signature stability --------------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_black_litterman))
})
