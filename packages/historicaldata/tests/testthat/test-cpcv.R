test_that("hd_cpcv_purge removes contaminated training observations", {
  # 20 monthly observations; months 16:20 are test; label horizon 1 month
  # Month 15: 15 + 1 = 16 = test_start → contaminated → removed
  # Month 14: 14 + 1 = 15 < 16 → clean → kept
  result <- hd_cpcv_purge(
    train_idx     = 1L:15L,
    test_idx      = 16L:20L,
    label_horizon = 1L
  )
  expect_equal(result, 1L:14L)

  # Tier A: function signature snapshot (catches param renames/additions).
  expect_snapshot(args(hd_cpcv_purge))
})

test_that("hd_cpcv_purge with label_horizon = 0 removes nothing", {
  result <- hd_cpcv_purge(
    train_idx     = 1L:15L,
    test_idx      = 16L:20L,
    label_horizon = 0L
  )
  expect_equal(result, 1L:15L)
})

test_that("hd_cpcv_purge with multi-period label removes multiple observations", {
  # label_horizon = 3: remove t where t + 3 >= 16 → t >= 13
  # So months 13, 14, 15 are removed; months 1:12 kept
  result <- hd_cpcv_purge(
    train_idx     = 1L:15L,
    test_idx      = 16L:20L,
    label_horizon = 3L
  )
  expect_equal(result, 1L:12L)
})

test_that("hd_cpcv_purge returns empty if all training obs contaminated", {
  result <- hd_cpcv_purge(
    train_idx     = 10L:15L,
    test_idx      = 16L:20L,
    label_horizon = 10L
  )
  # All t: t + 10 >= 16 → t >= 6 → all in 10:15 are removed
  expect_equal(length(result), 0L)
})

test_that("hd_cpcv_purge rejects negative label_horizon", {
  expect_snapshot(error = TRUE, hd_cpcv_purge(1L:15L, 16L:20L, label_horizon = -1L))
})

test_that("hd_cpcv_purge handles empty inputs gracefully", {
  expect_equal(hd_cpcv_purge(integer(0), 16L:20L, 1L), integer(0))
  expect_equal(hd_cpcv_purge(1L:15L, integer(0), 1L), 1L:15L)
})

# ── embargo ────────────────────────────────────────────────────────────────────

test_that("hd_cpcv_embargo removes the gap after the test fold", {
  # test_idx = 16:20; embargo_n = 2 → embargo zone is 21, 22
  # train_idx includes 1:15 and 21:25; expected: 1:15 and 23:25
  result <- hd_cpcv_embargo(
    train_idx = c(1L:15L, 21L:25L),
    test_idx  = 16L:20L,
    embargo_n = 2L
  )
  expect_equal(result, c(1L:15L, 23L:25L))
})

test_that("hd_cpcv_embargo with embargo_n = 0 removes nothing", {
  result <- hd_cpcv_embargo(
    train_idx = c(1L:15L, 21L:25L),
    test_idx  = 16L:20L,
    embargo_n = 0L
  )
  expect_equal(result, c(1L:15L, 21L:25L))
})

test_that("hd_cpcv_embargo with embargo_n = 1 removes one observation", {
  result <- hd_cpcv_embargo(
    train_idx = c(1L:15L, 21L:25L),
    test_idx  = 16L:20L,
    embargo_n = 1L
  )
  # embargo zone: 21 → remove only 21
  expect_equal(result, c(1L:15L, 22L:25L))
})

test_that("hd_cpcv_embargo rejects negative embargo_n", {
  expect_snapshot(error = TRUE, hd_cpcv_embargo(1L:15L, 16L:20L, embargo_n = -1L))
})

test_that("hd_cpcv_embargo handles empty inputs gracefully", {
  expect_equal(hd_cpcv_embargo(integer(0), 16L:20L, 2L), integer(0))
  expect_equal(hd_cpcv_embargo(1L:15L, integer(0), 2L), 1L:15L)
})

# ── paths ──────────────────────────────────────────────────────────────────────

test_that("hd_cpcv_paths returns C(6,2) = 15 pairs for n=6, k=2", {
  paths <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)
  expect_equal(length(paths), choose(6, 2))  # 15
})

