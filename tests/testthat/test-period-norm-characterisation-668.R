testthat::local_edition(3)
# Characterisation tests for the #668 Phase 2 migration (P2-1, P2-2).
#
# Written BEFORE the migration and kept green after it: they pin the observable
# behaviour of the period-label rename inside the `leaderboard` target's
# `.norm_mf()` / `.norm_value()` closures, and of S11's `exempt_periods` set,
# so that moving both onto `resolve_entity()` / the glossary cannot change an
# output.
#
# The closures live inside the body of `tar_target(leaderboard, {...})`, so
# they are extracted from the parsed source of R/plan_leaderboard.R (the real
# code, not a copy) and evaluated in an environment carrying only dplyr, the
# glossary loaders and the helper(s) plan_leaderboard.R defines at top level.

source(here::here("R/glossary.R"))
source(here::here("R/plan_qa_gates.R"))

# ── Extract a closure by name from the parsed plan file ──────────────────────

.find_assignment <- function(expr, name) {
  if (is.call(expr)) {
    if (identical(expr[[1]], as.name("<-")) &&
          is.name(expr[[2]]) && identical(as.character(expr[[2]]), name)) {
      return(expr[[3]])
    }
    for (i in seq_along(expr)) {
      found <- .find_assignment(expr[[i]], name)
      if (!is.null(found)) return(found)
    }
  }
  NULL
}

.load_plan_closure <- function(name) {
  exprs <- parse(here::here("R/plan_leaderboard.R"), keep.source = FALSE)
  # parent = this file's test env, where source("R/glossary.R") put the loaders
  env <- new.env(parent = environment(.load_plan_closure))
  # top-level definitions in the plan file (helpers), without running targets
  for (e in exprs) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
          is.name(e[[2]]) && is.call(e[[3]]) &&
          identical(e[[3]][[1]], as.name("function"))) {
      eval(e, env)
    }
  }
  fn_expr <- NULL
  for (e in exprs) {
    fn_expr <- .find_assignment(e, name)
    if (!is.null(fn_expr)) break
  }
  stopifnot(!is.null(fn_expr))
  fn <- eval(fn_expr, env)
  environment(fn) <- list2env(
    list(
      filter = dplyr::filter, select = dplyr::select, rename = dplyr::rename,
      mutate = dplyr::mutate
    ),
    parent = env
  )
  fn
}

# ── Fixture: one kept strategy with one row per period spelling ──────────────

.periods_in <- c("Full", "Training", "OOS", "Full Period", "Testing",
                 "Holdout", "Validation", "full", " Full", "", NA)

.golden_periods_out <- c("Full Period", "Training", "OOS", "Full Period", "Testing",
                         "Holdout", "Validation", "full", " Full", "", NA)

.make_in <- function(strategy) {
  n <- length(.periods_in)
  tibble::tibble(
    strategy = c(rep(strategy, n), "Some Other Strategy"),
    period   = c(.periods_in, "Full"),
    n_months = c(seq_len(n), 99L),
    cagr     = c(seq_len(n) * 1.5, 7), vol = c(seq_len(n) * 2, 7),
    sharpe   = c(seq_len(n) / 10, 1),
    max_dd   = c(seq_len(n) * -3, -7), calmar = c(seq_len(n), 1),
    ann_rf   = c(seq_len(n) * 0.5, 0.5)
  )
}

.golden_out <- function() {
  n <- length(.periods_in)
  tibble::tibble(
    period = .golden_periods_out,
    months = seq_len(n),
    cagr   = seq_len(n) * 1.5 / 100, vol = seq_len(n) * 2 / 100,
    sharpe = seq_len(n) / 10,
    max_dd = seq_len(n) * -3 / 100,
    ann_rf = seq_len(n) * 0.5 / 100
  )
}

test_that(".norm_mf maps every period spelling exactly as before (golden table)", {
  fn <- .load_plan_closure(".norm_mf")
  out <- fn(.make_in("Long-Short TS-Mom (MOP 2012, vol-targeted)"))
  expect_identical(out, .golden_out())
})

test_that(".norm_value maps every period spelling exactly as before (golden table)", {
  fn <- .load_plan_closure(".norm_value")
  out <- fn(.make_in("Pure Value (100% HML, EV/EBIT proxy)"))
  expect_identical(out, .golden_out())
})

test_that("period renames: unknown spellings pass through unchanged (old behaviour kept)", {
  # Old code: ifelse(period == "Full", "Full Period", period) -- anything that
  # is not exactly "Full" is returned as-is. S10 (check_leaderboard_period_vocab)
  # is the downstream gate that fails loud on a non-vocabulary label.
  fn <- .load_plan_closure(".norm_mf")
  out <- fn(.make_in("Long-Short TS-Mom (MOP 2012, vol-targeted)"))
  expect_true(all(c("full", " Full", "") %in% out$period))
})

test_that(".norm_* return NULL for NULL or empty input as before", {
  for (nm in c(".norm_mf", ".norm_value")) {
    fn <- .load_plan_closure(nm)
    expect_null(fn(NULL))
    expect_null(fn(.make_in("x")[0, ]))
  }
})

# ── S11 exempt_periods: behaviour per period spelling ────────────────────────

test_that("check_metric_window_bounds exempts exactly Validation/Holdout/Full/Full Period", {
  test_end <- as.Date("2022-12-31")
  late <- as.Date("2026-01-31")
  run <- function(p) {
    m <- tibble::tibble(strategy = "S", period = p, window_end = late)
    tryCatch({ check_metric_window_bounds(m, test_end, "fixture"); "pass" },
             error = function(e) "abort")
  }
  exempt <- c("Validation", "Holdout", "Full", "Full Period")
  checked <- c("Training", "Testing", "OOS", "full", " Full", "", NA_character_)
  expect_identical(vapply(exempt, run, character(1), USE.NAMES = FALSE),
                   rep("pass", length(exempt)))
  expect_identical(vapply(checked, run, character(1), USE.NAMES = FALSE),
                   rep("abort", length(checked)))
})

test_that(".s11_exempt_periods() derives exactly the previously hand-typed set", {
  expect_identical(.s11_exempt_periods(),
                   c("Validation", "Holdout", "Full", "Full Period"))
})

test_that("falsification: dropping the alias removes 'Full' from the derived exemption and from the rename", {
  empty_resolution <- list()
  expect_identical(.s11_exempt_periods(resolution = empty_resolution),
                   c("Validation", "Holdout", "Full Period"))
  expect_identical(resolve_entity("Full", "period_label", empty_resolution), "Full")
})

test_that(".s11_exempt_periods aborts when the glossary has no canonical full-sample value", {
  g <- load_glossary()
  g$period_label$canonical_full_sample_value <- NULL
  expect_error(.s11_exempt_periods(glossary = g), "canonical_full_sample_value")
})
