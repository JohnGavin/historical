testthat::local_edition(3)
# #937 phase 2, group B: commodity momentum / momentum decomposition / regime
# momentum / Zakamulin allocation Sharpes.
#
# Every series here is a dollar-neutral long-short spread (weights
# +1/(2*n_long), -1/(2*n_short) sum to zero), or such a spread scaled by an
# exposure in [0, 1] whose cash leg earns 0 by construction. It is an EXCESS
# return, so NO rf is deducted. The old code deducted a monthly rf (hardcoded
# 2%/yr or stk_rf) -- or rf * mean_allocation -- from them.
#
# Approximation (see hd_return_basis()): "excess, no rf" treats long funding
# and short rebate as cancelling; the residual is the funding/rebate spread.
#
# No new cli_abort is added by the fix (the label guard is the existing
# .require_basis_label()), so the missing/unregistered-label checks use
# expect_error(): a snapshot would embed the whole registry listing and churn
# every time any phase adds a row.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
suppressMessages(library(dplyr))
source(here::here("R/utils_metrics.R"))
source(here::here("R/commodities_momentum.R"))
source(here::here("R/momentum_decomposition.R"))
source(here::here("R/regime_momentum.R"))
source(here::here("R/zakamulin_allocation.R"))
source(here::here("R/plan_commodities_momentum.R"))
suppressMessages(library(targets))
source(here::here("R/plan_momentum_decomposition.R"))

LBL_COMM   <- "Commodity Momentum L/S"
LBL_DECOMP <- "Momentum Decomposition L/S"
LBL_REGIME <- "Regime Momentum"

# A spread whose monthly mean (0.002) is BELOW the monthly equivalent of a
# 6%/yr rf (0.00487): the rf-deducted Sharpe is negative, the excess Sharpe is
# positive. This is the shape that flips an "any positive Sharpe" verdict.
.ret <- rep(c(0.012, -0.008), 30L)        # mean 0.002, sd > 0
.annual_rf <- 0.06
.mrf <- (1 + .annual_rf)^(1 / 12) - 1
.excess_sharpe <- function(x) mean(x) / stats::sd(x) * sqrt(12)

# ── Registry ────────────────────────────────────────────────────────────────

test_that("the three group-B labels are registered on the excess basis", {
  for (l in c(LBL_COMM, LBL_DECOMP, LBL_REGIME)) {
    expect_identical(hd_return_basis_of(l), "excess")
  }
  reg <- hd_return_basis()
  expect_true(all(nzchar(reg$evidence[reg$strategy %in% c(LBL_COMM, LBL_DECOMP, LBL_REGIME)])))
})

# ── summarize_commodity_performance ─────────────────────────────────────────

.comm_bt <- function(ret = .ret) {
  tibble::tibble(
    date = rep(seq(as.Date("2020-01-31"), by = "month", length.out = length(ret)), 2L),
    strategy = rep(c("baseline", "short_long"), each = length(ret)),
    portfolio_ret = c(ret, ret), turnover = 0.1, cost = 0.0002,
    net_ret = c(ret, ret), n_positions = 20L
  )
}

test_that("summarize_commodity_performance: excess label deducts no rf", {
  res <- summarize_commodity_performance(.comm_bt(), annual_rf = .annual_rf,
                                         strategy = LBL_COMM)
  expect_equal(res$sharpe, rep(.excess_sharpe(.ret), 2L))
  expect_equal(res$gross_sharpe, rep(.excess_sharpe(.ret), 2L))
})

test_that("summarize_commodity_performance: a total label still deducts rf (control)", {
  res <- summarize_commodity_performance(.comm_bt(), annual_rf = .annual_rf,
                                         strategy = "Value (HML)")
  expect_equal(res$sharpe, rep((mean(.ret) - .mrf) / stats::sd(.ret) * sqrt(12), 2L))
})

test_that("summarize_commodity_performance: missing / unregistered label aborts", {
  expect_error(summarize_commodity_performance(.comm_bt()), "strategy")
  expect_error(summarize_commodity_performance(.comm_bt(), strategy = "Not A Strategy"),
               "not registered")
})

test_that("DECISION: the rescue test's 'any positive Sharpe' flips when rf stops being deducted", {
  res <- summarize_commodity_performance(.comm_bt(), annual_rf = .annual_rf,
                                         strategy = LBL_COMM)
  # old behaviour: sharpe < 0 everywhere -> verdict UNIVERSAL FAILURE
  old <- (mean(.ret) - .mrf) / stats::sd(.ret) * sqrt(12)
  expect_lt(old, 0)
  expect_true(any(res$sharpe > 0))
})

# ── summarize_backtest_performance (momentum decomposition) ─────────────────

.decomp_bt <- function(ret = .ret) {
  tibble::tibble(
    date = rep(seq(as.Date("2020-01-31"), by = "month", length.out = length(ret)), 2L),
    scheme = rep(c("baseline", "paper"), each = length(ret)),
    portfolio_ret = c(ret, ret), turnover = 0.1, cost = 0.0002,
    net_ret = c(ret, ret), n_positions = 100L
  )
}

test_that("summarize_backtest_performance: excess label deducts no rf", {
  res <- summarize_backtest_performance(.decomp_bt(), annual_rf = .annual_rf,
                                        strategy = LBL_DECOMP)
  expect_equal(res$sharpe, rep(.excess_sharpe(.ret), 2L))
  expect_equal(res$gross_sharpe, rep(.excess_sharpe(.ret), 2L))
})

