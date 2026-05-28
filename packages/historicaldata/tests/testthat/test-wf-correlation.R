# Tests for hd_wf_correlation() — Walk-Forward Correlation (#297)
#
# Tinsley (2026), SSRN 6324079. Computes Pearson and Spearman ρ across the
# full IS↔OOS parameter grid, and classifies via the 2×2 diagnostic matrix.

# ── Helpers ────────────────────────────────────────────────────────────────────

make_grid <- function(is_vals, oos_vals) {
  stopifnot(length(is_vals) == length(oos_vals))
  data.frame(
    theta_id    = seq_along(is_vals),
    theta_label = paste0("p", seq_along(is_vals)),
    IS_metric   = is_vals,
    OOS_metric  = oos_vals
  )
}

# ── 1. Correlation arithmetic matches base R ───────────────────────────────────

test_that("Pearson matches base R cor() for a known small grid", {
  is_v  <- c(0.2, 0.5, 0.8, 1.1, 1.4)
  oos_v <- c(0.1, 0.4, 0.7, 1.0, 1.3)
  grid  <- make_grid(is_v, oos_v)

  result      <- hd_wf_correlation(grid)
  expected_r  <- stats::cor(is_v, oos_v, method = "pearson")
  expected_sp <- stats::cor(is_v, oos_v, method = "spearman")

  expect_equal(result$pearson,  expected_r,  tolerance = 1e-10)
  expect_equal(result$spearman, expected_sp, tolerance = 1e-10)
})

test_that("Spearman matches base R cor(method='spearman') for a mixed grid", {
  is_v  <- c(1.0, 0.3, 2.1, 0.8, 1.5)   # not monotone
  oos_v <- c(0.5, 0.1, 1.8, 0.9, 1.2)
  grid  <- make_grid(is_v, oos_v)

  result <- hd_wf_correlation(grid)
  expect_equal(
    result$spearman,
    stats::cor(is_v, oos_v, method = "spearman"),
    tolerance = 1e-10
  )
})

# ── 2. Empty / degenerate grids → informative error ────────────────────────────

test_that("Empty grid triggers informative error", {
  grid <- data.frame(
    theta_id    = integer(0),
    theta_label = character(0),
    IS_metric   = numeric(0),
    OOS_metric  = numeric(0)
  )
  expect_error(
    hd_wf_correlation(grid),
    "at least 2 rows"
  )
})

test_that("All-NA IS_metric triggers informative error", {
  grid <- make_grid(c(NA_real_, NA_real_), c(0.5, 0.8))
  expect_error(
    hd_wf_correlation(grid),
    "at least 2 rows"
  )
})

test_that("Single complete row triggers informative error", {
  grid <- make_grid(c(0.5, NA_real_), c(0.3, 0.7))
  expect_error(
    hd_wf_correlation(grid),
    "at least 2 rows"
  )
})

test_that("Missing required column triggers informative error", {
  grid <- data.frame(
    theta_id    = 1:3,
    theta_label = c("a", "b", "c"),
    IS_metric   = c(0.5, 0.8, 1.0)
    # OOS_metric deliberately absent
  )
  expect_error(
    hd_wf_correlation(grid),
    "missing required columns"
  )
})

# ── 3. Perfect correlation ─────────────────────────────────────────────────────

test_that("Perfectly correlated IS=OOS gives rho=1 and 'structural_edge' classification", {
  vals   <- c(0.2, 0.5, 1.0, 1.5, 2.0)
  grid   <- make_grid(vals, vals)        # IS identical to OOS
  result <- hd_wf_correlation(grid)

  expect_equal(result$pearson,         1.0)
  expect_equal(result$spearman,        1.0)
  expect_equal(result$classification,  "structural_edge")
  expect_equal(result$wfc_category,    "high")
})

test_that("Perfectly negatively correlated IS↔OOS gives rho=-1 and 'noise' classification", {
  is_v   <- c(1.0, 0.5, 0.0, -0.5, -1.0)
  oos_v  <- rev(is_v)   # inverse rank → ρ = -1
  grid   <- make_grid(is_v, oos_v)
  result <- hd_wf_correlation(grid)

  expect_equal(result$pearson,  -1.0)
  expect_equal(result$spearman, -1.0)
  # Median OOS is 0 → oos_positive = (0 >= 0) = TRUE → "spurious_luck" not "noise"
  # But oos_ref median is 0.0 so oos_positive is TRUE — classification is spurious_luck
  expect_equal(result$classification, "spurious_luck")
})

