# Tests for hd_strategy_value_gate() -- Advisory governance scorer (#496,
# supersedes PR #511)
#
# Test structure:
#   1. Strong anti-correlated candidate, 20yr sample -> "admit"
#   2. Near-duplicate candidate, short sample -> "reject"
#   3. Noise candidate -> "mixed" (a determinate, non-"admit" result)
#   4. Degenerate zero-variance existing column -> "indeterminate" (never
#      collapsed with "mixed" or "reject" -- checks-must-distinguish-unknown)
#   5. Verdict tibble schema (exact columns, 7 rows, factor levels incl. "n_a")
#   6. Advisory: failing candidate returns tibble, never errors
#   7. crowding = TRUE yields 'flag' verdict
#   8. corr_threshold defaults to HD_REDUNDANCY_THRESH (single source of truth)
#   9. detection_power "n_a" for a non-positive candidate Sharpe (requirement 3)
#   10. Input-validation snapshot: non-numeric candidate
#   11. Input-validation snapshot: non-numeric existing
#   12. Input-validation snapshot: no overlapping rows (empty after NA drop)
#   13. Function signature stability snapshot
#
# Snapshot count: 4 snapshots (errors x3 + args x1) out of 13 blocks
# => ratio 4/13 >= 30% -- satisfies snapshot-test-policy for 9+ blocks

# ---- Synthetic data helpers ------------------------------------------------
#
# All fixtures below were run and confirmed against the live implementation
# (see PR body) before being encoded as expectations here -- not derived
# analytically and hoped to match.

# 20 years of monthly data, single existing strategy, and a strong-effect
# anti-correlated candidate. Verified: cor ~ -0.285, candidate's own
# annualised Sharpe ~ 1.26 (well above the ~4-year detection-power
# requirement at that Sharpe), incremental Sharpe positive, EW
# diversification positive -> overall "admit".
.make_existing_1strat <- function(n = 240L, seed = 1L, mean = 0.006, sd = 0.035) {
  set.seed(seed)
  matrix(rnorm(n, mean = mean, sd = sd), nrow = n, ncol = 1L,
         dimnames = list(NULL, "strat_a"))
}

.make_admit_candidate <- function(existing_1strat, seed = 42L) {
  set.seed(seed)
  x <- existing_1strat[, 1]
  -0.3 * (x - mean(x)) + 0.012 + rnorm(length(x), sd = 0.03)
}

# Near-duplicate candidate (rho ~ 0.998 vs strat_a) on a short (5yr) 2-strategy
# existing set. Verified: similarity fails, incremental_sharpe fails,
# diversification_ew fails, detection_power fails (short sample) -> "reject".
.make_existing_2strat <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  matrix(
    c(rnorm(n, mean = 0.006, sd = 0.04), rnorm(n, mean = 0.004, sd = 0.03)),
    nrow = n, ncol = 2L, dimnames = list(NULL, c("strat_a", "strat_b"))
  )
}

.make_near_dup_candidate <- function(existing, seed = 7L) {
  set.seed(seed)
  0.97 * existing[, 1] + rnorm(nrow(existing), sd = 0.002)
}

# Pure noise candidate on a short (5yr) 1-strategy existing set. Verified:
# similarity passes (rho ~ 0.20), incremental_sharpe fails (negative),
# diversification_ew passes, detection_power is "n_a" (candidate's own
# Sharpe is negative -- no positive effect to test) -> overall "mixed"
# (a determinate result: some checks pass, some fail/n_a, none NA).
.make_noise_existing <- function(n = 60L, seed = 1L) {
  set.seed(seed)
  matrix(rnorm(n, mean = 0.006, sd = 0.035), nrow = n, ncol = 1L,
         dimnames = list(NULL, "strat_a"))
}

.make_noise_candidate <- function(n = 60L, seed = 99L) {
  set.seed(seed)
  rnorm(n, mean = 0, sd = 0.04)
}

