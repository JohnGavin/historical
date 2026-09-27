testthat::local_edition(3)

source(here::here("R/plan_qa_gates.R"))

# ── S41: selection-before-OOS gate (#910 item 1) ──────────────────────────
#
# "From Alpha Signals to Portfolio" (#910)'s single most important rule: a
# feature/factor/parameter set must be selected on data that STRICTLY
# PREDATES the first out-of-sample bar. build_selection_before_oos_table()
# combines a static walk-forward registry (PASS by construction, verified
# from source) with a caller-supplied single-shot tibble whose
# cutoff_date/first_oos_date are compared live. check_selection_before_oos()
# reports every row and, in STAGED (default) mode, warns rather than aborts
# on any FAIL/INDETERMINATE.

test_that("build_selection_before_oos_table: single-shot PASS when cutoff strictly precedes first OOS", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")
  ss <- tibble::tibble(
    strategy = "fake single-shot pass",
    cutoff_date = as.Date("2019-12-31"),
    first_oos_date = as.Date("2020-01-01"),
    evidence = "fake evidence"
  )
  tbl <- build_selection_before_oos_table(ss, walk_forward = wf)

  expect_identical(nrow(tbl), 2L)
  expect_identical(tbl$verdict[tbl$mechanism == "walk_forward"], "PASS")
  expect_identical(tbl$verdict[tbl$strategy == "fake single-shot pass"], "PASS")
})

test_that("build_selection_before_oos_table: single-shot FAIL when cutoff is at or after first OOS", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")

  # Strictly after
  ss_after <- tibble::tibble(
    strategy = "fake fail after",
    cutoff_date = as.Date("2026-05-14"),
    first_oos_date = as.Date("2020-01-01"),
    evidence = "fake evidence"
  )
  expect_identical(
    build_selection_before_oos_table(ss_after, walk_forward = wf)$verdict[2],
    "FAIL"
  )

  # Exactly equal (not STRICTLY before -- must also FAIL, not PASS)
  ss_equal <- tibble::tibble(
    strategy = "fake fail equal",
    cutoff_date = as.Date("2020-01-01"),
    first_oos_date = as.Date("2020-01-01"),
    evidence = "fake evidence"
  )
  expect_identical(
    build_selection_before_oos_table(ss_equal, walk_forward = wf)$verdict[2],
    "FAIL"
  )
})

test_that("build_selection_before_oos_table: single-shot INDETERMINATE when either date is NA, never PASS", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")

  ss_na_cutoff <- tibble::tibble(
    strategy = "fake indeterminate cutoff",
    cutoff_date = as.Date(NA), first_oos_date = as.Date("2020-01-01"),
    evidence = "fake evidence"
  )
  expect_identical(
    build_selection_before_oos_table(ss_na_cutoff, walk_forward = wf)$verdict[2],
    "INDETERMINATE"
  )

  ss_na_oos <- tibble::tibble(
    strategy = "fake indeterminate oos",
    cutoff_date = as.Date("2019-12-31"), first_oos_date = as.Date(NA),
    evidence = "fake evidence"
  )
  expect_identical(
    build_selection_before_oos_table(ss_na_oos, walk_forward = wf)$verdict[2],
    "INDETERMINATE"
  )
})

test_that("build_selection_before_oos_table: multiple single-shot rows each get their own verdict", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")
  ss <- tibble::tibble(
    strategy = c("pass one", "fail one", "indeterminate one"),
    cutoff_date = as.Date(c("2019-12-31", "2026-01-01", NA)),
    first_oos_date = as.Date(c("2020-01-01", "2020-01-01", "2020-01-01")),
    evidence = rep("fake evidence", 3)
  )
  tbl <- build_selection_before_oos_table(ss, walk_forward = wf)
  expect_identical(nrow(tbl), 4L)  # 1 walk-forward + 3 single-shot
  expect_identical(tbl$verdict[tbl$strategy == "pass one"], "PASS")
  expect_identical(tbl$verdict[tbl$strategy == "fail one"], "FAIL")
  expect_identical(tbl$verdict[tbl$strategy == "indeterminate one"], "INDETERMINATE")
})

test_that("build_selection_before_oos_table aborts on an empty/malformed walk-forward registry", {
  ss <- tibble::tibble(
    strategy = "x", cutoff_date = as.Date("2020-01-01"),
    first_oos_date = as.Date("2020-01-02"), evidence = "x"
  )
  expect_snapshot(
    error = TRUE,
    build_selection_before_oos_table(ss, walk_forward = tibble::tibble())
  )
})

test_that("build_selection_before_oos_table aborts when single_shot is missing a required column", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")
  expect_snapshot(
    error = TRUE,
    build_selection_before_oos_table(tibble::tibble(strategy = "x"), walk_forward = wf)
  )
})

test_that("check_selection_before_oos: STAGED mode warns (not aborts) on FAIL/INDETERMINATE", {
  tbl <- tibble::tibble(
    strategy = c("ok", "bad"), mechanism = c("walk_forward", "single_shot"),
    verdict = c("PASS", "FAIL"), detail = c("fine", "trouble")
  )
  expect_warning(
    result <- check_selection_before_oos(tbl, enforce = FALSE),
    "FAILED or are INDETERMINATE"
  )
  expect_identical(result, tbl)
})

test_that("check_selection_before_oos: enforce=TRUE aborts on FAIL/INDETERMINATE", {
  tbl <- tibble::tibble(
    strategy = c("ok", "bad"), mechanism = c("walk_forward", "single_shot"),
    verdict = c("PASS", "INDETERMINATE"), detail = c("fine", "trouble")
  )
  expect_snapshot(error = TRUE, check_selection_before_oos(tbl, enforce = TRUE))
})

test_that("check_selection_before_oos: an acknowledged strategy is excluded from the FAIL/INDETERMINATE consequence", {
  tbl <- tibble::tibble(
    strategy = "acked bad", mechanism = "single_shot",
    verdict = "FAIL", detail = "trouble"
  )
  expect_no_warning(
    check_selection_before_oos(tbl, acknowledged = "acked bad", enforce = FALSE)
  )
})

test_that("check_selection_before_oos: an all-PASS table produces no warning", {
  tbl <- tibble::tibble(
    strategy = "ok", mechanism = "walk_forward",
    verdict = "PASS", detail = "fine"
  )
  expect_no_warning(check_selection_before_oos(tbl, enforce = FALSE))
})

test_that("check_selection_before_oos aborts on a zero-row verdict table", {
  empty <- tibble::tibble(
    strategy = character(0), mechanism = character(0),
    verdict = character(0), detail = character(0)
  )
  expect_snapshot(error = TRUE, check_selection_before_oos(empty))
})

test_that("SELECTION_WALK_FORWARD_REGISTRY is non-empty and every row lands as PASS", {
  ss <- tibble::tibble(
    strategy = character(0), cutoff_date = as.Date(character(0)),
    first_oos_date = as.Date(character(0)), evidence = character(0)
  )
  tbl <- build_selection_before_oos_table(ss)
  expect_gt(nrow(tbl), 0L)
  expect_true(all(tbl$verdict == "PASS"))
  expect_true(all(tbl$mechanism == "walk_forward"))
})
