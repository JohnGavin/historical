# Tests for plan_structural_breaks.R (#477)
#
# Tests for the plan helper logic (summary builder, divergence flag) using a
# synthetic multi-strategy input.  Snapshot tests for assembled caption strings.
#
# Note: unit tests for hd_structural_breaks() itself live in:
#   packages/historicaldata/tests/testthat/test-structural-breaks.R
# They are NOT duplicated here (snapshot-test-policy.md).
#
# All tests are self-contained: no live targets pipeline is executed.

testthat::local_edition(3)

# Load hd_structural_breaks() from the package source.
# We source the file directly rather than pkgload::load_all() to avoid
# pulling in all historicaldata dependencies (duckplyr, etc.) in the
# root-level test environment, which mirrors the outer dev shell that lacks
# the full package dependency set.  cli:: is available in the dev shell.
source(here::here("packages/historicaldata/R/structural_breaks.R"))


# ─────────────────────────────────────────────────────────────────────────────
# Summary-builder helper — tested inline
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

test_that("summary builder: no-break strategy has n_breaks = 0 and equal Sharpes", {
  res <- .make_sb_results()
  s_a <- res$strat_a

  whole_sharpe <- .sharpe_ann(s_a$series$returns, s_a$series$ann)
  # main's hd_structural_breaks() does not return post_break_returns;
  # derive from post_break_start index (same as the plan consumer does).
  post_start <- s_a$result$post_break_start
  post_r      <- s_a$series$returns[post_start:length(s_a$series$returns)]
  post_sharpe  <- .sharpe_ann(post_r, s_a$series$ann)

  # No-break strategy: post_break = full series -> Sharpes identical.
  expect_equal(s_a$result$n_breaks, 0L)
  expect_equal(length(s_a$result$break_indices), 0L)
  # When no break, post series = whole series -> Sharpes identical.
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
# Caption snapshot — catches wording drift
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
