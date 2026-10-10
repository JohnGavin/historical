testthat::local_edition(3)
# #937 (refs #919): #935 Change 4 fed hd_prob_sharpe_positive() the DSR path's
# arithmetic naive_sharpe but still paired it with the leaderboard `months`
# as n_obs. For a row whose DSR window differs from the leaderboard window
# (Factor MAX: 193 vs 740 before the wide-table fix) that pairs a Sharpe
# measured over T observations with a different n -- one home per value: the
# n must be the SAME T_obs the DSR path used, by construction.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))

test_that(".prob_sharpe_input_n uses the DSR T_obs ONLY on covered Full-Period rows", {
  out <- .prob_sharpe_input_n(
    period      = c("Full Period", "Training", "Full Period", "Full Period"),
    months      = c(740,            100,        740,           195),
    dsr_T_obs   = c(193,            193,        NA_real_,      NA_real_),
    dsr_covered = c(TRUE,           TRUE,       TRUE,          FALSE)
  )
  expect_equal(out[1], 193)   # covered Full Period -> the DSR path's own T
  expect_equal(out[2], 100)   # sub-period keeps the row's months (unchanged)
  expect_true(is.na(out[3]))  # covered but T_obs NA -> NA, NEVER silently `months`
  expect_equal(out[4], 195)   # no DSR row (PSO Optimal) -> months (unchanged)
})

test_that("FALSIFICATION: pairing the DSR Sharpe with leaderboard months changes the probability", {
  sr <- 0.30
  n_dsr <- .prob_sharpe_input_n("Full Period", 740, 193, TRUE)
  same  <- hd_prob_sharpe_positive(sr, n_obs = n_dsr, ann_factor = 12)$prob_sharpe_positive
  mixed <- hd_prob_sharpe_positive(sr, n_obs = 740,   ann_factor = 12)$prob_sharpe_positive
  expect_equal(same, hd_prob_sharpe_positive(sr, n_obs = 193, ann_factor = 12)$prob_sharpe_positive)
  expect_gt(abs(mixed - same), 0.01)
})

test_that(".prob_sharpe_input_n aborts on mismatched input lengths", {
  expect_snapshot(
    error = TRUE,
    .prob_sharpe_input_n("Full Period", c(10, 20), 10, TRUE)
  )
  expect_snapshot(args(.prob_sharpe_input_n))
})

test_that("WIRING: the leaderboard target carries T_obs from the DSR path into the PSR n", {
  hit <- vapply(plan_leaderboard(), function(t) identical(t$settings$name, "leaderboard"), logical(1))
  expect_equal(sum(hit), 1L)
  body <- gsub("\\s+", " ", paste(deparse(plan_leaderboard()[[which(hit)]]$command$expr), collapse = " "))
  expect_match(body, ".dsr_T_obs = T_obs", fixed = TRUE)
  expect_match(body, ".prob_sharpe_input_n(", fixed = TRUE)
  expect_match(body, "list(prob_sharpe_in, prob_sharpe_n", fixed = TRUE)
  # the raw leaderboard months must no longer be the PSR n
  expect_false(grepl("list(prob_sharpe_in, all_metrics$months", body, fixed = TRUE))
})
