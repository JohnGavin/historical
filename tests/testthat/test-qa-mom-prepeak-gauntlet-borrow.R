testthat::local_edition(3)
source(here::here("R/plan_qa_gates.R"))

# ── S35: mom_prepeak-gauntlet borrow-cost consistency ──────────────────────
#
# #800: R/plan_mom_prepeak_gauntlet.R recomputes the mom_prepeak short-leg
# return series at several points (WFC grid, random-peak null, CPCV IS/OOS)
# rather than reusing the published `mom_prepeak_returns` target. #676 made
# the published targets borrow-aware but deliberately left every other
# `.mom_prepeak_compute_returns()` caller at the function's zero default --
# these tests guard that the gauntlet's recomputations were brought onto the
# same cost basis, and stay there.
#
# Fixture files use a FIXED basename (not tempfile()'s random name) so the
# error messages -- which report basename(file) -- are snapshot-stable
# across runs and machines.

fixture_path <- function(name) file.path(tempdir(), name)

test_that("check_mom_prepeak_gauntlet_borrow_consistency flags a named-arg call missing borrow_rate_annual", {
  tmp <- fixture_path("gauntlet_fixture_named_missing.R")
  writeLines(c(
    "ret <- .mom_prepeak_compute_returns(",
    "  portfolio_tbl  = port,",
    "  universe_tbl   = ltr_universe,",
    "  cost_per_trade = 0.001",
    ")"
  ), tmp)
  on.exit(unlink(tmp))
  expect_snapshot(error = TRUE, check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency flags a positional-arg call missing borrow_rate_annual (CPCV style)", {
  tmp <- fixture_path("gauntlet_fixture_positional_missing.R")
  writeLines(
    "ret_is <- .mom_prepeak_compute_returns(port_is, ltr_universe, 0.001)",
    tmp
  )
  on.exit(unlink(tmp))
  expect_snapshot(error = TRUE, check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency passes when borrow_rate_annual is present (named arg, comment interleaved)", {
  tmp <- fixture_path("gauntlet_fixture_named_ok.R")
  writeLines(c(
    "ret <- .mom_prepeak_compute_returns(",
    "  portfolio_tbl      = port,",
    "  universe_tbl       = ltr_universe,",
    "  cost_per_trade     = 0.001,",
    "  # an interleaved comment must not truncate the call block (#800)",
    "  borrow_rate_annual = mom_prepeak_params$borrow_rate_annual",
    ")"
  ), tmp)
  on.exit(unlink(tmp))
  expect_true(check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency passes when borrow_rate_annual is present (positional call)", {
  tmp <- fixture_path("gauntlet_fixture_positional_ok.R")
  writeLines(
    "ret_is <- .mom_prepeak_compute_returns(port_is, ltr_universe, 0.001, mom_prepeak_params$borrow_rate_annual)",
    tmp
  )
  on.exit(unlink(tmp))
  expect_true(check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency respects the zero-borrow-intentional opt-out", {
  tmp <- fixture_path("gauntlet_fixture_opt_out.R")
  writeLines(
    paste0(
      "ret <- .mom_prepeak_compute_returns(port, ltr_universe, 0.001)",
      "  # zero-borrow-intentional: diagnostic-only correlation, not a performance verdict"
    ),
    tmp
  )
  on.exit(unlink(tmp))
  expect_true(check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency ignores commented-out call sites", {
  tmp <- fixture_path("gauntlet_fixture_commented_out.R")
  writeLines(
    "# .mom_prepeak_compute_returns(port_is, ltr_universe, 0.001)  # old approach, superseded",
    tmp
  )
  on.exit(unlink(tmp))
  expect_true(check_mom_prepeak_gauntlet_borrow_consistency(tmp))
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency aborts cleanly on a missing file", {
  # Not snapshotted: the error message interpolates the full (randomised)
  # tempfile() path, which is not stable across runs/machines.
  err <- tryCatch(
    check_mom_prepeak_gauntlet_borrow_consistency(tempfile()),
    error = function(e) e
  )
  expect_s3_class(err, "rlang_error")
  expect_match(conditionMessage(err), "file not found")
})

test_that("check_mom_prepeak_gauntlet_borrow_consistency: the real gauntlet file passes (#800 fix)", {
  gauntlet_file <- here::here("R", "plan_mom_prepeak_gauntlet.R")
  skip_if_not(file.exists(gauntlet_file), "R/plan_mom_prepeak_gauntlet.R not found")
  expect_true(check_mom_prepeak_gauntlet_borrow_consistency(gauntlet_file))
})

test_that("qa_mom_prepeak_gauntlet_borrow_consistency scanner function signature is stable (catches API drift)", {
  expect_snapshot(args(check_mom_prepeak_gauntlet_borrow_consistency))
})
