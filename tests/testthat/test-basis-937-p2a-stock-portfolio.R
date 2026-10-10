testthat::local_edition(3)
# #937 Phase 2, group A: rf deducted from series that are ALREADY on an excess
# basis (stock / portfolio / regime / DRIF-multiverse / alpha-decay sites).
#
# Rule (hd_return_basis()): a Sharpe is on an EXCESS basis; rf is deducted iff
# the series is a TOTAL return. A dollar-neutral long-short spread is already
# excess; a blend deducts rf only on the cash leg.
#
#   * .port_neg_sharpe     -- PSO objective (picks the weights)
#   * .drif_mv_perf        -- drif_multiverse per-spec Sharpe
#   * .decay_metrics_row   -- decay_metrics per strategy x delay Sharpe
#   * market_impact_sensitivity -- Sharpe-vs-eta panel
#   * regime_metrics       -- base row EXCESS, regime-adjusted row BLEND
#
# Every test uses a constant, deliberately LARGE rf (0.004/month, ~4.9%/yr)
# so a wrong deduction or omission moves a Sharpe by far more than tolerance.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_portfolio_opt.R"))
source(here::here("R/plan_drif_v2.R"))
source(here::here("R/plan_alpha_decay.R"))
source(here::here("R/plan_regime.R"))
local_env_stk <- new.env(parent = globalenv())
suppressWarnings(sys.source(here::here("R/plan_stock_backtest.R"),
                            envir = local_env_stk, keep.source = FALSE))

RF_M <- 0.004

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

.std <- function(x, mean, sd) as.numeric(scale(x)) * sd + mean

# ── registry ────────────────────────────────────────────────────────────────
test_that("registry: the regime-adjusted PSO series is a registered BLEND", {
  expect_identical(hd_return_basis_of("PSO Regime-Adjusted"), "blend")
  reg <- hd_return_basis()
  expect_identical(reg$cash_weight_col[reg$strategy == "PSO Regime-Adjusted"], "cash_weight")
})

# ── PSO objective ───────────────────────────────────────────────────────────
.pso_fixture <- function() {
  set.seed(9371)
  n <- 120L
  m <- cbind(
    stk_max  = .std(rnorm(n), 0.012, 0.060),   # high return, high vol
    stk_drif = .std(rnorm(n), 0.004, 0.010)    # low return, low vol
  )
  list(m = m, rf = rep(RF_M, n))
}

test_that(".port_neg_sharpe is minus the EXCESS-basis Sharpe: no rf deducted (#937)", {
  fx <- .pso_fixture()
  w <- c(0.5, 0.5)
  r <- as.numeric(fx$m %*% w)
  n <- length(r)
  want <- -((prod(1 + r)^(12 / n) - 1) / (sd(r) * sqrt(12)))
  expect_equal(.port_neg_sharpe(w, fx$m, fx$rf), want, tolerance = 1e-10)
})

test_that(".port_neg_sharpe: the rf-deducted objective would pick DIFFERENT weights (decision at stake)", {
  fx <- .pso_fixture()
  grid <- seq(0, 1, by = 0.01)
  best_excess <- grid[which.min(vapply(grid, function(a)
    .port_neg_sharpe(c(a, 1 - a), fx$m, fx$rf), numeric(1)))]
  # reference: what the OLD objective (rf deducted from an excess series) picks
  old_obj <- function(a) {
    r <- as.numeric(fx$m %*% c(a, 1 - a)); n <- length(r)
    -(((prod(1 + r)^(12 / n) - 1) - mean(fx$rf) * 12) / (sd(r) * sqrt(12)))
  }
  best_old <- grid[which.min(vapply(grid, old_obj, numeric(1)))]
  expect_false(isTRUE(all.equal(best_excess, best_old)))
  # the helper must agree with the EXCESS argmax, not the old one
  ref <- function(a) {
    r <- as.numeric(fx$m %*% c(a, 1 - a)); n <- length(r)
    -((prod(1 + r)^(12 / n) - 1) / (sd(r) * sqrt(12)))
  }
  expect_identical(best_excess, grid[which.min(vapply(grid, ref, numeric(1)))])
})

