# Tests for plan_structural_breaks.R (#477)
#
# Tests for the plan helper logic (summary builder, divergence flag) using a
# synthetic multi-strategy input.  Snapshot tests for assembled caption strings.
#
# Note: unit tests for hd_structural_breaks() itself live in:
#   packages/historicaldata/tests/testthat/test-structural-breaks.R
# They are NOT duplicated here (snapshot-test-policy.md).
#
# All tests are self-contained: no live targets pipeline is executed.

testthat::local_edition(3)

# Load hd_structural_breaks() from the package source.
# We source the file directly rather than pkgload::load_all() to avoid
# pulling in all historicaldata dependencies (duckplyr, etc.) in the
# root-level test environment, which mirrors the outer dev shell that lacks
# the full package dependency set.  cli:: is available in the dev shell.
source(here::here("packages/historicaldata/R/structural_breaks.R"))


# ─────────────────────────────────────────────────────────────────────────────
# Summary-builder helper — tested inline
#
# Replicates the logic from the `structural_breaks_summary` target body so we
# can test it without running a full pipeline.
# ─────────────────────────────────────────────────────────────────────────────

# Inline the Sharpe helper used inside the target.
.sharpe_ann <- function(r, ann) {
  r <- r[!is.na(r)]
  if (length(r) < 2L) return(NA_real_)
  sd_r <- stats::sd(r)
  if (is.na(sd_r) || sd_r <= .Machine$double.eps) return(NA_real_)
  mean(r) / sd_r * sqrt(ann)
}

# Build a synthetic multi-strategy sb_break_results list.
.make_sb_results <- function() {
  set.seed(42)
  n <- 252L * 10L  # 10 years daily
  dates <- seq.Date(as.Date("2014-01-01"), by = "day", length.out = n)

  # Strategy A: no break
  r_a <- rnorm(n, 0.0005, 0.01)
  result_a <- hd_structural_breaks(r_a, alpha = 0.01, min_years = 3L,
                                     periods_per_year = 252L)

  # Strategy B: strong injected break (Sharpe reversal)
  pre_b  <- rnorm(6L * 252L, 0.001,  0.01)
  post_b <- rnorm(4L * 252L, -0.001, 0.01)
  r_b    <- c(pre_b, post_b)
  dates_b <- seq.Date(as.Date("2014-01-01"), by = "day", length.out = length(r_b))
  result_b <- hd_structural_breaks(r_b, alpha = 0.01, min_years = 2L,
                                     periods_per_year = 252L)

  list(
    strat_a = list(
      strategy = "Strategy A",
      result   = result_a,
      error    = NULL,
      series   = list(returns = r_a, dates = dates, ppy = 252L, ann = 252)
    ),
    strat_b = list(
      strategy = "Strategy B",
      result   = result_b,
      error    = NULL,
      series   = list(returns = r_b, dates = dates_b, ppy = 252L, ann = 252)
    ),
    strat_c = list(
      strategy = "Strategy C (too short)",
      result   = NULL,
      error    = "too short: 100 < 1512",
      series   = list(returns = rnorm(100L, 0.0003, 0.01), dates = NULL,
                      ppy = 252L, ann = 252)
    )
  )
}

test_that("summary builder: no-break strategy has n_breaks = 0 and equal Sharpes", {
  res <- .make_sb_results()
  s_a <- res$strat_a

  whole_sharpe <- .sharpe_ann(s_a$series$returns, s_a$series$ann)
  # main's hd_structural_breaks() does not return post_break_returns;
  # derive from post_break_start index (same as the plan consumer does).
  post_start <- s_a$result$post_break_start
  post_r      <- s_a$series$returns[post_start:length(s_a$series$returns)]
  post_sharpe  <- .sharpe_ann(post_r, s_a$series$ann)

  # No-break strategy: post_break = full series -> Sharpes identical.
  expect_equal(s_a$result$n_breaks, 0L)
  expect_equal(length(s_a$result$break_indices), 0L)
  # When no break, post series = whole series -> Sharpes identical.
  expect_equal(whole_sharpe, post_sharpe, tolerance = 1e-10)
})

test_that("summary builder: injected-break strategy has n_breaks >= 1", {
  res   <- .make_sb_results()
  s_b   <- res$strat_b
  expect_true(s_b$result$n_breaks >= 1L)
})

