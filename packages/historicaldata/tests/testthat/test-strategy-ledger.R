# Tests for the strategy ledger on top of the research log (Refs #962):
# hd_strategy_idea_priorities(), hd_strategy_idea_append(),
# hd_strategy_ledger(), hd_strategy_ledger_register(), hd_strategy_trial_count()
#
# Every test uses a temp base_dir; the real research log is never touched.

testthat::local_edition(3)

.sl_tmp_dir <- function() {
  tf <- tempfile("rlog-ledger-")
  dir.create(tf)
  tf
}

# Append a plain (non-idea) hypothesis row with an explicit timestamp.
.sl_hyp <- function(base_dir, claim, predictor, status, ts,
                    parent_uuid = NA_character_, uuid = NA_character_) {
  suppressMessages(hd_rlog_append(
    "hypotheses",
    tibble::tibble(
      uuid           = uuid,
      parent_uuid    = parent_uuid,
      timestamp      = as.POSIXct(ts, tz = "UTC"),
      economic_claim = claim,
      predictor      = predictor,
      status         = status
    ),
    base_dir = base_dir
  ))
}

.sl_idea <- function(base_dir, name = "idea_a", ...) {
  args <- list(
    name = name, economic_claim = paste("claim of", name),
    source = "https://example.org/x", priority = "low",
    asset_class = "equity", base_dir = base_dir
  )
  args[names(list(...))] <- list(...)
  suppressMessages(do.call(hd_strategy_idea_append, args))
}

# ---- 1. Vocabulary ---------------------------------------------------------
test_that("hd_strategy_idea_priorities is the single priority vocabulary", {
  expect_snapshot(print(hd_strategy_idea_priorities()))
})

# ---- 2. Writer round-trip --------------------------------------------------
test_that("idea writer round-trips as an unsealed strategy_idea hypothesis row", {
  d <- .sl_tmp_dir()
  uuid <- .sl_idea(d, name = "spy_tlt", issue = 962, strategy_id = "S1",
                   priority = "queued")
  rows <- suppressWarnings(hd_rlog_query("hypotheses", base_dir = d))
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$uuid, uuid)
  expect_equal(rows$status, "proposed")
  expect_equal(rows$predictor, "spy_tlt")
  # never sealed
  expect_true(is.na(rows$commit_hash))
  expect_true(is.na(rows$sealed_at))
  expect_true(is.na(rows$seal_method))
  ex <- jsonlite::fromJSON(rows$extra_json)
  expect_equal(ex$kind, "strategy_idea")
  expect_false(ex$preregistered)
  expect_equal(
    ex$seal_omitted_reason,
    "backlog idea; pre-registration happens at admission (hd_admission_preregister)"
  )
  expect_equal(ex$priority, "queued")
  expect_equal(ex$issue, 962L)
  expect_equal(ex$strategy_id, "S1")
  expect_equal(ex$source, "https://example.org/x")
})

# ---- 3. Abort paths (snapshots) -------------------------------------------
test_that("missing source aborts", {
  expect_snapshot(error = TRUE, hd_strategy_idea_append(
    name = "a", economic_claim = "c", priority = "low",
    asset_class = "equity", base_dir = .sl_tmp_dir()
  ))
})

test_that("unknown priority aborts naming value and allowed set", {
  expect_snapshot(error = TRUE, hd_strategy_idea_append(
    name = "a", economic_claim = "c", source = "s", priority = "urgent",
    asset_class = "equity", base_dir = .sl_tmp_dir()
  ))
})

test_that("unknown status aborts naming value and allowed set", {
  expect_snapshot(error = TRUE, hd_strategy_idea_append(
    name = "a", economic_claim = "c", source = "s", priority = "low",
    asset_class = "equity", status = "maybe", base_dir = .sl_tmp_dir()
  ))
})

test_that("deprecated status 'tested' is refused", {
  expect_snapshot(error = TRUE, hd_strategy_idea_append(
    name = "a", economic_claim = "c", source = "s", priority = "low",
    asset_class = "equity", status = "tested", base_dir = .sl_tmp_dir()
  ))
})

test_that("empty name aborts", {
  expect_snapshot(error = TRUE, hd_strategy_idea_append(
    name = "", economic_claim = "c", source = "s", priority = "low",
    asset_class = "equity", base_dir = .sl_tmp_dir()
  ))
})

test_that("a refused call writes nothing", {
  d <- .sl_tmp_dir()
  expect_error(hd_strategy_idea_append(
    name = "a", economic_claim = "c", source = "s", priority = "urgent",
    asset_class = "equity", base_dir = d
  ))
  expect_length(list.files(d, recursive = TRUE), 0L)
})