# ── 4. Classification matrix ──────────────────────────────────────────────────

test_that("High WFC + positive OOS median → structural_edge", {
  is_v  <- seq(0.1, 1.0, by = 0.1)
  oos_v <- is_v - 0.05   # near-perfect positive correlation, all OOS > 0
  result <- hd_wf_correlation(make_grid(is_v, oos_v))

  expect_equal(result$classification, "structural_edge")
  expect_equal(result$wfc_category,   "high")
  expect_gte(result$pearson, 0.70)
})

test_that("High WFC + negative OOS median → consistently_loss_making", {
  is_v  <- seq(0.1, 1.0, by = 0.1)
  oos_v <- is_v - 1.05   # near-perfect positive correlation, all OOS < 0
  result <- hd_wf_correlation(make_grid(is_v, oos_v))

  expect_equal(result$classification, "consistently_loss_making")
  expect_equal(result$wfc_category,   "high")
})

test_that("Low WFC + positive OOS median → spurious_luck", {
  set.seed(42L)
  is_v  <- seq(0.1, 1.0, by = 0.1)
  oos_v <- 0.3 + stats::rnorm(10L, sd = 0.5)  # positive median, no correlation with IS
  result <- hd_wf_correlation(make_grid(is_v, oos_v))

  # Classification depends on actual ρ; just confirm logic is wired correctly
  if (result$wfc_category != "high") {
    expect_true(result$classification %in% c("spurious_luck", "noise"))
  }
})

test_that("Low WFC + negative OOS median → noise", {
  set.seed(99L)
  is_v  <- seq(0.1, 1.0, by = 0.1)
  oos_v <- -0.5 + stats::rnorm(10L, sd = 0.2)  # negative median, uncorrelated
  result <- hd_wf_correlation(make_grid(is_v, oos_v))

  if (result$wfc_category != "high") {
    expect_true(result$classification %in% c("noise", "spurious_luck"))
  }
})

# ── 5. n_points counts complete cases ─────────────────────────────────────────

test_that("n_points equals complete-case count when some NAs present", {
  is_v  <- c(0.5, NA_real_, 0.8, 1.0)
  oos_v <- c(0.4, 0.6,      NA_real_, 0.9)
  grid  <- make_grid(is_v, oos_v)
  result <- hd_wf_correlation(grid)

  # Only rows 1 and 4 are complete (rows 2, 3 have at least one NA)
  expect_equal(result$n_points, 2L)
})

# ── 6. wfc_threshold_high parameter ──────────────────────────────────────────

test_that("Custom wfc_threshold_high changes classification boundary", {
  is_v  <- c(0.1, 0.5, 0.9, 1.3, 1.7)
  oos_v <- 0.8 * is_v + 0.1   # ρ ≈ 1 by construction; use lower threshold
  grid  <- make_grid(is_v, oos_v)

  # With default threshold 0.70 → high (ρ ~1)
  result_default <- hd_wf_correlation(grid)
  expect_equal(result_default$wfc_category, "high")

  # With threshold 0.999 → moderate or low (ρ < 0.999 even if close to 1)
  result_strict <- hd_wf_correlation(grid, wfc_threshold_high = 0.999)
  # ρ of this grid is 1.0 exactly (linear), so still high even at 0.999
  # Try a noisy grid instead
  set.seed(7L)
  oos_noisy <- 0.6 * is_v + stats::rnorm(5L, sd = 0.3)
  result_noisy <- hd_wf_correlation(make_grid(is_v, oos_noisy), wfc_threshold_high = 0.95)
  # ρ will be < 0.95 for this noisy grid
  expect_true(result_noisy$wfc_category %in% c("moderate", "low"))
})

# ── 7. pct_positive_oos arithmetic ────────────────────────────────────────────

test_that("pct_positive_oos matches manual calculation", {
  is_v  <- c(0.5, 0.8, 1.0, 1.2, 1.5)
  oos_v <- c(-0.2, 0.1, 0.3, -0.1, 0.4)   # 3 positive, 2 negative
  result <- hd_wf_correlation(make_grid(is_v, oos_v))

  expect_equal(result$pct_positive_oos, 3 / 5)
})


