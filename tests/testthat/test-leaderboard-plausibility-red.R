testthat::local_edition(3)
# Tests for check_leaderboard_plausibility_red() -- QA gate S29
# (#719 Layer 1, Red tier: physically impossible metric values).
#
# Four checks: vol <= 0, max_dd < -1, abs(sharpe) > 5, and implied years
# (months / obs_ann_factor) > 100. The function is defined in
# R/plan_qa_gates.R. Tests exercise it directly on synthetic fixtures,
# without running tar_make().

source(here::here("R/plan_qa_gates.R"))

good_leaderboard <- tibble::tibble(
  strategy = c("CMR", "OLMAR-1", "Factor DRIF"),
  period   = "Full Period",
  vol      = c(0.229, 0.15, 0.12),
  max_dd   = c(-0.35, -0.20, -0.40),
  sharpe   = c(-0.75, 0.62, 0.30),
  months   = c(6852, 2000, 300)
)
good_obs_ann_factor <- tibble::tibble(
  strategy = c("CMR", "OLMAR-1", "Factor DRIF"),
  obs_ann_factor = c(252L, 252L, 12L)
)

test_that("check_leaderboard_plausibility_red passes on plausible values", {
  expect_true(check_leaderboard_plausibility_red(good_leaderboard, good_obs_ann_factor))
})

test_that("vol <= 0 is flagged as RED, including exactly 0 (S9's inclusive gap)", {
  bad <- good_leaderboard
  bad$vol[1] <- 0
  expect_error(
    check_leaderboard_plausibility_red(bad, good_obs_ann_factor),
    "vol"
  )
})

test_that("max_dd < -1 is flagged as RED", {
  bad <- good_leaderboard
  bad$max_dd[2] <- -1.2
  expect_error(
    check_leaderboard_plausibility_red(bad, good_obs_ann_factor),
    "max_dd"
  )
})

test_that("abs(sharpe) > 5 is flagged as RED", {
  bad <- good_leaderboard
  bad$sharpe[3] <- 7.5
  expect_error(
    check_leaderboard_plausibility_red(bad, good_obs_ann_factor),
    "sharpe"
  )
})

test_that("implied years > 100 is flagged as RED -- reproduces the #717 shape", {
  bad <- good_leaderboard
  # The #717 defect: n = 6789 daily rows / ann_factor = 12 = 565.75 "years".
  bad$months[1] <- 6789
  bad_obs <- good_obs_ann_factor
  bad_obs$obs_ann_factor[bad_obs$strategy == "CMR"] <- 12L
  expect_error(
    check_leaderboard_plausibility_red(bad, bad_obs),
    "implied_years"
  )
  expect_snapshot(error = TRUE, check_leaderboard_plausibility_red(bad, bad_obs))
})

test_that("multiple RED violations are all named in one abort", {
  bad <- good_leaderboard
  bad$vol[1] <- -0.01
  bad$sharpe[2] <- 6
  err <- tryCatch(
    check_leaderboard_plausibility_red(bad, good_obs_ann_factor),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "CMR")
  expect_match(err, "OLMAR-1")
})

test_that("required leaderboard columns are enforced", {
  expect_error(
    check_leaderboard_plausibility_red(dplyr::select(good_leaderboard, -sharpe), good_obs_ann_factor),
    "sharpe"
  )
})

test_that("required obs_ann_factor_tbl columns are enforced", {
  expect_error(
    check_leaderboard_plausibility_red(good_leaderboard, dplyr::select(good_obs_ann_factor, -obs_ann_factor)),
    "obs_ann_factor"
  )
})
