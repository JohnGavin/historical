testthat::local_edition(3)
# #972 step 1 (report-only): strat_deflated_sharpe gains k_trials_logged (the
# per-specification trial count) and a K-corrected deflated Sharpe pair BESIDE
# the published one. Nothing already published may move.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

.toy <- function(k_logged = 40L, rf_m = 0.004, rf_d = 0.0002) {
  set.seed(972)
  n   <- 240L
  yms <- format(seq(as.Date("2000-01-15"), by = "month", length.out = n), "%Y-%m")
  dts <- seq(as.Date("2020-01-01"), by = "day", length.out = 400L)
  wide <- tibble::tibble(ym = yms)
  for (cn in c("stk_max", "stk_drif", "fac_max", "fac_drif", "ltr", "xgb_drif",
               "mom_prepeak", "mom_postpeak", "mom_combined", "managed_futures",
               "value_hml")) {
    wide[[cn]] <- stats::rnorm(n, 0.004, 0.03)
  }
  daily <- function() tibble::tibble(date = dts, ret = stats::rnorm(400L, 0.0004, 0.01))
  cw <- rep(c(0, 0.5, 1, 0.25), length.out = 400L)
  cmr_cond <- tibble::tibble(
    date = dts, ret = (1 - cw) * stats::rnorm(400L, 0.0004, 0.01) + cw * rf_d,
    cash_weight = cw, rf_ret = rf_d
  )
  list(
    strat_returns_wide = wide,
    strat_returns_daily_native = list(
      cmr = daily(), cmr_conditioned = cmr_cond, olmar_1 = daily(),
      tom = daily(), risk_state = daily(), avoid_worst = daily()
    ),
    ev_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf_m),
    mf_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf_m),
    olmar_portfolio = tibble::tibble(date = dts, rf_ret = rf_d),
    tom_portfolio = tibble::tibble(date = dts, rf_ret = rf_d),
    rsc_portfolio = tibble::tibble(date = dts, rf_daily = rf_d),
    aw_daily_rf = tibble::tibble(date = dts, rf_ret = rf_d),
    strat_keff_vertox_leaderboard = 5,
    strat_corr_matrix_leaderboard = diag(5),
    strat_keff_vertox = 3,
    strat_corr_matrix = diag(3),
    strat_k_trials_logged = k_logged
  )
}

.run <- function(toy) {
  cmd <- .target_command(plan_leaderboard(), "strat_deflated_sharpe")
  env <- list2env(toy, envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

.new_cols <- c("k_trials_logged", "deflated_sharpe_klogged", "dsr_pvalue_klogged")

test_that("the three new columns are appended; every pre-existing column keeps its name and order", {
  out <- .run(.toy())
  expect_true(all(.new_cols %in% names(out)))
  old <- setdiff(names(out), .new_cols)
  expect_equal(old, c("strategy", "naive_sharpe", "T_obs", "deflated_sharpe",
                      "dsr_pvalue", "dsr_convention", "dsr_haircut_pct",
                      "sharpe_haircut", "sharpe_haircut_pct",
                      "k_eff_leaderboard", "k_raw_leaderboard",
                      "k_eff_family", "k_raw_family"))
})

test_that("REPORT-ONLY: changing the logged K moves ONLY the new columns, bit-for-bit", {
  a <- .run(.toy(k_logged = 3L))
  b <- .run(.toy(k_logged = 400L))
  old <- setdiff(names(a), .new_cols)
  expect_identical(a[, old], b[, old])
  # ... and the new DSR columns really do respond to K (not a no-op).
  ok <- !is.na(a$deflated_sharpe_klogged)
  expect_true(any(ok))
  expect_true(all(a$deflated_sharpe_klogged[ok] > b$deflated_sharpe_klogged[ok]))
})

test_that("published columns equal the pre-#972 formula (K = k_eff) on the same series", {
  toy <- .toy()
  out <- .run(toy)
  exp <- hd_deflated_sharpe(toy$strat_returns_wide$mom_prepeak, K_trials = 5L,
                            ann_factor = 12L)
  row <- out[out$strategy == "Mom Pre-Peak", ]
  expect_identical(row$deflated_sharpe, exp$dsr)
  expect_identical(row$dsr_pvalue, exp$dsr_pvalue)
  expect_identical(row$naive_sharpe, exp$naive_sharpe)
})

test_that("the klogged pair is hd_deflated_sharpe() on the SAME series with K = k_trials_logged", {
  toy <- .toy(k_logged = 40L)
  out <- .run(toy)
  exp <- hd_deflated_sharpe(toy$strat_returns_wide$mom_prepeak, K_trials = 40L,
                            ann_factor = 12L)
  row <- out[out$strategy == "Mom Pre-Peak", ]
  expect_identical(row$deflated_sharpe_klogged, exp$dsr)
  expect_identical(row$dsr_pvalue_klogged, exp$dsr_pvalue)
  expect_true(all(out$k_trials_logged == 40L))
})

test_that("FALSIFICATION: with k_trials_logged == k_eff the pair equals the published one", {
  out <- .run(.toy(k_logged = 5L))
  expect_identical(out$deflated_sharpe_klogged, out$deflated_sharpe)
  expect_identical(out$dsr_pvalue_klogged, out$dsr_pvalue)
})

test_that("klogged is NA wherever the published value is NA, and never 0", {
  toy <- .toy()
  toy$strat_returns_wide$fac_max[] <- NA_real_
  out <- .run(toy)
  expect_identical(is.na(out$deflated_sharpe_klogged), is.na(out$deflated_sharpe))
  expect_identical(is.na(out$dsr_pvalue_klogged), is.na(out$dsr_pvalue))
  fm <- out[out$strategy == "Factor MAX", ]
  expect_true(is.na(fm$deflated_sharpe_klogged))
  expect_true(is.na(fm$dsr_pvalue_klogged))
  expect_false(any(out$deflated_sharpe_klogged == 0, na.rm = TRUE))
})

test_that("a non-positive or non-scalar logged K aborts instead of being used", {
  expect_snapshot(error = TRUE, .run(.toy(k_logged = 0L)))
  expect_snapshot(error = TRUE, .run(.toy(k_logged = c(3L, 4L))))
  expect_snapshot(error = TRUE, .run(.toy(k_logged = NA_integer_)))
})

test_that("WIRING: the leaderboard joins the new columns from strat_deflated_sharpe", {
  hit <- vapply(plan_leaderboard(), function(t) identical(t$settings$name, "leaderboard"), logical(1))
  expect_equal(sum(hit), 1L)
  body <- gsub("\\s+", " ", paste(deparse(plan_leaderboard()[[which(hit)]]$command$expr), collapse = " "))
  expect_match(body, "k_trials_logged", fixed = TRUE)
  expect_match(body, "deflated_sharpe_klogged", fixed = TRUE)
  expect_match(body, "dsr_pvalue_klogged", fixed = TRUE)
})

test_that("strat_k_trials_logged is a target that calls hd_strategy_spec_trial_count()", {
  cmd <- .target_command(plan_leaderboard(), "strat_k_trials_logged")
  expect_match(paste(deparse(cmd), collapse = " "), "hd_strategy_spec_trial_count", fixed = TRUE)
})
