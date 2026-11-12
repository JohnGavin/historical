testthat::local_edition(3)
# Tests for the Keep / Watch / Failed verdict (R/strategy_verdict.R) and its QA
# gate S51 (register coverage). Three outcomes are never collapsed: PASS / FAIL
# (qa_s51_fail) / INDETERMINATE (qa_s51_indeterminate).

source(here::here("R/strategy_verdict.R"))

names_tbl <- tibble::tibble(
  code_name = c("a_keep", "b_watch", "c_fail_ret", "d_fail_fals", "e_hind", "f_na"),
  short_name = c("A", "B", "C", "D", "E", "F")
)

lb_row <- function(strategy, net_cagr, dsr_p, under, borrow = "not_applicable",
                   period = "Full Period") {
  tibble::tibble(period = period, strategy = strategy, net_cagr = net_cagr,
                 dsr_pvalue_klogged = dsr_p, detection_underpowered = under,
                 borrow_status = borrow, sharpe = 0.5, max_dd = -0.2)
}

lb <- dplyr::bind_rows(
  lb_row("A", 0.05, 0.01, FALSE),                       # Keep
  lb_row("B", -0.01, 0.04, FALSE),                      # Watch: net <= 0, DSR ok
  lb_row("C", -0.10, 0.90, NA),                         # Failed: net < 0 and p > 0.5
  lb_row("D", 0.04, 0.02, FALSE),                       # Failed via falsification only
  lb_row("E", 0.03, 0.01, FALSE, borrow = "not_tradeable"),  # Failed: hindsight
  lb_row("F", NA_real_, NA_real_, NA),                  # all inputs missing
  lb_row("A", 9, 0, FALSE, period = "Testing")          # other periods are ignored
)

fals <- tibble::tibble(strategy = "d_fail_fals", ff_alpha_tstat = -1.0,
                       ff_r_squared = 0.5)

v <- compute_strategy_verdict(lb, names_tbl, fals)
vd <- function(id) v[v$strategy_id == id, ]

test_that("Keep needs net CAGR > 0, DSR p < 0.05 and detection powered", {
  expect_identical(vd("a_keep")$verdict, "Keep")
})

test_that("Watch names every unmet Keep criterion", {
  expect_identical(vd("b_watch")$verdict, "Watch")
  expect_match(vd("b_watch")$verdict_reason, "net CAGR not > 0", fixed = TRUE)
})

test_that("Failed on net CAGR < 0 AND DSR p > 0.5, and not on either alone", {
  expect_identical(vd("c_fail_ret")$verdict, "Failed")
  neg_only <- compute_strategy_verdict(
    lb_row("A", -0.10, 0.30, TRUE), names_tbl[1, ])
  expect_identical(neg_only$verdict, "Watch")
  high_p_only <- compute_strategy_verdict(
    lb_row("A", 0.02, 0.90, TRUE), names_tbl[1, ])
  expect_identical(high_p_only$verdict, "Watch")
})

test_that("Failed on a no-alpha falsification verdict even when returns look fine", {
  expect_identical(vd("d_fail_fals")$verdict, "Failed")
  expect_match(vd("d_fail_fals")$verdict_reason, "No alpha (beta)", fixed = TRUE)
})

test_that("Failed when the leaderboard flags the series as not tradeable", {
  expect_identical(vd("e_hind")$verdict, "Failed")
  expect_match(vd("e_hind")$verdict_reason, "not tradeable", fixed = TRUE)
})

test_that("NA inputs give an explicit reason, never a silent Watch", {
  expect_identical(vd("f_na")$verdict, "Watch")
  r <- vd("f_na")$verdict_reason
  expect_match(r, "net CAGR missing", fixed = TRUE)
  expect_match(r, "DSR p missing", fixed = TRUE)
  expect_match(r, "detection power not assessed", fixed = TRUE)
})

test_that("a strategy with no Full Period row is Watch with a stated reason", {
  out <- compute_strategy_verdict(lb[lb$strategy != "A", ], names_tbl)
  expect_match(out$verdict_reason[out$strategy_id == "a_keep"], "no Full Period row")
})

