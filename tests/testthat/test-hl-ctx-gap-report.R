testthat::local_edition(3)
source(here::here("scripts", "hl_ctx_gap_report.R"))

# The gap report (#1088): slots due vs on HF vs in KV, per UTC day. NO network: fake
# client; "HF" is a folder holding each day's raw file, whose lines are the slot ledger.

.now <- as.POSIXct("2026-11-22 14:00:00", tz = "UTC")   # with the 60 min lag, slots are due up to 13:00
.slots <- function(day, from = "0000", to = "2355") {
  t <- seq(as.POSIXct(paste(day, substr(from, 1, 2), substr(from, 3, 4)), format = "%Y-%m-%d %H %M", tz = "UTC"),
           as.POSIXct(paste(day, substr(to, 1, 2), substr(to, 3, 4)), format = "%Y-%m-%d %H %M", tz = "UTC"),
           by = 300)
  paste0(day, "/", format(t, "%H%M", tz = "UTC"))
}
# Put slot documents on the fake HF (one raw file per day).
.put_hf <- function(remote, ids) {
  for (d in unique(substr(ids, 1L, 10L))) {
    mine <- ids[startsWith(ids, paste0(d, "/"))]
    lines <- sprintf('{"collector":"cf-1","slot":"%s","perp_dexs_ok":true,"truncated":false,"replies":[]}', .hl_iso(mine))
    hl_drain_write_lines(lines, file.path(remote, hl_drain_hf_path("raw", d)))
  }
}
# A KV with these slots (names only: the report never reads values).
.kv <- function(ids) stats::setNames(rep(list(list(status = 200L, body = raw(0))), length(ids)), paste0("ctx/", ids))
.report <- function(kv_ids, hf_ids, days = 3L, ...) {
  remote <- withr::local_tempdir(.local_envir = parent.frame())
  .put_hf(remote, hf_ids)
  hl_gap_report(.hl_fake_client(.kv(kv_ids), remote), now = .now, days = days, ...)
}

full <- c(.slots("2026-11-21"), .slots("2026-11-22", to = "1300"))     # everything due, both days

test_that("complete coverage is a PASS, and days before collection started are not gaps", {
  r <- .report(kv_ids = full, hf_ids = full)
  expect_equal(r$status, 0L)
  expect_equal(r$table$day, c("2026-11-20", "2026-11-21", "2026-11-22"))
  expect_equal(r$table$due, c(0L, 288L, 157L))                          # 12:00 UTC day 3 = 157 slots to 13:00
  expect_equal(r$table$on_hf, c(0L, 288L, 157L))
  expect_equal(r$table$kv_not_hf, c(0L, 0L, 0L))
  expect_equal(r$table$never, c(0L, 0L, 0L))
  expect_equal(r$table$status, rep("PASS", 3L))
})

test_that("a slot in KV but not on HF is always a FAIL, however few", {
  hf <- setdiff(full, "2026-11-21/0830")
  r <- .report(kv_ids = full, hf_ids = hf)
  expect_equal(r$status, 1L)
  expect_equal(r$table$kv_not_hf, c(0L, 1L, 0L))
  expect_equal(r$table$status, c("PASS", "FAIL", "PASS"))
  # the newest slots (inside the lag) that the drain has not carried yet are not judged
  hf2 <- setdiff(full, c("2026-11-22/1300"))
  recent <- c(full, "2026-11-22/1305", "2026-11-22/1355")                # newer than now - 60 min
  r2 <- .report(kv_ids = recent, hf_ids = hf2)
  expect_equal(r2$table$kv_not_hf[3], 1L)                               # 13:00 is due and missing from HF
  r3 <- .report(kv_ids = recent, hf_ids = full)                         # only the too-new ones are missing
  expect_equal(r3$status, 0L)
})

test_that("never-collected slots fail above 2% of the day's slots and not at or below", {
  # 5 of 288 = 1.7%: PASS; 6 of 288 = 2.08%: FAIL
  gone5 <- setdiff(full, .slots("2026-11-21", "0100", "0120"))          # 5 slots out of BOTH places
  r5 <- .report(kv_ids = gone5, hf_ids = gone5)
  expect_equal(r5$table$never[2], 5L)
  expect_equal(r5$table$status[2], "PASS")
  expect_equal(r5$status, 0L)
  gone6 <- setdiff(full, .slots("2026-11-21", "0100", "0125"))
  r6 <- .report(kv_ids = gone6, hf_ids = gone6)
  expect_equal(r6$table$never[2], 6L)
  expect_equal(r6$table$never_pct[2], 2.1)
  expect_equal(r6$table$status[2], "FAIL")
  expect_equal(r6$status, 1L)
  # a slot that is only on HF (its KV copy expired) is covered
  r7 <- .report(kv_ids = setdiff(full, .slots("2026-11-21", "0000", "0300")), hf_ids = full)
  expect_equal(r7$status, 0L)
  # a day with nothing at all, after collection began, is 100% never
  late_start <- c(.slots("2026-11-20", "1200"), .slots("2026-11-22", to = "1300"))
  r8 <- .report(kv_ids = late_start, hf_ids = late_start)
  expect_equal(r8$table$never[2], 288L)                                 # the 21st: nothing
  expect_equal(r8$status, 1L)
})

test_that("the first day counts only from its first slot", {
  from_noon <- c(.slots("2026-11-21", "1200"), .slots("2026-11-22", to = "1300"))
  r <- .report(kv_ids = from_noon, hf_ids = from_noon, days = 2L)
  expect_equal(r$table$due[1], 144L)                                    # 12:00 to 23:55
  expect_equal(r$status, 0L)
})

test_that("the command line: usage 2, not configured 3, nothing anywhere 3, otherwise 0 or 1", {
  expect_equal(suppressMessages(.gap_main("--days=0")), 2L)
  expect_equal(suppressMessages(.gap_main("--nope")), 2L)
  expect_equal(suppressMessages(.gap_main(character(), env = function(v, unset) "")), 3L)
  remote <- withr::local_tempdir()
  expect_equal(suppressMessages(.gap_main(character(), client = .hl_fake_client(list(), remote), now = .now)), 3L)
  .put_hf(remote, full)
  ok <- .hl_fake_client(.kv(full), remote)
  printed <- capture.output(st <- suppressMessages(.gap_main("--days=3", client = ok, now = .now)))
  expect_equal(st, 0L)
  expect_true(any(grepl("2026-11-21", printed)))
  bad <- .hl_fake_client(.kv(c(full, "2026-11-21/0000x")), remote)          # a stray key is ignored, not a gap
  capture.output(st2 <- suppressMessages(.gap_main("--days=3", client = bad, now = .now)))
  expect_equal(st2, 0L)
  broken <- list(kv_list = function(prefix) stop("KV key list failed (HTTP 403)"))
  expect_equal(suppressMessages(.gap_main(character(), client = broken, now = .now)), 3L)
})
