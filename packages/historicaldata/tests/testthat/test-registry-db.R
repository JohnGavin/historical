# Tests for the backtest registry bootstrap helpers (#347 PR 1/4)

test_that("hd_registry_path returns a sensible default path", {
  withr::local_envvar(HD_REGISTRY_PATH = "")
  p <- hd_registry_path()
  expect_type(p, "character")
  expect_match(p, "registry\\.duckdb$")
})

test_that("HD_REGISTRY_PATH env var overrides default", {
  withr::local_envvar(HD_REGISTRY_PATH = "/tmp/override.duckdb")
  expect_equal(hd_registry_path(), "/tmp/override.duckdb")
})

test_that("hd_registry_init creates a DuckDB file with all bt and art tables", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(if (file.exists(tmp)) unlink(tmp))

  hd_registry_init(tmp)

  expect_true(file.exists(tmp))

  con <- hd_registry_open(tmp, read_only = TRUE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  schemas <- DBI::dbGetQuery(
    con,
    "SELECT schema_name FROM information_schema.schemata
     WHERE schema_name IN ('bt', 'art') ORDER BY schema_name"
  )
  expect_setequal(schemas$schema_name, c("art", "bt"))

  bt_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'bt' ORDER BY table_name"
  )
  expect_setequal(
    bt_tables$table_name,
    c("cost_model", "diagnostic", "metric", "output",
      "params", "run", "strategy", "universe")
  )

  art_tables <- DBI::dbGetQuery(
    con,
    "SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'art' ORDER BY table_name"
  )
  expect_setequal(
    art_tables$table_name,
    c("dependency", "deploy", "diagram", "vignette")
  )

  # schema_version row inserted by the bootstrap
  sv <- DBI::dbGetQuery(con, "SELECT version FROM schema_version")
  expect_equal(sv$version, "1.0.0")
})

test_that("hd_registry_init is idempotent (second call is a no-op)", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(if (file.exists(tmp)) unlink(tmp))

  hd_registry_init(tmp)
  expect_no_error(hd_registry_init(tmp))

  # Still exactly one schema_version row after re-init
  con <- hd_registry_open(tmp, read_only = TRUE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) AS n FROM schema_version")$n
  expect_equal(n, 1L)
})

test_that("hd_registry_schema_version returns the current version", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(if (file.exists(tmp)) unlink(tmp))

  # Before init: NA
  expect_true(is.na(hd_registry_schema_version(tmp)))

  hd_registry_init(tmp)
  expect_equal(hd_registry_schema_version(tmp), "1.0.0")
})

test_that("hd_registry_open errors if the file does not exist", {
  tmp <- tempfile(fileext = ".duckdb")
  expect_error(
    hd_registry_open(tmp),
    regexp = "Registry file not found"
  )
})

test_that("foreign keys on bt.run reject orphan strategy_id", {
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")

  tmp <- tempfile(fileext = ".duckdb")
  withr::defer(if (file.exists(tmp)) unlink(tmp))
  hd_registry_init(tmp)

  con <- hd_registry_open(tmp, read_only = FALSE)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

  expect_error(
    DBI::dbExecute(
      con,
      "INSERT INTO bt.run (run_uuid, strategy_id)
       VALUES ('test-uuid', 'nonexistent_strategy')"
    ),
    regexp = "Constraint|FOREIGN KEY|Violates|foreign|not present"
  )
})