test_that("a leaderboard strategy absent from strategy_names is still a row", {
  out <- compute_strategy_verdict(
    dplyr::bind_rows(lb, lb_row("Z", 0.05, 0.01, FALSE)), names_tbl)
  expect_true("Z" %in% out$strategy_id)
})

test_that("thresholds come from the rule list (one home)", {
  rule <- utils::modifyList(STRATEGY_VERDICT_RULE, list(keep_dsr_p_below = 0.001))
  out <- compute_strategy_verdict(lb, names_tbl, fals, rule = rule)
  expect_identical(out$verdict[out$strategy_id == "a_keep"], "Watch")
})

test_that("duplicate Full Period rows abort (one row per strategy)", {
  expect_error(compute_strategy_verdict(dplyr::bind_rows(lb, lb_row("A", 1, 0, FALSE)),
                                        names_tbl), "Duplicate")
})

test_that("falsification_verdict reproduces the scorecard rule and keeps NA as NA", {
  expect_identical(falsification_verdict(c(4, 1.99, 0.5, NA), c(0.03, 0.07, 0.4, 0.1)),
                   c("Genuine alpha", "Borderline", "No alpha (beta)", NA))
})

test_that("verdict count text is derived from the verdicts", {
  expect_identical(strategy_verdict_counts_text(v$verdict),
                   sprintf("Verdict: %d Keep, %d Watch, %d Failed of %d.",
                           sum(v$verdict == "Keep"), sum(v$verdict == "Watch"),
                           sum(v$verdict == "Failed"), nrow(v)))
})

# ---- S51: register coverage ----

reg_row <- function(id, reason = "evidence") {
  tibble::tibble(strategy_id = id, reason = reason)
}
reg_full <- dplyr::bind_rows(lapply(names_tbl$code_name, reg_row))
run51 <- function(verdict_tbl, register) {
  check_strategy_register(build_strategy_register_table(verdict_tbl, register))
}

test_that("S51 PASS when every strategy has a row and every Failed has a reason", {
  out <- run51(v, reg_full)
  expect_identical(attr(out, "summary")[["fail"]], 0L)
  expect_identical(attr(out, "summary")[["examined"]], nrow(v))
})

test_that("S51 FAIL when a strategy has no register row", {
  expect_error(run51(v, reg_full[reg_full$strategy_id != "a_keep", ]),
               class = "qa_s51_fail")
})

test_that("S51 FAIL when a register row names an unknown strategy", {
  expect_error(run51(v, dplyr::bind_rows(reg_full, reg_row("ghost"))),
               class = "qa_s51_fail")
})

test_that("S51 FAIL when a Failed strategy has an empty or NA reason", {
  r1 <- reg_full; r1$reason[r1$strategy_id == "c_fail_ret"] <- NA_character_
  expect_error(run51(v, r1), class = "qa_s51_fail")
  r2 <- reg_full; r2$reason[r2$strategy_id == "c_fail_ret"] <- "  "
  expect_error(run51(v, r2), class = "qa_s51_fail")
})

test_that("S51 does not need a reason for a Watch strategy", {
  r <- reg_full; r$reason[r$strategy_id == "b_watch"] <- NA_character_
  expect_error(run51(v, r), NA)
})

test_that("S51 FAIL on a duplicated register id", {
  expect_error(run51(v, dplyr::bind_rows(reg_full, reg_row("a_keep"))),
               class = "qa_s51_fail")
})

test_that("S51 INDETERMINATE (not PASS, not FAIL) on NULL, empty or malformed input", {
  expect_error(run51(NULL, reg_full), class = "qa_s51_indeterminate")
  expect_error(run51(v, NULL), class = "qa_s51_indeterminate")
  expect_error(run51(v, reg_full[0, ]), class = "qa_s51_indeterminate")
  expect_error(run51(v, tibble::tibble(strategy_id = "a_keep")),
               class = "qa_s51_indeterminate")
})

test_that("the real register parses and covers every strategy_names row", {
  source(here::here("R/plan_strategy_names.R"))
  reg <- read_strategy_register(here::here("data", "strategy_register.csv"))
  sn <- hd_strategy_names_tbl()
  expect_setequal(reg$strategy_id, sn$code_name)
  expect_false(anyDuplicated(reg$strategy_id) > 0L)
})
