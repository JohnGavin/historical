testthat::local_edition(3)
# #919: strat_deflated_sharpe must score each strategy on the SAME return
# basis as the leaderboard Sharpe -- hd_return_basis() is the single home.
# Before the fix the DSR path fed hd_deflated_sharpe() the RAW series, so a
# TOTAL-return series (HML = RF + HML - cost) carried its cash component in
# the numerator (naive_sharpe 0.528 vs the leaderboard's 0.068).

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

# ── Toy inputs: every object the target body reads ──────────────────────────
.toy <- function(rf_m = 0.004, rf_d = 0.0002) {
  set.seed(919)
  n   <- 240L
  yms <- format(seq(as.Date("2000-01-15"), by = "month", length.out = n), "%Y-%m")
  dts <- seq(as.Date("2020-01-01"), by = "day", length.out = 400L)
  wide <- tibble::tibble(ym = yms)
  hml_spread <- stats::rnorm(n, 0.0005, 0.03)
  for (cn in c("stk_max", "stk_drif", "fac_max", "fac_drif", "ltr", "xgb_drif",
               "mom_prepeak", "mom_postpeak", "mom_combined", "managed_futures")) {
    wide[[cn]] <- stats::rnorm(n, 0.004, 0.03)
  }
  wide$value_hml <- rf_m + hml_spread        # TOTAL return: RF + spread
  daily <- function() tibble::tibble(date = dts, ret = stats::rnorm(400L, 0.0004, 0.01))
  list(
    strat_returns_wide = wide,
    hml_spread = hml_spread,
    strat_returns_daily_native = list(
      cmr = daily(), cmr_conditioned = daily(), olmar_1 = daily(),
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
    strat_corr_matrix = diag(3)
  )
}

.run <- function(toy) {
  cmd <- .target_command(plan_leaderboard(), "strat_deflated_sharpe")
  env <- list2env(toy, envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

test_that("strat_deflated_sharpe output schema and row order are stable", {
  out <- .run(.toy())
  expect_snapshot_value(
    list(names = names(out), strategy = out$strategy),
    style = "deparse"
  )
  expect_snapshot(args(hd_rf_for_basis))
})

test_that("a TOTAL-basis row (Value HML) is scored on its EXCESS series", {
  toy <- .toy()
  out <- .run(toy)
  hml <- out[out$strategy == "Value (HML)", ]

  expected <- hd_deflated_sharpe(toy$hml_spread, K_trials = 5L, ann_factor = 12L)
  expect_equal(hml$naive_sharpe, expected$naive_sharpe, tolerance = 1e-8)
  expect_equal(hml$dsr_pvalue,   expected$dsr_pvalue,   tolerance = 1e-8)
})

test_that("FALSIFICATION: HML naive_sharpe is NOT the flattered raw-series value", {
  toy <- .toy()
  out <- .run(toy)
  raw <- hd_deflated_sharpe(toy$strat_returns_wide$value_hml, K_trials = 5L, ann_factor = 12L)
  hml <- out[out$strategy == "Value (HML)", ]
  # the raw (RF-inclusive) Sharpe is inflated by ~ rf/sd * sqrt(12)
  expect_gt(raw$naive_sharpe - hml$naive_sharpe, 0.5)
})

test_that("an EXCESS-basis row (Mom Pre-Peak) is scored on its raw series (no rf deducted)", {
  toy <- .toy()
  out <- .run(toy)
  mom <- out[out$strategy == "Mom Pre-Peak", ]
  expected <- hd_deflated_sharpe(toy$strat_returns_wide$mom_prepeak, K_trials = 5L, ann_factor = 12L)
  expect_equal(mom$naive_sharpe, expected$naive_sharpe, tolerance = 1e-8)
})

test_that("a rf change moves a TOTAL daily row but not an EXCESS one", {
  lo <- .run(.toy(rf_d = 0))
  hi <- .run(.toy(rf_d = 0.0004))
  rs <- function(o, s) o$naive_sharpe[o$strategy == s]
  expect_gt(rs(lo, "Risk State"), rs(hi, "Risk State"))        # total: rf deducted
  expect_equal(rs(lo, "CMR"), rs(hi, "CMR"))                    # excess: untouched
})

test_that("a total-basis row with no rf coverage drops AND reports the observations", {
  toy <- .toy()
  toy$ev_portfolios <- toy$ev_portfolios[1:200, ]  # rf ends 40 months early
  expect_warning(out <- .run(toy), regexp = "dropped 40 of 240")
  expect_false(is.na(out$naive_sharpe[out$strategy == "Value (HML)"]))
})