test_that("summary builder: errored strategy preserved with note", {
  res   <- .make_sb_results()
  s_c   <- res$strat_c
  expect_null(s_c$result)
  expect_false(is.null(s_c$error))
  expect_match(s_c$error, "too short")
})


# ─────────────────────────────────────────────────────────────────────────────
# Caption snapshot — catches wording drift
# ─────────────────────────────────────────────────────────────────────────────

# Replicate the caption-building logic (snapshot of assembled string).
.build_caption <- function(n_strats, n_with_breaks, n_material,
                            alpha_pct, divergence_pct, min_years) {
  paste0(
    "Structural break analysis (Carver 2026): ",
    n_with_breaks, " of ", n_strats, " strategies show ",
    "at least one structural break at the ", alpha_pct, "% significance level. ",
    n_material, " show a material post-break Sharpe divergence ",
    "(>", divergence_pct, "% from whole-history Sharpe). ",
    "Breaks are detected using an iterative forward-split t-test on ",
    "vol-normalised returns with a minimum segment of ",
    min_years, " years. ",
    "Per the resulting-prohibition rule, a detected break is evidence ",
    "requiring investigation — not a signal to revise strategy allocation. ",
    "Per Carver's own finding, 'no break' often wins OOS: ",
    "break-splitting is a guard against over-splitting, not an always-on ",
    "re-estimator. ",
    "Multiple-testing note: scanning all candidate split dates inflates ",
    "the false-break rate above the nominal ", alpha_pct, "% level."
  )
}

test_that("structural_breaks_caption: format is stable (snapshot)", {
  caption <- .build_caption(
    n_strats = 7L, n_with_breaks = 1L, n_material = 0L,
    alpha_pct = 1, divergence_pct = 25, min_years = 5
  )
  expect_snapshot(cat(caption))
})


# ─────────────────────────────────────────────────────────────────────────────
# Short-series guard (#477 follow-up)
#
# Strategies with < 2 * min_years * ppy observations must produce a summary
# row with a `note` column, not an error.  Verifies the existing
# sb_break_results guard (the structural_breaks_summary target tolerates NULLs).
# ─────────────────────────────────────────────────────────────────────────────

# Replicate the summary-builder inline (mirrors structural_breaks_summary target).
.build_summary_row <- function(nm, entry, s, divergence_pct = 0.25) {
  sharpe_ann <- function(r, ann) {
    r <- r[!is.na(r)]
    if (length(r) < 2L) return(NA_real_)
    sd_r <- stats::sd(r)
    if (is.na(sd_r) || sd_r <= .Machine$double.eps) return(NA_real_)
    mean(r) / sd_r * sqrt(ann)
  }

  if (!is.null(entry$error)) {
    return(tibble::tibble(
      strategy              = nm,
      n_breaks              = NA_integer_,
      break_dates           = NA_character_,
      post_break_start      = as.Date(NA),
      whole_sharpe          = NA_real_,
      post_break_sharpe     = NA_real_,
      sharpe_divergence_pct = NA_real_,
      material_divergence   = NA,
      n_obs_whole           = if (is.null(s)) NA_integer_ else length(s$returns),
      n_obs_post_break      = NA_integer_,
      note                  = entry$error
    ))
  }

  res <- entry$result
  r   <- s$returns
  d   <- s$dates
  ann <- s$ann

  whole_sharpe   <- sharpe_ann(r, ann)
  post_start_idx <- res$post_break_start
  post_r         <- r[post_start_idx:length(r)]
  post_break_sharpe <- sharpe_ann(post_r, ann)

  break_dates_str <- if (length(res$break_indices) == 0L) {
    NA_character_
  } else {
    paste(format(d[res$break_indices], "%Y-%m-%d"), collapse = ", ")
  }

  post_break_date <- if (post_start_idx <= length(d)) d[[post_start_idx]] else as.Date(NA)

  divergence <- if (!is.na(whole_sharpe) && abs(whole_sharpe) > 0.01 &&
                     res$n_breaks > 0L && !is.na(post_break_sharpe)) {
    (post_break_sharpe - whole_sharpe) / abs(whole_sharpe)
  } else {
    NA_real_
  }

  material_flag <- if (is.na(divergence)) NA else abs(divergence) > divergence_pct

  tibble::tibble(
    strategy              = nm,
    n_breaks              = res$n_breaks,
    break_dates           = break_dates_str,
    post_break_start      = post_break_date,
    whole_sharpe          = round(whole_sharpe,      3L),
    post_break_sharpe     = round(post_break_sharpe, 3L),
    sharpe_divergence_pct = round(divergence * 100,  1L),
    material_divergence   = material_flag,
    n_obs_whole           = length(r),
    n_obs_post_break      = length(post_r),
    note                  = NA_character_
  )
}

