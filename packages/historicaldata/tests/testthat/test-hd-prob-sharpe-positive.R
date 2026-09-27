# Tests for hd_prob_sharpe_positive() -- probabilistic Sharpe ratio, P(true
# Sharpe > benchmark) (#851).
#
# #851's premise (see the issue and .claude/rules/detection-power-required.md):
# hd_detection_power() answers "is the sample long enough to detect this
# effect if it's real" (a PROSPECTIVE, frequentist power question).
# hd_prob_sharpe_positive() answers a DIFFERENT question: "given the sample
# we have, how confident are we the true Sharpe exceeds a benchmark" (a
# RETROSPECTIVE probability statement) -- the "Probabilistic Sharpe Ratio"
# (PSR) of Bailey & Lopez de Prado.
#
# REUSE, not re-derivation: this function's variance formula is the EXACT
# same Lo (2002) / Mertens (2002) asymptotic Sharpe-ratio variance already
# implemented by hd_deflated_sharpe()'s `var_sr` line (and referenced in
# hd_detection_power()'s own roxygen "Derivation" section) -- see the
# "reuses hd_deflated_sharpe()'s variance formula exactly" test below, which
# proves this by direct numerical comparison against hd_deflated_sharpe(),
# not merely by both functions citing the same paper.

test_that("with normal-returns defaults (skewness=0, kurtosis=0), matches an independently recomputed value using hd_detection_power()'s own c1 formula", {
  # hd_detection_power()'s roxygen documents the normal-returns simplification
  # Var(SR) ~= (1 + SR^2/2) / T -- i.e. c1^2 / T. With skewness = 0 and
  # (excess) kurtosis = 0, hd_prob_sharpe_positive()'s general
  # Lo/Mertens formula (1 - skew*SR + (kurtosis_raw - 1)/4 * SR^2) / T must
  # collapse to EXACTLY this, since kurtosis_raw = kurtosis + 3 = 3.
  sharpe_annual <- 0.6
  n_obs <- 84
  ann_factor <- 12
  sr_period <- sharpe_annual / sqrt(ann_factor)
  c1 <- sqrt(1 + 0.5 * sr_period^2)
  expected_prob <- stats::pnorm(sr_period / (c1 / sqrt(n_obs)))

  out <- hd_prob_sharpe_positive(sharpe_annual, n_obs = n_obs, ann_factor = ann_factor)
  expect_equal(out$prob_sharpe_positive, expected_prob, tolerance = 1e-9)
})

test_that("reuses hd_deflated_sharpe()'s variance formula exactly (K_trials = 1, benchmark = 0)", {
  set.seed(851)
  r <- rnorm(300, mean = 0.001, sd = 0.02) + rgamma(300, shape = 2, rate = 10) / 100
  d <- hd_deflated_sharpe(r, K_trials = 1L, ann_factor = 252L)

  out <- hd_prob_sharpe_positive(
    sharpe_annual = d$naive_sharpe, n_obs = d$T, ann_factor = 252L,
    skewness = d$skewness, kurtosis = d$kurtosis
  )

  # hd_deflated_sharpe()'s dsr_pvalue is P(SR <= E[max SR]); at K_trials = 1,
  # E[max SR] = 0, so 1 - dsr_pvalue IS P(SR > 0) computed from the SAME
  # var_sr line this function reuses -- must match to numerical precision.
  expect_equal(out$prob_sharpe_positive, 1 - d$dsr_pvalue, tolerance = 1e-9)
})

test_that("negative observed Sharpe is computable and yields a low probability (unlike hd_detection_power, which requires sharpe_annual > 0)", {
  out <- hd_prob_sharpe_positive(sharpe_annual = -0.3, n_obs = 60, ann_factor = 12)
  expect_true(is.finite(out$prob_sharpe_positive))
  expect_lt(out$prob_sharpe_positive, 0.5)
})

test_that("zero observed Sharpe gives exactly 50% probability at benchmark = 0", {
  out <- hd_prob_sharpe_positive(sharpe_annual = 0, n_obs = 60, ann_factor = 12)
  expect_equal(out$prob_sharpe_positive, 0.5, tolerance = 1e-9)
})

test_that("larger observed Sharpe with the same sample gives a higher probability (monotonicity)", {
  low  <- hd_prob_sharpe_positive(sharpe_annual = 0.2, n_obs = 60, ann_factor = 12)
  high <- hd_prob_sharpe_positive(sharpe_annual = 0.8, n_obs = 60, ann_factor = 12)
  expect_gt(high$prob_sharpe_positive, low$prob_sharpe_positive)
})

test_that("longer sample with the same Sharpe gives a higher probability (monotonicity)", {
  short <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 24, ann_factor = 12)
  long  <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 240, ann_factor = 12)
  expect_gt(long$prob_sharpe_positive, short$prob_sharpe_positive)
})

test_that("pvalue is exactly 1 - prob_sharpe_positive", {
  out <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 12)
  expect_equal(out$pvalue, 1 - out$prob_sharpe_positive, tolerance = 1e-12)
})

