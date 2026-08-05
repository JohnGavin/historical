testthat::local_edition(3)
# Tests for check_no_published_validation_reads() — QA gate S15 (#660)
#
# The function is defined in R/plan_qa_gates.R. Tests exercise the gate
# directly without running tar_make().
#
# Background (#660): docs/stock-backtest.qmd read `period == "Validation"`
# directly from upstream source-metrics targets (stk_drif_metrics,
# stk_max_metrics, fm_metrics, drif_metrics, etf_a_metrics, etf_b_metrics)
# in inline R expressions and unfiltered metrics tables -- publishing
# sealed one-shot evaluation figures in prose and table cells, and in one
# case drawing a strategy conclusion from them. This bypassed the
# `leaderboard` target and its S14 gate entirely, because the reads went
# straight to the source metrics targets, which still legitimately compute
# a Validation row for other consumers.

source(here::here("R/plan_qa_gates.R"))

# ── S15: literal `period == "Validation"` detection ──────────────────────────

test_that("check_no_published_validation_reads detects period==\"Validation\" (no spaces)", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(
    'Validation Sharpe: `r { m <- safe_tar_read("x"); m$sharpe[m$period=="Validation"] }`',
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 1L)
  expect_equal(hits$line, 1L)
  # Schema snapshot: pins the returned tibble's column names (file/line/code).
  expect_snapshot(names(hits))
})

test_that("check_no_published_validation_reads detects period == \"Validation\" (spaced)", {
  tmp <- tempfile(fileext = ".R")
  writeLines(
    'offenders <- m[m$period == "Validation", ]',
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_published_validation_reads detects single-quoted comparisons", {
  tmp <- tempfile(fileext = ".R")
  writeLines(
    "v <- m$sharpe[m$period == 'Validation']",
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_published_validation_reads respects # validation-read-safe opt-out marker", {
  tmp <- tempfile(fileext = ".R")
  writeLines(
    'v <- m$sharpe[m$period == "Validation"]  # validation-read-safe: internal audit only',
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_published_validation_reads ignores filter(period != \"Validation\")", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(
    'display <- metrics |> filter(period != "Validation")',
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_published_validation_reads ignores prose mentions of Validation with no comparison", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(
    "**Validation (sealed partition):** Not reported here -- see scripts/evaluate_validation.R.",
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_published_validation_reads ignores computing/labelling a Validation row", {
  # R/plan_stock_backtest.R and siblings legitimately compute a Validation
  # row for source metrics targets via calc_metrics(val_data, "Validation")
  # -- a label argument, not a `period ==` comparison. Out of #660 scope.
  tmp <- tempfile(fileext = ".R")
  writeLines(
    'calc_metrics(val_data |> filter(date >= params$val_start), "Validation")',
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_published_validation_reads returns zero rows for a clean file", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(
    c(
      "Full-period Sharpe: `r round(m$sharpe[m$period==\"Full Period\"], 2)`",
      "Testing Sharpe: `r round(m$sharpe[m$period==\"Testing\"], 2)`"
    ),
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_published_validation_reads(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_published_validation_reads names every offending file:line", {
  tmp1 <- tempfile(fileext = ".qmd")
  tmp2 <- tempfile(fileext = ".qmd")
  writeLines('m$sharpe[m$period=="Validation"]', tmp1)
  writeLines(c("prose line", 'm$cagr[m$period=="Validation"]'), tmp2)
  on.exit({
    unlink(tmp1)
    unlink(tmp2)
  })
  hits <- check_no_published_validation_reads(c(tmp1, tmp2))
  expect_equal(nrow(hits), 2L)
  expect_true(tmp1 %in% hits$file)
  expect_true(tmp2 %in% hits$file)
  expect_equal(hits$line[hits$file == tmp2], 2L)
})

# ── Live tripwire: current docs/R/scripts tree must pass (same scan as S15) ──

test_that("qa_no_published_validation_reads scanner function signature is stable (catches API drift)", {
  expect_snapshot(args(check_no_published_validation_reads))
})

test_that("qa_no_published_validation_reads passes on the current docs/R/scripts tree", {
  scan_dirs <- c(here::here("docs"), here::here("R"), here::here("scripts"))
  scan_dirs <- scan_dirs[dir.exists(scan_dirs)]
  files <- unlist(lapply(scan_dirs, function(d) {
    list.files(d, pattern = "\\.(qmd|R)$", full.names = TRUE, recursive = TRUE)
  }))
  files <- files[basename(files) != "plan_qa_gates.R"]
  files <- files[basename(files) != "evaluate_validation.R"]

  hits <- check_no_published_validation_reads(files)
  expect_equal(
    nrow(hits),
    0L,
    info = paste(capture.output(print(hits)), collapse = "\n")
  )
})
