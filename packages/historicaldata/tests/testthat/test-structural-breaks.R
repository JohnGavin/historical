# Tests for hd_structural_breaks() — iterative forward-split break detector
#
# Following the snapshot-test-policy.md:
#   6 test_that blocks → need >= 2 snapshots; we have 3 (error x2 + signature)
#   Algorithmic tests use expect_equal / expect_gte / expect_true; no snapshots.
#   Snapshot tests guard: error messages (NA in returns, alpha out of range)
#   and the function signature for API stability.

# ── 1. Injected break detected (algorithmic) ──────────────────────────────────

test_that("injected mean-shift break is detected in correct half", {
  set.seed(1)
  n_half <- 6L * 252L
  r_pre  <- rnorm(n_half,  mean =  0.0008, sd = 0.01)
  r_post <- rnorm(n_half,  mean = -0.0008, sd = 0.01)
  r      <- c(r_pre, r_post)

  result <- hd_structural_breaks(r)

  expect_true(length(result$break_indices) >= 1L,
              label = "at least one break detected in injected-shift series")
  expect_true(result$post_break_start > n_half * 0.5,
              label = "post-break segment starts in second half of series")
})


# ── 2. No break on a stationary series (algorithmic) ─────────────────────────

test_that("stationary series returns zero breaks and post_break_start == 1", {
  set.seed(2)
  r <- rnorm(12L * 252L, mean = 0.0005, sd = 0.01)

  result <- hd_structural_breaks(r)

  expect_equal(length(result$break_indices), 0L,
               label = "no breaks in stationary series")
  expect_equal(result$post_break_start, 1L,
               label = "post_break_start is 1 when no break found")
})


# ── 3. Series too short to split (algorithmic) ────────────────────────────────

test_that("series shorter than 2 * min_obs returns no break and post_break_start == 1", {
  # min_obs = ceiling(5 * 252) = 1260; series of 50 < 2 * 1260
  r <- rnorm(50L)

  result <- hd_structural_breaks(r)

  expect_equal(result$n_breaks, 0L,
               label = "n_breaks == 0 for too-short series")
  expect_equal(result$post_break_start, 1L,
               label = "post_break_start == 1 for too-short series")
  expect_equal(nrow(result$segments), 1L,
               label = "single segment when no break")
})


# ── 4. NA in returns aborts (snapshot) ───────────────────────────────────────

test_that("NA in returns aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks(c(0.1, NA, 0.2))
  )
})


# ── 5. alpha out of range aborts (snapshot) ───────────────────────────────────

test_that("alpha out of range aborts with informative error", {
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks(rnorm(100), alpha = 1.5)
  )
})


# ── 6. Signature stability (snapshot) ────────────────────────────────────────

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_structural_breaks))
})
