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
