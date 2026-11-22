testthat::local_edition(3)
source(here::here("scripts", "poll_hyperliquid_ctx.R"))

# scripts/poll_hyperliquid_ctx.R (#1080). NO network: the post function is
# injected. The fixture is a real metaAndAssetCtxs reply for the builder exchange
# "xyz", reduced to 3 markets (XYZ100, NVDA, and URANIUM, which has null midPx /
# impactPxs / premium as 24 of 147 real markets did). No wallet/deployer fields.

.fx_path <- here::here("tests", "testthat", "fixtures", "hyperliquid",
                       "metaandassetctxs_xyz.json")
.mac <- jsonlite::read_json(.fx_path, simplifyVector = FALSE)
.t0 <- as.POSIXct("2026-11-22 12:07:31.5", tz = "UTC")
.now <- function() .t0
.ok_post <- function(body) {
  stopifnot(identical(body$type, "metaAndAssetCtxs"), identical(body$dex, "xyz"))
  .mac
}
.poll <- function(post, out, dexes = "xyz", ...) {
  suppressMessages(hl_ctx_poll(post, out_dir = out, dexes = dexes, now = .now,
                               sleep_fn = function(s) invisible(NULL), ...))
}
.nosleep <- function(s) invisible(NULL)

test_that("parse keeps every market and the documented columns", {
  d <- hl_parse_ctx(.mac, "xyz", .t0)
  expect_equal(d$coin, c("xyz:XYZ100", "xyz:NVDA", "xyz:URANIUM"))
  expect_equal(names(d), c("dex", "coin", "fetched_at", "slot", "collector", "server_time",
                           "mid_px", "oracle_px", "mark_px", "impact_bid_px",
                           "impact_ask_px", "premium", "funding", "open_interest",
                           "day_ntl_vlm", "is_delisted"))
  expect_equal(d$mid_px[1:2], c(25664.5, 132.775))
  expect_equal(d$oracle_px[2], 132.58)
  expect_equal(d$impact_bid_px[2], 132.763)
  expect_equal(d$impact_ask_px[2], 132.78)
  expect_equal(d$premium[1], 0.0014633004)
  expect_equal(d$day_ntl_vlm[1], 149545047.8408024609)
  # the null fields of URANIUM become NA, the row is KEPT
  expect_true(all(is.na(d$mid_px[3]), is.na(d$impact_bid_px[3]),
                  is.na(d$impact_ask_px[3]), is.na(d$premium[3])))
  expect_equal(d$oracle_px[3], 85)
  # the reply carries no server time: NA, never invented
  expect_true(all(is.na(d$server_time)))
  # no wallet / deployer / margin field is persisted
  expect_false(any(grepl("deployer|wallet|margin", names(d), ignore.case = TRUE)))
})

test_that("fetched_at is the true time; slot is its 5-minute floor", {
  d <- hl_parse_ctx(.mac, "xyz", .t0)
  expect_equal(as.numeric(d$fetched_at[1]), as.numeric(.t0))
  expect_equal(d$slot[1], as.POSIXct("2026-11-22 12:05:00", tz = "UTC"))
  expect_equal(attr(d$fetched_at, "tzone"), "UTC")
  expect_equal(hl_ctx_slot(as.POSIXct("2026-11-22 12:10:00", tz = "UTC")),
               as.POSIXct("2026-11-22 12:10:00", tz = "UTC"))      # on the boundary
  expect_equal(hl_ctx_slot(as.POSIXct("2026-11-22 12:09:59.9", tz = "UTC")),
               as.POSIXct("2026-11-22 12:05:00", tz = "UTC"))
})

test_that("null and \"NaN\" become NA and are counted; other text aborts", {
  m <- .mac
  m[[2]][[1]]$premium <- "NaN"
  d <- hl_parse_ctx(m, "xyz", .t0)
  expect_true(is.na(d$premium[1]))
  expect_equal(nrow(d), 3L)                          # never dropped
  na <- hl_ctx_na_counts(d)
  expect_equal(na[["premium"]], 2L)                  # NVDA ok, XYZ100 NaN, URANIUM null
  expect_equal(na[["mid_px"]], 1L)
  # Red: "nan", "Inf" and "" are NOT accepted spellings
  for (bad in c("nan", "Inf", "")) {
    m2 <- .mac; m2[[2]][[2]]$midPx <- bad
    expect_error(hl_parse_ctx(m2, "xyz", .t0), "Non-numeric")
  }
})

