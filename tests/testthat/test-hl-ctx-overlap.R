testthat::local_edition(3)
source(here::here("scripts", "poll_hyperliquid_ctx.R"))

# During the week the laptop poller and the Cloudflare Worker run side by side (#1088),
# the reader keeps ONE collector per (dex, coin, 5-minute slot), preferring `cf-1`.

.fx <- here::here("tests", "testthat", "fixtures", "hyperliquid", "metaandassetctxs_xyz.json")
.mac <- jsonlite::fromJSON(paste(readLines(.fx, warn = FALSE), collapse = "\n"), simplifyVector = FALSE)
.utc <- function(x) as.POSIXct(x, tz = "UTC")
.rows <- function(dex, at, collector) hl_parse_ctx(.mac, dex, .utc(at), collector)
.write <- function(out, ...) {
  suppressMessages(hl_ctx_write(dplyr::bind_rows(...), out))
}

test_that("cf-1 beats laptop-1 in a shared slot; a lone collector's rows are all kept", {
  out <- withr::local_tempdir()
  .write(out,
         .rows("xyz", "2026-11-22 12:05:01", "laptop-1"), .rows("xyz", "2026-11-22 12:05:02", "cf-1"),  # shared slot A
         .rows("xyz", "2026-11-22 12:10:01", "laptop-1"),                                                 # B: laptop only
         .rows("xyz", "2026-11-22 12:15:02", "cf-1"),                                                     # C: worker only
         .rows("xyz", "2026-11-22 12:20:01", "cf-1"), .rows("xyz", "2026-11-22 12:21:30", "cf-1"),      # D: two polls of ONE collector
         .rows("flx", "2026-11-22 12:05:01", "laptop-1"))                                                 # E: other exchange, same slot as A
  x <- hl_ctx_read(out)
  by_slot <- function(dex, slot) x[x$dex == dex & format(x$slot, "%H:%M", tz = "UTC") == slot, ]
  expect_equal(unique(by_slot("xyz", "12:05")$collector), "cf-1")
  expect_equal(nrow(by_slot("xyz", "12:05")), 3L)                       # one row per coin (3 markets), not 6
  expect_equal(unique(by_slot("xyz", "12:10")$collector), "laptop-1")
  expect_equal(unique(by_slot("xyz", "12:15")$collector), "cf-1")
  expect_equal(nrow(by_slot("xyz", "12:20")), 6L)                       # a collector's own repeats are not thinned
  expect_equal(unique(by_slot("flx", "12:05")$collector), "laptop-1")  # a different exchange is not a duplicate
  # exactly one collector per (dex, coin, slot)
  per <- tapply(x$collector, list(x$dex, x$coin, as.numeric(x$slot)), function(v) length(unique(v)))
  expect_true(all(per[!is.na(per)] == 1L))
  # the unfiltered reader still returns every row
  all_rows <- hl_ctx_read(out, one_collector_per_slot = FALSE)
  expect_equal(nrow(all_rows), nrow(x) + 3L)
  expect_equal(nrow(dplyr::collect(hl_ctx_open(out))), nrow(all_rows))   # open is the raw union
})

test_that("the preference order is cf-1, laptop-1, then other collectors alphabetically; not by file order", {
  df <- dplyr::bind_rows(.rows("xyz", "2026-11-22 12:05:01", "zzz"), .rows("xyz", "2026-11-22 12:05:02", "aaa"))
  expect_equal(unique(hl_ctx_prefer_collector(df)$collector), "aaa")
  df2 <- dplyr::bind_rows(df, .rows("xyz", "2026-11-22 12:05:03", "laptop-1"))
  expect_equal(unique(hl_ctx_prefer_collector(df2)$collector), "laptop-1")
  df3 <- dplyr::bind_rows(df2, .rows("xyz", "2026-11-22 12:05:04", "cf-1"))
  expect_equal(unique(hl_ctx_prefer_collector(df3)$collector), "cf-1")
  expect_equal(unique(hl_ctx_prefer_collector(df3[nrow(df3):1, ])$collector), "cf-1")   # row order is irrelevant
  # Red: with the preference reversed the laptop wins, so the order is what decides
  expect_equal(unique(hl_ctx_prefer_collector(df3, prefer = c("laptop-1", "cf-1"))$collector), "laptop-1")
  expect_equal(nrow(hl_ctx_prefer_collector(df3[0, ])), 0L)
})
