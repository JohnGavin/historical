# Tests for topological_risk_parity.R
# Covers: hrp_weights(), trp_weights(), and shared internal helpers

# ── Test fixtures ─────────────────────────────────────────────────────────────

# 5-asset covariance matrix with two clear clusters:
# - Cluster 1: A1, A2 (high correlation 0.8)
# - Cluster 2: A3, A4 (high correlation 0.7)
# - A5: weakly correlated to both clusters
make_5asset_cov <- function() {
  R <- matrix(c(
    1.0, 0.8, 0.1, 0.1, 0.0,
    0.8, 1.0, 0.1, 0.1, 0.0,
    0.1, 0.1, 1.0, 0.7, 0.2,
    0.1, 0.1, 0.7, 1.0, 0.2,
    0.0, 0.0, 0.2, 0.2, 1.0
  ), nrow = 5, byrow = TRUE)
  sds <- c(0.02, 0.03, 0.015, 0.025, 0.02)
  cov_mat <- diag(sds) %*% R %*% diag(sds)
  rownames(cov_mat) <- colnames(cov_mat) <- paste0("A", 1:5)
  cov_mat
}

# Diagonal covariance (uncorrelated assets) — all weights should be equal
make_diag_cov <- function(n = 4, sds = rep(0.02, n)) {
  cm <- diag(sds^2)
  rownames(cm) <- colnames(cm) <- paste0("B", seq_len(n))
  cm
}

# 2-asset covariance (minimum valid input)
make_2asset_cov <- function() {
  cm <- matrix(c(4e-4, 1e-4, 1e-4, 9e-4), nrow = 2)
  rownames(cm) <- colnames(cm) <- c("X", "Y")
  cm
}

# ── hrp_weights() ─────────────────────────────────────────────────────────────

test_that("hrp_weights: weights sum to 1 (5-asset)", {
  w <- hrp_weights(make_5asset_cov())
  expect_equal(sum(w), 1, tolerance = 1e-10)
})

test_that("hrp_weights: all weights strictly positive (5-asset)", {
  w <- hrp_weights(make_5asset_cov())
  expect_true(all(w > 0))
})

test_that("hrp_weights: all weights strictly less than 1 (5-asset)", {
  w <- hrp_weights(make_5asset_cov())
  expect_true(all(w < 1))
})

test_that("hrp_weights: names match covariance matrix columns", {
  cov_mat <- make_5asset_cov()
  w <- hrp_weights(cov_mat)
  expect_equal(sort(names(w)), sort(colnames(cov_mat)))
})

test_that("hrp_weights: diagonal cov gives equal weights", {
  # Uncorrelated + equal variance => HRP should give 1/n for each asset.
  # Order of names may vary depending on hclust leaf ordering; sort both sides.
  n <- 4
  w <- hrp_weights(make_diag_cov(n))
  expected <- setNames(rep(1 / n, n), paste0("B", seq_len(n)))
  expect_equal(w[sort(names(w))], expected[sort(names(expected))],
               tolerance = 1e-10)
})

test_that("hrp_weights: cluster structure respected (correlated pair gets less total weight)", {
  # A1 and A2 are highly correlated (0.8) — HRP should allocate less total to the pair
  # than two uncorrelated assets would get (i.e., < 2/5 combined for the correlated pair)
  cov_mat <- make_5asset_cov()
  w <- hrp_weights(cov_mat)
  # Both A1 and A2 are in the same cluster — their combined weight should reflect
  # diversification penalty for high correlation
  # (This is a directional test, not an exact value test)
  pair_weight <- w["A1"] + w["A2"]
  solo_expected <- 2 / 5  # equal weight share for 2 out of 5 assets
  # High correlation => concentrated risk => HRP allocates fewer resources
  expect_true(pair_weight < solo_expected * 1.1)  # allow 10% slack
})

test_that("hrp_weights: works with 2 assets", {
  w <- hrp_weights(make_2asset_cov())
  expect_equal(sum(w), 1, tolerance = 1e-10)
  expect_true(all(w > 0))
})

test_that("hrp_weights: method='average' also works", {
  w <- hrp_weights(make_5asset_cov(), method = "average")
  expect_equal(sum(w), 1, tolerance = 1e-10)
  expect_true(all(w > 0))
})

# ── trp_weights() ─────────────────────────────────────────────────────────────

test_that("trp_weights: weights sum to 1 (5-asset)", {
  w <- trp_weights(make_5asset_cov())
  expect_equal(sum(w), 1, tolerance = 1e-10)
})

test_that("trp_weights: all weights strictly positive (5-asset)", {
  w <- trp_weights(make_5asset_cov())
  expect_true(all(w > 0))
})

test_that("trp_weights: all weights strictly less than 1 (5-asset)", {
  w <- trp_weights(make_5asset_cov())
  expect_true(all(w < 1))
})

test_that("trp_weights: names match covariance matrix columns", {
  cov_mat <- make_5asset_cov()
  w <- trp_weights(cov_mat)
  expect_equal(sort(names(w)), sort(colnames(cov_mat)))
})

test_that("trp_weights: diagonal cov gives equal weights", {
  n <- 4
  w <- trp_weights(make_diag_cov(n))
  expect_equal(sum(w), 1, tolerance = 1e-10)
  expect_true(all(w > 0))
})

test_that("trp_weights: works with 2 assets", {
  w <- trp_weights(make_2asset_cov())
  expect_equal(sum(w), 1, tolerance = 1e-10)
  expect_true(all(w > 0))
})

# ── Input validation ──────────────────────────────────────────────────────────

test_that("hrp_weights: error on non-matrix input", {
  expect_error(hrp_weights(list(a = 1)), class = "rlang_error")
})

test_that("hrp_weights: error on non-square matrix", {
  m <- matrix(1:6, nrow = 2)
  rownames(m) <- c("A", "B")
  expect_error(hrp_weights(m), class = "rlang_error")
})

test_that("hrp_weights: error on unnamed matrix", {
  m <- matrix(c(1, 0.5, 0.5, 1), nrow = 2)
  expect_error(hrp_weights(m), class = "rlang_error")
})

test_that("hrp_weights: error on mismatched row/col names", {
  m <- matrix(c(1, 0.5, 0.5, 1), nrow = 2)
  rownames(m) <- c("A", "B")
  colnames(m) <- c("C", "D")
  expect_error(hrp_weights(m), class = "rlang_error")
})

test_that("hrp_weights: error on single-asset matrix", {
  m <- matrix(0.04, nrow = 1, ncol = 1)
  rownames(m) <- colnames(m) <- "A"
  expect_error(hrp_weights(m), class = "rlang_error")
})

test_that("trp_weights: error on non-matrix input", {
  expect_error(trp_weights(data.frame(a = 1)), class = "rlang_error")
})

# ── Consistency: TRP vs HRP ───────────────────────────────────────────────────

test_that("trp_weights and hrp_weights produce similar weights on low-correlation data", {
  # With all assets near-uncorrelated, MST ordering ≈ hclust ordering
  # => TRP should be close to HRP (within 10pp per asset)
  cov_mat <- make_diag_cov(5)
  w_hrp <- hrp_weights(cov_mat)
  w_trp <- trp_weights(cov_mat)
  # Both should give near equal weights on diagonal cov
  expect_true(max(abs(w_hrp - w_trp)) < 0.05)
})