# ── drif_multiverse ─────────────────────────────────────────────────────────
test_that(".drif_mv_perf: Factor DRIF is an EXCESS spread -- rf not deducted (#937)", {
  set.seed(9372)
  n <- 60L
  port <- tibble::tibble(ym = format(seq(as.Date("2015-01-01"), by = "month", length.out = n), "%Y-%m"),
                         port_ret = .std(rnorm(n), 0.006, 0.03), rf = rep(RF_M, n))
  out <- .drif_mv_perf(port)
  want <- (prod(1 + port$port_ret)^(12 / n) - 1) / (sd(port$port_ret) * sqrt(12))
  expect_equal(out$oos_sharpe, want, tolerance = 1e-10)
  # falsification: the rf-deducted number is materially different
  old <- (prod(1 + port$port_ret - RF_M)^(12 / n) - 1) / (sd(port$port_ret) * sqrt(12))
  expect_gt(abs(want - old), 0.3)
})

test_that(".drif_mv_perf: an NA rf does not change an excess Sharpe", {
  set.seed(9373)
  n <- 36L
  port <- tibble::tibble(ym = format(seq(as.Date("2015-01-01"), by = "month", length.out = n), "%Y-%m"),
                         port_ret = .std(rnorm(n), 0.006, 0.03), rf = rep(NA_real_, n))
  out <- .drif_mv_perf(port)
  want <- (prod(1 + port$port_ret)^(12 / n) - 1) / (sd(port$port_ret) * sqrt(12))
  expect_equal(out$oos_sharpe, want, tolerance = 1e-10)
})

# ── decay_metrics ───────────────────────────────────────────────────────────
test_that(".decay_metrics_row: stk_max / stk_drif are EXCESS long-short spreads (#937)", {
  set.seed(9374)
  n <- 60L
  port <- tibble::tibble(ym = format(seq(as.Date("2015-01-01"), by = "month", length.out = n), "%Y-%m"),
                         port_ret = .std(rnorm(n), 0.008, 0.03), rf_ret = rep(RF_M, n))
  want <- (prod(1 + port$port_ret)^(12 / n) - 1) / (sd(port$port_ret) * sqrt(12))
  for (s in c("stk_max", "stk_drif")) {
    out <- .decay_metrics_row(port, s, 3L)
    expect_equal(out$sharpe, want, tolerance = 1e-10, info = s)
    expect_equal(out$delay, 3L)
  }
})

test_that(".decay_metrics_row: an unmapped strategy name aborts (never a silent default)", {
  port <- tibble::tibble(port_ret = rep(c(0.01, -0.005), 20L), rf_ret = RF_M)
  expect_snapshot(error = TRUE, .decay_metrics_row(port, "not_a_strategy", 1L))
})

# ── Sharpe-vs-eta panel ─────────────────────────────────────────────────────
.impact_fixture <- function() {
  returns_wide <- tibble::tibble(
    ym = c("2019-11", "2019-12"),
    L1 = c(0.01, 0.01), L2 = c(0.01, 0.01), S1 = c(0.01, 0.01), S2 = c(0.01, 0.01)
  )
  df <- tibble::tibble(
    ym = c(rep("2020-01", 4), rep("2020-02", 4)),
    ticker = rep(c("L1", "L2", "S1", "S2"), 2),
    decile = rep(c(1L, 1L, 10L, 10L), 2),
    monthly_ret = c(0.02, 0.03, -0.01, 0.00, 0.01, 0.02, 0.00, 0.01)
  )
  adv_monthly <- tibble::tibble(
    ym = c(rep("2020-01", 4), rep("2020-02", 4)),
    ticker = rep(c("L1", "L2", "S1", "S2"), 2),
    adv_dollars = rep(c(6e7, 4e7, 3e7, 2e7), 2)
  )
  list(returns_wide = returns_wide, df = df, adv_monthly = adv_monthly,
       rf = tibble::tibble(ym = c("2020-01", "2020-02"), rf_ret = RF_M))
}

