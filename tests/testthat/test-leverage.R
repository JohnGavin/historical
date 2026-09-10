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

# ── .leverage_gross_backstop() (#626) ───────────────────────────────────────

test_that(".leverage_gross_backstop: returns the default when the env var is unset", {
  expect_equal(.leverage_gross_backstop(""), LEVERAGE_GROSS_BACKSTOP_DEFAULT)
})

test_that(".leverage_gross_backstop: honours a valid positive numeric override", {
  expect_equal(.leverage_gross_backstop("2.75"), 2.75)
})

test_that(".leverage_gross_backstop: errors on a non-numeric override", {
  expect_snapshot(error = TRUE, .leverage_gross_backstop("banana"))
})

test_that(".leverage_gross_backstop: errors on a non-positive override", {
  expect_snapshot(error = TRUE, .leverage_gross_backstop("0"))
  expect_snapshot(error = TRUE, .leverage_gross_backstop("-1.5"))
})

# ── compute_allocator_gross() (#626) ────────────────────────────────────────
# Full Period rows from .leaderboard_fixture(): A (vol=0.11, gross=2),
# B (vol=0.22, gross=1), C (vol=0.05, gross=1), D (vol=0.33, gross=2).
# vol_per_unit_gross: A=0.055, B=0.22, C=0.05, D=0.165.
# Using sigma_target = 0.11 (chosen for easy hand-verification, not the
# fixture's own budget-neutral value):
#   G_implied: A = 0.11/0.055 = 2.0, B = 0.11/0.22 = 0.5,
#              C = 0.11/0.05  = 2.2, D = 0.11/0.165 = 0.6667
# With backstop = 1.5: A and C exceed it (G_capped = 1.5, backstop_binds = TRUE);
# B and D do not (G_capped == G_implied, backstop_binds = FALSE).

test_that("compute_allocator_gross: computes G_implied = sigma_target / vol_per_unit_gross", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)

  b_row <- out[out$strategy == "B", ]
  expect_equal(b_row$G_implied, 0.5, tolerance = 1e-9)
  d_row <- out[out$strategy == "D", ]
  expect_equal(d_row$G_implied, 0.11 / (0.33 / 2), tolerance = 1e-9)
})

test_that("compute_allocator_gross: caps G_capped at the backstop and flags backstop_binds", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)

  a_row <- out[out$strategy == "A", ]
  expect_equal(a_row$G_implied, 2.0, tolerance = 1e-9)
  expect_equal(a_row$G_capped, 1.5, tolerance = 1e-9)
  expect_true(a_row$backstop_binds)

  b_row <- out[out$strategy == "B", ]
  expect_equal(b_row$G_capped, b_row$G_implied, tolerance = 1e-9)
  expect_false(b_row$backstop_binds)
})

test_that("compute_allocator_gross: only Full Period rows are returned", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)
  expect_false(any(c("Training", "Testing") %in% out$strategy))
  expect_equal(sort(out$strategy), c("A", "B", "C", "D"))
})

test_that("compute_allocator_gross: is_cap is carried through unchanged", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)
  b_row <- out[out$strategy == "B", ]
  expect_true(b_row$is_cap)
})

test_that("compute_allocator_gross: sorted descending by G_implied", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)
  expect_true(all(diff(out$G_implied) <= 0))
  expect_equal(out$strategy[1], "C")  # highest G_implied (2.2)
})

test_that("compute_allocator_gross: backstop_used/sigma_target_used echo the inputs", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  out <- compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 1.5)
  expect_true(all(out$backstop_used == 1.5))
  expect_true(all(out$sigma_target_used == 0.11))
})

test_that("compute_allocator_gross: errors on missing required columns", {
  bad <- compute_vol_per_unit_gross(.leaderboard_fixture())
  bad$is_cap <- NULL
  expect_snapshot(error = TRUE, compute_allocator_gross(bad, sigma_target = 0.11))
})

test_that("compute_allocator_gross: errors on a non-positive sigma_target", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  expect_snapshot(error = TRUE, compute_allocator_gross(vpug, sigma_target = -0.1))
  expect_snapshot(error = TRUE, compute_allocator_gross(vpug, sigma_target = NA_real_))
})

test_that("compute_allocator_gross: errors on a non-positive backstop", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  expect_snapshot(error = TRUE, compute_allocator_gross(vpug, sigma_target = 0.11, backstop = 0))
})

test_that("compute_allocator_gross: errors when no Full Period rows are present", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  no_full <- vpug[vpug$period != "Full Period", ]
  expect_snapshot(error = TRUE, compute_allocator_gross(no_full, sigma_target = 0.11))
})

test_that("compute_allocator_gross: default backstop is .leverage_gross_backstop()", {
  vpug <- compute_vol_per_unit_gross(.leaderboard_fixture())
  withr::local_envvar(c(HD_LEVERAGE_GROSS_BACKSTOP = "3"))
  out <- compute_allocator_gross(vpug, sigma_target = 0.11)
  expect_true(all(out$backstop_used == 3))
})

test_that("compute_allocator_gross: function signature is stable (catches API drift)", {
  expect_snapshot(args(compute_allocator_gross))
})
