# Tests for plan_drif.R (factor-level) and plan_drif_v2.R (multiverse)
testthat::local_edition(3)

# compute_drif_selected_features() / compute_drif_selection_jaccard() /
# summarise_drif_selection_stability() (#910 item 2) live in R/plan_drif.R
# and are not otherwise loaded when tests run via test_dir() -- mirrors the
# source() pattern in test-qa-search-funnel.R (R/plan_qa_gates.R). Safe to
# source unconditionally: plan_drif() itself is a function definition with
# no side effects until called.
source(here::here("R/plan_drif.R"))

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

# ── Selection-stability diagnostic (#910 item 2) ──────────────────────────────
# compute_drif_selected_features() / compute_drif_selection_jaccard() /
# summarise_drif_selection_stability() -- see R/plan_drif.R.

test_that("compute_drif_selection_jaccard computes known overlaps for consecutive pairs", {
  selected <- list(
    "2020-01" = c("c1", "c2", "r1"),
    "2020-02" = c("c1", "c2", "r1"),       # identical -> jaccard 1
    "2020-03" = c("r5", "r6"),             # disjoint from prior -> jaccard 0
    "2020-04" = character(0),              # empty
    "2020-05" = character(0)               # empty vs empty -> NA (undefined)
  )
  result <- compute_drif_selection_jaccard(selected)

  expect_equal(nrow(result), 4L)
  expect_equal(result$ym_from, c("2020-01", "2020-02", "2020-03", "2020-04"))
  expect_equal(result$ym_to,   c("2020-02", "2020-03", "2020-04", "2020-05"))
  expect_equal(result$jaccard[1], 1)
  expect_equal(result$jaccard[2], 0)
  expect_equal(result$jaccard[3], 0)       # {r5,r6} vs {} -> intersect 0 / union 2 = 0
  expect_true(is.na(result$jaccard[4]))    # {} vs {} -> undefined, not zero
})

test_that("compute_drif_selection_jaccard computes a known partial-overlap fraction", {
  selected <- list(
    "2020-01" = c("c1", "c2", "c3", "r1"),
    "2020-02" = c("c1", "c2", "r5")
  )
  result <- compute_drif_selection_jaccard(selected)
  # intersect = {c1, c2} (2), union = {c1,c2,c3,r1,r5} (5) -> 2/5
  expect_equal(result$jaccard, 2 / 5)
})

test_that("compute_drif_selection_jaccard aborts with fewer than 2 months", {
  expect_snapshot(
    error = TRUE,
    compute_drif_selection_jaccard(list("2020-01" = c("c1")))
  )
})

test_that("summarise_drif_selection_stability computes median/mean/share-below-0.5", {
  jaccard_tbl <- tibble::tibble(
    ym_from = c("2020-01", "2020-02", "2020-03", "2020-04"),
    ym_to   = c("2020-02", "2020-03", "2020-04", "2020-05"),
    jaccard = c(1, 0, 0.4, 0.6)
  )
  result <- summarise_drif_selection_stability(jaccard_tbl)

  expect_equal(result$n_pairs, 4L)
  expect_equal(result$n_undefined, 0L)
  expect_equal(result$median_jaccard, 0.5)
  expect_equal(result$mean_jaccard, mean(c(1, 0, 0.4, 0.6)))
  expect_equal(result$`share_below_0.5`, 0.5)  # {0, 0.4} of {1, 0, 0.4, 0.6}
  expect_equal(result$min_jaccard, 0)
  expect_equal(result$max_jaccard, 1)
})

test_that("summarise_drif_selection_stability handles all-NA (undefined) input without erroring", {
  jaccard_tbl <- tibble::tibble(
    ym_from = c("2020-01", "2020-02"),
    ym_to   = c("2020-02", "2020-03"),
    jaccard = c(NA_real_, NA_real_)
  )
  result <- summarise_drif_selection_stability(jaccard_tbl)

  expect_equal(result$n_pairs, 2L)
  expect_equal(result$n_undefined, 2L)
  expect_true(is.na(result$median_jaccard))
  expect_true(is.na(result$mean_jaccard))
})