test_that("summarize_backtest_performance: missing / unregistered label aborts", {
  expect_error(summarize_backtest_performance(.decomp_bt()), "strategy")
  expect_error(summarize_backtest_performance(.decomp_bt(), strategy = "Not A Strategy"),
               "not registered")
})

# ── regime_conditional_performance / compare_regime_allocation ──────────────

.regime_tbl <- function(ret = .ret) {
  n <- length(ret)
  tibble::tibble(
    date = seq(as.Date("2020-01-31"), by = "month", length.out = n),
    scheme = "baseline", net_ret = ret, portfolio_ret = ret,
    turnover = 0.1, cost = 0.0002,
    regime = factor(rep("calm", n), levels = c("calm", "elevated", "spike")),
    mean_vix = rep(18, n), max_vix = rep(22, n)
  )
}

test_that("regime_conditional_performance: excess label deducts no rf", {
  res <- regime_conditional_performance(.regime_tbl(), annual_rf = .annual_rf,
                                        strategy = LBL_REGIME)
  expect_equal(res$sharpe, .excess_sharpe(.ret))
})

test_that("regime_conditional_performance: missing / unregistered label aborts", {
  expect_error(regime_conditional_performance(.regime_tbl()), "strategy")
  expect_error(regime_conditional_performance(.regime_tbl(), strategy = "Not A Strategy"),
               "not registered")
})

test_that("compare_regime_allocation: allocated excess spread has no rf term", {
  res <- compare_regime_allocation(.regime_tbl(), regimes = "calm", strategy = LBL_REGIME)
  binary <- res[res$allocation_type == "binary", ]
  # exposure is 1 in every (calm) month so allocated_ret == net_ret
  expect_equal(binary$sharpe, .excess_sharpe(.ret))
  expect_error(compare_regime_allocation(.regime_tbl()), "strategy")
})

test_that("DECISION: regime rescue test input flips when rf stops being deducted", {
  old <- (mean(.ret) - .mrf) / stats::sd(.ret) * sqrt(12)
  new <- regime_conditional_performance(.regime_tbl(), annual_rf = .annual_rf,
                                        strategy = LBL_REGIME)$sharpe
  expect_lt(old, 0)
  expect_gt(new, 0)
})

# ── summarize_regime_allocation ─────────────────────────────────────────────

.alloc_bt <- function() {
  n <- length(.ret)
  alloc <- rep(c(1, 0.5), length.out = n)
  tibble::tibble(
    date = seq(as.Date("2020-01-31"), by = "month", length.out = n),
    scheme = "baseline", signal_type = "raw", allocation_fn = "linear",
    net_ret = .ret, allocation = alloc, allocated_ret = alloc * .ret
  )
}

test_that("summarize_regime_allocation: neither Sharpe deducts rf (cash leg earns 0)", {
  bt <- .alloc_bt()
  res <- summarize_regime_allocation(bt, annual_rf = .annual_rf, strategy = LBL_REGIME)
  expect_equal(res$sharpe, .excess_sharpe(bt$net_ret))
  expect_equal(res$sharpe_allocated, .excess_sharpe(bt$allocated_ret))
})

test_that("summarize_regime_allocation: missing / unregistered label aborts", {
  expect_error(summarize_regime_allocation(.alloc_bt()), "strategy")
  expect_error(summarize_regime_allocation(.alloc_bt(), strategy = "Not A Strategy"),
               "not registered")
})

test_that("summarize_regime_allocation: allocated-vs-baseline gap on the excess basis", {
  # With rf deducted the baseline is penalised by the full rf but the
  # allocated series only by rf * mean_allocation, so the comparison was tilted
  # toward allocation. On the excess basis neither is penalised.
  bt <- .alloc_bt()
  new <- summarize_regime_allocation(bt, annual_rf = .annual_rf, strategy = LBL_REGIME)
  old_base  <- (mean(bt$net_ret) - .mrf) / stats::sd(bt$net_ret) * sqrt(12)
  old_alloc <- (mean(bt$allocated_ret) - .mrf * mean(bt$allocation)) /
    stats::sd(bt$allocated_ret) * sqrt(12)
  expect_false(isTRUE(all.equal(new$sharpe_allocated - new$sharpe, old_alloc - old_base)))
})

# ── Rolling-Sharpe plot targets (hardcoded 2%/yr rf) ────────────────────────

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}
.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

test_that("commodities_rolling_sharpe_plot: rolling Sharpe has no rf deducted", {
  skip_if_not_installed("slider")
  cmd <- .target_command(plan_commodities_momentum(), "commodities_rolling_sharpe_plot")
  bt <- .comm_bt(rep(c(0.012, -0.008), 30L))
  p <- .eval_command(cmd, commodities_backtest = bt)
  d <- p$data[p$data$strategy == "baseline" & !is.na(p$data$rolling_sharpe_36m), ]
  expect_gt(nrow(d), 0L)
  last <- tail(bt$net_ret[bt$strategy == "baseline"], 36L)
  expect_equal(tail(d$rolling_sharpe_36m, 1L), .excess_sharpe(last))
})

test_that("rolling_sharpe_plot (momentum decomposition): no rf deducted", {
  skip_if_not_installed("slider")
  cmd <- .target_command(plan_momentum_decomposition(), "rolling_sharpe_plot")
  bt <- .decomp_bt(rep(c(0.012, -0.008), 30L))
  p <- .eval_command(cmd, backtest_results = bt)
  d <- p$data[p$data$scheme == "baseline", ]
  last <- tail(bt$net_ret[bt$scheme == "baseline"], 36L)
  expect_equal(tail(d$rolling_sharpe, 1L), .excess_sharpe(last))
})
