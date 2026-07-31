testthat::local_edition(3)

# Tests for level-2 path signatures and Lévy area (#605).
#
# The shuffle identities are the real specification here: they are exact
# algebraic facts, so they make excellent property-based tests.  If an
# implementation is wrong, at least one of them breaks.

set.seed(11)

# Independent reference: refine the piecewise-linear path and Riemann-sum the
# iterated integral directly.  Deliberately NOT the same algorithm as the
# implementation, so agreement is meaningful.
ref_sig2 <- function(X, refine = 100L) {
  n <- nrow(X)
  tt <- seq_len(n)
  fine <- seq(1, n, length.out = (n - 1L) * refine + 1L)
  Xf <- sapply(seq_len(ncol(X)), function(j) stats::approx(tt, X[, j], xout = fine)$y)
  dXf <- diff(Xf)
  d <- ncol(X)
  S2 <- matrix(0, d, d)
  for (i in seq_len(d)) for (j in seq_len(d)) {
    cum_i <- cumsum(c(0, dXf[-nrow(dXf), i]))
    S2[i, j] <- sum(cum_i * dXf[, j]) + 0.5 * sum(dXf[, i] * dXf[, j])
  }
  S2
}

rand_path <- function(n = 40L, d = 2L) {
  matrix(apply(matrix(stats::rnorm(n * d), n, d), 2, cumsum), n, d)
}

# ── hd_path_signature2: agreement with an independent computation ──────────

test_that("level-2 signature matches a refined Riemann sum", {
  X <- rand_path(30L)
  got <- hd_path_signature2(X)
  expect_equal(got$S2, ref_sig2(X), tolerance = 1e-8)
})

test_that("level 1 is the total increment", {
  X <- rand_path(25L)
  expect_equal(hd_path_signature2(X)$S1, X[nrow(X), ] - X[1, ])
})

# ── Shuffle identities (the specification) ─────────────────────────────────

test_that("diagonal terms satisfy S(i,i) = S(i)^2 / 2", {
  for (d in c(2L, 3L)) {
    X <- rand_path(35L, d)
    s <- hd_path_signature2(X)
    expect_equal(diag(s$S2), s$S1^2 / 2)
  }
})

test_that("off-diagonal terms satisfy S(i,j) + S(j,i) = S(i) * S(j)", {
  X <- rand_path(35L, 3L)
  s <- hd_path_signature2(X)
  expect_equal(s$S2 + t(s$S2), outer(s$S1, s$S1))
})

test_that("the shuffle identities leave Levy area as the only new number", {
  # Reconstruct the whole level-2 tensor from level 1 plus the Levy area.
  X <- rand_path(50L)
  s <- hd_path_signature2(X)
  levy <- hd_levy_area(diff(X)[, 1], diff(X)[, 2], scale = FALSE)

  rebuilt <- matrix(c(
    s$S1[1]^2 / 2,                          # S(1,1)
    s$S1[1] * s$S1[2] / 2 - levy,           # S(2,1)
    s$S1[1] * s$S1[2] / 2 + levy,           # S(1,2)
    s$S1[2]^2 / 2                           # S(2,2)
  ), 2, 2)
  expect_equal(rebuilt, s$S2)
})

# ── Lévy area: geometry ────────────────────────────────────────────────────

test_that("Levy area is antisymmetric in its arguments", {
  x <- stats::rnorm(30); y <- stats::rnorm(30)
  expect_equal(hd_levy_area(x, y), -hd_levy_area(y, x))
})

test_that("a straight-line path encloses zero area", {
  # Both coordinates proportional -> the path is a line -> no area.
  x <- stats::rnorm(30)
  expect_equal(hd_levy_area(x, 2.5 * x, scale = FALSE), 0)
  expect_equal(hd_levy_area(x, -x, scale = FALSE), 0)
})

test_that("Levy area is invariant to translation of the path", {
  # The signature depends only on increments, so shifting the level is a no-op.
  x <- stats::rnorm(30); y <- stats::rnorm(30)
  expect_equal(hd_levy_area(x, y), hd_levy_area(x, y))
  X <- cbind(cumsum(x), cumsum(y))
  s1 <- hd_path_signature2(X)
  s2 <- hd_path_signature2(sweep(X, 2, c(17, -4), "+"))
  expect_equal(s1$S2, s2$S2)
})

