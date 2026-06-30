# Tests for hd_returns_shrink() — expected-return shrinkage estimator (#507 Phase 1)
#
# Test structure:
#   1.  grand_mean: target is mean(mu) replicated across all assets
#   2.  grand_mean: result is a convex combination of mu and target
#   3.  grand_mean: intensity attribute is in [0, 1]
#   4.  grand_mean: data-driven intensity is used when n_obs is supplied
#   5.  Degenerate: all mu equal → output == mu for grand_mean
#   6.  james_stein: shrinks toward minimum-variance weighted mean
#   7.  james_stein: intensity (phi) is in [0, 1]
#   8.  james_stein: result is a convex combination of mu and target
#   9.  equilibrium: target equals lambda * sigma %*% w_mkt
#   10. equilibrium: result is a convex combination of mu and target
#   11. Names are preserved for all three methods
#   12. Error snapshot: sigma missing for james_stein
#   13. Error snapshot: n_obs missing for james_stein
#   14. Error snapshot: required args missing for equilibrium
#   15. Error snapshot: sigma wrong size
#   16. Error snapshot: risk_aversion <= 0
#   17. Function signature stability snapshot
#
# Snapshot count: 6 snapshots (errors x5 + args x1) out of 17 blocks
# => ratio 6/17 ≈ 35% > 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers -------------------------------------------

# 5-asset positive-definite covariance matrix (Wishart draw, fixed seed)
.make_sigma_5 <- function(seed = 42L) {
  set.seed(seed)
  X  <- matrix(stats::rnorm(60L * 5L), nrow = 60L, ncol = 5L)
  S  <- stats::cov(X)
  dimnames(S) <- list(paste0("A", seq_len(5L)), paste0("A", seq_len(5L)))
  S
}

# Named expected-return vector for 5 assets
.make_mu_5 <- function() {
  mu <- c(0.05, 0.08, 0.12, 0.07, 0.10)
  names(mu) <- paste0("A", seq_len(5L))
  mu
}

# Market-cap weights for 5 assets (sum to 1)
.make_wmkt_5 <- function() {
  w <- c(0.30, 0.20, 0.25, 0.15, 0.10)
  names(w) <- paste0("A", seq_len(5L))
  w
}

# ---- Test 1: grand_mean target is mean(mu) replicated ----------------
test_that("grand_mean target equals mean(mu) for every element", {
  mu  <- .make_mu_5()
  out <- hd_returns_shrink(mu, method = "grand_mean", intensity = 0.3)

  target <- attr(out, "target")
  expect_length(target, length(mu))
  expect_equal(unique(target), mean(mu),
    label = "all target elements equal the grand mean")
})

# ---- Test 2: grand_mean result is a convex combination ---------------
test_that("grand_mean result lies between mu and target element-wise", {
  mu  <- .make_mu_5()
  out <- hd_returns_shrink(mu, method = "grand_mean", intensity = 0.4)
  tgt <- attr(out, "target")

  lo <- pmin(mu, tgt)
  hi <- pmax(mu, tgt)
  expect_true(all(out >= lo - 1e-12 & out <= hi + 1e-12),
    label = "result in [min(mu,tgt), max(mu,tgt)] element-wise")
})

# ---- Test 3: grand_mean intensity attribute is in [0, 1] --------------
test_that("grand_mean intensity attribute is in [0, 1]", {
  mu  <- .make_mu_5()
  out <- hd_returns_shrink(mu, method = "grand_mean", intensity = 0.6)
  phi <- attr(out, "intensity")

  expect_true(is.numeric(phi) && length(phi) == 1L)
  expect_gte(phi, 0)
  expect_lte(phi, 1)
})

# ---- Test 4: grand_mean uses data-driven delta when n_obs supplied ----
test_that("grand_mean derives intensity from n_obs when intensity = NULL", {
  mu  <- .make_mu_5()

  # With n_obs — intensity should be data-driven, still in [0, 1]
  out_n <- hd_returns_shrink(mu, method = "grand_mean", n_obs = 120L)
  phi_n <- attr(out_n, "intensity")
  expect_gte(phi_n, 0)
  expect_lte(phi_n, 1)

  # Without n_obs — uses documented default 0.5
  out_def <- hd_returns_shrink(mu, method = "grand_mean")
  expect_equal(attr(out_def, "intensity"), 0.5,
    label = "default intensity is 0.5")
})

# ---- Test 5: degenerate case — all mu equal → output equals mu --------
test_that("when all mu elements are equal, grand_mean output equals mu", {
  mu_flat <- rep(0.08, 5L)
  names(mu_flat) <- paste0("A", seq_len(5L))

  out <- hd_returns_shrink(mu_flat, method = "grand_mean", intensity = 0.7)
  expect_equal(as.numeric(out), as.numeric(mu_flat), tolerance = 1e-12,
    label = "flat mu: output unchanged (target == mu)")
})

# ---- Test 6: james_stein shrinks toward minimum-variance mean --------
test_that("james_stein target equals the minimum-variance weighted mean", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  n_obs <- 120L

  out <- hd_returns_shrink(mu, method = "james_stein",
                           sigma = sigma, n_obs = n_obs)

  # Recompute the JS target from first principles
  ones     <- rep(1, length(mu))
  Sigma_inv <- solve(sigma)
  mu_0     <- as.numeric(t(ones) %*% Sigma_inv %*% mu) /
               as.numeric(t(ones) %*% Sigma_inv %*% ones)
  expected_target <- mu_0 * ones
  names(expected_target) <- names(mu)

  tgt <- attr(out, "target")
  expect_equal(tgt, expected_target, tolerance = 1e-10,
    label = "JS target equals min-var weighted mean of mu")
})

