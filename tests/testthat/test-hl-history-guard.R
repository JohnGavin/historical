testthat::local_edition(3)
source(here::here("scripts", "hl_history_guard.R"))

# The weekly-history steps (#1088): guard, start date, pack, download. NO network: the
# Hugging Face client is a folder (helper-hl-ctx-drain.R), tables are tiny parquet files.

# ── guard ───────────────────────────────────────────────────────────
test_that("the guard passes when the new table holds every old key and more", {
  old <- withr::local_tempdir(); new <- withr::local_tempdir()
  .put_all(old); .put_all(new, c("2026-01-01", "2026-01-02", "2026-01-03"))
  g <- hl_hist_guard(old, new)
  expect_equal(g$status, 0L)
  expect_true(all(g$tbl$verdict == "PASS"))
  expect_equal(unique(g$tbl$old_rows[g$tbl$table == "perp_daily"]), 4L)
  expect_equal(g$tbl$new_rows[g$tbl$table == "perp_daily"], 6L)
})

test_that("FALSIFIED: rows lost, a key lost at equal row count, or a later earliest date each fail", {
  old <- withr::local_tempdir()
  .put(.mk_table("perp_daily", c("2026-01-01", "2026-01-02")), old, "perp_daily")
  chk <- function(new_df) {
    new <- withr::local_tempdir(); .put(new_df, new, "perp_daily")
    hl_hist_guard_one(file.path(old, "perp_daily.parquet"), file.path(new, "perp_daily.parquet"),
                      hl_hist_spec("perp_daily"))
  }
  # (a) the table was rebuilt from only the newest rows
  a <- chk(.mk_table("perp_daily", "2026-01-02"))
  expect_equal(a$verdict, "FAIL"); expect_match(a$why, "rows fell from 4 to 2")
  # (b) same row count, but 2026-01-01 BTC is gone and a new BTC row is in its place
  b_df <- .mk_table("perp_daily", c("2026-01-01", "2026-01-02"))
  b_df$date[b_df$coin == "BTC" & b_df$date == as.Date("2026-01-01")] <- as.Date("2026-01-05")
  b <- chk(b_df)
  expect_equal(b$verdict, "FAIL"); expect_equal(b$lost_keys, 1L)
  expect_match(b$why, "1 old key")
  # (c) the earliest day moved later (history cut off at the front, padded to equal count)
  c_df <- .mk_table("perp_daily", c("2026-01-02", "2026-01-03"))
  cc <- chk(c_df)
  expect_equal(cc$verdict, "FAIL"); expect_match(cc$why, "earliest date moved from 2026-01-01 to 2026-01-02")
  # (d) the control: the same table again passes
  expect_equal(chk(.mk_table("perp_daily", c("2026-01-01", "2026-01-02")))$verdict, "PASS")
})

test_that("a table missing from the new set fails; no table at all, or an unreadable one, is undecided", {
  old <- withr::local_tempdir(); new <- withr::local_tempdir()
  .put_all(old); .put_all(new, tables = setdiff(.required(), "perp_funding"))
  g <- hl_hist_guard(old, new)
  expect_equal(g$status, 1L)
  expect_equal(g$tbl$verdict[g$tbl$table == "perp_funding"], "FAIL")
  empty <- withr::local_tempdir()
  expect_equal(hl_hist_guard(empty, new)$status, 3L)        # nothing to compare is not a pass
  writeLines("not parquet", file.path(new, "perp_daily.parquet"))
  g2 <- hl_hist_guard(old, new)
  expect_equal(g2$tbl$verdict[g2$tbl$table == "perp_daily"], "UNDECIDED")
  expect_true(g2$status %in% c(1L, 3L))
})

test_that("tables whose new row replaces the old one may move their dates", {
  old <- withr::local_tempdir(); new <- withr::local_tempdir()
  .put(.mk_table("perp_dexs"), old, "perp_dexs"); .put(.mk_table("perp_dexs"), new, "perp_dexs")
  expect_equal(hl_hist_guard(old, new)$status, 0L)
  .put(.mk_table("perp_dexs")[1, ], new, "perp_dexs")     # a dex dropped
  expect_equal(hl_hist_guard(old, new)$status, 1L)
})

test_that("epoch-millisecond and ISO-string date columns are compared and reported as days", {
  old <- withr::local_tempdir(); new <- withr::local_tempdir()
  for (t in c("perp_funding", "perp_oi_snapshot")) {
    .put(.mk_table(t, "2026-01-02"), old, t)
    .put(.mk_table(t, c("2026-01-01", "2026-01-02")), new, t)
  }
  g <- hl_hist_guard(old, new)
  expect_equal(g$status, 0L)
  expect_equal(g$tbl$new_earliest, c("2026-01-01", "2026-01-01"))
})