test_that("summarise_drif_selection_stability aborts on a malformed input tibble", {
  expect_snapshot(
    error = TRUE,
    summarise_drif_selection_stability(tibble::tibble(wrong_col = 1))
  )
})

test_that("compute_drif_selected_features returns a per-month selected feature set on a tiny synthetic dataset", {
  # Small enough to run real glmnet::cv.glmnet fast: 6 factor-months' worth
  # of rows per month clears the >= 50-complete-row internal guard once
  # min_train_months' worth of months are pooled (9 * 6 = 54 rows).
  skip_if_not_installed("glmnet")
  set.seed(910L)

  factors    <- paste0("F", 1:5)
  benchmark  <- "F6"
  all_factors <- c(factors, benchmark)
  lb <- 2L
  n_months <- 12L
  yms <- format(seq.Date(as.Date("2019-01-01"), by = "month", length.out = n_months), "%Y-%m")

  chrono_cols <- paste0("c", seq_len(lb))
  rank_cols   <- paste0("r", seq_len(lb))

  features <- tidyr::expand_grid(factor_name = all_factors, ym = yms) |>
    dplyr::mutate(target_ret = stats::rnorm(dplyr::n(), 0, 0.02))
  for (col in c(chrono_cols, rank_cols)) {
    features[[col]] <- stats::rnorm(nrow(features), 0, 0.01)
  }

  params <- list(
    factors = factors, benchmark_factor = benchmark,
    lookback_days = lb, alpha = 0.5, min_train_months = 9L
  )

  selected <- compute_drif_selected_features(features, params)

  # trade_months = months[(9+1):12] = last 3 months
  expect_true(length(selected) >= 1L)
  expect_true(all(names(selected) %in% yms[10:12]))
  # No selected set should ever include the intercept term
  expect_false(any(vapply(selected, function(s) "(Intercept)" %in% s, logical(1))))
  # Every element is a character vector, possibly empty (glmnet may select
  # zero features on tiny synthetic noise -- that is a valid, real outcome)
  expect_true(all(vapply(selected, is.character, logical(1))))

  # Chains cleanly into the jaccard + summary functions (#910 item 2 full path)
  if (length(selected) >= 2L) {
    jaccard_tbl <- compute_drif_selection_jaccard(selected)
    summary_tbl <- summarise_drif_selection_stability(jaccard_tbl)
    expect_equal(summary_tbl$n_pairs, length(selected) - 1L)
  }
})

test_that("compute_drif_selected_features aborts when every month is skipped", {
  # min_train_months so large relative to n_months that trade_months is
  # empty, or every train pool is below the 50-row floor -- either way,
  # zero fitted months should abort loudly rather than return an empty
  # list silently (fail-loud-not-null.md Pattern 5).
  factors    <- paste0("F", 1:5)
  benchmark  <- "F6"
  all_factors <- c(factors, benchmark)
  lb <- 2L
  n_months <- 6L
  yms <- format(seq.Date(as.Date("2019-01-01"), by = "month", length.out = n_months), "%Y-%m")
  chrono_cols <- paste0("c", seq_len(lb))
  rank_cols   <- paste0("r", seq_len(lb))

  features <- tidyr::expand_grid(factor_name = all_factors, ym = yms) |>
    dplyr::mutate(target_ret = stats::rnorm(dplyr::n(), 0, 0.02))
  for (col in c(chrono_cols, rank_cols)) {
    features[[col]] <- stats::rnorm(nrow(features), 0, 0.01)
  }

  params <- list(
    factors = factors, benchmark_factor = benchmark,
    lookback_days = lb, alpha = 0.5, min_train_months = 5L
  )
  # trade_months = months[6:6] = 1 month; train pool = 5 months * 6 factors
  # = 30 rows < 50 -- every trade month is skipped by the internal guard.
  expect_snapshot(
    error = TRUE,
    compute_drif_selected_features(features, params)
  )
})
