# Tests for S43 (DSR-vs-leaderboard window coverage) and S44 (DSR p-value vs
# prob_sharpe_positive ordering) -- Refs #937, #919.
#
# S43 origin: strat_deflated_sharpe scored Factor MAX over 193 months while the
# leaderboard row sat on 740, because strat_returns_wide was cut to the stock
# window. Nothing compared the two counts.
# S44 origin (#919): `1 - dsr_pvalue <= prob_sharpe_positive` must hold -- the
# DSR benchmarks against the best of K trials, so it can never be MORE
# confident than the plain probabilistic Sharpe. It was violated for Value
# (HML) when the two paths used different Sharpe bases.
testthat::local_edition(3)

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Fixtures ────────────────────────────────────────────────────────────────
.lb <- function(strats = c("Factor MAX", "Stock MAX", "Mom Pre-Peak", "PSO Optimal"),
                mths = c(740, 255, 637, 195)) {
  tibble::tibble(
    strategy = rep(strats, 2L),
    period   = rep(c("Full Period", "Training"), each = length(strats)),
    months   = c(mths, mths / 2),
    sharpe   = c(0.39, -0.8, 0.44, 0.13, 0.2, -0.5, 0.3, 0.1),
    dsr_pvalue = c(0.966, 1, 0.03, NA, 0.966, 1, 0.03, NA),
    prob_sharpe_positive = c(0.686, NA, 1, 0.70, 0.5, NA, 0.9, 0.6)
  )
}
.dsr <- function(strategy = c("Factor MAX", "Stock MAX", "Mom Pre-Peak"),
                 T_obs = c(740L, 255L, 638L)) {
  tibble::tibble(strategy = strategy, T_obs = T_obs)
}
.allow <- tibble::tibble(
  strategy = "Mom Pre-Peak", max_rel_diff = 0.0025,
  reason = "test: one-month offset"
)

# ═══ S43 ════════════════════════════════════════════════════════════════════
test_that("S43 GREEN: matching windows pass; an allow-listed drift within its bound is tolerated", {
  tbl <- build_dsr_coverage_table(.lb(), .dsr(), allowlist = .allow, excluded = "PSO Optimal")
  expect_equal(tbl$verdict[tbl$strategy == "Factor MAX"], "PASS")
  expect_equal(tbl$verdict[tbl$strategy == "Mom Pre-Peak"], "PASS_ALLOWLISTED")
  expect_false("PSO Optimal" %in% tbl$strategy)
  out <- check_dsr_coverage(tbl, allowlist = .allow)
  s <- attr(out, "summary")
  expect_equal(unname(s[c("pass", "fail", "indeterminate")]), c(3L, 0L, 0L))
})

