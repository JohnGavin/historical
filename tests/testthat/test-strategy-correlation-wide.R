testthat::local_edition(3)
# Tests for the leaderboard-wide correlation helpers added by #728 items 1+2
# (R/plan_strategy_correlation.R): .full_join_return_spine() and
# .build_wide_corr_matrix(), plus STRAT_RETURNS_WIDE_CODES itself.
#
# Both functions are split out as plain, unit-testable functions specifically
# because the rest of this file's logic lives embedded inside tar_target()
# calls, which have no test coverage today (no existing test file references
# strat_returns_aligned/strat_corr_matrix/strat_corr_augment) -- and #728
# item 2's leaderboard-wide correlation matrix is exactly the kind of silent
# NA-propagation risk fail-loud-not-null.md warns about, so it gets direct
# test coverage instead of only pipeline-time observation.

source(here::here("R/plan_strategy_correlation.R"))

# ── .full_join_return_spine(): fail-loud-not-null.md fix ───────────────────

test_that(".full_join_return_spine keeps every part's rows -- a gap in one series does not drop another's data", {
  # Series A has 3 months, series B only has the first 2 -- an inner_join
  # would drop 2026-03 entirely (the exact fail-loud-not-null.md "One
  # series' gap silently deletes the period for all of them" defect).
  a <- tibble::tibble(ym = c("2026-01", "2026-02", "2026-03"), a = c(0.01, 0.02, 0.03))
  b <- tibble::tibble(ym = c("2026-01", "2026-02"), b = c(0.10, 0.20))

  out <- .full_join_return_spine(list(a, b))

  expect_equal(nrow(out), 3L)
  expect_equal(out$ym, c("2026-01", "2026-02", "2026-03"))
  expect_true(is.na(out$b[out$ym == "2026-03"]))
  # Series A's 2026-03 value survives even though B has no data that month.
  expect_equal(out$a[out$ym == "2026-03"], 0.03)
})

test_that(".full_join_return_spine unions ym values across all parts, not just the first", {
  a <- tibble::tibble(ym = "2026-01", a = 0.01)
  b <- tibble::tibble(ym = "2026-06", b = 0.02)
  c <- tibble::tibble(ym = "2026-12", c = 0.03)

  out <- .full_join_return_spine(list(a, b, c))

  expect_setequal(out$ym, c("2026-01", "2026-06", "2026-12"))
  expect_equal(nrow(out), 3L)
})

# ── .build_wide_corr_matrix() ───────────────────────────────────────────────

test_that(".build_wide_corr_matrix returns a square, symmetric, unit-diagonal matrix matching stats::cor()", {
  set.seed(728)
  n <- 100L
  ret_tbl <- tibble::tibble(
    x = rnorm(n), y = rnorm(n), z = rnorm(n)
  )
  out <- .build_wide_corr_matrix(ret_tbl, c("x", "y", "z"), min_obs = 12L)

  expect_equal(dim(out), c(3L, 3L))
  expect_equal(rownames(out), c("x", "y", "z"))
  expect_equal(colnames(out), c("x", "y", "z"))
  expect_equal(unname(diag(out)), rep(1, 3L))
  expect_true(max(abs(out - t(out))) < 1e-12)
  expect_equal(out, stats::cor(as.matrix(ret_tbl[, c("x", "y", "z")])), ignore_attr = TRUE)
})

test_that(".build_wide_corr_matrix drops columns below min_obs instead of propagating their NA", {
  set.seed(729)
  n <- 100L
  ret_tbl <- tibble::tibble(
    plenty_a = rnorm(n),
    plenty_b = rnorm(n),
    sparse   = c(rnorm(5L), rep(NA_real_, n - 5L))  # only 5 non-NA, below default min_obs
  )
  out <- .build_wide_corr_matrix(ret_tbl, c("plenty_a", "plenty_b", "sparse"), min_obs = 12L)

  # "sparse" dropped entirely -- 2x2 matrix, not a 3x3 with NA cells.
  expect_equal(dim(out), c(2L, 2L))
  expect_setequal(rownames(out), c("plenty_a", "plenty_b"))
})

test_that(".build_wide_corr_matrix aborts (does not silently return NA) when fewer than 2 columns qualify", {
  ret_tbl <- tibble::tibble(only_col = rnorm(50L))
  expect_error(
    .build_wide_corr_matrix(ret_tbl, "only_col", min_obs = 12L),
    regexp = "at least 2 strategies"
  )
  expect_snapshot(
    error = TRUE,
    .build_wide_corr_matrix(ret_tbl, "only_col", min_obs = 12L)
  )
})

test_that(".build_wide_corr_matrix aborts and names the pair when pairwise overlap is too sparse for stats::cor()", {
  # x and y each individually clear min_obs, but they share only 1
  # non-NA row in common -- stats::cor(use = "pairwise.complete.obs")
  # returns NA for that pair, which must fail loudly, not silently.
  n <- 20L
  ret_tbl <- tibble::tibble(
    x = c(rnorm(n), rep(NA_real_, n)),
    y = c(rep(NA_real_, n), rnorm(n - 1L), 1)
  )
  # Overlap: only the very last row is non-NA on both sides.
  expect_error(
    .build_wide_corr_matrix(ret_tbl, c("x", "y"), min_obs = 12L),
    regexp = "NA pairwise cell"
  )
})

# ── STRAT_RETURNS_WIDE_CODES itself ─────────────────────────────────────────

test_that("STRAT_RETURNS_WIDE_CODES has no duplicates and matches the 11-strategy #728 coverage", {
  expect_equal(length(STRAT_RETURNS_WIDE_CODES), length(unique(STRAT_RETURNS_WIDE_CODES)))
  expect_length(STRAT_RETURNS_WIDE_CODES, 11L)
})