test_that("shape guards: not [meta, ctxs], empty universe, length mismatch", {
  expect_error(hl_parse_ctx(list(1), "xyz", .t0), "must be")
  expect_error(hl_parse_ctx(list(list(universe = list()), list()), "xyz", .t0),
               class = "hl_empty_markets")
  expect_error(hl_parse_ctx(list(.mac[[1]], .mac[[2]][1:2]), "xyz", .t0), "differ")
})

test_that("polling twice with the same fetched_at gives one row per market", {
  out <- withr::local_tempdir()
  expect_equal(.poll(.ok_post, out)$status, 0L)
  expect_equal(.poll(.ok_post, out)$status, 0L)
  x <- hl_ctx_read(out)
  expect_equal(nrow(x), 3L)
  expect_equal(anyDuplicated(x[c("dex", "coin", "fetched_at")]), 0L)
  # Red: a later fetched_at is a NEW row (the key includes the time)
  later <- function() .t0 + 300
  suppressMessages(hl_ctx_poll(.ok_post, out_dir = out, dexes = "xyz", now = later))
  x2 <- hl_ctx_read(out)
  expect_equal(nrow(x2), 6L)
  expect_equal(length(unique(x2$slot)), 2L)
})

test_that("a failed request is status 3 and writes nothing, never 0", {
  out <- withr::local_tempdir()
  down <- function(body) hl_unavailable("connection refused")
  r <- .poll(down, out)
  expect_equal(r$status, 3L)
  expect_length(hl_ctx_files(out), 0L)
  limited <- function(body) {
    cli::cli_abort("HTTP 429", class = c("hl_rate_limited", "hl_source_unavailable"))
  }
  expect_equal(.poll(limited, out)$status, 3L)
  empty <- function(body) list(list(universe = list()), list())
  expect_equal(.poll(empty, out)$status, 3L)
  garbage <- function(body) list("x")
  expect_equal(.poll(garbage, out)$status, 3L)
  expect_length(hl_ctx_files(out), 0L)
})

test_that("main returns the exit status: 0 ok, 3 when the dependency is broken, 2 usage", {
  out <- withr::local_tempdir()
  args <- c(paste0("--out-dir=", out), paste0("--raw-dir=", file.path(out, "raw")),
            "--dexes=xyz")
  ok <- suppressMessages(.poll_hyperliquid_ctx_main(args, post_fn = .ok_post))
  expect_equal(ok, 0L)
  broken <- function(body) stop("simulated broken dependency")
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main(args, post_fn = broken, sleep_fn = .nosleep)), 3L)
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main("--bogus=1")), 2L)
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main("--pace=7")), 2L)
})

test_that("collector is a configured label, never the host name, and can be set", {
  withr::local_envvar(HL_POLL_COLLECTOR = NA)
  expect_equal(unique(hl_parse_ctx(.mac, "xyz", .t0)$collector), "laptop-1")
  withr::local_envvar(HL_POLL_COLLECTOR = "lab-7")
  expect_equal(unique(hl_parse_ctx(.mac, "xyz", .t0)$collector), "lab-7")
  withr::local_envvar(HL_POLL_COLLECTOR = "")          # empty = unset
  expect_equal(hl_ctx_collector(), "laptop-1")
  expect_false(Sys.info()[["nodename"]] %in% hl_parse_ctx(.mac, "xyz", .t0)$collector)
  expect_equal(unique(hl_parse_ctx(.mac, "xyz", .t0, collector = "pi-1")$collector), "pi-1")
  out <- withr::local_tempdir()
  suppressMessages(hl_ctx_poll(.ok_post, out_dir = out, dexes = "xyz", now = .now,
                               collector = "pi-1"))
  expect_equal(unique(hl_ctx_read(out)$collector), "pi-1")
})

