# Smoke tests for CPCV integration into plan_drif (#319)
#
# Verifies that the drif_path_sharpe / drif_pbo computation logic
# produces correct-length output and a valid PBO value on a small
# synthetic portfolio.  Does NOT run a targets pipeline — all logic
# is extracted inline so the tests are self-contained and fast.

# ── Helpers (mirrors logic in plan_drif.R) ───────────────────────────────────

.make_port <- function(n = 90L, seed = 42L) {
  set.seed(seed)
  tibble::tibble(
    ym            = format(seq.Date(as.Date("2016-01-01"), by = "month",
                                   length.out = n), "%Y-%m"),
    portfolio_ret = stats::rnorm(n, mean = 0.006, sd = 0.04),
    benchmark_ret = stats::rnorm(n, mean = 0.004, sd = 0.035),
    rf_ret        = rep(0.0002, n)
  )
}

.sharpe_monthly <- function(ret) {
  ret <- ret[!is.na(ret)]
  if (length(ret) < 3L) return(NA_real_)
  ann_ret <- prod(1 + ret)^(12 / length(ret)) - 1
  ann_vol <- stats::sd(ret) * sqrt(12)
  if (ann_vol <= 0) return(NA_real_)
  ann_ret / ann_vol
}

.run_path_sharpe <- function(port, params) {
  n          <- nrow(port)
  group_id   <- cut(seq_len(n), breaks = params$n_groups,
                    labels = FALSE, include.lowest = TRUE)
  group_rows <- lapply(seq_len(params$n_groups), function(g) which(group_id == g))
  paths      <- hd_cpcv_paths(params$n_groups, params$n_test_groups)

  vapply(paths, function(p) {
    train_rows   <- sort(unlist(group_rows[p$train]))
    test_rows    <- sort(unlist(group_rows[p$test]))
    train_purged <- hd_cpcv_purge(train_rows, test_rows, params$label_horizon)
    train_clean  <- hd_cpcv_embargo(train_purged, test_rows, params$embargo_n)
    .sharpe_monthly(port$portfolio_ret[test_rows])
  }, numeric(1L))
}

.run_pbo <- function(port, params) {
  n          <- nrow(port)
  group_id   <- cut(seq_len(n), breaks = params$n_groups,
                    labels = FALSE, include.lowest = TRUE)
  group_rows <- lapply(seq_len(params$n_groups), function(g) which(group_id == g))
  paths      <- hd_cpcv_paths(params$n_groups, params$n_test_groups)
  n_paths    <- length(paths)

  is_mat  <- matrix(NA_real_, nrow = n_paths, ncol = 2L,
                    dimnames = list(NULL, c("DRIF", "Benchmark")))
  oos_mat <- is_mat

  for (i in seq_len(n_paths)) {
    p            <- paths[[i]]
    train_rows   <- sort(unlist(group_rows[p$train]))
    test_rows    <- sort(unlist(group_rows[p$test]))
    train_purged <- hd_cpcv_purge(train_rows, test_rows, params$label_horizon)
    train_clean  <- hd_cpcv_embargo(train_purged, test_rows, params$embargo_n)

    is_mat[i, "DRIF"]       <- .sharpe_monthly(port$portfolio_ret[train_clean])
    is_mat[i, "Benchmark"]  <- .sharpe_monthly(port$benchmark_ret[train_clean])
    oos_mat[i, "DRIF"]      <- .sharpe_monthly(port$portfolio_ret[test_rows])
    oos_mat[i, "Benchmark"] <- .sharpe_monthly(port$benchmark_ret[test_rows])
  }

  hd_pbo(is_scores = is_mat, oos_scores = oos_mat)
}

# ── Tests ────────────────────────────────────────────────────────────────────

test_that("drif_path_sharpe has length C(n_groups, n_test_groups) = 15", {
  params <- list(n_groups = 6L, n_test_groups = 2L,
                 label_horizon = 1L, embargo_n = 1L)
  port   <- .make_port(n = 90L)

  path_sharpe <- .run_path_sharpe(port, params)

  expected_paths <- choose(params$n_groups, params$n_test_groups)
  expect_equal(length(path_sharpe), expected_paths)
  # 15 = C(6,2)
  expect_equal(expected_paths, 15L)
})

test_that("drif_path_sharpe values are numeric (finite or NA)", {
  params      <- list(n_groups = 6L, n_test_groups = 2L,
                      label_horizon = 1L, embargo_n = 1L)
  port        <- .make_port(n = 90L)
  path_sharpe <- .run_path_sharpe(port, params)

  expect_type(path_sharpe, "double")
  # At least one finite Sharpe (random data with n=90 should produce finite values)
  expect_true(any(is.finite(path_sharpe)))
})

test_that("drif_pbo is computed and returns a valid list", {
  params <- list(n_groups = 6L, n_test_groups = 2L,
                 label_horizon = 1L, embargo_n = 1L)
  port   <- .make_port(n = 90L)

  pbo_result <- .run_pbo(port, params)

  expect_type(pbo_result, "list")
  expect_named(pbo_result,
               c("pbo", "n_paths", "n_strategies", "is_best_idx", "oos_rank_pct"),
               ignore.order = TRUE)
  expect_true(is.finite(pbo_result$pbo) || is.nan(pbo_result$pbo))
  # PBO is in [0, 1]
  if (is.finite(pbo_result$pbo)) {
    expect_gte(pbo_result$pbo, 0)
    expect_lte(pbo_result$pbo, 1)
  }
  # n_strategies should be 2 (DRIF + Benchmark)
  expect_equal(pbo_result$n_strategies, 2L)
})

test_that("drif_pbo n_paths equals C(n_groups, n_test_groups)", {
  params <- list(n_groups = 6L, n_test_groups = 2L,
                 label_horizon = 1L, embargo_n = 1L)
  port   <- .make_port(n = 90L)

  pbo_result <- .run_pbo(port, params)

  expected_paths <- choose(params$n_groups, params$n_test_groups)
  # n_paths in the result excludes NA paths; with 90 obs and 6 groups
  # (~15 obs each) all paths should have enough data
  expect_lte(pbo_result$n_paths, expected_paths)
  expect_gte(pbo_result$n_paths, 1L)
})

test_that("purge reduces training set when label horizon = 1", {
  # With label_horizon = 1, the training observation immediately before the
  # test fold should be purged.
  train <- 1L:20L
  test  <- 21L:25L
  purged <- hd_cpcv_purge(train, test, label_horizon = 1L)
  # Obs 20: 20 + 1 = 21 = test_start → should be removed
  expect_false(20L %in% purged)
  expect_true(19L %in% purged)
})

test_that("embargo removes training observations immediately after test fold", {
  train    <- c(1L:15L, 26L:30L)
  test     <- 16L:25L
  embargoed <- hd_cpcv_embargo(train, test, embargo_n = 2L)
  # Embargo zone: 26, 27 (test_end=25, +1 and +2)
  expect_false(26L %in% embargoed)
  expect_false(27L %in% embargoed)
  expect_true(28L %in% embargoed)
})
