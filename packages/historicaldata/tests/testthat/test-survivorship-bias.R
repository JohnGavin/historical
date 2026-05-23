
# Tests for survivorship-bias guard (issue #150)
#
# RED phase: these tests will fail until the implementation is added.

test_that("equity_daily registry entry declares survivorship_biased = TRUE", {
  ds <- hd_datasets()
  expect_true(
    isTRUE(ds[["equity_daily"]][["survivorship_biased"]]),
    label = "equity_daily$survivorship_biased must be TRUE"
  )
})

test_that("equity_daily registry entry declares known_delistings = 0L", {
  ds <- hd_datasets()
  expect_identical(
    ds[["equity_daily"]][["known_delistings"]],
    0L,
    label = "equity_daily$known_delistings must be 0L (documented in #150)"
  )
})

test_that("non-equity datasets do NOT have survivorship_biased flag", {
  ds <- hd_datasets()
  # Fama-French factors are point-in-time — no survivorship bias
  expect_false(
    isTRUE(ds[["factors"]][["survivorship_biased"]]),
    label = "factors dataset should not be flagged as survivorship-biased"
  )
})

test_that("hd_check_survivorship_bias emits warning for equity_daily", {
  expect_warning(
    hd_check_survivorship_bias("equity_daily"),
    regexp = "survivorship"
  )
})

test_that("hd_check_survivorship_bias is silent for factors dataset", {
  expect_no_warning(
    hd_check_survivorship_bias("factors")
  )
})

test_that("hd_check_survivorship_bias is silent for macro_daily", {
  expect_no_warning(
    hd_check_survivorship_bias("macro_daily")
  )
})

test_that("hd_check_survivorship_bias errors on unknown dataset", {
  expect_error(
    hd_check_survivorship_bias("nonexistent_dataset"),
    regexp = "Unknown dataset"
  )
})

test_that("hd_datasets equity_daily description mentions survivorship bias", {
  ds <- hd_datasets()
  expect_true(
    grepl("survivorship", ds[["equity_daily"]][["description"]], ignore.case = TRUE),
    label = "equity_daily description should mention survivorship bias"
  )
})