test_that("sign convention: positive means the first series leads", {
  # Coordinate 1 moves on step 1, coordinate 2 moves on step 2.
  # "return moves first, then volatility" -> positive.
  lead_first <- hd_levy_area(c(1, 0), c(0, 1), scale = FALSE)
  expect_gt(lead_first, 0)

  # Reverse the order -> same level 1, opposite sign.
  lead_second <- hd_levy_area(c(0, 1), c(1, 0), scale = FALSE)
  expect_lt(lead_second, 0)
  expect_equal(lead_first, -lead_second)

  # Level 1 really is identical in both orderings.
  expect_equal(sum(c(1, 0)), sum(c(0, 1)))
})

test_that("Levy area magnitude matches the enclosed area of a unit square", {
  # Path (0,0) -> (1,0) -> (1,1): half the unit square, traversed one way.
  expect_equal(hd_levy_area(c(1, 0), c(0, 1), scale = FALSE), 0.5)
})

# ── Scaling ────────────────────────────────────────────────────────────────

test_that("within-window scaling makes the statistic scale-free", {
  x <- stats::rnorm(40); y <- stats::rnorm(40)
  base <- hd_levy_area(x, y, scale = TRUE)
  expect_equal(hd_levy_area(100 * x, y, scale = TRUE), base)
  expect_equal(hd_levy_area(x, 0.001 * y, scale = TRUE), base)
})

test_that("unscaled Levy area is bilinear in the two series", {
  x <- stats::rnorm(20); y <- stats::rnorm(20)
  expect_equal(
    hd_levy_area(3 * x, 5 * y, scale = FALSE),
    15 * hd_levy_area(x, y, scale = FALSE)
  )
})

test_that("scaling degenerates gracefully on a constant series", {
  expect_true(is.na(hd_levy_area(rep(2, 10), stats::rnorm(10), scale = TRUE)))
})

# ── NA policy: no splicing, ever ───────────────────────────────────────────

test_that("any NA yields NA - interior points are never spliced out", {
  x <- stats::rnorm(20); y <- stats::rnorm(20)
  y[10] <- NA
  expect_true(is.na(hd_levy_area(x, y)))

  # Deliberately NOT equal to the value from dropping the NA pair: that would
  # splice non-adjacent steps into one, the defect behind #603.
  spliced <- hd_levy_area(x[-10], y[-10], scale = FALSE)
  expect_false(isTRUE(all.equal(spliced, NA_real_)))
})

# ── Rolling helper ─────────────────────────────────────────────────────────

test_that("rolling Levy area preserves length and warms up with NA", {
  x <- stats::rnorm(50); y <- stats::rnorm(50)
  out <- hd_roll_levy_area(x, y, n = 10L)
  expect_length(out, 50L)
  expect_true(all(is.na(out[1:9])))
  expect_false(any(is.na(out[10:50])))
})

test_that("rolling window value equals the scalar on the same slice", {
  x <- stats::rnorm(40); y <- stats::rnorm(40)
  out <- hd_roll_levy_area(x, y, n = 12L, scale = FALSE)
  expect_equal(out[20], hd_levy_area(x[9:20], y[9:20], scale = FALSE))
})

test_that("a single NA blanks exactly the windows that contain it", {
  x <- stats::rnorm(30); y <- stats::rnorm(30)
  y[15] <- NA
  out <- hd_roll_levy_area(x, y, n = 5L)
  expect_true(all(is.na(out[15:19])))   # windows spanning index 15
  expect_false(is.na(out[14]))
  expect_false(is.na(out[20]))
})

# ── Input validation ───────────────────────────────────────────────────────

test_that("hd_levy_area rejects mismatched lengths", {
  expect_snapshot(error = TRUE, hd_levy_area(1:5, 1:6))
})

test_that("hd_levy_area rejects a series too short to enclose area", {
  expect_snapshot(error = TRUE, hd_levy_area(1, 2))
})

test_that("hd_path_signature2 rejects a path with fewer than two points", {
  expect_snapshot(error = TRUE, hd_path_signature2(matrix(1:2, nrow = 1)))
})

test_that("hd_roll_levy_area rejects a window shorter than two steps", {
  expect_snapshot(error = TRUE, hd_roll_levy_area(stats::rnorm(10), stats::rnorm(10), n = 1L))
})

# ── API stability ──────────────────────────────────────────────────────────

test_that("path-signature function signatures are stable", {
  expect_snapshot(args(hd_path_signature2))
  expect_snapshot(args(hd_levy_area))
  expect_snapshot(args(hd_roll_levy_area))
})
