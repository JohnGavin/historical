# Tests for S47 (leaderboard Sharpe vs the DSR path's Sharpe, same basis) --
# Refs #937 Phase 3 item 3, #919.
#
# Principle: the leaderboard `sharpe` is GEOMETRIC, (CAGR - rf) / vol; the
# DSR path's `naive_sharpe` is ARITHMETIC annualised excess mean / sd. Same
# series and same rf basis => geometric <= arithmetic (CAGR <= arithmetic mean,
# AM-GM). So `leaderboard sharpe > naive_sharpe + tol` can only mean
# the two paths deduct rf differently (the #919 shape), and is a FAIL.
# (S43 checks the windows match, S44 the 1 - dsr_pvalue <= PSR ordering, which
# also forces the DSR hurdle SR0 >= 0.)
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_qa_gates.R"))

# naive_sharpe (hd_deflated_sharpe) is already annualised, same units as the
# leaderboard sharpe.
.lb47 <- function(sharpe = c(0.40, 0.30, 0.20)) {
  tibble::tibble(
    strategy = c("A", "B", "PSO Optimal"),
    period   = "Full Period",
    sharpe   = c(sharpe[1:2], 0.5)
  )
}
.dsr47 <- function(naive = c(0.45, 0.35)) {
  tibble::tibble(strategy = c("A", "B"), naive_sharpe = naive)
}

test_that("S47 GREEN: geometric Sharpe at or below the annualised arithmetic Sharpe passes", {
  # 0.40 <= 0.45 ; 0.30 <= 0.35
  tbl <- build_sharpe_basis_table(.lb47(), .dsr47())
  expect_equal(tbl$verdict, c("PASS", "PASS"))
  s <- attr(check_sharpe_basis(tbl), "summary")
  expect_equal(s[["examined"]], 2L)
  expect_false("PSO Optimal" %in% tbl$strategy)
})

test_that("S47 RED: DSR path deducted rf the leaderboard did not (#919 shape) is a FAIL naming the strategy", {
  # 0.40 > 0.28 + 0.1: the DSR path deducted rf the leaderboard did not
  tbl <- build_sharpe_basis_table(.lb47(), .dsr47(naive = c(0.28, 0.35)))
  expect_equal(tbl$verdict, c("FAIL", "PASS"))
  err <- tryCatch(check_sharpe_basis(tbl), error = function(e) e)
  expect_s3_class(err, "qa_s47_fail")
  expect_match(conditionMessage(err), "A", fixed = TRUE)
})

test_that("S47: NA inputs or a strategy in one table only are INDETERMINATE (own class), never PASS", {
  tbl <- build_sharpe_basis_table(.lb47(), .dsr47(naive = c(NA, 0.35)))
  expect_equal(tbl$verdict[tbl$strategy == "A"], "INDETERMINATE")
  err <- tryCatch(check_sharpe_basis(tbl), error = function(e) e)
  expect_s3_class(err, "qa_s47_indeterminate")
  expect_false(inherits(err, "qa_s47_fail"))

  tbl2 <- build_sharpe_basis_table(.lb47(), .dsr47()[1, ])
  expect_equal(tbl2$verdict[tbl2$strategy == "B"], "INDETERMINATE")
  expect_match(tbl2$detail[tbl2$strategy == "B"], "missing_in_dsr")
})

test_that("S47 NON-VACUOUS: zero rows examined is INDETERMINATE, not a pass", {
  tbl <- build_sharpe_basis_table(.lb47()[0, ], .dsr47()[0, ])
  err <- tryCatch(check_sharpe_basis(tbl), error = function(e) e)
  expect_s3_class(err, "qa_s47_indeterminate")
})

test_that("S47: missing columns abort loud", {
  expect_error(build_sharpe_basis_table(.lb47()[, c("strategy", "period")], .dsr47()), "missing")
})
