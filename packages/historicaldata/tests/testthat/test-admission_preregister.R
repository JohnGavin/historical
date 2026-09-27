# Tests for hd_admission_preregister() / hd_admission_read() -- strategy
# admission pre-registration via the research log (#496, supersedes PR #511's
# bespoke `strategy_admission` table)
#
# Test structure:
#   1. Basic preregister + read round-trip
#   2. expected_* fields round-trip
#   3. counterparty / kill_criterion fields round-trip (#902)
#   4. Detection-power fields computed and round-tripped when expected_sharpe given
#   5. Detection-power fields absent when expected_sharpe not supplied
#   6. gate_result attached -> gate_overall + gate_detail populated
#   7. A sealed claim CANNOT be silently overwritten (aborts without revises=TRUE)
#   8. revises = TRUE creates a NEW row linked via parent_uuid; old row untouched
#   9. Unsealed (seal = FALSE) drafts can be re-registered without revises
#   10. hd_admission_read() ignores non-admission hypotheses rows
#   11. hd_admission_read() returns empty tibble when store is empty
#   12. Input-validation snapshot: empty strategy
#   13. Input-validation snapshot: empty hypothesis
#   14. Input-validation snapshot: missing reviewer
#   15. Function signature snapshot: hd_admission_preregister
#   16. Function signature snapshot: hd_admission_read
#
# Snapshot count: 5 snapshots (3 validation errors + 2 signatures) / 16 blocks
# => ratio ~31% -- satisfies snapshot-test-policy for 9+ blocks

# ---- Helpers ----------------------------------------------------------------

.temp_rlog_dir <- function() {
  tf <- tempfile("rlog-admission-")
  dir.create(tf)
  tf
}

# ---- Test 1: Basic preregister + read round-trip ---------------------------
test_that("preregister + read round-trip works", {
  base_dir <- .temp_rlog_dir()

  uuid <- hd_admission_preregister(
    strategy   = "test_strat_1",
    hypothesis = "Testing round-trip",
    reviewer   = "tester",
    base_dir   = base_dir
  )

  expect_type(uuid, "character")
  expect_true(nzchar(uuid))

  tbl <- hd_admission_read(base_dir = base_dir)
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 1L)
  expect_equal(tbl$strategy[[1]], "test_strat_1")
  expect_equal(tbl$hypothesis[[1]], "Testing round-trip")
  expect_equal(tbl$status[[1]], "proposed")
  expect_true(nzchar(tbl$commit_hash[[1]]))   # sealed by default
})

# ---- Test 2: expected_* fields round-trip ----------------------------------
test_that("expected_* fields are stored and retrieved correctly", {
  base_dir <- .temp_rlog_dir()

  hd_admission_preregister(
    strategy   = "test_strat_2",
    hypothesis = "Testing expected fields",
    expected   = list(incr_sharpe = 0.08, var_reduction = 0.0015,
                      target_regime = "mean-reverting", max_corr = 0.60),
    reviewer   = "tester",
    base_dir   = base_dir
  )

  tbl <- hd_admission_read(strategy = "test_strat_2", base_dir = base_dir)
  expect_equal(nrow(tbl), 1L)
  expect_equal(tbl$expected_incr_sharpe[[1]],   0.08,             tolerance = 1e-9)
  expect_equal(tbl$expected_var_reduction[[1]], 0.0015,           tolerance = 1e-9)
  expect_equal(tbl$expected_target_regime[[1]], "mean-reverting")
  expect_equal(tbl$expected_max_corr[[1]],      0.60,             tolerance = 1e-9)
})

# ---- Test 3: counterparty / kill_criterion round-trip (#902) ---------------
test_that("counterparty and kill_criterion (#902) round-trip correctly", {
  base_dir <- .temp_rlog_dir()

  hd_admission_preregister(
    strategy       = "test_strat_3",
    hypothesis     = "Testing #902 fields",
    reviewer       = "tester",
    counterparty   = "EM local funds forced to de-risk into drawdowns",
    kill_criterion = "trailing 36-month incremental Sharpe <= 0",
    base_dir       = base_dir
  )

  tbl <- hd_admission_read(strategy = "test_strat_3", base_dir = base_dir)
  expect_equal(tbl$counterparty[[1]],
               "EM local funds forced to de-risk into drawdowns")
  expect_equal(tbl$kill_criterion[[1]],
               "trailing 36-month incremental Sharpe <= 0")
})

