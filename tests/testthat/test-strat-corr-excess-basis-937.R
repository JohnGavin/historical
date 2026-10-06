testthat::local_edition(3)
# #937 Phase 1 (refs #919): strat_corr_augment's Sharpe panel (sharpe_full,
# sharpe_ew, incremental_sharpe, redundant) used annualise_returns()
# (CAGR/vol, no rf) on columns that MIX total-basis series (Value HML, Managed
# Futures, OLMAR-1, TOM, Risk State, Avoid Worst), excess ones and a blend
# (CMR Conditioned), flattering the total-basis columns. Every column must be
# put on the EXCESS basis through the registry (hd_excess_returns(), using the
# column's registered label) before the Sharpe is computed.
#
# Sharpe convention (unchanged): annualise_returns() = geometric CAGR / vol,
# periods_per_year = 12, on equal-weight combinations over a shared
# complete-case monthly window.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_strategy_correlation.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

# ── Toy world ───────────────────────────────────────────────────────────────
# A (stk_max, EXCESS basis) and B (value_hml, TOTAL basis = rf + spread - 0.002)
# are highly correlated. Raw, B beats A only because of its cash component;
# on the excess basis B is strictly WORSE than A.
.toy <- function(rf = 0.004) {
  set.seed(937)
  n   <- 120L
  yms <- format(seq(as.Date("2010-01-15"), by = "month", length.out = n), "%Y-%m")
  s   <- stats::rnorm(n, 0.004, 0.03)
  dts <- seq(as.Date("2010-01-01"), by = "day", length.out = 400L)
  wide <- tibble::tibble(ym = yms, stk_max = s, value_hml = rf + s - 0.002)
  list(
    strat_returns_wide = wide,
    strat_corr_matrix_leaderboard = matrix(
      c(1, 0.95, 0.95, 1), 2L, dimnames = list(c("stk_max", "value_hml"), c("stk_max", "value_hml"))
    ),
    strat_returns_daily_native = list(
      cmr_conditioned = tibble::tibble(date = dts, ret = 0, cash_weight = 0.5, rf_ret = rf / 20)
    ),
    ev_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf),
    mf_portfolios = tibble::tibble(date = as.Date(paste0(yms, "-15")), RF = rf),
    olmar_portfolio = tibble::tibble(date = dts, rf_ret = rf / 20),
    tom_portfolio = tibble::tibble(date = dts, rf_ret = rf / 20),
    rsc_portfolio = tibble::tibble(date = dts, rf_daily = rf / 20),
    aw_daily_rf = tibble::tibble(date = dts, rf_ret = rf / 20),
    .s = s, .rf = rf
  )
}