test_that("fetched_at is taken AFTER the reply is received", {
  st <- new.env(); st$replied <- FALSE
  post <- function(body) { st$replied <- TRUE; .mac }
  clock <- function() {
    if (!st$replied) stop("clock read before the reply arrived")   # red if taken before
    .t0
  }
  out <- withr::local_tempdir()
  expect_equal(suppressMessages(hl_ctx_poll(post, out_dir = out, dexes = "xyz",
                                            now = clock))$status, 0L)
  # and with a retry: the clock is read once, after the SUCCESSFUL attempt
  reads <- 0L
  n <- 0L
  flaky <- function(body) { n <<- n + 1L; if (n < 2L) hl_unavailable("blip"); .mac }
  counting <- function() { reads <<- reads + 1L; .t0 }
  r <- suppressMessages(hl_ctx_poll(flaky, out_dir = withr::local_tempdir(), dexes = "xyz",
                                    now = counting, sleep_fn = function(s) invisible(NULL)))
  expect_equal(c(r$status, r$attempts, reads), c(0L, 2L, 1L))
})

test_that("non-429 errors are retried up to 3 times; 429 is not retried", {
  waits <- numeric()
  sleep <- function(s) waits <<- c(waits, s)
  calls <- 0L
  down <- function(body) { calls <<- calls + 1L; hl_unavailable("connection refused") }
  r <- suppressMessages(hl_ctx_poll(down, out_dir = withr::local_tempdir(), dexes = "xyz",
                                    now = .now, sleep_fn = sleep))
  expect_equal(c(r$status, calls, r$attempts), c(3L, 3L, 3L))
  expect_equal(waits, c(5, 10))                  # total wait 15 s: well inside ~60 s
  # fails twice, then succeeds: status 0 on the third attempt
  calls <- 0L
  flaky <- function(body) {
    calls <<- calls + 1L
    if (calls < 3L) hl_unavailable("blip")
    .mac
  }
  out <- withr::local_tempdir()
  r2 <- suppressMessages(hl_ctx_poll(flaky, out_dir = out, dexes = "xyz", now = .now,
                                     sleep_fn = sleep))
  expect_equal(c(r2$status, calls), c(0L, 3L))
  expect_length(hl_ctx_files(out), 1L)
  # Red: a rate limit is NOT retried (one call, no wait)
  calls <- 0L; waits <- numeric()
  limited <- function(body) {
    calls <<- calls + 1L
    cli::cli_abort("HTTP 429", class = c("hl_rate_limited", "hl_source_unavailable"))
  }
  r3 <- suppressMessages(hl_ctx_poll(limited, out_dir = withr::local_tempdir(), dexes = "xyz",
                                     now = .now, sleep_fn = sleep))
  expect_equal(c(r3$status, calls, length(waits)), c(3L, 1L, 0L))
})

test_that("a run over its time limit exits 3, never 0", {
  # R checks its limit at interrupt points (a blocking socket read is not one;
  # the wrapper's hard kill and the 15 s request timeout cover that), so the
  # sleep returns first and the run is then over budget.
  slow <- function(body) { Sys.sleep(2); .mac }
  out <- withr::local_tempdir()
  args <- c(paste0("--out-dir=", out), paste0("--raw-dir=", file.path(out, "raw")),
            "--dexes=xyz")
  st <- suppressMessages(.poll_hyperliquid_ctx_main(args, post_fn = slow, budget_s = 1))
  expect_equal(st, 3L)
  expect_length(hl_ctx_files(out), 0L)
  # Red: the same dependency inside the budget is fine
  fast <- function(body) .mac
  expect_equal(suppressMessages(.poll_hyperliquid_ctx_main(args, post_fn = fast, budget_s = 30)), 0L)
})

test_that("raw replies are kept append-only, one file per poll", {
  raw <- withr::local_tempdir()
  text <- paste(readLines(.fx_path, warn = FALSE), collapse = "\n")
  fake_post <- function(body, ..., on_response = NULL) {
    if (!is.null(on_response)) on_response(body, text)
    jsonlite::fromJSON(text, simplifyVector = FALSE)
  }
  post <- hl_make_post(raw, post = fake_post, sleep_fn = function(s) invisible(NULL),
                       max_attempts = 1L)
  suppressMessages(hl_ctx_poll(post, out_dir = withr::local_tempdir(), dexes = "xyz",
                               now = .now))
  suppressMessages(hl_ctx_poll(post, out_dir = withr::local_tempdir(), dexes = "xyz",
                               now = .now))
  files <- list.files(raw, recursive = TRUE)
  expect_length(files, 2L)
  expect_true(all(grepl("metaAndAssetCtxs_xyz", files)))
})
