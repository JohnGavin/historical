# Tests for SSR and top5pct columns added to the mom_prepeak gauntlet (#400)
#
# These tests verify that hd_sharpe_stability_ratio() and hd_top5pct_share()
# produce the expected list structure and numeric columns when called with a
# synthetic monthly return series — the same signature used in the gauntlet
# targets mom_prepeak_ssr and mom_prepeak_top5pct.
#
# All tests are self-contained and use set.seed() locally.

testthat::local_edition(3)

# ── Helpers ───────────────────────────────────────────────────────────────────

# Synthetic monthly L/S return series (positive mean, realistic vol)
make_monthly_returns <- function(n = 120L, mean_r = 0.005, sd_r = 0.04,
                                 seed = 42L) {
  set.seed(seed)
  stats::rnorm(n, mean = mean_r, sd = sd_r)
}


# ── SSR column structure ───────────────────────────────────────────────────────

test_that("G1: mom_prepeak_ssr target — hd_sharpe_stability_ratio returns expected names", {
  r <- make_monthly_returns()
  result <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expected_names <- c("ssr", "mean_sharpe", "se", "n_windows", "w",
                       "lag_nw", "ann_factor")
  expect_named(result, expected_names)
})

test_that("G2: mom_prepeak_ssr target — ssr is numeric scalar", {
  r <- make_monthly_returns()
  result <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expect_true(is.numeric(result$ssr))
  expect_length(result$ssr, 1L)
})

test_that("G3: mom_prepeak_ssr target — n_windows is positive integer for n=120, w=36", {
  r   <- make_monthly_returns(n = 120L)
  res <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  # Expect 120 - 36 + 1 = 85 complete windows
  expect_equal(res$n_windows, 120L - 36L + 1L)
})

test_that("G4: mom_prepeak_ssr target — returns NA ssr when fewer than 2 complete windows", {
  # n = 36 gives exactly 1 window, which is < 2 — SSR cannot be computed
  r   <- make_monthly_returns(n = 36L)
  res <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expect_true(is.na(res$ssr),
    info = "SSR must be NA when n_windows < 2")
})

test_that("G5: mom_prepeak_ssr target — positive-mean series yields positive mean_sharpe", {
  r   <- make_monthly_returns(n = 120L, mean_r = 0.01, sd_r = 0.02)
  res <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expect_true(!is.na(res$mean_sharpe) && res$mean_sharpe > 0,
    info = "Positive-mean return series should give positive mean_sharpe")
})

test_that("G6: mom_prepeak_ssr target — ann_factor=12 echoed in result", {
  r   <- make_monthly_returns()
  res <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)

  expect_equal(res$ann_factor, 12)
})


# ── top5pct_share column structure ────────────────────────────────────────────

test_that("G7: mom_prepeak_top5pct target — hd_top5pct_share returns expected names", {
  r      <- make_monthly_returns()
  result <- hd_top5pct_share(r)

  expected_names <- c("top_share", "n_top", "n_total", "pct", "total_return")
  expect_named(result, expected_names)
})

test_that("G8: mom_prepeak_top5pct target — top_share is numeric in (0, 1) for positive-mean series", {
  r      <- make_monthly_returns(n = 120L, mean_r = 0.005)
  result <- hd_top5pct_share(r)

  expect_true(is.numeric(result$top_share))
  expect_length(result$top_share, 1L)
  # For a positive-mean series, top_share should be positive
  expect_true(!is.na(result$top_share) && result$top_share > 0,
    info = "Positive-mean series should have positive top_share")
})

test_that("G9: mom_prepeak_top5pct target — n_top is ceiling(n_total * 0.05)", {
  n      <- 120L
  r      <- make_monthly_returns(n = n)
  result <- hd_top5pct_share(r)

  expected_n_top <- as.integer(ceiling(n * 0.05))
  expect_equal(result$n_top, expected_n_top)
})

test_that("G10: mom_prepeak_top5pct target — n_total matches length of non-NA returns", {
  n   <- 120L
  r   <- make_monthly_returns(n = n)
  res <- hd_top5pct_share(r)

  expect_equal(res$n_total, n)
})

test_that("G11: mom_prepeak_top5pct target — all-NA returns yields NA top_share", {
  r   <- rep(NA_real_, 50L)
  res <- hd_top5pct_share(r)

  expect_true(is.na(res$top_share),
    info = "All-NA input should yield NA top_share")
  expect_equal(res$n_total, 0L)
})


# ── Integration: gauntlet workflow ────────────────────────────────────────────

test_that("G12: gauntlet workflow — ssr and top5pct columns are numeric scalars", {
  # Simulates the gauntlet target computation on a synthetic return vector
  r <- make_monthly_returns(n = 120L)

  ssr_res  <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)
  top5_res <- hd_top5pct_share(r)

  ssr_col        <- round(ssr_res$ssr,          3)
  ssr_mean_sr    <- round(ssr_res$mean_sharpe,   3)
  ssr_n_windows  <- ssr_res$n_windows
  top5pct_share  <- round(top5_res$top_share,    3)

  expect_true(is.numeric(ssr_col)        && length(ssr_col)       == 1L)
  expect_true(is.numeric(ssr_mean_sr)    && length(ssr_mean_sr)   == 1L)
  expect_true(is.integer(ssr_n_windows)  && length(ssr_n_windows) == 1L)
  expect_true(is.numeric(top5pct_share)  && length(top5pct_share) == 1L)
})

test_that("G13: gauntlet workflow — tibble with all four new columns assembles cleanly", {
  r <- make_monthly_returns(n = 120L)

  ssr_res  <- hd_sharpe_stability_ratio(r, w = 36L, ann_factor = 12L)
  top5_res <- hd_top5pct_share(r)

  row <- tibble::tibble(
    ssr           = round(ssr_res$ssr,          3),
    ssr_mean_sr   = round(ssr_res$mean_sharpe,   3),
    ssr_n_windows = as.integer(ssr_res$n_windows),
    top5pct_share = round(top5_res$top_share,    3)
  )

  expect_equal(nrow(row), 1L)
  expect_true(all(c("ssr", "ssr_mean_sr", "ssr_n_windows", "top5pct_share") %in% names(row)))
  expect_true(all(vapply(row[c("ssr", "ssr_mean_sr", "top5pct_share")], is.numeric, logical(1L))))
  expect_true(is.integer(row$ssr_n_windows))
})
