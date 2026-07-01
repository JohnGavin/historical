# Tests for hd_weight_stability_diagnostic() — Phase 4 core of #507
#
# Covers:
#   1. Output structure: columns, row count, attributes
#   2. equal_weight sanity anchor: zero turnover, max_abs_weight = 1/p
#   3. raw_mvo instability: higher turnover than gmv (article's core claim)
#   4. Wide-regime failure: raw_mvo n_failed > 0 when p >= train_window;
#      gmv and hrp remain finite
#   5. Look-ahead guard: perturbing the final OOS row does not affect
#      weight-construction metrics (avg_turnover, max_abs_weight, n_failed)
#   6. Validation errors: snapshot-tested cli_abort calls
#   7. Function signature stability (catches API drift)

# Helper: synthetic returns matrix (no date column, complete cases)
.ws_returns <- function(n, p, seed = 42L, sd = 0.05) {
  set.seed(seed)
  X <- matrix(stats::rnorm(n * p, sd = sd), nrow = n, ncol = p)
  colnames(X) <- paste0("A", seq_len(p))
  X
}

# ---------------------------------------------------------------------------
# 1. Output structure
# ---------------------------------------------------------------------------

test_that("output has one row per requested method with expected columns and attributes", {
  X  <- .ws_returns(120L, 5L)
  tw <- 60L
  result <- hd_weight_stability_diagnostic(X, train_window = tw)

  expect_s3_class(result, "tbl_df")

  expected_methods <- c(
    "raw_mvo", "gmv", "shrunk_mu", "black_litterman", "equal_weight", "hrp"
  )
  expect_equal(nrow(result), 6L)
  expect_equal(sort(result$method), sort(expected_methods))

  expected_cols <- c(
    "method", "n_oos", "n_failed", "oos_mean", "oos_vol", "oos_sharpe",
    "avg_turnover", "max_abs_weight", "mean_eff_n"
  )
  expect_true(all(expected_cols %in% names(result)))

  # Attributes
  expect_equal(attr(result, "train_window"), tw)
  expect_equal(attr(result, "n_periods"), 120L)
  expect_equal(attr(result, "n_assets"), 5L)
  expect_equal(attr(result, "cov_method"), "ledoit_wolf")
})

test_that("subset of methods returns only requested rows", {
  X <- .ws_returns(100L, 4L)
  result <- hd_weight_stability_diagnostic(
    X,
    methods = c("gmv", "equal_weight"),
    train_window = 50L
  )
  expect_equal(nrow(result), 2L)
  expect_equal(sort(result$method), c("equal_weight", "gmv"))
})

test_that("data frame input with date column is handled correctly", {
  X  <- as.data.frame(.ws_returns(100L, 4L))
  X$date <- seq.Date(as.Date("2010-01-01"), by = "month", length.out = 100L)
  result <- hd_weight_stability_diagnostic(
    X,
    methods = "equal_weight",
    train_window = 50L
  )
  expect_equal(attr(result, "n_assets"), 4L)
  expect_equal(nrow(result), 1L)
})

# ---------------------------------------------------------------------------
# 2. equal_weight sanity anchor
# ---------------------------------------------------------------------------

test_that("equal_weight has zero turnover and max_abs_weight == 1/p", {
  p  <- 8L
  X  <- .ws_returns(150L, p)
  result <- hd_weight_stability_diagnostic(
    X,
    methods      = "equal_weight",
    train_window = 60L
  )
  eq_row <- result[result$method == "equal_weight", ]

  # Turnover must be exactly 0: weights never change for 1/N
  expect_lt(eq_row$avg_turnover, 1e-12)

  # max_abs_weight must equal 1/p (every weight = 1/p)
  expect_lt(abs(eq_row$max_abs_weight - 1 / p), 1e-12)

  # effective N must equal p (all weights equal)
  expect_lt(abs(eq_row$mean_eff_n - p), 1e-9)

  # No failures for equal_weight (no solve required)
  expect_equal(eq_row$n_failed, 0L)
})

# ---------------------------------------------------------------------------
# 3. raw_mvo instability: higher turnover than gmv
# ---------------------------------------------------------------------------

test_that("raw_mvo avg_turnover > gmv avg_turnover on wide synthetic returns", {
  # p=5, n=240, tw=40: p < n so raw_mvo succeeds, but sample-mu noise causes
  # much higher turnover than gmv (which only needs Sigma, not mu).
  # Inflated sd ensures sample means are noisy relative to variation in Sigma.
  p  <- 5L
  n  <- 240L
  tw <- 40L
  set.seed(2025L)
  X  <- matrix(stats::rnorm(n * p, mean = 0, sd = 0.08), nrow = n, ncol = p)
  colnames(X) <- paste0("A", seq_len(p))

  result <- hd_weight_stability_diagnostic(
    X,
    methods      = c("raw_mvo", "gmv"),
    train_window = tw
  )

  raw_to <- result$avg_turnover[result$method == "raw_mvo"]
  gmv_to <- result$avg_turnover[result$method == "gmv"]

  # The article's thesis: plug-in MVO amplifies mu-estimation noise → high turnover
  expect_gt(raw_to, gmv_to)
})

