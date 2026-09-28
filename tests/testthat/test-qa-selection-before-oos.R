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

# ── Regression: literal curly braces in evidence/detail text must not break
# cli formatting (real scripts/build.sh failure on main b16ff1e, #910/#917) ──
#
# cli::cli_inform()/cli_warn()/cli_abort() treat every character element
# they are handed as a glue-style format string and re-parse any `{...}`
# inside it as R code to evaluate. check_selection_before_oos() builds its
# bullet text with sprintf()/paste0() from data-derived `detail`/`evidence`
# fields -- and the real S41 CMR evidence text
# ("...cmr_portfolio_{1m,3m,6m} rows...") contains a literal brace pair.
# Before the fix, this aborted every `tar_make()` with:
#   "Could not parse cli `{}` expression: `1m,3m,6m`."
# because `1m` is not valid R syntax (and even a syntactically valid
# expression would have been evaluated, not printed literally). None of the
# fixtures above ever contained a brace, so `devtools::test()` never caught
# it -- this is the fixture gap being closed here.

test_that("check_selection_before_oos: literal curly braces in detail/strategy text do not break cli formatting in STAGED (warn) mode", {
  tbl <- tibble::tibble(
    strategy = "CMR {x}",
    mechanism = "single_shot",
    verdict = "FAIL",
    detail = "picks the max-Sharpe lookback using ONLY cmr_portfolio_{1m,3m,6m} rows strictly before test_start"
  )

  w <- testthat::capture_warnings(
    result <- check_selection_before_oos(tbl, enforce = FALSE)
  )
  expect_length(w, 1L)
  # The brace text must appear VERBATIM (single braces, not doubled/escaped
  # and not evaluated as R code) in the rendered warning.
  expect_match(w, "cmr_portfolio_{1m,3m,6m}", fixed = TRUE)
  expect_match(w, "CMR {x}", fixed = TRUE)
  expect_identical(result, tbl)
})

test_that("check_selection_before_oos: literal curly braces survive verbatim into the enforced abort message", {
  tbl <- tibble::tibble(
    strategy = "CMR {x}",
    mechanism = "single_shot",
    verdict = "FAIL",
    detail = "picks the max-Sharpe lookback using ONLY cmr_portfolio_{1m,3m,6m} rows strictly before test_start"
  )
  expect_snapshot(error = TRUE, check_selection_before_oos(tbl, enforce = TRUE))
})

test_that("build_selection_before_oos_table -> check_selection_before_oos: end-to-end with brace-bearing evidence text does not error (reproduces the real b16ff1e build failure)", {
  wf <- tibble::tibble(strategy = "fake walk-forward", evidence = "fake evidence")
  ss <- tibble::tibble(
    strategy = "CMR best-lookback selection",
    # Deliberately a FAIL verdict (cutoff >= first_oos) so the offending
    # `bad_msgs` cli_warn() path -- not just the always-run cli_inform()
    # summary path -- is exercised too.
    cutoff_date = as.Date("2026-01-01"),
    first_oos_date = as.Date("2020-01-01"),
    evidence = paste0(
      "R/plan_commodities_mean_reversion.R's .cmr_select_pre_oos_lookback() ",
      "picks the max-Sharpe lookback using ONLY cmr_portfolio_{1m,3m,6m} ",
      "rows strictly before bt_partitions$macro$test_start"
    )
  )
  tbl <- build_selection_before_oos_table(ss, walk_forward = wf)

  w <- testthat::capture_warnings(check_selection_before_oos(tbl, enforce = FALSE))
  expect_length(w, 1L)
  expect_match(w, "cmr_portfolio_{1m,3m,6m}", fixed = TRUE)
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
