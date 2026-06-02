# Tests for hd_record_stability_metrics() (#400 PR 3/6)
#
# Covers:
#   1. End-to-end: 8 rows written to bt.metric
#   2. Idempotency: second call still leaves exactly 8 rows
#   3. Different w: w=60 vs w=252 produce different SSR values
#   4. NA returns: 10 % NAs interleaved; helper completes; metrics computed
#   5. Monthly frequency: ann_factor=12, w=36 on 240 obs; sensible values

# ── shared fixture ────────────────────────────────────────────────────────

.setup_for_stability <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  hd_strategy_upsert(con, list(
    strategy_id = "test_strat",
    short_name  = "TS",
    long_name   = "Test Strategy",
    asset_class = "equity"
  ))
  uuid <- hd_run_record(con, strategy_id = "test_strat", partition = "full")
  list(tmp = tmp, con = con, uuid = uuid)
}

.count_metric_rows <- function(con, uuid) {
  DBI::dbGetQuery(
    con,
    "SELECT COUNT(*) AS n FROM bt.metric WHERE run_uuid = ?",
    params = list(uuid)
  )$n
}

.get_metric_names <- function(con, uuid) {
  DBI::dbGetQuery(
    con,
    "SELECT metric_name FROM bt.metric WHERE run_uuid = ? ORDER BY metric_name",
    params = list(uuid)
  )$metric_name
}

# ── test 1: end-to-end — 8 rows written ──────────────────────────────────

test_that("hd_record_stability_metrics writes exactly 8 rows to bt.metric", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  set.seed(1)
  r <- rnorm(500L, mean = 5e-4, sd = 0.01)

  out <- hd_record_stability_metrics(s$con, s$uuid, returns = r, w = 63L)

  expect_equal(.count_metric_rows(s$con, s$uuid), 8L)

  expected_names <- sort(c(
    "ssr", "ssr_mean_sharpe", "ssr_se", "ssr_n_windows", "ssr_lag_nw",
    "top_share", "top_n_top", "top_n_total"
  ))
  expect_equal(.get_metric_names(s$con, s$uuid), expected_names)
})

test_that("hd_record_stability_metrics returns the 8-element list invisibly", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  set.seed(2)
  r <- rnorm(300L, mean = 4e-4, sd = 0.01)

  out <- hd_record_stability_metrics(s$con, s$uuid, returns = r, w = 63L)

  expect_named(
    out,
    c("ssr", "ssr_mean_sharpe", "ssr_se", "ssr_n_windows", "ssr_lag_nw",
      "top_share", "top_n_top", "top_n_total")
  )
  expect_true(is.numeric(out$ssr))
  expect_true(is.numeric(out$top_share))
})

# ── test 2: idempotency ───────────────────────────────────────────────────

test_that("calling hd_record_stability_metrics twice leaves exactly 8 rows", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  set.seed(3)
  r <- rnorm(500L, mean = 5e-4, sd = 0.01)

  hd_record_stability_metrics(s$con, s$uuid, returns = r, w = 63L)
  hd_record_stability_metrics(s$con, s$uuid, returns = r, w = 63L)

  expect_equal(.count_metric_rows(s$con, s$uuid), 8L)
})

# ── test 3: different w produces different SSR values ────────────────────

test_that("w=60 and w=252 produce different SSR values", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  s1 <- .setup_for_stability()
  uuid2 <- hd_run_record(s1$con, strategy_id = "test_strat", partition = "w252")
  withr::defer({
    DBI::dbDisconnect(s1$con, shutdown = TRUE)
    unlink(s1$tmp)
  })

  set.seed(4)
  r <- rnorm(600L, mean = 5e-4, sd = 0.01)

  out60  <- hd_record_stability_metrics(s1$con, s1$uuid, returns = r, w = 60L)
  out252 <- hd_record_stability_metrics(s1$con, uuid2,   returns = r, w = 252L)

  # SSR values must differ because window length changes the rolling series.
  expect_false(isTRUE(all.equal(out60$ssr, out252$ssr)))
})

# ── test 4: NA returns ────────────────────────────────────────────────────

test_that("10 % NAs interleaved: helper completes and metrics are non-NA", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  set.seed(5)
  r <- rnorm(500L, mean = 5e-4, sd = 0.01)
  # Inject ~10 % NAs at regular positions
  r[seq(1L, 500L, by = 10L)] <- NA_real_

  out <- hd_record_stability_metrics(s$con, s$uuid, returns = r, w = 63L)

  expect_equal(.count_metric_rows(s$con, s$uuid), 8L)
  # SSR should be numeric (not NA) because enough observations remain
  expect_false(is.na(out$ssr))
  # n_total reflects the count after NA removal
  expect_lt(out$top_n_total, 500L)
})

test_that("all-NA returns: helper returns 8-element NA list without writing", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  out <- hd_record_stability_metrics(
    s$con, s$uuid,
    returns = rep(NA_real_, 100L),
    w = 20L
  )

  expect_equal(.count_metric_rows(s$con, s$uuid), 0L)
  expect_true(is.na(out$ssr))
  expect_true(is.na(out$top_share))
})

# ── test 5: monthly frequency ─────────────────────────────────────────────

test_that("monthly frequency: ann_factor=12, w=36, 240 obs gives sensible values", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  s <- .setup_for_stability()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  set.seed(6)
  # 240 monthly obs (20 years); positive drift -> positive SSR expected
  r <- rnorm(240L, mean = 0.005, sd = 0.04)

  out <- hd_record_stability_metrics(
    s$con, s$uuid,
    returns    = r,
    w          = 36L,
    ann_factor = 12,
    pct        = 0.05
  )

  expect_equal(.count_metric_rows(s$con, s$uuid), 8L)

  # n_windows = 240 - 36 + 1 = 205
  expect_equal(out$ssr_n_windows, 205L)

  # With a positive-drift series SSR should be > 0
  expect_gt(out$ssr, 0)

  # top_n_total reflects 240 obs (no NAs)
  expect_equal(out$top_n_total, 240L)

  # top_n_top = ceiling(240 * 0.05) = 12
  expect_equal(out$top_n_top, 12L)
})
