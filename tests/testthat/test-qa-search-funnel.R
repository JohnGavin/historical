testthat::local_edition(3)

# build_search_funnel_table() calls historicaldata::hd_trial_sharpe_var(),
# so the package must be loaded before sourcing the plan file. Mirrors the
# pattern used in test-cmr-units.R.
pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/plan_qa_gates.R"))

# ── S38: search funnel (tried -> min-trades-pass -> deflation-survivor) ────
#
# #558 Gap G5: "a target reporting, per strategy family, how many variants
# were tried -> passed the min-trades screen -> survived deflation, so the
# search size behind every published Sharpe is visible." build_search_
# funnel_table() computes this table from a named list of trial-population
# tibbles; check_search_funnel() asserts it is internally consistent
# (survivors <= min-trades-passed <= tried) and non-empty, aborting
# otherwise.
#
# The "deflation-survivor" stage is a documented APPROXIMATION (see
# build_search_funnel_table()'s own roxygen): it substitutes the same
# normal-returns simplification hd_detection_power() already uses (no raw
# per-trial returns survive in the multiverse runners to estimate skew/
# kurtosis from) into hd_deflated_sharpe()'s exact E[max SR] formula. These
# tests reimplement that same approximation independently (mirroring
# test-deflated-sharpe.R's own "legacy_dsr" pattern) rather than hardcoding
# magic survivor counts.

# Independent reimplementation of the deflation-survival approximation, for
# comparison against build_search_funnel_table()'s own computation.
.expected_survivors <- function(sharpe, n_obs, ann_factor, V, K, alpha = 0.05) {
  sr_period <- sharpe / sqrt(ann_factor)
  var_sr <- (1 + 0.5 * sr_period^2) / n_obs
  if (K > 1L) {
    z <- sqrt(2 * log(K))
    gamma <- 0.5772156649
    e_max_sr <- (z - (gamma + log(pi / 2)) / (2 * z)) * sqrt(V) / sqrt(n_obs)
  } else {
    e_max_sr <- 0
  }
  z_stat <- (sr_period - e_max_sr) / sqrt(var_sr)
  p_value <- 1 - stats::pnorm(z_stat)
  sum(p_value < alpha)
}

test_that("build_search_funnel_table: all trials clear min_trades, funnel reproduces the independent reimplementation", {
  set.seed(1)
  sharpe <- c(0.9, 0.85, 0.95, 1.1, 0.8)   # comfortably positive, huge T below
  n_obs  <- rep(1000, 5)                   # far above min_trades -> nothing screened

  fam <- list(
    fake_a = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 12L)
  )
  tbl <- list(fake_a = tibble::tibble(sr = sharpe, n = n_obs))

  funnel <- build_search_funnel_table(tbl, families = fam)
  expect_identical(nrow(funnel), 1L)
  expect_identical(funnel$family, "fake_a")
  expect_identical(funnel$n_tried, 5L)
  expect_identical(funnel$n_min_trades_pass, 5L)

  v <- hd_trial_sharpe_var(sharpe, n_obs)
  want <- .expected_survivors(sharpe, n_obs, 12L, v$trial_sharpe_var, v$n_included)
  expect_identical(funnel$n_deflation_survivors, as.integer(want))
})

test_that("build_search_funnel_table: trials below min_trades are excluded from BOTH the min-trades and deflation stages", {
  sharpe <- c(0.5, 0.6, 0.55, 0.52, 3.0)
  n_obs  <- c(200, 200, 200, 200, 5)   # last one is "junk"

  fam <- list(fake_b = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 252L))
  tbl <- list(fake_b = tibble::tibble(sr = sharpe, n = n_obs))

  funnel <- build_search_funnel_table(tbl, families = fam)
  expect_identical(funnel$n_tried, 5L)
  expect_identical(funnel$n_min_trades_pass, 4L)
  expect_lte(funnel$n_deflation_survivors, funnel$n_min_trades_pass)
})

test_that("build_search_funnel_table: fewer than 2 min-trades survivors yields NA deflation-survivor count, not a silent zero", {
  sharpe <- c(0.5, 0.6)
  n_obs  <- c(5, 6)   # both junk -- 0 survivors of the min-trades screen

  fam <- list(fake_c = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 12L))
  tbl <- list(fake_c = tibble::tibble(sr = sharpe, n = n_obs))

  funnel <- build_search_funnel_table(tbl, families = fam)
  expect_identical(funnel$n_min_trades_pass, 0L)
  expect_true(is.na(funnel$n_deflation_survivors))
})

test_that("build_search_funnel_table: multiple families each get their own row", {
  fam <- list(
    a = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 12L),
    b = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 252L)
  )
  tbl <- list(
    a = tibble::tibble(sr = c(0.3, 0.4, 0.5), n = c(100, 100, 100)),
    b = tibble::tibble(sr = c(0.2, 0.25),      n = c(500, 500))
  )
  funnel <- build_search_funnel_table(tbl, families = fam)
  expect_identical(nrow(funnel), 2L)
  expect_setequal(funnel$family, c("a", "b"))
  expect_identical(funnel$n_tried[funnel$family == "a"], 3L)
  expect_identical(funnel$n_tried[funnel$family == "b"], 2L)
})

test_that("build_search_funnel_table aborts on an empty families registry", {
  expect_snapshot(error = TRUE, build_search_funnel_table(list(), families = list()))
})

test_that("build_search_funnel_table aborts when trial_tables is missing a registered family", {
  fam <- list(a = list(sharpe_col = "sr", n_obs_col = "n", ann_factor = 12L))
  expect_snapshot(error = TRUE, build_search_funnel_table(list(), families = fam))
})

test_that("check_search_funnel passes on a consistent funnel", {
  ok <- tibble::tibble(
    family = c("a", "b"),
    n_tried = c(16L, 16L),
    n_min_trades_pass = c(16L, 12L),
    n_deflation_survivors = c(3L, NA_integer_)
  )
  expect_true(check_search_funnel(ok))
})

test_that("check_search_funnel aborts on an empty (zero-row) funnel", {
  empty <- tibble::tibble(
    family = character(0), n_tried = integer(0),
    n_min_trades_pass = integer(0), n_deflation_survivors = integer(0)
  )
  expect_snapshot(error = TRUE, check_search_funnel(empty))
})

test_that("check_search_funnel aborts when min-trades-pass exceeds tried", {
  bad <- tibble::tibble(
    family = "a", n_tried = 5L, n_min_trades_pass = 6L,
    n_deflation_survivors = NA_integer_
  )
  expect_snapshot(error = TRUE, check_search_funnel(bad))
})

test_that("check_search_funnel aborts when deflation-survivors exceeds min-trades-pass", {
  bad <- tibble::tibble(
    family = "a", n_tried = 10L, n_min_trades_pass = 5L,
    n_deflation_survivors = 7L
  )
  expect_snapshot(error = TRUE, check_search_funnel(bad))
})
