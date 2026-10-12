testthat::local_edition(3)
# #937 phase 2 group C, site 7: does cmr_selection / cmr_selection_conditioned
# CHOOSE the lookback on the same return basis the published row REPORTS?
#
# The tracking issue's "Checked since the inventory" note said the selection
# used an rf-deducted Sharpe while the published figure was rf-free. On current
# main that is no longer true: .cmr_select_pre_oos_lookback() passes
# basis_strategy = label to .compute_cmr_metrics() (#935), the SAME function
# and the SAME registry label the published cmr_metrics_* targets use. This file
# pins that equality so it cannot regress, and shows the choice is
# basis-sensitive (a fixture where the rf-deducted winner differs from the
# registry-basis winner), i.e. the guard is not vacuous.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_commodities_mean_reversion.R"))

.oos_start <- as.Date("2021-01-01")
.mk <- function(pre, post, cash_weight = NULL) {
  d <- tibble::tibble(
    date = c(seq.Date(as.Date("2019-01-01"), by = "month", length.out = 24L),
             seq.Date(as.Date("2021-01-01"), by = "month", length.out = 12L)),
    net_ret = c(pre, post)
  )
  if (!is.null(cash_weight)) d$cash_weight <- cash_weight
  d
}
# A: low return / low vol.  B: higher return / higher vol.  rf = 0.5%/month.
#   registry-basis (rf-free, "CMR" is excess):  A 1.0  > B 0.8   => A
#   total-basis (rf deducted):                   A 0.5  < B 0.55  => B
.rf  <- 0.005
.A_pre <- rep(c(0.020, 0.000), 12L)          # mean 0.010, sd ~0.0102
.B_pre <- rep(c(0.036, -0.004), 12L)         # mean 0.016, sd ~0.0205
.post  <- rep(0.004, 12L)
.rf_tbl <- tibble::tibble(
  date = seq.Date(as.Date("2019-01-01"), by = "month", length.out = 36L),
  rf_ret = rep(.rf, 36L)
)
.cmr_sharpe <- function(tbl, basis, ann = 12L) {
  .compute_cmr_metrics(tbl, lookback = "x", daily_rf = .rf_tbl, ann_factor = ann,
                       periodicity_check = "warn", basis_strategy = basis)$sharpe
}

test_that("cmr_selection chooses on the registry basis ('CMR' = excess), the same basis as the published row", {
  portfolios <- list(`1m` = .mk(.A_pre, .post), `3m` = .mk(.B_pre, .post))
  sel <- .cmr_select_pre_oos_lookback(portfolios, .oos_start, .rf_tbl, ann_factor = 12L, label = "CMR")

  pre <- function(tbl) tbl[tbl$date < .oos_start, ]
  published_basis <- vapply(portfolios, function(p) .cmr_sharpe(pre(p), "CMR"), numeric(1))
  expect_equal(sel$diagnostics$sharpe, unname(round(published_basis, 3)))
  expect_identical(sel$chosen, names(which.max(published_basis)))
  expect_identical(sel$chosen, "1m")

  # FALSIFICATION: scoring the same candidates as a TOTAL series (rf deducted)
  # picks the OTHER lookback, so a selection on the wrong basis would be caught.
  total_basis <- vapply(portfolios, function(p) .cmr_sharpe(pre(p), "Value (HML)"), numeric(1))
  expect_identical(names(which.max(total_basis)), "3m")
  expect_false(identical(sel$chosen, names(which.max(total_basis))))
})

test_that("cmr_selection_conditioned scores the BLEND basis: rf deducted on the cash weight only", {
  cw <- rep(0.5, 36L)
  portfolios <- list(
    `1m` = dplyr::rename(.mk(.A_pre, .post, cw), net_ret_conditioned = net_ret),
    `3m` = dplyr::rename(.mk(.B_pre, .post, cw), net_ret_conditioned = net_ret)
  )
  sel <- .cmr_select_pre_oos_lookback(portfolios, .oos_start, .rf_tbl, return_col = "net_ret_conditioned",
                                      ann_factor = 12L, label = "CMR Conditioned")
  # Independent hand computation of the blend-basis Sharpe on the pre-OOS slice.
  hand <- vapply(list(.A_pre, .B_pre), function(r) {
    sharpe_ratio_rf(r, rep(0.5 * .rf, length(r)), periods_per_year = 12L)$sharpe
  }, numeric(1))
  expect_equal(sel$diagnostics$sharpe, round(hand, 3))
  # and it is the SAME number the published conditioned row would carry
  # (.compute_cmr_metrics on the same slice with the same label)
  pre <- .mk(.A_pre, .post, cw)
  pre <- pre[pre$date < .oos_start, ]
  expect_equal(sel$diagnostics$sharpe[1], .cmr_sharpe(pre, "CMR Conditioned"))
})

# ── Registry writer: SSR is scored on the excess series (#937) ──────────────
.rf_daily <- 0.0002
.ssr_port <- function(n = 60L) {
  set.seed(9379)
  tibble::tibble(
    date = seq.Date(as.Date("2020-01-01"), by = "day", length.out = n),
    net_ret = 0.5 * stats::rnorm(n, 0.001, 0.01) + 0.5 * .rf_daily,
    cash_weight = rep(0.5, n)
  )
}
.ssr_rf <- tibble::tibble(
  date = seq.Date(as.Date("2019-12-01"), by = "day", length.out = 200L),
  rf_ret = .rf_daily
)

test_that(".cmr_ssr_returns: CMR (excess spread) is unchanged; CMR Conditioned (blend) loses rf on the cash weight only", {
  port <- .ssr_port()
  expect_identical(.cmr_ssr_returns(port, "cmr", NULL, "1m"), port$net_ret)
  out <- .cmr_ssr_returns(port, "cmr_conditioned", .ssr_rf, "1m")
  expect_equal(out, port$net_ret - 0.5 * .rf_daily)
  # FALSIFICATION: neither the raw series nor a full-rf deduction is returned
  expect_false(isTRUE(all.equal(out, port$net_ret)))
  expect_false(isTRUE(all.equal(out, port$net_ret - .rf_daily)))
})

test_that(".cmr_ssr_returns aborts on an unknown strategy_id and on a blend without rf / cash weight", {
  port <- .ssr_port()
  expect_snapshot(error = TRUE, .cmr_ssr_returns(port, "cmr_other", .ssr_rf, "1m"))
  expect_snapshot(error = TRUE, .cmr_ssr_returns(port, "cmr_conditioned", NULL, "1m"))
  expect_snapshot(error = TRUE, .cmr_ssr_returns(port[, c("date", "net_ret")], "cmr_conditioned", .ssr_rf, "1m"))
})

test_that("an unregistered selection label aborts (no silent default basis)", {
  portfolios <- list(`1m` = .mk(.A_pre, .post), `3m` = .mk(.B_pre, .post))
  expect_error(
    .cmr_select_pre_oos_lookback(portfolios, .oos_start, .rf_tbl, ann_factor = 12L, label = "Not Registered"),
    "not registered"
  )
})
