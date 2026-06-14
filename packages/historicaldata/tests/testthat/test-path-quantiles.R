## Tests for hd_path_quantiles() and hd_plot_fan_chart()
## Phase D of issue #389

# ── Toy fixture ──────────────────────────────────────────────────────────────
#
# Builds a minimal paths tibble without calling hd_simulate_paths() so tests
# remain fully offline (no MASS::mvrnorm dependency).

.make_paths <- function(n_assets = 2L, n_paths = 3L, n_years = 10L) {
  assets   <- c("SPY", "TLT")[seq_len(n_assets)]
  path_ids <- seq_len(n_paths)
  years    <- seq_len(n_years)

  ret <- stats::runif(n_assets * n_paths * n_years, min = -0.10, max = 0.25)
  tibble::tibble(
    path_id        = rep(rep(path_ids, each = n_years), times = n_assets),
    year           = rep(rep(years, times = n_paths), times = n_assets),
    asset          = rep(assets, each = n_paths * n_years),
    return_nominal = ret,
    return_real    = ret - 0.03,
    cum_nominal    = 1 + cumsum(ret) / length(ret),
    cum_real       = 1 + cumsum(ret - 0.03) / length(ret)
  )
}

# ── 1. Schema: output has exactly the expected columns ────────────────────────
test_that("hd_path_quantiles() returns expected column names (default probs)", {
  set.seed(99L)
  paths <- .make_paths()
  out   <- hd_path_quantiles(paths)
  expect_named(out, c("year", "asset", "q10", "q25", "q50", "q75", "q90"))
})

# ── 2. Row count: horizon_years × n_assets ───────────────────────────────────
test_that("hd_path_quantiles() returns one row per (year, asset) combination", {
  set.seed(99L)
  paths <- .make_paths(n_assets = 2L, n_paths = 3L, n_years = 10L)
  out   <- hd_path_quantiles(paths)
  expect_equal(nrow(out), 10L * 2L)
})

# ── 3. Monotonicity: q10 <= q25 <= q50 <= q75 <= q90 per row ─────────────────
test_that("quantiles are monotonically non-decreasing across all rows", {
  set.seed(99L)
  paths <- .make_paths()
  out   <- hd_path_quantiles(paths)
  expect_true(all(out$q10 <= out$q25))
  expect_true(all(out$q25 <= out$q50))
  expect_true(all(out$q50 <= out$q75))
  expect_true(all(out$q75 <= out$q90))
})

# ── 4. metric = "cum_real" differs from "cum_nominal" ────────────────────────
test_that("cum_real quantiles are strictly less than cum_nominal quantiles", {
  set.seed(99L)
  paths      <- .make_paths()
  nom        <- hd_path_quantiles(paths, metric = "cum_nominal")
  rea        <- hd_path_quantiles(paths, metric = "cum_real")
  # Real returns are deflated by 3% annually, so medians should be lower
  expect_true(mean(rea$q50) < mean(nom$q50))
})

# ── 5. Error snapshot: paths missing required column ─────────────────────────
test_that("missing cum_nominal column gives informative error", {
  set.seed(99L)
  bad_paths <- .make_paths()
  bad_paths <- bad_paths[, setdiff(colnames(bad_paths), "cum_nominal")]
  expect_snapshot(
    error = TRUE,
    hd_path_quantiles(bad_paths, metric = "cum_nominal")
  )
})

# ── 6. Error snapshot: probs out of range ─────────────────────────────────────
test_that("probs outside [0, 1] gives informative error", {
  set.seed(99L)
  paths <- .make_paths()
  expect_snapshot(
    error = TRUE,
    hd_path_quantiles(paths, probs = c(0.1, 1.5))
  )
})

# ── 7. Error snapshot: hd_plot_fan_chart missing required column ──────────────
test_that("hd_plot_fan_chart() with missing q50 gives informative error", {
  set.seed(99L)
  paths  <- .make_paths()
  quants <- hd_path_quantiles(paths)
  bad_q  <- quants[, setdiff(colnames(quants), "q50")]
  expect_snapshot(
    error = TRUE,
    hd_plot_fan_chart(bad_q)
  )
})

# ── 8. Function signature snapshot: hd_path_quantiles ────────────────────────
test_that("hd_path_quantiles() function signature is stable", {
  expect_snapshot(args(hd_path_quantiles))
})

# ── 9. Function signature snapshot: hd_plot_fan_chart ────────────────────────
test_that("hd_plot_fan_chart() function signature is stable", {
  expect_snapshot(args(hd_plot_fan_chart))
})

# ── 10. Smoke test: hd_plot_fan_chart returns a ggplot object ─────────────────
test_that("hd_plot_fan_chart() returns a ggplot2 object", {
  set.seed(99L)
  paths  <- .make_paths()
  quants <- hd_path_quantiles(paths)
  p      <- hd_plot_fan_chart(quants)
  expect_true(inherits(p, "ggplot"))
})

# ── 11. Single-asset: no faceting applied ────────────────────────────────────
test_that("hd_plot_fan_chart() with 1 asset returns unfaceted ggplot", {
  set.seed(99L)
  paths  <- .make_paths(n_assets = 1L)
  quants <- hd_path_quantiles(paths)
  p      <- hd_plot_fan_chart(quants)
  # facet_wrap adds a FacetWrap element; without it only FacetNull is present
  expect_false(inherits(p$facet, "FacetWrap"))
})

# ── 12. Two-asset: faceting applied ──────────────────────────────────────────
test_that("hd_plot_fan_chart() with 2 assets adds facet_wrap", {
  set.seed(99L)
  paths  <- .make_paths(n_assets = 2L)
  quants <- hd_path_quantiles(paths)
  p      <- hd_plot_fan_chart(quants)
  expect_true(inherits(p$facet, "FacetWrap"))
})

# ── 13. Custom probs produce correctly named columns ─────────────────────────
test_that("hd_path_quantiles() with custom probs names columns correctly", {
  set.seed(99L)
  paths <- .make_paths()
  out   <- hd_path_quantiles(paths, probs = c(0.05, 0.95))
  expect_named(out, c("year", "asset", "q5", "q95"))
})