# ---- Test 4: detection-power fields computed when expected_sharpe given ---
test_that("expected_sharpe triggers a detection-power computation that round-trips", {
  base_dir <- .temp_rlog_dir()

  hd_admission_preregister(
    strategy        = "test_strat_4",
    hypothesis      = "Testing detection power",
    reviewer        = "tester",
    expected_sharpe = 0.6,
    ann_factor      = 12,
    base_dir        = base_dir
  )

  tbl <- hd_admission_read(strategy = "test_strat_4", base_dir = base_dir)
  expect_equal(tbl$expected_sharpe[[1]], 0.6, tolerance = 1e-9)
  expect_gt(tbl$min_n_years[[1]], 0)
  expect_gte(tbl$min_n_years_corrected[[1]], tbl$min_n_years[[1]])
})

# ---- Test 5: detection-power fields absent without expected_sharpe --------
test_that("no expected_sharpe means no detection-power fields (NA, not 0)", {
  base_dir <- .temp_rlog_dir()

  hd_admission_preregister(
    strategy   = "test_strat_5",
    hypothesis = "No expected Sharpe supplied",
    reviewer   = "tester",
    base_dir   = base_dir
  )

  tbl <- hd_admission_read(strategy = "test_strat_5", base_dir = base_dir)
  expect_true(is.na(tbl$expected_sharpe[[1]]))
  expect_true(is.na(tbl$min_n_years[[1]]))
  expect_true(is.na(tbl$min_n_years_corrected[[1]]))
})

# ---- Test 6: gate_result attached ------------------------------------------
test_that("a supplied gate_result populates gate_overall", {
  base_dir <- .temp_rlog_dir()

  existing  <- matrix(rnorm(240, mean = 0.006, sd = 0.035), ncol = 1L,
                       dimnames = list(NULL, "strat_a"))
  candidate <- -0.3 * (existing[, 1] - mean(existing[, 1])) + 0.012 +
    rnorm(nrow(existing), sd = 0.03)
  gate_result <- hd_strategy_value_gate(candidate, existing, periods_per_year = 12L)

  hd_admission_preregister(
    strategy    = "test_strat_6",
    hypothesis  = "Testing gate_result attachment",
    reviewer    = "tester",
    gate_result = gate_result,
    base_dir    = base_dir
  )

  tbl <- hd_admission_read(strategy = "test_strat_6", base_dir = base_dir)
  expect_equal(tbl$gate_overall[[1]], attr(gate_result, "overall"))
})

# ---- Test 7: a sealed claim cannot be silently overwritten -----------------
test_that("re-registering a sealed strategy without revises = TRUE aborts", {
  base_dir <- .temp_rlog_dir()

  hd_admission_preregister(
    strategy   = "test_strat_7",
    hypothesis = "Original claim",
    reviewer   = "tester",
    base_dir   = base_dir
  )

  expect_error(
    hd_admission_preregister(
      strategy   = "test_strat_7",
      hypothesis = "Reworded claim after seeing the outcome",
      reviewer   = "tester",
      base_dir   = base_dir
    ),
    regexp = "sealed admission hypothesis already exists"
  )

  # The original row must be untouched (append-only; no UPDATE path exists).
  tbl <- hd_admission_read(strategy = "test_strat_7", base_dir = base_dir)
  expect_equal(nrow(tbl), 1L)
  expect_equal(tbl$hypothesis[[1]], "Original claim")
})

# ---- Test 8: revises = TRUE creates a new, linked row ----------------------
test_that("revises = TRUE creates a new row linked via parent_uuid, old row unchanged", {
  base_dir <- .temp_rlog_dir()

  uuid1 <- hd_admission_preregister(
    strategy   = "test_strat_8",
    hypothesis = "Original claim",
    reviewer   = "tester",
    base_dir   = base_dir
  )

  uuid2 <- hd_admission_preregister(
    strategy   = "test_strat_8",
    hypothesis = "Revised claim, new evidence",
    reviewer   = "tester",
    revises    = TRUE,
    base_dir   = base_dir
  )

  expect_false(identical(uuid1, uuid2))

  tbl <- hd_admission_read(strategy = "test_strat_8", base_dir = base_dir)
  expect_equal(nrow(tbl), 2L)

  old_row <- tbl[tbl$uuid == uuid1, ]
  new_row <- tbl[tbl$uuid == uuid2, ]
  expect_equal(old_row$hypothesis[[1]], "Original claim")
  expect_equal(new_row$hypothesis[[1]], "Revised claim, new evidence")
  expect_true(is.na(old_row$parent_uuid[[1]]))
  expect_equal(new_row$parent_uuid[[1]], uuid1)
})

