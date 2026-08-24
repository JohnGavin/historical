testthat::local_edition(3)
# Tests for hd_strategy_names_tbl() (R/plan_strategy_names.R) -- the plain,
# non-target constructor behind the `strategy_names` tar_target -- and for
# .build_strategy_obs_ann_factor() (R/plan_leaderboard.R), which derives
# STRATEGY_OBS_ANN_FACTOR from it instead of hand-duplicating the same data
# (#629: OLMAR-1 was ranked on the leaderboard but absent from
# strategy_names -- a single-source-of-truth violation between the two
# hand-maintained lists).

source(here::here("R/plan_strategy_names.R"))
source(here::here("R/plan_leaderboard.R"))

# ── Parallel-vector integrity ────────────────────────────────────────────
# strategy_names.R is a set of hand-aligned parallel vectors with inline
# comments between elements -- a misaligned edit silently corrupts a
# DIFFERENT strategy's declaration with no obvious symptom (see the
# strategy-name-consistency rule + prior #629 dispatch notes). These tests
# evaluate the actual constructed tibble rather than eyeballing the diff.

strategy_names_tbl <- hd_strategy_names_tbl()

test_that("hd_strategy_names_tbl() has 17 strategies with all vectors equal length", {
  expect_equal(nrow(strategy_names_tbl), 17L)
  # Every column must be length 17 -- tibble::tibble() would already error
  # on unequal lengths at construction time, but assert explicitly so a
  # future refactor that swaps tibble::tibble() for something more lenient
  # (e.g. data.frame(stringsAsFactors=...)) cannot silently recycle a
  # shorter vector.
  lengths <- vapply(strategy_names_tbl, length, integer(1))
  expect_true(all(lengths == 17L))
})

test_that("hd_strategy_names_tbl() has no duplicate code_name or short_name", {
  expect_equal(nrow(strategy_names_tbl), dplyr::n_distinct(strategy_names_tbl$code_name))
  expect_equal(nrow(strategy_names_tbl), dplyr::n_distinct(strategy_names_tbl$short_name))
})

test_that("olmar row (#629) is present with the expected declared values", {
  olmar_row <- dplyr::filter(strategy_names_tbl, code_name == "olmar")
  expect_equal(nrow(olmar_row), 1L)
  expect_equal(olmar_row$short_name, "OLMAR-1")
  expect_equal(olmar_row$frequency, "daily")
  expect_equal(olmar_row$ann_factor, 252L)
  expect_equal(olmar_row$asset_class, "equity")
  expect_equal(as.character(olmar_row$directionality), "long_only")
})

# OBSERVED (not predicted): full parallel-vector table for the PR record,
# every position's (code, short, long, frequency, ann_factor) tuple.
test_that("full strategy_names tuple table is stable (parallel-vector alignment snapshot)", {
  tuple_tbl <- strategy_names_tbl |>
    dplyr::select(code_name, short_name, long_name, frequency, ann_factor) |>
    as.data.frame()
  expect_snapshot(print(tuple_tbl, width = 200))
})

# ── STRATEGY_OBS_ANN_FACTOR derivation (#629) ────────────────────────────

test_that("STRATEGY_OBS_ANN_FACTOR covers exactly the same strategies as strategy_names", {
  expect_setequal(STRATEGY_OBS_ANN_FACTOR$strategy, strategy_names_tbl$short_name)
  expect_equal(nrow(STRATEGY_OBS_ANN_FACTOR), nrow(strategy_names_tbl))
})

test_that("STRATEGY_OBS_ANN_FACTOR$obs_ann_factor agrees with strategy_names$ann_factor for every strategy", {
  merged <- dplyr::inner_join(
    STRATEGY_OBS_ANN_FACTOR,
    dplyr::select(strategy_names_tbl, short_name, ann_factor),
    by = c("strategy" = "short_name")
  )
  expect_equal(nrow(merged), nrow(STRATEGY_OBS_ANN_FACTOR))
  expect_equal(merged$obs_ann_factor, merged$ann_factor)
})

test_that("STRATEGY_OBS_ANN_FACTOR includes OLMAR-1 at ann_factor 252 (#629 regression)", {
  olmar_obs <- dplyr::filter(STRATEGY_OBS_ANN_FACTOR, strategy == "OLMAR-1")
  expect_equal(nrow(olmar_obs), 1L)
  expect_equal(olmar_obs$obs_ann_factor, 252)
})

test_that(".build_strategy_obs_ann_factor() aborts loudly when a strategy has no source citation", {
  incomplete_source <- dplyr::filter(.strategy_obs_ann_factor_source, code_name != "olmar")
  expect_error(
    .build_strategy_obs_ann_factor(strategy_names_tbl, incomplete_source),
    regexp = "OLMAR-1"
  )
  expect_snapshot(
    error = TRUE,
    .build_strategy_obs_ann_factor(strategy_names_tbl, incomplete_source)
  )
})

test_that(".build_strategy_obs_ann_factor() succeeds and drops code_name from the output", {
  built <- .build_strategy_obs_ann_factor(strategy_names_tbl, .strategy_obs_ann_factor_source)
  expect_setequal(names(built), c("strategy", "obs_ann_factor", "obs_ann_factor_source"))
  expect_equal(nrow(built), nrow(strategy_names_tbl))
})
