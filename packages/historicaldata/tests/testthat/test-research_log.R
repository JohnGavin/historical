test_that("hd_rlog_tables() returns the 5 expected table names", {
  tbls <- hd_rlog_tables()
  expect_type(tbls, "character")
  expect_length(tbls, 5L)
  expect_setequal(
    tbls,
    c("hypotheses", "implementations", "results", "critiques", "robustness")
  )
})

# ── Schema: column types and lineage-first ordering ─────────────────────────

test_that("hd_rlog_schema() puts lineage cols first for hypotheses", {
  s <- hd_rlog_schema("hypotheses")
  expect_s3_class(s, "tbl_df")
  expect_equal(nrow(s), 0L)
  lineage_cols <- c("uuid", "parent_uuid", "timestamp", "git_commit",
                    "sandbox_image_hash")
  expect_equal(names(s)[seq_along(lineage_cols)], lineage_cols)
})

test_that("hd_rlog_schema() column types are correct for hypotheses", {
  s <- hd_rlog_schema("hypotheses")
  expect_type(s$uuid,               "character")
  expect_type(s$parent_uuid,        "character")
  expect_s3_class(s$timestamp,      "POSIXct")
  expect_type(s$git_commit,         "character")
  expect_type(s$sandbox_image_hash, "character")
  expect_type(s$economic_claim,     "character")
  expect_type(s$status,             "character")
})

test_that("hd_rlog_schema() puts lineage cols first for all 5 tables", {
  lineage_cols <- c("uuid", "parent_uuid", "timestamp", "git_commit",
                    "sandbox_image_hash")
  for (tbl in hd_rlog_tables()) {
    s <- hd_rlog_schema(tbl)
    expect_equal(names(s)[seq_along(lineage_cols)], lineage_cols,
                 label = paste0("lineage cols first in ", tbl))
  }
})

test_that("hd_rlog_schema() types correct for implementations", {
  s <- hd_rlog_schema("implementations")
  expect_type(s$code_ref,      "character")
  expect_type(s$notebook_path, "character")
  expect_type(s$params_json,   "character")
})

test_that("hd_rlog_schema() types correct for results", {
  s <- hd_rlog_schema("results")
  expect_type(s$cagr,       "double")
  expect_type(s$sharpe_hac, "double")
  expect_type(s$n_obs,      "integer")
  expect_s3_class(s$results_db_run_date, "Date")
})

test_that("hd_rlog_schema() types correct for critiques", {
  s <- hd_rlog_schema("critiques")
  expect_type(s$defect_class, "character")
  expect_type(s$resolved,     "logical")
})

test_that("hd_rlog_schema() types correct for robustness", {
  s <- hd_rlog_schema("robustness")
  expect_type(s$metric_value, "double")
  expect_type(s$passed,       "logical")
})

test_that("hd_rlog_schema() aborts on unknown table", {
  expect_error(
    hd_rlog_schema("bogus"),
    regexp = "Unknown research-log table"
  )
})

# ── UUID-v4 generator ───────────────────────────────────────────────────────

test_that("hd_rlog_uuid() produces valid UUID-v4", {
  uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  for (i in seq_len(20L)) {
    u <- historicaldata:::hd_rlog_uuid()
    expect_match(u, uuid_re, label = paste0("uuid ", i))
  }
})

test_that("hd_rlog_uuid() generates distinct values", {
  uuids <- replicate(100L, historicaldata:::hd_rlog_uuid())
  expect_equal(length(unique(uuids)), 100L)
})

# ── Append → query round-trip ────────────────────────────────────────────────

test_that("append + query round-trips a hypotheses row", {
  skip_if_not_installed("arrow")

  tmp <- tempfile("rlog-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  row <- tibble::tibble(
    economic_claim  = "Value premium persists OOS",
    dependent_var   = "monthly_return",
    predictor       = "book_to_market",
    sample_spec     = "US equities 1963-2023",
    null_hypothesis = "No premium net of costs",
    status          = "active",
    extra_json      = NA_character_
  )

  hd_rlog_append("hypotheses", row, base_dir = tmp)

  result <- hd_rlog_query("hypotheses", base_dir = tmp)
  expect_equal(nrow(result), 1L)
  expect_equal(result$economic_claim, "Value premium persists OOS")
})

