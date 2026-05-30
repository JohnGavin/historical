# Tests for hd_metric_record + hd_diagnostic_record +
# hd_leaderboard_from_registry (#347 PR 3/4)

.setup_registry_with_run <- function() {
  tmp <- tempfile(fileext = ".duckdb")
  hd_registry_init(tmp)
  con <- hd_registry_open(tmp, read_only = FALSE)
  hd_strategy_upsert(con, list(strategy_id = "cmr",
                              short_name = "MR", long_name = "MR",
                              asset_class = "commodities"))
  uuid <- hd_run_record(con, strategy_id = "cmr", partition = "1m")
  list(tmp = tmp, con = con, uuid = uuid)
}

test_that("hd_metric_record writes wide-form metrics as long rows", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  n <- hd_metric_record(
    s$con, s$uuid,
    tibble::tibble(
      n_months = 120L,
      sharpe   = 0.85,
      cagr     = 0.07,
      max_dd   = -0.15
    )
  )
  expect_equal(n, 4L)

  rows <- DBI::dbGetQuery(
    s$con,
    "SELECT metric_name, metric_value FROM bt.metric WHERE run_uuid = ?
     ORDER BY metric_name", params = list(s$uuid)
  )
  expect_setequal(rows$metric_name, c("cagr", "max_dd", "n_months", "sharpe"))
  expect_equal(
    rows$metric_value[rows$metric_name == "sharpe"],
    0.85
  )
})

test_that("hd_metric_record accepts long-form metrics directly", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  long <- tibble::tibble(
    metric_name  = c("sharpe", "max_dd"),
    metric_value = c(1.2, -0.1),
    metric_unit  = c("ratio", "pct")
  )
  n <- hd_metric_record(s$con, s$uuid, long)
  expect_equal(n, 2L)

  rows <- DBI::dbGetQuery(s$con,
    "SELECT metric_name, metric_unit FROM bt.metric WHERE run_uuid = ?
     ORDER BY metric_name", params = list(s$uuid)
  )
  expect_equal(rows$metric_unit[rows$metric_name == "max_dd"], "pct")
})

test_that("hd_metric_record is idempotent (re-record overwrites)", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  hd_metric_record(s$con, s$uuid, tibble::tibble(sharpe = 0.5))
  hd_metric_record(s$con, s$uuid, tibble::tibble(sharpe = 0.9))

  v <- DBI::dbGetQuery(s$con,
    "SELECT metric_value FROM bt.metric WHERE run_uuid = ?
       AND metric_name = 'sharpe'", params = list(s$uuid))$metric_value
  expect_equal(length(v), 1L)
  expect_equal(v, 0.9)
})

test_that("hd_metric_record rejects NA / NULL run_uuid", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  expect_error(hd_metric_record(s$con, NA_character_,
                                tibble::tibble(sharpe = 1)),
               regexp = "run_uuid")
})

test_that("hd_diagnostic_record writes wide-form numeric diagnostics", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  n <- hd_diagnostic_record(
    s$con, s$uuid,
    tibble::tibble(deflated_sharpe = 0.6, pbo = 0.12, k_eff_strat = 4.2)
  )
  expect_equal(n, 3L)

  rows <- DBI::dbGetQuery(s$con,
    "SELECT diagnostic_name, value_num FROM bt.diagnostic
     WHERE run_uuid = ? ORDER BY diagnostic_name", params = list(s$uuid))
  expect_setequal(rows$diagnostic_name,
                  c("deflated_sharpe", "k_eff_strat", "pbo"))
})

test_that("hd_leaderboard_from_registry returns latest-per-partition sharpe", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  hd_metric_record(s$con, s$uuid,
                   tibble::tibble(sharpe = 0.7, max_dd = -0.1))

  # Second strategy + run with a different sharpe
  hd_strategy_upsert(s$con, list(strategy_id = "ltr",
                                short_name = "LTR", long_name = "LTR",
                                asset_class = "equity"))
  u2 <- hd_run_record(s$con, strategy_id = "ltr", partition = NA_character_)
  hd_metric_record(s$con, u2, tibble::tibble(sharpe = 1.3))

  lb <- hd_leaderboard_from_registry(s$con, metric_name = "sharpe")
  expect_setequal(lb$strategy_id, c("cmr", "ltr"))
  expect_equal(lb$value[lb$strategy_id == "ltr"], 1.3)
  expect_equal(lb$value[lb$strategy_id == "cmr"], 0.7)
  expect_true(all(lb$metric_name == "sharpe"))
})

test_that("hd_leaderboard_from_registry filters by metric_name", {
  skip_if_not_installed("DBI"); skip_if_not_installed("duckdb")
  s <- .setup_registry_with_run()
  withr::defer({ DBI::dbDisconnect(s$con, shutdown = TRUE); unlink(s$tmp) })

  hd_metric_record(s$con, s$uuid,
                   tibble::tibble(sharpe = 0.5, max_dd = -0.2))
  lb_sh <- hd_leaderboard_from_registry(s$con, metric_name = "sharpe")
  lb_dd <- hd_leaderboard_from_registry(s$con, metric_name = "max_dd")
  expect_equal(lb_sh$value, 0.5)
  expect_equal(lb_dd$value, -0.2)
})
