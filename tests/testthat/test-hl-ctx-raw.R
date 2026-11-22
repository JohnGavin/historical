testthat::local_edition(3)
source(here::here("scripts", "poll_hyperliquid_ctx.R"))

# One gzipped raw file per run of the 5-minute poller, and the replay that rebuilds a
# day's parquet from those files (#1082). NO network: the post function is injected.
# The fixture is a real metaAndAssetCtxs reply for the builder exchange "xyz", reduced
# to 3 markets; every exchange of these tests answers with it.

.fx_path <- here::here("tests", "testthat", "fixtures", "hyperliquid",
                       "metaandassetctxs_xyz.json")
.text <- paste(readLines(.fx_path, warn = FALSE), collapse = "\n")
.mac <- jsonlite::fromJSON(.text, simplifyVector = FALSE)
.nosleep <- function(s) invisible(NULL)
.utc <- function(x) as.POSIXct(x, tz = "UTC")
.md5 <- function(files) unname(tools::md5sum(files))

# A clock that returns the given times one after the other, then the last one.
.clock <- function(times) {
  i <- 0L
  function() { i <<- min(i + 1L, length(times)); times[[i]] }
}
.poll <- function(post, out, dexes = "xyz", now, collector = "lab-1", ...) {
  suppressMessages(hl_ctx_poll(post, out_dir = out, dexes = dexes, now = now,
                               collector = collector, sleep_fn = .nosleep, ...))
}
.fake_post <- function(body, ..., on_response = NULL) {
  txt <- if (identical(body$dex, "bad")) "[1]" else .text   # "bad": a reply that will not parse
  if (!is.null(on_response)) on_response(body, txt)
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}
.capture_post <- function(raw) {
  hl_make_post(raw, post = .fake_post, sleep_fn = .nosleep, max_attempts = 1L, capture_raw = TRUE)
}

test_that("hl_make_post writes per-reply files as before, or hands the text to the caller", {
  raw <- withr::local_tempdir()
  weekly <- hl_make_post(raw, post = .fake_post, sleep_fn = .nosleep, max_attempts = 1L)
  res <- weekly(list(type = "metaAndAssetCtxs", dex = "xyz"))
  expect_null(attr(res, "raw_text"))
  expect_equal(list.files(raw, recursive = TRUE),
               paste0(format(Sys.time(), "%Y-%m-%d", tz = "UTC"), "/metaAndAssetCtxs_xyz_na.json"))
  raw2 <- withr::local_tempdir()
  res2 <- .capture_post(raw2)(list(type = "metaAndAssetCtxs", dex = "xyz"))
  expect_equal(attr(res2, "raw_text"), .text)             # the exact reply text
  expect_length(list.files(raw2, recursive = TRUE), 0L)   # and no file of its own
  expect_equal(res2, res, ignore_attr = TRUE)
})

test_that("one poll writes ONE gzip file with every reply, atomically, never overwritten", {
  raw <- withr::local_tempdir()
  out <- withr::local_tempdir()
  post <- .capture_post(raw)
  r <- .poll(post, out, dexes = c("xyz", "flx"), raw_dir = raw,
             now = .clock(c(.utc("2026-11-22 12:07:31.5"), .utc("2026-11-22 12:07:32.25"))))
  expect_equal(r$status, 0L)
  files <- list.files(raw, recursive = TRUE)
  expect_equal(files, "ctx_poll/2026-11-22/lab-1_120731.json.gz")   # no other file anywhere
  path <- file.path(raw, files)
  expect_equal(readBin(path, "raw", 2L), as.raw(c(0x1f, 0x8b)))     # gzip magic bytes
  text <- hl_ctx_raw_text(path)
  expect_lt(file.size(path), nchar(text, type = "bytes"))
  # the exact reply text sits in it, once per reply
  expect_equal(lengths(regmatches(text, gregexpr(.text, text, fixed = TRUE))), 2L)
  doc <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  expect_equal(doc$collector, "lab-1")
  expect_equal(vapply(doc$replies, function(x) x$dex, ""), c("xyz", "flx"))
  expect_equal(vapply(doc$replies, function(x) x$fetched_at_us, ""),
               sprintf("%.0f", as.numeric(c(.utc("2026-11-22 12:07:31.5"),
                                            .utc("2026-11-22 12:07:32.25"))) * 1e6))
  expect_equal(doc$replies[[1]]$reply, .mac)                          # round trip
  # a second run in the same second: a counter, the first file is untouched
  before <- .md5(path)
  .poll(post, out, dexes = "xyz", raw_dir = raw, now = .clock(.utc("2026-11-22 12:07:31.9")))
  expect_equal(sort(list.files(raw, recursive = TRUE)),
               c("ctx_poll/2026-11-22/lab-1_120731.json.gz", "ctx_poll/2026-11-22/lab-1_120731_1.json.gz"))
  expect_equal(.md5(path), before)
})

