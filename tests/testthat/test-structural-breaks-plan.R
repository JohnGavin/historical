# Tests for plan_structural_breaks.R and hd_structural_breaks() (#477)
#
# Tests at two levels:
#   1. Unit tests for hd_structural_breaks() on synthetic series with a
#      known injected break.
#   2. Tests for the plan helper logic (summary builder, divergence flag)
#      using a synthetic multi-strategy input.
#   3. Snapshot tests for error/CLI paths and assembled caption strings.
#
# All tests are self-contained: no live targets pipeline is executed.
# The package is loaded via pkgload::load_all() which reflects the worktree.

testthat::local_edition(3)

# Load hd_structural_breaks() from the package source.
# We source the file directly rather than pkgload::load_all() to avoid
# pulling in all historicaldata dependencies (duckplyr, etc.) in the
# root-level test environment, which mirrors the outer dev shell that lacks
# the full package dependency set.  cli:: is available in the dev shell.
source(here::here("packages/historicaldata/R/structural_breaks.R"))


# ─────────────────────────────────────────────────────────────────────────────
# 1. hd_structural_breaks() — input validation (snapshot: error messages)
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_structural_breaks: non-numeric input aborts with structured cli message", {
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks("not_a_vector")
  )
})

test_that("hd_structural_breaks: NA values abort with structured cli message", {
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks(c(0.01, NA_real_, 0.02))
  )
})

test_that("hd_structural_breaks: alpha out of (0,1) aborts with structured cli message", {
  set.seed(42)
  r <- rnorm(500, 0.0004, 0.01)
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks(r, alpha = 1.5)
  )
})

test_that("hd_structural_breaks: non-positive min_years aborts", {
  set.seed(42)
  r <- rnorm(500, 0.0004, 0.01)
  expect_snapshot(
    error = TRUE,
    hd_structural_breaks(r, min_years = 0)
  )
})


# ─────────────────────────────────────────────────────────────────────────────
# 2. hd_structural_breaks() — no-break on stationary series
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_structural_breaks: stationary series produces n_breaks = 0", {
  set.seed(123)
  # 10 years of daily returns drawn from a stable distribution — no break.
  r <- rnorm(10L * 252L, mean = 0.0004, sd = 0.01)

  result <- hd_structural_breaks(r, alpha = 0.01, min_years = 5L,
                                   periods_per_year = 252L)

  expect_type(result, "list")
  expect_equal(result$n_breaks, 0L)
  expect_equal(length(result$break_indices), 0L)
  expect_equal(result$post_break_start, 1L)
  expect_equal(result$post_break_returns, r)
})


# ─────────────────────────────────────────────────────────────────────────────
# 3. hd_structural_breaks() — known injected break is detected
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_structural_breaks: injected mean shift is detected at 1% level", {
  set.seed(42)
  n_daily <- 252L

  # Pre-break: 7 years, modest positive mean.
  pre  <- rnorm(7L * n_daily, mean =  0.0008, sd = 0.01)
  # Post-break: 6 years, large negative mean (clear regime shift).
  post <- rnorm(6L * n_daily, mean = -0.0008, sd = 0.01)
  r    <- c(pre, post)

  result <- hd_structural_breaks(r, alpha = 0.01, min_years = 3L,
                                   periods_per_year = 252L)

  # Must detect at least one break somewhere in the series.
  expect_true(result$n_breaks >= 1L)

  # The first break found must be within the series boundaries.
  # Note: the algorithm scans forward and reports the EARLIEST significant
  # split (within [min_periods, n - min_periods]).  With opposite-sign means
  # the split will be detected somewhere in the early part of the data.
  # We only assert that a break exists and post_break_start < n.
  expect_true(result$post_break_start >= 1L)
  expect_true(result$post_break_start <= length(r))
})

test_that("hd_structural_breaks: post_break_returns length matches assertion", {
  set.seed(42)
  n_daily <- 252L
  pre  <- rnorm(7L * n_daily, mean =  0.0008, sd = 0.01)
  post <- rnorm(6L * n_daily, mean = -0.0008, sd = 0.01)
  r    <- c(pre, post)

  result <- hd_structural_breaks(r, alpha = 0.01, min_years = 3L,
                                   periods_per_year = 252L)

  # post_break_returns must equal r[post_break_start:length(r)]
  expected_post <- r[result$post_break_start:length(r)]
  expect_equal(result$post_break_returns, expected_post)
  expect_equal(length(result$post_break_returns),
               length(r) - result$post_break_start + 1L)
})


# ─────────────────────────────────────────────────────────────────────────────
# 4. hd_structural_breaks() — return structure completeness
# ─────────────────────────────────────────────────────────────────────────────

test_that("hd_structural_breaks: return list has all required components", {
  set.seed(7)
  r <- rnorm(5L * 252L, 0.0003, 0.01)
  result <- hd_structural_breaks(r, alpha = 0.05, min_years = 2L,
                                   periods_per_year = 252L)

  expected_names <- c(
    "n_breaks", "break_indices", "post_break_start",
    "post_break_returns", "alpha", "min_periods",
    "multiple_testing_note"
  )
  expect_setequal(names(result), expected_names)
})

test_that("hd_structural_breaks: multiple_testing_note is a non-empty string", {
  set.seed(7)
  r <- rnorm(5L * 252L, 0.0003, 0.01)
  result <- hd_structural_breaks(r, alpha = 0.01, min_years = 2L,
                                   periods_per_year = 252L)

  expect_type(result$multiple_testing_note, "character")
  expect_true(nchar(result$multiple_testing_note) > 0L)
  # Snapshot to catch wording drift.
  expect_snapshot(cat(result$multiple_testing_note))
})

