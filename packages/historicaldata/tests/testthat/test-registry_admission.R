# Tests for registry_admission.R — strategy pre-registration (#496 Phase 1)
#
# Test structure:
#   1. init → register → read round-trip (basic)
#   2. expected_* fields round-trip correctly
#   3. git_commit / admission_uuid populated on insert
#   4. gate_result → gate_overall populated; gate_detail_json is valid JSON
#   5. idempotency: re-register same strategy → updates, uuid/admitted_at preserved
#   6. idempotency: new strategy appended; both rows present
#   7. hd_admission_read() returns empty tibble when table absent
#   8. override = TRUE requires override_reason
#   9. Table schema snapshot
#   10. Function signature snapshot (hd_admission_register)
#
# Snapshot count: 3 snapshots (schema + 2 sigs) + 1 error snapshot = 4 / 10 blocks
# => ratio 4/10 >= 30% — satisfies snapshot-test-policy

# ---- Helpers ---------------------------------------------------------------

# Open a fresh tempfile DuckDB for each test (avoid shared state)
.temp_con <- function() {
  tf  <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tf)
  withr::defer(
    suppressWarnings(DBI::dbDisconnect(con, shutdown = TRUE)),
    envir = parent.frame()
  )
  hd_admission_init(con)
  con
}

# Minimal gate_result fixture (as returned by hd_strategy_value_gate)
.make_gate_result <- function(overall = "admit") {
  verdict_levels <- c("pass", "fail", "flag", "na")
  gr <- tibble::tibble(
    check     = c("similarity", "incremental_sharpe", "diversification_ew",
                  "diversification_gmv", "crowding", "robustness"),
    metric    = rep("test_metric", 6L),
    value     = c(0.30, 0.05, 0.001, NA_real_, NA_real_, NA_real_),
    threshold = c(0.80, 0, 0, 0, NA_real_, NA_real_),
    verdict   = factor(c("pass","pass","pass","na","na","na"), levels = verdict_levels)
  )
  attr(gr, "overall") <- overall
  attr(gr, "candidate_name") <- "test_candidate"
  gr
}

# ---- Test 1: Basic init → register → read round-trip ----------------------
test_that("init + register + read round-trip works", {
  con <- .temp_con()

  uuid <- hd_admission_register(
    con        = con,
    strategy   = "test_strat_1",
    hypothesis = "Testing round-trip",
    expected   = list(incr_sharpe = 0.12, var_reduction = 0.003,
                      target_regime = "trending", max_corr = 0.40),
    reviewer   = "tester"
  )

  expect_type(uuid, "character")
  expect_true(nzchar(uuid))

  tbl <- hd_admission_read(con = con)
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 1L)
  expect_equal(tbl$strategy[[1]], "test_strat_1")
})

# ---- Test 2: expected_* fields round-trip ----------------------------------
test_that("expected_* fields are stored and retrieved correctly", {
  con <- .temp_con()

  hd_admission_register(
    con        = con,
    strategy   = "test_strat_2",
    hypothesis = "Testing expected fields",
    expected   = list(incr_sharpe = 0.08, var_reduction = 0.0015,
                      target_regime = "mean-reverting", max_corr = 0.60),
    reviewer   = "tester"
  )

  tbl <- hd_admission_read(con = con)
  row <- tbl[tbl$strategy == "test_strat_2", ]

  expect_equal(row$expected_incr_sharpe[[1]],   0.08,             tolerance = 1e-9)
  expect_equal(row$expected_var_reduction[[1]],  0.0015,           tolerance = 1e-9)
  expect_equal(row$expected_target_regime[[1]], "mean-reverting")
  expect_equal(row$expected_max_corr[[1]],       0.60,             tolerance = 1e-9)
})

# ---- Test 3: git_commit + admission_uuid populated -------------------------
test_that("git_commit and admission_uuid are populated on insert", {
  con <- .temp_con()

  hd_admission_register(
    con        = con,
    strategy   = "test_strat_3",
    hypothesis = "Testing uuid + git",
    expected   = list(),
    reviewer   = "tester"
  )

  tbl <- hd_admission_read(con = con)
  row <- tbl[tbl$strategy == "test_strat_3", ]

  # admission_uuid must be a non-empty UUID-like string
  expect_true(nzchar(row$admission_uuid[[1]]))
  # git_commit may be NA if git unavailable, but field must exist
  expect_true("git_commit" %in% names(row))
})