# ---- Test 9: unsealed drafts can be re-registered without revises ----------
test_that("unsealed (seal = FALSE) drafts do not trigger the sealed-claim guard", {
  base_dir <- .temp_rlog_dir()

  expect_no_error(
    hd_admission_preregister(
      strategy   = "test_strat_9",
      hypothesis = "First draft",
      reviewer   = "tester",
      base_dir   = base_dir,
      seal       = FALSE
    )
  )
  expect_no_error(
    hd_admission_preregister(
      strategy   = "test_strat_9",
      hypothesis = "Still drafting",
      reviewer   = "tester",
      base_dir   = base_dir,
      seal       = FALSE
    )
  )

  tbl <- hd_admission_read(strategy = "test_strat_9", base_dir = base_dir)
  expect_equal(nrow(tbl), 2L)
  expect_true(all(is.na(tbl$commit_hash) | !nzchar(tbl$commit_hash)))
})

# ---- Test 10: non-admission hypotheses are ignored -------------------------
test_that("hd_admission_read() ignores ordinary (non-admission) hypotheses rows", {
  base_dir <- .temp_rlog_dir()

  # A plain research-log hypothesis, unrelated to strategy admission.
  hd_rlog_append("hypotheses",
    tibble::tibble(
      uuid            = hd_rlog_uuid(),
      economic_claim  = "Equity prices mean-revert over daily horizons",
      dependent_var   = "next-day return",
      predictor       = "SMA/price ratio",
      sample_spec     = "some universe",
      null_hypothesis = "No premium",
      status          = "proposed",
      extra_json      = NA_character_
    ),
    base_dir = base_dir
  )

  hd_admission_preregister(
    strategy   = "test_strat_10",
    hypothesis = "An actual admission hypothesis",
    reviewer   = "tester",
    base_dir   = base_dir
  )

  tbl <- hd_admission_read(base_dir = base_dir)
  expect_equal(nrow(tbl), 1L)
  expect_equal(tbl$strategy[[1]], "test_strat_10")
})

# ---- Test 11: empty store returns empty tibble -----------------------------
test_that("hd_admission_read() returns an empty tibble when the store is empty", {
  base_dir <- .temp_rlog_dir()
  tbl <- hd_admission_read(base_dir = base_dir)
  expect_s3_class(tbl, "tbl_df")
  expect_equal(nrow(tbl), 0L)
  expect_true("strategy" %in% names(tbl))
})

# ---- Test 12: Input-validation snapshot: empty strategy --------------------
test_that("empty strategy triggers cli_abort", {
  base_dir <- .temp_rlog_dir()
  expect_snapshot(
    error = TRUE,
    hd_admission_preregister(strategy = "", hypothesis = "x", reviewer = "tester",
                              base_dir = base_dir)
  )
})

# ---- Test 13: Input-validation snapshot: empty hypothesis ------------------
test_that("empty hypothesis triggers cli_abort", {
  base_dir <- .temp_rlog_dir()
  expect_snapshot(
    error = TRUE,
    hd_admission_preregister(strategy = "s", hypothesis = "", reviewer = "tester",
                              base_dir = base_dir)
  )
})

# ---- Test 14: Input-validation snapshot: missing reviewer ------------------
test_that("missing reviewer triggers cli_abort", {
  base_dir <- .temp_rlog_dir()
  expect_snapshot(
    error = TRUE,
    hd_admission_preregister(strategy = "s", hypothesis = "x", reviewer = "",
                              base_dir = base_dir)
  )
})

# ---- Test 15: Function signature stability (hd_admission_preregister) -----
test_that("hd_admission_preregister() signature is stable (catches API drift)", {
  expect_snapshot(args(hd_admission_preregister))
})

# ---- Test 16: Function signature stability (hd_admission_read) ------------
test_that("hd_admission_read() signature is stable (catches API drift)", {
  expect_snapshot(args(hd_admission_read))
})
