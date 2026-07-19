testthat::local_edition(3)

# Regression tests for #569: peak_value was set equal to final_value in
# R/plan_falsification.R's fals_results_db target, which understates the
# true historical high-water mark for any strategy in a drawdown at the end
# of the sample.
#
# The fix computes peak_value from the return series inside the local
# compute_drawdowns() closure (peak <- cummax(cumprod(1 + ret)); the last
# element of peak is the overall running maximum, i.e. max(cum)).
#
# compute_drawdowns() is an inline closure defined inside a tar_target()
# body (R/plan_falsification.R), not an exported function. Following the
# pattern used in test-plan-factormax.R, we reproduce the fixed logic here
# to regression-test the guarantee.

# ── Helper: compute_drawdowns (extracted from plan_falsification.R,
#    fals_results_db target, post-#569 fix) ─────────────────────────────

compute_drawdowns_extracted <- function(ret) {
  ret <- ret[!is.na(ret)]
  if (length(ret) == 0L) {
    return(list(max_dd = NA_real_, avg_dd = NA_real_,
                max_dd_duration_days = NA_integer_,
                avg_dd_duration_obs  = NA_real_,
                n_drawdowns = NA_integer_,
                recovery_days = NA_integer_,
                peak_value = NA_real_))
  }
  cum  <- cumprod(1 + ret)
  peak <- cummax(cum)
  dd   <- (cum - peak) / peak

  peak_value <- peak[length(peak)]

  max_dd <- min(dd, na.rm = TRUE)

  in_dd  <- dd < -0.01
  rle_dd  <- rle(in_dd)
  dd_runs <- rle_dd$lengths[rle_dd$values]
  n_drawdowns <- length(dd_runs)
  avg_dd <- if (any(in_dd)) mean(dd[in_dd], na.rm = TRUE) else NA_real_

  max_dd_duration <- if (n_drawdowns > 0L) as.integer(max(dd_runs)) else NA_integer_
  avg_dd_duration <- if (n_drawdowns > 0L) mean(dd_runs) else NA_real_

  trough_idx <- which.min(dd)
  recovery_obs <- NA_integer_
  if (!is.na(trough_idx) && trough_idx < length(dd)) {
    post_trough <- dd[(trough_idx + 1L):length(dd)]
    rec_rel <- which(post_trough >= -0.001)[1L]
    if (!is.na(rec_rel)) recovery_obs <- as.integer(rec_rel)
  }

  list(
    max_dd               = max_dd,
    avg_dd               = avg_dd,
    max_dd_duration_obs  = max_dd_duration,
    avg_dd_duration_obs  = avg_dd_duration,
    n_drawdowns          = as.integer(n_drawdowns),
    recovery_obs         = recovery_obs,
    peak_value           = peak_value
  )
}

# ── F1: peak_value differs from final_value when the curve peaked and
#    then declined before the end of the sample (the bug this fixes) ─────

test_that("peak_value: exceeds final_value for a strategy in a drawdown at period end (regression #569)", {
  # Equity rises 20%, then gives back half of it, ending in a drawdown.
  ret <- c(0.05, 0.05, 0.05, 0.05, -0.03, -0.03, -0.03, -0.03, -0.02, -0.02)
  dd <- compute_drawdowns_extracted(ret)

  final_value <- prod(1 + ret)
  expect_gt(dd$peak_value, final_value)

  # The buggy code set peak_value <- final_value exactly. Confirm the fixed
  # value is materially different (not just floating point noise).
  expect_gt(dd$peak_value - final_value, 1e-6)
})

# ── F2: peak_value equals final_value when the curve never draws down
#    (monotonically increasing equity — the one case where the old
#    approximation was accidentally correct) ──────────────────────────

test_that("peak_value: equals final_value for a monotonically increasing equity curve", {
  ret <- rep(0.01, 10L)
  dd <- compute_drawdowns_extracted(ret)

  final_value <- prod(1 + ret)
  expect_equal(dd$peak_value, final_value, tolerance = 1e-10)
})

# ── F3: peak_value is always >= final_value (running high-water mark is
#    never below the final value; property test across random series) ───

test_that("peak_value: is always >= final_value (running max property)", {
  set.seed(569)
  for (i in 1:20) {
    ret <- rnorm(50, mean = 0, sd = 0.02)
    dd <- compute_drawdowns_extracted(ret)
    final_value <- prod(1 + ret)
    expect_gte(dd$peak_value, final_value - 1e-10)
  }
})

# ── F4: peak_value matches an independently computed max(cummax(cumprod)) ─

test_that("peak_value: matches max(cummax(cumprod(1 + ret))) independently", {
  ret <- c(0.02, -0.01, 0.03, -0.05, 0.01, 0.04, -0.02, 0.01, -0.03, 0.02)
  dd <- compute_drawdowns_extracted(ret)

  expected <- max(cummax(cumprod(1 + ret)))
  expect_equal(dd$peak_value, expected, tolerance = 1e-10)
})

# ── F5: empty return series yields NA peak_value (consumers must tolerate) ─

test_that("peak_value: NA for empty return series", {
  dd <- compute_drawdowns_extracted(numeric(0))
  expect_true(is.na(dd$peak_value))
})
