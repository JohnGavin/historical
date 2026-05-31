# Tests for hd_drif_select_topn() in R/drif_selection.R
#
# Selection logic (rank-first, filter-benchmark-second):
# 1. pred_rank is computed ACROSS ALL series (including benchmark).
# 2. Benchmark is dropped via params$factors filter.
# 3. Only rows where pred_rank <= top_n survive.
#
# Consequence: a benchmark with rank 1 consumes a rank slot, so
# top_n=1 returns the factor with global rank 2 (not rank 1 in
# the factor-only sub-pool).  This matches production plan_drif.R.

library(dplyr)

# ── helpers ──────────────────────────────────────────────────────────────────

make_preds <- function() {
  # 5 investable factors + 1 benchmark ("MKT") for two months.
  # Benchmark has the highest predicted return and thus global rank 1
  # in both months.  Within the factor pool the effective ranks are:
  #
  #   Jan: SMB(global 2), MOM(global 3), BAB(global 5), HML(global 4), QMJ(global 6)
  #   Feb: MOM(global 1 — tie with MKT? no, MKT=8%), BAB(global 2), HML(global 3), ...
  #
  # Using explicit pred_rank to keep the test deterministic.
  tibble::tibble(
    factor_name   = rep(c("HML", "SMB", "MOM", "QMJ", "BAB", "MKT"), 2),
    ym            = rep(c("2024-01", "2024-02"), each = 6L),
    predicted_ret = c(0.03, 0.05, 0.04, 0.01, 0.02, 0.10,
                      0.02, 0.01, 0.06, 0.03, 0.05, 0.08),
    actual_ret    = rnorm(12L, 0.005, 0.03),
    # Global ranks (lower = higher predicted return) across all 6 series:
    # Jan: MKT(0.10)=1, SMB(0.05)=2, MOM(0.04)=3, HML(0.03)=4, BAB(0.02)=5, QMJ(0.01)=6
    # Feb: MKT(0.08)=1, MOM(0.06)=2, BAB(0.05)=3, QMJ(0.03)=4, HML(0.02)=5, SMB(0.01)=6
    pred_rank     = c(4L, 2L, 3L, 6L, 5L, 1L,
                      5L, 6L, 2L, 4L, 3L, 1L)
  )
}

make_params <- function() {
  list(factors = c("HML", "SMB", "MOM", "QMJ", "BAB"))
}

# ── standard behaviour ────────────────────────────────────────────────────────

test_that("helper returns correct factors (benchmark excluded, global ranks respected)", {
  preds  <- make_preds()
  params <- make_params()

  # top_n = 3: keep pred_rank <= 3, then drop MKT (rank 1)
  #   Jan: rank<=3 is MKT(1), SMB(2), MOM(3) → after drop MKT: SMB, MOM
  #   Feb: rank<=3 is MKT(1), MOM(2), BAB(3) → after drop MKT: MOM, BAB
  result <- hd_drif_select_topn(preds, params, top_n = 3L)

  expect_false("MKT" %in% result$factor_name)

  jan <- result |> filter(ym == "2024-01") |> pull(factor_name)
  expect_setequal(jan, c("SMB", "MOM"))

  feb <- result |> filter(ym == "2024-02") |> pull(factor_name)
  expect_setequal(feb, c("MOM", "BAB"))
})

test_that("top_n=2 only returns factors with global rank <= 2 (benchmark consumes rank 1)", {
  preds  <- make_preds()
  params <- make_params()

  # top_n=2: keep pred_rank <= 2, drop MKT
  #   Jan: rank<=2 = MKT(1), SMB(2) → drop MKT → SMB only
  #   Feb: rank<=2 = MKT(1), MOM(2) → drop MKT → MOM only
  result <- hd_drif_select_topn(preds, params, top_n = 2L)

  jan <- result |> filter(ym == "2024-01") |> pull(factor_name)
  expect_equal(jan, "SMB")

  feb <- result |> filter(ym == "2024-02") |> pull(factor_name)
  expect_equal(feb, "MOM")
})

test_that("benchmark-would-be-top-1 edge case: top_n=2 returns rank-2 factor", {
  # Minimal case: 1 benchmark + 1 factor.
  # Benchmark rank 1, factor rank 2. top_n=2 → factor survives.
  preds <- tibble::tibble(
    factor_name   = c("MKT", "HML"),
    ym            = c("2024-01", "2024-01"),
    predicted_ret = c(0.20, 0.10),
    actual_ret    = c(0.05, 0.03),
    pred_rank     = c(1L, 2L)
  )
  params <- list(factors = "HML")

  result <- hd_drif_select_topn(preds, params, top_n = 2L)

  expect_equal(nrow(result), 1L)
  expect_equal(result$factor_name, "HML")
  expect_false("MKT" %in% result$factor_name)
})

