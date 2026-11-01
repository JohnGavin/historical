# Tests for hd_strategy_spec_trial_count() (Refs #972, #496): the number of
# distinct SPECIFICATIONS tested, not ledger rows. Hermetic: every test uses a
# temp research-log base_dir.

testthat::local_edition(3)

.st_tmp_dir <- function() {
  tf <- tempfile("rlog-spec-")
  dir.create(tf)
  tf
}

.st_hyp <- function(base_dir, claim, predictor, status, ts, uuid = NA_character_) {
  suppressWarnings(suppressMessages(hd_rlog_append(
    "hypotheses",
    tibble::tibble(
      uuid           = uuid,
      timestamp      = as.POSIXct(ts, tz = "UTC"),
      economic_claim = claim,
      predictor      = predictor,
      status         = status
    ),
    base_dir = base_dir
  )))
}

.st_impl <- function(base_dir, parent, params_json, uuid = NA_character_) {
  suppressMessages(hd_rlog_append(
    "implementations",
    tibble::tibble(
      uuid        = uuid,
      parent_uuid = parent,
      params_json = params_json
    ),
    base_dir = base_dir
  ))
}

.st_uuid <- function() hd_rlog_uuid()

test_that("many rows of one claim with identical params count as ONE trial", {
  d <- .st_tmp_dir()
  u <- .st_uuid()
  p <- '{"window":25,"epsilon":10,"leverage":0.2,"cost_bps":10}'
  for (i in 1:7) {
    .st_hyp(d, "c-olmar", "OLMAR-1", "tested", sprintf("2026-01-0%d", i), uuid = u)
  }
  .st_hyp(d, "c-olmar", "OLMAR-1", "refuted", "2026-02-01")
  for (i in 1:3) .st_impl(d, u, p)
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 1L)
})

test_that("distinct params under one claim are distinct specifications", {
  d <- .st_tmp_dir()
  u <- .st_uuid()
  .st_hyp(d, "c", "p", "refuted", "2026-01-01", uuid = u)
  .st_impl(d, u, '{"window":25}')
  .st_impl(d, u, '{"window":50}')
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 2L)
})

test_that("params are normalised: key order and whitespace do not matter", {
  d <- .st_tmp_dir()
  u <- .st_uuid()
  .st_hyp(d, "c", "p", "supported", "2026-01-01", uuid = u)
  .st_impl(d, u, '{"a":1,"b":2}')
  .st_impl(d, u, '{ "b": 2, "a": 1 }')
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 1L)
})

test_that("a counted group with no implementation counts as one specification", {
  d <- .st_tmp_dir()
  .st_hyp(d, "c1", "p1", "refuted", "2026-01-01")
  .st_hyp(d, "c2", "p2", "testing", "2026-01-01")
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 2L)
})

test_that("status rules: unmeasurable, proposed, withdrawn are excluded", {
  d <- .st_tmp_dir()
  .st_hyp(d, "c-ref", "p-ref", "refuted", "2026-01-01")
  .st_hyp(d, "c-sup", "p-sup", "supported", "2026-01-01")
  .st_hyp(d, "c-inc", "p-inc", "inconclusive-underpowered", "2026-01-01")
  .st_hyp(d, "c-tst", "p-tst", "testing", "2026-01-01")
  .st_hyp(d, "c-unm", "p-unm", "inconclusive-unmeasurable", "2026-01-01")
  .st_hyp(d, "c-prop", "p-prop", "proposed", "2026-01-01")
  .st_hyp(d, "c-wd", "p-wd", "withdrawn", "2026-01-01")
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 4L)
})

test_that("legacy 'tested' groups are left out and reported", {
  d <- .st_tmp_dir()
  .st_hyp(d, "c", "OLMAR-1", "tested", "2026-01-01")
  expect_snapshot(n <- hd_strategy_spec_trial_count(base_dir = d))
  expect_equal(n, 0L)
})

test_that("an implementation is looked up through any row of its group", {
  d <- .st_tmp_dir()
  u1 <- .st_uuid()
  u2 <- .st_uuid()
  .st_hyp(d, "c", "p", "testing", "2026-01-01", uuid = u1)
  .st_hyp(d, "c", "p", "refuted", "2026-02-01", uuid = u2)
  .st_impl(d, u1, '{"w":1}')
  .st_impl(d, u2, '{"w":2}')
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 2L)
})

test_that("an empty log counts zero trials", {
  expect_equal(hd_strategy_spec_trial_count(base_dir = .st_tmp_dir()), 0L)
})

test_that("unparseable or missing params fail loud", {
  d <- .st_tmp_dir()
  u <- .st_uuid()
  .st_hyp(d, "c", "p", "refuted", "2026-01-01", uuid = u)
  .st_impl(d, u, "not json", uuid = "impl-bad-json")
  expect_snapshot(error = TRUE, hd_strategy_spec_trial_count(base_dir = d))
  d2 <- .st_tmp_dir()
  u2 <- .st_uuid()
  .st_hyp(d2, "c", "p", "refuted", "2026-01-01", uuid = u2)
  .st_impl(d2, u2, NA_character_, uuid = "impl-na-params")
  expect_snapshot(error = TRUE, hd_strategy_spec_trial_count(base_dir = d2))
})

test_that("hd_strategy_trial_count is untouched by the new function", {
  d <- .st_tmp_dir()
  u <- .st_uuid()
  .st_hyp(d, "c", "p", "refuted", "2026-01-01", uuid = u)
  .st_impl(d, u, '{"w":1}')
  .st_impl(d, u, '{"w":2}')
  expect_equal(hd_strategy_trial_count(base_dir = d), 1L)
  expect_equal(hd_strategy_spec_trial_count(base_dir = d), 2L)
})

test_that("function signature is stable", {
  expect_snapshot(args(hd_strategy_spec_trial_count))
})
