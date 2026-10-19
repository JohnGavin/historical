# Tests for hd_deflated_sharpe() — variance-aware hurdle (#558)
#
# #558's complaint: the pre-existing E[max SR] hurdle depended only on
# K_trials (the trial COUNT), never on the DISPERSION of the trial Sharpes
# (V). A pool containing low-trade "junk" strategies has a wide Sharpe
# dispersion and a correspondingly higher honest hurdle, even at identical
# K_trials -- the "junk-variance trap" the two source articles (rulyfi.com)
# demonstrate with an identical Bollinger strategy scoring DSR 0.03 in a
# noisy pool vs 0.92 after dropping two junk indicators.
#
# These tests establish: (1) trial_sharpe_var = 1 (the default) reproduces
# pre-#558 output exactly for every K_trials -- "nothing breaks"; (2) raising
# trial_sharpe_var for the SAME underlying returns widens the hurdle and so
# lowers dsr / raises dsr_pvalue -- the qualitative flip the issue asks for.

test_that("trial_sharpe_var defaults to 1 and is echoed in the return list", {
  set.seed(1)
  r <- stats::rnorm(100, mean = 0.001, sd = 0.01)
  out <- hd_deflated_sharpe(r, K_trials = 5L, ann_factor = 252L)
  expect_identical(out$trial_sharpe_var, 1)
})

test_that("trial_sharpe_var = 1 reproduces the pre-#558 (unit-variance) hurdle exactly", {
  # Same formula, computed inline, pre-#558 (no V scaling)
  legacy_dsr <- function(r, K_trials, ann_factor) {
    r <- r[!is.na(r)]
    T_obs <- length(r)
    mu <- mean(r); sigma <- stats::sd(r)
    sr <- if (sigma > 0) mu / sigma else 0
    naive_sr <- sr * sqrt(ann_factor)
    n <- T_obs
    m3 <- sum((r - mu)^3) / n / sigma^3
    m4 <- sum((r - mu)^4) / n / sigma^4
    ek <- m4 - 3
    var_sr <- (1 - m3 * sr + (m4 - 1) / 4 * sr^2) / T_obs
    if (K_trials > 1L) {
      # #931: the benchmark E[max of K iid N(0,1)] is now the EXACT value,
      # K * int x phi(x) Phi(x)^(K-1) dx, not the old closed-form
      # approximation z - (gamma + log(pi/2)) / (2z), which overstated it by
      # 9-31%. Computed here independently of hd_expected_max_normal().
      emax <- stats::integrate(
        function(x) K_trials * x * stats::dnorm(x) * stats::pnorm(x)^(K_trials - 1),
        lower = -40, upper = 40, rel.tol = 1e-12, subdivisions = 2000L
      )$value
      e_max_sr <- emax / sqrt(T_obs)
    } else {
      e_max_sr <- 0
    }
    se_sr <- sqrt(max(var_sr, .Machine$double.eps))
    dsr_stat <- (sr - e_max_sr) / se_sr
    dsr_ann <- dsr_stat * sqrt(ann_factor / T_obs)
    dsr_ann
  }

  set.seed(2)
  r <- stats::rnorm(240, mean = 0.0008, sd = 0.012)
  for (K in c(1L, 2L, 5L, 20L, 100L)) {
    got <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 1)
    want <- legacy_dsr(r, K, 252L)
    expect_equal(got$dsr, want, tolerance = 1e-10)
  }
})

test_that("K_trials = 1 gives zero hurdle regardless of trial_sharpe_var", {
  set.seed(3)
  r <- stats::rnorm(120, mean = 0.001, sd = 0.01)
  d1 <- hd_deflated_sharpe(r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 1)
  d9 <- hd_deflated_sharpe(r, K_trials = 1L, ann_factor = 252L, trial_sharpe_var = 9)
  expect_equal(d1$dsr, d9$dsr)
})

