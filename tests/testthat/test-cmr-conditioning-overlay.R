# Tests for the #751 item 1 follow-up conditioning overlay helpers
# (.cmr_conditioning_regime() / .cmr_apply_conditioning_overlay(),
# R/plan_commodities_mean_reversion.R).
#
# Decision (#751, 2026-08-29): the 8 untradeable-twin IMF/FRED series are
# excluded from the CMR position pool and exposed instead as a MIDAS-style
# conditioning covariate (hd_commodity_mr_conditioning_universe() /
# hd_commodity_mr_conditioning_signal(), packages/historicaldata/R/
# commodities_mean_reversion.R). These tests exercise the plan-level
# regime-classification and exposure-scaling overlay built on that
# covariate, mirroring R/plan_risk_state.R's rsc_thresholds -> rsc_regime
# shape but reduced to one signal.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

# ── .cmr_conditioning_regime() ──────────────────────────────────────────────

test_that(".cmr_conditioning_regime: dates below the minimum-prior-observations floor are 'insufficient_history' with full (benign) exposure", {
  cond_signal_tbl <- tibble::tibble(
    date        = seq.Date(as.Date("2000-01-31"), by = "month", length.out = 10),
    cond_signal = rnorm(10, 0, 0.02)
  )
  out <- .cmr_conditioning_regime(cond_signal_tbl)
  expect_true(all(out$regime == "insufficient_history"))
  expect_true(all(out$exposure_mult == 1.0))
})


test_that(".cmr_conditioning_regime: a strongly extreme composite classifies as hostile with reduced exposure, once enough history exists", {
  set.seed(1)
  n <- 60
  cond_signal_tbl <- tibble::tibble(
    date        = seq.Date(as.Date("2000-01-31"), by = "month", length.out = n),
    cond_signal = rnorm(n, 0, 0.01)
  )
  # Inject one dramatic outlier well after the min-prior-obs floor (24).
  cond_signal_tbl$cond_signal[40] <- 5.0

  out <- .cmr_conditioning_regime(cond_signal_tbl)
  hit <- out[40, ]
  expect_equal(hit$regime, "hostile")
  expect_equal(hit$exposure_mult, 0.1)
})


test_that(".cmr_conditioning_regime: the threshold classifying date t never uses cond_signal at or after t (no look-ahead)", {
  # Two signal series identical up to date t, diverging strictly AFTER it --
  # the regime assigned AT t must be identical for both, since nothing at or
  # after t may influence it.
  set.seed(2)
  n <- 50
  base <- rnorm(n, 0, 0.02)
  sig_a <- base
  sig_b <- base
  sig_b[45:50] <- sig_b[45:50] + 10  # diverge only in the tail, after t = 30

  dates <- seq.Date(as.Date("2000-01-31"), by = "month", length.out = n)
  out_a <- .cmr_conditioning_regime(tibble::tibble(date = dates, cond_signal = sig_a))
  out_b <- .cmr_conditioning_regime(tibble::tibble(date = dates, cond_signal = sig_b))

  expect_equal(out_a$regime[1:30], out_b$regime[1:30])
  expect_equal(out_a$exposure_mult[1:30], out_b$exposure_mult[1:30])
})


test_that(".cmr_conditioning_regime: output columns are as documented", {
  cond_signal_tbl <- tibble::tibble(
    date        = seq.Date(as.Date("2000-01-31"), by = "month", length.out = 5),
    cond_signal = rnorm(5)
  )
  out <- .cmr_conditioning_regime(cond_signal_tbl)
  expect_equal(names(out), c("date", "cond_signal", "regime", "exposure_mult"))
  expect_true(all(out$regime %in% c("benign", "cautious", "hostile", "insufficient_history")))
})


# ── .cmr_apply_conditioning_overlay() ───────────────────────────────────────

