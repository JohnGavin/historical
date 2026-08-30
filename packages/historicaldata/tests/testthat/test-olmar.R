# Tests for OLMAR-1: olmar_simplex_project, olmar_update, olmar_backtest
# All tests are OFFLINE — no network calls, no file I/O to inst/extdata.
# testthat edition 3.

# ── olmar_simplex_project ─────────────────────────────────────────────────

test_that("simplex_project: output sums to 1", {
  v <- c(3, 1, -1, 2)
  w <- olmar_simplex_project(v)
  expect_equal(sum(w), 1, tolerance = 1e-8)

  # Tier A: function signature snapshot (catches param renames/additions).
  expect_snapshot(args(olmar_simplex_project))
})

test_that("simplex_project: all elements >= 0", {
  v <- c(3, 1, -1, 2)
  w <- olmar_simplex_project(v)
  expect_true(all(w >= 0))
})

test_that("simplex_project: idempotent on a point already in the simplex", {
  # A valid simplex point should map to itself
  v <- c(0.5, 0.3, 0.2)
  w <- olmar_simplex_project(v)
  expect_equal(w, v, tolerance = 1e-8)
})

test_that("simplex_project: handles vector with all negatives", {
  v <- c(-3, -1, -2)
  w <- olmar_simplex_project(v)
  expect_equal(sum(w), 1, tolerance = 1e-8)
  expect_true(all(w >= 0))
})

test_that("simplex_project: handles single-element vector", {
  w <- olmar_simplex_project(5)
  expect_equal(w, 1, tolerance = 1e-8)
})

test_that("simplex_project: errors on non-numeric input", {
  expect_snapshot(error = TRUE, olmar_simplex_project("a"))
})

test_that("simplex_project: errors on empty vector", {
  expect_snapshot(error = TRUE, olmar_simplex_project(numeric(0L)))
})

# ── olmar_update ─────────────────────────────────────────────────────────

test_that("olmar_update: returns valid simplex weight", {
  b <- c(0.5, 0.3, 0.2)
  x <- c(1.1, 0.9, 1.0)
  w <- olmar_update(b, x, epsilon = 10)
  expect_equal(sum(w), 1, tolerance = 1e-8)
  expect_true(all(w >= 0))
})

test_that("olmar_update: higher x_pred asset gets more weight from equal start", {
  # Asset 1 has x_pred > x_pred[2] = x_pred[3]  (MA/price > 1 => expect rise)
  # Starting from equal weight, the update should tilt toward asset 1.
  b_eq <- c(1/3, 1/3, 1/3)
  # x_pred[1] = 2.0 (strong mean-reversion signal), others near 1
  x <- c(2.0, 1.0, 1.0)
  w <- olmar_update(b_eq, x, epsilon = 10)
  expect_true(w[1] > w[2])
  expect_true(w[1] > w[3])
})

test_that("olmar_update: equal x_pred leaves weights unchanged", {
  # When all x_pred are equal, lambda = 0 (x_bar - x_pred = 0 for all),
  # so weights should stay at b_prev.
  b <- c(0.4, 0.4, 0.2)
  x <- c(1.0, 1.0, 1.0)
  w <- olmar_update(b, x, epsilon = 10)
  expect_equal(w, b, tolerance = 1e-8)
})

test_that("olmar_update: errors on length mismatch", {
  b <- c(0.5, 0.5)
  x <- c(1.0, 1.0, 1.0)
  expect_snapshot(error = TRUE, olmar_update(b, x))
})

test_that("olmar_update: errors on non-positive epsilon", {
  b <- c(0.5, 0.5)
  x <- c(1.1, 0.9)
  expect_snapshot(error = TRUE, olmar_update(b, x, epsilon = 0))
  expect_snapshot(error = TRUE, olmar_update(b, x, epsilon = -1))
})

# ── olmar_backtest ────────────────────────────────────────────────────────

# Helper: make a synthetic mean-reverting price matrix (offline, deterministic)
make_mr_prices <- function(n_days = 200L, n_assets = 4L, seed = 42L) {
  set.seed(seed)
  # Prices that oscillate around a mean (simple AR(1) with phi = -0.5)
  mat <- matrix(NA_real_, nrow = n_days, ncol = n_assets)
  for (j in seq_len(n_assets)) {
    p <- numeric(n_days)
    p[1L] <- 100
    for (i in 2:n_days) {
      # Mean-reverting: pull toward 100 + small noise
      p[i] <- p[i-1] + (-0.5) * (p[i-1] - 100) + rnorm(1, 0, 2)
    }
    mat[, j] <- pmax(p, 1)  # keep prices positive
  }
  mat
}

test_that("olmar_backtest: returns expected columns", {
  prices <- make_mr_prices()
  result <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2, cost_bps = 5)
  expect_s3_class(result, "tbl_df")
  expect_named(result, c("date", "gross_ret", "net_ret", "turnover"))
  expect_equal(nrow(result), nrow(prices))

  # Tier A: schema snapshot (catches column renames/additions/removals).
  expect_snapshot(names(result))
})