test_that("S43 RED: the pre-fix Factor MAX shape (193 vs 740) is a FAIL naming the strategy and both counts", {
  tbl <- build_dsr_coverage_table(
    .lb(), .dsr(T_obs = c(193L, 255L, 638L)), allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_equal(tbl$verdict[tbl$strategy == "Factor MAX"], "FAIL")
  expect_snapshot(error = TRUE, check_dsr_coverage(tbl, allowlist = .allow))
})

test_that("S43: an allow-listed drift BEYOND its bound is a FAIL, not a pass", {
  tbl <- build_dsr_coverage_table(
    .lb(), .dsr(T_obs = c(740L, 255L, 700L)), allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_equal(tbl$verdict[tbl$strategy == "Mom Pre-Peak"], "FAIL")
})

test_that("S43: a strategy in only one table, or an NA count, is INDETERMINATE (distinct class), never PASS or FAIL", {
  tbl <- build_dsr_coverage_table(
    .lb(), .dsr(strategy = c("Factor MAX", "Mom Pre-Peak"), T_obs = c(740L, 638L)),
    allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_equal(tbl$verdict[tbl$strategy == "Stock MAX"], "INDETERMINATE")
  expect_match(tbl$detail[tbl$strategy == "Stock MAX"], "missing_in_dsr")

  tbl2 <- build_dsr_coverage_table(
    .lb(), .dsr(T_obs = c(NA, 255L, 638L)), allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_equal(tbl2$verdict[tbl2$strategy == "Factor MAX"], "INDETERMINATE")
  expect_match(tbl2$detail[tbl2$strategy == "Factor MAX"], "na_value")

  tbl3 <- build_dsr_coverage_table(
    .lb(), rbind(.dsr(), .dsr(strategy = "Extra", T_obs = 10L)),
    allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_match(tbl3$detail[tbl3$strategy == "Extra"], "missing_in_leaderboard")

  # INDETERMINATE aborts with its OWN class and message, separate from FAIL
  err <- tryCatch(check_dsr_coverage(tbl, allowlist = .allow), error = function(e) e)
  expect_s3_class(err, "qa_s43_indeterminate")
  expect_false(inherits(err, "qa_s43_fail"))
  expect_snapshot(error = TRUE, check_dsr_coverage(tbl, allowlist = .allow))
})

test_that("S43: FAIL and INDETERMINATE together abort with the FAIL class and BOTH counts", {
  tbl <- build_dsr_coverage_table(
    .lb(), .dsr(strategy = c("Factor MAX", "Mom Pre-Peak"), T_obs = c(193L, 638L)),
    allowlist = .allow, excluded = "PSO Optimal"
  )
  err <- tryCatch(check_dsr_coverage(tbl, allowlist = .allow), error = function(e) e)
  expect_s3_class(err, "qa_s43_fail")
  expect_match(conditionMessage(err), "1 fail", fixed = TRUE)
  expect_match(conditionMessage(err), "1 indeterminate", fixed = TRUE)
})

test_that("S43: a STALE allow-list entry (no drift any more) is reported, not silently kept", {
  tbl <- build_dsr_coverage_table(
    .lb(), .dsr(T_obs = c(740L, 255L, 637L)), allowlist = .allow, excluded = "PSO Optimal"
  )
  expect_equal(tbl$verdict[tbl$strategy == "Mom Pre-Peak"], "PASS")
  expect_warning(out <- check_dsr_coverage(tbl, allowlist = .allow), "stale")
  expect_equal(attr(out, "summary")[["stale"]], 1L)
})

test_that("S43: every allow-list entry must carry a written reason (no blank exemptions)", {
  bad <- tibble::tibble(strategy = "Mom Pre-Peak", max_rel_diff = 0.0025, reason = "")
  expect_snapshot(
    error = TRUE,
    build_dsr_coverage_table(.lb(), .dsr(), allowlist = bad, excluded = "PSO Optimal")
  )
})

test_that("S43 NON-VACUOUS: a gate that examined zero rows is INDETERMINATE, not a pass", {
  empty_lb <- .lb()[0, ]
  expect_snapshot(
    error = TRUE,
    check_dsr_coverage(
      build_dsr_coverage_table(empty_lb, .dsr()[0, ], allowlist = .allow, excluded = "PSO Optimal"),
      allowlist = .allow
    )
  )
})

test_that("S43 summary counts rows examined (non-vacuity is observable)", {
  tbl <- build_dsr_coverage_table(.lb(), .dsr(), allowlist = .allow, excluded = "PSO Optimal")
  s <- attr(check_dsr_coverage(tbl, allowlist = .allow), "summary")
  expect_equal(s[["examined"]], 3L)
})

# ═══ S44 ════════════════════════════════════════════════════════════════════
test_that("S44 GREEN: 1 - dsr_pvalue <= prob_sharpe_positive; NA prob on a negative-Sharpe row is not applicable", {
  tbl <- build_psr_vs_dsr_table(.lb(), excluded = "PSO Optimal")
  expect_equal(tbl$verdict[tbl$strategy == "Factor MAX"], "PASS")
  expect_equal(tbl$verdict[tbl$strategy == "Stock MAX"], "NOT_APPLICABLE")
  out <- check_psr_vs_dsr(tbl)
  s <- attr(out, "summary")
  expect_equal(s[["pass"]], 2L)
  expect_equal(s[["not_applicable"]], 1L)
  expect_equal(s[["examined"]], 2L)
})

test_that("S44 RED: a #919-style violation (DSR more confident than the plain PSR) FAILs and names the numbers", {
  lb <- .lb()
  lb$prob_sharpe_positive[lb$strategy == "Factor MAX" & lb$period == "Full Period"] <- 0.20
  lb$dsr_pvalue[lb$strategy == "Factor MAX" & lb$period == "Full Period"] <- 0.05   # 1 - p = 0.95 > 0.20
  tbl <- build_psr_vs_dsr_table(lb, excluded = "PSO Optimal")
  expect_equal(tbl$verdict[tbl$strategy == "Factor MAX"], "FAIL")
  expect_snapshot(error = TRUE, check_psr_vs_dsr(tbl))
})

test_that("S44: NA prob on a POSITIVE-Sharpe row is NOT_COMPUTED (distinct from not-applicable) and aborts", {
  lb <- .lb()
  lb$prob_sharpe_positive[lb$strategy == "Mom Pre-Peak" & lb$period == "Full Period"] <- NA_real_
  tbl <- build_psr_vs_dsr_table(lb, excluded = "PSO Optimal")
  expect_equal(tbl$verdict[tbl$strategy == "Mom Pre-Peak"], "NOT_COMPUTED")
  err <- tryCatch(check_psr_vs_dsr(tbl), error = function(e) e)
  expect_s3_class(err, "qa_s44_fail")
  expect_match(conditionMessage(err), "NOT_COMPUTED", fixed = TRUE)
})

test_that("S44: missing dsr_pvalue (outside the documented exclusion) is INDETERMINATE with its own class", {
  lb <- .lb()
  lb$dsr_pvalue[lb$strategy == "Factor MAX" & lb$period == "Full Period"] <- NA_real_
  tbl <- build_psr_vs_dsr_table(lb, excluded = "PSO Optimal")
  expect_equal(tbl$verdict[tbl$strategy == "Factor MAX"], "INDETERMINATE")
  err <- tryCatch(check_psr_vs_dsr(tbl), error = function(e) e)
  expect_s3_class(err, "qa_s44_indeterminate")
  expect_false(inherits(err, "qa_s44_fail"))
  expect_snapshot(error = TRUE, check_psr_vs_dsr(tbl))
})

test_that("S44: the documented exclusion (PSO Optimal, no DSR row) is reported as excluded, not INDETERMINATE", {
  tbl <- build_psr_vs_dsr_table(.lb(), excluded = "PSO Optimal")
  expect_false("PSO Optimal" %in% tbl$strategy)
  # ...and WITHOUT the exclusion the same data is INDETERMINATE (the exclusion is doing real work)
  tbl2 <- build_psr_vs_dsr_table(.lb(), excluded = character(0))
  expect_equal(tbl2$verdict[tbl2$strategy == "PSO Optimal"], "INDETERMINATE")
})

test_that("S44 NON-VACUOUS: zero Full-Period rows examined is INDETERMINATE", {
  lb <- .lb()
  lb$period <- "Training"
  expect_snapshot(
    error = TRUE,
    check_psr_vs_dsr(build_psr_vs_dsr_table(lb, excluded = "PSO Optimal"))
  )
})
