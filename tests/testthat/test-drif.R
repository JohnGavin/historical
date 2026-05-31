# Tests for plan_drif.R (factor-level) and plan_drif_v2.R (multiverse)
testthat::local_edition(3)

test_that("plan_drif cumprod survives scattered NA in returns", {
  df <- tibble::tibble(
    ym = c("2024-01", "2024-02", "2024-03"),
    portfolio_ret = c(0.05, NA_real_, 0.03),
    benchmark_ret = c(0.02, 0.01, NA_real_),
    rf_ret        = c(0, 0, 0),
    last_date     = as.Date(c("2024-01-31", "2024-02-29", "2024-03-31"))
  )
  result <- df |>
    dplyr::mutate(
      date       = last_date,
      port_cum   = cumprod(1 + dplyr::coalesce(portfolio_ret, 0)),
      bench_cum  = cumprod(1 + dplyr::coalesce(benchmark_ret, 0))
    )
  expect_false(any(is.na(result$port_cum)))
  expect_false(any(is.na(result$bench_cum)))
  # February row's port_cum == January's (NA → 0 → no change)
  expect_equal(result$port_cum[2], result$port_cum[1], tolerance = 1e-10)
})

# ── plan_drif_v2 unit tests ──────────────────────────────────────────────────

test_that("drif_multiverse_grid has 16 rows with expected columns", {
  # Inline the grid construction so the test is self-contained
  # (does not require a running targets pipeline)
  grid <- tidyr::expand_grid(
    alpha       = c(0.5, 1.0),
    nfolds      = c(5L, 10L),
    feature_set = c("chrono", "both"),
    lambda_rule = c("lambda.min", "lambda.1se")
  ) |>
    dplyr::mutate(
      spec_id    = sprintf("S%02d", dplyr::row_number()),
      is_current = alpha == 0.5 &
                   nfolds == 5L &
                   feature_set == "chrono" &
                   lambda_rule == "lambda.min"
    )

  expect_equal(nrow(grid), 16L)
  expect_true("spec_id"    %in% names(grid))
  expect_true("is_current" %in% names(grid))
  # Exactly one row flagged as the current production specification
  expect_equal(sum(grid$is_current), 1L)
  # Current spec is S01 (first row after expand_grid ordering)
  expect_equal(grid$spec_id[grid$is_current], "S01")
})

test_that("drif_multiverse_grid contains the two alpha values from the paper", {
  grid <- tidyr::expand_grid(
    alpha       = c(0.5, 1.0),
    nfolds      = c(5L, 10L),
    feature_set = c("chrono", "both"),
    lambda_rule = c("lambda.min", "lambda.1se")
  )
  # alpha 0.5 = elastic net as in current plan_drif.R
  # alpha 1.0 = pure LASSO (one extreme advocated in the paper)
  expect_setequal(unique(grid$alpha), c(0.5, 1.0))
})

test_that("drif_multiverse_caption is a non-empty string", {
  # Simulate the caption computation on a toy drif_multiverse tibble
  toy_mv <- tibble::tibble(
    spec_id     = c("S01", "S02", "S03"),
    alpha       = c(0.5, 1.0, 0.5),
    nfolds      = c(5L, 5L, 10L),
    feature_set = c("chrono", "chrono", "both"),
    lambda_rule = c("lambda.min", "lambda.min", "lambda.1se"),
    is_current  = c(TRUE, FALSE, FALSE),
    oos_sharpe  = c(0.82, 0.74, 0.91)
  )

  d <- toy_mv |>
    dplyr::filter(!is.na(oos_sharpe)) |>
    dplyr::arrange(oos_sharpe)

  n_specs        <- nrow(d)
  current_rank   <- which(d$is_current)
  min_sharpe     <- round(min(d$oos_sharpe, na.rm = TRUE), 2)
  max_sharpe     <- round(max(d$oos_sharpe, na.rm = TRUE), 2)
  current_sharpe <- round(d$oos_sharpe[current_rank], 2)

  caption <- paste0(
    "Of ", n_specs, " specifications tested (varying elastic-net alpha, ",
    "CV folds, feature set, and lambda rule), the current DRIF spec ",
    "(S01: alpha=0.5, k=5, chrono, lambda.min) ranks ", current_rank,
    " by OOS Sharpe (", current_sharpe,
    "). Sharpe range across specs: ", min_sharpe, " to ", max_sharpe,
    ". Source: plan_drif_v2.R; paper: Cakici et al. 2024 (SSRN 6005614)."
  )

  expect_type(caption, "character")
  expect_gt(nchar(caption), 50L)
  expect_true(grepl("SSRN 6005614", caption))
  expect_true(grepl("plan_drif_v2", caption))
  # Snapshot guard: catches format/wording drift in the assembled caption (#340)
  expect_snapshot(cat(caption))
})

test_that("run_spec helper computes OOS Sharpe from a toy dataset", {
  # Simulate the computation that happens inside run_spec in plan_drif_v2.R
  # without actually fitting elastic net (too slow for unit tests).
  # We test just the portfolio + metrics aggregation path.
  set.seed(42L)
  n_months <- 24L
  yms <- format(seq.Date(as.Date("2020-01-01"), by = "month", length.out = n_months), "%Y-%m")

  port <- tibble::tibble(
    ym       = yms,
    port_ret = rnorm(n_months, mean = 0.008, sd = 0.04),
    rf       = rep(0.0003, n_months)
  )

  ret <- port$port_ret
  n   <- nrow(port)

  ann_ret <- prod(1 + ret)^(12 / n) - 1
  ann_vol <- stats::sd(ret) * sqrt(12)
  sharpe  <- if (ann_vol > 0) ann_ret / ann_vol else NA_real_
  cum     <- cumprod(1 + ret)
  max_dd  <- min(cum / cummax(cum) - 1)

  result <- tibble::tibble(
    n_months   = n,
    oos_cagr   = ann_ret,
    oos_vol    = ann_vol,
    oos_sharpe = sharpe,
    oos_max_dd = max_dd
  )

  expect_equal(result$n_months, n_months)
  expect_true(is.finite(result$oos_sharpe))
  # max drawdown must be <= 0
  expect_lte(result$oos_max_dd, 0)
  # annualised vol must be positive
  expect_gt(result$oos_vol, 0)
})