# ---------------------------------------------------------------------------
# 4. Wide-regime failure (p >= train_window)
# ---------------------------------------------------------------------------

test_that("raw_mvo n_failed > 0 when p >= train_window; gmv and hrp stay finite", {
  # p = train_window = 10 → sample cov rank-deficient → solve() fails for raw_mvo
  # Regularised methods (gmv: Ledoit-Wolf; hrp: HRP on Ledoit-Wolf) remain finite
  p  <- 10L
  tw <- 10L    # p == tw: sample cov is exactly singular
  n  <- 60L    # n > tw + 1 required
  X  <- .ws_returns(n, p, seed = 7L)

  result <- hd_weight_stability_diagnostic(
    X,
    methods      = c("raw_mvo", "gmv", "hrp"),
    train_window = tw
  )

  raw_row <- result[result$method == "raw_mvo", ]
  gmv_row <- result[result$method == "gmv",     ]
  hrp_row <- result[result$method == "hrp",     ]

  expect_gt(raw_row$n_failed, 0L)
  expect_equal(gmv_row$n_failed, 0L)
  expect_equal(hrp_row$n_failed, 0L)
})

# ---------------------------------------------------------------------------
# 5. Look-ahead guard
# ---------------------------------------------------------------------------

test_that("weight-construction metrics unchanged when final OOS row is perturbed 1000x", {
  # The last OOS row (row n) is used as OOS for origin t = n-1.
  # It appears in NO training window (last training window ends at row n-1).
  # Therefore perturbing row n:
  #   - MUST NOT change: avg_turnover, max_abs_weight, n_failed (weight metrics)
  #   - MUST change: oos_mean, oos_vol (OOS performance metrics)
  # This verifies that weight construction never reads returns[t+1, ].
  p  <- 5L
  n  <- 100L
  tw <- 60L
  set.seed(42L)
  X  <- matrix(stats::rnorm(n * p, sd = 0.05), nrow = n, ncol = p)
  colnames(X) <- paste0("A", seq_len(p))

  meths <- c("gmv", "equal_weight", "hrp")

  result_orig <- hd_weight_stability_diagnostic(X, methods = meths, train_window = tw)

  # Perturb ONLY row n (final OOS period; never in any training window)
  X_pert <- X
  X_pert[n, ] <- X[n, ] * 1000

  result_pert <- hd_weight_stability_diagnostic(X_pert, methods = meths, train_window = tw)

  # Weight-construction metrics must be identical
  expect_equal(result_orig$avg_turnover,   result_pert$avg_turnover)
  expect_equal(result_orig$max_abs_weight, result_pert$max_abs_weight)
  expect_equal(result_orig$n_failed,       result_pert$n_failed)
  expect_equal(result_orig$mean_eff_n,     result_pert$mean_eff_n)

  # OOS mean must differ (final OOS return was inflated 1000x)
  # At least one method's oos_mean changes
  expect_false(
    isTRUE(all.equal(result_orig$oos_mean, result_pert$oos_mean)),
    label = "OOS mean must change when final OOS return is perturbed"
  )
})

# ---------------------------------------------------------------------------
# 6. Validation errors (snapshot-tested cli_abort calls)
# ---------------------------------------------------------------------------

test_that("non-matrix/non-data-frame returns triggers cli_abort", {
  expect_snapshot(
    error = TRUE,
    hd_weight_stability_diagnostic("not_a_matrix")
  )
})

test_that("non-numeric returns (after date drop) triggers cli_abort", {
  bad <- matrix(letters[1:20], nrow = 5, ncol = 4)
  expect_snapshot(
    error = TRUE,
    hd_weight_stability_diagnostic(bad)
  )
})

test_that("too few rows triggers cli_abort", {
  # n=11, train_window=10: n <= train_window + 1 → abort
  X <- .ws_returns(11L, 4L)
  expect_snapshot(
    error = TRUE,
    hd_weight_stability_diagnostic(X, train_window = 10L)
  )
})

test_that("invalid method name triggers cli_abort", {
  X <- .ws_returns(100L, 4L)
  expect_snapshot(
    error = TRUE,
    hd_weight_stability_diagnostic(X, methods = c("gmv", "not_a_method"))
  )
})

test_that("empty methods vector triggers cli_abort", {
  X <- .ws_returns(100L, 4L)
  expect_snapshot(
    error = TRUE,
    hd_weight_stability_diagnostic(X, methods = character(0))
  )
})

# ---------------------------------------------------------------------------
# 7. Function signature stability
# ---------------------------------------------------------------------------

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_weight_stability_diagnostic))
})