# ── start date ──────────────────────────────────────────────────────
test_that("the start date is the oldest latest-bar date less the overlap, never before the floor", {
  d <- withr::local_tempdir()
  .put_all(d, c("2026-03-01", "2026-03-10"))
  .put(.mk_table("perp_15m", c("2026-03-01", "2026-03-07")), d, "perp_15m")   # the stale one
  expect_equal(hl_hist_start_date(d), as.Date("2026-03-04"))                 # 03-07 less 3 days
  .put(.mk_table("perp_15m", "2023-01-02"), d, "perp_15m")
  expect_equal(hl_hist_start_date(d), as.Date("2023-01-01"))                 # the floor
  unlink(file.path(d, "perp_funding.parquet"))
  expect_error(hl_hist_start_date(d), class = "hl_hist_missing")
})

# ── pack ────────────────────────────────────────────────────────────
.mk_raw <- function() {
  raw <- withr::local_tempdir(.local_envir = parent.frame())
  for (day in c("2026-11-15", "2026-11-16")) {
    dir.create(file.path(raw, day))
    for (i in 1:3) writeLines(sprintf('{"day":"%s","n":%d}', day, i), file.path(raw, day, sprintf("candle_%d.json", i)))
  }
  dir.create(file.path(raw, "ctx_poll", "2026-11-15"), recursive = TRUE)
  writeLines("poll", file.path(raw, "ctx_poll", "2026-11-15", "laptop-1_000000.json.gz"))
  raw
}

test_that("each day folder becomes one tar of gzipped members; ctx_poll is left alone", {
  raw <- .mk_raw(); out <- withr::local_tempdir()
  p <- hl_hist_pack_days(raw, out, "run42")
  expect_equal(p$day, c("2026-11-15", "2026-11-16"))
  expect_equal(p$files, c(3L, 3L))
  expect_true(all(file.exists(file.path(out, "date=2026-11-15", "run42.tar"),
                              file.path(out, "date=2026-11-16", "run42.tar"))))
  expect_false(dir.exists(file.path(out, "date=ctx_poll")))
  members <- utils::untar(file.path(out, "date=2026-11-15", "run42.tar"), list = TRUE)
  expect_equal(sort(sub("^\\./", "", members)), sprintf("candle_%d.json.gz", 1:3))
  x <- withr::local_tempdir()
  utils::untar(file.path(out, "date=2026-11-15", "run42.tar"), exdir = x)
  con <- gzfile(file.path(x, "candle_2.json.gz"), "rb")
  expect_equal(rawToChar(readBin(con, "raw", 1000)), '{"day":"2026-11-15","n":2}\n')
  close(con)
  expect_equal(hl_hist_pack_days(raw, withr::local_tempdir(), "r", skip_days = "2026-11-15")$day, "2026-11-16")
  expect_error(hl_hist_pack_days(raw, out, "../evil"), class = "hl_hist_bad_arg")
})

test_that("nothing to pack is exit 3 from the command line, never 0", {
  empty <- withr::local_tempdir(); out <- withr::local_tempdir()
  dir.create(file.path(empty, "ctx_poll"))
  expect_equal(suppressMessages(.hist_main(c("pack", paste0("--raw-dir=", empty), paste0("--out-dir=", out), "--name=x"))), 3L)
  raw <- .mk_raw()
  invisible(capture.output(r <- .hist_main(c("pack", paste0("--raw-dir=", raw), paste0("--out-dir=", out), "--name=x"))))
  expect_equal(r, 0L)
  expect_true(file.exists(file.path(out, "date=2026-11-15", "x.tar")))
})

# ── download ────────────────────────────────────────────────────────
.remote_with_seed <- function(days = c("2026-01-01", "2026-01-02"), tables = .required()) {
  remote <- withr::local_tempdir(.local_envir = parent.frame())
  root <- file.path(remote, "hyperliquid")
  .put_all(root, days, tables)
  m <- list(format = "hl-seed-v1", tables = stats::setNames(lapply(tables, function(t) {
    list(rows = nrow(.mk_table(t, days)))
  }), tables))
  jsonlite::write_json(m, file.path(root, "_seeded.json"), auto_unbox = TRUE)
  .hl_fake_client(list(), remote)
}

test_that("download returns 0 only with the marker and every expected table", {
  dir <- withr::local_tempdir()
  r <- suppressMessages(hl_hist_download(.remote_with_seed(), dir))
  expect_equal(r$status, 0L)
  expect_setequal(sub("[.]parquet$", "", list.files(dir)), .required())
})

