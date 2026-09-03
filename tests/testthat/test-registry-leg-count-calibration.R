# Tests for check_registry_leg_count_calibration() -- QA gate S32 (#839)
#
# Mirrors the S20 pattern (check_leaderboard_detection_power_values,
# #726): a pure function over a status tibble, so it's testable without a
# live registry connection. hd_registry_leg_count_status() (packages/
# historicaldata/R/registry_metrics.R) is the reader this gate is built on;
# it has its own tests in packages/historicaldata/tests/testthat/
# test-registry-metrics.R.

test_that("check_registry_leg_count_calibration passes with zero composite rows", {
  status <- tibble::tibble(
    strategy_id = character(0),
    leg_count = integer(0),
    has_leg_calibration = logical(0)
  )
  expect_true(check_registry_leg_count_calibration(status))
})

test_that("check_registry_leg_count_calibration passes when every composite row has calibration", {
  status <- tibble::tibble(
    strategy_id = c("ens1", "ens2"),
    leg_count = c(2L, 4L),
    has_leg_calibration = c(TRUE, TRUE)
  )
  expect_true(check_registry_leg_count_calibration(status))
})

test_that("check_registry_leg_count_calibration aborts naming an uncalibrated composite", {
  status <- tibble::tibble(
    strategy_id = "ens1",
    leg_count = 2L,
    has_leg_calibration = FALSE
  )
  expect_snapshot(error = TRUE, check_registry_leg_count_calibration(status))
})

test_that("check_registry_leg_count_calibration aborts naming ALL uncalibrated composites, not just the first", {
  status <- tibble::tibble(
    strategy_id = c("ens1", "ens2", "ens3"),
    leg_count = c(2L, 3L, 4L),
    has_leg_calibration = c(FALSE, TRUE, FALSE)
  )
  err <- tryCatch(
    check_registry_leg_count_calibration(status),
    error = function(e) e
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "ens1")
  expect_match(conditionMessage(err), "ens3")
  expect_false(grepl("ens2", conditionMessage(err)))
})

test_that("check_registry_leg_count_calibration aborts on a status tibble missing required columns", {
  expect_snapshot(
    error = TRUE,
    check_registry_leg_count_calibration(tibble::tibble(strategy_id = "ens1"))
  )
})

# ── .run_qa_registry_leg_count_calibration (the S32 target wrapper) ─────
#
# Exercises the wrapper that opens the live registry -- distinct from the
# pure check_registry_leg_count_calibration() tests above, which never
# touch a DB connection.

test_that(".run_qa_registry_leg_count_calibration skips (does not error) when no registry file exists", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  withr::local_envvar(c(HD_REGISTRY_PATH = tempfile(fileext = ".duckdb")))
  expect_true(.run_qa_registry_leg_count_calibration())
})

test_that(".run_qa_registry_leg_count_calibration passes against a real registry with no composites", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(unlink(tmp))
  historicaldata::hd_registry_init(tmp)
  withr::local_envvar(c(HD_REGISTRY_PATH = tmp))
  expect_true(.run_qa_registry_leg_count_calibration())
})

test_that(".run_qa_registry_leg_count_calibration aborts against a real registry with an uncalibrated composite", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(unlink(tmp))
  historicaldata::hd_registry_init(tmp)
  con <- historicaldata::hd_registry_open(tmp, read_only = FALSE)
  historicaldata::hd_strategy_upsert(
    con,
    list(strategy_id = "ens_live", short_name = "ENSL", long_name = "Ensemble Live"),
    underlying_signals = c("a", "b"), leg_count = 2L
  )
  DBI::dbDisconnect(con, shutdown = TRUE)

  withr::local_envvar(c(HD_REGISTRY_PATH = tmp))
  expect_error(
    .run_qa_registry_leg_count_calibration(),
    regexp = "manufactured-Sharpe calibration annotation"
  )
})
