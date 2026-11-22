testthat::local_edition(3)
source(here::here("scripts", "drain_hl_ctx_kv.R"))

# The daily drain of the Cloudflare KV buffer (#1088). NO network: the client (KV store
# and Hugging Face folder) is a fake, the values are framed as the Worker frames them
# from recorded Hyperliquid replies (tests/testthat/fixtures/hl_ctx_collector/).

.entry <- function(slot_id, replies = .hl_ok_replies(), ...) {
  list(status = 200L, body = .hl_kv_value(slot_id, replies, ...))
}
.key <- function(slot_id) paste0("ctx/", slot_id)
.entries <- function(ids, ...) stats::setNames(lapply(ids, .entry, ...), .key(ids))
.run <- function(client, stage, now_s = as.numeric(as.POSIXct("2026-11-22 14:00:00", tz = "UTC"))) {
  suppressMessages(hl_drain_run(client, stage, work_dir = withr::local_tempdir(.local_envir = parent.frame()),
                                now = function() as.POSIXct(now_s, origin = "1970-01-01", tz = "UTC")))
}
.stage_rows <- function(stage) hl_ctx_read(file.path(stage, "hyperliquid"), one_collector_per_slot = FALSE)

test_that("a value unframes to its header and bodies, byte for byte", {
  v <- .hl_kv_value("2026-11-22/1205", .hl_ok_replies())
  u <- hl_drain_unframe(v)
  expect_equal(u$header$slot, "2026-11-22T12:05:00.000Z")
  expect_equal(vapply(u$header$replies, function(r) r$dex, ""), c("xyz", "flx"))
  expect_identical(u$bodies[[1]], .hlfx("metaandassetctxs_xyz.json"))
  expect_identical(u$bodies[[2]], .hlfx("metaandassetctxs_flx.json"))
  # a marker (perpDexs failed): header only, no replies
  m <- hl_drain_unframe(.hl_kv_value("2026-11-22/1205", list(), perp_ok = FALSE))
  expect_length(m$bodies, 0L)
  expect_false(m$header$perp_dexs$ok)
})

test_that("a corrupt value is refused with a class, never half-read", {
  v <- .hl_kv_value("2026-11-22/1205", .hl_ok_replies())
  bad <- list(
    "empty" = raw(0),
    "no newline" = charToRaw("{}"),
    "header is not JSON" = c(charToRaw("not json\n"), v[1:5]),
    "short body" = v[-length(v)],
    "stray bytes" = c(v, as.raw(1L)),
    "unknown format" = c(charToRaw('{"format":"x","collector":"cf-1","slot":"2026-11-22T12:05:00.000Z","replies":[]}\n')),
    "malformed reply entry" = c(charToRaw(paste0('{"format":"hl-ctx-v1","collector":"cf-1","slot":"2026-11-22T12:05:00.000Z",',
                                                 '"replies":[{"dex":"a"}]}\n'))))
  for (nm in names(bad)) {
    expect_error(hl_drain_unframe(bad[[nm]]), class = "hl_drain_corrupt", info = nm)
  }
})

