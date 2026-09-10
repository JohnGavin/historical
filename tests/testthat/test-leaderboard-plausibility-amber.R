testthat::local_edition(3)
# Tests for .leaderboard_peer_amber_flags() and
# check_leaderboard_plausibility_amber() -- QA gate S30 (#719 Layer 1,
# Amber tier: peer-relative plausibility outliers).
#
# The design point under test: an amber flag with no written
# acknowledgement in LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED escalates to a
# pipeline-aborting error ONLY when enforce = TRUE (or
# HD_ENFORCE_PLAUSIBILITY_AMBER=1) -- by default the gate STAGES (reports
# via cli_warn, still returns TRUE), per the roxygen precedent (#738's
# periodicity_check warn-mode, HD_FAIL_ON_STALE_DASHBOARDS). The functions
# are defined in R/plan_qa_gates.R.

source(here::here("R/plan_qa_gates.R"))

# 17 peers with vol tightly clustered ~0.15-0.19 except CMR, an outlier at
# 0.05 -- reproduces #717's own worked example ("CMR published 5.0% vol,
# the second-lowest of seventeen, against a peer median near 17%").
peer_vol <- c(0.17, 0.16, 0.18, 0.15, 0.19, 0.16, 0.17, 0.18, 0.15, 0.19,
              0.16, 0.17, 0.18, 0.15, 0.19, 0.16)
leaderboard_with_outlier <- tibble::tibble(
  strategy = c(paste0("Peer", seq_along(peer_vol)), "CMR"),
  period   = "Full Period",
  vol      = c(peer_vol, 0.05),
  sharpe   = c(rep(0.3, length(peer_vol)), -0.75)
)

leaderboard_no_outlier <- tibble::tibble(
  strategy = paste0("Peer", 1:5),
  period   = "Full Period",
  vol      = c(0.17, 0.16, 0.18, 0.15, 0.19),
  sharpe   = c(0.3, 0.35, 0.28, 0.32, 0.31)
)

empty_ack <- tibble::tibble(strategy = character(0), metric = character(0), reason = character(0))

# ── .leaderboard_peer_amber_flags() ─────────────────────────────────────

test_that(".leaderboard_peer_amber_flags flags CMR's understated vol against its peers", {
  flags <- .leaderboard_peer_amber_flags(leaderboard_with_outlier, metrics = "vol")
  expect_true("CMR" %in% flags$strategy)
  expect_equal(flags$metric[flags$strategy == "CMR"], "vol")
})

test_that(".leaderboard_peer_amber_flags returns zero rows when nothing is an outlier", {
  flags <- .leaderboard_peer_amber_flags(leaderboard_no_outlier, metrics = c("vol", "sharpe"))
  expect_equal(nrow(flags), 0L)
})

test_that(".leaderboard_peer_amber_flags does not divide by zero when peer MAD is 0", {
  identical_vol <- tibble::tibble(
    strategy = paste0("Peer", 1:5), period = "Full Period",
    vol = rep(0.15, 5), sharpe = c(0.1, 0.2, 0.3, 0.4, 0.5)
  )
  flags <- .leaderboard_peer_amber_flags(identical_vol, metrics = "vol")
  expect_equal(nrow(flags), 0L)
  expect_false(any(is.infinite(flags$modified_z)))
})

test_that(".leaderboard_peer_amber_flags scopes to the requested period only", {
  mixed <- dplyr::bind_rows(
    leaderboard_with_outlier,
    dplyr::mutate(leaderboard_with_outlier, period = "Testing")
  )
  flags_full <- .leaderboard_peer_amber_flags(mixed, metrics = "vol", period = "Full Period")
  expect_true(all(flags_full$strategy == "CMR"))
})

# ── check_leaderboard_plausibility_amber(): staged (default) behaviour ────

test_that("an unacknowledged amber flag warns (does not abort) by default", {
  expect_warning(
    result <- check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack),
    "NOT acknowledged|no written"
  )
  expect_true(result)
})

test_that("no amber flags at all: silent, no warning, passes", {
  expect_silent(check_leaderboard_plausibility_amber(leaderboard_no_outlier, empty_ack))
})

# ── check_leaderboard_plausibility_amber(): enforce = TRUE ────────────────

test_that("enforce = TRUE aborts on an unacknowledged amber flag and names it", {
  expect_error(
    check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack, enforce = TRUE),
    "CMR"
  )
  expect_snapshot(
    error = TRUE,
    check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack, enforce = TRUE)
  )
})

test_that("enforce = TRUE passes when the amber flag IS acknowledged", {
  ack <- tibble::tibble(
    strategy = "CMR", metric = "vol",
    reason = "test fixture: deliberately flagged for this test"
  )
  expect_true(
    check_leaderboard_plausibility_amber(leaderboard_with_outlier, ack, enforce = TRUE)
  )
})

test_that("HD_ENFORCE_PLAUSIBILITY_AMBER=1 escalates without passing enforce explicitly", {
  withr::local_envvar(HD_ENFORCE_PLAUSIBILITY_AMBER = "1")
  expect_error(
    check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack),
    "CMR"
  )
})

test_that("as.logical()-on-strings footgun is avoided: env var '0' does NOT enforce", {
  # fail-loud-not-null.md: as.logical('1') is NA, not TRUE -- pins that
  # this gate uses an explicit string comparison, not as.logical().
  withr::local_envvar(HD_ENFORCE_PLAUSIBILITY_AMBER = "0")
  expect_warning(
    result <- check_leaderboard_plausibility_amber(leaderboard_with_outlier, empty_ack),
    "NOT acknowledged|no written"
  )
  expect_true(result)
})

test_that("acknowledged_tbl missing required columns aborts", {
  expect_error(
    check_leaderboard_plausibility_amber(
      leaderboard_with_outlier, dplyr::select(empty_ack, -reason)
    ),
    "reason"
  )
})

test_that("LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED is empty by design at introduction (#719)", {
  # Pins the documented starting state -- see that table's roxygen for why
  # it is deliberately not pre-populated with a guess.
  expect_equal(nrow(LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED), 0L)
  expect_setequal(
    names(LEADERBOARD_PLAUSIBILITY_ACKNOWLEDGED),
    c("strategy", "metric", "reason")
  )
})
