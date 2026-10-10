testthat::local_edition(3)
# #937 Phase 1 (group B), origin #919: Risk State and Avoid Worst computed
# Sharpe / HAC statistics on the WRONG return basis.
#
#   * rsc_metrics: DRIF_raw/DRIF_overlay/FacMAX_raw/FacMAX_overlay are EXCESS
#     spreads (R/plan_drif.R, R/plan_factormax.R; hd_return_basis()) scaled by
#     an exposure with no cash leg -- rf must NOT be deducted. They were
#     deducting it (so their Sharpe was biased DOWN).
#   * rsc_metrics SPY rows, rsc_alpha_decay, rsc_subperiod: the HAC statistics
#     were arithmetic on a TOTAL series (rf not deducted: biased UP).
#   * aw_cross_market / aw_bootstrap_ci: mean/sd*sqrt(252) on a TOTAL series
#     with no rf (biased UP).
#
# Every test has a falsification: it is RED if rf is not removed for a TOTAL
# row, or is wrongly removed for an EXCESS row (a constant, large rf makes
# either mistake move the number by far more than the tolerance).

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_risk_state.R"))
source(here::here("R/plan_avoid_worst.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

.eval_command <- function(expr, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(expr, envir = env)
}

# Run `expr`, returning list(value, warnings) so extra cli_warns do not leak.
.collect_warnings <- function(expr) {
  w <- character()
  v <- withCallingHandlers(
    expr,
    warning = function(cnd) {
      w <<- c(w, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  list(value = v, warnings = w)
}

# A constant, deliberately LARGE rf: 0.004/month (~4.9%/yr) and 0.0002/day
# (~5.2%/yr). Any wrong deduction/omission shifts a Sharpe by ~1 unit.
RF_M <- 0.004
RF_D <- 0.0002

# ── rsc_metrics ──────────────────────────────────────────────────────────────
.toy_rsc <- function(n_days = 500L, seed = 937L, rf_daily = RF_D, rf_m = RF_M) {
  set.seed(seed)
  dates <- seq(as.Date("2018-01-01"), by = "day", length.out = n_days)
  port <- tibble::tibble(
    date         = dates,
    ret_buyhold  = stats::rnorm(n_days, 0.0005, 0.01),
    ret_strategy = stats::rnorm(n_days, 0.0004, 0.008),
    rf_daily     = rep(rf_daily, n_days)
  )
  months <- seq(as.Date("2000-01-31"), by = "month", length.out = 120L)
  drif <- tibble::tibble(
    date        = months,
    ret_raw     = stats::rnorm(120L, 0.004, 0.03),
    ret_overlay = stats::rnorm(120L, 0.003, 0.02),
    rf_ret      = rep(rf_m, 120L)
  )
  fmx <- tibble::tibble(
    date        = months,
    ret_raw     = stats::rnorm(120L, 0.004, 0.03),
    ret_overlay = stats::rnorm(120L, 0.003, 0.02),
    rf_ret      = rep(rf_m, 120L)
  )
  list(port = port, drif = drif, fmx = fmx)
}

.run_rsc_metrics <- function(inputs) {
  cmd <- .target_command(plan_risk_state(), "rsc_metrics")
  .eval_command(
    cmd,
    rsc_params          = list(oos_start = as.Date("2019-01-01"),
                               test_end  = as.Date("2019-06-30")),
    rsc_portfolio       = inputs$port,
    rsc_overlay_drif    = inputs$drif,
    rsc_overlay_fac_max = inputs$fmx
  )
}

.row <- function(res, strategy, period = "Full Period") {
  res[res$strategy == strategy & res$period == period, ]
}

test_that("rsc_metrics: DRIF/FacMAX rows are EXCESS spreads -- rf is NOT deducted (#937)", {
  inp <- .toy_rsc()
  res <- .run_rsc_metrics(inp)

  cases <- list(
    DRIF_raw       = inp$drif$ret_raw,
    DRIF_overlay   = inp$drif$ret_overlay,
    FacMAX_raw     = inp$fmx$ret_raw,
    FacMAX_overlay = inp$fmx$ret_overlay
  )
  for (nm in names(cases)) {
    r <- cases[[nm]]
    row <- .row(res, nm)
    expect_equal(nrow(row), 1L, info = nm)
    # Sharpe is the geometric Sharpe of the series with rf == 0 ...
    want <- round(sharpe_ratio_rf(r, rep(0, length(r)), periods_per_year = 12L)$sharpe, 3)
    expect_equal(row$sharpe, want, info = nm)
    # ... so the published risk-free column is exactly zero ...
    expect_equal(row$ann_rf, 0, info = nm)
    # ... and the HAC statistics are on the raw (already-excess) series.
    hac <- hd_hac_sharpe(r, ann_factor = 12L)
    expect_equal(row$hac_sharpe, round(hac$naive_sharpe, 3), info = nm)
    expect_equal(row$hac_tstat,  round(hac$hac_tstat, 3),   info = nm)
  }
})

test_that("rsc_metrics: SPY rows are TOTAL -- rf deducted from Sharpe AND HAC (#937)", {
  inp <- .toy_rsc()
  res <- .run_rsc_metrics(inp)

  cases <- list(
    SPY_overlay = inp$port$ret_strategy,   # Risk State: exposure*SPY + (1-e)*rf
    SPY_buyhold = inp$port$ret_buyhold     # SPY benchmark, total return
  )
  for (nm in names(cases)) {
    r  <- cases[[nm]]
    rf <- inp$port$rf_daily
    row <- .row(res, nm)
    sr <- sharpe_ratio_rf(r, rf, periods_per_year = 252L)
    expect_equal(row$sharpe, round(sr$sharpe, 3), info = nm)
    expect_gt(row$ann_rf, 0)
    hac <- hd_hac_sharpe(r - rf, ann_factor = 252L)
    expect_equal(row$hac_sharpe, round(hac$naive_sharpe, 3), info = nm)
    expect_equal(row$hac_tstat,  round(hac$hac_tstat, 3),   info = nm)
    # falsification guard: the un-deducted statistic is materially different
    raw <- hd_hac_sharpe(r, ann_factor = 252L)
    expect_gt(abs(round(raw$naive_sharpe, 3) - row$hac_sharpe), 0.3)
  }
})

test_that("rsc_metrics: a total row with NA rf is dropped with a COUNTED warning, never 0-filled (#937)", {
  inp <- .toy_rsc()
  inp$port$rf_daily[c(10L, 11L, 12L)] <- NA_real_
  out <- .collect_warnings(.run_rsc_metrics(inp))
  expect_true(any(grepl("Dropped 3 ", out$warnings)))
  row <- .row(out$value, "SPY_overlay")
  keep <- !is.na(inp$port$rf_daily)
  want <- hd_hac_sharpe(inp$port$ret_strategy[keep] - inp$port$rf_daily[keep],
                        ann_factor = 252L)
  expect_equal(row$hac_sharpe, round(want$naive_sharpe, 3))
})

# ── rsc_alpha_decay (delay table) ────────────────────────────────────────────
test_that("rsc_alpha_decay: hac_sharpe/hac_tstat are on the EXCESS Risk State series (#937)", {
  set.seed(937)
  n <- 300L
  spy <- stats::rnorm(n, 0.0005, 0.01)
  # All signals NA -> every regime "benign" -> exposure 1 -> ret == spy_ret,
  # so the expected excess series is spy_ret - rf_use exactly.
  data <- tibble::tibble(
    date = seq(as.Date("2018-01-01"), by = "day", length.out = n),
    spy_ret = spy, rf = rep(RF_D, n),
    vvix = NA_real_, vix1m = NA_real_, vix3m = NA_real_
  )
  params <- list(slope_change_window = 5L, slope_change_hostile = -1,
                 slope_change_cautious = -0.5, exposure_benign = 1,
                 exposure_cautious = 0.5, exposure_hostile = 0.1)
  thr <- list(vvix_hostile = 100, vvix_cautious = 90,
              slope_level_hostile = 0.8, slope_level_cautious = 0.9)

  captured <- list()
  spy_hac <- function(ret, ann_factor = 252) {
    captured[[length(captured) + 1L]] <<- ret
    hd_hac_sharpe(ret, ann_factor = ann_factor)
  }
  cmd <- .target_command(plan_risk_state(), "rsc_alpha_decay")
  res <- .eval_command(cmd, hd_hac_sharpe = spy_hac, rsc_data = data,
                       rsc_params = params, rsc_thresholds = thr)
  expect_equal(nrow(res), 10L)

  d <- 1L
  rf_use <- c(rep(0, d), rep(RF_D, n - d))   # lag(rf, d); leading NA -> 0
  expect_equal(captured[[1]], spy - rf_use)
  # falsification: the raw series (what the code passed before) is different
  expect_gt(max(abs(captured[[1]] - spy)), 1e-4)
})

# ── rsc_subperiod ────────────────────────────────────────────────────────────
test_that("rsc_subperiod: hac_tstat is on the EXCESS Risk State series (#937)", {
  set.seed(938)
  days <- seq(as.Date("2009-01-01"), as.Date("2026-04-30"), by = "day")
  n <- length(days)
  port <- tibble::tibble(
    date = days,
    ret_strategy = stats::rnorm(n, 0.0004, 0.01),
    ret_buyhold  = stats::rnorm(n, 0.0004, 0.012),
    rf_daily     = rep(RF_D, n),
    regime       = rep_len(c("benign", "cautious", "hostile"), n)
  )
  captured <- list()
  spy_hac <- function(ret, ann_factor = 252) {
    captured[[length(captured) + 1L]] <<- ret
    hd_hac_sharpe(ret, ann_factor = ann_factor)
  }
  cmd <- .target_command(plan_risk_state(), "rsc_subperiod")
  res <- .eval_command(cmd, rsc_portfolio = port, hd_hac_sharpe = spy_hac,
                       rsc_params = list(holdout_end = as.Date("2026-04-30")))
  expect_true("Full Period" %in% res$period)
  full <- captured[[length(captured)]]          # Full Period is the last call
  expect_equal(full, port$ret_strategy - RF_D)
  expect_equal(res$hac_tstat[res$period == "Full Period"],
               round(hd_hac_sharpe(port$ret_strategy - RF_D)$hac_tstat, 3))
})

# ── Avoid Worst ──────────────────────────────────────────────────────────────
.aw_toy_backtest <- function(n = 600L, seed = 939L) {
  set.seed(seed)
  tibble::tibble(
    date         = seq(as.Date("2015-01-01"), by = "day", length.out = n),
    ret_market   = stats::rnorm(n, 0.0006, 0.011),
    ret_strategy = ifelse(stats::runif(n) < 0.8, stats::rnorm(n, 0.0006, 0.009), 0)
  )
}

.arith_sharpe <- function(x) mean(x) / stats::sd(x) * sqrt(252)

test_that("aw_bootstrap_ci: point estimate AND CI are on the EXCESS basis (#937)", {
  bt <- .aw_toy_backtest()
  rf <- tibble::tibble(date = bt$date, rf_ret = RF_D)
  cmd <- .target_command(plan_avoid_worst(), "aw_bootstrap_ci")
  res <- .eval_command(cmd, aw_practical_backtest = bt, aw_daily_rf = rf)

  # Point estimates: strategy is "Avoid Worst" (total); SPY buy & hold is a
  # total-return benchmark. Both have rf deducted.
  expect_equal(res$sharpe_point[res$scenario == "VIX Protection"],
               round(.arith_sharpe(bt$ret_strategy - RF_D), 2))
  expect_equal(res$sharpe_point[res$scenario == "Buy & Hold"],
               round(.arith_sharpe(bt$ret_market - RF_D), 2))

  # CI: reproduce the block bootstrap on the EXCESS series (same seed/idx
  # logic) -- point and interval share one basis.
  ex_s <- bt$ret_strategy - RF_D
  n <- length(ex_s); block <- 63L
  set.seed(42)
  boot_s <- numeric(1000L)
  for (b in seq_len(1000L)) {
    starts <- sample(seq_len(n - block + 1), ceiling(n / block), replace = TRUE)
    idx <- unlist(lapply(starts, function(s) s:(s + block - 1)))[1:n]
    boot_s[b] <- .arith_sharpe(ex_s[idx])
  }
  strat <- res[res$scenario == "VIX Protection", ]
  expect_equal(unname(strat$sharpe_ci_lo), round(unname(stats::quantile(boot_s, 0.05)), 2))
  expect_equal(unname(strat$sharpe_ci_hi), round(unname(stats::quantile(boot_s, 0.95)), 2))
  # falsification: the interval centre is far below the un-deducted one
  expect_lt(strat$sharpe_point, round(.arith_sharpe(bt$ret_strategy), 2) - 0.3)
})

test_that("aw_bootstrap_ci: a trailing rf gap drops rows with a COUNTED warning (#937)", {
  bt <- .aw_toy_backtest()
  rf <- tibble::tibble(date = bt$date[1:(nrow(bt) - 5L)], rf_ret = RF_D)
  cmd <- .target_command(plan_avoid_worst(), "aw_bootstrap_ci")
  out <- .collect_warnings(.eval_command(cmd, aw_practical_backtest = bt, aw_daily_rf = rf))
  expect_true(any(grepl("Dropped 5 trailing", out$warnings)))
  keep <- seq_len(nrow(bt) - 5L)
  expect_equal(out$value$sharpe_point[out$value$scenario == "VIX Protection"],
               round(.arith_sharpe(bt$ret_strategy[keep] - RF_D), 2))
})

test_that("aw_cross_market: sharpe_bh and sharpe_strat are on the EXCESS basis (#937)", {
  set.seed(940)
  n <- 700L
  dts <- seq(as.Date("2015-01-01"), by = "day", length.out = n)
  vix <- rep(15, n); vix[seq(60L, n, by = 70L)] <- 35   # periodic stress -> cash days
  rets <- stats::rnorm(n, 0.0006, 0.009)
  ret_all <- tibble::tibble(
    ticker = rep(c("SPY", "QQQ", "IWM", "DIA"), each = n),
    date = rep(dts, 4L),
    ret = c(rets, rets * 1.1, rets * 0.9, rets * 1.05)
  )
  rf <- tibble::tibble(date = dts, rf_ret = RF_D)
  mock_macro <- function(series) tibble::tibble(date = dts, value = vix)

  cmd <- .target_command(plan_avoid_worst(), "aw_cross_market")
  res <- .eval_command(cmd, hd_macro = mock_macro, aw_daily_returns = ret_all,
                       aw_daily_rf = rf)

  # Mirror the target's own in-market rule to rebuild the strategy series.
  strat_of <- function(r) {
    in_mkt <- rep(TRUE, n); cool <- 0L
    for (i in 2:n) {
      if (cool > 0) cool <- cool - 1L
      vp <- vix[i - 1]
      if (abs(r[i - 1]) > 0.03 || (!is.na(vp) && vp > 30)) {
        in_mkt[i] <- FALSE; cool <- max(cool, 5L)
      } else if (cool > 0 || (!is.na(vp) && vp > 25)) in_mkt[i] <- FALSE
    }
    ifelse(in_mkt, r, 0)
  }
  r <- ret_all$ret[ret_all$ticker == "SPY"]
  row <- res[res$ticker == "SPY", ]
  expect_equal(row$sharpe_bh,    round(.arith_sharpe(r - RF_D), 2))
  expect_equal(row$sharpe_strat, round(.arith_sharpe(strat_of(r) - RF_D), 2))
  # falsification: the un-deducted values differ materially
  expect_gt(round(.arith_sharpe(r), 2) - row$sharpe_bh, 0.3)
  expect_gt(round(.arith_sharpe(strat_of(r)), 2) - row$sharpe_strat, 0.3)
  # every ticker row follows the same rule
  r2 <- ret_all$ret[ret_all$ticker == "QQQ"]
  expect_equal(res$sharpe_bh[res$ticker == "QQQ"], round(.arith_sharpe(r2 - RF_D), 2))
})

# ── helper: fail-loud behaviours (snapshots) ─────────────────────────────────
test_that(".aw_excess_series: unregistered strategy label aborts (#937)", {
  d <- as.Date("2020-01-01") + 0:9
  rf <- tibble::tibble(date = d, rf_ret = RF_D)
  # The message is the registry's own (snapshotted with hd_return_basis_of());
  # a snapshot here would break whenever the registry grows (#937 Phase 3).
  expect_error(
    .aw_excess_series(d, rep(0.001, 10L), rf, strategy = "Not A Strategy"),
    "not registered"
  )
})

test_that(".aw_excess_series: a hole INSIDE the rf span aborts (#937)", {
  d <- as.Date("2020-01-01") + 0:9
  rf <- tibble::tibble(date = d[-4], rf_ret = RF_D)
  rf <- rbind(rf, tibble::tibble(date = as.Date("2020-02-01"), rf_ret = RF_D))
  expect_snapshot(
    error = TRUE,
    .aw_excess_series(d, rep(0.001, 10L), rf, strategy = "Avoid Worst")
  )
})

test_that(".aw_excess_series: total strategy subtracts rf; NA strategy is the benchmark (#937)", {
  d <- as.Date("2020-01-01") + 0:9
  rf <- tibble::tibble(date = d, rf_ret = RF_D)
  r <- seq(0.001, 0.01, length.out = 10L)
  expect_equal(.aw_excess_series(d, r, rf, strategy = "Avoid Worst")$ret, r - RF_D)
  expect_equal(.aw_excess_series(d, r, rf, strategy = NA_character_)$ret, r - RF_D)
})