# ---- Test 7: james_stein intensity (phi) is in [0, 1] ----------------
test_that("james_stein intensity (phi) is in [0, 1]", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  n_obs <- 120L

  out <- hd_returns_shrink(mu, method = "james_stein",
                           sigma = sigma, n_obs = n_obs)
  phi <- attr(out, "intensity")

  expect_true(is.numeric(phi) && length(phi) == 1L)
  expect_gte(phi, 0)
  expect_lte(phi, 1)
})

# ---- Test 8: james_stein result is a convex combination ---------------
test_that("james_stein result lies between mu and target element-wise", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  n_obs <- 60L

  out <- hd_returns_shrink(mu, method = "james_stein",
                           sigma = sigma, n_obs = n_obs)
  tgt <- attr(out, "target")

  lo <- pmin(mu, tgt)
  hi <- pmax(mu, tgt)
  expect_true(all(out >= lo - 1e-12 & out <= hi + 1e-12),
    label = "JS result in [min(mu,tgt), max(mu,tgt)] element-wise")
})

# ---- Test 9: equilibrium target equals lambda * sigma %*% w_mkt -------
test_that("equilibrium target equals risk_aversion * sigma %*% w_mkt", {
  mu            <- .make_mu_5()
  sigma         <- .make_sigma_5()
  w_mkt         <- .make_wmkt_5()
  risk_aversion <- 2.5

  out <- hd_returns_shrink(mu, method = "equilibrium",
                           sigma = sigma, w_mkt = w_mkt,
                           risk_aversion = risk_aversion,
                           intensity = 0.5)

  expected_target <- as.numeric(risk_aversion * sigma %*% w_mkt)
  names(expected_target) <- names(mu)

  tgt <- attr(out, "target")
  expect_equal(tgt, expected_target, tolerance = 1e-12,
    label = "equilibrium target = lambda * Sigma * w_mkt")
})

# ---- Test 10: equilibrium result is a convex combination --------------
test_that("equilibrium result lies between mu and target element-wise", {
  mu            <- .make_mu_5()
  sigma         <- .make_sigma_5()
  w_mkt         <- .make_wmkt_5()
  risk_aversion <- 2.0

  out <- hd_returns_shrink(mu, method = "equilibrium",
                           sigma = sigma, w_mkt = w_mkt,
                           risk_aversion = risk_aversion,
                           intensity = 0.4)
  tgt <- attr(out, "target")

  lo <- pmin(mu, tgt)
  hi <- pmax(mu, tgt)
  expect_true(all(out >= lo - 1e-12 & out <= hi + 1e-12),
    label = "equilibrium result in [min(mu,tgt), max(mu,tgt)] element-wise")
})

# ---- Test 11: names are preserved for all methods ----------------------
test_that("names of mu are preserved on the output for all methods", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  w_mkt <- .make_wmkt_5()
  nms   <- names(mu)

  out_gm <- hd_returns_shrink(mu, method = "grand_mean", intensity = 0.3)
  expect_equal(names(out_gm), nms, label = "grand_mean: names preserved")

  out_js <- hd_returns_shrink(mu, method = "james_stein",
                              sigma = sigma, n_obs = 100L)
  expect_equal(names(out_js), nms, label = "james_stein: names preserved")

  out_eq <- hd_returns_shrink(mu, method = "equilibrium",
                              sigma = sigma, w_mkt = w_mkt,
                              risk_aversion = 2.0, intensity = 0.5)
  expect_equal(names(out_eq), nms, label = "equilibrium: names preserved")
})

# ---- Test 12: Error — sigma missing for james_stein -------------------
test_that("james_stein without sigma aborts with informative error", {
  mu <- .make_mu_5()
  expect_snapshot(
    error = TRUE,
    hd_returns_shrink(mu, method = "james_stein", n_obs = 100L)
  )
})

# ---- Test 13: Error — n_obs missing for james_stein -------------------
test_that("james_stein without n_obs aborts with informative error", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  expect_snapshot(
    error = TRUE,
    hd_returns_shrink(mu, method = "james_stein", sigma = sigma)
  )
})

# ---- Test 14: Error — required args missing for equilibrium -----------
test_that("equilibrium without w_mkt aborts with informative error", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  expect_snapshot(
    error = TRUE,
    hd_returns_shrink(mu, method = "equilibrium",
                      sigma = sigma, risk_aversion = 2.0)
  )
})

# ---- Test 15: Error — sigma wrong size --------------------------------
test_that("sigma with wrong dimensions aborts with informative error", {
  mu       <- .make_mu_5()
  # p=5 but sigma is 3x3 — mismatch
  sigma_3x3 <- diag(3)
  dimnames(sigma_3x3) <- list(c("X","Y","Z"), c("X","Y","Z"))
  expect_snapshot(
    error = TRUE,
    hd_returns_shrink(mu, method = "james_stein",
                      sigma = sigma_3x3, n_obs = 100L)
  )
})

# ---- Test 16: Error — risk_aversion <= 0 ------------------------------
test_that("risk_aversion <= 0 aborts with informative error", {
  mu    <- .make_mu_5()
  sigma <- .make_sigma_5()
  w_mkt <- .make_wmkt_5()
  expect_snapshot(
    error = TRUE,
    hd_returns_shrink(mu, method = "equilibrium",
                      sigma = sigma, w_mkt = w_mkt,
                      risk_aversion = -1.0, intensity = 0.5)
  )
})

# ---- Test 17: function signature stability ----------------------------
test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_returns_shrink))
})
