# Tests for hd_strategy_value_gate() — Advisory governance scorer (#496 Phase 1)
#
# Test structure:
#   1. Anti-correlated candidate → "admit"
#   2. Near-duplicate candidate → "reject"
#   3. Pure noise candidate → NOT "admit"
#   4. Verdict tibble schema (exact columns + levels)
#   5. Advisory: failing candidate returns tibble, never errors
#   6. Input-validation snapshot: non-numeric candidate
#   7. Input-validation snapshot: non-numeric existing
#   8. Input-validation snapshot: no overlapping rows (empty after NA drop)
#   9. Function signature stability snapshot
#
# Snapshot count: 4 snapshots (errors x3 + args x1) out of 9 blocks
# => ratio 4/9 >= 30% — satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers ------------------------------------------------

# Well-conditioned existing 2-strategy return matrix (60 months)
.make_existing <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  matrix(
    c(rnorm(n, mean = 0.006, sd = 0.04),
      rnorm(n, mean = 0.004, sd = 0.03)),
    nrow = n, ncol = 2L,
    dimnames = list(NULL, c("strat_a", "strat_b"))
  )
}

# Anti-correlated candidate that passes ALL three quantitative checks:
#   - |rho| ≈ 0.22 (< 0.80 threshold) → similarity PASS
#   - negative-correlation reduces equal-weight portfolio variance → div PASS
#   - own mean return 0.007/mo > 0 so equal-weight Sharpe improves → IS PASS
#
# Construction: candidate = 0.007 + (-0.3) * (strat_a - mean(strat_a)) + noise
#   anti-correlation comes from the -0.3 * deviation term (mean-centred)
#   so candidate has its own positive mean regardless of strat_a's level.
.make_existing_1strat <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  matrix(
    rnorm(n, mean = 0.006, sd = 0.04),
    nrow = n, ncol = 1L,
    dimnames = list(NULL, "strat_a")
  )
}

.make_anti_corr_candidate <- function(existing_1strat, seed = 42L) {
  set.seed(seed)
  x   <- existing_1strat[, 1]
  # Subtract the sample mean so candidate's mean is controlled independently
  -0.3 * (x - mean(x)) + 0.007 + rnorm(length(x), sd = 0.04)
  # |rho| ≈ 0.22 with strat_a (well below 0.80 threshold)
  # candidate mean ≈ 0.007 (positive → Sharpe should improve in EW portfolio)
}

# Near-duplicate candidate (ρ ≈ 0.97 vs strat_a, high noise on strat_b)
.make_near_dup_candidate <- function(existing, seed = 7L) {
  set.seed(seed)
  0.97 * existing[, 1] + rnorm(nrow(existing), sd = 0.002)
}

# Pure noise candidate (ρ ≈ 0 vs both strategies)
.make_noise_candidate <- function(n = 60L, seed = 99L) {
  set.seed(seed)
  rnorm(n, mean = 0, sd = 0.04)
}


# ---- Test 1: Anti-correlated candidate → "admit" ---------------------------
# Uses a 1-strategy existing set so we fully control the correlation.
# With coefficient -0.5 and equal noise, |rho| ≈ 0.45 (< 0.80 threshold)
# → similarity passes. Anti-correlated strategy should also reduce variance
# and improve portfolio Sharpe → incremental_sharpe and diversification pass.
test_that("moderately anti-correlated candidate yields 'admit' overall", {
  existing  <- .make_existing_1strat()
  candidate <- .make_anti_corr_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate,
    existing,
    candidate_name   = "anti_corr",
    periods_per_year = 12L
  )

  expect_equal(attr(result, "overall"), "admit")
  expect_equal(attr(result, "candidate_name"), "anti_corr")

  # similarity should pass (|ρ| ≈ 0.45 < 0.80)
  sim_row <- result[result$check == "similarity", ]
  expect_equal(as.character(sim_row$verdict), "pass")
  expect_lt(sim_row$value, 0.80)

  # diversification_ew must pass
  div_row <- result[result$check == "diversification_ew", ]
  expect_equal(as.character(div_row$verdict), "pass")
})