test_that("benchmark-would-be-top-1: top_n=1 returns NO factors (rank 1 is taken by benchmark)", {
  # With top_n=1 and benchmark having rank 1, no investable factor survives.
  preds <- tibble::tibble(
    factor_name   = c("MKT", "HML"),
    ym            = c("2024-01", "2024-01"),
    predicted_ret = c(0.20, 0.10),
    actual_ret    = c(0.05, 0.03),
    pred_rank     = c(1L, 2L)
  )
  params <- list(factors = "HML")

  result <- hd_drif_select_topn(preds, params, top_n = 1L)

  # HML has pred_rank=2, which exceeds top_n=1 → no rows survive
  expect_equal(nrow(result), 0L)
})

test_that("all factors filtered → returns zero-row tibble without error", {
  preds  <- make_preds()
  params <- list(factors = character(0))

  result <- suppressWarnings(
    hd_drif_select_topn(preds, params, top_n = 2L)
  )

  expect_equal(nrow(result), 0L)
  expect_true("factor_name" %in% names(result))
  expect_true("ym"          %in% names(result))
})

test_that("empty input tibble returns empty tibble without error", {
  empty  <- make_preds()[0L, ]
  params <- make_params()

  result <- hd_drif_select_topn(empty, params, top_n = 2L)

  expect_equal(nrow(result), 0L)
})

test_that("top_n larger than pool returns all investable factors per month", {
  preds  <- make_preds()
  params <- make_params()  # 5 investable factors; MKT excluded

  result <- hd_drif_select_topn(preds, params, top_n = 99L)

  for (m in unique(preds$ym)) {
    month_facts <- result |> filter(ym == m) |> pull(factor_name)
    expect_setequal(month_facts, params$factors)
  }
})

# ── ranking computed from raw predictions (no pre-computed pred_rank) ─────────

test_that("helper ranks internally from predicted_ret when pred_rank absent", {
  # Remove pre-computed ranks; function must rank on predicted_ret across ALL rows
  preds_no_rank <- make_preds() |> select(-pred_rank)
  params <- make_params()

  # top_n=3: internally ranks all 6 per month, keeps rank<=3, drops MKT
  # Jan: MKT(0.10)=1, SMB(0.05)=2, MOM(0.04)=3 → SMB + MOM
  # Feb: MKT(0.08)=1, MOM(0.06)=2, BAB(0.05)=3 → MOM + BAB
  result <- hd_drif_select_topn(preds_no_rank, params, top_n = 3L)

  expect_false("MKT" %in% result$factor_name)
  # 2 months × 2 factors each = 4 rows
  expect_equal(nrow(result), 4L)

  jan <- result |> filter(ym == "2024-01") |> pull(factor_name)
  expect_setequal(jan, c("SMB", "MOM"))
})

test_that("helper ranks internally from 'predicted' column (multiverse style)", {
  preds_mv <- make_preds() |>
    rename(predicted = predicted_ret) |>
    select(-pred_rank)
  params <- make_params()

  result <- hd_drif_select_topn(preds_mv, params, top_n = 3L)

  expect_false("MKT" %in% result$factor_name)
  expect_equal(nrow(result), 4L)
})

# ── input validation ──────────────────────────────────────────────────────────

test_that("non-data-frame predictions throws cli_abort", {
  # Existing guard: class check (algorithmic)
  expect_error(
    hd_drif_select_topn("not_a_df", make_params(), 2L),
    class = "rlang_error"
  )
  # Snapshot guard: exact error wording (#340)
  expect_snapshot(
    error = TRUE,
    hd_drif_select_topn("not_a_df", make_params(), 2L)
  )
})

test_that("missing params$factors throws cli_abort", {
  # Existing guard: class check (algorithmic)
  expect_error(
    hd_drif_select_topn(make_preds(), list(), 2L),
    class = "rlang_error"
  )
  # Snapshot guard: exact error wording (#340)
  expect_snapshot(
    error = TRUE,
    hd_drif_select_topn(make_preds(), list(), 2L)
  )
})

test_that("non-positive top_n throws cli_abort", {
  # Existing guard: class check (algorithmic)
  expect_error(
    hd_drif_select_topn(make_preds(), make_params(), 0L),
    class = "rlang_error"
  )
  # Snapshot guard: exact error wording (#340)
  expect_snapshot(
    error = TRUE,
    hd_drif_select_topn(make_preds(), make_params(), 0L)
  )
})

# ── API stability ──────────────────────────────────────────────────────────────

test_that("hd_drif_select_topn function signature is stable (catches API drift)", {
  expect_snapshot(args(hd_drif_select_topn))
})
