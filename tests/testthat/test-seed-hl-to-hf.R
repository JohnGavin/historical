testthat::local_edition(3)
source(here::here("scripts", "seed_hl_to_hf.R"))

# The one-off seed of the laptop's Hyperliquid history to Hugging Face (#1088). NO network:
# the dataset is a folder, the upload is a function that records what it was given, and
# "is a fetch running" is a function. Builders: helper-hl-history.R.

# A local data folder with every required table (3 days), a raw folder with two day folders
# and a ctx_poll folder, an empty stand-in for the dataset, and a staging folder.
.setup <- function(env = parent.frame()) {
  data <- withr::local_tempdir(.local_envir = env)
  raw <- withr::local_tempdir(.local_envir = env)
  remote <- withr::local_tempdir(.local_envir = env)
  stage <- file.path(withr::local_tempdir(.local_envir = env), "stage")
  .put_all(data, c("2026-01-01", "2026-01-02", "2026-01-03"))
  for (day in c("2026-11-15", "2026-11-16")) {
    dir.create(file.path(raw, day))
    for (i in 1:4) writeLines(sprintf('{"n":%d}', i), file.path(raw, day, sprintf("c_%d.json", i)))
  }
  dir.create(file.path(raw, "ctx_poll", "2026-11-15"), recursive = TRUE)
  writeLines("x", file.path(raw, "ctx_poll", "2026-11-15", "laptop-1_000000.json.gz"))
  list(data = data, raw = raw, remote = remote, stage = stage, client = .hl_fake_client(list(), remote))
}
.never <- function() FALSE
# An upload stand-in that records what it was given and returns `code`.
.rec <- function(code = 0L) {
  st <- new.env(); st$calls <- 0L
  fn <- function(stage, message) {
    st$calls <- st$calls + 1L
    st$files <- sort(list.files(stage, recursive = TRUE))
    st$marker <- jsonlite::fromJSON(file.path(stage, "hyperliquid", "_seeded.json"), simplifyVector = FALSE)
    code
  }
  list(fn = fn, st = st)
}
.run <- function(s, ..., apply = FALSE, upload = .rec()$fn, running = .never) {
  suppressMessages(hl_seed_run(s$data, s$raw, s$client, stage_dir = s$stage, work_dir = file.path(s$stage, "..", "work"),
                               apply = apply, running_fn = running, upload_fn = upload,
                               preflight_fn = function() NULL, ...))
}
.staged <- function(s, t) arrow::read_parquet(file.path(s$stage, "hyperliquid", paste0(t, ".parquet")))

test_that("a dry run with an empty dataset stages the local tables, one tar per raw day and the marker, and uploads nothing", {
  s <- .setup(); up <- .rec()
  r <- .run(s, upload = up$fn)
  expect_equal(r$status, 0L)
  expect_equal(up$st$calls, 0L)
  expect_equal(r$commits, 1L)
  expect_true(all(is.na(r$tables$hf_rows)))
  expect_equal(r$tables$merged_rows[r$tables$table == "perp_daily"], 6L)   # missing HF copy: union equals local
  expect_equal(nrow(.staged(s, "perp_daily")), nrow(arrow::read_parquet(file.path(s$data, "perp_daily.parquet"))))
  expect_equal(r$days$day, c("2026-11-15", "2026-11-16"))
  expect_equal(r$days$files, c(4L, 4L))
  expect_true(all(!is.na(r$days$packed_mb)))
  expect_true("hyperliquid/raw/weekly/date=2026-11-15/seed.tar" %in% r$files)
  expect_false(any(grepl("ctx_poll", r$files)))
  expect_true("hyperliquid/_seeded.json" %in% r$files)
})

test_that("with an HF copy the result is the union of both, local rows winning a clash", {
  s <- .setup()
  hf <- .mk_table("perp_daily", c("2025-12-30", "2025-12-31", "2026-01-01"))   # older days + one shared day
  hf$v <- 1000L
  .put(hf, file.path(s$remote, "hyperliquid"), "perp_daily")
  r <- .run(s)
  expect_equal(r$status, 0L)
  row <- r$tables[r$tables$table == "perp_daily", ]
  expect_equal(c(row$local_rows, row$hf_rows, row$merged_rows), c(6L, 6L, 10L))   # 6 + 6 - 2 shared keys
  expect_equal(row$earliest, "2025-12-30")
  m <- .staged(s, "perp_daily")
  shared <- m[m$date == as.Date("2026-01-01"), ]
  expect_true(all(shared$v < 1000L))                                              # local won
  expect_equal(sum(m$v == 1000L), 4L)                                             # the 4 HF-only rows are kept
})

