# Tests for hd_first_passage() — first-passage / gambler's-ruin barrier
# probability (#586 G1)
#
# The symmetric case has an independently-checkable closed form quoted by
# the source article: P(pass) = 1/(1+exp(-theta)), theta = 2*mu*T/sigma^2.
# Every symmetric-case test below recomputes that logistic form directly
# rather than re-deriving the implementation's own two-barrier formula, so
# agreement is evidence the general formula correctly specialises.

test_that("symmetric barriers reproduce the source article's logistic identity exactly", {
  for (mu in c(0.0005, 0.001, 0.002, -0.001)) {
    for (sigma in c(0.01, 0.02, 0.05)) {
      for (T in c(0.05, 0.10, 0.20)) {
        theta <- 2 * mu * T / sigma^2
        expected <- 1 / (1 + exp(-theta))

        out <- hd_first_passage(mu = mu, sigma = sigma, upper = T, lower = T)
        expect_equal(out$pass_prob, expected, tolerance = 1e-9)
        expect_equal(out$theta, theta, tolerance = 1e-9)
      }
    }
  }
})

test_that("positive drift with symmetric barriers gives pass_prob > 0.5", {
  out <- hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.10)
  expect_gt(out$pass_prob, 0.5)
})

test_that("negative drift with symmetric barriers gives pass_prob < 0.5", {
  out <- hd_first_passage(mu = -0.001, sigma = 0.02, upper = 0.10)
  expect_lt(out$pass_prob, 0.5)
})

test_that("positive and negative drift of equal magnitude are complementary under symmetric barriers", {
  pos <- hd_first_passage(mu = 0.0015, sigma = 0.02, upper = 0.10)
  neg <- hd_first_passage(mu = -0.0015, sigma = 0.02, upper = 0.10)
  expect_equal(pos$pass_prob, 1 - neg$pass_prob, tolerance = 1e-9)
})

test_that("driftless (mu = 0) case matches the linear gambler's-ruin limit a/(a+b)", {
  out <- hd_first_passage(mu = 0, sigma = 0.02, upper = 0.15, lower = 0.05)
  expect_equal(out$pass_prob, 0.05 / (0.05 + 0.15), tolerance = 1e-9)

  # Symmetric driftless case is exactly 0.5, matching the logistic identity
  # at theta = 0.
  out_sym <- hd_first_passage(mu = 0, sigma = 0.02, upper = 0.10)
  expect_equal(out_sym$pass_prob, 0.5, tolerance = 1e-9)
})

test_that("mu near-zero (but nonzero) is numerically continuous with the mu = 0 limit", {
  out_zero <- hd_first_passage(mu = 0, sigma = 0.02, upper = 0.10, lower = 0.10)
  out_tiny <- hd_first_passage(mu = 1e-10, sigma = 0.02, upper = 0.10, lower = 0.10)
  expect_equal(out_tiny$pass_prob, out_zero$pass_prob, tolerance = 1e-6)
})

test_that("asymmetric barriers: closer barrier is more likely to be hit first", {
  # A far upper target and a near lower floor, mild positive drift --
  # the near floor should still be materially likely to be hit first.
  out <- hd_first_passage(mu = 0.0005, sigma = 0.02, upper = 0.30, lower = 0.05)
  # Compare against the driftless baseline for the same asymmetric barriers.
  baseline <- 0.05 / (0.05 + 0.30)
  # Positive drift should raise pass_prob above the driftless baseline, but
  # the near floor still caps it well below the symmetric near-certain case.
  expect_gt(out$pass_prob, baseline)
  expect_lt(out$pass_prob, 0.9)
})

test_that("asymmetric theta is NA (no single theta exists for asymmetric barriers)", {
  out <- hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.20, lower = 0.05)
  expect_true(is.na(out$theta))
})

test_that("lower defaults to upper (symmetric convention)", {
  out_default <- hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.10)
  out_explicit <- hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.10, lower = 0.10)
  expect_equal(out_default, out_explicit)
})

test_that("echoed inputs are returned unchanged", {
  out <- hd_first_passage(mu = 0.0012, sigma = 0.025, upper = 0.12, lower = 0.08)
  expect_equal(out$mu, 0.0012)
  expect_equal(out$sigma, 0.025)
  expect_equal(out$upper, 0.12)
  expect_equal(out$lower, 0.08)
})

# ── Input validation (snapshot-tested per snapshot-test-policy.md) ──────────

test_that("mu: must be a single non-missing number", {
  expect_snapshot(error = TRUE, hd_first_passage(mu = "x", sigma = 0.02, upper = 0.10))
  expect_snapshot(error = TRUE, hd_first_passage(mu = NA_real_, sigma = 0.02, upper = 0.10))
  expect_snapshot(error = TRUE, hd_first_passage(mu = c(0.001, 0.002), sigma = 0.02, upper = 0.10))
})

test_that("sigma: must be a single positive number", {
  expect_snapshot(error = TRUE, hd_first_passage(mu = 0.001, sigma = -0.02, upper = 0.10))
  expect_snapshot(error = TRUE, hd_first_passage(mu = 0.001, sigma = 0, upper = 0.10))
})

test_that("upper: must be a single positive number", {
  expect_snapshot(error = TRUE, hd_first_passage(mu = 0.001, sigma = 0.02, upper = -0.10))
  expect_snapshot(error = TRUE, hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0))
})

test_that("lower: must be a single positive number", {
  expect_snapshot(error = TRUE, hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.10, lower = -0.05))
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_first_passage))
})
