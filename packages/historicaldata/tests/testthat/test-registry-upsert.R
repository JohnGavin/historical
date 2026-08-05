# Tests for hd_run_upsert() idempotent run recording (#375)
#
# Covers:
#  1. First run — inserts, returns UUID-shaped string.
#  2. Second run (idempotency) — still 1 row, same UUID, finished_at refreshed.
#  3. Metric refresh — old bt.metric rows deleted before re-insert.
#  4. Different partition — 2 rows for same strategy_id.

.setup_registry_for_upsert <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  hd_strategy_upsert(con, list(
    strategy_id = "test_strat",
    short_name  = "TS",
    long_name   = "Test Strategy",
    asset_class = "equity"
  ))
  list(tmp = tmp, con = con)
}

# ── Test 1: first run inserts a row and returns a valid UUID ──────────────

test_that("hd_run_upsert first call inserts 1 bt.run row and returns UUID", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  s <- .setup_registry_for_upsert()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  uuid <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  expect_match(
    uuid,
    "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  )

  n <- DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM bt.run")$n
  expect_equal(n, 1L)

  row <- DBI::dbGetQuery(
    s$con,
    "SELECT run_uuid, strategy_id FROM bt.run LIMIT 1"
  )
  expect_equal(row$run_uuid, uuid)
  expect_equal(row$strategy_id, "test_strat")
})

# ── Test 2: second call is idempotent — same UUID, refreshed timestamp ────

test_that("hd_run_upsert second call returns same UUID and refreshes finished_at", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  s <- .setup_registry_for_upsert()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  t1 <- as.POSIXct("2026-01-01 10:00:00", tz = "UTC")
  t2 <- as.POSIXct("2026-01-02 12:00:00", tz = "UTC")

  uuid1 <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    started_at       = t1,
    finished_at      = t1,
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  uuid2 <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    started_at       = t2,
    finished_at      = t2,
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  expect_equal(uuid1, uuid2)

  n <- DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM bt.run")$n
  expect_equal(n, 1L)

  row <- DBI::dbGetQuery(
    s$con,
    "SELECT finished_at FROM bt.run WHERE run_uuid = ?",
    params = list(uuid2)
  )
  # finished_at should have been updated to t2
  stored_ts <- as.POSIXct(row$finished_at, tz = "UTC")
  expect_true(as.numeric(stored_ts - t1, units = "secs") > 0)
})

# ── Test 3: metric refresh — old bt.metric rows deleted on re-upsert ─────

test_that("hd_run_upsert deletes old bt.metric rows when run already exists", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  s <- .setup_registry_for_upsert()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  uuid <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Insert a metric row for the first run.
  hd_metric_record(s$con, uuid, tibble::tibble(sharpe = 0.5), units = c(sharpe = "ratio"))

  n_before <- DBI::dbGetQuery(
    s$con,
    "SELECT COUNT(*) AS n FROM bt.metric WHERE run_uuid = ?",
    params = list(uuid)
  )$n
  expect_equal(n_before, 1L)

  # Re-upsert the same run.
  uuid2 <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    partition        = "phase1",
    pipeline_version = "phase1"
  )
  expect_equal(uuid, uuid2)

  # Old metric rows for this UUID must be gone (caller re-inserts fresh ones).
  n_after <- DBI::dbGetQuery(
    s$con,
    "SELECT COUNT(*) AS n FROM bt.metric WHERE run_uuid = ?",
    params = list(uuid)
  )$n
  expect_equal(n_after, 0L)
})

# ── Test 4: different partition → separate run rows ───────────────────────

test_that("hd_run_upsert with different partition creates 2 bt.run rows", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  s <- .setup_registry_for_upsert()
  withr::defer({
    DBI::dbDisconnect(s$con, shutdown = TRUE)
    unlink(s$tmp)
  })

  uuid_a <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  uuid_b <- hd_run_upsert(
    s$con,
    strategy_id      = "test_strat",
    partition        = "phase2",
    pipeline_version = "phase1"
  )

  expect_false(uuid_a == uuid_b)

  n <- DBI::dbGetQuery(s$con, "SELECT COUNT(*) AS n FROM bt.run")$n
  expect_equal(n, 2L)
})