.run <- function(toy) {
  cmd <- .target_command(plan_strategy_correlation(), "strat_corr_augment")
  env <- list2env(toy, envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

# ── target-level ───────────────────────────────────────────────────────────
test_that("redundant flag compares peers on the EXCESS basis, not the raw total series", {
  toy <- .toy()
  out <- .run(toy)

  # Excess basis: B (value_hml) = s - 0.002 is worse than A (stk_max) = s.
  # Raw basis would instead flag A (B's cash component makes it "better").
  expect_true(out$redundant[out$code_name == "value_hml"])
  expect_false(out$redundant[out$code_name == "stk_max"])
})

test_that("incremental_sharpe equals the independent excess-basis computation", {
  toy <- .toy()
  out <- .run(toy)

  ew <- function(m) annualise_returns(as.numeric(m %*% rep(1 / ncol(m), ncol(m))), 12L)$sharpe
  ex <- cbind(stk_max = toy$.s, value_hml = toy$.s - 0.002)  # excess = ret - rf
  expected_vh <- round(ew(ex) - ew(ex[, "stk_max", drop = FALSE]), 3)
  expect_equal(unname(out$incremental_sharpe[out$code_name == "value_hml"]), unname(expected_vh))

  # Falsification: leaving the total column raw must give a DIFFERENT answer.
  raw <- cbind(stk_max = toy$.s, value_hml = toy$.s - 0.002 + toy$.rf)
  raw_vh <- round(ew(raw) - ew(raw[, "stk_max", drop = FALSE]), 3)
  expect_false(isTRUE(all.equal(raw_vh, expected_vh)))
})

# ── helper-level ───────────────────────────────────────────────────────────
.label_map <- c(stk_max = "Stock MAX", value_hml = "Value (HML)")

test_that(".strat_excess_wide deducts rf from a total column and leaves an excess column alone", {
  toy <- .toy()
  src <- .strat_rf_sources(
    toy$ev_portfolios, toy$mf_portfolios, toy$olmar_portfolio, toy$tom_portfolio,
    toy$rsc_portfolio, toy$aw_daily_rf, toy$strat_returns_daily_native
  )
  out <- .strat_excess_wide(
    toy$strat_returns_wide, c("stk_max", "value_hml"), .label_map,
    toy$strat_returns_daily_native, src
  )
  expect_equal(out$stk_max, toy$strat_returns_wide$stk_max)
  expect_equal(out$value_hml, toy$strat_returns_wide$value_hml - toy$.rf)
})

test_that(".strat_excess_wide drops (NA) and warns on a total row with no rf -- never 0-fills", {
  toy <- .toy()
  toy$ev_portfolios$RF[5:7] <- NA_real_
  src <- .strat_rf_sources(
    toy$ev_portfolios, toy$mf_portfolios, toy$olmar_portfolio, toy$tom_portfolio,
    toy$rsc_portfolio, toy$aw_daily_rf, toy$strat_returns_daily_native
  )
  expect_warning(
    out <- .strat_excess_wide(
      toy$strat_returns_wide, c("stk_max", "value_hml"), .label_map,
      toy$strat_returns_daily_native, src
    ),
    "dropped 3 of 120"
  )
  expect_true(all(is.na(out$value_hml[5:7])))
  expect_false(anyNA(out$value_hml[-(5:7)]))
})

test_that(".strat_excess_wide aborts on an unmapped column", {
  toy <- .toy()
  src <- .strat_rf_sources(
    toy$ev_portfolios, toy$mf_portfolios, toy$olmar_portfolio, toy$tom_portfolio,
    toy$rsc_portfolio, toy$aw_daily_rf, toy$strat_returns_daily_native
  )
  expect_snapshot(
    error = TRUE,
    .strat_excess_wide(
      toy$strat_returns_wide, c("stk_max", "value_hml"), c(stk_max = "Stock MAX"),
      toy$strat_returns_daily_native, src
    )
  )
})

test_that(".strat_excess_wide aborts when a total column has no rf source", {
  toy <- .toy()
  expect_snapshot(
    error = TRUE,
    .strat_excess_wide(
      toy$strat_returns_wide, c("stk_max", "value_hml"), .label_map,
      toy$strat_returns_daily_native, list(monthly = list(), daily = list())
    )
  )
})

test_that(".strat_excess_wide: daily total column is compounded AFTER rf is deducted daily", {
  dts <- seq(as.Date("2020-01-01"), by = "day", length.out = 60L)
  daily_ret <- rep(0.001, 60L)
  rf_d <- 0.0002
  wide <- tibble::tibble(ym = c("2020-01", "2020-02"), tom = c(NA_real_, NA_real_))
  daily <- list(tom = tibble::tibble(date = dts, ret = daily_ret))
  src <- list(monthly = list(), daily = list(tom = tibble::tibble(key = dts, rf = rf_d)))
  out <- .strat_excess_wide(wide, "tom", c(tom = "TOM"), daily, src)
  jan <- prod(1 + rep(daily_ret[1] - rf_d, 31L)) - 1
  expect_equal(out$tom[out$ym == "2020-01"], jan)
})

test_that("blend column (CMR Conditioned) deducts rf on the cash weight only", {
  dts <- seq(as.Date("2020-01-01"), by = "day", length.out = 40L)
  cw <- rep(0.5, 40L); rf_d <- 0.0002
  ret <- 0.001 * (1 - cw) + cw * rf_d      # spread leg + cash leg
  wide <- tibble::tibble(ym = c("2020-01", "2020-02"), cmr_conditioned = NA_real_)
  daily <- list(cmr_conditioned = tibble::tibble(date = dts, ret = ret, cash_weight = cw))
  src <- list(monthly = list(), daily = list(
    cmr_conditioned = tibble::tibble(key = dts, rf = rf_d)
  ))
  out <- .strat_excess_wide(wide, "cmr_conditioned", c(cmr_conditioned = "CMR Conditioned"), daily, src)
  expect_equal(out$cmr_conditioned[out$ym == "2020-01"], prod(1 + rep(0.0005, 31L)) - 1)
})