test_that("append auto-fills uuid and timestamp", {
  skip_if_not_installed("arrow")

  tmp <- tempfile("rlog-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  row <- tibble::tibble(
    economic_claim  = "Test",
    dependent_var   = "ret",
    predictor       = "x",
    sample_spec     = "all",
    null_hypothesis = "none",
    status          = "draft",
    extra_json      = NA_character_
  )

  hd_rlog_append("hypotheses", row, base_dir = tmp)
  result <- hd_rlog_query("hypotheses", base_dir = tmp)

  expect_false(is.na(result$uuid[1L]))
  expect_false(result$uuid[1L] == "")
  expect_false(is.na(result$timestamp[1L]))

  uuid_re <- "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
  expect_match(result$uuid[1L], uuid_re)
})

# ── 3-deep lineage ───────────────────────────────────────────────────────────

test_that("hd_rlog_lineage() returns 3-deep ancestry in order", {
  skip_if_not_installed("arrow")

  tmp <- tempfile("rlog-lineage-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Append a hypothesis
  hyp_row <- tibble::tibble(
    economic_claim  = "Value premium",
    dependent_var   = "ret",
    predictor       = "bm",
    sample_spec     = "US 1963-2023",
    null_hypothesis = "none",
    status          = "active",
    extra_json      = NA_character_
  )
  hd_rlog_append("hypotheses", hyp_row, base_dir = tmp)
  hyp_uuid <- hd_rlog_query("hypotheses", base_dir = tmp)$uuid[1L]

  # Append an implementation linked to hypothesis
  impl_row <- tibble::tibble(
    parent_uuid   = hyp_uuid,
    code_ref      = "R/strat_value.R",
    notebook_path = NA_character_,
    params_json   = '{"lookback":12}',
    extra_json    = NA_character_
  )
  hd_rlog_append("implementations", impl_row, base_dir = tmp)
  impl_uuid <- hd_rlog_query("implementations", base_dir = tmp)$uuid[1L]

  # Append a result linked to implementation
  res_row <- tibble::tibble(
    parent_uuid         = impl_uuid,
    strategy_id         = "value_bm",
    partition           = "OOS_2010_2023",
    cagr                = 0.08,
    sharpe_hac          = 0.65,
    max_dd              = -0.32,
    turnover_annual     = 1.2,
    n_obs               = 156L,
    results_db_run_date = as.Date(NA),
    extra_json          = NA_character_
  )
  hd_rlog_append("results", res_row, base_dir = tmp)
  res_uuid <- hd_rlog_query("results", base_dir = tmp)$uuid[1L]

  # Walk lineage from result uuid
  lin <- hd_rlog_lineage(res_uuid, base_dir = tmp)

  # Should have 3 rows: result -> implementation -> hypothesis
  expect_equal(nrow(lin), 3L)
  expect_equal(lin$table[1L], "results")
  expect_equal(lin$table[2L], "implementations")
  expect_equal(lin$table[3L], "hypotheses")
  expect_equal(lin$uuid[1L], res_uuid)
  expect_equal(lin$uuid[2L], impl_uuid)
  expect_equal(lin$uuid[3L], hyp_uuid)
})

# ── DuckDB connect ───────────────────────────────────────────────────────────

test_that("hd_rlog_connect() returns a working connection and view matches appended count", {
  skip_if_not_installed("arrow")

  tmp <- tempfile("rlog-connect-")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Append 2 hypothesis rows
  rows <- tibble::tibble(
    economic_claim  = c("Claim A", "Claim B"),
    dependent_var   = c("ret", "vol"),
    predictor       = c("bm", "me"),
    sample_spec     = c("US", "INT"),
    null_hypothesis = c("none", "none"),
    status          = c("active", "draft"),
    extra_json      = c(NA_character_, NA_character_)
  )
  hd_rlog_append("hypotheses", rows, base_dir = tmp)

  con <- hd_rlog_connect(base_dir = tmp)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  count_result <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM hypotheses")
  expect_equal(count_result$n, 2L)
})