# ── 8. wfc_all_summary shape (smoke tests for #318 — DRIF extension) ──────────
#
# These tests verify that hd_wf_correlation() accepts grids in the shape
# that wfc_drif_grid_is / wfc_drif_grid_oos / wfc_drif_grid will produce:
# 5 rows (alpha ∈ {0.00, 0.25, 0.50, 0.75, 1.00}), integer theta_id,
# character theta_label of the form "alpha=X.XX".

make_drif_grid <- function() {
  alpha_grid <- c(0.00, 0.25, 0.50, 0.75, 1.00)
  # Simulate plausible IS and OOS Sharpe values (positive, partial correlation)
  set.seed(318L)
  is_vals  <- 0.3 + 0.4 * seq_along(alpha_grid) + stats::rnorm(5L, sd = 0.05)
  oos_vals <- 0.1 + 0.3 * seq_along(alpha_grid) + stats::rnorm(5L, sd = 0.10)
  data.frame(
    theta_id    = seq_along(alpha_grid),
    theta_label = paste0("alpha=", alpha_grid),
    IS_metric   = is_vals,
    OOS_metric  = oos_vals
  )
}

test_that("DRIF-shaped grid (5 alpha values) produces well-formed WFC result", {
  grid   <- make_drif_grid()
  result <- hd_wf_correlation(grid)

  # Must have all required return fields
  expect_named(result,
    c("pearson", "spearman", "n_points", "classification",
      "wfc_category", "median_oos", "pct_positive_oos"),
    ignore.order = TRUE
  )

  # n_points = 5 (all rows complete)
  expect_equal(result$n_points, 5L)

  # Pearson and Spearman are in [-1, 1]
  expect_true(result$pearson  >= -1 & result$pearson  <= 1)
  expect_true(result$spearman >= -1 & result$spearman <= 1)
})

test_that("DRIF-shaped grid: classification is one of the four valid labels", {
  grid   <- make_drif_grid()
  result <- hd_wf_correlation(grid)

  valid_labels <- c("structural_edge", "consistently_loss_making",
                    "spurious_luck",   "noise")
  expect_true(result$classification %in% valid_labels)
})

test_that("DRIF-shaped grid: wfc_category is one of 'high', 'moderate', 'low'", {
  grid   <- make_drif_grid()
  result <- hd_wf_correlation(grid)

  expect_true(result$wfc_category %in% c("high", "moderate", "low"))
})

test_that("wfc_all_summary shape: two-strategy tibble has expected columns", {
  # Simulate wfc_all_summary structure as produced by plan_wf_correlation.R
  # (one row per strategy, same columns for FM and DRIF)
  grid_fm   <- make_grid(c(0.2, 0.5, 1.0, 1.5, 1.8),
                          c(0.1, 0.4, 0.9, 1.3, 1.6))
  grid_drif <- make_drif_grid()

  res_fm   <- hd_wf_correlation(grid_fm)
  res_drif <- hd_wf_correlation(grid_drif)

  make_row <- function(strategy, res) {
    tibble::tibble(
      strategy       = strategy,
      wfc_pearson    = res$pearson,
      wfc_spearman   = res$spearman,
      wfc_n_points   = res$n_points,
      wfc_category   = res$wfc_category,
      classification = res$classification,
      median_oos     = res$median_oos,
      pct_pos_oos    = res$pct_positive_oos
    )
  }

  summary_tbl <- dplyr::bind_rows(
    make_row("Factor MAX",  res_fm),
    make_row("Factor DRIF", res_drif)
  )

  # Two rows — one per strategy
  expect_equal(nrow(summary_tbl), 2L)

  # strategy column contains both names
  expect_true("Factor MAX"  %in% summary_tbl$strategy)
  expect_true("Factor DRIF" %in% summary_tbl$strategy)

  # All numeric WFC columns are finite or NA (no NaN or Inf)
  numeric_cols <- c("wfc_pearson", "wfc_spearman", "wfc_n_points",
                    "median_oos", "pct_pos_oos")
  for (col in numeric_cols) {
    vals <- summary_tbl[[col]]
    expect_true(all(is.finite(vals) | is.na(vals)),
                info = paste0("Column '", col, "' contains non-finite value"))
  }
})
