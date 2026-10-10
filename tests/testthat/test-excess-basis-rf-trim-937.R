# Refs #937, #919: an EXCESS-basis strategy never uses rf (hd_rf_for_basis()
# zeroes it), so subjecting it to the rf-availability trim in the
# leaderboard path only throws away valid trailing returns -- and made the
# leaderboard's month count disagree with the deflated-Sharpe path's T_obs
# (Mom Pre-Peak / Post-Peak / 12-2: 1 month; CMR: 53 daily rows).
# TOTAL and BLEND basis strategies genuinely need rf, so they keep the trim.
# Hermetic synthetic data only: no network, no targets store.
testthat::local_edition(3)

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_mom_prepeak.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Mom path (monthly, joined on ym derived from exec_date) ─────────────────
.mdates <- function(n) seq.Date(as.Date("2020-01-31"), by = "month", length.out = n)
.mom_rets <- function(n) {
  tibble::tibble(exec_date = .mdates(n), ret_ls = rep(c(0.02, -0.01, 0.015), length.out = n))
}
.mom_rf <- function(n) {
  tibble::tibble(ym = format(.mdates(n), "%Y-%m"), rf_ret = 0.0016)
}

test_that("Mom excess-basis: every return month survives an rf series that ends early", {
  rets <- .mom_rets(24)
  rf   <- .mom_rf(24)[1:20, ]  # rf ends 4 months before the returns

  for (s in c("Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2")) {
    expect_no_warning(joined <- .mom_prepeak_join_rf(rets, rf, strategy = s))
    expect_equal(nrow(joined), nrow(rets), info = s)
    expect_equal(joined$ret_ls, rets$ret_ls, info = s)
  }
})

test_that("Mom excess-basis: Sharpe is unchanged by the extra months' rf being absent", {
  rets <- .mom_rets(36)
  rf   <- .mom_rf(36)[1:30, ]
  joined <- .mom_prepeak_join_rf(rets, rf, strategy = "Mom Pre-Peak")
  m <- historicaldata:::.mom_prepeak_compute_metrics(joined, strategy = "test")
  got <- .mom_prepeak_sharpe(joined, m, strategy = "Mom Pre-Peak")
  expect_equal(got, sharpe_ratio_rf(rets$ret_ls, rep(0, 36), periods_per_year = 12L)$sharpe)
})

test_that("Mom CONTROL: a TOTAL-basis label still trims to the rf window and warns", {
  rets <- .mom_rets(24)
  rf   <- .mom_rf(24)[1:20, ]
  expect_warning(joined <- .mom_prepeak_join_rf(rets, rf, strategy = "Avoid Worst"), "Dropped")
  expect_equal(nrow(joined), 20L)
  expect_false(anyNA(joined$rf_ret))
})

test_that("Mom: an unregistered label still aborts (no silent default)", {
  expect_snapshot(error = TRUE, .mom_prepeak_join_rf(.mom_rets(12), .mom_rf(12), strategy = "Nope"))
})

# ── CMR path (daily metrics; toy fixtures use monthly spacing, ann_factor 12) ─
.cdates <- seq.Date(as.Date("2020-01-01"), by = "month", length.out = 24L)
.cmr_pt <- tibble::tibble(date = .cdates, net_ret = rep(c(0.01, -0.02, 0.015, 0.005), length.out = 24L))
.cmr_rf_short <- tibble::tibble(date = .cdates[1:20], rf_ret = 0.002)  # ends 4 periods early

test_that("CMR excess-basis: every return row survives an rf series that ends early", {
  expect_no_warning(
    m <- .compute_cmr_metrics(.cmr_pt, lookback = "t", daily_rf = .cmr_rf_short,
                              ann_factor = 12L, basis_strategy = "CMR")
  )
  expect_equal(m$n_days, 24L)
  expect_identical(m$ann_rf, 0)
})