test_that("market_impact_sensitivity: a decile long-short spread is EXCESS -- rf not deducted (#937)", {
  fx <- .impact_fixture()
  out <- local_env_stk$market_impact_sensitivity(
    fx$df, fx$returns_wide, eta_grid = c(0.5, 1), lookback_months = 1L,
    adv_monthly = fx$adv_monthly, adv_pct_cap = 1, impact_aum = 1e7,
    impact_sigma = 0.02, rf = fx$rf, strategy = "Stock MAX"
  )
  expect_equal(out$sharpe, out$cagr / out$vol, tolerance = 1e-10)
})

test_that("market_impact_sensitivity: rf supplied without a registered label aborts", {
  fx <- .impact_fixture()
  expect_snapshot(
    error = TRUE,
    local_env_stk$market_impact_sensitivity(
      fx$df, fx$returns_wide, eta_grid = 1, lookback_months = 1L,
      adv_monthly = fx$adv_monthly, adv_pct_cap = 1, impact_aum = 1e7,
      impact_sigma = 0.02, rf = fx$rf
    )
  )
})

# ── regime ──────────────────────────────────────────────────────────────────
.regime_inputs <- function(n = 120L) {
  set.seed(9375)
  dates <- seq(as.Date("2000-01-15"), by = "month", length.out = n)
  base  <- .std(rnorm(n), 0.006, 0.03)
  expo  <- rep(c(1.0, 0.7, 0.4), length.out = n)
  rf    <- rep(RF_M, n)
  list(dates = dates, base = base, expo = expo, rf = rf)
}

test_that("regime_portfolio carries cash_weight = 1 - exposure (#937)", {
  i <- .regime_inputs()
  n <- length(i$dates)
  port_returns <- tibble::tibble(
    ym = format(i$dates, "%Y-%m"), date = i$dates,
    stk_max = i$base, stk_drif = i$base, fac_max = i$base, fac_drif = i$base,
    rf_ret = i$rf
  )
  regime_weights <- tibble::tibble(
    ym = port_returns$ym, regime = factor("low_risk"), exposure = i$expo
  )
  out <- .eval_command(
    .target_command(plan_regime(), "regime_portfolio"),
    port_returns = port_returns,
    port_optimal_weights = stats::setNames(rep(0.25, 4),
                                           c("stk_max", "stk_drif", "fac_max", "fac_drif")),
    regime_weights = regime_weights
  )
  expect_true("cash_weight" %in% names(out))
  expect_equal(out$cash_weight, 1 - i$expo, tolerance = 1e-12)
})

test_that("regime_metrics: base row is EXCESS, regime-adjusted row is a BLEND (#937)", {
  i <- .regime_inputs()
  n <- length(i$dates)
  regime_ret <- i$expo * i$base + (1 - i$expo) * i$rf
  regime_portfolio <- tibble::tibble(
    date = i$dates, base_ret = i$base, regime_ret = regime_ret,
    rf_ret = i$rf, cash_weight = 1 - i$expo
  )
  stk_params <- list(is_end = as.Date("2005-12-31"), test_start = as.Date("2006-01-01"),
                     test_end = as.Date("2008-12-31"))
  res <- .eval_command(.target_command(plan_regime(), "regime_metrics"),
                       regime_portfolio = regime_portfolio, stk_params = stk_params)
  full <- res[res$period == "Full Period", ]

  vol_of <- function(r) sd(r) * sqrt(12)
  cagr_of <- function(r) prod(1 + r)^(12 / length(r)) - 1

  b <- full[full$strategy == "Base Portfolio", ]
  expect_equal(b$sharpe, cagr_of(i$base) / vol_of(i$base), tolerance = 1e-10)

  g <- full[full$strategy == "Regime-Adjusted", ]
  rf_cash <- mean((1 - i$expo) * i$rf) * 12   # rf on the CASH leg only
  expect_equal(g$sharpe, (cagr_of(regime_ret) - rf_cash) / vol_of(regime_ret),
               tolerance = 1e-10)
  # falsification: deducting the FULL rf (the old behaviour) is materially different
  old <- (cagr_of(regime_ret) - mean(i$rf) * 12) / vol_of(regime_ret)
  expect_gt(abs(g$sharpe - old), 0.2)
})
