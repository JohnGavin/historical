testthat::local_edition(3)
# Regression tests for #677 slice 1: canonical, risk-free-adjusted Sharpe
# for LTR (R/plan_ltr_momentum.R).
#
# Two testing strategies are used, matching the two shapes of target in
# this file:
#
#   1. Extraction (`ltr_metrics`, `ltr_subperiod`): these targets take
#      `ltr_portfolio` (a plain tibble) as their only real input -- no file
#      I/O -- so their exact shipped command expression is extracted from
#      plan_ltr_momentum() and eval()'d against synthetic data, following
#      the pattern established in test-bound-testing-windows.R (#667). This
#      exercises the REAL shipped code, not a re-implementation.
#
#   2. Inline simulation (`ltr_portfolio`'s new rf_ret join + coverage
#      check): `ltr_portfolio` itself reads a parquet file from data/raw/
#      (gitignored, requires `nix develop . --command Rscript
#      scripts/compute_ltr_model.R` to populate) that does not exist in a
#      bare checkout, so its command cannot be eval()'d directly. Its
#      join+coverage-check logic is instead reproduced faithfully inline,
#      matching the project's established pattern for data-dependent
#      targets (see tests/testthat/test-drif.R).

source(here::here("R/plan_ltr_momentum.R"))
source(here::here("R/utils_metrics.R"))

# ── Helpers (mirrors test-bound-testing-windows.R) ──────────────────────

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) {
    stop("target '", name, "' not found (or not unique) in this plan's target list")
  }
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# Minimal stand-in for historicaldata::hd_hac_sharpe() -- ltr_metrics/
# ltr_subperiod call it for hac_sharpe/hac_tstat columns this test does not
# assert on (real HAC math is out of scope here). Deliberately NOT
# rf-adjusted, so it differs from the canonical sharpe under test.
.mock_hac_sharpe <- function(ret_vec) {
  list(hac_tstat = 0, naive_sharpe = mean(ret_vec) / stats::sd(ret_vec) * sqrt(12))
}

.toy_ltr_portfolio <- function(n_months = 60L, seed = 677L, rf_val = 0.0015) {
  set.seed(seed)
  dates <- seq(as.Date("2018-01-01"), by = "month", length.out = n_months)
  tibble::tibble(
    ym       = format(dates, "%Y-%m"),
    date     = dates,
    port_ret = stats::rnorm(n_months, mean = 0.006, sd = 0.03),
    rf_ret   = rep(rf_val, n_months),
    n_long   = 5L,
    n_short  = 5L
  )
}

# ── 1. ltr_portfolio: rf_ret join + coverage check (inline simulation) ───

test_that("ltr_portfolio: full stk_rf coverage joins rf_ret with no NA", {
  port <- tibble::tibble(ym = c("2020-01", "2020-02", "2020-03"))
  stk_rf <- tibble::tibble(
    ym = c("2020-01", "2020-02", "2020-03"),
    rf_ret = c(0.001, 0.001, 0.001)
  )

  joined <- dplyr::left_join(port, stk_rf, by = "ym")
  missing_rf_ym <- sort(joined$ym[is.na(joined$rf_ret)])

  expect_length(missing_rf_ym, 0L)
  expect_false(anyNA(joined$rf_ret))
})

test_that("ltr_portfolio: a gap in stk_rf coverage is detected -- what R/plan_ltr_momentum.R now cli_aborts on (#677 defect B)", {
  port <- tibble::tibble(ym = c("2020-01", "2020-02", "2020-03"))
  # stk_rf is missing 2020-02 -- the exact shape of the original defect
  stk_rf <- tibble::tibble(ym = c("2020-01", "2020-03"), rf_ret = c(0.001, 0.001))

  joined <- dplyr::left_join(port, stk_rf, by = "ym")
  missing_rf_ym <- sort(joined$ym[is.na(joined$rf_ret)])

  expect_equal(missing_rf_ym, "2020-02")
  expect_gt(length(missing_rf_ym), 0L)
})

# ── 2. ltr_metrics: carries both `sharpe` and `hac_sharpe`, and they differ ──

test_that("ltr_metrics: Full Period row has both sharpe and hac_sharpe, and they differ", {
  cmd <- .target_command(plan_ltr_momentum(), "ltr_metrics")
  port <- .toy_ltr_portfolio(n_months = 48L, rf_val = 0.0015)

  result <- .eval_command(
    cmd,
    hd_hac_sharpe   = .mock_hac_sharpe,
    sharpe_ratio_rf = sharpe_ratio_rf,
    ltr_params = list(
      is_end = as.Date("2019-12-31"), test_start = as.Date("2020-01-01"),
      test_end = as.Date("2020-12-31"), holdout_start = as.Date("2021-01-01"),
      holdout_end = as.Date("2021-06-30"), val_start = as.Date("2021-07-01")
    ),
    ltr_portfolio = port
  )

  full_row <- result[result$period == "Full Period", ]
  expect_equal(nrow(full_row), 1L)
  expect_true("sharpe" %in% names(full_row))
  expect_true("hac_sharpe" %in% names(full_row))
  expect_false(is.na(full_row$sharpe))
  expect_false(is.na(full_row$hac_sharpe))
  # rf-adjusted vs naive statistics are genuinely different quantities --
  # they must not be equal (the pre-#677 bug was `sharpe` being a rename of
  # `hac_sharpe`, i.e. always identical).
  expect_false(isTRUE(all.equal(full_row$sharpe, full_row$hac_sharpe)))
})