test_that(".cmr_apply_conditioning_overlay: full (1.0) exposure reproduces net_ret minus the rf blend and switch cost exactly", {
  dates <- seq.Date(as.Date("2010-01-31"), by = "day", length.out = 5)
  portfolio_tbl <- tibble::tibble(date = dates, net_ret = c(0.01, -0.02, 0.005, 0.03, -0.01))
  cond_regime_tbl <- tibble::tibble(
    date = dates[1], cond_signal = 0, regime = "benign", exposure_mult = 1.0
  )
  daily_rf <- tibble::tibble(date = dates, rf_ret = 0.0001)

  out <- .cmr_apply_conditioning_overlay(portfolio_tbl, cond_regime_tbl, daily_rf, lookback = "1m")

  expect_true(all(c("date", "net_ret", "regime", "exposure_mult", "switch_cost",
                     "net_ret_conditioned") %in% names(out)))
  expect_true(all(out$exposure_mult == 1.0))
  # At full exposure with no regime switch, net_ret_conditioned == net_ret
  # (the rf blend term (1 - 1.0) * rf drops out, and switch_cost is 0 since
  # exposure never changes).
  expect_equal(out$net_ret_conditioned, out$net_ret, tolerance = 1e-12)
  expect_true(all(out$switch_cost == 0))
})


test_that(".cmr_apply_conditioning_overlay: sparse regime is carried forward (LOCF) onto every portfolio date", {
  dates <- seq.Date(as.Date("2010-01-01"), by = "day", length.out = 10)
  portfolio_tbl <- tibble::tibble(date = dates, net_ret = rep(0.001, 10))
  # Regime only known on day 1 and day 6 -- must persist for days 2-5 and 7-10.
  cond_regime_tbl <- tibble::tibble(
    date          = dates[c(1, 6)],
    cond_signal   = c(0, 5),
    regime        = c("benign", "hostile"),
    exposure_mult = c(1.0, 0.1)
  )
  daily_rf <- tibble::tibble(date = dates, rf_ret = 0)

  out <- .cmr_apply_conditioning_overlay(portfolio_tbl, cond_regime_tbl, daily_rf, lookback = "1m")

  expect_true(all(out$exposure_mult[1:5] == 1.0))
  expect_true(all(out$exposure_mult[6:10] == 0.1))
})


test_that(".cmr_apply_conditioning_overlay: dates before the first conditioning print default to full (neutral) exposure", {
  dates <- seq.Date(as.Date("2010-01-01"), by = "day", length.out = 5)
  portfolio_tbl <- tibble::tibble(date = dates, net_ret = rep(0.001, 5))
  # No conditioning data covers ANY of these dates.
  cond_regime_tbl <- tibble::tibble(
    date = as.Date("2020-01-01"), cond_signal = 0, regime = "benign", exposure_mult = 1.0
  )
  daily_rf <- tibble::tibble(date = dates, rf_ret = 0)

  out <- .cmr_apply_conditioning_overlay(portfolio_tbl, cond_regime_tbl, daily_rf, lookback = "1m")

  expect_true(all(out$exposure_mult == 1.0))
  expect_true(all(out$regime == "insufficient_history"))
})


test_that(".cmr_apply_conditioning_overlay: a regime switch deducts a strictly positive cost", {
  dates <- seq.Date(as.Date("2010-01-01"), by = "day", length.out = 4)
  portfolio_tbl <- tibble::tibble(date = dates, net_ret = rep(0.001, 4))
  cond_regime_tbl <- tibble::tibble(
    date          = dates[c(1, 3)],
    cond_signal   = c(0, 5),
    regime        = c("benign", "hostile"),
    exposure_mult = c(1.0, 0.1)
  )
  daily_rf <- tibble::tibble(date = dates, rf_ret = 0)

  out <- .cmr_apply_conditioning_overlay(portfolio_tbl, cond_regime_tbl, daily_rf, lookback = "1m")

  # Switch happens between date 2 (still 1.0, carried forward) and date 3 (0.1).
  expect_equal(out$switch_cost[1], 0)
  expect_equal(out$switch_cost[2], 0)
  expect_true(out$switch_cost[3] > 0)
})