# A completely flat (zero-variance) existing column makes cor() return NA
# for every entry, which makes BOTH similarity and incremental_sharpe
# uncomputable -- this is the "indeterminate" fixture.
.make_flat_existing <- function(n = 60L) {
  matrix(rep(0.01, n), nrow = n, ncol = 1L, dimnames = list(NULL, "flat"))
}

.make_flat_candidate <- function(n = 60L, seed = 5L) {
  set.seed(seed)
  rnorm(n, mean = 0.01, sd = 0.02)
}

# ---- Test 1: strong anti-correlated candidate, long sample -> "admit" ------
test_that("strong anti-correlated candidate with a 20yr sample yields 'admit'", {
  existing  <- .make_existing_1strat()
  candidate <- .make_admit_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate, existing, candidate_name = "anti_corr", periods_per_year = 12L
  )

  expect_equal(attr(result, "overall"), "admit")
  expect_equal(attr(result, "verdict_reason"), character())
  expect_equal(attr(result, "candidate_name"), "anti_corr")
  expect_type(attr(result, "detection_power"), "list")

  sim_row <- result[result$check == "similarity", ]
  expect_equal(as.character(sim_row$verdict), "pass")
  expect_lt(sim_row$value, 0.80)

  dp_row <- result[result$check == "detection_power", ]
  expect_equal(as.character(dp_row$verdict), "pass")
  expect_gt(dp_row$value, 0)
})

# ---- Test 2: near-duplicate candidate, short sample -> "reject" ------------
test_that("near-duplicate candidate on a short sample yields 'reject'", {
  existing  <- .make_existing_2strat()
  candidate <- .make_near_dup_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate, existing, candidate_name = "near_dup",
    corr_threshold = 0.80, periods_per_year = 12L
  )

  sim_row <- result[result$check == "similarity", ]
  expect_equal(as.character(sim_row$verdict), "fail")

  is_row  <- result[result$check == "incremental_sharpe", ]
  div_row <- result[result$check == "diversification_ew", ]
  dp_row  <- result[result$check == "detection_power", ]
  expect_equal(as.character(is_row$verdict),  "fail")
  expect_equal(as.character(div_row$verdict), "fail")
  expect_equal(as.character(dp_row$verdict),  "fail")

  expect_equal(attr(result, "overall"), "reject")
})

# ---- Test 3: noise candidate -> "mixed" (determinate, not "admit") ---------
test_that("noise candidate yields 'mixed', never 'admit', never 'indeterminate'", {
  existing  <- .make_noise_existing()
  candidate <- .make_noise_candidate(n = nrow(existing))

  result <- hd_strategy_value_gate(
    candidate, existing, candidate_name = "noise", periods_per_year = 12L
  )

  expect_equal(attr(result, "overall"), "mixed")
  expect_equal(attr(result, "verdict_reason"), character())

  dp_row <- result[result$check == "detection_power", ]
  expect_equal(as.character(dp_row$verdict), "n_a")
  expect_lt(dp_row$value, 0)
})

# ---- Test 4: degenerate input -> "indeterminate" (never "mixed"/"reject") --
test_that("a check that cannot be computed yields 'indeterminate', distinct from 'mixed'/'reject'", {
  existing  <- .make_flat_existing()
  candidate <- .make_flat_candidate(n = nrow(existing))

  # Two warnings fire here: cor()'s own "standard deviation is zero" (an R
  # base warning we don't own) and the gate's "indeterminate" cli_warn.
  # Capture both explicitly rather than letting the unmatched one leak into
  # the test run as an uncaptured WARNING.
  warns <- character()
  result <- withCallingHandlers(
    hd_strategy_value_gate(
      candidate, existing, candidate_name = "flatcol", periods_per_year = 12L
    ),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("indeterminate", warns)))

  expect_equal(attr(result, "overall"), "indeterminate")
  expect_setequal(attr(result, "verdict_reason"), c("similarity", "incremental_sharpe"))

  sim_row <- result[result$check == "similarity", ]
  is_row  <- result[result$check == "incremental_sharpe", ]
  expect_equal(as.character(sim_row$verdict), "na")
  expect_equal(as.character(is_row$verdict),  "na")
  expect_true(is.na(sim_row$value))
  expect_false(is.infinite(sim_row$value))
})

