testthat::local_edition(3)

# compute_vol_per_unit_gross(), compute_budget_neutral_sigma(), and
# compute_regime_stress_ratio() are genuine top-level (non-tar_target)
# functions in R/plan_leverage.R (#635) -- source the real file rather than
# reproducing it, same pattern as test-plan-portfolio-opt.R's
# .port_weighted_return() tests.
source(here::here("R/plan_leverage.R"))

# ── Fixture: a small leaderboard slice mirroring the real column set ───────
# Values are NOT the real leaderboard data (that lives only in the built
# `docs/_targets` store) -- they are synthetic, chosen to make the expected
# budget-neutral sigma easy to hand-verify.

.leaderboard_fixture <- function() {
  tibble::tibble(
    strategy = c(
      "A", "A", "A",
      "B", "B",
      "C",
      "D", "D",
      "NoGross", "NoGross"
    ),
    period = c(
      "Training", "Testing", "Full Period",
      "Training", "Full Period",
      "Full Period",
      "Testing", "Full Period",
      "Full Period", "Training"
    ),
    vol = c(
      0.10, 0.12, 0.11,
      0.20, 0.22,
      0.05,
      0.30, 0.33,
      0.08, 0.09
    ),
    gross_convention = c(
      2, 2, 2,
      1, 1,
      1,
      2, 2,
      NA_real_, NA_real_
    ),
    is_cap = c(
      FALSE, FALSE, FALSE,
      TRUE, TRUE,
      FALSE,
      FALSE, FALSE,
      FALSE, FALSE
    )
  )
}

# ── compute_vol_per_unit_gross() ────────────────────────────────────────────

test_that("compute_vol_per_unit_gross: computes vol / gross_convention per row", {
  out <- compute_vol_per_unit_gross(.leaderboard_fixture())

  a_full <- out[out$strategy == "A" & out$period == "Full Period", ]
  expect_equal(a_full$vol_per_unit_gross, 0.11 / 2, tolerance = 1e-12)

  b_train <- out[out$strategy == "B" & out$period == "Training", ]
  expect_equal(b_train$vol_per_unit_gross, 0.20 / 1, tolerance = 1e-12)
})

test_that("compute_vol_per_unit_gross: excludes rows with NA gross_convention", {
  out <- compute_vol_per_unit_gross(.leaderboard_fixture())
  expect_false("NoGross" %in% out$strategy)
})

test_that("compute_vol_per_unit_gross: is_cap is carried through unchanged", {
  out <- compute_vol_per_unit_gross(.leaderboard_fixture())
  b_rows <- out[out$strategy == "B", ]
  expect_true(all(b_rows$is_cap))
})

test_that("compute_vol_per_unit_gross: default periods restrict to Training/Testing/Full Period", {
  fixture <- .leaderboard_fixture()
  fixture <- dplyr::bind_rows(
    fixture,
    tibble::tibble(
      strategy = "A", period = "Holdout", vol = 0.5,
      gross_convention = 2, is_cap = FALSE
    )
  )
  out <- compute_vol_per_unit_gross(fixture)
  expect_false("Holdout" %in% out$period)
})

test_that("compute_vol_per_unit_gross: errors on non-data-frame input", {
  expect_snapshot(error = TRUE, compute_vol_per_unit_gross(list(a = 1)))
})

test_that("compute_vol_per_unit_gross: errors on missing required columns", {
  bad <- .leaderboard_fixture()
  bad$gross_convention <- NULL
  expect_snapshot(error = TRUE, compute_vol_per_unit_gross(bad))
})

test_that("compute_vol_per_unit_gross: function signature is stable (catches API drift)", {
  expect_snapshot(args(compute_vol_per_unit_gross))
})

# ── compute_budget_neutral_sigma() ──────────────────────────────────────────
# Full Period rows: A (vol=0.11, gross=2), B (vol=0.22, gross=1), C (vol=0.05, gross=1),
# D (vol=0.33, gross=2). sum(gross) = 2+1+1+2 = 6.
# sum(gross/vol) = 2/0.11 + 1/0.22 + 1/0.05 + 2/0.33
#                = 18.181818 + 4.545455 + 20 + 6.060606 = 48.787879
# sigma = 6 / 48.787879 = 0.122991...