test_that("CMR excess-basis metrics equal the full-rf-coverage metrics", {
  rf_full <- tibble::tibble(date = .cdates, rf_ret = 0.002)
  full  <- .compute_cmr_metrics(.cmr_pt, "t", rf_full, ann_factor = 12L, basis_strategy = "CMR")
  short <- .compute_cmr_metrics(.cmr_pt, "t", .cmr_rf_short, ann_factor = 12L, basis_strategy = "CMR")
  expect_equal(short, full)
})

test_that("CMR CONTROL: a TOTAL-basis label still trims to the rf window and warns", {
  expect_warning(
    m <- .compute_cmr_metrics(.cmr_pt, "t", .cmr_rf_short, ann_factor = 12L,
                              basis_strategy = "Value (HML)"),
    "Dropped"
  )
  expect_equal(m$n_days, 20L)
})

test_that("CMR Conditioned (blend) is unchanged: still trims, rf still needed on the cash leg", {
  overlay_rf <- tibble::tibble(date = .cdates, rf_ret = 0.002)
  cond <- tibble::tibble(date = .cdates, cond_signal = 0, regime = "benign",
                         exposure_mult = rep(c(1.0, 0.5, 0.1), length.out = 24L))
  pt <- .cmr_apply_conditioning_overlay(.cmr_pt, cond, overlay_rf, lookback = "1m") |>
    dplyr::select(date, net_ret = net_ret_conditioned, cash_weight)
  expect_warning(
    m <- .compute_cmr_metrics(pt, "t", .cmr_rf_short, ann_factor = 12L,
                              basis_strategy = "CMR Conditioned"),
    "Dropped"
  )
  expect_equal(m$n_days, 20L)
  expect_gt(m$ann_rf, 0)
})

# ── S43 gate: the four formerly allow-listed strategies pass on EQUALITY ────
.s43_strats <- c("Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2", "CMR")
# "Avoid Worst" is TOTAL basis and keeps its reasoned allow-list entry (-29
# rows with no rf), so it is part of the fixture: it is the only remaining
# allow-listed strategy and must not be reported stale.
.s43_lb <- function(mths) {
  tibble::tibble(strategy = c(.s43_strats, "Avoid Worst"), period = "Full Period",
                 months = c(mths, 8353))
}
.s43_dsr <- function(t_obs) {
  tibble::tibble(strategy = c(.s43_strats, "Avoid Worst"), T_obs = c(t_obs, 8324L))
}

test_that("S43: the default allow-list no longer exempts Mom Pre/Post-Peak, Mom 12-2 or CMR", {
  expect_false(any(.s43_strats %in% S43_DSR_WINDOW_ALLOWLIST$strategy))
})

test_that("S43: equal months and T_obs pass with NO allow-list entry and no stale warning", {
  tbl <- build_dsr_coverage_table(.s43_lb(c(638, 638, 638, 6516)), .s43_dsr(c(638L, 638L, 638L, 6516L)),
                                  excluded = character(0))
  expect_true(all(tbl$verdict[tbl$strategy %in% .s43_strats] == "PASS"))
  expect_equal(tbl$verdict[tbl$strategy == "Avoid Worst"], "PASS_ALLOWLISTED")
  expect_no_warning(out <- check_dsr_coverage(tbl))
  expect_equal(unname(attr(out, "summary")[["stale"]]), 0L)
})

test_that("S43 FALSIFICATION: a leftover offset on a formerly exempt strategy now FAILS", {
  tbl <- build_dsr_coverage_table(.s43_lb(c(637, 638, 638, 6463)), .s43_dsr(c(638L, 638L, 638L, 6516L)),
                                  excluded = character(0))
  expect_equal(tbl$verdict[tbl$strategy == "Mom Pre-Peak"], "FAIL")
  expect_equal(tbl$verdict[tbl$strategy == "CMR"], "FAIL")
  expect_error(check_dsr_coverage(tbl), class = "qa_s43_fail")
})