test_that("ltr_metrics: aborts loud (not silent NA) if rf_ret is missing from ltr_portfolio (#677 defect B guard)", {
  cmd <- .target_command(plan_ltr_momentum(), "ltr_metrics")
  port <- .toy_ltr_portfolio(n_months = 48L) |> dplyr::select(-rf_ret)

  expect_error(
    .eval_command(
      cmd,
      hd_hac_sharpe   = .mock_hac_sharpe,
      sharpe_ratio_rf = sharpe_ratio_rf,
      ltr_params = list(
        is_end = as.Date("2019-12-31"), test_start = as.Date("2020-01-01"),
        test_end = as.Date("2020-12-31"), holdout_start = as.Date("2021-01-01"),
        holdout_end = as.Date("2021-06-30"), val_start = as.Date("2021-07-01")
      ),
      ltr_portfolio = port
    ),
    class = "rlang_error"
  )
})

# ── 3. ltr_subperiod: sharpe is not all-NA (defect B regression) ────────

test_that("ltr_subperiod: sharpe is populated (not all-NA) when rf_ret is present -- #677 defect B", {
  cmd <- .target_command(plan_ltr_momentum(), "ltr_subperiod")
  port <- .toy_ltr_portfolio(n_months = 60L, rf_val = 0.0012)

  result <- .eval_command(
    cmd,
    hd_hac_sharpe   = .mock_hac_sharpe,
    sharpe_ratio_rf = sharpe_ratio_rf,
    ltr_portfolio   = port
  )

  expect_equal(nrow(result), 3L)
  # Pre-#677: `mean(df$rf_ret, na.rm = TRUE)` against a column that did not
  # exist on ltr_portfolio returned NA silently, so every row here was NA.
  expect_false(all(is.na(result$sharpe)))
  expect_true(all(is.finite(result$sharpe)))
})

test_that("ltr_subperiod: aborts loud (not silent NA) if rf_ret is missing from ltr_portfolio (#677 defect B guard)", {
  cmd <- .target_command(plan_ltr_momentum(), "ltr_subperiod")
  port <- .toy_ltr_portfolio(n_months = 60L) |> dplyr::select(-rf_ret)

  expect_error(
    .eval_command(
      cmd,
      hd_hac_sharpe   = .mock_hac_sharpe,
      sharpe_ratio_rf = sharpe_ratio_rf,
      ltr_portfolio   = port
    ),
    class = "rlang_error"
  )
})

# ── .ltr_join_rf() coverage policy (#677 follow-up) ─────────────────────────
#
# PR #678 aborted on ANY uncovered month. On its first real run that took the
# whole leaderboard down: ltr_portfolio spanned 2005-01..2026-03 while stk_rf
# (Fama-French) ended 2026-02. FF3 publishes with a lag, so the newest month
# routinely has no rf yet and this recurs monthly. The policy now distinguishes
# a trailing lag (trim + loud warn) from an interior hole (still abort).

.mk_port <- function(yms) tibble::tibble(ym = yms, port_ret = seq_along(yms) / 1000)
.mk_rf   <- function(yms) tibble::tibble(ym = yms, rf_ret = rep(0.001, length(yms)))

test_that(".ltr_join_rf attaches rf_ret with no NA when coverage is complete", {
  out <- .ltr_join_rf(.mk_port(c("2026-01", "2026-02")), .mk_rf(c("2026-01", "2026-02")))
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
})

test_that(".ltr_join_rf trims a trailing uncovered month and warns (the #678 breakage)", {
  port <- .mk_port(c("2026-01", "2026-02", "2026-03"))
  rf   <- .mk_rf(c("2026-01", "2026-02"))

  expect_warning(out <- .ltr_join_rf(port, rf), regexp = "2026-03")
  # The uncovered month is REMOVED, not carried as NA -- carrying it is the
  # defect B this join exists to fix.
  expect_equal(nrow(out), 2L)
  expect_false(anyNA(out$rf_ret))
  expect_false("2026-03" %in% out$ym)
})

test_that(".ltr_join_rf warning names the effective end date, not just the drop", {
  expect_warning(
    .ltr_join_rf(.mk_port(c("2026-01", "2026-02", "2026-03")), .mk_rf(c("2026-01", "2026-02"))),
    regexp = "2026-02"
  )
})

test_that(".ltr_join_rf still aborts on an INTERIOR hole -- a real FF3 gap, not a lag", {
  port <- .mk_port(c("2026-01", "2026-02", "2026-03"))
  rf   <- .mk_rf(c("2026-01", "2026-03"))  # 2026-02 missing, inside the span

  expect_error(.ltr_join_rf(port, rf), regexp = "2026-02")
  expect_error(.ltr_join_rf(port, rf), regexp = "HOLE")
})

test_that(".ltr_join_rf aborts when stk_rf lacks required columns", {
  expect_error(
    .ltr_join_rf(.mk_port("2026-01"), tibble::tibble(ym = "2026-01")),
    regexp = "rf_ret"
  )
})

test_that(".ltr_join_rf abort messages are stable", {
  port <- .mk_port(c("2026-01", "2026-02", "2026-03"))
  expect_snapshot(error = TRUE, .ltr_join_rf(port, .mk_rf(c("2026-01", "2026-03"))))
  expect_snapshot(error = TRUE, .ltr_join_rf(.mk_port("2026-01"), tibble::tibble(ym = "2026-01")))
})