test_that("compute_budget_neutral_sigma: reproduces sum(G_i) == sum(gross_i) by construction", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  sigma_tbl <- compute_budget_neutral_sigma(vpug)

  full <- sigma_tbl[sigma_tbl$period == "Full Period", ]
  sigma <- full$sigma_target_budget_neutral

  full_vpug <- vpug[vpug$period == "Full Period", ]
  implied_gross <- sigma / full_vpug$vol_per_unit_gross

  expect_equal(sum(implied_gross), sum(full_vpug$gross_convention), tolerance = 1e-9)
})

test_that("compute_budget_neutral_sigma: matches hand-derived value on the fixture", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  sigma_tbl <- compute_budget_neutral_sigma(vpug)

  full <- sigma_tbl[sigma_tbl$period == "Full Period", ]
  expected_sigma <- 6 / (2 / 0.11 + 1 / 0.22 + 1 / 0.05 + 2 / 0.33)
  expect_equal(full$sigma_target_budget_neutral, expected_sigma, tolerance = 1e-9)
  expect_equal(full$n, 4L)
})

test_that("compute_budget_neutral_sigma: is_headline flags exactly the Full Period row", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  sigma_tbl <- compute_budget_neutral_sigma(vpug)

  expect_equal(sigma_tbl$period[sigma_tbl$is_headline], "Full Period")
  expect_true(sum(sigma_tbl$is_headline) == 1L)
})

test_that("compute_budget_neutral_sigma: errors on missing required columns", {
  expect_snapshot(error = TRUE, compute_budget_neutral_sigma(tibble::tibble(period = "Full Period")))
})

test_that("compute_budget_neutral_sigma: errors on zero-row input", {
  empty <- compute_vol_per_unit_gross(.leaderboard_fixture())[0, ]
  expect_snapshot(error = TRUE, compute_budget_neutral_sigma(empty))
})

test_that("compute_budget_neutral_sigma: function signature is stable (catches API drift)", {
  expect_snapshot(args(compute_budget_neutral_sigma))
})

# ── compute_regime_stress_ratio() ───────────────────────────────────────────

test_that("compute_regime_stress_ratio: computes Testing / Training per strategy", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  stress <- compute_regime_stress_ratio(vpug)

  a_row <- stress[stress$strategy == "A", ]
  expect_equal(a_row$stress_ratio, 0.12 / 0.10, tolerance = 1e-12)
})

test_that("compute_regime_stress_ratio: strategies missing either partition are excluded", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  stress <- compute_regime_stress_ratio(vpug)

  # B has Training but no Testing row; C has neither; D has Testing but no Training.
  expect_false("B" %in% stress$strategy)
  expect_false("C" %in% stress$strategy)
  expect_false("D" %in% stress$strategy)
  expect_equal(stress$strategy, "A")
})

test_that("compute_regime_stress_ratio: sorted descending by stress_ratio", {
  fixture <- .leaderboard_fixture()
  fixture <- dplyr::bind_rows(
    fixture,
    tibble::tibble(
      strategy = c("E", "E"), period = c("Training", "Testing"),
      vol = c(0.10, 0.50), gross_convention = c(1, 1), is_cap = c(FALSE, FALSE)
    )
  )
  vpug <- compute_vol_per_unit_gross(fixture)
  stress <- compute_regime_stress_ratio(vpug)

  expect_true(all(diff(stress$stress_ratio) <= 0))
  expect_equal(stress$strategy[1], "E")  # 5x stress ratio, the largest
})

test_that("compute_regime_stress_ratio: errors when Training/Testing partitions are entirely absent", {
  full_only <- .leaderboard_fixture()
  full_only <- full_only[full_only$period == "Full Period", ]
  vpug <- compute_vol_per_unit_gross(full_only)
  expect_snapshot(error = TRUE, compute_regime_stress_ratio(vpug))
})

test_that("compute_regime_stress_ratio: function signature is stable (catches API drift)", {
  expect_snapshot(args(compute_regime_stress_ratio))
})