test_that("olmar_backtest: net_ret <= gross_ret where turnover > 0", {
  prices <- make_mr_prices()
  result <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2, cost_bps = 10)
  active_days <- result$turnover > 1e-10
  if (any(active_days)) {
    expect_true(all(result$net_ret[active_days] <= result$gross_ret[active_days] + 1e-10))
  }
})

test_that("olmar_backtest: LOOK-AHEAD GUARD — perturbing only the last day's prices does not change earlier weights/returns", {
  prices_orig  <- make_mr_prices(n_days = 50L)
  prices_perturb <- prices_orig
  # Perturb only the very last row substantially
  prices_perturb[50L, ] <- prices_perturb[50L, ] * 2

  r_orig    <- olmar_backtest(prices_orig, window = 10L, epsilon = 5, leverage = 0.5, cost_bps = 0)
  r_perturb <- olmar_backtest(prices_perturb, window = 10L, epsilon = 5, leverage = 0.5, cost_bps = 0)

  # All rows EXCEPT the last should be identical
  # (weight at t uses prices[1:t]; changing prices[50] affects only
  # the gross_ret of row 49 which uses prices[50]/prices[49], and
  # the formation at row 50 itself — nothing earlier.)
  # Actually row 49 realizes return at t+1=50, so row 49 gross_ret changes too.
  # Rows 1..48 should be completely unchanged.
  n <- nrow(r_orig)
  if (n > 2L) {
    expect_equal(r_orig$gross_ret[1:(n - 2L)], r_perturb$gross_ret[1:(n - 2L)],
                 tolerance = 1e-10)
    expect_equal(r_orig$net_ret[1:(n - 2L)], r_perturb$net_ret[1:(n - 2L)],
                 tolerance = 1e-10)
    expect_equal(r_orig$turnover[1:(n - 2L)], r_perturb$turnover[1:(n - 2L)],
                 tolerance = 1e-10)
  }
})

test_that("olmar_backtest: small numeric sanity check (2 assets, 5 days)", {
  # Hand-verifiable case: 2 assets, prices go up then down for asset 1
  # and inverse for asset 2, so MA should consistently prefer one.
  # window = 3 so we need >=4 days of prices for at least 1 valid return.
  prices <- matrix(
    c(100, 105, 102, 108, 103,   # asset 1: moderate mean-reversion
      100, 95,  98,  92,  97),   # asset 2: inverse
    nrow = 5, ncol = 2
  )
  result <- olmar_backtest(prices, window = 3L, epsilon = 5, leverage = 1, cost_bps = 0)
  # Should return 5 rows
  expect_equal(nrow(result), 5L)
  # Gross return column should be finite (no NaN, no Inf)
  expect_true(all(is.finite(result$gross_ret)))
  # Net ret equals gross ret when cost_bps = 0
  expect_equal(result$net_ret, result$gross_ret, tolerance = 1e-10)
})

test_that("olmar_backtest: errors on insufficient rows", {
  prices <- matrix(rnorm(20), nrow = 4L, ncol = 5L)
  expect_snapshot(error = TRUE, olmar_backtest(prices, window = 25L))
})

test_that("olmar_backtest: handles data.frame with date column", {
  prices <- make_mr_prices(n_days = 50L, n_assets = 3L)
  dates  <- seq.Date(as.Date("2020-01-01"), by = "day", length.out = 50L)
  df     <- as.data.frame(prices)
  df$date <- dates
  result <- olmar_backtest(df, window = 10L, epsilon = 5, leverage = 0.2, cost_bps = 5)
  expect_s3_class(result$date[1L], "Date")
  expect_equal(nrow(result), 50L)
})

# ── olmar_backtest: signal_null (#718) ──────────────────────────────────────

test_that("signal_null = FALSE (default) is unaffected by seed", {
  prices <- make_mr_prices(n_days = 60L, n_assets = 4L)
  # Real backtest ignores `seed` entirely when signal_null is FALSE.
  r1 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2, seed = 1L)
  r2 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2, seed = 999L)
  expect_equal(r1, r2)
})

test_that("signal_null = TRUE with a seed is reproducible", {
  prices <- make_mr_prices(n_days = 60L, n_assets = 4L)
  r1 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2,
                        signal_null = TRUE, seed = 42L)
  r2 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2,
                        signal_null = TRUE, seed = 42L)
  expect_equal(r1, r2)
})

test_that("signal_null = TRUE with different seeds gives different returns", {
  prices <- make_mr_prices(n_days = 60L, n_assets = 4L)
  r1 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2,
                        signal_null = TRUE, seed = 1L)
  r2 <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2,
                        signal_null = TRUE, seed = 2L)
  expect_false(identical(r1$net_ret, r2$net_ret))
})

test_that("signal_null = TRUE keeps the same schema and row count as the real backtest", {
  prices <- make_mr_prices(n_days = 60L, n_assets = 4L)
  real <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2)
  null <- olmar_backtest(prices, window = 10L, epsilon = 5, leverage = 0.2,
                          signal_null = TRUE, seed = 42L)
  expect_named(null, names(real))
  expect_equal(nrow(null), nrow(real))
})

