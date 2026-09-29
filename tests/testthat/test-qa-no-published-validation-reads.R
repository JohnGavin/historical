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

# ── Regression: a flagged source line containing literal curly braces must
# not crash the qa_no_published_validation_reads gate's cli_abort (roborev
# #10641, same defect class as S40/S41's #851/#910/#917 fixes -- cli treats
# every bullet element as a glue format string and re-parses literal `{}`
# as R code). `code` here is a raw SOURCE LINE flagged by
# check_no_published_validation_reads()'s lexical scan of published
# .qmd/.R files, so a brace is near-certain (an inline `r { ... }`
# expression chunk, an if-block, etc.) -- unlike S40/S41's data fields,
# none of the fixtures above ever exercised this. Before the fix, splicing
# an unescaped brace into cli_abort() crashed with a cli/glue parse error
# instead of reporting the violation. ──

          # NOTE: `qa10641_undefined_probe` is a deliberately never-defined
          # symbol (not a real project function like safe_tar_read()) so this
          # fixture's cli-evaluation behaviour cannot depend on whether some
          # OTHER test file has already sourced a file that happens to define
          # a same-named helper into the shared test-session globalenv.
test_that(".qa_validation_reads_msgs escapes literal braces in a flagged source line", {
  hits <- tibble::tibble(
    file = "docs/stock-backtest.qmd",
    line = 7L,
    code = '`r { qa10641_undefined_probe(); m$period=="Validation" }`'
  )
  msgs <- .qa_validation_reads_msgs(hits)
  expect_length(msgs, 1L)
  expect_true(grepl("{{", msgs, fixed = TRUE))
  expect_true(grepl("}}", msgs, fixed = TRUE))
})

test_that("qa_no_published_validation_reads's cli_abort does not crash on a source line with literal braces (fixed)", {
  hits <- tibble::tibble(
    file = "docs/stock-backtest.qmd",
    line = 7L,
    code = '`r { qa10641_undefined_probe(); m$period=="Validation" }`'
  )
  # Reproduces the qa_no_published_validation_reads target's own abort call
  # (R/plan_qa_gates.R) exactly, using the fixed message-building helper,
  # without needing tar_make().
  err <- testthat::capture_error({
    msgs <- .qa_validation_reads_msgs(hits)
    cli::cli_abort(c(
      "x" = paste0(
        "Published document(s) read the sealed Validation partition in ",
        nrow(hits), " place(s), #660:"
      ),
      setNames(msgs, rep("i", length(msgs))),
      "i" = paste0(
        "Validation is sealed for display AND reasoning ",
        "(.claude/rules/backtest-partitions.md) -- remove the read, or use ",
        "scripts/evaluate_validation.R for the sanctioned one-shot evaluation."
      )
    ))
  })
  expect_false(is.null(err))
  expect_match(
    conditionMessage(err),
    "Published document(s) read the sealed Validation partition in 1 place(s), #660",
    fixed = TRUE
  )
  expect_match(
    conditionMessage(err),
    'r { qa10641_undefined_probe(); m$period=="Validation" }',
    fixed = TRUE
  )
})

test_that("falsification: the PRE-fix (unescaped) message-building crashes cli_abort instead of reporting the violation", {
  # Reproduces the pre-fix code path (no .qa_cli_escape) to prove the two
  # tests above are real regression tests, not vacuous ones -- per
  # verification-before-completion. Uses the same deliberately never-defined
  # `qa10641_undefined_probe` symbol as above so the crash is guaranteed
  # regardless of what other test files have sourced into globalenv by the
  # time this file runs (see NOTE above) -- the earlier version of this test
  # used the real safe_tar_read() function name and was order-dependent:
  # it passed in isolation but failed inside the full root suite once
  # test-vignette-utils.R had already sourced docs/vignette_utils.R (which
  # defines safe_tar_read() to return NULL, rather than error, for a
  # missing target), so the unescaped `{}` evaluated to NULL instead of
  # throwing.
  hits <- tibble::tibble(
    file = "docs/stock-backtest.qmd",
    line = 7L,
    code = '`r { qa10641_undefined_probe(); m$period=="Validation" }`'
  )
  err <- testthat::capture_error({
    msgs_unescaped <- purrr::pmap_chr(
      hits[, c("file", "line", "code")],
      function(file, line, code) {
        sprintf("  %s:%d -- %s", basename(file), line, trimws(code))
      }
    )
    cli::cli_abort(c(
      "x" = paste0(
        "Published document(s) read the sealed Validation partition in ",
        nrow(hits), " place(s), #660:"
      ),
      setNames(msgs_unescaped, rep("i", length(msgs_unescaped)))
    ))
  })
  expect_false(is.null(err))
  expect_false(grepl(
    "Published document(s) read the sealed Validation partition",
    conditionMessage(err),
    fixed = TRUE
  ))
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
