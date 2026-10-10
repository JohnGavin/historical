testthat::local_edition(3)
# #937 phase 2, group C: research targets whose Sharpe was computed on a TOTAL
# return series with NO rf deducted (inflating both strategy and benchmark):
#   plan_rafi.R (rafi_metrics, rafi_decay)
#   plan_european_overlay.R (eur_results, eur_comparison, eur_ciss_results)
#   plan_vix_macro_overlay.R (vmo_results)
#   plan_jst_trend.R (jt_country_metrics, jt_pooled, jt_sensitivity)
# The rule (hd_return_basis()): a Sharpe is on an EXCESS basis; rf is deducted
# iff the series is a TOTAL return. Each series below is registered as "total"
# under a "Research: ..." label and must be routed through the registry
# helpers. All data are synthetic (hermetic).
#
# Every test asserts against an INDEPENDENT hand computation of the excess-basis
# Sharpe, and each also asserts the pre-fix (rf-free) value is DIFFERENT, so a
# green result cannot be produced by leaving the code unchanged.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_rafi.R"))
source(here::here("R/plan_european_overlay.R"))
source(here::here("R/plan_vix_macro_overlay.R"))
source(here::here("R/plan_jst_trend.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}
.run <- function(cmd, ...) {
  env <- list2env(list(...), envir = new.env(parent = globalenv()))
  eval(cmd, envir = env)
}

RESEARCH_LABELS <- c(
  "Research: RF + factor overlay",
  "Research: cap-weighted market (Mkt-RF + RF)",
  "Research: ETF buy and hold",
  "Research: ETF/cash overlay",
  "Research: JST equity total return",
  "Research: JST equity/bills trend",
  "Research: asset panel (adjusted-close returns)"
)

test_that("every research label is registered as a TOTAL-basis series (registry rows)", {
  for (lab in RESEARCH_LABELS) {
    expect_identical(hd_return_basis_of(lab), "total", info = lab)
  }
  # total => rf is kept (not zeroed), so the Sharpe helpers deduct it
  expect_identical(hd_rf_for_basis(c(0.1, 0.2), RESEARCH_LABELS[1]), c(0.1, 0.2))
})

# ── RAFI ────────────────────────────────────────────────────────────────────
.rafi_toy <- function(n = 360L, start = "1990-01-01") {
  set.seed(9371)
  dates <- seq(as.Date(start), by = "month", length.out = n)
  rf <- rep(0.003, n)                       # 3.6%/yr
  tibble::tibble(
    date = dates, RF = rf,
    ret_rafi    = rf + stats::rnorm(n, 0.004, 0.03),
    ret_revenue = rf + stats::rnorm(n, 0.003, 0.03),
    ret_ew      = rf + stats::rnorm(n, 0.002, 0.03),
    ret_market  = rf + stats::rnorm(n, 0.005, 0.04)
  )
}
.excess_sharpe_geo <- function(r, rf, ppy) {
  n <- length(r)
  ((prod(1 + r)^(ppy / n) - 1) - mean(rf) * ppy) / (stats::sd(r) * sqrt(ppy))
}
.raw_sharpe_geo <- function(r, ppy) .excess_sharpe_geo(r, 0, ppy)

test_that("rafi_metrics Sharpe is on the excess basis for all four total-basis series", {
  port <- .rafi_toy()
  params <- list(oos_start = as.Date("2010-01-01"), test_end = as.Date("2019-12-31"))
  out <- .run(.target_command(plan_rafi(), "rafi_metrics"),
              rafi_params = params, rafi_portfolios = port)
  cols <- c(
    "RAFI Composite (50% HML + 30% SMB + 20% Mom)" = "ret_rafi",
    "Revenue Proxy (100% HML)"                     = "ret_revenue",
    "Equal-Weight Proxy (100% SMB)"                = "ret_ew",
    "Benchmark (Cap-Weighted Market)"              = "ret_market"
  )
  for (lab in names(cols)) {
    row <- out[out$strategy == lab & out$period == "Full", ]
    expect_equal(row$sharpe, round(.excess_sharpe_geo(port[[cols[[lab]]]], port$RF, 12), 3),
                 info = lab)
    # FALSIFICATION: the pre-fix rf-free value is materially different
    expect_gt(abs(row$sharpe - round(.raw_sharpe_geo(port[[cols[[lab]]]], 12), 3)), 0.05)
  }
  # OOS slice is deducted with the OOS slice's own rf
  oos <- port$date >= params$oos_start & port$date <= params$test_end
  row <- out[out$strategy == "Benchmark (Cap-Weighted Market)" & out$period == "OOS", ]
  expect_equal(row$sharpe, round(.excess_sharpe_geo(port$ret_market[oos], port$RF[oos], 12), 3))
})

test_that("rafi_decay Sharpe is on the excess basis, per early/late split", {
  port <- .rafi_toy()
  out <- .run(.target_command(plan_rafi(), "rafi_decay"), rafi_portfolios = port)
  early <- port$date < as.Date("2000-01-01")
  row <- out[out$strategy == "RAFI Composite" & out$period == "Pre-2000", ]
  expect_equal(row$sharpe, round(.excess_sharpe_geo(port$ret_rafi[early], port$RF[early], 12), 3))
  expect_gt(abs(row$sharpe - round(.raw_sharpe_geo(port$ret_rafi[early], 12), 3)), 0.05)
  row <- out[out$strategy == "Benchmark" & out$period == "2000+", ]
  expect_equal(row$sharpe, round(.excess_sharpe_geo(port$ret_market[!early], port$RF[!early], 12), 3))
})

# ── European overlay ────────────────────────────────────────────────────────
.eur_toy <- function(n = 600L) {
  set.seed(9372)
  dates <- seq(as.Date("2018-01-01"), by = "day", length.out = n)
  rf <- rep(0.0002, n)                       # ~5%/yr
  list(
    params = list(
      eu_tickers = "VGK", eu_ticker_labels = c(VGK = "FTSE Europe"),
      oos_start = as.Date("2019-06-01"), test_end = as.Date("2019-08-31")
    ),
    daily = tibble::tibble(
      date = dates, ticker = "VGK", label = "FTSE Europe",
      eu_ret = stats::rnorm(n, 0.0004, 0.01),
      regime = "cautious",
      exposure = rep(c(1, 0.5, 0.1), length.out = n),
      rf_lag = rf
    ),
    rf = rf
  )
}
.hac <- function(x) hd_hac_sharpe(x)$naive_sharpe

test_that("eur_results hac_sharpe is on the excess basis (buy-and-hold and RSC overlay)", {
  toy <- .eur_toy()
  out <- .run(.target_command(plan_european_overlay(), "eur_results"),
              eur_params = toy$params, eur_daily = toy$daily)
  d <- toy$daily
  overlay <- d$exposure * d$eu_ret + (1 - d$exposure) * d$rf_lag
  bh <- out[out$strategy == "Buy & Hold" & out$period == "Full", ]
  ov <- out[out$strategy == "RSC Overlay" & out$period == "Full", ]
  expect_equal(bh$hac_sharpe, round(.hac(d$eu_ret - d$rf_lag), 3))
  expect_equal(ov$hac_sharpe, round(.hac(overlay - d$rf_lag), 3))
  # FALSIFICATION: pre-fix values (rf-free) differ
  expect_gt(abs(bh$hac_sharpe - round(.hac(d$eu_ret), 3)), 0.05)
  expect_gt(abs(ov$hac_sharpe - round(.hac(overlay), 3)), 0.05)
  # cagr/vol remain total-return statistics (unchanged by the fix)
  expect_equal(bh$vol, round(stats::sd(d$eu_ret) * sqrt(252) * 100, 2))
})

test_that("eur_comparison SPY rows are on the excess basis", {
  toy <- .eur_toy()
  set.seed(9373)
  spy <- tibble::tibble(
    date = toy$daily$date,
    ret_buyhold = stats::rnorm(nrow(toy$daily), 0.0004, 0.01),
    rf_daily = toy$rf
  )
  spy$ret_strategy <- 0.6 * spy$ret_buyhold + 0.4 * spy$rf_daily
  res <- tibble::tibble(
    ticker = character(), asset = character(), strategy = character(),
    period = character(), cagr = numeric(), vol = numeric(), max_dd = numeric(),
    hac_tstat = numeric(), hac_sharpe = numeric(),
    window_start = as.Date(character()), window_end = as.Date(character())
  )
  out <- .run(.target_command(plan_european_overlay(), "eur_comparison"),
              eur_params = toy$params, rsc_portfolio = spy, eur_results = res)
  w <- spy$date >= toy$params$oos_start & spy$date <= toy$params$test_end
  bh <- out[out$ticker == "SPY" & out$strategy == "Buy & Hold", ]
  ov <- out[out$ticker == "SPY" & out$strategy == "RSC Overlay", ]
  expect_equal(bh$hac_sharpe, round(.hac(spy$ret_buyhold[w] - spy$rf_daily[w]), 3))
  expect_equal(ov$hac_sharpe, round(.hac(spy$ret_strategy[w] - spy$rf_daily[w]), 3))
  expect_gt(abs(bh$hac_sharpe - round(.hac(spy$ret_buyhold[w]), 3)), 0.05)
})

test_that("eur_ciss_results hac_sharpe is on the excess basis", {
  toy <- .eur_toy()
  ciss <- tibble::tibble(date = toy$daily$date,
                         ciss_exposure = rep(c(0.1, 1, 0.5), length.out = nrow(toy$daily)))
  out <- .run(.target_command(plan_european_overlay(), "eur_ciss_results"),
              eur_params = toy$params, eur_daily = toy$daily, eur_ciss_regime = ciss)
  d <- toy$daily
  w <- d$date >= toy$params$oos_start & d$date <= toy$params$test_end
  ov_ret <- ciss$ciss_exposure * d$eu_ret + (1 - ciss$ciss_exposure) * d$rf_lag
  bh <- out[out$strategy == "Buy & Hold", ]
  ov <- out[out$strategy == "CISS Overlay", ]
  expect_equal(bh$hac_sharpe, round(.hac((d$eu_ret - d$rf_lag)[w]), 3))
  expect_equal(ov$hac_sharpe, round(.hac((ov_ret - d$rf_lag)[w]), 3))
  expect_gt(abs(bh$hac_sharpe - round(.hac(d$eu_ret[w]), 3)), 0.05)
})

# ── VIX macro overlay ───────────────────────────────────────────────────────
test_that("vmo_results Sharpe is on the excess basis; overlay cash leg earns 0, not rf", {
  set.seed(9374)
  n <- 400L
  dates <- seq(as.Date("2018-01-01"), by = "day", length.out = n)
  ret <- stats::rnorm(n, 0.0004, 0.01)
  vix <- rep(15, n); vix[10] <- 30        # one spike: out of market on days 11-13
  rf  <- 0.0002
  params <- list(
    tickers = "TLT", ticker_labels = c(TLT = "20+ Year Treasury Bonds"),
    vix_high = 25, vix_reentry = 20, min_cooloff = 3L
  )
  daily <- tibble::tibble(date = dates, ticker = "TLT", ret = ret, vix = vix)
  daily_rf <- tibble::tibble(date = dates, rf_ret = rep(rf, n))
  out <- .run(.target_command(plan_vix_macro_overlay(), "vmo_results"),
              vmo_params = params, vmo_daily = daily, daily_rf = daily_rf)
  ov_ret <- ret; ov_ret[11:13] <- 0
  sh <- function(x) round(mean(x - rf) / stats::sd(x - rf) * sqrt(252), 2)
  raw <- function(x) round(mean(x) / stats::sd(x) * sqrt(252), 2)
  bh <- out[out$strategy == "Buy & Hold", ]
  ov <- out[out$strategy == "VIX Overlay", ]
  expect_equal(bh$sharpe, sh(ret))
  expect_equal(ov$sharpe, sh(ov_ret))
  expect_gt(abs(bh$sharpe - raw(ret)), 0.2)   # FALSIFICATION: pre-fix value differs
  expect_equal(ov$pct_in_market, round((n - 3) / n * 100, 1))
})

# ── JST trend ───────────────────────────────────────────────────────────────
.jt_toy <- function(n_c = 6L, years = 1900:2019) {
  set.seed(9375)
  do.call(rbind, lapply(seq_len(n_c), function(i) {
    n <- length(years)
    tibble::tibble(
      iso = paste0("C", i), year = years,
      eq_tr = stats::runif(n, 2, 12),        # percent, always positive => trend always long
      bond_tr = 3, bill_rate = stats::runif(n, 1, 6)
    )
  }))
}
.annual_excess_sharpe <- function(r, rf) {
  n <- length(r)
  (((prod(1 + r)^(1 / n) - 1) - mean(rf)) / stats::sd(r))
}

test_that("jt_country_metrics Sharpe is on the excess basis (bill rate deducted)", {
  raw <- .jt_toy()
  jt_data <- raw |>
    dplyr::group_by(iso) |>
    dplyr::mutate(eq_idx = cumprod(1 + eq_tr / 100), eq_ma = NA_real_,
                  trend_sig = 1L, tf_ret = eq_tr / 100) |>
    dplyr::ungroup()
  out <- .run(.target_command(plan_jst_trend(), "jt_country_metrics"),
              jt_params = list(oos_start = 1950L), jt_data = jt_data)
  c1 <- jt_data[jt_data$iso == "C1", ]
  bh <- out[out$iso == "C1" & out$strategy == "Buy-and-Hold" & out$period == "Full", ]
  expect_equal(bh$sharpe, round(.annual_excess_sharpe(c1$eq_tr / 100, c1$bill_rate / 100), 3))
  expect_gt(abs(bh$sharpe - round(.annual_excess_sharpe(c1$eq_tr / 100, 0), 3)), 0.05)
  # OOS slice uses the OOS slice's own bill rates
  o <- c1[c1$year >= 1950, ]
  bh_oos <- out[out$iso == "C1" & out$strategy == "Buy-and-Hold" & out$period == "OOS", ]
  expect_equal(bh_oos$sharpe, round(.annual_excess_sharpe(o$eq_tr / 100, o$bill_rate / 100), 3))
})

test_that("jt_pooled Sharpe is on the excess basis (pooled bill rate deducted)", {
  raw <- .jt_toy()
  jt_data <- raw |>
    dplyr::group_by(iso) |>
    dplyr::mutate(eq_idx = cumprod(1 + eq_tr / 100), eq_ma = NA_real_,
                  trend_sig = 1L, tf_ret = eq_tr / 100) |>
    dplyr::ungroup()
  out <- .run(.target_command(plan_jst_trend(), "jt_pooled"),
              jt_params = list(oos_start = 1950L), jt_data = jt_data)
  by_year <- jt_data |>
    dplyr::group_by(year) |>
    dplyr::summarise(bh = mean(eq_tr / 100), rf = mean(bill_rate / 100), .groups = "drop")
  row <- out[out$strategy == "Pooled Buy-and-Hold" & out$period == "Full", ]
  expect_equal(row$sharpe, round(.annual_excess_sharpe(by_year$bh, by_year$rf), 3))
  expect_gt(abs(row$sharpe - round(.annual_excess_sharpe(by_year$bh, 0), 3)), 0.05)
  row_t <- out[out$strategy == "Pooled Trend (MA-12y)" & out$period == "Full", ]
  expect_equal(row_t$sharpe, row$sharpe)   # trend == buy-and-hold in this toy
})

test_that("jt_sensitivity tf/bh Sharpe are on the excess basis", {
  raw <- .jt_toy(years = 1900:1979)
  out <- .run(.target_command(plan_jst_trend(), "jt_sensitivity"),
              jt_params = list(ma_sweep = 6L), jst_raw = raw)
  # eq_tr > 0 every year => index strictly rising => signal long after warm-up,
  # so the trend and buy-and-hold pooled series coincide on the kept years.
  kept <- raw[raw$year >= 1900 + 6L, ]      # 6 MA years + 1 lag year dropped
  kept <- raw |>
    dplyr::group_by(iso) |>
    dplyr::arrange(year, .by_group = TRUE) |>
    dplyr::filter(dplyr::row_number() > 6L) |>
    dplyr::ungroup()
  by_year <- kept |>
    dplyr::group_by(year) |>
    dplyr::summarise(r = mean(eq_tr / 100), rf = mean(bill_rate / 100), .groups = "drop")
  expect_equal(out$bh_sharpe, round(.annual_excess_sharpe(by_year$r, by_year$rf), 3))
  expect_equal(out$tf_sharpe, out$bh_sharpe)
  expect_gt(abs(out$bh_sharpe - round(.annual_excess_sharpe(by_year$r, 0), 3)), 0.05)
})
