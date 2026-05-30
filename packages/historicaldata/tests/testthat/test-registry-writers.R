# Tests for hd_strategy_upsert + hd_run_record (#347 PR 2/4)

.init_tmp_registry <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  tmp
}

test_that("hd_strategy_upsert inserts a strategy row", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))

  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  hd_strategy_upsert(con, tibble::tibble(
    strategy_id    = "cmr",
    short_name     = "MR",
    long_name      = "Commodities Mean Reversion",
    asset_class    = "commodities",
    frequency      = "monthly",
    ann_factor     = 12L,
    directionality = "long_short",
    liquidity_tier = "med"
  ))

  got <- DBI::dbGetQuery(
    con,
    "SELECT strategy_id, short_name, asset_class FROM bt.strategy"
  )
  expect_equal(nrow(got), 1L)
  expect_equal(got$strategy_id, "cmr")
  expect_equal(got$asset_class, "commodities")
})

test_that("hd_strategy_upsert is idempotent (second call is a no-op)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))

  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  row <- tibble::tibble(strategy_id = "cmr", short_name = "MR",
                       long_name = "Commodities Mean Reversion")
  hd_strategy_upsert(con, row)
  hd_strategy_upsert(con, row)

  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM bt.strategy")$n
  expect_equal(n, 1L)
})

test_that("hd_strategy_upsert rejects empty strategy_id", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  expect_error(
    hd_strategy_upsert(con, tibble::tibble(strategy_id = "")),
    regexp = "strategy_id"
  )
})

test_that("hd_run_record returns a UUID-shaped string and inserts a row", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  hd_strategy_upsert(con, list(strategy_id = "cmr",
                              short_name = "MR", long_name = "MR"))

  uuid <- hd_run_record(con, strategy_id = "cmr", partition = "1m")
  expect_match(uuid, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

  got <- DBI::dbGetQuery(con, "SELECT * FROM bt.run")
  expect_equal(nrow(got), 1L)
  expect_equal(got$strategy_id, "cmr")
  expect_equal(got$partition, "1m")
  expect_equal(got$status, "success")
})

test_that("hd_run_record FK rejects orphan strategy_id", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  expect_error(
    hd_run_record(con, strategy_id = "no_such_strategy"),
    regexp = "Constraint|FOREIGN KEY|Violates|foreign|not present"
  )
})

test_that("HD_GIT_SHA env var populates git_sha column", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  hd_strategy_upsert(con, list(strategy_id = "cmr",
                              short_name = "MR", long_name = "MR"))

  withr::with_envvar(c(HD_GIT_SHA = "abc123def456"), {
    hd_run_record(con, strategy_id = "cmr")
  })

  sha <- DBI::dbGetQuery(con, "SELECT git_sha FROM bt.run LIMIT 1")$git_sha
  expect_equal(sha, "abc123def456")
})

test_that("two run_uuid values are distinct", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- .init_tmp_registry()
  withr::defer(unlink(tmp))
  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  hd_strategy_upsert(con, list(strategy_id = "cmr",
                              short_name = "MR", long_name = "MR"))

  u1 <- hd_run_record(con, strategy_id = "cmr", partition = "1m")
  u2 <- hd_run_record(con, strategy_id = "cmr", partition = "3m")
  expect_false(u1 == u2)
})