test_that("a document keeps ok replies as sent and marks the rest ok:false, on ONE line", {
  replies <- list(
    list(dex = "xyz", status = 200L, body = c(.hlfx("metaandassetctxs_xyz.json"), charToRaw("\n \n")), offset_s = 1),
    list(dex = "flx", status = 429L, body = raw(0), offset_s = 2),           # HTML rate-limit page, dropped by the Worker
    list(dex = "bad", status = 200L, body = charToRaw("<html>200 but not JSON</html>"), offset_s = 3),
    list(dex = "odd", status = 200L, body = charToRaw('{"error":"x"}'), offset_s = 4))  # JSON, not [meta, ctxs]
  u <- hl_drain_unframe(.hl_kv_value("2026-11-22/1205", replies))
  d <- hl_drain_doc(u$header, u$bodies)
  expect_false(grepl("\n", d$line, fixed = TRUE))
  expect_match(d$line, '^\\{"collector":"cf-1","slot":"2026-11-22T12:05:00.000Z"')
  doc <- jsonlite::fromJSON(d$line, simplifyVector = FALSE)
  expect_equal(vapply(doc$replies, function(r) r$ok, TRUE), c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(vapply(doc$replies, function(r) r$status, 1L), c(200L, 429L, 200L, 200L))
  expect_null(doc$replies[[2]]$reply)                                 # no body at all
  expect_match(doc$replies[[3]]$reply, "200 but not JSON")            # kept for audit, as a string
  expect_equal(doc$replies[[1]]$reply, jsonlite::fromJSON(rawToChar(.hlfx("metaandassetctxs_xyz.json")),
                                                          simplifyVector = FALSE))
  expect_equal(c(d$n_ok, d$n_failed), c(1L, 3L))
  expect_equal(nrow(dplyr::bind_rows(d$frames)), 4L)                  # the one good reply: 4 markets
})

test_that("a drain stages one raw file and one parquet per day, and replay reproduces the parquet", {
  stage <- withr::local_tempdir()
  remote <- withr::local_tempdir()
  ids <- c("2026-11-21/1200", "2026-11-21/1205", "2026-11-21/1210", "2026-11-22/1200", "2026-11-22/1205")
  client <- .hl_fake_client(.entries(ids), remote)
  r <- .run(client, stage)
  expect_equal(r$status, 0L)
  expect_equal(r$days$built, c(3L, 2L))
  expect_equal(r$staged, c(
    "hyperliquid/perp_ctx_5m/date=2026-11-21/cf-1.parquet", "hyperliquid/perp_ctx_5m/date=2026-11-22/cf-1.parquet",
    "hyperliquid/raw/ctx_poll/date=2026-11-21/cf-1.jsonl.gz", "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz"))
  rows <- .stage_rows(stage)
  expect_equal(nrow(rows), 5L * 8L)                                   # 5 slots x (4 + 4) markets
  expect_equal(unique(rows$collector), "cf-1")
  expect_false(anyDuplicated(rows[c("dex", "coin", "fetched_at")]) > 0L)
  # one document per slot, in slot order
  lines <- hl_drain_read_lines(file.path(stage, "hyperliquid/raw/ctx_poll/date=2026-11-21/cf-1.jsonl.gz"))
  expect_equal(hl_drain_line_slot_ids(lines), ids[1:3])
  # replay from the raw files alone reproduces each day's parquet exactly
  dates <- format(rows$fetched_at, "%Y-%m-%d", tz = "UTC")
  for (d in unique(dates)) {
    out2 <- withr::local_tempdir()
    rp <- hl_ctx_replay_day_jsonl(d, file.path(stage, "hyperliquid", "raw"), out2)
    want <- rows[dates == d, ] |> `rownames<-`(NULL)
    expect_equal(rp$n_rows, nrow(want))
    expect_identical(hl_ctx_read(out2, one_collector_per_slot = FALSE), want)
    expect_equal(rp$n_failed_replies, 0L)
  }
  # Red: replay of a day whose raw file is truncated does NOT equal the parquet
  out3 <- withr::local_tempdir()
  raw_dir <- withr::local_tempdir()
  dir.create(file.path(raw_dir, "ctx_poll", "date=2026-11-21"), recursive = TRUE)
  hl_drain_write_lines(lines[1:2], file.path(raw_dir, "ctx_poll", "date=2026-11-21", "cf-1.jsonl.gz"))
  rp3 <- hl_ctx_replay_day_jsonl("2026-11-21", raw_dir, out3)
  expect_lt(rp3$n_rows, sum(dates == "2026-11-21"))
})

test_that("a second run over the same KV and a filled HF reads no value and stages nothing", {
  stage <- withr::local_tempdir()
  remote <- withr::local_tempdir()
  ids <- c("2026-11-21/1200", "2026-11-22/1200", "2026-11-22/1205")
  client <- .hl_fake_client(.entries(ids), remote)
  expect_equal(.run(client, stage)$status, 0L)
  .hl_publish(stage, remote)
  state <- attr(client, "state")
  state$gets <- character()
  stage2 <- withr::local_tempdir()
  r2 <- .run(client, stage2)
  expect_equal(r2$status, 0L)
  expect_length(state$gets, 0L)                       # nothing was read from KV
  expect_length(r2$staged, 0L)                        # and nothing is to upload
  expect_equal(r2$days$built, c(0L, 0L))
  expect_equal(r2$days$hf, r2$days$kv)
})

test_that("a day HF holds in part gets only its missing slots, merged without duplicates", {
  remote <- withr::local_tempdir()
  stage1 <- withr::local_tempdir()
  first <- c("2026-11-22/1200", "2026-11-22/1210")
  expect_equal(.run(.hl_fake_client(.entries(first), remote), stage1)$status, 0L)
  .hl_publish(stage1, remote)
  # later KV also holds the 12:05 slot (the earlier run never saw it) plus a 12:15 one
  all_ids <- c("2026-11-22/1200", "2026-11-22/1205", "2026-11-22/1210", "2026-11-22/1215")
  client <- .hl_fake_client(.entries(all_ids), remote)
  stage2 <- withr::local_tempdir()
  r <- .run(client, stage2)
  expect_equal(r$status, 0L)
  expect_equal(sort(attr(client, "state")$gets), sort(.key(c("2026-11-22/1205", "2026-11-22/1215"))))
  lines <- hl_drain_read_lines(file.path(stage2, "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz"))
  expect_equal(hl_drain_line_slot_ids(lines), all_ids)               # old + new, in order, once each
  rows <- .stage_rows(stage2)
  expect_equal(nrow(rows), 4L * 8L)
  expect_false(anyDuplicated(rows[c("dex", "coin", "fetched_at")]) > 0L)
  # the merged day equals a fresh build of all four slots
  stage3 <- withr::local_tempdir()
  .run(.hl_fake_client(.entries(all_ids), withr::local_tempdir()), stage3)
  expect_identical(.stage_rows(stage2), .stage_rows(stage3))
})

test_that("a slot that only failed is recorded and not read again", {
  remote <- withr::local_tempdir()
  stage <- withr::local_tempdir()
  entries <- c(.entries("2026-11-22/1200"),
               stats::setNames(list(.entry("2026-11-22/1205", list(), perp_ok = FALSE)), .key("2026-11-22/1205")),
               stats::setNames(list(.entry("2026-11-22/1210", list(list(dex = "xyz", status = 429L, body = raw(0))))),
                               .key("2026-11-22/1210")))
  client <- .hl_fake_client(entries, remote)
  r <- .run(client, stage)
  expect_equal(r$status, 0L)
  expect_equal(r$days$built, 3L)
  expect_equal(nrow(.stage_rows(stage)), 8L)                          # only the good slot made rows
  lines <- hl_drain_read_lines(file.path(stage, "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz"))
  expect_length(lines, 3L)                                            # all three slots are in the ledger
  expect_match(lines[2], '"perp_dexs_ok":false')
  .hl_publish(stage, remote)
  attr(client, "state")$gets <- character()
  r2 <- .run(client, withr::local_tempdir())
  expect_length(attr(client, "state")$gets, 0L)
  expect_equal(r2$status, 0L)
})

test_that("a reply fetched after midnight goes to the next day's parquet, seeded from HF", {
  remote <- withr::local_tempdir()
  # day 22 already on HF with one slot
  s0 <- withr::local_tempdir()
  .run(.hl_fake_client(.entries("2026-11-23/0000"), remote), s0)
  .hl_publish(s0, remote)
  # slot 23:55 of the 22nd whose xyz reply arrived 5 min 2 s late, i.e. on the 23rd
  late <- list(list(dex = "xyz", status = 200L, body = .hlfx("metaandassetctxs_xyz.json"), offset_s = 302))
  client <- .hl_fake_client(c(.entries("2026-11-23/0000"), stats::setNames(list(.entry("2026-11-22/2355", late)), .key("2026-11-22/2355"))), remote)
  stage <- withr::local_tempdir()
  r <- .run(client, stage)
  expect_equal(r$status, 0L)
  expect_true(file.exists(file.path(stage, "hyperliquid/perp_ctx_5m/date=2026-11-23/cf-1.parquet")))
  expect_false(file.exists(file.path(stage, "hyperliquid/perp_ctx_5m/date=2026-11-22/cf-1.parquet")))  # no rows on the 22nd
  expect_equal(nrow(.stage_rows(stage)), 8L + 4L)       # the seeded 23rd-00:00 rows + the late reply
})

test_that("an unreadable, corrupt or vanished key makes the run 1, and the rest is still staged", {
  ids <- c("2026-11-22/1200", "2026-11-22/1205", "2026-11-22/1210", "2026-11-22/1215", "2026-11-22/1220")
  e <- .entries(ids)
  e[[.key(ids[2])]] <- list(error = TRUE)                                     # connection error
  e[[.key(ids[3])]] <- list(status = 500L)                                    # server error
  e[[.key(ids[4])]]$body <- e[[.key(ids[4])]]$body[-1]                        # corrupt: header cut
  r <- .run(.hl_fake_client(e, withr::local_tempdir()), stage <- withr::local_tempdir())
  expect_equal(r$status, 1L)
  expect_equal(c(r$days$built, r$days$unreadable, r$days$corrupt), c(2L, 2L, 1L))
  expect_equal(nrow(.stage_rows(stage)), 2L * 8L)
  # a value filed under the wrong slot is corrupt too
  e2 <- .entries("2026-11-22/1200")
  e2[[.key("2026-11-22/1200")]]$body <- .hl_kv_value("2026-11-22/1205", .hl_ok_replies())
  expect_equal(.run(.hl_fake_client(e2, withr::local_tempdir()), withr::local_tempdir())$status, 1L)
  # a 404 on a key far from expiry is a failure; one about to expire is not
  now_s <- as.numeric(as.POSIXct("2026-11-22 14:00:00", tz = "UTC"))
  gone <- list(status = 404L, expiration = now_s + 5 * 86400)
  expiring <- list(status = 404L, expiration = now_s + 600)
  ok <- .entries("2026-11-22/1200")
  c_gone <- .hl_fake_client(c(ok, stats::setNames(list(gone), .key("2026-11-22/1205"))), withr::local_tempdir())
  expect_equal(.run(c_gone, withr::local_tempdir())$status, 1L)
  c_exp <- .hl_fake_client(c(ok, stats::setNames(list(expiring), .key("2026-11-22/1205"))), withr::local_tempdir())
  r_exp <- .run(c_exp, withr::local_tempdir())
  expect_equal(r_exp$status, 0L)
  expect_equal(r_exp$days$expired, 1L)
})

test_that("when HF cannot be read for a day the run is 3, never 0; a failed key still outranks it with 1", {
  ids <- c("2026-11-21/1200", "2026-11-22/1200")
  client <- .hl_fake_client(.entries(ids), withr::local_tempdir())
  attr(client, "state")$hf_fail <- "date=2026-11-21"
  stage <- withr::local_tempdir()
  r <- .run(client, stage)
  expect_equal(r$status, 3L)
  expect_match(r$undecided, "2026-11-21")
  expect_equal(r$days$built, c(0L, 1L))                 # the other day was still done
  e <- .entries(ids)
  e[[.key(ids[2])]] <- list(status = 500L)
  client2 <- .hl_fake_client(e, withr::local_tempdir())
  attr(client2, "state")$hf_fail <- "date=2026-11-21"
  expect_equal(.run(client2, withr::local_tempdir())$status, 1L)
})

test_that("keys that are not ours are ignored, not read", {
  e <- c(.entries("2026-11-22/1200"), list("other/key" = list(status = 200L, body = raw(0)),
                                           "ctx/2026-11-22/12" = list(status = 200L, body = raw(0))))
  client <- .hl_fake_client(e, withr::local_tempdir())
  r <- .run(client, withr::local_tempdir())
  expect_equal(r$status, 0L)
  expect_equal(attr(client, "state")$gets, .key("2026-11-22/1200"))
})

test_that("the KV requests are paced under the window limit", {
  clock <- 0
  times <- numeric()
  pace <- hl_drain_pacer(max_requests = 5L, window_s = 10, now = function() clock,
                         sleep = function(s) clock <<- clock + s)
  for (i in 1:23) {
    pace()
    times <- c(times, clock)
    clock <- clock + 0.1                                # a request takes 0.1 s
  }
  # never more than 5 requests in any 10 s window
  worst <- max(vapply(times, function(t) sum(times >= t & times < t + 10), 1))
  expect_lte(worst, 5)
  expect_gt(max(times), 30)                             # it did have to wait: 23 requests need >= 4 windows
  # Red: the same loop without the pacer breaks the limit
  burst <- seq(0, by = 0.1, length.out = 23)
  expect_gt(max(vapply(burst, function(t) sum(burst >= t & burst < t + 10), 1)), 5)
})

test_that("the command line: usage 2, not configured 3 (secrets never printed), configured with a fake client", {
  expect_equal(suppressMessages(.drain_main("--bogus")), 2L)
  expect_equal(suppressMessages(.drain_main(character(), env = function(v, unset) "")), 3L)
  msg <- testthat::capture_messages(.drain_main(character(), env = function(v, unset) if (v == "CF_API_TOKEN") "" else "SECRET-ACCOUNT"))
  expect_match(paste(msg, collapse = ""), "CF_API_TOKEN")
  expect_false(grepl("SECRET-ACCOUNT", paste(msg, collapse = ""), fixed = TRUE))
  out <- withr::local_tempdir()
  client <- .hl_fake_client(.entries("2026-11-22/1200"), withr::local_tempdir())
  printed <- capture.output(st <- suppressMessages(.drain_main(paste0("--out-dir=", out), client = client)))
  expect_gt(length(printed), 0L)                         # the per-day table
  expect_equal(st, 0L)
  expect_true(file.exists(file.path(out, "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz")))
  # a client that cannot list KV is INDETERMINATE
  broken <- list(kv_list = function(prefix) stop("KV key list failed (HTTP 403)"))
  expect_equal(suppressMessages(.drain_main(paste0("--out-dir=", out), client = broken)), 3L)
})