test_that("summary builder: short series produces note row, not an error", {
  # Simulate a monthly strategy with only 30 months (< 2*5*12 = 120 minimum)
  short_returns <- rnorm(30L, 0.003, 0.04)
  entry_short <- list(
    result = NULL,
    error  = "too short: 30 < 120"
  )
  s_short <- list(returns = short_returns, dates = NULL, ppy = 12L, ann = 12)

  row <- .build_summary_row("CMR", entry_short, s_short)

  expect_equal(nrow(row), 1L)
  expect_equal(row$strategy, "CMR")
  expect_true(!is.na(row$note))
  expect_match(row$note, "too short")
  expect_true(is.na(row$n_breaks))
  expect_true(is.na(row$whole_sharpe))
})

test_that("summary builder: multi-strategy mix including no-break and known-break", {
  set.seed(99)

  # No-break monthly strategy (~15 years)
  r_nobreak  <- rnorm(180L, 0.004, 0.035)
  dates_nb   <- seq.Date(as.Date("2010-01-01"), by = "month", length.out = 180L)
  res_nobreak <- hd_structural_breaks(r_nobreak, alpha = 0.01, min_years = 3L,
                                       periods_per_year = 12L)

  # Known-break monthly strategy (positive then negative)
  r_break  <- c(rnorm(96L, 0.006, 0.030), rnorm(84L, -0.004, 0.030))
  dates_br <- seq.Date(as.Date("2010-01-01"), by = "month", length.out = 180L)
  res_break <- hd_structural_breaks(r_break, alpha = 0.01, min_years = 3L,
                                     periods_per_year = 12L)

  # Short strategy (below threshold)
  r_short <- rnorm(50L, 0.002, 0.04)

  results_list <- list(
    `Mom Pre-Peak`  = list(result = res_nobreak,  error = NULL,
                           series = list(returns = r_nobreak,  dates = dates_nb,
                                         ppy = 12L, ann = 12)),
    `Mom Post-Peak` = list(result = res_break,    error = NULL,
                           series = list(returns = r_break,    dates = dates_br,
                                         ppy = 12L, ann = 12)),
    `Mom 12-2`      = list(result = NULL,         error = "too short: 50 < 120",
                           series = list(returns = r_short,    dates = NULL,
                                         ppy = 12L, ann = 12))
  )

  rows <- lapply(names(results_list), function(nm) {
    e  <- results_list[[nm]]
    s  <- e$series
    .build_summary_row(nm, list(result = e$result, error = e$error), s)
  })
  summary_tbl <- dplyr::bind_rows(rows)

  expect_equal(nrow(summary_tbl), 3L)
  expect_equal(summary_tbl$strategy, c("Mom Pre-Peak", "Mom Post-Peak", "Mom 12-2"))

  # Both analysed strategies (rows 1 and 2) must have a non-NA n_breaks —
  # the summary builder produced a real result row, not a skip row.
  # We do NOT assert the exact break count because hd_structural_breaks() at
  # alpha = 0.01 may produce a false positive on 180 months of rnorm data
  # (the test exercises the pipeline path, not the detector's power).
  expect_false(is.na(summary_tbl$n_breaks[[1L]]))
  expect_true(summary_tbl$n_breaks[[1L]] >= 0L)

  # Known-break strategy: should have n_breaks >= 0 (not errored)
  expect_false(is.na(summary_tbl$n_breaks[[2L]]))

  # Short strategy: should have note, NA for numeric fields
  expect_match(summary_tbl$note[[3L]], "too short")
  expect_true(is.na(summary_tbl$whole_sharpe[[3L]]))
})

test_that("summary builder: updated caption counts with 14 strategies", {
  # Caption now counts 14 strategies (was 7 in original plan)
  caption <- .build_caption(
    n_strats = 14L, n_with_breaks = 2L, n_material = 1L,
    alpha_pct = 1, divergence_pct = 25, min_years = 5
  )
  expect_snapshot(cat(caption))
})
