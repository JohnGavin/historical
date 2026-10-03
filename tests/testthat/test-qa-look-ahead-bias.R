testthat::local_edition(3)
source(here::here("R/plan_qa_gates.R"))

# ── S1: lead(ym) detection ────────────────────────────────────────────────────

test_that("check_no_lead_ym detects lead(ym) pattern", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "foo <- function(df) {",
    "  df |> mutate(next_ym = lead(ym))",
    "}"
  ), tmp)
  on.exit(unlink(tmp))
  hits <- check_no_lead_ym(tmp)
  expect_equal(nrow(hits), 1L)
  expect_equal(hits$line, 2L)
  # Schema snapshot: pins the returned tibble's column names (file/line/code).
  expect_snapshot(names(hits))
})

test_that("check_no_lead_ym detects dplyr::lead(ym) pattern", {
  tmp <- tempfile(fileext = ".R")
  writeLines("mutate(ym = dplyr::lead(ym))", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_lead_ym(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_lead_ym respects # look-ahead-safe opt-out marker", {
  tmp <- tempfile(fileext = ".R")
  writeLines(
    "mutate(next_ym = dplyr::lead(ym)) |>   # look-ahead-safe: join key",
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_lead_ym(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_lead_ym ignores lead() calls on non-ym variables", {
  tmp <- tempfile(fileext = ".R")
  writeLines("mutate(next_ret = lead(ret))", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_lead_ym(tmp)
  expect_equal(nrow(hits), 0L)
})

# ── S2: slide_dbl forward-window without _lead ────────────────────────────────

test_that("check_no_unleaded_slider detects slide_dbl .before=0 without _lead", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "x <- slider::slide_dbl(",
    "  some_var, mean, .before = 0, .after = 5",
    ")"
  ), tmp)
  on.exit(unlink(tmp))
  hits <- check_no_unleaded_slider(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_unleaded_slider passes when input is a _lead variable", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "x <- slider::slide_dbl(",
    "  monthly_ret_lead, mean, .before = 0, .after = 5",
    ")"
  ), tmp)
  on.exit(unlink(tmp))
  hits <- check_no_unleaded_slider(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_unleaded_slider respects # look-ahead-safe opt-out marker", {
  tmp <- tempfile(fileext = ".R")
  writeLines(
    "x <- slide_dbl(forecast, mean, .before = 0, .after = 5) # look-ahead-safe",
    tmp
  )
  on.exit(unlink(tmp))
  hits <- check_no_unleaded_slider(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_unleaded_slider ignores slide_dbl with .before > 0", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "x <- slider::slide_dbl(",
    "  some_var, mean, .before = 11, .after = 0",
    ")"
  ), tmp)
  on.exit(unlink(tmp))
  hits <- check_no_unleaded_slider(tmp)
  expect_equal(nrow(hits), 0L)
})

# ── S3: na.approx detection ───────────────────────────────────────────────────

test_that("check_no_na_approx detects zoo::na.approx", {
  tmp <- tempfile(fileext = ".R")
  writeLines("x <- zoo::na.approx(y)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_na_approx(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_na_approx detects bare na.approx", {
  tmp <- tempfile(fileext = ".R")
  writeLines("x <- na.approx(y)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_na_approx(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_na_approx does not flag na.locf", {
  tmp <- tempfile(fileext = ".R")
  writeLines("x <- zoo::na.locf(y, maxgap = 3)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_na_approx(tmp)
  expect_equal(nrow(hits), 0L)
})

# ── S4: cumulative of forward_* detection ────────────────────────────────────

test_that("check_no_forward_cumulative detects cumprod(1 + forward_ret)", {
  tmp <- tempfile(fileext = ".R")
  writeLines("p <- cumprod(1 + forward_ret)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_forward_cumulative(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_forward_cumulative detects cumsum(forward_ret)", {
  tmp <- tempfile(fileext = ".R")
  writeLines("s <- cumsum(forward_returns)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_forward_cumulative(tmp)
  expect_equal(nrow(hits), 1L)
})

test_that("check_no_forward_cumulative respects # look-ahead-safe opt-out", {
  tmp <- tempfile(fileext = ".R")
  writeLines("p <- cumprod(1 + forward_ret)  # look-ahead-safe: forecast evaluation", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_forward_cumulative(tmp)
  expect_equal(nrow(hits), 0L)
})

test_that("check_no_forward_cumulative does not flag ordinary cumprod(1 + ret)", {
  tmp <- tempfile(fileext = ".R")
  writeLines("cum <- cumprod(1 + port_ret)", tmp)
  on.exit(unlink(tmp))
  hits <- check_no_forward_cumulative(tmp)
  expect_equal(nrow(hits), 0L)
})

# ── Live tripwire: current R/ tree must pass all 4 checks ────────────────────

test_that("qa look-ahead-bias scanner function signatures are stable (catches API drift)", {
  expect_snapshot(args(check_no_lead_ym))
  expect_snapshot(args(check_no_unleaded_slider))
  expect_snapshot(args(check_no_na_approx))
  expect_snapshot(args(check_no_forward_cumulative))
})

# ── Regression: a flagged source line containing literal curly braces must
# not crash the qa_look_ahead_bias gate's cli_abort (roborev #10641, same
# defect class as S40/S41's #851/#910/#917 fixes -- cli treats every bullet
# element as a glue format string and re-parses literal `{}` as R code).
# `code` here is a raw SOURCE LINE flagged by S1-S4's lexical scans, so a
# brace is near-certain (any hit inside a function body, an if-block, a
# glue call, etc.) -- unlike S40/S41's data fields, none of the fixtures
# above ever exercised this. Before the fix, splicing an unescaped brace
# into cli_abort() crashed with a cli/glue parse error instead of reporting
# the violation. ──

test_that(".qa_look_ahead_bias_msgs escapes literal braces in a flagged source line", {
  all_hits <- tibble::tibble(
    check = "S1: lead(ym)",
    file  = "R/plan_foo.R",
    line  = 42L,
    code  = "if (x) { mutate(next_ym = lead(ym)) }"
  )
  msgs <- .qa_look_ahead_bias_msgs(all_hits)
  expect_length(msgs, 1L)
  # Doubled braces are glue's own escape convention -- a single literal
  # brace in the source line must become a doubled brace in the escaped
  # message, never a bare one that glue would re-parse.
  expect_true(grepl("{{", msgs, fixed = TRUE))
  expect_true(grepl("}}", msgs, fixed = TRUE))
})

          # NOTE: `qa10641_undefined_probe` is a deliberately never-defined
          # symbol (not a real dplyr/project call like mutate()/lead()) so
          # this fixture's cli-evaluation behaviour cannot depend on what
          # some OTHER test file has already attached/sourced into the
          # shared test-session globalenv by the time this file runs.
test_that("qa_look_ahead_bias's cli_abort does not crash on a source line with literal braces (fixed)", {
  all_hits <- tibble::tibble(
    check = "S1: lead(ym)",
    file  = "R/plan_foo.R",
    line  = 42L,
    code  = "if (x) { qa10641_undefined_probe(next_ym = lead(ym)) }"
  )
  # Reproduces the qa_look_ahead_bias target's own abort call (R/plan_qa_gates.R)
  # exactly, using the fixed message-building helper, without needing tar_make().
  err <- testthat::capture_error({
    msgs <- .qa_look_ahead_bias_msgs(all_hits)
    cli::cli_abort(c(
      "x" = "Look-ahead bias patterns detected in {nrow(all_hits)} place(s):",
      setNames(msgs, rep("i", length(msgs)))
    ))
  })
  expect_false(is.null(err))
  expect_match(conditionMessage(err), "Look-ahead bias patterns detected in 1 place", fixed = TRUE)
  expect_match(conditionMessage(err), "if (x) { qa10641_undefined_probe(next_ym = lead(ym)) }", fixed = TRUE)
})

test_that("falsification: the PRE-fix (unescaped) message-building crashes cli_abort instead of reporting the violation", {
  # Reproduces the pre-fix code path (no .qa_cli_escape) to prove the two
  # tests above are real regression tests, not vacuous ones -- per
  # verification-before-completion. See NOTE above re: qa10641_undefined_probe.
  all_hits <- tibble::tibble(
    check = "S1: lead(ym)",
    file  = "R/plan_foo.R",
    line  = 42L,
    code  = "if (x) { qa10641_undefined_probe(next_ym = lead(ym)) }"
  )
  err <- testthat::capture_error({
    msgs_unescaped <- purrr::pmap_chr(
      all_hits[, c("check", "file", "line", "code")],
      function(check, file, line, code) {
        sprintf("  %s -- %s:%d -- %s", check, basename(file), line, trimws(code))
      }
    )
    cli::cli_abort(c(
      "x" = "Look-ahead bias patterns detected in {nrow(all_hits)} place(s):",
      setNames(msgs_unescaped, rep("i", length(msgs_unescaped)))
    ))
  })
  expect_false(is.null(err))
  # The pre-fix crash is a cli/glue PARSE error, not the intended violation
  # message -- exactly the bug roborev #10641 reported.
  expect_false(grepl("Look-ahead bias patterns detected", conditionMessage(err), fixed = TRUE))
})

test_that("qa_look_ahead_bias passes on current R/ tree", {
  files <- list.files(here::here("R"), pattern = "\\.R$",
                      full.names = TRUE, recursive = TRUE)
  files <- files[basename(files) != "plan_qa_gates.R"]

  s1 <- check_no_lead_ym(files)
  s2 <- check_no_unleaded_slider(files)
  s3 <- check_no_na_approx(files)
  s4 <- check_no_forward_cumulative(files)

  combined <- dplyr::bind_rows(s1, s2, s3, s4)
  expect_equal(
    nrow(combined),
    0L,
    info = paste(capture.output(print(combined)), collapse = "\n")
  )
})