test_that("junk-variance trap: same returns, wider trial-pool variance lowers DSR and raises its p-value", {
  set.seed(4)
  r <- stats::rnorm(500, mean = 0.001, sd = 0.01)
  K <- 100L

  clean_pool <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 1)
  junk_pool  <- hd_deflated_sharpe(r, K_trials = K, ann_factor = 252L, trial_sharpe_var = 9)

  # Same K_trials, same underlying returns -- only the trial-pool dispersion
  # differs. The wider (junkier) pool must produce a MORE conservative
  # verdict: lower deflated Sharpe, higher (less significant) p-value.
  expect_lt(junk_pool$dsr, clean_pool$dsr)
  expect_gt(junk_pool$dsr_pvalue, clean_pool$dsr_pvalue)

  # Everything upstream of the hurdle (naive Sharpe, moments, T) is
  # unaffected by V -- only the deflation itself moves.
  expect_equal(junk_pool$naive_sharpe, clean_pool$naive_sharpe)
  expect_equal(junk_pool$T, clean_pool$T)
})

test_that("larger trial_sharpe_var monotonically widens the hurdle (dsr is non-increasing in V)", {
  set.seed(5)
  r <- stats::rnorm(300, mean = 0.0015, sd = 0.009)
  vs <- c(1, 2, 4, 8, 16)
  dsrs <- vapply(vs, function(v) {
    hd_deflated_sharpe(r, K_trials = 50L, ann_factor = 252L, trial_sharpe_var = v)$dsr
  }, numeric(1))
  expect_true(all(diff(dsrs) <= 0))
})

test_that("input validation: non-positive trial_sharpe_var aborts with informative message", {
  r <- stats::rnorm(50)
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 0))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = -1))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = NA_real_))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = Inf))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = c(1, 2)))
})

test_that("short series (T < 10) returns NA list including trial_sharpe_var echo, no error", {
  out <- hd_deflated_sharpe(c(0.01, -0.02, 0.005), K_trials = 5L, trial_sharpe_var = 3)
  expect_true(is.na(out$dsr))
  expect_identical(out$trial_sharpe_var, 3)
})

test_that("function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_deflated_sharpe))
})

# ── #959: two named conventions for V, defaults unchanged ──────────────────

# Independent reference: the DSR given an explicit per-period hurdle.
ref_dsr_from_hurdle <- function(r, hurdle, ann_factor) {
  T_obs <- length(r)
  mu <- mean(r); sigma <- stats::sd(r)
  sr <- mu / sigma
  m3 <- sum((r - mu)^3) / T_obs / sigma^3
  m4 <- sum((r - mu)^4) / T_obs / sigma^4
  var_sr <- (1 - m3 * sr + (m4 - 1) / 4 * sr^2) / T_obs
  (sr - hurdle) / sqrt(var_sr) * sqrt(ann_factor / T_obs)
}

test_that("default-call outputs are byte-identical to origin/main (#959 regression)", {
  # Recorded by running the unmodified origin/main hd_deflated_sharpe() on
  # this exact input (dc587cd), printed with %.17g so they round-trip exactly.
  # Compared as 17-significant-digit strings: R's parser does not round-trip
  # 17-digit literals, but sprintf("%.17g") does, so a string match is exact.
  fmt17 <- function(x) sprintf("%.17g", x)
  set.seed(959)
  r <- stats::rnorm(500, mean = 0.0004, sd = 0.01)
  cases <- list(
    list(K = 1L,  ann = 252L, V = 1,   dsr = "0.71897876228969726",
         p = "0.15559060655486756", naive = "0.71974263680213801",
         haircut = "0.1061316189123751"),
    list(K = 5L,  ann = 252L, V = 1,   dsr = "-0.10576786410487299",
         p = "0.55921671331936518", naive = "0.71974263680213801",
         haircut = "114.69523392067006"),
    list(K = 50L, ann = 252L, V = 1,   dsr = "-0.87601053480007662",
         p = "0.89138737809064728", naive = "0.71974263680213801",
         haircut = "221.71163552186474"),
    list(K = 5L,  ann = 252L, V = 9,   dsr = "-1.7552611168940133",
         p = "0.99329036323451569", naive = "0.71974263680213801",
         haircut = "343.87343852418542"),
    list(K = 20L, ann = 12L,  V = 2.5, dsr = "-0.30005658741776464",
         p = "0.97361858354097985", naive = "0.15706071971585267",
         haircut = "291.04495889272238")
  )
  for (cs in cases) {
    got <- hd_deflated_sharpe(r, K_trials = cs$K, ann_factor = cs$ann,
                              trial_sharpe_var = cs$V)
    expect_identical(fmt17(got$dsr), cs$dsr)
    expect_identical(fmt17(got$dsr_pvalue), cs$p)
    expect_identical(fmt17(got$naive_sharpe), cs$naive)
    expect_identical(fmt17(got$haircut_pct), cs$haircut)
    expect_identical(got$hurdle_convention, "multiplier")
  }
  # The default call (no V argument) equals the explicit V = 1 call.
  keep <- c("dsr", "dsr_pvalue", "haircut_pct")
  expect_identical(
    hd_deflated_sharpe(r, K_trials = 5L)[keep],
    hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 1)[keep]
  )
})