# ---- 4. Ledger grouping ----------------------------------------------------
test_that("3 rows with identical claim+predictor are ONE entry, n_attempts 3", {
  d <- .sl_tmp_dir()
  for (i in 1:3) {
    .sl_hyp(d, "same claim", "OLMAR-1", "inconclusive-underpowered",
            sprintf("2026-01-0%d", i))
  }
  led <- hd_strategy_ledger(base_dir = d)
  expect_equal(nrow(led), 1L)
  expect_equal(led$n_attempts, 3L)
  expect_equal(led$kind, "hypothesis")
  expect_true(is.na(led$priority))
  # grouping is not an edit: all three rows are still in the log
  expect_equal(nrow(hd_rlog_query("hypotheses", base_dir = d)), 3L)
})

test_that("latest status is the newest row; a change is a NEW linked row", {
  d <- .sl_tmp_dir()
  .sl_hyp(d, "c1", "p1", "proposed", "2026-01-01", uuid = "u-1")
  .sl_hyp(d, "c1", "p1", "testing", "2026-02-01", uuid = "u-2",
          parent_uuid = "u-1")
  .sl_hyp(d, "c1", "p1", "refuted", "2026-03-01", parent_uuid = "u-2")
  led <- hd_strategy_ledger(base_dir = d)
  expect_equal(nrow(led), 1L)
  expect_equal(led$latest_status, "refuted")
  expect_equal(led$stage, "refuted")
  expect_equal(led$n_attempts, 3L)
  expect_equal(led$last_updated, as.POSIXct("2026-03-01", tz = "UTC"))
})

test_that("kind separates ideas from other hypotheses (kind filter)", {
  d <- .sl_tmp_dir()
  .sl_idea(d, name = "an_idea")
  .sl_hyp(d, "plain claim", "plain_pred", "supported", "2026-01-01")
  led <- hd_strategy_ledger(base_dir = d)
  expect_equal(nrow(led), 2L)
  expect_equal(led$kind[led$name == "an_idea"], "idea")
  expect_equal(led$priority[led$name == "an_idea"], "low")
  expect_equal(led$kind[led$name == "plain_pred"], "hypothesis")
  expect_true(is.na(led$priority[led$name == "plain_pred"]))
})

test_that("an out-of-vocabulary status already in the log aborts the ledger", {
  d <- .sl_tmp_dir()
  # Bypass hd_rlog_append() validation to simulate a hand-written file.
  dir.create(file.path(d, "hypotheses"))
  bad <- hd_rlog_schema("hypotheses")[0, ]
  bad[1, "uuid"] <- "bad-1"
  bad[1, "economic_claim"] <- "c"
  bad[1, "status"] <- "maybe"
  arrow::write_parquet(bad, file.path(d, "hypotheses", "bad.parquet"))
  expect_snapshot(error = TRUE, hd_strategy_ledger(base_dir = d))
})

test_that("empty log returns a zero-row ledger with the full column set", {
  led <- hd_strategy_ledger(base_dir = .sl_tmp_dir())
  expect_equal(nrow(led), 0L)
  expect_snapshot(names(led))
})

# ---- 5. Optional registry --------------------------------------------------
test_that("registry path NULL: research-log part only, reported not silent", {
  d <- .sl_tmp_dir()
  .sl_idea(d)
  expect_snapshot(led <- hd_strategy_ledger(base_dir = d))
  expect_equal(nrow(led), 1L)
})

test_that("a registry without the research schema still works", {
  d <- .sl_tmp_dir()
  .sl_idea(d, name = "linked", strategy_id = "LIVE1")
  reg <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = reg)
  DBI::dbExecute(con, "CREATE SCHEMA bt")
  DBI::dbExecute(con, "CREATE TABLE bt.strategy (strategy_id VARCHAR,
    short_name VARCHAR, lifecycle VARCHAR, created_at TIMESTAMP)")
  DBI::dbExecute(con, "INSERT INTO bt.strategy VALUES
    ('LIVE1','live_one','stable','2026-01-01'),
    ('OLD1','old_one','deprecated','2026-01-01')")
  DBI::dbDisconnect(con, shutdown = TRUE)
  has_research <- {
    ro <- DBI::dbConnect(duckdb::duckdb(), dbdir = reg, read_only = TRUE)
    on.exit(DBI::dbDisconnect(ro, shutdown = TRUE), add = TRUE)
    DBI::dbGetQuery(ro, "SELECT count(*) n FROM information_schema.schemata
                         WHERE schema_name = 'research'")$n
  }
  expect_equal(has_research, 0L)

  led <- hd_strategy_ledger(base_dir = d, registry_path = reg)
  expect_setequal(led$kind, c("idea", "live_strategy"))
  live <- led[led$kind == "live_strategy", ]
  expect_equal(nrow(live), 1L)          # 'deprecated' lifecycle excluded
  expect_equal(live$stage, "live")
  expect_equal(live$n_attempts, 1L)     # the linked idea row
})

test_that("absent registry file and registry without bt.strategy are reported", {
  d <- .sl_tmp_dir()
  .sl_idea(d)
  expect_message(
    led <- hd_strategy_ledger(base_dir = d,
                              registry_path = file.path(d, "nope.duckdb")),
    "Registry file not found"
  )
  expect_equal(nrow(led), 1L)

  reg <- tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = reg)
  DBI::dbDisconnect(con, shutdown = TRUE)
  expect_message(
    led2 <- hd_strategy_ledger(base_dir = d, registry_path = reg),
    "no .*bt.strategy"
  )
  expect_equal(nrow(led2), 1L)
})

