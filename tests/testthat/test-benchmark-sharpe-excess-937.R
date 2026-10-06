testthat::local_edition(3)
# #937 Phase 1 (refs #919): the Factor MAX / Factor DRIF benchmark is Mkt-RF,
# which is ALREADY an excess return. fm_metrics/drif_metrics used to deduct
# rf from it a second time, understating bench_sharpe next to a strategy side
# that is already rf-free (#934). Basis: excess (Mkt-RF); registry vocabulary
# for benchmarks is tracked in #937 Phase 3.

pkg_path <- if (dir.exists(here::here("packages/historicaldata"))) {
  here::here("packages/historicaldata")
} else {
  file.path(dirname(here::here()), "packages/historicaldata")
}
suppressMessages(pkgload::load_all(pkg_path, quiet = TRUE))
source(here::here("R/plan_factormax.R"))
source(here::here("R/plan_drif.R"))

.target_command <- function(target_list, name) {
  hit <- vapply(target_list, function(t) identical(t$settings$name, name), logical(1))
  if (sum(hit) != 1L) stop("target '", name, "' not found (or not unique)")
  target_list[[which(hit)]]$command$expr[[1]]
}

# Toy portfolio: benchmark (Mkt-RF) is an excess return, rf is non-trivially
# positive so a second deduction is clearly visible.
.toy_portfolio <- function(rf = 0.004) {
  set.seed(937)
  n <- 120L
  tibble::tibble(
    date          = seq(as.Date("2010-01-31"), by = "month", length.out = n),
    portfolio_ret = stats::rnorm(n, 0.004, 0.03),
    benchmark_ret = stats::rnorm(n, 0.006, 0.04),
    rf_ret        = rf
  )
}

.params <- function(df) {
  d <- max(df$date)
  list(
    is_end = d, test_start = d + 1, test_end = d + 2,
    holdout_start = d + 3, holdout_end = d + 4,
    val_start = d + 5, val_end = d + 6
  )
}

.expected_bench_sharpe <- function(b) {
  n <- length(b)
  (prod(1 + b)^(12 / n) - 1) / (stats::sd(b) * sqrt(12))
}

.full_row <- function(out) out[out$period == "Full Period", , drop = FALSE]

test_that("fm_metrics: Mkt-RF benchmark Sharpe has NO rf deducted", {
  df  <- .toy_portfolio()
  cmd <- .target_command(plan_factormax(), "fm_metrics")
  env <- list2env(list(fm_portfolio = df, fm_params = .params(df)),
                  envir = new.env(parent = globalenv()))
  row <- .full_row(eval(cmd, envir = env))

  expect_equal(row$bench_sharpe, .expected_bench_sharpe(df$benchmark_ret))
  # Falsification: the double-deducted value must be strictly lower.
  double_deducted <- (row$bench_cagr - mean(df$rf_ret) * 12) / row$bench_vol
  expect_gt(row$bench_sharpe, double_deducted + 0.05)
})

test_that("drif_metrics: Mkt-RF benchmark Sharpe has NO rf deducted", {
  df  <- .toy_portfolio()
  cmd <- .target_command(plan_drif(), "drif_metrics")
  env <- list2env(list(drif_portfolio = df, drif_params = .params(df)),
                  envir = new.env(parent = globalenv()))
  row <- .full_row(eval(cmd, envir = env))

  expect_equal(row$bench_sharpe, .expected_bench_sharpe(df$benchmark_ret))
  double_deducted <- (row$bench_cagr - mean(df$rf_ret) * 12) / row$bench_vol
  expect_gt(row$bench_sharpe, double_deducted + 0.05)
})

test_that("benchmark fix leaves the strategy-side Sharpe untouched (excess, ann_rf = 0)", {
  df  <- .toy_portfolio()
  env <- list2env(list(fm_portfolio = df, fm_params = .params(df)),
                  envir = new.env(parent = globalenv()))
  row <- .full_row(eval(.target_command(plan_factormax(), "fm_metrics"), envir = env))
  expect_equal(row$ann_rf, 0)
  expect_equal(row$sharpe, row$cagr / row$vol)
})