test_that("trial_sharpe_var_stat: hurdle = E[max Z] * sqrt(V), hand-computed", {
  set.seed(959)
  r <- stats::rnorm(500, mean = 0.0004, sd = 0.01)
  # K = 2: E[max of 2 iid N(0,1)] = 1/sqrt(pi) (closed form).
  V <- 0.0004                         # per-period Sharpe variance (sd 0.02)
  hurdle <- (1 / sqrt(pi)) * sqrt(V)  # 0.5641896 * 0.02 = 0.01128379
  expect_equal(hurdle, 0.011283791670955126, tolerance = 1e-12)
  got <- hd_deflated_sharpe(r, K_trials = 2L, ann_factor = 252L,
                            trial_sharpe_var_stat = V)
  expect_equal(got$dsr, ref_dsr_from_hurdle(r, hurdle, 252L), tolerance = 1e-8)
  expect_identical(got$hurdle_convention, "statistic-units")
  expect_identical(got$trial_sharpe_var_stat, V)
  expect_identical(got$trial_sharpe_var, 1)
})

test_that("supplying both V arguments aborts with a classed error", {
  r <- stats::rnorm(50)
  expect_error(
    hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 4,
                       trial_sharpe_var_stat = 0.01),
    class = "hd_deflated_sharpe_conflicting_v"
  )
  expect_snapshot(
    error = TRUE,
    hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 4,
                       trial_sharpe_var_stat = 0.01)
  )
  # An explicit trial_sharpe_var = 1 is the default, so it is allowed.
  expect_no_error(
    hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var = 1,
                       trial_sharpe_var_stat = 0.01)
  )
})

test_that("trial_sharpe_var_stat input validation", {
  r <- stats::rnorm(50)
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = 0))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = NA_real_))
  expect_snapshot(error = TRUE, hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = c(1, 2)))
  expect_error(hd_deflated_sharpe(r, K_trials = 5L, trial_sharpe_var_stat = -1),
               class = "hd_deflated_sharpe_bad_v_stat")
})

test_that("the two conventions agree exactly when V_stat = V_mult / T_obs, and differ otherwise", {
  set.seed(959)
  r <- stats::rnorm(500, mean = 0.0004, sd = 0.01)
  T_obs <- length(r)
  V_mult <- 9
  a <- hd_deflated_sharpe(r, K_trials = 20L, ann_factor = 252L,
                          trial_sharpe_var = V_mult)
  b <- hd_deflated_sharpe(r, K_trials = 20L, ann_factor = 252L,
                          trial_sharpe_var_stat = V_mult / T_obs)
  expect_equal(b$dsr, a$dsr, tolerance = 1e-12)
  expect_equal(b$dsr_pvalue, a$dsr_pvalue, tolerance = 1e-12)
  expect_identical(a$hurdle_convention, "multiplier")
  expect_identical(b$hurdle_convention, "statistic-units")
  # The same number in the other slot is a different (much larger) hurdle.
  same_number <- hd_deflated_sharpe(r, K_trials = 20L, ann_factor = 252L,
                                    trial_sharpe_var_stat = V_mult)
  expect_lt(same_number$dsr, a$dsr - 1)
  # K = 1 keeps a zero hurdle under both conventions.
  k1m <- hd_deflated_sharpe(r, K_trials = 1L, trial_sharpe_var = 9)
  k1s <- hd_deflated_sharpe(r, K_trials = 1L, trial_sharpe_var_stat = 9)
  expect_identical(k1s$dsr, k1m$dsr)
})

test_that("short series (T < 10) echoes the convention and V_stat, no error", {
  out <- hd_deflated_sharpe(c(0.01, -0.02, 0.005), K_trials = 5L,
                            trial_sharpe_var_stat = 0.01)
  expect_true(is.na(out$dsr))
  expect_identical(out$hurdle_convention, "statistic-units")
  expect_identical(out$trial_sharpe_var_stat, 0.01)
})