# ---- 6. DuckDB view agrees with the R reader -------------------------------
test_that("research.strategy_ledger view matches hd_strategy_ledger()", {
  d <- .sl_tmp_dir()
  .sl_idea(d, name = "linked", strategy_id = "LIVE1", issue = 962)
  for (i in 1:2) .sl_hyp(d, "same", "OLMAR-1", "testing", sprintf("2026-01-0%d", i))
  .sl_hyp(d, "same", "OLMAR-1", "refuted", "2026-01-09")
  reg <- tempfile(fileext = ".duckdb")
  hd_registry_init(reg)
  con <- hd_registry_open(reg, read_only = FALSE)
  DBI::dbExecute(con, "INSERT INTO bt.strategy (strategy_id, short_name,
    long_name, lifecycle) VALUES ('LIVE1','live_one','Live One','stable')")
  hd_strategy_ledger_register(con, base_dir = d)
  v <- tibble::as_tibble(DBI::dbGetQuery(
    con, "SELECT * FROM research.strategy_ledger ORDER BY ledger_id"
  ))
  DBI::dbDisconnect(con, shutdown = TRUE)

  r <- hd_strategy_ledger(base_dir = d, registry_path = reg)
  r <- r[order(r$ledger_id), ]
  expect_equal(v$ledger_id, r$ledger_id)
  expect_equal(v$name, r$name)
  expect_equal(v$kind, r$kind)
  expect_equal(v$stage, r$stage)
  expect_equal(v$latest_status, r$latest_status)
  expect_equal(v$n_attempts, r$n_attempts)
  expect_equal(v$priority, r$priority)
  expect_equal(v$issue, r$issue)
  expect_equal(v$strategy_id, r$strategy_id)
  expect_equal(v$source, r$source)
})

test_that("schema.sql creates the research schema; registering with no log aborts", {
  reg <- tempfile(fileext = ".duckdb")
  hd_registry_init(reg)
  con <- hd_registry_open(reg, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  n <- DBI::dbGetQuery(con, "SELECT count(*) n FROM information_schema.schemata
                             WHERE schema_name = 'research'")$n
  expect_equal(n, 1L)
  d <- .sl_tmp_dir()
  expect_error(hd_strategy_ledger_register(con, base_dir = d),
               "No hypotheses parquet files")
})

# ---- 7. Trial count --------------------------------------------------------
test_that("trial count includes rejected attempts and excludes proposed/withdrawn", {
  d <- .sl_tmp_dir()
  .sl_hyp(d, "c-ref", "p-ref", "refuted", "2026-01-01")
  .sl_hyp(d, "c-sup", "p-sup", "supported", "2026-01-01")
  .sl_hyp(d, "c-inc", "p-inc", "inconclusive-underpowered", "2026-01-01")
  .sl_hyp(d, "c-unm", "p-unm", "inconclusive-unmeasurable", "2026-01-01")
  .sl_hyp(d, "c-tst", "p-tst", "testing", "2026-01-01")
  .sl_hyp(d, "c-prop", "p-prop", "proposed", "2026-01-01")
  .sl_hyp(d, "c-wd", "p-wd", "withdrawn", "2026-01-01")
  .sl_idea(d, name = "parked")                   # proposed idea: not a trial
  expect_equal(hd_strategy_trial_count(base_dir = d), 5L)
})

test_that("trial count uses the LATEST status and counts a group once", {
  d <- .sl_tmp_dir()
  .sl_hyp(d, "c", "p", "proposed", "2026-01-01")
  .sl_hyp(d, "c", "p", "refuted", "2026-02-01")
  .sl_hyp(d, "c", "p", "refuted", "2026-03-01")
  expect_equal(hd_strategy_trial_count(base_dir = d), 1L)
})

test_that("legacy 'tested' entries are not counted but are reported", {
  d <- .sl_tmp_dir()
  expect_warning(.sl_hyp(d, "c", "OLMAR-1", "tested", "2026-01-01"),
                 "deprecated")
  expect_snapshot(n <- hd_strategy_trial_count(base_dir = d))
  expect_equal(n, 0L)
})

test_that("function signatures are stable", {
  expect_snapshot(args(hd_strategy_idea_append))
  expect_snapshot(args(hd_strategy_ledger))
  expect_snapshot(args(hd_strategy_ledger_register))
  expect_snapshot(args(hd_strategy_trial_count))
})