test_that("FALSIFIED: no marker, a missing table, a truncated table or fewer rows than seeded is exit 3", {
  # no marker: the job refuses to run before the seed
  remote <- withr::local_tempdir(); .put_all(file.path(remote, "hyperliquid"))
  r1 <- hl_hist_download(.hl_fake_client(list(), remote), withr::local_tempdir())
  expect_equal(r1$status, 3L); expect_match(r1$why, "refuses to run before the owner's seed")
  # a required table absent on HF, although the marker is there
  remote2 <- withr::local_tempdir(); root2 <- file.path(remote2, "hyperliquid")
  .put_all(root2, tables = setdiff(.required(), "spot_daily"))
  writeLines('{"format":"hl-seed-v1","tables":{"perp_daily":{"rows":4}}}', file.path(root2, "_seeded.json"))
  r2 <- suppressMessages(hl_hist_download(.hl_fake_client(list(), remote2), withr::local_tempdir()))
  expect_equal(r2$status, 3L)
  expect_equal(r2$tbl$why[r2$tbl$table == "spot_daily"], "not on Hugging Face")
  # a truncated parquet
  remote3 <- withr::local_tempdir(); root3 <- file.path(remote3, "hyperliquid"); .put_all(root3)
  jsonlite::write_json(list(tables = stats::setNames(lapply(.required(), function(t) list(rows = 1L)), .required())),
                       file.path(root3, "_seeded.json"), auto_unbox = TRUE)
  f <- file.path(root3, "perp_15m.parquet"); writeBin(readBin(f, "raw", file.size(f) %/% 2), f)
  r3 <- suppressMessages(hl_hist_download(.hl_fake_client(list(), remote3), withr::local_tempdir()))
  expect_equal(r3$status, 3L); expect_match(r3$tbl$why[r3$tbl$table == "perp_15m"], "unreadable")
  # fewer rows than the marker recorded at seed
  remote4 <- withr::local_tempdir(); root4 <- file.path(remote4, "hyperliquid"); .put_all(root4)
  jsonlite::write_json(list(tables = list(perp_daily = list(rows = 999L))), file.path(root4, "_seeded.json"), auto_unbox = TRUE)
  r4 <- suppressMessages(hl_hist_download(.hl_fake_client(list(), remote4), withr::local_tempdir()))
  expect_equal(r4$status, 3L); expect_match(r4$tbl$why[r4$tbl$table == "perp_daily"], "fewer than the 999")
  # the control: an intact set passes
  expect_equal(suppressMessages(hl_hist_download(.remote_with_seed(), withr::local_tempdir()))$status, 0L)
})

test_that("a table the marker lists becomes required even if the registry calls it optional", {
  cl <- .remote_with_seed(tables = c(.required(), "perp_markets"))
  d <- withr::local_tempdir()
  expect_equal(suppressMessages(hl_hist_download(cl, d))$status, 0L)
  expect_true(file.exists(file.path(d, "perp_markets.parquet")))
  remote <- withr::local_tempdir(); root <- file.path(remote, "hyperliquid"); .put_all(root)
  writeLines('{"format":"hl-seed-v1","tables":{"perp_markets":{"rows":2}}}', file.path(root, "_seeded.json"))
  r <- suppressMessages(hl_hist_download(.hl_fake_client(list(), remote), withr::local_tempdir()))
  expect_equal(r$status, 3L)
})

# ── command line ────────────────────────────────────────────────────
test_that("a bad command line is exit 2", {
  expect_equal(suppressMessages(.hist_main(character())), 2L)
  expect_equal(suppressMessages(.hist_main("frobnicate")), 2L)
  expect_equal(suppressMessages(.hist_main(c("guard", "--old-dir=/x"))), 2L)
  expect_equal(suppressMessages(.hist_main(c("download", "--dir=/x", "--zzz=1"))), 2L)
})

test_that("the guard command prints and returns its status; start-date prints a day", {
  old <- withr::local_tempdir(); new <- withr::local_tempdir()
  .put_all(old); .put_all(new, "2026-01-02")
  args <- c("guard", paste0("--old-dir=", old), paste0("--new-dir=", new))
  shown <- suppressMessages(capture.output(r <- .hist_main(args)))
  expect_gt(length(shown), 0L)
  expect_equal(r, 1L)
  out <- capture.output(r2 <- .hist_main(c("start-date", paste0("--dir=", old))))
  expect_equal(r2, 0L)
  expect_equal(trimws(out), "2025-12-30")     # the latest bar, 2026-01-02, less 3 days
})