test_that("FALSIFIED: a merge that would drop rows is exit 1 and nothing is uploaded, even with --apply", {
  s <- .setup(); up <- .rec()
  hf <- .mk_table("perp_daily", c("2025-12-30", "2025-12-31"))
  .put(hf, file.path(s$remote, "hyperliquid"), "perp_daily")
  lossy <- function(local_path, hf_path, spec) {
    m <- hl_seed_merge(local_path, hf_path, spec)
    m[-nrow(m), ]                                    # drops the newest row
  }
  r <- .run(s, apply = TRUE, upload = up$fn, merge_fn = lossy)
  expect_equal(r$status, 1L)
  expect_equal(up$st$calls, 0L)
  expect_equal(r$tables$verdict[r$tables$table == "perp_daily"], "FAIL")
  expect_match(r$tables$why[r$tables$table == "perp_daily"], "1 old key")
  # the control: the real merge passes and the upload is made
  up2 <- .rec()
  expect_equal(.run(.setup(), apply = TRUE, upload = up2$fn)$status, 0L)
  expect_equal(up2$st$calls, 1L)
})

test_that("FALSIFIED: while a fetch is running (progress file, live process, or unknown) the seed is exit 3 and reads nothing", {
  s <- .setup(); up <- .rec()
  writeLines("# config: x", file.path(s$data, "hl_progress.txt"))
  r <- .run(s, apply = TRUE, upload = up$fn)
  expect_equal(r$status, 3L); expect_match(r$reason, "hl_progress.txt")
  expect_false(dir.exists(file.path(s$stage, "hyperliquid")))
  file.remove(file.path(s$data, "hl_progress.txt"))
  r2 <- .run(s, apply = TRUE, upload = up$fn, running = function() TRUE)
  expect_equal(r2$status, 3L); expect_match(r2$reason, "process is running")
  r3 <- .run(s, apply = TRUE, upload = up$fn, running = function() NA)
  expect_equal(r3$status, 3L); expect_match(r3$reason, "could not tell")
  expect_equal(up$st$calls, 0L)
  # the control: no marker, nothing running
  expect_equal(.run(s)$status, 0L)
})

test_that("the real process check reads pgrep's exit status: 0 running, 1 not, anything else unknown", {
  bin <- withr::local_tempdir()
  stub <- function(code) {
    p <- file.path(bin, "pgrep"); writeLines(c("#!/bin/sh", paste("exit", code)), p); Sys.chmod(p, "0755")
  }
  withr::local_path(bin, action = "prefix")
  stub(0); expect_true(hl_seed_fetch_running())
  stub(1); expect_false(hl_seed_fetch_running())
  stub(2); expect_true(is.na(hl_seed_fetch_running()))
})

test_that("a required table that is on neither side is exit 3; an optional one is not", {
  s <- .setup()
  file.remove(file.path(s$data, "spot_hourly.parquet"))
  r <- .run(s)
  expect_equal(r$status, 3L)
  expect_equal(r$tables$verdict[r$tables$table == "spot_hourly"], "UNDECIDED")
  # on HF only: fine, the dataset already has it (and the marker will list it)
  .put(.mk_table("spot_hourly"), file.path(s$remote, "hyperliquid"), "spot_hourly")
  r2 <- .run(s)
  expect_equal(r2$status, 0L)
  expect_false("hyperliquid/spot_hourly.parquet" %in% r2$files)       # nothing local to publish
  expect_equal(r2$tables$merged_rows[r2$tables$table == "spot_hourly"], 4L)   # counted from the HF copy
  up <- .rec(); .run(s, apply = TRUE, upload = up$fn)
  expect_true("spot_hourly" %in% names(up$st$marker$tables))                  # and listed in the marker
  expect_equal(r$tables$verdict[r$tables$table == "perp_markets"], "ABSENT")
})