test_that("hd_cpcv_paths each element has train and test components", {
  paths <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)
  for (p in paths) {
    expect_named(p, c("train", "test"))
    expect_type(p$train, "integer")
    expect_type(p$test, "integer")
  }
})

test_that("hd_cpcv_paths train + test = all groups", {
  paths <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)
  for (p in paths) {
    expect_equal(sort(c(p$train, p$test)), 1L:6L)
  }
})

test_that("hd_cpcv_paths test set has exactly n_test_groups elements", {
  paths <- hd_cpcv_paths(n_groups = 6L, n_test_groups = 2L)
  for (p in paths) {
    expect_equal(length(p$test), 2L)
  }
})

test_that("hd_cpcv_paths returns C(5,3) = 10 for n=5, k=3", {
  paths <- hd_cpcv_paths(n_groups = 5L, n_test_groups = 3L)
  expect_equal(length(paths), choose(5, 3))  # 10
})

test_that("hd_cpcv_paths rejects invalid inputs", {
  expect_snapshot(error = TRUE, hd_cpcv_paths(1L, 1L))  # n_groups < 2
  expect_snapshot(error = TRUE, hd_cpcv_paths(6L, 0L))  # n_test_groups < 1
  expect_snapshot(error = TRUE, hd_cpcv_paths(6L, 6L))  # n_test_groups >= n_groups
})

# ── PBO ────────────────────────────────────────────────────────────────────────

test_that("hd_pbo returns near 1 when IS/OOS are perfectly anti-correlated", {
  set.seed(42L)
  n_paths <- 15L
  n_strat <- 6L
  is_scores  <- matrix(rnorm(n_paths * n_strat), n_paths, n_strat)
  # OOS is the negative of IS → IS-best is always OOS-worst
  oos_scores <- -is_scores
  res <- hd_pbo(is_scores, oos_scores)
  expect_equal(res$pbo, 1.0)
  expect_equal(res$n_paths, n_paths)
  expect_equal(res$n_strategies, n_strat)

  # Tier A: function signature snapshot (catches param renames/additions).
  expect_snapshot(args(hd_pbo))
})

test_that("hd_pbo returns near 0 when IS/OOS are perfectly correlated", {
  set.seed(42L)
  n_paths <- 15L
  n_strat <- 6L
  is_scores <- matrix(rnorm(n_paths * n_strat), n_paths, n_strat)
  # OOS = IS (perfect IS→OOS transfer, no overfitting)
  oos_scores <- is_scores
  res <- hd_pbo(is_scores, oos_scores)
  expect_equal(res$pbo, 0.0)
})

test_that("hd_pbo result is between 0 and 1 for random scores", {
  set.seed(123L)
  is_scores  <- matrix(rnorm(20L * 8L), 20L, 8L)
  oos_scores <- matrix(rnorm(20L * 8L), 20L, 8L)
  res <- hd_pbo(is_scores, oos_scores)
  expect_gte(res$pbo, 0.0)
  expect_lte(res$pbo, 1.0)
  expect_equal(length(res$is_best_idx),  20L)
  expect_equal(length(res$oos_rank_pct), 20L)
})

test_that("hd_pbo rejects dimension mismatch", {
  is_scores  <- matrix(rnorm(10L), 5L, 2L)
  oos_scores <- matrix(rnorm(15L), 5L, 3L)
  expect_snapshot(error = TRUE, hd_pbo(is_scores, oos_scores))
})

test_that("hd_pbo rejects fewer than 2 paths", {
  expect_snapshot(
    error = TRUE,
    hd_pbo(matrix(rnorm(4L), 1L, 4L), matrix(rnorm(4L), 1L, 4L))
  )
})

test_that("hd_pbo rejects fewer than 2 strategies", {
  expect_snapshot(
    error = TRUE,
    hd_pbo(matrix(rnorm(5L), 5L, 1L), matrix(rnorm(5L), 5L, 1L))
  )
})

test_that("hd_pbo oos_rank_pct values are in [0, 1]", {
  set.seed(7L)
  is_scores  <- matrix(rnorm(30L), 10L, 3L)
  oos_scores <- matrix(rnorm(30L), 10L, 3L)
  res <- hd_pbo(is_scores, oos_scores)
  valid_ranks <- res$oos_rank_pct[!is.na(res$oos_rank_pct)]
  expect_true(all(valid_ranks >= 0 & valid_ranks <= 1))
})
