testthat::local_edition(3)

# Refs #937: Mean Reversion's published Sharpe is on the EXCESS basis.
# net_ret (R/plan_mean_reversion.R) is a long-only equal-weight TOTAL return
# (flat days earn 0, no rf deducted), registered as "total" in
# hd_return_basis(). mr_metrics must therefore deduct rf. Hermetic synthetic
# data only: no network, no targets store.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))

source(here::here("R/utils_metrics.R"))
source(here::here("R/plan_mean_reversion.R"))

.mr_target_command <- function(name) {
  tl <- plan_mean_reversion()
  hit <- vapply(tl, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found or not unique")
  tl[[which(hit)]]$command$expr[[1]]
}

.mr_weekdays <- function(from, to) {
  d <- seq(as.Date(from), as.Date(to), by = "day")
  d[!weekdays(d) %in% c("Saturday", "Sunday")]
}

# Daily net_ret with a known shape: mean ~0.0005, sd ~0.0028 per day.
.mr_fixture_port <- function() {
  d <- .mr_weekdays("2021-01-04", "2022-06-30")
  tibble::tibble(
    date = d,
    net_ret = 0.0005 + 0.004 * sin(seq_along(d)),
    n_new_trades = 1L,
    n_positions = 5L
  )
}

.mr_fixture_rf <- function(rf = 0.0002, from = "2020-01-01", to = "2023-12-31") {
  d <- .mr_weekdays(from, to)
  tibble::tibble(date = d, rf_ret = rf)
}

.mr_run <- function(port, daily_rf) {
  env <- list2env(
    list(
      mr_portfolio = port,
      daily_rf = daily_rf,
      mr_params = list(test_start = as.Date("2021-09-01"),
                       test_end = as.Date("2022-03-31"))
    ),
    envir = new.env(parent = globalenv())
  )
  eval(.mr_target_command("mr_metrics"), envir = env)
}

test_that("Mean Reversion is registered as a total-return series", {
  expect_identical(hd_return_basis_of("Mean Reversion"), "total")
  rf <- c(0.001, 0.002)
  expect_identical(hd_rf_for_basis(rf, "Mean Reversion"), rf)
})

test_that("mr_metrics Sharpe equals the hand-computed excess-basis value (constant rf)", {
  port <- .mr_fixture_port()
  rf_daily <- 0.0002
  res <- .mr_run(port, .mr_fixture_rf(rf_daily))
  full <- res[res$period == "Full Period", ]

  # Independent hand computation: (geometric CAGR - annual rf) / annual vol.
  ret <- port$net_ret
  n <- length(ret)
  cagr <- prod(1 + ret)^(252 / n) - 1
  vol <- sd(ret) * sqrt(252)
  expected <- (cagr - rf_daily * 252) / vol

  expect_equal(full$sharpe, round(expected, 2))
  expect_equal(full$days, n)
})

test_that("FALSIFICATION: mr_metrics goes RED if rf is not deducted", {
  port <- .mr_fixture_port()
  rf_daily <- 0.0002
  res <- .mr_run(port, .mr_fixture_rf(rf_daily))
  full <- res[res$period == "Full Period", ]

  ret <- port$net_ret
  n <- length(ret)
  cagr <- prod(1 + ret)^(252 / n) - 1
  vol <- sd(ret) * sqrt(252)
  no_rf_sharpe <- cagr / vol

  # The excess Sharpe sits below the no-rf figure by ann_rf / vol, which is
  # large on this fixture (>1); a missing deduction would make this fail.
  expect_gt(no_rf_sharpe - full$sharpe, 1)
  expect_equal(no_rf_sharpe - full$sharpe, rf_daily * 252 / vol, tolerance = 0.01)
  expect_false(isTRUE(all.equal(full$sharpe, round(no_rf_sharpe, 2))))
})

test_that("a higher rf lowers the published Sharpe (rf actually reaches the metric)", {
  port <- .mr_fixture_port()
  low <- .mr_run(port, .mr_fixture_rf(0.0001))
  high <- .mr_run(port, .mr_fixture_rf(0.0003))
  expect_lt(high$sharpe[high$period == "Full Period"],
            low$sharpe[low$period == "Full Period"])
})

test_that("column names, types and the window columns are unchanged", {
  res <- .mr_run(.mr_fixture_port(), .mr_fixture_rf())
  expect_identical(
    names(res),
    c("strategy", "period", "days", "years", "cagr", "vol", "sharpe", "max_dd",
      "avg_positions", "avg_daily_trades", "window_start", "window_end")
  )
  expect_identical(unique(res$strategy), "Mean Reversion")
  expect_s3_class(res$window_start, "Date")
  expect_type(res$sharpe, "double")
})

test_that("rf coverage gaps fail loud instead of dropping days", {
  port <- .mr_fixture_port()
  # LEADING: rf starts after the first portfolio date
  expect_error(
    .mr_run(port, .mr_fixture_rf(from = "2021-03-01")),
    "come before daily_rf even starts"
  )
  # INTERIOR: a hole inside rf's own span
  rf_hole <- .mr_fixture_rf()
  rf_hole <- rf_hole[rf_hole$date != as.Date("2021-06-16"), ]
  expect_snapshot(error = TRUE, .mr_run(port, rf_hole))
  # TRAILING publication lag: trimmed (not zero-filled) with a counted warning
  expect_warning(
    res <- .mr_run(port, .mr_fixture_rf(to = "2022-05-31")),
    "trailing"
  )
  expect_lt(res$window_end[res$period == "Full Period"], as.Date("2022-06-30"))
})

test_that("a daily_rf without rf_ret aborts", {
  expect_snapshot(
    error = TRUE,
    .mr_run(.mr_fixture_port(), tibble::tibble(date = .mr_weekdays("2020-01-01", "2023-12-31")))
  )
})

test_that("mr_caption still reads the Sharpe dynamically from mr_metrics", {
  res <- .mr_run(.mr_fixture_port(), .mr_fixture_rf())
  env <- list2env(
    list(
      mr_metrics = res,
      mr_params = list(drop_threshold = -2, lookback_vol = 21L, hold_days = 5L,
                       max_positions = 25L, min_skew = -1.5,
                       max_semivar_ratio = 1.5, max_cvar_pct = -0.08,
                       cost_per_trade = 0.002, tickers = c("A", "B"))
    ),
    envir = new.env(parent = globalenv())
  )
  cap <- eval(.mr_target_command("mr_caption"), envir = env)
  full <- res[res$period == "Full Period", ]
  expect_true(grepl(paste0("Sharpe: ", full$sharpe, ","), cap, fixed = TRUE))
})