# ---- Test 5: Verdict tibble schema -----------------------------------------
test_that("result tibble has exact columns, 7 rows, and factor levels incl. 'n_a'", {
  existing  <- .make_existing_1strat()
  candidate <- .make_admit_candidate(existing)

  result <- hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)

  expect_s3_class(result, "tbl_df")
  expect_named(result, c("check", "metric", "value", "threshold", "verdict"))
  expect_s3_class(result$verdict, "factor")
  expect_equal(levels(result$verdict), c("pass", "fail", "flag", "na", "n_a"))
  expect_equal(nrow(result), 7L)

  expect_setequal(result$check, c(
    "similarity", "incremental_sharpe",
    "diversification_ew", "diversification_gmv", "detection_power",
    "crowding", "robustness"
  ))

  # crowding and robustness with no input -> "na"
  expect_equal(as.character(result[result$check == "crowding",   "verdict"][[1]]), "na")
  expect_equal(as.character(result[result$check == "robustness", "verdict"][[1]]), "na")
})

# ---- Test 6: Advisory -- failing candidate returns tibble, never errors ----
test_that("a reject-quality candidate returns a tibble, not an error", {
  existing  <- .make_existing_2strat()
  candidate <- .make_near_dup_candidate(existing)

  result <- expect_no_error(
    hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)
  )
  expect_s3_class(result, "tbl_df")
  expect_true(attr(result, "overall") %in% c("admit", "mixed", "reject", "indeterminate"))
})

# ---- Test 7: crowding flag --------------------------------------------------
test_that("crowding = TRUE yields 'flag' verdict", {
  existing  <- .make_existing_1strat()
  candidate <- .make_admit_candidate(existing)

  result <- hd_strategy_value_gate(
    candidate, existing, crowding = TRUE, periods_per_year = 12L
  )
  crowd_row <- result[result$check == "crowding", ]
  expect_equal(as.character(crowd_row$verdict), "flag")
})

# ---- Test 8: corr_threshold defaults to the canonical constant ------------
test_that("default corr_threshold is HD_REDUNDANCY_THRESH (single source of truth)", {
  expect_equal(formals(hd_strategy_value_gate)$corr_threshold, quote(HD_REDUNDANCY_THRESH))
  expect_equal(HD_REDUNDANCY_THRESH, 0.80)
})

# ---- Test 9: detection_power "n_a" for non-positive candidate Sharpe -------
test_that("detection_power is 'n_a' (not 'na') when the candidate's own Sharpe is non-positive", {
  existing  <- .make_noise_existing()
  candidate <- .make_noise_candidate(n = nrow(existing))

  result <- hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)
  dp_row <- result[result$check == "detection_power", ]

  # "n_a" (not applicable -- a legitimate, determinate non-positive-effect
  # state) must NOT be confused with "na" (could not compute at all).
  expect_equal(as.character(dp_row$verdict), "n_a")
  expect_false(as.character(dp_row$verdict) == "na")
})

# ---- Test 10: Input-validation snapshot: non-numeric candidate -------------
test_that("non-numeric candidate triggers cli_abort", {
  existing <- .make_existing_2strat()
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate("not_a_vector", existing)
  )
})

# ---- Test 11: Input-validation snapshot: non-numeric existing --------------
test_that("non-numeric existing triggers cli_abort", {
  existing  <- .make_existing_1strat()
  candidate <- .make_admit_candidate(existing)
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate(candidate, "not_a_matrix")
  )
})

# ---- Test 12: Input-validation snapshot: no overlapping complete rows ------
test_that("candidate all-NA yields cli_abort for no overlapping rows", {
  existing  <- .make_existing_2strat(n = 5L)
  candidate <- rep(NA_real_, 5L)
  expect_snapshot(
    error = TRUE,
    hd_strategy_value_gate(candidate, existing)
  )
})

# ---- Test 13: Function signature stability ---------------------------------
test_that("hd_strategy_value_gate() signature is stable (catches API drift)", {
  expect_snapshot(args(hd_strategy_value_gate))
})