test_that("--apply publishes the staged folder once; a failed or undecided upload is not success", {
  s <- .setup(); up <- .rec(0L)
  r <- .run(s, apply = TRUE, upload = up$fn)
  expect_equal(r$status, 0L); expect_true(r$uploaded); expect_equal(up$st$calls, 1L)
  expect_true("hyperliquid/_seeded.json" %in% up$st$files)
  expect_equal(.run(.setup(), apply = TRUE, upload = .rec(1L)$fn)$status, 1L)
  expect_equal(.run(.setup(), apply = TRUE, upload = .rec(3L)$fn)$status, 3L)
  # a failed preflight (no token, no hf) stops before any work
  s2 <- .setup(); up2 <- .rec()
  r2 <- suppressMessages(hl_seed_run(s2$data, s2$raw, s2$client, stage_dir = s2$stage, apply = TRUE,
                                     running_fn = .never, upload_fn = up2$fn,
                                     preflight_fn = function() "HF_TOKEN is not set"))
  expect_equal(r2$status, 3L); expect_equal(up2$st$calls, 0L)
})

test_that("the marker lists tables, rows and dates and holds no path or host name", {
  s <- .setup(); up <- .rec()
  .run(s, apply = TRUE, upload = up$fn)
  m <- up$st$marker
  expect_equal(m$format, "hl-seed-v1")
  expect_equal(m$tables$perp_daily$rows, 6)
  expect_equal(m$tables$perp_daily$earliest, "2026-01-01")
  expect_equal(m$tables$perp_funding$earliest, "2026-01-01")
  expect_equal(m$raw_days$count, 2)
  txt <- paste(readLines(file.path(s$stage, "hyperliquid", "_seeded.json")), collapse = "")
  expect_false(grepl(s$data, txt, fixed = TRUE))
  expect_false(grepl(Sys.info()[["nodename"]], txt, fixed = TRUE))
  expect_false(grepl(Sys.info()[["user"]], txt, fixed = TRUE))
})

test_that("a raw day whose seed.tar is already on HF is skipped, not overwritten", {
  s <- .setup()
  d <- file.path(s$remote, "hyperliquid", "raw", "weekly", "date=2026-11-15")
  dir.create(d, recursive = TRUE); writeLines("old", file.path(d, "seed.tar"))
  r <- .run(s)
  expect_equal(r$days$action, c("seed.tar already on HF, skipped", "pack"))
  expect_false("hyperliquid/raw/weekly/date=2026-11-15/seed.tar" %in% r$files)
  expect_true("hyperliquid/raw/weekly/date=2026-11-16/seed.tar" %in% r$files)
})

test_that("more files than one commit should carry is exit 3, not a silent split", {
  s <- .setup()
  r <- .run(s, max_files = 3L)
  expect_equal(r$status, 3L); expect_match(r$reason, "splitting is not implemented")
})

test_that("a type clash between the two copies is exit 3, not a guess", {
  s <- .setup()
  hf <- .mk_table("perp_daily"); hf$v <- as.character(hf$v)
  .put(hf, file.path(s$remote, "hyperliquid"), "perp_daily")
  r <- .run(s)
  expect_equal(r$tables$verdict[r$tables$table == "perp_daily"], "UNDECIDED")
  expect_equal(r$status, 3L)
})

test_that("the command line needs both absolute directories and prints them first", {
  s <- .setup()
  expect_equal(suppressMessages(.seed_main(character())), 2L)
  expect_equal(suppressMessages(.seed_main(c("--data-dir=/x"))), 2L)
  expect_equal(suppressMessages(.seed_main(c("--data-dir=rel", paste0("--raw-dir=", s$raw)))), 2L)
  expect_equal(suppressMessages(.seed_main(c(paste0("--data-dir=", s$data), "--raw-dir=/no/such/folder"))), 2L)
  expect_equal(suppressMessages(.seed_main(c(paste0("--data-dir=", s$data), paste0("--raw-dir=", s$raw), "--apply", "--dry-run"))), 2L)
  expect_equal(suppressMessages(.seed_main(c(paste0("--data-dir=", s$data), paste0("--raw-dir=", s$raw), "--bogus"))), 2L)
  out <- suppressMessages(capture.output(code <- .seed_main(
    c(paste0("--data-dir=", s$data), paste0("--raw-dir=", s$raw)),
    client = s$client, running_fn = .never)))
  expect_equal(code, 0L)
  expect_match(out[1], "DRY RUN")
  expect_true(any(grepl(normalizePath(s$data), out, fixed = TRUE)))
  expect_true(any(grepl("nothing was uploaded", out)))
})