test_that("signal_null must be a single non-NA logical", {
  prices <- make_mr_prices(n_days = 30L, n_assets = 3L)
  expect_snapshot(error = TRUE,
    olmar_backtest(prices, window = 10L, signal_null = "yes"))
  expect_snapshot(error = TRUE,
    olmar_backtest(prices, window = 10L, signal_null = NA))
})

test_that("seed must be NULL or a single numeric", {
  prices <- make_mr_prices(n_days = 30L, n_assets = 3L)
  expect_snapshot(error = TRUE,
    olmar_backtest(prices, window = 10L, signal_null = TRUE, seed = "42"))
})

# ── hd_rlog_uuid export ───────────────────────────────────────────────────
# Step 0 requirement: hd_rlog_uuid() is now exported.

test_that("hd_rlog_uuid() is exported and produces valid UUID-v4", {
  uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  u <- historicaldata::hd_rlog_uuid()
  expect_match(u, uuid_re)
})

test_that("hd_rlog_uuid() can be used to pre-generate ids for lineage chaining", {
  # Simulate the Step 0 use-case: caller pre-generates id, passes as parent_uuid
  hyp_id  <- historicaldata::hd_rlog_uuid()
  impl_id <- historicaldata::hd_rlog_uuid()
  expect_false(is.na(hyp_id))
  expect_false(hyp_id == impl_id)  # distinct
})

test_that("olmar research-log DB lineage write works with synthetic metrics (temp dir)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("jsonlite")

  tmp <- withr::local_tempdir()

  hyp_id  <- historicaldata::hd_rlog_uuid()
  impl_id <- historicaldata::hd_rlog_uuid()
  res_id  <- historicaldata::hd_rlog_uuid()

  # 1. Hypothesis
  historicaldata::hd_rlog_append("hypotheses",
    tibble::tibble(
      uuid            = hyp_id,
      economic_claim  = "Equity prices mean-revert toward SMA (test)",
      dependent_var   = "next-day portfolio return",
      predictor       = "MA/price ratio (OLMAR-1)",
      sample_spec     = "30-ticker US large-cap, 2010-2025 (synthetic)",
      null_hypothesis = "No MA-reversion premium net of costs",
      status          = "tested",
      extra_json      = NA_character_
    ),
    base_dir = tmp
  )

  # 2. Implementation
  historicaldata::hd_rlog_append("implementations",
    tibble::tibble(
      uuid          = impl_id,
      parent_uuid   = hyp_id,
      code_ref      = "R/plan_olmar.R + packages/historicaldata/R/olmar.R",
      notebook_path = NA_character_,
      params_json   = '{"window":25,"epsilon":10,"leverage":0.2,"cost_bps":10}',
      extra_json    = NA_character_
    ),
    base_dir = tmp
  )

  # 3. Results
  historicaldata::hd_rlog_append("results",
    tibble::tibble(
      uuid                = res_id,
      parent_uuid         = impl_id,
      strategy_id         = "olmar",
      partition           = "full",
      cagr                = 0.05,
      sharpe_hac          = 0.42,
      max_dd              = -0.18,
      turnover_annual     = 12.5,
      n_obs               = 3780L,
      results_db_run_date = Sys.Date(),
      extra_json          = NA_character_
    ),
    base_dir = tmp
  )

  # 4. Critiques
  historicaldata::hd_rlog_append("critiques",
    tibble::tibble(
      uuid         = c(historicaldata::hd_rlog_uuid(), historicaldata::hd_rlog_uuid()),
      parent_uuid  = res_id,
      defect_class = c("look_ahead", "omitted_costs"),
      severity     = c("critical", "major"),
      finding      = c(
        "weights at t from prices[1:t]; r_{t+1} not used in formation",
        "10 bps one-way cost applied; avg daily turnover ~0.05"
      ),
      cell_ref     = c("olmar.R:olmar_backtest()", "olmar.R:olmar_backtest()"),
      resolved     = c(TRUE, TRUE)
    ),
    base_dir = tmp
  )

  # 5. Robustness
  historicaldata::hd_rlog_append("robustness",
    tibble::tibble(
      uuid         = c(historicaldata::hd_rlog_uuid(), historicaldata::hd_rlog_uuid()),
      parent_uuid  = res_id,
      panel_name   = c("Training", "Testing"),
      variation    = "window=25,epsilon=10,leverage=0.2",
      metric_name  = "sharpe",
      metric_value = c(0.55, 0.38),
      passed       = c(TRUE, TRUE),
      extra_json   = NA_character_
    ),
    base_dir = tmp
  )

  # Verify lineage walkable from res_id back to hyp_id
  lin <- historicaldata::hd_rlog_lineage(res_id, base_dir = tmp)
  expect_equal(nrow(lin), 3L)
  expect_equal(lin$table[1L], "results")
  expect_equal(lin$table[2L], "implementations")
  expect_equal(lin$table[3L], "hypotheses")

  # Verify all 5 tables have rows
  for (tbl in c("hypotheses", "implementations", "results", "critiques", "robustness")) {
    rows <- historicaldata::hd_rlog_query(tbl, base_dir = tmp)
    expect_gt(nrow(rows), 0L, label = paste0(tbl, " has rows"))
  }
})