test_that("reason is NA_character_ on a normal, computable call", {
  out <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 12)
  expect_true(is.na(out$reason))
})

test_that("n_obs < 10 is non-computable: returns NA with a stated reason, never a silent default or 0.5", {
  out <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 9, ann_factor = 12)
  expect_true(is.na(out$prob_sharpe_positive))
  expect_true(is.na(out$pvalue))
  expect_false(is.na(out$reason))
  expect_match(out$reason, "n_obs")
})

test_that("degenerate (non-positive) estimated variance is non-computable: NA with a stated reason", {
  # kurtosis = -2 is the theoretical floor (any distribution); combined with
  # a large skewness*sr_period term this can drive the Lo/Mertens variance
  # non-positive -- a legitimate edge case the formula itself flags, not a
  # bug to silently paper over.
  out <- hd_prob_sharpe_positive(
    sharpe_annual = 3, n_obs = 60, ann_factor = 12,
    skewness = 50, kurtosis = -2
  )
  expect_true(is.na(out$prob_sharpe_positive))
  expect_false(is.na(out$reason))
})

# ── Input validation (fail-loud-not-null.md) ────────────────────────────────

test_that("non-numeric/non-finite sharpe_annual aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = NA_real_, n_obs = 60))
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = Inf, n_obs = 60))
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = c(0.1, 0.2), n_obs = 60))
})

test_that("n_obs < 2 aborts (distinct from the n_obs < 10 NA-with-reason path)", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 1))
})

test_that("non-positive ann_factor aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 0))
})

test_that("non-finite skewness aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, skewness = NA_real_))
})

test_that("kurtosis below the theoretical floor (-2) aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, kurtosis = -3))
})

test_that("non-finite benchmark_annual aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, benchmark_annual = NA_real_))
})

test_that("n_tests < 1 aborts", {
  expect_snapshot(error = TRUE, hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, n_tests = 0))
})

test_that("invalid correction value aborts via match.arg", {
  expect_error(
    hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, correction = "holm"),
    "should be one of"
  )
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_prob_sharpe_positive))
})

# ── Multiple-testing correction (n_tests / correction, consistent with
# hd_detection_power()'s #905 API) ──────────────────────────────────────────
#
# Unlike hd_detection_power()'s alpha-tightening Bonferroni, this function
# corrects the P-VALUE directly (pvalue_corrected = min(1, pvalue * n_tests),
# the standard Bonferroni p-value adjustment) -- the natural analogue when the
# reported object IS a probability rather than a sample-size requirement. See
# the function's own roxygen "Multiple-testing correction" section for the
# full rationale, including why hd_deflated_sharpe()'s existing K_trials
# benchmark-shift mechanism (a DIFFERENT, already-implemented correction) is
# not reused here.

test_that("default n_tests = 1 / correction = 'none' leaves the corrected fields identical to the uncorrected ones", {
  out <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 12)
  expect_equal(out$n_tests, 1)
  expect_equal(out$correction, "none")
  expect_equal(out$pvalue_corrected, out$pvalue)
  expect_equal(out$prob_sharpe_positive_corrected, out$prob_sharpe_positive)
})

test_that("n_tests = 1 with correction = 'bonferroni' also reproduces the uncorrected value exactly (falsification)", {
  out <- hd_prob_sharpe_positive(
    sharpe_annual = 0.5, n_obs = 60, ann_factor = 12,
    n_tests = 1, correction = "bonferroni"
  )
  expect_equal(out$prob_sharpe_positive_corrected, out$prob_sharpe_positive, tolerance = 1e-12)
  expect_equal(out$pvalue_corrected, out$pvalue, tolerance = 1e-12)
})

test_that("correction = 'none' ignores n_tests entirely, even when n_tests > 1", {
  out <- hd_prob_sharpe_positive(
    sharpe_annual = 0.5, n_obs = 60, ann_factor = 12,
    n_tests = 18, correction = "none"
  )
  expect_equal(out$prob_sharpe_positive_corrected, out$prob_sharpe_positive)
})

test_that("bonferroni correction with n_tests > 1 never increases the reported probability (monotonicity)", {
  out_1  <- hd_prob_sharpe_positive(sharpe_annual = 0.5, n_obs = 60, ann_factor = 12)
  out_18 <- hd_prob_sharpe_positive(
    sharpe_annual = 0.5, n_obs = 60, ann_factor = 12,
    n_tests = 18, correction = "bonferroni"
  )
  expect_lte(out_18$prob_sharpe_positive_corrected, out_1$prob_sharpe_positive)
})

test_that("bonferroni pvalue_corrected matches an independently recomputed value and is capped at 1", {
  out <- hd_prob_sharpe_positive(
    sharpe_annual = 0.05, n_obs = 40, ann_factor = 12,
    n_tests = 50, correction = "bonferroni"
  )
  expect_equal(out$pvalue_corrected, min(1, out$pvalue * 50), tolerance = 1e-9)
  expect_lte(out$pvalue_corrected, 1)
  expect_gte(out$prob_sharpe_positive_corrected, 0)
})