# ---- Test 4: gate_result → gate_overall + gate_detail_json -----------------
test_that("gate_result is serialised correctly", {
  skip_if_not_installed("jsonlite")
  con <- .temp_con()
  gr  <- .make_gate_result(overall = "admit")

  hd_admission_register(
    con         = con,
    strategy    = "test_strat_4",
    hypothesis  = "Testing gate serialisation",
    expected    = list(),
    reviewer    = "tester",
    gate_result = gr
  )

  tbl <- hd_admission_read(con = con)
  row <- tbl[tbl$strategy == "test_strat_4", ]

  expect_equal(row$gate_overall[[1]], "admit")
  expect_true(nzchar(row$gate_detail_json[[1]]))

  # gate_detail_json must be parseable JSON
  parsed <- jsonlite::fromJSON(row$gate_detail_json[[1]])
  expect_true(is.data.frame(parsed) || is.list(parsed))
})

# ---- Test 5: idempotency — re-register same strategy updates, preserves uuid
test_that("re-registering same strategy updates fields; preserves uuid + admitted_at", {
  con <- .temp_con()

  uuid1 <- hd_admission_register(
    con        = con,
    strategy   = "test_strat_5",
    hypothesis = "First registration",
    expected   = list(incr_sharpe = 0.05),
    reviewer   = "alice"
  )

  tbl1 <- hd_admission_read(con = con)
  at1  <- tbl1[tbl1$strategy == "test_strat_5", ]$admitted_at[[1]]

  # Re-register with updated hypothesis and expected values
  uuid2 <- hd_admission_register(
    con        = con,
    strategy   = "test_strat_5",
    hypothesis = "Revised registration",
    expected   = list(incr_sharpe = 0.10),
    reviewer   = "bob"
  )

  tbl2 <- hd_admission_read(con = con)
  row2 <- tbl2[tbl2$strategy == "test_strat_5", ]

  # Still only one row for this strategy
  expect_equal(nrow(tbl2), 1L)
  # UUID is preserved from first registration
  expect_equal(row2$admission_uuid[[1]], uuid1)
  expect_equal(uuid2, uuid1)
  # admitted_at is preserved
  expect_equal(row2$admitted_at[[1]], at1)
  # Updated fields are reflected
  expect_equal(row2$hypothesis[[1]], "Revised registration")
  expect_equal(row2$expected_incr_sharpe[[1]], 0.10, tolerance = 1e-9)
  expect_equal(row2$reviewer[[1]], "bob")
})

# ---- Test 6: Two strategies → both rows present ---------------------------
test_that("registering two distinct strategies appends two rows", {
  con <- .temp_con()

  hd_admission_register(
    con = con, strategy = "strat_a", hypothesis = "A",
    expected = list(), reviewer = "r1"
  )
  hd_admission_register(
    con = con, strategy = "strat_b", hypothesis = "B",
    expected = list(), reviewer = "r2"
  )

  tbl <- hd_admission_read(con = con)
  expect_equal(nrow(tbl), 2L)
  expect_setequal(tbl$strategy, c("strat_a", "strat_b"))
})

# ---- Test 7: hd_admission_read() when table absent -------------------------
test_that("hd_admission_read() returns empty tibble when db absent", {
  tf  <- tempfile(fileext = ".duckdb")
  # Don't initialise — file doesn't exist
  tbl <- hd_admission_read(path = tf)
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 0L)
  expect_true("strategy" %in% names(tbl))
})

# ---- Test 8: override = TRUE requires override_reason ---------------------
test_that("override = TRUE without reason triggers cli_abort", {
  con <- .temp_con()
  expect_snapshot(
    error = TRUE,
    hd_admission_register(
      con        = con,
      strategy   = "override_strat",
      hypothesis = "Testing override guard",
      expected   = list(),
      reviewer   = "tester",
      override   = TRUE
      # override_reason intentionally omitted
    )
  )
})

# ---- Test 9: Table schema snapshot -----------------------------------------
test_that("strategy_admission schema is stable", {
  con <- .temp_con()
  schema <- DBI::dbGetQuery(con, "
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_name = 'strategy_admission'
    ORDER BY ordinal_position
  ")
  expect_snapshot(schema)
})

# ---- Test 10: Function signature snapshots ---------------------------------
test_that("hd_admission_register() signature is stable", {
  expect_snapshot(args(hd_admission_register))
})

test_that("hd_admission_read() signature is stable", {
  expect_snapshot(args(hd_admission_read))
})