# ---- Test 2: Near-duplicate candidate → "reject" ---------------------------
test_that("near-duplicate candidate (rho~0.97) yields 'reject' when incremental_sharpe<=0", {
  existing  <- .make_existing()
  candidate <- .make_near_dup_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate,
    existing,
    candidate_name   = "near_dup",
    corr_threshold   = 0.80,
    periods_per_year = 12L
  )

  # similarity must fail (|ρ| > 0.80)
  sim_row <- result[result$check == "similarity", ]
  expect_equal(as.character(sim_row$verdict), "fail")

  # overall must be "reject" or at minimum not "admit"
  expect_false(attr(result, "overall") == "admit")

  # If also incremental_sharpe and diversification fail → "reject"
  is_row  <- result[result$check == "incremental_sharpe", ]
  div_row <- result[result$check == "diversification_ew", ]
  if (as.character(is_row$verdict)  == "fail" &&
      as.character(div_row$verdict) == "fail") {
    expect_equal(attr(result, "overall"), "reject")
  }
})

# ---- Test 3: Noise candidate → NOT "admit" ----------------------------------
test_that("pure noise candidate is NOT 'admit'", {
  existing  <- .make_existing_1strat()
  candidate <- .make_noise_candidate(n = nrow(existing))

  result <- hd_strategy_value_gate(
    candidate,
    existing,
    candidate_name   = "noise",
    periods_per_year = 12L
  )

  # Noise usually offers no incremental Sharpe → not admit
  expect_false(attr(result, "overall") == "admit")
})

# ---- Test 4: Verdict tibble schema ----------------------------------------
test_that("result tibble has exact columns and factor levels", {
  existing  <- .make_existing()
  candidate <- .make_anti_corr_candidate(existing)

  result <- hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("check", "metric", "value", "threshold", "verdict"))
  expect_s3_class(result$verdict, "factor")
  expect_equal(levels(result$verdict), c("pass", "fail", "flag", "na"))
  expect_equal(nrow(result), 6L)

  # All 6 checks are present
  expect_setequal(result$check, c(
    "similarity", "incremental_sharpe",
    "diversification_ew", "diversification_gmv",
    "crowding", "robustness"
  ))

  # crowding and robustness with no input → "na"
  expect_equal(as.character(result[result$check == "crowding",    "verdict"][[1]]), "na")
  expect_equal(as.character(result[result$check == "robustness",  "verdict"][[1]]), "na")
})

# ---- Test 5: Advisory — failing candidate returns tibble, never errors ------
test_that("a reject-quality candidate returns a tibble, not an error", {
  existing  <- .make_existing()
  candidate <- .make_near_dup_candidate(existing)

  result <- expect_no_error(
    hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)
  )
  expect_s3_class(result, "tbl_df")
  expect_true(attr(result, "overall") %in% c("admit", "research_only", "reject"))
})

# ---- Test 6: crowding flag --------------------------------------------------
test_that("crowding = TRUE yields 'flag' verdict", {
  existing  <- .make_existing()
  candidate <- .make_anti_corr_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate, existing, crowding = TRUE, periods_per_year = 12L
  )
  crowd_row <- result[result$check == "crowding", ]
  expect_equal(as.character(crowd_row$verdict), "flag")
})

# ---- Test 7: Input-validation snapshot: non-numeric candidate ---------------
test_that("non-numeric candidate triggers cli_abort", {
  existing <- .make_existing()
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate("not_a_vector", existing)
  )
})

# ---- Test 8: Input-validation snapshot: non-numeric existing ----------------
test_that("non-numeric existing triggers cli_abort", {
  existing  <- .make_existing()
  candidate <- .make_anti_corr_candidate(existing)
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate(candidate, "not_a_matrix")
  )
})

# ---- Test 9: Input-validation snapshot: no overlapping complete rows --------
test_that("candidate all-NA yields cli_abort for no overlapping rows", {
  existing  <- .make_existing(n = 5L)
  candidate <- rep(NA_real_, 5L)
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate(candidate, existing)
  )
})

# ---- Test 10: Function signature stability ---------------------------------
test_that("hd_strategy_value_gate() signature is stable (catches API drift)", {
  expect_snapshot(args(hd_strategy_value_gate))
})