test_that("replay matches the poller, across midnight, and never reads other scripts' raw files", {
  raw <- withr::local_tempdir()
  out <- withr::local_tempdir()
  post <- .capture_post(raw)
  runs <- list(c("2026-11-22 23:50:00.123456", "2026-11-22 23:50:01"),
               c("2026-11-22 23:59:59", "2026-11-23 00:00:01.5"),   # crosses 00:00 UTC
               c("2026-11-23 00:05:00.75", "2026-11-23 00:05:02"))
  for (tt in runs) {
    r <- .poll(post, out, dexes = c("xyz", "flx"), raw_dir = raw, now = .clock(.utc(tt)))
    expect_equal(r$status, 0L)
  }
  # the crossing run is ONE raw file, in the folder of its first reply; the parquet
  # is split by each row's own fetched_at
  expect_equal(sort(list.files(raw, recursive = TRUE)),
               c("ctx_poll/2026-11-22/lab-1_235000.json.gz", "ctx_poll/2026-11-22/lab-1_235959.json.gz",
                 "ctx_poll/2026-11-23/lab-1_000500.json.gz"))
  # another script's metaAndAssetCtxs replies sit in the same day folders, under the
  # names fetch_hyperliquid.R uses, with values that would show if they leaked
  other <- gsub("0", "7", .text, fixed = TRUE)
  for (d in c("2026-11-22", "2026-11-23")) {
    dir.create(file.path(raw, d))
    writeLines(other, file.path(raw, d, "metaAndAssetCtxs_xyz_na.json"))
    gz <- gzfile(file.path(raw, d, "metaAndAssetCtxs_xyz_na_235959.json.gz"), "wb")
    writeLines(other, gz)
    close(gz)
    writeLines(other, file.path(raw, d, "metaAndAssetCtxs_all_na_000500.json"))
  }
  polled <- hl_ctx_read(out)
  expect_equal(nrow(polled), 18L)
  dates <- format(polled$fetched_at, "%Y-%m-%d", tz = "UTC")
  expect_equal(sort(unique(dates)), c("2026-11-22", "2026-11-23"))
  for (d in unique(dates)) {
    out2 <- withr::local_tempdir()
    rp <- hl_ctx_replay_day(d, raw, out2)
    want <- polled[dates == d, ] |> `rownames<-`(NULL)
    expect_equal(rp$n_rows, nrow(want))
    expect_identical(hl_ctx_read(out2), want)       # same rows, same values, same types
    expect_equal(rp$n_failed_replies, 0L)
    live <- hl_ctx_files(out)
    expect_equal(sub(out2, "", rp$paths, fixed = TRUE),
                 sub(out, "", live[basename(dirname(live)) == paste0("date=", d)], fixed = TRUE))
  }
  # the foreign files are not counted: only the 3 run files are seen
  expect_equal(hl_ctx_replay_day("2026-11-22", raw, withr::local_tempdir())$n_files, 3L)
  # a date with no data is empty, not an error
  expect_equal(hl_ctx_replay_day("2026-01-01", raw, withr::local_tempdir())$n_rows, 0L)
})

test_that("a reply that fails to parse is kept in the raw file, counted, not replayed", {
  raw <- withr::local_tempdir()
  out <- withr::local_tempdir()
  r <- .poll(.capture_post(raw), out, dexes = c("xyz", "bad"), raw_dir = raw,
             now = .clock(c(.utc("2026-11-22 12:00:00"), .utc("2026-11-22 12:00:01"))))
  expect_equal(r$status, 3L)                                  # partial run
  f <- list.files(raw, recursive = TRUE, full.names = TRUE)
  expect_length(f, 1L)
  doc <- jsonlite::fromJSON(hl_ctx_raw_text(f), simplifyVector = FALSE)
  expect_equal(vapply(doc$replies, function(x) x$ok, TRUE), c(TRUE, FALSE))
  rp <- hl_ctx_replay_day("2026-11-22", raw, withr::local_tempdir())
  expect_equal(c(rp$n_rows, rp$n_failed_replies), c(3L, 1L))
  expect_equal(rp$n_rows, nrow(hl_ctx_read(out)))
})

test_that("a raw file that cannot be written makes the run 3 but the rows are kept", {
  blocker <- withr::local_tempfile()
  writeLines("a file, not a folder", blocker)
  out <- withr::local_tempdir()
  r <- suppressWarnings(.poll(.capture_post(blocker), out, raw_dir = blocker,
                              now = .clock(.utc("2026-11-22 12:00:00"))))
  expect_equal(r$status, 3L)
  expect_match(r$reason, "raw file not written")
  expect_equal(nrow(hl_ctx_read(out)), 3L)
})