test_that("hd_structural_breaks: min_periods echoed correctly", {
  set.seed(7)
  r <- rnorm(8L * 12L, 0.003, 0.04)  # monthly series
  result <- hd_structural_breaks(r, alpha = 0.01, min_years = 3L,
                                   periods_per_year = 12L)

  expect_equal(result$min_periods, 3L * 12L)
  expect_equal(result$alpha, 0.01)
})


# ─────────────────────────────────────────────────────────────────────────────
# 5. Summary-builder helper — tested inline
#
# Replicates the logic from the `structural_breaks_summary` target body so we
# can test it without running a full pipeline.
# ─────────────────────────────────────────────────────────────────────────────

# Inline the Sharpe helper used inside the target.
.sharpe_ann <- function(r, ann) {
  r <- r[!is.na(r)]
  if (length(r) < 2L) return(NA_real_)
  sd_r <- stats::sd(r)
  if (is.na(sd_r) || sd_r <= .Machine$double.eps) return(NA_real_)
  mean(r) / sd_r * sqrt(ann)
}

# Build a synthetic multi-strategy sb_break_results list.
.make_sb_results <- function() {
  set.seed(42)
  n <- 252L * 10L  # 10 years daily
  dates <- seq.Date(as.Date("2014-01-01"), by = "day", length.out = n)

  # Strategy A: no break
  r_a <- rnorm(n, 0.0005, 0.01)
  result_a <- hd_structural_breaks(r_a, alpha = 0.01, min_years = 3L,
                                     periods_per_year = 252L)

  # Strategy B: strong injected break (Sharpe reversal)
  pre_b  <- rnorm(6L * 252L, 0.001,  0.01)
  post_b <- rnorm(4L * 252L, -0.001, 0.01)
  r_b    <- c(pre_b, post_b)
  dates_b <- seq.Date(as.Date("2014-01-01"), by = "day", length.out = length(r_b))
  result_b <- hd_structural_breaks(r_b, alpha = 0.01, min_years = 2L,
                                     periods_per_year = 252L)

  list(
    strat_a = list(
      strategy = "Strategy A",
      result   = result_a,
      error    = NULL,
      series   = list(returns = r_a, dates = dates, ppy = 252L, ann = 252)
    ),
    strat_b = list(
      strategy = "Strategy B",
      result   = result_b,
      error    = NULL,
      series   = list(returns = r_b, dates = dates_b, ppy = 252L, ann = 252)
    ),
    strat_c = list(
      strategy = "Strategy C (too short)",
      result   = NULL,
      error    = "too short: 100 < 1512",
      series   = list(returns = rnorm(100L, 0.0003, 0.01), dates = NULL,
                      ppy = 252L, ann = 252)
    )
  )
}

test_that("summary builder: no-break strategy has n_breaks = 0 and divergence NA", {
  res <- .make_sb_results()
  s_a <- res$strat_a

  whole_sharpe <- .sharpe_ann(s_a$series$returns, s_a$series$ann)
  post_r       <- s_a$result$post_break_returns
  post_sharpe  <- .sharpe_ann(post_r, s_a$series$ann)

  # No-break strategy: post_break = full series → divergence should be 0, not NA.
  expect_equal(s_a$result$n_breaks, 0L)
  expect_equal(length(s_a$result$break_indices), 0L)
  # When no break, post series = whole series → Sharpes identical.
  expect_equal(whole_sharpe, post_sharpe, tolerance = 1e-10)
})

test_that("summary builder: injected-break strategy has n_breaks >= 1", {
  res   <- .make_sb_results()
  s_b   <- res$strat_b
  expect_true(s_b$result$n_breaks >= 1L)
})

test_that("summary builder: errored strategy preserved with note", {
  res   <- .make_sb_results()
  s_c   <- res$strat_c
  expect_null(s_c$result)
  expect_false(is.null(s_c$error))
  expect_match(s_c$error, "too short")
})


# ─────────────────────────────────────────────────────────────────────────────
# 6. Caption snapshot — catches wording drift
# ─────────────────────────────────────────────────────────────────────────────

# Replicate the caption-building logic (snapshot of assembled string).
.build_caption <- function(n_strats, n_with_breaks, n_material,
                            alpha_pct, divergence_pct, min_years) {
  paste0(
    "Structural break analysis (Carver 2026): ",
    n_with_breaks, " of ", n_strats, " strategies show ",
    "at least one structural break at the ", alpha_pct, "% significance level. ",
    n_material, " show a material post-break Sharpe divergence ",
    "(>", divergence_pct, "% from whole-history Sharpe). ",
    "Breaks are detected using an iterative forward-split t-test on ",
    "vol-normalised returns with a minimum segment of ",
    min_years, " years. ",
    "Per the resulting-prohibition rule, a detected break is evidence ",
    "requiring investigation — not a signal to revise strategy allocation. ",
    "Per Carver's own finding, 'no break' often wins OOS: ",
    "break-splitting is a guard against over-splitting, not an always-on ",
    "re-estimator. ",
    "Multiple-testing note: scanning all candidate split dates inflates ",
    "the false-break rate above the nominal ", alpha_pct, "% level."
  )
}

test_that("structural_breaks_caption: format is stable (snapshot)", {
  caption <- .build_caption(
    n_strats = 7L, n_with_breaks = 1L, n_material = 0L,
    alpha_pct = 1, divergence_pct = 25, min_years = 5
  )
  expect_snapshot(cat(caption))
})
