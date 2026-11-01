testthat::local_edition(3)
# #972 step 1 (report-only): check_leaderboard_k_trials_logged() asserts that,
# when the leaderboard carries k_trials_logged, it is ONE positive whole number
# repeated on every row (it is a property of the whole leaderboard, not of one
# strategy).

source(here::here("R/plan_qa_gates.R"))

good <- tibble::tibble(
  strategy                = c("A", "B", "C"),
  k_trials_logged         = c(13L, 13L, 13L),
  deflated_sharpe_klogged = c(0.2, NA_real_, 0.4),
  dsr_pvalue_klogged      = c(0.3, NA_real_, 0.1)
)

test_that("a single positive integer on every row passes", {
  expect_true(check_leaderboard_k_trials_logged(good))
})

test_that("a leaderboard without the column is not checked (report-only columns are optional)", {
  expect_true(check_leaderboard_k_trials_logged(good[, "strategy"]))
})

test_that("FALSIFICATION: each way of being wrong aborts", {
  bad_zero <- good; bad_zero$k_trials_logged <- 0L
  expect_snapshot(error = TRUE, check_leaderboard_k_trials_logged(bad_zero))

  bad_na <- good; bad_na$k_trials_logged[2] <- NA_integer_
  expect_snapshot(error = TRUE, check_leaderboard_k_trials_logged(bad_na))

  bad_two <- good; bad_two$k_trials_logged[3] <- 14L
  expect_snapshot(error = TRUE, check_leaderboard_k_trials_logged(bad_two))

  bad_frac <- good; bad_frac$k_trials_logged <- 13.5
  expect_snapshot(error = TRUE, check_leaderboard_k_trials_logged(bad_frac))

  bad_chr <- good; bad_chr$k_trials_logged <- "13"
  expect_error(check_leaderboard_k_trials_logged(bad_chr), "positive whole number")
})
