testthat::local_edition(3)
source(here::here("scripts", "poll_hyperliquid_ctx.R"))
source(here::here("scripts", "migrate_hl_ctx_to_daily.R"))

# Daily files, the reader, the legacy migration, gzipped raw replies and the replay
# (#1082). NO network: the post function is injected. The fixture is a real
# metaAndAssetCtxs reply for the builder exchange "xyz", reduced to 3 markets; every
# exchange of these tests answers with it.

.fx_path <- here::here("tests", "testthat", "fixtures", "hyperliquid",
                       "metaandassetctxs_xyz.json")
.text <- paste(readLines(.fx_path, warn = FALSE), collapse = "\n")
.mac <- jsonlite::fromJSON(.text, simplifyVector = FALSE)
.nosleep <- function(s) invisible(NULL)
.ok_post <- function(body) .mac
.utc <- function(x) as.POSIXct(x, tz = "UTC")

# A clock that returns the given times one after the other, then the last one.
.clock <- function(times) {
  i <- 0L
  function() { i <<- min(i + 1L, length(times)); times[[i]] }
}
.poll <- function(post, out, dexes = "xyz", now, collector = "lab-1", ...) {
  suppressMessages(hl_ctx_poll(post, out_dir = out, dexes = dexes, now = now,
                               collector = collector, sleep_fn = .nosleep, ...))
}
.md5 <- function(files) unname(tools::md5sum(files))
.tree <- function(dir) {   # every file under dir with its checksum
  f <- list.files(dir, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  stats::setNames(.md5(f), sub(paste0(dir, "/"), "", f, fixed = TRUE))
}

test_that("a poll writes one file per UTC day and collector, and no single file", {
  out <- withr::local_tempdir()
  expect_equal(.poll(.ok_post, out, now = .clock(.utc("2026-11-22 12:07:31.5")))$status, 0L)
  f <- hl_ctx_files(out)
  expect_equal(sub(paste0(out, "/"), "", f, fixed = TRUE),
               "perp_ctx_5m/date=2026-11-22/lab-1.parquet")
  expect_false(file.exists(file.path(out, HL_CTX_LEGACY_FILE)))
  # the label (env var HL_POLL_COLLECTOR) names the file and fills the column
  withr::local_envvar(HL_POLL_COLLECTOR = "lab-7")
  out3 <- withr::local_tempdir()
  suppressMessages(hl_ctx_poll(.ok_post, out_dir = out3, dexes = "xyz", sleep_fn = .nosleep,
                               now = .clock(.utc("2026-11-22 12:07:31.5"))))
  expect_match(hl_ctx_files(out3), "date=2026-11-22/lab-7\\.parquet$")
  expect_equal(unique(hl_ctx_read(out3)$collector), "lab-7")
  # a collector name is made safe for a file name
  out2 <- withr::local_tempdir()
  .poll(.ok_post, out2, now = .clock(.utc("2026-11-22 12:07:31.5")), collector = "Pi 1/x")
  expect_match(hl_ctx_files(out2), "date=2026-11-22/Pi_1_x\\.parquet$")
  expect_equal(hl_ctx_collector_tag(c("a", "", NA)), c("a", "unknown", "unknown"))
})

test_that("a run that straddles midnight UTC writes two files, each with its own day", {
  out <- withr::local_tempdir()
  now <- .clock(c(.utc("2026-11-22 23:59:58"), .utc("2026-11-23 00:00:02")))
  r <- .poll(.ok_post, out, dexes = c("xyz", "flx"), now = now)
  expect_equal(r$status, 0L)
  f <- hl_ctx_files(out)
  expect_equal(basename(dirname(f)), c("date=2026-11-22", "date=2026-11-23"))
  d1 <- arrow::read_parquet(f[1]); d2 <- arrow::read_parquet(f[2])
  expect_equal(c(nrow(d1), nrow(d2)), c(3L, 3L))
  expect_equal(unique(d1$dex), "xyz")
  expect_equal(unique(d2$dex), "flx")
  expect_true(all(format(d1$fetched_at, "%Y-%m-%d", tz = "UTC") == "2026-11-22"))
  expect_true(all(format(d2$fetched_at, "%Y-%m-%d", tz = "UTC") == "2026-11-23"))
  # the reader sees all six rows once
  expect_equal(nrow(hl_ctx_read(out)), 6L)
})

test_that("yesterday's file is byte-identical after today's poll", {
  out <- withr::local_tempdir()
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 23:55:00")))
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 23:58:00.25")))
  yesterday <- hl_ctx_files(out)
  expect_length(yesterday, 1L)
  before <- .md5(yesterday)
  .poll(.ok_post, out, now = .clock(.utc("2026-11-23 00:01:00")))
  .poll(.ok_post, out, now = .clock(.utc("2026-11-23 00:06:00")))
  expect_equal(.md5(yesterday), before)
  expect_length(hl_ctx_files(out), 2L)
  expect_equal(nrow(hl_ctx_read(out)), 12L)
  # Red: a poll of the SAME day does change that day's file
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 23:59:00")))
  expect_false(identical(.md5(yesterday), before))
})

test_that("the reader unites old files without is_delisted with new ones", {
  out <- withr::local_tempdir()
  .poll(.ok_post, out, now = .clock(.utc("2026-11-21 10:00:00")))
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 10:00:00")))
  files <- hl_ctx_files(out)
  old <- arrow::read_parquet(files[1])
  old$is_delisted <- NULL                      # the pre-#1084 schema, and the OLDEST file
  arrow::write_parquet(old, files[1])
  x <- hl_ctx_read(out)
  expect_equal(nrow(x), 6L)
  expect_true("is_delisted" %in% names(x))
  expect_equal(sum(is.na(x$is_delisted)), 3L)  # the old file's rows
  expect_equal(sum(!is.na(x$is_delisted)), 3L)
  # Why unify_schemas = TRUE is needed (measured with arrow 23): without it the
  # schema of the FIRST file wins and the column is silently dropped.
  plain <- arrow::open_dataset(files, format = "parquet")
  expect_false("is_delisted" %in% names(plain))
  expect_true("is_delisted" %in% names(hl_ctx_open(out)))
  # a leftover .tmp of a killed write and the legacy single file are never read
  writeLines("not parquet", paste0(files[2], ".tmp"))
  arrow::write_parquet(x[1:2, ], file.path(out, HL_CTX_LEGACY_FILE))
  expect_equal(nrow(hl_ctx_read(out)), 6L)
  # no files at all is an error with a class, not an empty table
  expect_error(hl_ctx_read(withr::local_tempdir()), class = "hl_ctx_empty")
})

# ── migration of the legacy single file ─────────────────────────────
.make_legacy <- function(dir) {
  rows <- dplyr::bind_rows(
    hl_parse_ctx(.mac, "xyz", .utc("2026-11-21 23:55:00.125"), "hostA"),
    hl_parse_ctx(.mac, "xyz", .utc("2026-11-22 00:00:00.5"), "hostA"),
    hl_parse_ctx(.mac, "xyz", .utc("2026-11-22 00:05:00.75"), "hostA"),
    hl_parse_ctx(.mac, "flx", .utc("2026-11-22 00:05:01"), "hostB"))
  rows$is_delisted[1:3] <- NA                  # rows from before #1084
  path <- file.path(dir, HL_CTX_LEGACY_FILE)
  arrow::write_parquet(rows, path)
  path
}

test_that("migration dry-run (the default) changes nothing", {
  out <- withr::local_tempdir()
  legacy <- .make_legacy(out)
  before <- .tree(out)
  res <- suppressMessages(hl_ctx_migrate_legacy(legacy, out, collector = "lab-1"))
  expect_equal(res$status, 0L)
  expect_false(res$applied)
  expect_equal(res$n_legacy, 12L)
  expect_equal(nrow(res$plan), 2L)             # one file per day: the label replaces both hosts
  expect_equal(res$n_legacy_collectors, 2L)
  expect_equal(sum(res$plan$n_new), 12L)
  expect_equal(.tree(out), before)             # not one byte written
  expect_false(dir.exists(file.path(out, HL_CTX_DIR)))
  # the command line: no flag = dry run; both flags = usage; a missing file = 3
  args <- c(paste0("--out-dir=", out), "--collector=lab-1")
  capture.output(st <- suppressMessages(.migrate_main(args)))
  expect_equal(st, 0L)
  expect_equal(.tree(out), before)
  expect_equal(suppressMessages(.migrate_main(c("--apply", "--dry-run", args))), 2L)
  expect_equal(suppressMessages(.migrate_main("--bogus")), 2L)
  capture.output(st3 <- suppressMessages(.migrate_main(paste0("--out-dir=", withr::local_tempdir()))))
  expect_equal(st3, 3L)
})

test_that("migration --apply on a copy matches counts, keys and values; the legacy file stays", {
  out <- withr::local_tempdir()
  legacy <- .make_legacy(out)
  legacy_md5 <- .md5(legacy)
  old <- as.data.frame(arrow::read_parquet(legacy))
  old$collector <- "lab-1"                     # what the migration maps the host names to
  capture.output(res <- suppressMessages(hl_ctx_migrate_legacy(legacy, out, apply = TRUE, collector = "lab-1")))
  expect_equal(res$status, 0L)
  expect_equal(res$reason, "")
  expect_true(res$applied)
  expect_equal(.md5(legacy), legacy_md5)       # not deleted, moved or changed
  expect_equal(unique(as.data.frame(arrow::read_parquet(legacy))$collector), c("hostA", "hostB"))
  expect_equal(unique(hl_ctx_read(out)$collector), "lab-1")   # no host name in the daily files
  f <- hl_ctx_files(out)
  expect_equal(sub(paste0(out, "/"), "", f, fixed = TRUE),
               c("perp_ctx_5m/date=2026-11-21/lab-1.parquet",
                 "perp_ctx_5m/date=2026-11-22/lab-1.parquet"))
  x <- hl_ctx_read(out)
  expect_equal(nrow(x), nrow(old))
  expect_setequal(.mig_key(x), .mig_key(old))
  expect_equal(anyDuplicated(.mig_key(x)), 0L)
  ord <- function(d) d[do.call(order, unname(as.list(d[HL_CTX_KEYS]))), names(old)] |>
    `rownames<-`(NULL)
  expect_equal(ord(x), ord(old), ignore_attr = TRUE)
  # a second --apply is harmless: every row is an overlap, nothing doubles
  capture.output(res2 <- suppressMessages(hl_ctx_migrate_legacy(legacy, out, apply = TRUE, collector = "lab-1")))
  expect_equal(res2$status, 0L)
  expect_equal(sum(res2$plan$n_overlap), 12L)
  expect_equal(nrow(hl_ctx_read(out)), 12L)
})

test_that("migration meets a daily file the poller already wrote: no double count, no loss", {
  out <- withr::local_tempdir()
  legacy <- .make_legacy(out)
  # the new poller already polled 2026-11-22 00:05:00.75 (a key the legacy file holds)
  # and one later moment the legacy file does not have
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 00:05:00.75")))
  .poll(.ok_post, out, now = .clock(.utc("2026-11-22 00:10:00")))
  expect_equal(nrow(hl_ctx_read(out)), 6L)
  capture.output(res <- suppressMessages(hl_ctx_migrate_legacy(legacy, out, apply = TRUE, collector = "lab-1")))
  expect_equal(res$status, 0L)
  expect_equal(sum(res$plan$n_overlap), 3L)
  expect_equal(nrow(hl_ctx_read(out)), 12L + 3L)   # 12 legacy + the 3 new rows, 3 overlaps once
  # Red: a corrupted write is caught (verification is not a no-op)
  out2 <- withr::local_tempdir()
  legacy2 <- .make_legacy(out2)
  broken <- function(new, path, keys) {
    new$mid_px <- new$mid_px + 1                  # the "write" changes values
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(new, path)
  }
  capture.output(res3 <- suppressMessages(
    hl_ctx_migrate_legacy(legacy2, out2, apply = TRUE, collector = "lab-1", upsert_fn = broken)))
  expect_equal(res3$status, 1L)
  expect_match(res3$reason, "values differ")
})

