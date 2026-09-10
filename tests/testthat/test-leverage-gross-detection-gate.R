testthat::local_edition(3)
# Tests for check_leverage_gross_detection_gate() — QA gate S31
# (#626/#719 Layer 2 narrow slice, .claude/rules/detection-power-required.md)
#
# The function is defined in R/plan_qa_gates.R. It implements the narrow
# slice of #719's Layer 2 provenance-gating rule that #626's allocator work
# has enough pieces to enforce today: a strategy may not receive allocator
# gross (G_capped) above 1.0x while its Full-Period detection_underpowered
# verdict is TRUE or NA (unverified). NA is deliberately treated the same as
# TRUE — see the roxygen in R/plan_qa_gates.R for the fail-loud-not-null.md
# rationale.

source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ─────────────────────────────────────────────────────────────

# "Detectable" clears the detection bar and is levered above 1.0x -- should
# pass. "Underpowered" fails the detection bar and is levered above 1.0x --
# should be blocked. "Unverified" has NO detection verdict (NA) and is
# levered above 1.0x -- should ALSO be blocked (NA treated as TRUE).
# "UnderCapped" is underpowered but its G_capped is <= 1.0x -- not an
# offence regardless of detection status.
allocator_gross <- tibble::tibble(
  strategy = c("Detectable", "Underpowered", "Unverified", "UnderCapped"),
  G_capped = c(1.8, 1.5, 1.2, 0.9)
)

leaderboard_fixture <- tibble::tibble(
  strategy = c("Detectable", "Underpowered", "Unverified", "UnderCapped", "IgnoredOtherPeriod"),
  period = c("Full Period", "Full Period", "Full Period", "Full Period", "Training"),
  detection_underpowered = c(FALSE, TRUE, NA, TRUE, NA)
)

test_that("check_leverage_gross_detection_gate passes when only detectable strategies exceed 1.0x", {
  ok <- allocator_gross[allocator_gross$strategy %in% c("Detectable", "UnderCapped"), ]
  lb <- leaderboard_fixture[leaderboard_fixture$strategy %in% c("Detectable", "UnderCapped", "IgnoredOtherPeriod"), ]
  expect_true(check_leverage_gross_detection_gate(ok, lb))
})

test_that("check_leverage_gross_detection_gate does not flag underpowered strategies capped at or below 1.0x", {
  under_capped <- allocator_gross[allocator_gross$strategy == "UnderCapped", ]
  lb <- leaderboard_fixture[leaderboard_fixture$strategy == "UnderCapped", ]
  expect_true(check_leverage_gross_detection_gate(under_capped, lb))
})

test_that("check_leverage_gross_detection_gate throws when an underpowered strategy exceeds 1.0x", {
  bad <- allocator_gross[allocator_gross$strategy == "Underpowered", ]
  lb <- leaderboard_fixture[leaderboard_fixture$strategy == "Underpowered", ]
  expect_error(check_leverage_gross_detection_gate(bad, lb), regexp = "Underpowered")
  expect_snapshot(error = TRUE, check_leverage_gross_detection_gate(bad, lb))
})

test_that("check_leverage_gross_detection_gate treats a missing (NA) detection verdict as blocking", {
  bad <- allocator_gross[allocator_gross$strategy == "Unverified", ]
  lb <- leaderboard_fixture[leaderboard_fixture$strategy == "Unverified", ]
  expect_error(check_leverage_gross_detection_gate(bad, lb), regexp = "Unverified")
  expect_snapshot(error = TRUE, check_leverage_gross_detection_gate(bad, lb))
})

test_that("check_leverage_gross_detection_gate only scopes detection verdicts to Full Period rows", {
  # IgnoredOtherPeriod has no Full Period row in leaderboard_fixture, so the
  # left_join produces NA detection_underpowered for it if present in
  # allocator_gross -- exercised implicitly by every test above via
  # left_join's NA-on-no-match behaviour. This test makes the scoping
  # explicit: a strategy present ONLY as a Training row must not borrow a
  # Full Period verdict it doesn't have.
  fixture <- tibble::tibble(strategy = "OnlyTraining", G_capped = 1.5)
  lb <- tibble::tibble(
    strategy = "OnlyTraining", period = "Training", detection_underpowered = FALSE
  )
  expect_error(check_leverage_gross_detection_gate(fixture, lb), regexp = "OnlyTraining")
})

test_that("check_leverage_gross_detection_gate respects a declared override", {
  bad <- allocator_gross[allocator_gross$strategy == "Underpowered", ]
  lb <- leaderboard_fixture[leaderboard_fixture$strategy == "Underpowered", ]
  override <- tibble::tibble(strategy = "Underpowered", reason = "test override")
  expect_true(check_leverage_gross_detection_gate(bad, lb, override_tbl = override))
})

test_that("check_leverage_gross_detection_gate ignores strategies with no measurable G_capped", {
  na_gross <- tibble::tibble(strategy = "Underpowered", G_capped = NA_real_)
  lb <- leaderboard_fixture[leaderboard_fixture$strategy == "Underpowered", ]
  expect_true(check_leverage_gross_detection_gate(na_gross, lb))
})

# ── Required columns ────────────────────────────────────────────────────

test_that("check_leverage_gross_detection_gate throws when allocator_gross is missing required columns", {
  bad <- dplyr::select(allocator_gross, -G_capped)
  expect_error(
    check_leverage_gross_detection_gate(bad, leaderboard_fixture),
    regexp = "G_capped"
  )
  expect_snapshot(error = TRUE, check_leverage_gross_detection_gate(bad, leaderboard_fixture))
})

test_that("check_leverage_gross_detection_gate throws when leaderboard is missing required columns", {
  bad_lb <- dplyr::select(leaderboard_fixture, -detection_underpowered)
  expect_error(
    check_leverage_gross_detection_gate(allocator_gross, bad_lb),
    regexp = "detection_underpowered"
  )
  expect_snapshot(error = TRUE, check_leverage_gross_detection_gate(allocator_gross, bad_lb))
})

test_that("check_leverage_gross_detection_gate throws when override_tbl is missing required columns", {
  bad_override <- tibble::tibble(strategy = character(0))
  expect_error(
    check_leverage_gross_detection_gate(allocator_gross, leaderboard_fixture, override_tbl = bad_override),
    regexp = "reason"
  )
  expect_snapshot(
    error = TRUE,
    check_leverage_gross_detection_gate(allocator_gross, leaderboard_fixture, override_tbl = bad_override)
  )
})
