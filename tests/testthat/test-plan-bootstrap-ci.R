testthat::local_edition(3)
# Regression tests for #677 slice 2: bootstrap Sharpe CI (R/plan_bootstrap_ci.R)
# now uses the canonical, risk-free-adjusted sharpe_ratio_rf() instead of
# bare cagr/vol (implied rf of exactly 0.00%, the same formula signature as
# the rest of the "no rf deducted" family). Decision recorded in the PR:
# this IS migrated, not left as an internal-only diagnostic, because
# boot_ci_summary's "does the Sharpe CI cross zero" flag is a statistical-
# inference display compared implicitly against the rf-adjusted Sharpe
# published elsewhere for the same strategies (stk_max, stk_drif, fac_max,
# fac_drif) -- using a no-rf Sharpe here would make that comparison biased
# toward "significant" more often than warranted.

source(here::here("R/plan_bootstrap_ci.R"))
source(here::here("R/utils_metrics.R"))

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

# ── boot_monthly_returns: carries each strategy's own rf_ret ─────────────

.toy_stk_portfolio <- function(n = 36L, seed, rf_val) {
  set.seed(seed)
  yms <- format(seq(as.Date("2010-01-01"), by = "month", length.out = n), "%Y-%m")
  tibble::tibble(ym = yms, port_ret = stats::rnorm(n, 0.005, 0.02), rf_ret = rep(rf_val, n))
}
.toy_fac_portfolio <- function(n = 36L, seed, rf_val) {
  set.seed(seed)
  yms <- format(seq(as.Date("2010-01-01"), by = "month", length.out = n), "%Y-%m")
  tibble::tibble(ym = yms, portfolio_ret = stats::rnorm(n, 0.004, 0.025), rf_ret = rep(rf_val, n))
}

test_that("boot_monthly_returns: carries each strategy's own return AND rf_ret column", {
  cmd <- .target_command(plan_bootstrap_ci(), "boot_monthly_returns")

  result <- .eval_command(
    cmd,
    stk_max_portfolio  = .toy_stk_portfolio(seed = 1, rf_val = 0.002),
    stk_drif_portfolio = .toy_stk_portfolio(seed = 2, rf_val = 0.002),
    fm_portfolio        = .toy_fac_portfolio(seed = 3, rf_val = 0.002),
    drif_portfolio       = .toy_fac_portfolio(seed = 4, rf_val = 0.002)
  )

  expect_true(all(c(
    "ym", "stk_max", "stk_max_rf", "stk_drif", "stk_drif_rf",
    "fac_max", "fac_max_rf", "fac_drif", "fac_drif_rf"
  ) %in% names(result)))
  expect_false(anyNA(result$stk_max_rf))
  expect_false(anyNA(result$fac_max_rf))
})

# ── boot_metrics: rf deduction actually lowers Sharpe ────────────────────

.toy_boot_draws <- function(n = 60L, seed = 677L, rf_val = 0) {
  set.seed(seed)
  mat <- cbind(
    stk_max     = stats::rnorm(n, 0.006, 0.02),
    stk_drif    = stats::rnorm(n, 0.005, 0.022),
    fac_max     = stats::rnorm(n, 0.004, 0.018),
    fac_drif    = stats::rnorm(n, 0.0045, 0.019),
    stk_max_rf  = rep(rf_val, n),
    stk_drif_rf = rep(rf_val, n),
    fac_max_rf  = rep(rf_val, n),
    fac_drif_rf = rep(rf_val, n)
  )
  list(mat)  # single "draw" is enough to exercise calc_boot_metrics()
}

test_that("boot_metrics: sharpe is rf-adjusted, positive rf lowers sharpe vs zero-rf", {
  cmd <- .target_command(plan_bootstrap_ci(), "boot_metrics")

  res_zero <- .eval_command(
    cmd, boot_draws = .toy_boot_draws(rf_val = 0), sharpe_ratio_rf = sharpe_ratio_rf
  )
  res_pos <- .eval_command(
    cmd, boot_draws = .toy_boot_draws(rf_val = 0.003), sharpe_ratio_rf = sharpe_ratio_rf
  )

  expect_equal(nrow(res_zero), 4L)
  expect_equal(nrow(res_pos), 4L)
  expect_false(anyNA(res_zero$sharpe))
  expect_false(anyNA(res_pos$sharpe))

  for (strat in c("stk_max", "stk_drif", "fac_max", "fac_drif")) {
    sharpe_zero <- res_zero$sharpe[res_zero$strategy == strat]
    sharpe_pos  <- res_pos$sharpe[res_pos$strategy == strat]
    expect_lt(sharpe_pos, sharpe_zero)
  }
})

# ── strat_names is derived, not enumerated (#677 slice 2 review) ────────────
#
# The first form of this migration hardcoded
#   strat_names <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
# which would silently drop a fifth strategy from the bootstrap. These tests
# pin the derived behaviour so it cannot regress to an enumerated list.

.boot_strat_names <- function(cols) {
  all_cols <- setdiff(cols, "ym")
  all_cols[!grepl("_rf$", all_cols)]
}

test_that("boot strategy list is derived from the data, not hardcoded", {
  cols <- c("ym", "stk_max", "stk_max_rf", "fac_max", "fac_max_rf")
  expect_equal(.boot_strat_names(cols), c("stk_max", "fac_max"))
})

test_that("a NEW strategy column is picked up automatically", {
  cols <- c("ym", "stk_max", "stk_max_rf", "brand_new", "brand_new_rf")
  expect_true("brand_new" %in% .boot_strat_names(cols))
  expect_length(.boot_strat_names(cols), 2L)
})

test_that("rf columns are never mistaken for strategies", {
  cols <- c("ym", "stk_max", "stk_max_rf")
  expect_false(any(grepl("_rf$", .boot_strat_names(cols))))
})

test_that("boot_metrics aborts when a strategy has no paired rf column", {
  cmd <- .target_command(plan_bootstrap_ci(), "boot_metrics")
  set.seed(677)
  bad <- cbind(
    stk_max    = rnorm(12, 0.01, 0.02),
    stk_max_rf = rep(0.001, 12),
    orphan     = rnorm(12, 0.01, 0.02)   # no orphan_rf
  )
  expect_error(
    .eval_command(cmd, boot_draws = list(bad), sharpe_ratio_rf = sharpe_ratio_rf),
    regexp = "orphan_rf"
  )
})
