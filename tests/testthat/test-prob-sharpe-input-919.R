# #919 follow-up: the leaderboard's uncorrected prob_sharpe_positive (#916)
# was fed the GEOMETRIC Sharpe, but the probabilistic-Sharpe formula assumes
# the ARITHMETIC per-period mean/sd -- the one strat_deflated_sharpe's DSR
# path uses (on the hd_return_basis() EXCESS basis). Full-Period rows of
# DSR-covered strategies now use that arithmetic excess Sharpe so
# `1 - dsr_pvalue <= prob_sharpe_positive` is a like-for-like comparison.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))

test_that(".prob_sharpe_input_sharpe uses the arithmetic excess Sharpe ONLY on covered Full-Period rows", {
  out <- .prob_sharpe_input_sharpe(
    period       = c("Full Period", "Training", "Full Period", "Full Period"),
    sharpe       = c(0.068,          0.068,      0.30,          0.50),
    arith_sharpe = c(0.110,          0.110,      NA_real_,      NA_real_),
    dsr_covered  = c(TRUE,           TRUE,       TRUE,          FALSE)
  )
  expect_equal(out[1], 0.110)  # covered Full Period -> arithmetic
  expect_equal(out[2], 0.068)  # sub-period -> geometric (no arithmetic series exists)
  expect_true(is.na(out[3]))   # covered but arithmetic NA -> stays NA, NEVER silently geometric
  expect_equal(out[4], 0.50)   # no DSR row (e.g. PSO Optimal) -> geometric
})

test_that(".prob_sharpe_input_sharpe keeps the positive-Sharpe domain of the leaderboard Sharpe", {
  out <- .prob_sharpe_input_sharpe(
    period = rep("Full Period", 3), sharpe = c(-0.1, 0, NA_real_),
    arith_sharpe = c(0.2, 0.2, 0.2), dsr_covered = rep(TRUE, 3)
  )
  expect_true(all(is.na(out)))
})

test_that("FALSIFICATION: the arithmetic input changes the published probability (HML-like case)", {
  # HML-like: geometric 0.068 vs arithmetic 0.110 on a long monthly sample.
  geo   <- hd_prob_sharpe_positive(0.068, n_obs = 752, ann_factor = 12)$prob_sharpe_positive
  arith <- hd_prob_sharpe_positive(0.110, n_obs = 752, ann_factor = 12)$prob_sharpe_positive
  via   <- hd_prob_sharpe_positive(
    .prob_sharpe_input_sharpe("Full Period", 0.068, 0.110, TRUE),
    n_obs = 752, ann_factor = 12
  )$prob_sharpe_positive
  expect_gt(arith, geo)
  expect_equal(via, arith)
})

test_that(".prob_sharpe_input_sharpe aborts on mismatched input lengths", {
  expect_snapshot(
    error = TRUE,
    .prob_sharpe_input_sharpe("Full Period", c(0.1, 0.2), 0.1, TRUE)
  )
  expect_snapshot(args(.prob_sharpe_input_sharpe))
})

test_that("WIRING: the leaderboard target feeds prob_sharpe_positive through the arithmetic input", {
  hit <- vapply(plan_leaderboard(), function(t) identical(t$settings$name, "leaderboard"), logical(1))
  expect_equal(sum(hit), 1L)
  # deparse() re-wraps lines: collapse all whitespace before matching
  body <- gsub("\\s+", " ", paste(deparse(plan_leaderboard()[[which(hit)]]$command$expr), collapse = " "))
  # DSR join carries the arithmetic excess Sharpe ...
  expect_match(body, ".dsr_naive_sharpe = naive_sharpe", fixed = TRUE)
  # ... and the PSR pmap reads the helper's output, not the raw `sharpe` column
  expect_match(body, ".prob_sharpe_input_sharpe(", fixed = TRUE)
  # (#937: the n is now the DSR path's T_obs via prob_sharpe_n, not raw months)
  expect_match(body, "list(prob_sharpe_in, prob_sharpe_n", fixed = TRUE)
})
